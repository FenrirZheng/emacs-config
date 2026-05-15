;;; claude-jobs-view.el --- Tabulated UI for the jobctl CLI -*- lexical-binding: t; -*-

;; Author: fenrir
;; Keywords: tools, processes
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:
;;
;; A `tabulated-list-mode' wrapper around the `jobctl' CLI for managing
;; persistent Claude Code background sessions.  Modelled on `proced' and
;; `package-menu-mode': one row = one job.
;;
;; Entry point: M-x claude-jobs-view
;;
;; Two row types coexist in the same buffer (TYPE column):
;;   * `session' — jobctl-dispatched persistent Claude sessions.  All
;;                 commands below operate on these.
;;   * `daemon'  — read-only mirror of `~/.claude/jobs/<short>/state.json'
;;                 (the `claude agents' UI).  jobctl can only LIST these;
;;                 action keys (s/d/k/a/...) refuse with a clear error.
;;
;; Keys (in *claude-jobs* buffer):
;;   g       refresh
;;   RET / a attach — opens a new tmux window running `jobctl attach <uuid>'
;;           when $TMUX is set; falls back to vterm/term-mode otherwise.
;;   i       show detail buffer (uuid, cwd, transcript path, first prompt)
;;   o       open transcript JSONL read-only          (session only)
;;   s       send <uuid> <prompt> (async)             (session only)
;;   +       dispatch new session                     (any row)
;;   k       kill (SIGTERM only, state files kept)    (session only)
;;   d       delete (SIGTERM + rm state files)        (session only)
;;   l       show logs (snapshot)                     (session only)
;;   t       tail logs (live stream)                  (session only)
;;   p       copy transcript path to kill ring        (session only)
;;   c       copy cwd to kill ring                    (session only)
;;   w       wait until exit (async notification)     (session only)
;;   q       bury buffer
;;
;; The INTENT column shows the first user message from each session's
;; transcript (mouse-hover for the untrimmed text via `help-echo').  Set
;; `tooltip-mode' for the popup, or just press `i' for the full view.
;;
;; Note: `jobctl list' returns a non-zero exit code on some hosts even when
;; the listing itself succeeded — we therefore parse stdout regardless of
;; exit status, and only surface an error when stdout is empty.

;;; Code:

(require 'tabulated-list)
(require 'subr-x)
(require 'seq)
;; `json-parse-string' is a C builtin since Emacs 27; no `require' needed.

;; Forward declarations: these symbols come from packages we only touch at
;; runtime (vterm via `fboundp', term via lazy `require'); byte-compiling
;; this file alone would otherwise warn.
(defvar vterm-shell)
(defvar vterm-buffer-name)
(declare-function vterm "vterm" (&optional arg))
(declare-function term-mode "term" ())
(declare-function term-char-mode "term" ())

(defgroup claude-jobs-view nil
  "UI for the `jobctl' CLI."
  :group 'tools
  :prefix "claude-jobs-view-")

(defcustom claude-jobs-view-jobctl-program "jobctl"
  "Path to the `jobctl' executable.  Looked up on PATH by default."
  :type 'string)

(defcustom claude-jobs-view-state-dir
  (or (getenv "JOBCTL_STATE")
      (expand-file-name ".cache/jobctl" (or (getenv "HOME") "~")))
  "Mirrors $JOBCTL_STATE; directory where jobctl writes <uuid>.meta files."
  :type 'directory)

(defcustom claude-jobs-view-projects-dir
  (expand-file-name ".claude/projects" (or (getenv "HOME") "~"))
  "Where Claude Code writes session transcript JSONL files.
Used as the secondary cwd source when the meta file is missing `cwd='."
  :type 'directory)

(defcustom claude-jobs-view-transcript-head-bytes 65536
  "Bytes to scan from the head of a transcript JSONL for cwd / first prompt.
Sized to comfortably fit Claude Code's typical opening exchange — 3–4
system/init entries plus a single user message that itself can run to
several KB.  Bump higher if your dispatch prompts routinely exceed ~50KB."
  :type 'integer)

(defcustom claude-jobs-view-short-len 8
  "Number of leading UUID characters shown in the SHORT column."
  :type 'integer)

(defcustom claude-jobs-view-buffer-name "*claude-jobs*"
  "Buffer name for the main tabulated list."
  :type 'string)

;;;; Faces -------------------------------------------------------------------
;;
;; Colour palette deliberately built on the three semantic faces every
;; Emacs theme defines consistently — `success' (green), `warning'
;; (yellow/orange), `error' (red).  Inheriting from these instead of
;; `font-lock-*-face' avoids the "everything looks purple" trap most
;; doom-themes variants fall into, and a theme switch carries through
;; for free.

(defface claude-jobs-view-session-face
  '((t :inherit success))
  "Face for the TYPE column of dispatched-session rows (green)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-daemon-face
  '((t :inherit warning :slant italic))
  "Face for the TYPE column of daemon-job rows (italic yellow)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-alive-face
  '((t :inherit success :weight bold))
  "Face for STATE = alive (bold green)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-dead-face
  '((t :inherit error))
  "Face for STATE = dead or any non-alive state (red)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-short-face
  '((t :inherit warning))
  "Face for the short-UUID column (yellow)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-pid-face
  '((t :inherit warning))
  "Face for the PID column (yellow)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-timestamp-face
  '((t :inherit font-lock-comment-face))
  "Face for the UPDATED timestamp column (theme's comment colour — usually
muted/grey; deliberately not red/green/yellow because timestamps are
metadata, not status)."
  :group 'claude-jobs-view)

(defface claude-jobs-view-intent-face
  '((t :inherit success :slant italic))
  "Face for the INTENT column (italic green)."
  :group 'claude-jobs-view)

;;;; Parsing -----------------------------------------------------------------

(defconst claude-jobs-view--session-rx
  ;; "<uuid>  pid=<pid>(<state>)  <iso-timestamp>"
  (rx bol
      (group (= 8 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 12 hex))
      (+ space)
      "pid=" (group (+ digit)) "(" (group (+ (any "a-z"))) ")"
      (+ space)
      (group (+ (not (any " \t\n")))))
  "Matches a dispatched-session row in `jobctl list' output.")

(defconst claude-jobs-view--daemon-header-rx
  (rx bol "SHORT" (+ space) "STATE" (+ space) "UPDATED" (+ space) "INTENT")
  "Header line of the daemon-jobs block; data rows follow until a blank or
section divider.")

(defconst claude-jobs-view--section-rx
  (rx bol "===" (+ space) (group (+ nonl)) (+ space) "==="))

(defun claude-jobs-view--meta-cwd (uuid)
  "Return cwd recorded in $JOBCTL_STATE/UUID.meta, or nil.
Pre-2026-05 dispatches omit the `cwd=' line entirely; callers MUST treat
nil as `try the next source', not as a final answer."
  (let ((meta (expand-file-name (concat uuid ".meta")
                                claude-jobs-view-state-dir)))
    (when (file-readable-p meta)
      (with-temp-buffer
        (insert-file-contents meta)
        (goto-char (point-min))
        (when (re-search-forward "^cwd=\\(.*\\)$" nil t)
          (match-string 1))))))

(defun claude-jobs-view--find-transcript (uuid)
  "Locate the JSONL transcript for UUID under `claude-jobs-view-projects-dir'.
Returns absolute path or nil.  Claude scatters transcripts across per-cwd
subdirs (`-home-fenrir-code-foo/<uuid>.jsonl'); we don't know the subdir
without first knowing the cwd, so we wildcard-glob one level deep."
  (car (file-expand-wildcards
        (expand-file-name (format "*/%s.jsonl" uuid)
                          claude-jobs-view-projects-dir))))

(defun claude-jobs-view--transcript-cwd (uuid)
  "Read the first `\"cwd\":\"...\"' value from UUID's transcript JSONL.
Returns nil when the transcript is missing or contains no cwd entry.
Scans only the head of the file (see
`claude-jobs-view-transcript-head-bytes') — sufficient because Claude
writes the cwd on every entry, so the first occurrence is near the top."
  (when-let ((path (claude-jobs-view--find-transcript uuid)))
    (with-temp-buffer
      ;; `insert-file-contents' with BEG/END = (0 N) reads bytes 0..N-1.
      (insert-file-contents path nil 0 claude-jobs-view-transcript-head-bytes)
      (goto-char (point-min))
      (when (re-search-forward "\"cwd\":\"\\([^\"]+\\)\"" nil t)
        (match-string 1)))))

(defun claude-jobs-view--transcript-first-user-text (uuid)
  "Return the first `type:\"user\"' message's text from UUID's transcript.
Scans only the file head (`claude-jobs-view-transcript-head-bytes')
because the first user entry always sits near the top.  Returns nil when:
  - no transcript file is found,
  - the head contains no parsable user entry (truncation, races, format
    drift).  Caller treats nil as `no intent available'."
  (when-let ((path (claude-jobs-view--find-transcript uuid)))
    (with-temp-buffer
      (insert-file-contents path nil 0
                            claude-jobs-view-transcript-head-bytes)
      ;; NOTE: don't try to trim a partially-read last line here.  When the
      ;; head window happens to cut mid-way through THE line we want (the
      ;; user message can itself be several KB), trimming wipes the only
      ;; interesting entry.  Let `ignore-errors' silently drop chopped JSON
      ;; instead.
      (goto-char (point-min))
      (catch 'found
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            ;; Cheap prefilter — `json-parse-string' on every line of a
            ;; long transcript head is wasted work when we know what we
            ;; want.
            (when (and (not (string-empty-p line))
                       (string-search "\"type\":\"user\"" line))
              (let ((obj (ignore-errors
                           (json-parse-string line :object-type 'alist))))
                (when (and obj (equal (alist-get 'type obj) "user"))
                  (let* ((msg     (alist-get 'message obj))
                         (content (and msg (alist-get 'content msg)))
                         (text
                          (cond
                           ((stringp content) content)
                           ;; Content can be a vector of blocks; first
                           ;; `text' block is the user-visible prompt.
                           ((vectorp content)
                            (when-let ((blk
                                        (seq-find
                                         (lambda (b)
                                           (equal (alist-get 'type b) "text"))
                                         content)))
                              (alist-get 'text blk))))))
                    (when (and text (not (string-empty-p text)))
                      (throw 'found text)))))))
          (forward-line 1))
        nil))))

(defun claude-jobs-view--one-line (s)
  "Collapse all whitespace runs in S to a single space."
  (replace-regexp-in-string "[\n\t ]+" " " (string-trim s)))

(defun claude-jobs-view--resolve-cwd (uuid)
  "Resolve dispatch-time cwd for UUID; mirrors jobctl's `resolve_cwd' chain.
Source 1: $JOBCTL_STATE/UUID.meta `cwd=' line  (post-2026-05 dispatches).
Source 2: transcript JSONL `\"cwd\":\"...\"' grep  (always correct when
          a transcript exists, because Claude itself wrote it).
Returns nil only when BOTH sources are unavailable — typical for sessions
where the transcript has been pruned away."
  (or (claude-jobs-view--meta-cwd uuid)
      (claude-jobs-view--transcript-cwd uuid)))

(defun claude-jobs-view--run-list ()
  "Run `jobctl list' and return stdout as a string.
Tolerates non-zero exit codes — only signals an error when stdout is empty."
  (with-temp-buffer
    (let ((exit (call-process claude-jobs-view-jobctl-program
                              nil t nil "list")))
      (let ((out (buffer-string)))
        (when (and (not (zerop exit)) (string-empty-p (string-trim out)))
          (error "jobctl list failed (exit %d)" exit))
        out))))

(defun claude-jobs-view--parse (raw)
  "Parse RAW `jobctl list' output into a list of tabulated-list entries.
Each entry is of the form (ID [TYPE SHORT STATE PID UPDATED INFO]) where
ID is (TAG . KEY) — TAG is `session' (KEY = full uuid) or `daemon' (KEY =
short id)."
  (let ((rows '())
        (in-daemon-data nil))
    (dolist (line (split-string raw "\n"))
      (cond
       ;; Section divider — `=== ... ===`.  Just resets daemon-data mode;
       ;; row classification is by regex, not by which section we're in.
       ((string-match claude-jobs-view--section-rx line)
        (setq in-daemon-data nil))
       ;; Daemon header — data rows follow until blank or new section.
       ((string-match claude-jobs-view--daemon-header-rx line)
        (setq in-daemon-data t))
       ;; Placeholder "(none with state.json)" — skip.
       ((string-match-p "^(none" line)
        (setq in-daemon-data nil))
       ;; Blank line resets daemon-data mode.
       ((string-empty-p (string-trim line))
        (setq in-daemon-data nil))
       ;; Session row.
       ((string-match claude-jobs-view--session-rx line)
        (let* ((uuid   (match-string 1 line))
               (pid    (match-string 2 line))
               (state  (match-string 3 line))
               (ts     (match-string 4 line))
               (short  (substring uuid 0
                                  (min (length uuid)
                                       claude-jobs-view-short-len)))
               (raw    (claude-jobs-view--transcript-first-user-text uuid))
               (intent
                (if raw
                    (propertize (claude-jobs-view--one-line raw)
                                'face 'claude-jobs-view-intent-face
                                ;; help-echo carries the full untrimmed
                                ;; text — mouse-hover (or `tooltip-mode')
                                ;; reveals it without leaving the list.
                                'help-echo raw)
                  (propertize "—" 'face 'shadow))))
          (push (list (cons 'session uuid)
                      (vector
                       (propertize "session" 'face
                                   'claude-jobs-view-session-face)
                       (propertize short  'face
                                   'claude-jobs-view-short-face)
                       (propertize state  'face
                                   (if (string= state "alive")
                                       'claude-jobs-view-alive-face
                                     'claude-jobs-view-dead-face))
                       (propertize pid    'face
                                   'claude-jobs-view-pid-face)
                       (propertize ts     'face
                                   'claude-jobs-view-timestamp-face)
                       intent))
                rows)))
       ;; Daemon data row.
       (in-daemon-data
        (let ((fields (split-string (string-trim line) "[ \t]+" t)))
          (when (>= (length fields) 4)
            (pcase-let* ((`(,short ,state ,updated . ,intent-tail) fields)
                         (intent (string-join intent-tail " ")))
              (push (list (cons 'daemon short)
                          (vector
                           (propertize "daemon" 'face
                                       'claude-jobs-view-daemon-face)
                           (propertize short 'face
                                       'claude-jobs-view-short-face)
                           ;; daemon STATE vocabulary is open (idle,
                           ;; running, errored, …); colour-code only the
                           ;; clear-active markers, dim everything else.
                           (propertize state 'face
                                       (if (string-match-p
                                            "\\`\\(active\\|running\\|alive\\)\\'"
                                            state)
                                           'claude-jobs-view-alive-face
                                         'claude-jobs-view-dead-face))
                           (propertize "—" 'face 'shadow)
                           (propertize updated 'face
                                       'claude-jobs-view-timestamp-face)
                           (propertize intent 'face
                                       'claude-jobs-view-intent-face
                                       'help-echo intent)))
                    rows)))))))
    (nreverse rows)))

(defun claude-jobs-view--entries ()
  "Return `tabulated-list-entries' from a fresh `jobctl list' invocation."
  (claude-jobs-view--parse (claude-jobs-view--run-list)))

;;;; Helpers ----------------------------------------------------------------

(defun claude-jobs-view--id-at-point ()
  (or (tabulated-list-get-id)
      (user-error "No job on this line")))

(defun claude-jobs-view--session-at-point ()
  "Return full uuid for the session at point, or signal a user-error."
  (let ((id (claude-jobs-view--id-at-point)))
    (unless (and (consp id) (eq (car id) 'session))
      (user-error "This row is a daemon job; jobctl can only list those"))
    (cdr id)))

(defun claude-jobs-view--short (uuid)
  (substring uuid 0 (min (length uuid) claude-jobs-view-short-len)))

(defun claude-jobs-view--jobctl-string (&rest args)
  "Run jobctl ARGS synchronously; return trimmed stdout (signal on failure)."
  (with-temp-buffer
    (let ((exit (apply #'call-process claude-jobs-view-jobctl-program
                       nil t nil args)))
      (unless (zerop exit)
        (error "jobctl %s failed (exit %d):\n%s"
               (string-join args " ") exit (buffer-string)))
      (string-trim (buffer-string)))))

(defun claude-jobs-view--scratch-buffer (kind uuid)
  (let ((buf (get-buffer-create
              (format "*claude-jobs %s %s*" kind
                      (claude-jobs-view--short uuid)))))
    (with-current-buffer buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (special-mode))
    buf))

(defun claude-jobs-view--refresh-list-buffer ()
  "If the main list buffer is alive, refresh it."
  (let ((buf (get-buffer claude-jobs-view-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (claude-jobs-view-refresh)))))

;;;; Commands ---------------------------------------------------------------

(defun claude-jobs-view-refresh ()
  "Repopulate `*claude-jobs*'."
  (interactive)
  (setq tabulated-list-entries (claude-jobs-view--entries))
  (tabulated-list-print 'remember-pos))

(defun claude-jobs-view-open-transcript ()
  "Visit the transcript JSONL for the session at point (read-only)."
  (interactive)
  (let* ((uuid (claude-jobs-view--session-at-point))
         (path (claude-jobs-view--jobctl-string "path" uuid)))
    (when (string-empty-p path)
      (user-error "No transcript path for %s" (claude-jobs-view--short uuid)))
    (find-file-read-only path)))

(defun claude-jobs-view-show-info ()
  "Pop a detail buffer summarising the row at point.
For sessions, shows uuid / cwd / transcript path / first user message
verbatim — i.e. what you'd otherwise have to chain `jobctl path' +
`jobctl cwd' + `cat <jsonl> | jq' to see.  For daemon rows, just notes
that jobctl can only list them."
  (interactive)
  (let* ((id (claude-jobs-view--id-at-point))
         (tag (car id))
         (key (cdr id)))
    (pcase tag
      ('session (claude-jobs-view--render-session-info key))
      ('daemon  (claude-jobs-view--render-daemon-info  key))
      (_        (user-error "Unknown row type: %S" tag)))))

(defun claude-jobs-view--render-session-info (uuid)
  (let* ((buf  (claude-jobs-view--scratch-buffer "info" uuid))
         (path (ignore-errors
                 (claude-jobs-view--jobctl-string "path" uuid)))
         (cwd  (or (claude-jobs-view--resolve-cwd uuid) "(not resolved)"))
         (text (claude-jobs-view--transcript-first-user-text uuid)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (insert (propertize "Session\n" 'face 'bold))
        (insert (format "  uuid:        %s\n" uuid))
        (insert (format "  cwd:         %s\n" (abbreviate-file-name cwd)))
        (insert (format "  transcript:  %s\n" (or path "(unresolved)")))
        (insert "\n")
        (insert (propertize "First user message\n" 'face 'bold))
        (insert (or text "(none — transcript empty or unparseable)") "\n"))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(defun claude-jobs-view--render-daemon-info (short)
  (let ((buf (get-buffer-create
              (format "*claude-jobs info %s*" short))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "Daemon job %s\n\n" short) 'face 'bold))
        (insert "jobctl can only LIST daemon jobs; inspect/manage via the\n"
                "`claude agents' UI (see ~/.claude/jobs/<short>/state.json).\n"))
      (special-mode))
    (pop-to-buffer buf)))

(defun claude-jobs-view-send (uuid prompt)
  "Send PROMPT to UUID; reply streams into a side buffer (async)."
  (interactive
   (let* ((u (claude-jobs-view--session-at-point))
          (p (read-string (format "Prompt for %s: "
                                  (claude-jobs-view--short u)))))
     (list u p)))
  (let ((buf (claude-jobs-view--scratch-buffer "reply" uuid))
        (short (claude-jobs-view--short uuid)))
    (make-process
     :name (format "jobctl-send-%s" short)
     :buffer buf
     :command (list claude-jobs-view-jobctl-program "send" uuid prompt)
     :noquery t
     :sentinel (lambda (_p ev)
                 (when (string-match-p "finished\\|exited" ev)
                   (message "claude-jobs: send to %s done" short))))
    (display-buffer buf)))

(defun claude-jobs-view-dispatch (cwd prompt)
  "Dispatch a new session from CWD with initial PROMPT."
  (interactive
   (list (read-directory-name "Dispatch cwd: " default-directory nil t)
         (read-string "Initial prompt: ")))
  (let ((default-directory cwd)
        (buf (get-buffer-create "*claude-jobs dispatch*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (special-mode))
    (make-process
     :name "jobctl-dispatch"
     :buffer buf
     :command (list claude-jobs-view-jobctl-program "dispatch" prompt)
     :noquery t
     :sentinel (lambda (_p ev)
                 (when (string-match-p "finished\\|exited" ev)
                   (message "claude-jobs: dispatch done (g to refresh)")
                   (claude-jobs-view--refresh-list-buffer))))
    (display-buffer buf)))

(defun claude-jobs-view-kill ()
  "Send SIGTERM to the session at point (confirmed).
Does NOT delete state files — use `claude-jobs-view-delete' for that."
  (interactive)
  (let* ((uuid  (claude-jobs-view--session-at-point))
         (short (claude-jobs-view--short uuid)))
    (when (yes-or-no-p (format "SIGTERM %s ? " short))
      (claude-jobs-view--jobctl-string "kill" uuid)
      (claude-jobs-view-refresh))))

(defun claude-jobs-view-delete ()
  "Delete the session at point: SIGTERM (if alive) then remove its
$JOBCTL_STATE/<uuid>.{meta,out,err} bookkeeping files.

Safe to run on a live session: Linux keeps the inode alive for the
process's open `.out'/`.err' file descriptors until they're closed, so
the running claude keeps writing — it just becomes invisible from the
filesystem.  Transcript JSONL under ~/.claude/projects/ is NOT touched
(that's Claude Code's data; resume-able from elsewhere)."
  (interactive)
  (let* ((uuid  (claude-jobs-view--session-at-point))
         (short (claude-jobs-view--short uuid))
         (files (mapcar (lambda (ext)
                          (expand-file-name (concat uuid ext)
                                            claude-jobs-view-state-dir))
                        '(".meta" ".out" ".err")))
         (existing (seq-filter #'file-exists-p files)))
    (when (yes-or-no-p
           (format "Delete session %s? (SIGTERM + rm %d state files) "
                   short (length existing)))
      ;; Best-effort terminate: process may already be dead, in which case
      ;; jobctl kill exits non-zero — ignore and proceed to cleanup.
      (ignore-errors
        (claude-jobs-view--jobctl-string "kill" uuid))
      (dolist (f existing)
        (delete-file f))
      (message "claude-jobs: deleted %s (%d files removed)"
               short (length existing))
      (claude-jobs-view-refresh))))

(defun claude-jobs-view--attach-via-vterm (uuid)
  "Open `jobctl attach UUID' in a vterm (or term-mode) buffer.
Fallback path used when Emacs is not running inside tmux."
  (let* ((short (claude-jobs-view--short uuid))
         (cmd   (format "%s attach %s"
                        claude-jobs-view-jobctl-program uuid))
         (name  (format "*claude-jobs attach %s*" short)))
    (cond
     ((fboundp 'vterm)
      (let ((vterm-shell cmd)
            (vterm-buffer-name name))
        (vterm)))
     (t
      (require 'term)
      (switch-to-buffer
       (make-term (string-trim-left name "\\*") "bash" nil "-c" cmd))
      (term-mode)
      (term-char-mode)))))

(defun claude-jobs-view-attach ()
  "Attach to the session at point.

In a tmux session (`$TMUX' set), opens a new tmux window running
`jobctl attach <uuid>' — far better TTY isolation than running a
Claude REPL inside an Emacs terminal emulator.  Outside tmux, falls
back to vterm (or term-mode)."
  (interactive)
  (let* ((uuid  (claude-jobs-view--session-at-point))
         (short (claude-jobs-view--short uuid)))
    (cond
     ((not (getenv "TMUX"))
      (message "claude-jobs: no $TMUX — using vterm attach")
      (claude-jobs-view--attach-via-vterm uuid))
     (t
      ;; tmux passes the shell-command arg through `sh -c'; quote the
      ;; program path so a user-customised `claude-jobs-view-jobctl-program'
      ;; containing spaces still works.  UUIDs are hex+dash so safe verbatim.
      (let* ((cmd  (format "%s attach %s"
                           (shell-quote-argument
                            claude-jobs-view-jobctl-program)
                           uuid))
             (name (format "claude-%s" short))
             (exit (call-process "tmux" nil nil nil
                                 "new-window" "-n" name cmd)))
        (if (zerop exit)
            (message "tmux: opened window '%s'" name)
          (error "tmux new-window failed (exit %d)" exit)))))))

(defun claude-jobs-view-logs ()
  "Show stdout+stderr (snapshot) of the session at point."
  (interactive)
  (let* ((uuid (claude-jobs-view--session-at-point))
         (buf  (claude-jobs-view--scratch-buffer "logs" uuid)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (claude-jobs-view--jobctl-string "logs" uuid))
        (goto-char (point-max))))
    (display-buffer buf)))

(defun claude-jobs-view-tail ()
  "Tail the dispatched stdout of the session at point (live)."
  (interactive)
  (let* ((uuid  (claude-jobs-view--session-at-point))
         (short (claude-jobs-view--short uuid))
         (buf   (claude-jobs-view--scratch-buffer "tail" uuid)))
    (make-process
     :name (format "jobctl-tail-%s" short)
     :buffer buf
     :command (list claude-jobs-view-jobctl-program "tail" uuid)
     :noquery t
     :filter (lambda (proc chunk)
               (when (buffer-live-p (process-buffer proc))
                 (with-current-buffer (process-buffer proc)
                   (let* ((inhibit-read-only t)
                          (win (get-buffer-window (current-buffer) 'visible))
                          (at-end (or (null win)
                                      (= (window-point win) (point-max)))))
                     (save-excursion
                       (goto-char (point-max))
                       (insert chunk))
                     (when (and win at-end)
                       (set-window-point win (point-max))))))))
    (display-buffer buf)))

(defun claude-jobs-view-copy-path ()
  "Copy transcript path of the session at point to the kill ring."
  (interactive)
  (let* ((uuid (claude-jobs-view--session-at-point))
         (path (claude-jobs-view--jobctl-string "path" uuid)))
    (kill-new path)
    (message "Copied: %s" path)))

(defun claude-jobs-view-copy-cwd ()
  "Copy dispatch-time cwd of the session at point to the kill ring."
  (interactive)
  (let* ((uuid (claude-jobs-view--session-at-point))
         (cwd  (claude-jobs-view--jobctl-string "cwd" uuid)))
    (kill-new cwd)
    (message "Copied: %s" cwd)))

(defun claude-jobs-view-wait ()
  "Asynchronously wait until the session at point exits."
  (interactive)
  (let* ((uuid  (claude-jobs-view--session-at-point))
         (short (claude-jobs-view--short uuid)))
    (make-process
     :name (format "jobctl-wait-%s" short)
     :buffer nil
     :command (list claude-jobs-view-jobctl-program "wait" uuid)
     :noquery t
     :sentinel (lambda (_p ev)
                 (when (string-match-p "finished\\|exited" ev)
                   (message "claude-jobs: %s has exited" short)
                   (claude-jobs-view--refresh-list-buffer))))
    (message "Waiting for %s..." short)))

;;;; Mode --------------------------------------------------------------------

(defvar claude-jobs-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "g"        #'claude-jobs-view-refresh)
    (define-key map (kbd "RET") #'claude-jobs-view-attach)
    (define-key map "a"        #'claude-jobs-view-attach)
    (define-key map "i"        #'claude-jobs-view-show-info)
    (define-key map "o"        #'claude-jobs-view-open-transcript)
    (define-key map "s"        #'claude-jobs-view-send)
    (define-key map "+"        #'claude-jobs-view-dispatch)
    (define-key map "k"        #'claude-jobs-view-kill)
    (define-key map "d"        #'claude-jobs-view-delete)
    (define-key map "l"        #'claude-jobs-view-logs)
    (define-key map "t"        #'claude-jobs-view-tail)
    (define-key map "p"        #'claude-jobs-view-copy-path)
    (define-key map "c"        #'claude-jobs-view-copy-cwd)
    (define-key map "w"        #'claude-jobs-view-wait)
    map)
  "Keymap for `claude-jobs-view-mode'.")

(define-derived-mode claude-jobs-view-mode tabulated-list-mode "Claude-Jobs"
  "Tabulated UI for the `jobctl' CLI."
  (setq tabulated-list-format
        `[("TYPE"    8 t)
          ("SHORT"   ,(1+ claude-jobs-view-short-len) t)
          ("STATE"   7 t)
          ("PID"     8 t)
          ("UPDATED" 26 t)
          ("INTENT"  0 t)])
  (setq tabulated-list-sort-key '("UPDATED" . t))
  (setq tabulated-list-padding 1)
  (add-hook 'tabulated-list-revert-hook
            #'claude-jobs-view-refresh nil t)
  (tabulated-list-init-header)
  ;; Highlight the row under point — same idiom as `proced', `Buffer-menu'.
  (hl-line-mode 1))

;;;###autoload
(defun claude-jobs-view ()
  "Open the `*claude-jobs*' tabulated UI in the current window.
Uses `switch-to-buffer' rather than `pop-to-buffer' so the list claims
the full window width — the INTENT column is long enough that being
sliced into a side window cuts off the meaningful tail."
  (interactive)
  (let ((buf (get-buffer-create claude-jobs-view-buffer-name)))
    (with-current-buffer buf
      (claude-jobs-view-mode)
      (claude-jobs-view-refresh))
    (switch-to-buffer buf)))

(provide 'claude-jobs-view)
;;; claude-jobs-view.el ends here
