;;; init-terminal.el --- Terminal (vterm) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 10 of the pre-split monolithic init.el (see git log for the move).
;; A real terminal emulator (libvterm-backed), far more capable than term/eshell.
;; NOTE: it compiles a C module on first install -- needs `cmake' and
;; `libvterm' headers (`apt install cmake libvterm-dev').  If you'd rather not,
;; comment this block out and use the built-in `M-x eshell'.

;;; Code:

(use-package vterm
  :bind ("C-c t" . vterm)
  :custom
  (vterm-max-scrollback 10000)
  ;; Compile the C module when vterm.el loads, not on first `M-x vterm'.
  ;; Surfaces a missing cmake/libvterm-dev as a loud startup error.
  (vterm-always-compile-module t))

;; vterm-toggle: the IDE "integrated terminal" toggle (VSCode `Ctrl+\`').
;; `C-c t' (above) always spawns/visits a vterm; `C-c T' instead TOGGLES a
;; shared terminal window in and out of view and, crucially, `cd's it to the
;; current buffer's directory -- so "drop to a shell right here, then hide it
;; again" is one keystroke each way instead of window juggling.  `*vterm*'
;; buffers are already popper-managed (init-editing.el), so the toggled window
;; behaves consistently with the rest of the popup stack.
;;
;; `vterm-toggle-fullscreen-p' nil keeps the terminal a bottom split rather
;; than taking the whole frame; `vterm-toggle-scope' `project' makes the toggle
;; project-aware -- each project reuses its own terminal instead of one global
;; shell wandering between repos.
;; NOTE: no `:after vterm' -- that would defer the whole block (including the
;; global `C-c T' binding) until vterm is already loaded, so the very keystroke
;; meant to SUMMON the terminal wouldn't exist yet.  The `:bind' autoload pulls
;; vterm-toggle (and thus vterm) on first press instead.
(use-package vterm-toggle
  :bind (("C-c T" . vterm-toggle)
         :map vterm-mode-map
         ("C-c T" . vterm-toggle))
  :custom
  (vterm-toggle-fullscreen-p nil)
  (vterm-toggle-scope 'project))

;; bash-completion: bridge bash's programmable completion (compgen, complete -F,
;; aliases, builtins, functions, redirection-aware path expansion) into Emacs.
;; Lives on NonGNU ELPA -- already in `package-archives' by default on Emacs 28+,
;; nothing extra to register here.  Covers three completion sites:
;;   1. `M-x shell' (comint) -- via `shell-dynamic-complete-functions'.
;;   2. shell-command prompts (`M-x compile', `M-!', ...) -- bash-completion's
;;      `-dynamic-complete-nocomint' is wired in by `bash-completion-setup'.
;;   3. `M-x eshell' -- opt-in capf hook below.
;; Only useful for bash; doesn't help vterm (terminal owns its own completion).
(use-package bash-completion
  :commands (bash-completion-dynamic-complete
             bash-completion-capf-nonexclusive)
  :init
  (add-hook 'shell-dynamic-complete-functions
            #'bash-completion-dynamic-complete)
  (add-hook 'eshell-mode-hook
            (lambda ()
              (add-hook 'completion-at-point-functions
                        #'bash-completion-capf-nonexclusive nil t))))

(provide 'init-terminal)
;;; init-terminal.el ends here
