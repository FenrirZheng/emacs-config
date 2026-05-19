;;; init-snippets.el --- YASnippet -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 6 of the pre-split monolithic init.el (see git log for the move).

;;; Code:

(use-package yasnippet
  :init (yas-global-mode 1))

;; A large collection of ready-made snippets for many major modes.
(use-package yasnippet-snippets
  :after yasnippet)

(provide 'init-snippets)
;;; init-snippets.el ends here
