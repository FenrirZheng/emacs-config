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

(provide 'init-terminal)
;;; init-terminal.el ends here
