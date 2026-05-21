;;; init-tmux-claude.el --- tmux helper: split a pane running the Claude CLI -*- lexical-binding: t; -*-

;;; Commentary:
;; A single interactive command, `fenrir/tmux-claude-split', that splits the
;; current tmux pane left/right (the equivalent of tmux's `Prefix %') and
;; launches the `claude' CLI in the new pane.  Shells out to `tmux' via
;; `call-process'.
;;
;; The tmux environment (`TMUX', `TMUX_PANE') is read from the *invoking
;; frame*, not from `getenv': when Emacs runs as a daemon, its own process
;; environment has no tmux variables (the daemon was started outside tmux),
;; but an `emacsclient' frame opened from a tmux pane carries them in the
;; frame parameter `environment'.  See `fenrir/tmux-claude--getenv'.
;;
;; Not on any package archive; loaded by `init.el' like the other
;; `init-<area>' modules.  Invoke with `M-x fenrir/tmux-claude-split'.

;;; Code:

(require 'subr-x)                       ; `string-trim', `string-empty-p'

(defun fenrir/tmux-claude--getenv (var)
  "Return environment variable VAR as seen by the current frame.

Plain `getenv' reads `process-environment' -- the environment of the
Emacs process.  Under a daemon that environment has no tmux variables,
because the daemon was started outside tmux.  An `emacsclient' frame,
however, carries its client's environment in the frame parameter
`environment' (set by server.el at frame creation); this reads VAR from
there.  For a non-client frame -- plain `emacs -nw' launched inside tmux,
or `--batch' -- the parameter is nil and this falls back to `getenv'."
  (let ((env (frame-parameter nil 'environment)))
    (if env
        (getenv-internal var env)
      (getenv var))))

(defun fenrir/tmux-claude-split ()
  "Split the current tmux pane vertically and launch the `claude' CLI in it.

Mirrors tmux's `Prefix %': makes a left/right split of the pane Emacs
occupies, runs `claude' in the new pane, and sets the new pane's title to
`claude-<pane-id>' (e.g. `claude-%2').

Works whether Emacs runs in a terminal inside tmux or as a daemon reached
by `emacsclient -nw' from a tmux pane -- the tmux environment is taken
from the invoking frame (see `fenrir/tmux-claude--getenv'), not the
daemon's own environment.

Requires the invoking frame to be inside tmux and the `claude' executable
to be on `exec-path'.  Both are verified up front; if either is missing
the command aborts with a message and no pane is created.  The new pane
runs `claude' as its command, so it closes when `claude' exits.

The pane title is only visible when tmux.conf enables `pane-border-status';
`select-pane -T' sets it regardless."
  (interactive)
  (let ((tmux (fenrir/tmux-claude--getenv "TMUX")))
    (unless tmux
      (user-error "Not inside a tmux session -- cannot split a pane"))
    (let ((claude (executable-find "claude")))
      (unless claude
        (user-error "`claude' not found on `exec-path' -- install it first"))
      ;; tmux locates its server and current pane through $TMUX / $TMUX_PANE.
      ;; A daemon's `process-environment' lacks both, so re-inject the frame's
      ;; values for the child `tmux' processes -- this makes `split-window'
      ;; act on the pane the Emacs frame occupies.
      (let* ((pane (fenrir/tmux-claude--getenv "TMUX_PANE"))
             (process-environment
              (append (list (concat "TMUX=" tmux))
                      (and pane (list (concat "TMUX_PANE=" pane)))
                      process-environment)))
        (with-temp-buffer
          (let* ((exit (call-process "tmux" nil t nil
                                     "split-window" "-h"
                                     "-P" "-F" "#{pane_id}"
                                     (shell-quote-argument claude)))
                 (pane-id (string-trim (buffer-string))))
            (when (or (not (zerop exit)) (string-empty-p pane-id))
              (user-error "tmux split-window failed (exit %s): %s" exit pane-id))
            (unless (zerop (call-process "tmux" nil nil nil
                                         "select-pane" "-t" pane-id
                                         "-T" (concat "claude-" pane-id)))
              (message "tmux: pane %s created, but setting its title failed" pane-id))
            (message "tmux: claude launched in pane %s" pane-id)))))))

(provide 'init-tmux-claude)
;;; init-tmux-claude.el ends here
