;;; -*- lexical-binding: t -*-
;; This file is the single sink for `M-x customize' output.  init.el sets
;; `custom-file' to point here and loads it; do NOT keep a parallel
;; `custom-set-variables' block in init.el.
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(ace-window apheleia bash-completion breadcrumb cape combobulate
                consult-dir consult-eglot corfu-terminal dape diff-hl
                difftastic dired-narrow dired-subtree diredfl
                doom-modeline doom-themes eglot-booster eldoc-box
                embark-consult envrc exec-path-from-shell
                expand-region flymake-eslint gcmh ggtags gptel helpful
                jinx lua-mode magit-delta magit-todos marginalia
                multiple-cursors nerd-icons-dired no-littering
                orderless org-appear org-modern org-roam-ui popper
                pulsar rainbow-delimiters system-packages treesit-auto
                vertico vterm vue-mode vundo wgrep yasnippet-snippets))
 '(package-vc-selected-packages
   '((eglot-booster :url "https://github.com/jdtsmith/eglot-booster")
     (combobulate :url "https://github.com/mickeynp/combobulate"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(isearch-fail ((t (:background "#e0af68" :foreground "#414868" :weight bold)))))
