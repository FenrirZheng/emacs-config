;;; question-queue.el --- Ask a file-queue about a region, get the answer back -*- lexical-binding: t; -*-

;; Author: fenrir
;; Keywords: tools, convenience

;;; Commentary:
;;
;; Close the loop with an external file-based question queue from inside Emacs.
;;
;; A background monitor watches `<question-queue-dir>/input/'; for every file
;; that lands there it emits `NEW_QUESTION: <name>', an answerer writes the
;; reply to `<question-queue-dir>/output/<name>' (identical basename).  This
;; package:
;;
;;   1. Captures the highlighted region + a typed question.
;;   2. Hands them to the `question-queue-core' Rust dynamic module, which
;;      assembles a markdown document and ATOMICALLY drops it into `input/'
;;      (temp + rename => the monitor's `moved_to' fires on a complete file).
;;   3. Watches `output/' via `file-notify' (inotify) and, when the matching
;;      answer file appears, simply opens that output file in a buffer (a bottom
;;      side window).  The source buffer is never modified.
;;
;; Entry point: `M-x question-queue-ask' (bound to `C-c q q' in init-ai.el).
;; The native half is built once with `M-x question-queue-build' (or
;; `make -C rust/question-queue-core'); a fresh clone falls back to a helpful
;; error until then.  The split (native = compute + atomic file I/O, elisp =
;; region/prompt/watch/display) mirrors junit-runner.el + cpp/junit-core.

;;; Code:

(require 'filenotify)
(require 'compile)
(require 'subr-x)

(defgroup question-queue nil
  "Ask an external file-queue about a buffer region and get the answer back."
  :group 'tools
  :prefix "question-queue-")

(defcustom question-queue-dir nil
  "Optional persistent root of the external question queue, or nil.

There is deliberately NO built-in default directory -- the user must supply
one, either by customizing this variable or (the usual path) by letting the
first `question-queue-ask' of a session prompt for it, which is then remembered
and changeable via `question-queue-set-dir' (\\[question-queue-set-dir]).  When
neither this variable nor a session choice is set, `question-queue-ask' refuses
to run and tells you to pick a directory.

Requests go to the `input/' subdir; answers are read from `output/'."
  :type '(choice (const :tag "Unset -- ask on first use" nil) directory))

(defcustom question-queue-module
  (expand-file-name "rust/lib/question-queue-core.so" user-emacs-directory)
  "Absolute path to the built `question-queue-core' dynamic module.
Produced by `make -C rust/question-queue-core' into the workspace `rust/lib/'."
  :type 'file)

(defcustom question-queue-timeout 300
  "Seconds to wait for an answer file before giving up on a request."
  :type 'number)

(defcustom question-queue-delete-on-read nil
  "When non-nil, delete the `input/' request file once its answer is opened.
The `output/' answer file is left in place -- it is the buffer's visited file."
  :type 'boolean)

;; ---------------------------------------------------------------------------
;; State
;; ---------------------------------------------------------------------------

(defvar question-queue--pending (make-hash-table :test 'equal)
  "Map answer basename -> plist (:question :source :timer :time :input-dir
:output-dir).  An entry exists from submit until the answer is delivered or it
times out.  Each entry carries the directories it was submitted against, so a
request keeps resolving to its original queue even if the active dir changes.")

(defvar question-queue--watches (make-hash-table :test 'equal)
  "Map `output/' directory -> its `file-notify' descriptor.
Keyed by directory so several queues (or a changed directory with a request
still in flight) can be watched concurrently.")

(defvar question-queue--active-dir nil
  "The queue root chosen for this session, or nil until first picked.
Set by `question-queue-set-dir'; seeded interactively from `question-queue-dir'.")

(defun question-queue--root ()
  "The queue root to use now: the session's active dir, else `question-queue-dir'.
Signals a `user-error' when neither is set -- the user must provide a directory."
  (let ((dir (or question-queue--active-dir question-queue-dir)))
    (unless dir
      (user-error
       "No question-queue directory set -- run M-x question-queue-set-dir (C-c q d)"))
    (file-name-as-directory (expand-file-name dir))))

(defun question-queue--input-dir (&optional root)
  "Absolute `input/' directory under ROOT (default `question-queue--root')."
  (file-name-as-directory (expand-file-name "input" (or root (question-queue--root)))))

(defun question-queue--output-dir (&optional root)
  "Absolute `output/' directory under ROOT (default `question-queue--root')."
  (file-name-as-directory (expand-file-name "output" (or root (question-queue--root)))))

;;;###autoload
(defun question-queue-set-dir (dir)
  "Set the active question-queue root to DIR for this and future requests.
Pending requests already submitted keep watching their original directory."
  (interactive
   (list (read-directory-name
          "Question-queue directory: "
          ;; Seed with the current choice if any; nil falls back to
          ;; `default-directory' (there is no built-in default).
          (let ((seed (or question-queue--active-dir question-queue-dir)))
            (and seed (file-name-as-directory (expand-file-name seed)))))))
  (setq question-queue--active-dir (file-name-as-directory (expand-file-name dir)))
  (message "question-queue: directory set to %s" question-queue--active-dir)
  question-queue--active-dir)

(defun question-queue--ensure-dir ()
  "Return the active queue root, prompting for it on first use this session."
  (unless question-queue--active-dir
    (call-interactively #'question-queue-set-dir))
  question-queue--active-dir)

;; ---------------------------------------------------------------------------
;; Module loading / building (mirrors junit-runner.el)
;; ---------------------------------------------------------------------------

(defun question-queue--loaded-p ()
  "Non-nil when the question-queue-core submit function is available."
  (fboundp 'qq-core-submit))

(defun question-queue--ensure-module ()
  "Load the module, signalling an actionable error if it is not built."
  (unless (question-queue--loaded-p)
    (unless (and module-file-suffix (file-exists-p question-queue-module))
      (user-error
       "question-queue-core not built: %s -- run M-x question-queue-build"
       question-queue-module))
    (module-load question-queue-module)
    (unless (question-queue--loaded-p)
      (error "Loaded %s but qq-core functions are missing" question-queue-module))))

(defun question-queue-build ()
  "Build the question-queue-core module via make, then load it on success."
  (interactive)
  (let* ((dir (expand-file-name "rust/question-queue-core" user-emacs-directory))
         (default-directory dir))
    (unless (file-directory-p dir)
      (user-error "Module source dir not found: %s" dir))
    (let ((buf (compilation-start "make"
                                  nil
                                  (lambda (&rest _) "*question-queue build*"))))
      (with-current-buffer buf
        (add-hook 'compilation-finish-functions
                  #'question-queue--after-build nil t)))))

(defun question-queue--after-build (buffer status)
  "Load the freshly built module when BUFFER's build STATUS is success."
  (when (and (buffer-live-p buffer)
             (string-prefix-p "finished" status)
             (file-exists-p question-queue-module))
    (unless (question-queue--loaded-p)
      (condition-case err
          (progn (module-load question-queue-module)
                 (message "question-queue-core module loaded"))
        (error (message "question-queue-core built but load failed: %s"
                        (error-message-string err)))))))

;; ---------------------------------------------------------------------------
;; The output/ watch
;; ---------------------------------------------------------------------------

(defun question-queue--ensure-watch (output-dir)
  "Make sure a `file-notify' watch on OUTPUT-DIR is live (one per directory)."
  (let ((d (gethash output-dir question-queue--watches)))
    (unless (and d (file-notify-valid-p d))
      (make-directory output-dir t)
      (puthash output-dir
               (file-notify-add-watch
                output-dir '(change)
                ;; Capture the dir so the callback knows which queue fired.
                (lambda (event) (question-queue--on-event event output-dir)))
               question-queue--watches))))

(defun question-queue--stop-watch-if-idle (output-dir)
  "Drop OUTPUT-DIR's watch once no pending request still targets it."
  (let ((still-used nil))
    (maphash (lambda (_name entry)
               (when (equal (plist-get entry :output-dir) output-dir)
                 (setq still-used t)))
             question-queue--pending)
    (unless still-used
      (when-let ((d (gethash output-dir question-queue--watches)))
        (ignore-errors (file-notify-rm-watch d))
        (remhash output-dir question-queue--watches)))))

(defun question-queue--on-event (event _output-dir)
  "Dispatch a `file-notify' EVENT to a pending request by basename.
EVENT is (DESCRIPTOR ACTION FILE [FILE1]); for `renamed' the new path is FILE1.
The pending entry carries its own output dir, so basename is enough to route."
  (pcase-let ((`(,_desc ,action ,file . ,rest) event))
    (when (memq action '(created changed renamed attribute-changed))
      (let* ((cand (if (eq action 'renamed) (car rest) file))
             (name (and cand (file-name-nondirectory cand))))
        (when (and name (gethash name question-queue--pending))
          (question-queue--maybe-deliver name))))))

(defun question-queue--maybe-deliver (name)
  "Deliver the answer for NAME if its output file is present and non-empty."
  (when-let ((entry (gethash name question-queue--pending)))
    (let ((path (expand-file-name name (plist-get entry :output-dir))))
      (when (and (file-readable-p path)
                 (> (or (file-attribute-size (file-attributes path)) 0) 0))
        (question-queue--deliver name path entry)))))

(defun question-queue--deliver (name path entry)
  "Open answer file PATH for request NAME (ENTRY) in a buffer; clear the request."
  (remhash name question-queue--pending)
  (when (timerp (plist-get entry :timer))
    (cancel-timer (plist-get entry :timer)))
  ;; The output file is self-contained markdown -- just read it into a buffer.
  (let ((buf (find-file-noselect path)))
    (with-current-buffer buf
      ;; If this path was visited before and the answer was rewritten, refresh.
      (unless (verify-visited-file-modtime buf)
        (revert-buffer :ignore-auto :noconfirm)))
    (display-buffer
     buf '(display-buffer-in-side-window (side . bottom) (window-height . 0.4))))
  (when question-queue-delete-on-read
    (ignore-errors
      (delete-file (expand-file-name name (plist-get entry :input-dir)))))
  (message "question-queue: answer ready -- %s" name)
  (question-queue--stop-watch-if-idle (plist-get entry :output-dir)))

(defun question-queue--on-timeout (name)
  "Give up on request NAME after `question-queue-timeout' seconds."
  (when-let ((entry (gethash name question-queue--pending)))
    (remhash name question-queue--pending)
    (question-queue--stop-watch-if-idle (plist-get entry :output-dir))
    (message "question-queue: no answer for %s after %ds"
             name question-queue-timeout)))

;; ---------------------------------------------------------------------------
;; Helpers + entry point
;; ---------------------------------------------------------------------------

(defun question-queue--lang ()
  "Derive a fenced-code language tag from the current buffer's major mode.
E.g. `rust-ts-mode' -> \"rust\", `python-mode' -> \"python\"."
  (let ((name (replace-regexp-in-string
               "-ts-mode\\'" ""
               (replace-regexp-in-string "-mode\\'" "" (symbol-name major-mode)))))
    (if (string-empty-p name) "text" name)))

;;;###autoload
(defun question-queue-ask (region question)
  "Ship QUESTION (optionally with the highlighted REGION) to the queue.
Interactively, prompts for the question; if a region is active it is sent as
code context, otherwise the request is question-only (no highlight needed).
Writes a markdown request into `<root>/input/' (via the native module) and
watches `<root>/output/' for the reply, which lands in the `*question-queue*'
buffer.  Non-blocking: keep editing while you wait.

The queue root is picked on the first call of the session (defaulting to
`question-queue-dir') and remembered.  Change it with `question-queue-set-dir'
or by calling this command with a prefix arg (\\[universal-argument])."
  (interactive
   (progn
     ;; A prefix arg re-picks the directory before asking.
     (when current-prefix-arg
       (call-interactively #'question-queue-set-dir))
     ;; Resolve the queue root (prompts on first use) before the question, so
     ;; the directory prompt never appears mid-flow after typing the question.
     (question-queue--ensure-dir)
     ;; Region is optional: send it as context when active, else question-only.
     (list (when (use-region-p)
             (buffer-substring-no-properties (region-beginning) (region-end)))
           (read-string "Question: "))))
  (when (string-empty-p (string-trim question))
    (user-error "Empty question"))
  (question-queue--ensure-module)
  (let* ((root (question-queue--root))
         (input-dir (question-queue--input-dir root))
         (output-dir (question-queue--output-dir root))
         (lang (question-queue--lang))
         (source (or (buffer-file-name) (buffer-name)))
         (name (qq-core-submit region question lang source input-dir)))
    (unless (and (stringp name)
                 (file-exists-p (expand-file-name name input-dir)))
      (error "question-queue: submit did not produce a file (%S)" name))
    (question-queue--ensure-watch output-dir)
    (let ((timer (run-with-timer question-queue-timeout nil
                                 #'question-queue--on-timeout name)))
      (puthash name (list :question question :source source
                          :timer timer :time (current-time)
                          :input-dir input-dir :output-dir output-dir)
               question-queue--pending))
    ;; Race guard: a very fast answerer could write output/ before the watch
    ;; registered; check once immediately.
    (question-queue--maybe-deliver name)
    (message "question-queue: queued %s in %s -- waiting for answer..."
             name root)))

(provide 'question-queue)
;;; question-queue.el ends here
