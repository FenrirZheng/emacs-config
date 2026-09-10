;;; test-magit-status-overview.el --- ERT for the Magit status overview -*- lexical-binding: t; -*-

;;; Commentary:
;; Batch half of the verification for `fenrir/magit-status-overview'
;; (lisp/init-git.el).  Run from the repository root:
;;
;;     emacs -Q --batch -l shell/test-magit-status-overview.el \
;;           -f ert-run-tests-batch-and-exit
;;
;; DEPENDENCY LOADING.  `emacs -Q' loads no user configuration at all, so
;; everything this needs is loaded explicitly in the Setup section below: this
;; repository's own `elpa/' through `package-initialize', then `use-package'
;; (init-git.el is written with it), `magit', and finally the module under test.
;; The real `lisp/init-git.el' is loaded -- no function is copied here, or the
;; test would be verifying a duplicate.  Nothing is installed:
;; `use-package-always-ensure' is forced nil, so a missing package fails the run
;; instead of quietly reaching for the network.  Nothing is byte-compiled: a
;; stray `.elc' produced by a bare batch Emacs expands macros without their
;; runtime dependencies and is invisible to both `git status' and `fdfind'
;; (CLAUDE.md, "Build / test / run").
;;
;; WHAT THIS FILE CANNOT PROVE, and therefore does not claim.  Everything that
;; needs a real frame, a redisplay or a clock: TTY versus GUI rendering, the
;; window-point of a non-selected window on another frame, ellipsis appearance,
;; hint truncation at a given width, the interactive untracked prompt, timing,
;; and washer/paint/subprocess counts.  Those rows of spec R6 are
;; interactive-only and are recorded in
;; sdlc/intents/magit-status-overview/evidence/verification.md.  A green run
;; here is never a substitute for one of them.
;;
;; Every fixture is a throwaway repository created and deleted by the test
;; itself; no observed repository is read or written.

;;; Code:

;;;; Setup

(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst tmso--root
  (file-name-as-directory
   (expand-file-name
    ".." (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root, derived from this file's own location.")

(setq user-emacs-directory tmso--root
      package-user-dir (expand-file-name "elpa" tmso--root))

(require 'package)
(package-initialize)

(require 'use-package)
(setq use-package-always-ensure nil)   ; never install from a test run

;; State redirection.  The real init.el loads no-littering, which sends every
;; package's state under var/; this file loads only init-git.el, so packages
;; that create state ON LOAD would drop it in the repository root instead.
;; Forge is the one that does -- `use-package forge :after magit' fires the
;; moment magit is required, and Forge opens its database there and then.
;; These `setq's run before the packages load, and a `defcustom' does not
;; overwrite a value that is already set.
(defconst tmso--state
  (file-name-as-directory (make-temp-file "tmso-state-" t))
  "Throwaway directory for package state created during this run.")

(setq forge-database-file (expand-file-name "forge.sqlite" tmso--state)
      transient-history-file (expand-file-name "transient-history.el" tmso--state)
      transient-levels-file (expand-file-name "transient-levels.el" tmso--state)
      transient-values-file (expand-file-name "transient-values.el" tmso--state))

(add-hook 'kill-emacs-hook
          (lambda () (delete-directory tmso--state t)))

(require 'magit)
(load (expand-file-name "lisp/init-git.el" tmso--root) nil t)

;;;; Fixtures

(defvar tmso--repo nil
  "Absolute path of the throwaway repository the current test runs in.")

(defun tmso--git (&rest args)
  "Run git ARGS in `tmso--repo', erroring on a non-zero exit."
  (let ((default-directory tmso--repo))
    (unless (zerop (apply #'call-process "git" nil nil nil args))
      (error "git %s failed" (string-join args " ")))))

(defun tmso--write (path text)
  "Write TEXT to PATH inside `tmso--repo', creating directories as needed."
  (let ((full (expand-file-name path tmso--repo)))
    (make-directory (file-name-directory full) t)
    (with-temp-file full (insert text))))

(defun tmso--lines (n prefix)
  "Return N lines of filler text, each starting with PREFIX."
  (mapconcat (lambda (i) (format "%s %d" prefix i))
             (number-sequence 1 n) "\n"))

(defmacro tmso-with-repo (&rest body)
  "Run BODY inside a fresh throwaway Git repository."
  (declare (indent 0))
  `(let* ((tmso--repo (file-name-as-directory (make-temp-file "tmso-" t)))
          (default-directory tmso--repo))
     (unwind-protect
         (progn
           (tmso--git "init" "-q" "-b" "main")
           (tmso--git "config" "user.email" "test@example.invalid")
           (tmso--git "config" "user.name" "Overview Test")
           (tmso--git "config" "commit.gpgsign" "false")
           ,@body)
       (delete-directory tmso--repo t))))

(defmacro tmso-with-status (&rest body)
  "Open a status buffer on `tmso--repo' and run BODY inside it."
  (declare (indent 0))
  `(let ((buffer (save-window-excursion (magit-status-setup-buffer tmso--repo))))
     (unwind-protect
         (with-current-buffer buffer ,@body)
       (kill-buffer buffer))))

(defun tmso--seed ()
  "Commit a base tree, then leave 10 staged, 1 unstaged and 1 untracked file.
The staged set includes a 1,700-line XML file, matching the recorded
baseline that motivated the feature."
  (tmso--write "base.txt" "base\n")
  (tmso--git "add" "base.txt")
  (tmso--git "commit" "-qm" "base")
  (dotimes (i 9)
    (tmso--write (format "staged-%d.txt" i) (tmso--lines 20 "staged line")))
  (tmso--write "big.xml" (concat "<root>\n" (tmso--lines 1700 "  <node/>")
                                 "\n</root>\n"))
  (tmso--git "add" ".")
  (tmso--write "base.txt" "base\nunstaged change\n")
  (tmso--write "untracked.txt" "untracked\n"))

;;;; Helpers

(defun tmso--group (type)
  "Return the root-level status section of TYPE, or nil."
  (seq-find (lambda (section) (eq (oref section type) type))
            (and magit-root-section (oref magit-root-section children))))

(defun tmso--files (type)
  "Return the direct `file' children of the TYPE group."
  (let ((group (tmso--group type)))
    (and group
         (seq-filter (lambda (s) (eq (oref s type) 'file))
                     (oref group children)))))

(defun tmso--hidden-map ()
  "Return an alist of every section identity to its `hidden' slot."
  (let (acc)
    (cl-labels ((walk (section)
                  (push (cons (magit-section-ident section)
                              (and (oref section hidden) t))
                        acc)
                  (mapc #'walk (oref section children))))
      (walk magit-root-section))
    (nreverse acc)))

(defun tmso--index ()
  "Return the raw index listing, for before/after comparison."
  (let ((default-directory tmso--repo))
    (with-output-to-string
      (with-current-buffer standard-output
        (call-process "git" nil t nil "ls-files" "--stage")))))

(defun tmso--worktree ()
  "Return a content digest of every non-.git file in the working tree."
  (let ((default-directory tmso--repo))
    (mapconcat
     (lambda (file)
       (concat file ":"
               (with-temp-buffer
                 (insert-file-contents-literally file)
                 (secure-hash 'sha256 (current-buffer)))))
     (sort (seq-remove (lambda (f) (string-match-p "\\`\\./\\.git/" f))
                       (directory-files-recursively "." "" nil))
           #'string<)
     "\n")))

;;;; Control group -- what Magit does without this feature

(ert-deftest tmso-native-fresh-defaults ()
  "A fresh status buffer shows the diff groups and hides only untracked.
This is the control the overview is measured against: any test that would
also pass against stock Magit is not evidence."
  (tmso-with-repo
    (tmso--seed)
    (tmso-with-status
      (should-not (oref (tmso--group 'staged) hidden))
      (should-not (oref (tmso--group 'unstaged) hidden))
      (should (oref (tmso--group 'untracked) hidden))
      ;; Tracked file bodies are hidden in status mode, headings are not.
      (should (= 10 (length (tmso--files 'staged))))
      (should (seq-every-p (lambda (s) (oref s hidden)) (tmso--files 'staged)))
      ;; A hidden group has no children at all until its washer runs.
      (should-not (oref (tmso--group 'untracked) children)))))

;;;; The command

(ert-deftest tmso-user-error-outside-status ()
  "Outside a status buffer the command errors and changes nothing."
  (with-temp-buffer
    (let ((before (buffer-string)))
      (should-error (fenrir/magit-status-overview) :type 'user-error)
      (should (equal before (buffer-string))))))

(ert-deftest tmso-overview-from-fully-folded ()
  "Folding all three groups by hand, the overview brings the filenames back."
  (tmso-with-repo
    (tmso--seed)
    (tmso-with-status
      ;; Hand-fold everything, and leave one tracked body expanded, so a
      ;; no-op implementation and a parents-only one both fail.
      (magit-section-show (tmso--group 'staged))
      (magit-section-show (car (tmso--files 'staged)))
      (dolist (type '(staged unstaged untracked))
        (magit-section-hide (tmso--group type)))
      (fenrir/magit-status-overview)
      (dolist (type '(staged unstaged untracked))
        (should-not (oref (tmso--group type) hidden)))
      ;; File headings visible, file bodies collapsed.
      (should (seq-every-p (lambda (s) (oref s hidden)) (tmso--files 'staged)))
      (should (seq-every-p (lambda (s) (oref s hidden)) (tmso--files 'unstaged)))
      (should (seq-every-p (lambda (s) (not (invisible-p (oref s start))))
                           (tmso--files 'staged)))
      ;; Untracked was materialised by the expansion.
      (should (= 1 (length (tmso--files 'untracked)))))))

(ert-deftest tmso-overview-is-idempotent ()
  "Running the overview twice leaves an identical visibility map."
  (tmso-with-repo
    (tmso--seed)
    (tmso-with-status
      (fenrir/magit-status-overview)
      (let ((once (tmso--hidden-map)))
        (fenrir/magit-status-overview)
        (should (equal once (tmso--hidden-map)))))))

(ert-deftest tmso-overview-survives-refresh ()
  "A plain refresh keeps the overview rather than reopening the diffs."
  (tmso-with-repo
    (tmso--seed)
    (tmso-with-status
      (fenrir/magit-status-overview)
      (let ((before (tmso--hidden-map)))
        (magit-refresh-buffer)
        (should (equal before (tmso--hidden-map)))))))

(ert-deftest tmso-overview-leaves-other-sections-alone ()
  "Sections outside the three change groups keep their visibility."
  (tmso-with-repo
    (tmso--seed)
    (tmso--git "stash" "push" "-q" "-u" "-m" "stashed")
    (tmso--write "again.txt" "again\n")
    (tmso--git "add" "again.txt")
    (tmso-with-status
      (let* ((stashes (tmso--group 'stashes))
             (before (and stashes (oref stashes hidden))))
        (should stashes)
        (fenrir/magit-status-overview)
        (should (eq before (oref (tmso--group 'stashes) hidden)))))))

(ert-deftest tmso-overview-safe-when-nothing-to-do ()
  "A clean tree, and each single-group tree, are safe no-ops."
  (tmso-with-repo
    (tmso--write "base.txt" "base\n")
    (tmso--git "add" "base.txt")
    (tmso--git "commit" "-qm" "base")
    (tmso-with-status
      (should-not (tmso--group 'staged))
      (fenrir/magit-status-overview)))          ; must not error
  (tmso-with-repo
    (tmso--write "base.txt" "base\n")
    (tmso--git "add" "base.txt")
    (tmso--git "commit" "-qm" "base")
    (tmso--write "only-untracked.txt" "x\n")
    (tmso-with-status
      (fenrir/magit-status-overview)
      (should-not (oref (tmso--group 'untracked) hidden)))))

;;;; Native semantics the overview must not damage

(ert-deftest tmso-partial-stage-stays-two-entries ()
  "A file both staged and unstaged keeps one entry in each group."
  (tmso-with-repo
    (tmso--write "both.txt" "one\n")
    (tmso--git "add" "both.txt")
    (tmso--git "commit" "-qm" "base")
    (tmso--write "both.txt" "one\ntwo\n")
    (tmso--git "add" "both.txt")
    (tmso--write "both.txt" "one\ntwo\nthree\n")
    (tmso-with-status
      (fenrir/magit-status-overview)
      (should (= 1 (length (tmso--files 'staged))))
      (should (= 1 (length (tmso--files 'unstaged)))))))

(ert-deftest tmso-rename-and-binary-survive ()
  "Rename and binary sections keep their native representation."
  (tmso-with-repo
    (tmso--write "old-name.txt" (tmso--lines 40 "content"))
    (tmso--write "blob.bin" "\0\1\2\3binary\0\0")
    (tmso--git "add" ".")
    (tmso--git "commit" "-qm" "base")
    (tmso--git "mv" "old-name.txt" "new-name.txt")
    (tmso--write "blob.bin" "\0\1\2\3changed\0\0\7")
    (tmso--git "add" ".")
    (tmso-with-status
      (fenrir/magit-status-overview)
      (let ((names (mapcar (lambda (s) (oref s value)) (tmso--files 'staged))))
        (should (member "new-name.txt" names))
        (should (member "blob.bin" names))))))

(ert-deftest tmso-untracked-truncation-notice-kept ()
  "Over the list limit, the native \"not listed\" notice survives the overview."
  (tmso-with-repo
    (tmso--write "base.txt" "base\n")
    (tmso--git "add" "base.txt")
    (tmso--git "commit" "-qm" "base")
    (dotimes (i (+ magit-status-file-list-limit 20))
      (tmso--write (format "u-%03d.txt" i) "x\n"))
    (tmso-with-status
      (fenrir/magit-status-overview)
      (let ((group (tmso--group 'untracked)))
        (should-not (oref group hidden))
        ;; Exactly the limit is listed, and the overflow notice is present.
        (should (= magit-status-file-list-limit (length (tmso--files 'untracked))))
        (should (seq-find (lambda (s) (eq (oref s type) 'info))
                          (oref group children)))))))

(ert-deftest tmso-staged-list-not-capped-by-file-list-limit ()
  "`magit-status-file-list-limit' caps file LISTS, never the staged diff."
  (tmso-with-repo
    (tmso--write "base.txt" "base\n")
    (tmso--git "add" "base.txt")
    (tmso--git "commit" "-qm" "base")
    (dotimes (i (+ magit-status-file-list-limit 10))
      (tmso--write (format "s-%03d.txt" i) "x\n"))
    (tmso--git "add" ".")
    (tmso-with-status
      (fenrir/magit-status-overview)
      (should (= (+ magit-status-file-list-limit 10)
                 (length (tmso--files 'staged)))))))

;;;; The command touches no Git state

(ert-deftest tmso-overview-does-not-touch-index-or-worktree ()
  "The overview leaves the raw index and every working-tree file byte-identical."
  (tmso-with-repo
    (tmso--seed)
    (tmso-with-status
      (let ((index (tmso--index))
            (tree (tmso--worktree)))
        (fenrir/magit-status-overview)
        (fenrir/magit-status-overview)
        (should (equal index (tmso--index)))
        (should (equal tree (tmso--worktree)))))))

;;;; Entry point

(defun tmso--jump-columns ()
  "Return the column groups of `magit-status-jump'.
The layout root is [VERSION nil (GROUPS)] and its single group is the
`transient-columns' wrapper, whose own element 2 holds the columns -- so
`length' on the root would be 3 no matter how many columns exist."
  (aref (car (aref (transient--get-layout 'magit-status-jump) 2)) 2))

(ert-deftest tmso-transient-entry-present-and-idempotent ()
  "`o' in `magit-status-jump' runs the overview, and reinstalling is a no-op."
  (should (eq (fenrir/magit-status-overview--suffix-command
               (transient-get-suffix 'magit-status-jump "o"))
              'fenrir/magit-status-overview))
  ;; Reloading the module re-runs the installer; it must not append a second
  ;; column -- the failure mode of the difftastic precedent in init-git.el.
  ;; Any warning it emits would be a false conflict report, so those are fatal.
  (let ((before (length (tmso--jump-columns)))
        (warned nil))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (&rest args) (setq warned args))))
      (fenrir/magit-status-overview--install-entry)
      (fenrir/magit-status-overview--install-entry))
    (should-not warned)
    (should (= before (length (tmso--jump-columns))))
    (should (= 1 (seq-count (lambda (column)
                              (equal "View" (plist-get (aref column 1) :description)))
                            (tmso--jump-columns))))
    (should (eq (fenrir/magit-status-overview--suffix-command
                 (transient-get-suffix 'magit-status-jump "o"))
                'fenrir/magit-status-overview))))

(ert-deftest tmso-transient-entry-yields-to-a-conflict ()
  "When something else owns `o', the native action stays and M-x is advertised."
  ;; The layout lives in a symbol property whose list structure the edit
  ;; functions mutate in place, so isolate the fixture with a deep copy.
  (let ((saved (copy-tree (get 'magit-status-jump 'transient--layout) t))
        (fenrir/magit-status-overview--entry-warned nil)
        (warned nil))
    (unwind-protect
        (progn
          ;; Give `o' away, then ask the installer to place its own entry.
          (transient-remove-suffix 'magit-status-jump "o")
          (transient-append-suffix 'magit-status-jump '(0 2)
            ["Fixture" ("o" "Occupied" ignore)])
          (cl-letf (((symbol-function 'display-warning)
                     (lambda (&rest args) (setq warned args))))
            (fenrir/magit-status-overview--install-entry))
          (should warned)
          (should (string-match-p "M-x fenrir/magit-status-overview"
                                  (nth 1 warned)))
          (should (eq (fenrir/magit-status-overview--suffix-command
                       (transient-get-suffix 'magit-status-jump "o"))
                      'ignore)))
      (put 'magit-status-jump 'transient--layout saved))))

;;;; Threshold arithmetic (the prompt itself is interactive-only)

(ert-deftest tmso-child-count-read-without-git ()
  "The untracked count is read off the heading, and is the pre-truncation total."
  (tmso-with-repo
    (tmso--write "base.txt" "base\n")
    (tmso--git "add" "base.txt")
    (tmso--git "commit" "-qm" "base")
    (dotimes (i (+ magit-status-file-list-limit 20))
      (tmso--write (format "u-%03d.txt" i) "x\n"))
    (tmso-with-status
      (should (= (+ magit-status-file-list-limit 20)
                 (fenrir/magit-status-overview--child-count
                  (tmso--group 'untracked)))))))

(ert-deftest tmso-threshold-follows-magit-limit-by-default ()
  "A nil threshold means `magit-status-file-list-limit'."
  (let ((fenrir/magit-status-overview-untracked-threshold nil))
    (should (= magit-status-file-list-limit
               (fenrir/magit-status-overview--threshold))))
  (let ((fenrir/magit-status-overview-untracked-threshold 7))
    (should (= 7 (fenrir/magit-status-overview--threshold)))))

(provide 'test-magit-status-overview)
;;; test-magit-status-overview.el ends here
