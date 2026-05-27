;;; init-alacritty-claude.el --- Launch alacritty + tmux + claude CLI -*- lexical-binding: t; -*-

;;; Commentary:
;; A single interactive command, `fenrir/alacritty-tmux-claude', that opens a
;; brand-new alacritty window, starts a fresh tmux session inside it, and runs
;; the `claude' CLI in that session.
;;
;; Companion to `init-tmux-claude.el': that module's `fenrir/tmux-claude-split'
;; assumes Emacs is already inside tmux and splits the current pane to host
;; `claude'.  This module is the "from-scratch" variant -- useful when Emacs
;; runs as a GUI / daemon outside any tmux, and you want a new external
;; terminal window with the whole stack ready to go.
;;
;; Each invocation creates a brand-new tmux session (no `-A', no fixed `-s'
;; name) -- so calling the command N times yields N independent sessions, each
;; in its own alacritty window.  This matches the "one-shot launcher" UX where
;; sessions don't accidentally get shared between unrelated windows.
;;
;; Not on any package archive; loaded by `init.el' like the other
;; `init-<area>' modules.  Invoke with `M-x fenrir/alacritty-tmux-claude'.

;;; Code:

(defun fenrir/alacritty-tmux-claude ()
  "Open a fresh alacritty window running tmux + the `claude' CLI.

Spawns `alacritty' asynchronously via `start-process'.  The alacritty
window is launched with `--working-directory' set to Emacs'
`default-directory', so the tmux session (and `claude' inside it)
inherits the same cwd -- handy for letting `claude' see the current
project's files.

The full command line is:

    alacritty --working-directory <pwd> -e tmux new-session claude

`tmux new-session' with no `-s' auto-names the session (0, 1, ...); no
`-A', so each invocation creates an independent session rather than
attaching to a shared one.  When `claude' exits, its window exits, the
session has no remaining windows and tmux exits, and alacritty closes
its window -- a clean end-to-end teardown.

All three binaries (`alacritty', `tmux', `claude') must be on
`exec-path'; missing any aborts up front with a `user-error' and spawns
nothing.  The spawned process has `process-query-on-exit-flag' cleared
so quitting Emacs (\\[save-buffers-kill-terminal]) doesn't prompt about
the running alacritty."
  (interactive)
  (dolist (bin '("alacritty" "tmux" "claude"))
    (unless (executable-find bin)
      (user-error "`%s' not found on `exec-path' -- install it first" bin)))
  (let* ((cwd  (expand-file-name default-directory))
         (proc (start-process "alacritty-tmux-claude" nil
                              "alacritty"
                              "--working-directory" cwd
                              "-e" "tmux" "new-session" "claude")))
    (set-process-query-on-exit-flag proc nil)
    (message "alacritty: launched tmux+claude (pid %d, cwd %s)"
             (process-id proc) cwd)))

(provide 'init-alacritty-claude)
;;; init-alacritty-claude.el ends here
