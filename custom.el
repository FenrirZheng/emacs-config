;;; -*- lexical-binding: t -*-
;; This file is the single sink for `M-x customize' output.  init.el sets
;; `custom-file' to point here and loads it; do NOT keep a parallel
;; `custom-set-variables' block in init.el.
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("8c7e832be864674c220f9a9361c851917a93f921fedb7717b1b5ece47690c098"
     "720838034f1dd3b3da66f6bd4d053ee67c93a747b219d1c546c41c4e425daf93"
     default))
 '(eglot-confirm-server-edits nil nil nil "Customized with use-package eglot")
 '(package-selected-packages
   '(ace-link ace-window aidermacs apheleia avy-zap bash-completion
              beacon blamer breadcrumb cape casual-suite centaur-tabs
              cmake-mode colorful-mode combobulate consult-dir
              consult-eglot consult-todo copilot corfu-terminal dape
              dashboard devdocs diff-hl difftastic dimmer
              dired-collapse dired-narrow dired-sidebar diredfl docker
              dockerfile-mode doom-modeline doom-themes dumb-jump
              ef-themes eglot-inactive-regions eglot-x
              eldoc-box embark-consult envrc exec-path-from-shell
              expand-region expreg flymake-eslint fontaine forge
              frog-jump-buffer gcmh git-link git-timemachine goggles
              good-scroll goto-chg gptel gtags-mode helpful
              highlight-numbers imenu-list indent-bars jinx keyfreq
              ligature lin lua-mode magit-delta magit-todos marginalia
              mermaid-mode minimap mixed-pitch mlscroll move-text
              multiple-cursors nerd-icons-completion nerd-icons-corfu
              nerd-icons-dired nerd-icons-ibuffer no-littering
              nyan-mode ob-mermaid olivetti orderless org-appear
              org-download org-modern org-roam-ui plantuml-mode popper
              prism pulsar rainbow-delimiters restclient rime
              separedit sideline-flymake solaire-mode spacious-padding
              string-inflection symbol-overlay system-packages
              tabspaces tempel transient-posframe treesit-auto
              treesit-fold undo-fu-session valign vertico-posframe
              volatile-highlights vterm-toggle vue-mode vundo
              web-server wgrep which-key-posframe ws-butler
              yasnippet-snippets))
 '(package-vc-selected-packages
   '((combobulate :url "https://github.com/mickeynp/combobulate")
     (eglot-x :url "https://github.com/nemethf/eglot-x"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(isearch-fail ((t (:background "#e0af68" :foreground "#414868" :weight bold)))))
