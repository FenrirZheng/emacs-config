;;; claude-open.el --- Open files mentioned in Claude Code sessions -*- lexical-binding: t; -*-

;; Version: 2
;; Distributed by the Claude Code `emacs-open' skill (references/claude-open.el
;; is the distribution source; this installed copy is the runtime truth).
;; Sync direction on version mismatch is a user decision — never auto-overwrite.

;;; Commentary:
;; Entry points:
;;   `claude-open'           — open a list of (FILE LINE COL) specs.
;;   `claude-open-from-file' — same, specs read from a TSV file (the only
;;                             dispatch shape the skill uses; keeps hostile
;;                             filenames out of elisp read syntax).
;;   `claude-open-goto-last' — jump to the most recent opened location;
;;                             repeated calls cycle backward through the ring.
;;   `claude-open-setup-keys'— optional keybinding helper (shipped, not called).
;;
;; Design invariants:
;; - No code path may reach an interactive prompt — evals from emacsclient -e
;;   have no answerable home and would wedge the daemon.
;; - The return value is ALWAYS one plist per spec, containing only readable
;;   primitives (strings/numbers/symbols) — it crosses emacsclient's print
;;   boundary and is parsed by the calling LLM.
;; - No plist-put on shared structure: flags are freshly consed, reports are
;;   extended with `append' — nothing mutates, nothing leaks across calls.

;;; Code:

(require 'pulse)
(require 'ring)
(require 'seq)

(defgroup claude-open nil
  "Open files mentioned in Claude Code sessions."
  :group 'convenience)

(defcustom claude-open-create-gui-frames t
  "When non-nil, `claude-open' may create a GUI frame if none exists.
Set to nil if you deliberately work TTY-only and don't want Claude
resurrecting a GUI window you closed — cold displays then degrade to
the TTY frame (an EXISTING GUI frame is still preferred either way)."
  :type 'boolean)

(defconst claude-open-version 2
  "Version of the installed claude-open helper.
The emacs-open skill probes this to detect drift against its
distribution copy (and shadowing by unrelated `claude-open' definitions).")

(defvar claude-open-ring (make-ring 20)
  "Recent locations opened via `claude-open'.
Entries are (MARKER . PLIST).  Dead markers (killed buffers) are skipped.
The PLIST is a snapshot taken at visit time; keys appended to the returned
report afterwards (:displayed, :no-frame) do not propagate into it.")

(defvar claude-open--ring-index 0
  "Cycle position for `claude-open-goto-last'.")

(defun claude-open--frames (kind)
  "Frames of KIND (symbol `gui' or `tty'), most-recently-used first.
MRU is decided by `window-use-time' of each frame's selected window
(the same counter `get-mru-window' uses).  The daemon's invisible F1
frame reads (display-graphic-p nil, tty nil) — it matches neither class."
  (sort (seq-filter (lambda (f)
                      (pcase kind
                        ('gui (display-graphic-p f))
                        ('tty (frame-parameter f 'tty))))
                    (frame-list))
        (lambda (a b) (> (window-use-time (frame-selected-window a))
                         (window-use-time (frame-selected-window b))))))

(defun claude-open--frame ()
  "Preferred visible frame: GUI beats TTY (class beats recency), MRU within."
  (or (car (claude-open--frames 'gui))
      (car (claude-open--frames 'tty))))

(defun claude-open--ensure-frame (display)
  "Return (FRAME . FLAGS), creating a GUI frame lazily when useful.
Preference: existing GUI frame > create GUI frame > existing TTY frame —
create outranks TTY reuse because the user prefers the GUI window
(disable creation with `claude-open-create-gui-frames' nil).
DISPLAY-arg contract: a non-nil DISPLAY (the CLIENT's $DISPLAY at
invocation) takes precedence over the daemon's (getenv \"DISPLAY\"),
which can go stale across graphical-session restarts.  A DISPLAY that
fails degrades to the TTY frame (or no frame) and NEVER retries with
the daemon env — predictability over cleverness.
FLAGS reports :created-frame / :frame-create-failed."
  (let ((gui (car (claude-open--frames 'gui))))
    (if gui
        (cons gui nil)
      (let ((disp (and claude-open-create-gui-frames
                       (or display (getenv "DISPLAY")))))
        (if disp
            (condition-case nil
                (cons (make-frame-on-display disp)
                      (list :created-frame 'gui))
              (error (cons (car (claude-open--frames 'tty))
                           (list :frame-create-failed t))))
          (cons (car (claude-open--frames 'tty)) nil))))))

(defun claude-open--target (line col)
  "Absolute position for LINE/COL (1-based) in the current buffer.
Computed ignoring any narrowing; does not move point."
  (save-restriction
    (widen)
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (when (and col (> col 0))
        (move-to-column (1- col)))
      (point))))

(defun claude-open--jump (pos)
  "Move point to POS, widening only when narrowing hides POS.
When POS is already accessible, existing narrowing is left alone."
  (unless (<= (point-min) pos (point-max))
    (widen))
  (goto-char pos))

(defun claude-open--visit (file quiet)
  "Visit FILE per the never-prompt rules.
Return (BUFFER . FLAGS) where FLAGS is a freshly consed plist,
or (nil . (:error MSG))."
  (cond
   ;; Catches tab-mangled spec lines, empty path fields, and any future
   ;; caller bug — a relative path would resolve against the DAEMON's
   ;; default-directory, not the client's cwd.
   ((not (and (stringp file) (file-name-absolute-p file)))
    (cons nil (list :error "non-absolute path")))
   ((file-remote-p file)
    (cons nil (list :error "remote path — open manually")))
   ((file-directory-p file)
    (cons (dired-noselect file) (list :dired t)))
   ((not (file-exists-p file))
    (if quiet
        (cons nil (list :error "no such file (quiet mode refuses new files)"))
      (cons (let ((enable-local-variables :safe))
              (find-file-noselect file t))
            (list :new-file t))))
   ((let ((size (file-attribute-size (file-attributes file))))
      (and large-file-warning-threshold size
           (> size large-file-warning-threshold)))
    (cons nil (list :error "file exceeds large-file-warning-threshold")))
   (t
    (let* ((existing (find-buffer-visiting file))
           (buf (or existing
                    (let ((enable-local-variables :safe))
                      (find-file-noselect file t))))
           (flags (and existing (list :already-open t))))
      ;; Claude's Edit tool rewrites files under live buffers constantly;
      ;; refresh unmodified stale buffers, flag real conflicts, never prompt.
      (when existing
        (let ((stale (not (verify-visited-file-modtime buf)))
              (dirty (buffer-modified-p buf)))
          (cond
           ((and stale dirty)
            (setq flags (append flags (list :conflict t))))
           (stale
            (with-current-buffer buf
              (revert-buffer :ignore-auto :noconfirm))
            (setq flags (append flags (list :reverted t))))
           (dirty
            (setq flags (append flags (list :modified t)))))))
      (cons buf flags)))))

(defun claude-open (specs &optional quiet display)
  "Open SPECS, a list of (FILE &optional LINE COL); FILE absolute, 1-based pos.
Display policy: the first SUCCESSFULLY VISITED spec is displayed in the
preferred frame (GUI beats TTY; a GUI frame is created lazily when none
exists and DISPLAY — client's $DISPLAY, falling back to the daemon env —
resolves).  The rest are loaded only.  QUIET non-nil loads without touching
any window, point, or frame (quiet can never create frames).  Every
successfully visited spec gets a `claude-open-ring' entry.  A spec that
signals an error yields an :error plist and never aborts the rest of the
batch.  Return a list of plists, one per spec, in order."
  (let ((frame-info nil)             ; lazily filled (FRAME . FLAGS)
        (display-slot (not quiet))
        results)
    (dolist (spec specs)
      (pcase-let ((`(,file ,line ,col) spec))
        (push
         (condition-case-unless-debug err
             (pcase-let* ((`(,buf . ,flags) (claude-open--visit file quiet))
                          (report (append (list :file file :line line :col col)
                                          flags)))
               (when buf
                 (setq report (append report
                                      (list :buffer (buffer-name buf))))
                 ;; Ring entry for every visited spec (display or quiet).
                 (with-current-buffer buf
                   (ring-insert claude-open-ring
                                (cons (if line
                                          (copy-marker
                                           (claude-open--target line col))
                                        (point-marker))
                                      report)))
                 (when display-slot
                   ;; Lazy: the frame is ensured (and possibly created) only
                   ;; once a displayable buffer exists — an all-error batch
                   ;; never creates a frame.
                   (unless frame-info
                     (setq frame-info (claude-open--ensure-frame display)))
                   (let ((frame (car frame-info)))
                     (if frame
                         (progn
                           (with-selected-frame frame
                             (pop-to-buffer-same-window buf)
                             ;; Raise BEFORE the pulse so the user's eyes are
                             ;; on the frame while it animates.  GUI only
                             ;; (buried "success" repeats the F1 invisibility
                             ;; class); :raised means raise-frame was CALLED,
                             ;; not "window now visible" (mutter may demote it
                             ;; to a taskbar ping).  Never x-focus-frame — no
                             ;; keyboard-focus theft.
                             (when (display-graphic-p frame)
                               (raise-frame frame)
                               (setq report (append report (list :raised t))))
                             (when line
                               (claude-open--jump
                                (claude-open--target line col))
                               (recenter)
                               (pulse-momentary-highlight-one-line (point))))
                           (setq report (append report (list :displayed t)
                                                (cdr frame-info))))
                       ;; No frame obtainable: loaded + ring'd, honest report.
                       (setq report (append report (list :no-frame t)
                                            (cdr frame-info)))))
                   (setq display-slot nil)))
               report)
           (error (list :file file :error (error-message-string err))))
         results)))
    (setq claude-open--ring-index 0)
    (nreverse results)))

(defun claude-open-from-file (spec-file &optional quiet display)
  "Open specs read from SPEC-FILE: one `PATH<TAB>LINE<TAB>COL' per line.
LINE/COL may be empty.  Parsed with `split-string' only — file contents
never pass through elisp read syntax, so hostile filenames stay inert.
QUIET and DISPLAY are passed through to `claude-open'."
  (let (specs)
    (with-temp-buffer
      (insert-file-contents spec-file)
      (dolist (ln (split-string (buffer-string) "\n" t))
        (pcase-let ((`(,file ,line ,col) (split-string ln "\t")))
          (push (list file
                      (and line (string-match-p "[0-9]" line)
                           (string-to-number line))
                      (and col (string-match-p "[0-9]" col)
                           (string-to-number col)))
                specs))))
    (claude-open (nreverse specs) quiet display)))

(defun claude-open-goto-last ()
  "Jump to the most recent `claude-open' location.
Repeated invocations cycle backward through the ring, skipping
entries whose buffers have been killed."
  (interactive)
  (when (ring-empty-p claude-open-ring)
    (user-error "claude-open ring is empty"))
  (unless (eq last-command 'claude-open-goto-last)
    (setq claude-open--ring-index 0))
  (let ((len (ring-length claude-open-ring))
        (tries 0)
        entry marker)
    (while (and (< tries len) (not marker))
      (setq entry (ring-ref claude-open-ring claude-open--ring-index)
            claude-open--ring-index (mod (1+ claude-open--ring-index) len)
            tries (1+ tries))
      (when (marker-buffer (car entry))
        (setq marker (car entry))))
    (unless marker
      (user-error "All claude-open ring entries point to killed buffers"))
    (pop-to-buffer-same-window (marker-buffer marker))
    (claude-open--jump (marker-position marker))
    (recenter)
    (pulse-momentary-highlight-one-line (point))))

(defun claude-open-setup-keys (&optional map)
  "Bind `claude-open-goto-last' to \\`C-c j' in MAP (default the global map).
Shipped but not called: binding choice is the user's.  Recommended home is
the init-tmux-claude keybinding cluster in ~/.emacs.d/lisp/."
  (define-key (or map global-map) (kbd "C-c j") #'claude-open-goto-last))

(provide 'claude-open)
;;; claude-open.el ends here
