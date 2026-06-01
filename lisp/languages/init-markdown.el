;;; init-markdown.el --- Markdown -*- lexical-binding: t; -*-

;;; Commentary:
;; Markdown support, split out of the monolithic init-languages.el.
;; `markdown-mode' is also pulled in by some of the AI tools (init-ai.el,
;; init-aidermacs.el), so it may already be installed.

;;; Code:

;; gfm-mode (GitHub-flavoured Markdown) for READMEs; `pandoc' powers
;; `markdown-preview' / export.
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode))
  :custom (markdown-command "pandoc"))

(provide 'init-markdown)
;;; init-markdown.el ends here
