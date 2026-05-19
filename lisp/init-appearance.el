;;; init-appearance.el --- Appearance (doom-themes + doom-modeline + nerd-icons) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 11 of the pre-split monolithic init.el (see git log for the move).

;;; Code:

(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-one t)               ; swap for any `doom-*' you like
  (doom-themes-org-config))              ; tweak org-mode faces to match

;; nerd-icons: glyph set used by doom-modeline and (optionally) Dired/Corfu.
;; Run `M-x nerd-icons-install-fonts' ONCE after install to fetch the font.
;; `:defer t' is safe -- doom-modeline `require's it explicitly when it loads.
(use-package nerd-icons :defer t)

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :custom (doom-modeline-height 25))

(provide 'init-appearance)
;;; init-appearance.el ends here
