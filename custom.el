;;; -*- lexical-binding: t -*-
;; This file is the single sink for `M-x customize' output.  init.el sets
;; `custom-file' to point here and loads it; do NOT keep a parallel
;; `custom-set-variables' block in init.el.
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(eglot-confirm-server-edits nil nil nil "Customized with use-package eglot")
 '(package-selected-packages
   '(ace-link ace-window aidermacs apheleia avy-zap bash-completion
              beacon blamer breadcrumb cape centaur-tabs cmake-mode
              colorful-mode combobulate consult-dir consult-eglot
              consult-todo copilot corfu-terminal dape dashboard
              devdocs diff-hl difftastic dimmer dired-collapse
              dired-narrow dired-sidebar diredfl docker
              dockerfile-mode doom-modeline doom-themes dumb-jump
              ef-themes eglot-booster eglot-inactive-regions eglot-x
              eldoc-box embark-consult envrc exec-path-from-shell
              expand-region expreg flymake-eslint fontaine forge
              frog-jump-buffer gcmh ggtags git-link git-timemachine
              goggles good-scroll goto-chg gptel helpful
              highlight-numbers imenu-list indent-bars jinx ligature
              lin lua-mode magit-delta magit-todos marginalia
              mermaid-mode minimap mixed-pitch mlscroll move-text
              multiple-cursors nerd-icons-completion nerd-icons-corfu
              nerd-icons-dired nerd-icons-ibuffer no-littering
              nyan-mode ob-mermaid olivetti orderless org-appear
              org-download org-modern org-roam-ui plantuml-mode popper
              prism pulsar rainbow-delimiters restclient separedit
              sideline-flymake solaire-mode spacious-padding
              string-inflection symbol-overlay system-packages
              tabspaces tempel transient-posframe treesit-auto
              treesit-fold undo-fu-session valign vertico-posframe
              volatile-highlights vterm-toggle vue-mode vundo
              web-server wgrep which-key-posframe ws-butler
              yasnippet-snippets))
 '(package-vc-selected-packages
   '((eglot-booster :url "https://github.com/jdtsmith/eglot-booster")
     (combobulate :url "https://github.com/mickeynp/combobulate")
     (eglot-x :url "https://github.com/nemethf/eglot-x"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(isearch-fail ((t (:background "#e0af68" :foreground "#414868" :weight bold)))))
