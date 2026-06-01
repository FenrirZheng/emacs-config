;;; init-python.el --- Python: python-ts-mode + pyright -*- lexical-binding: t; -*-

;;; Commentary:
;; Python language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter / combobulate / ggtags
;; infrastructure lives in [`lisp/init-languages.el'](../init-languages.el);
;; this module only adds the Python mode hooks and pyright's per-server
;; workspace configuration.

;;; Code:

;; Eglot (gopls-style autoload) attaches on `python-ts-mode'.  combobulate adds
;; tree-sitter structural editing; ggtags is the GTAGS xref backend used only
;; in buffers without a live language server (Eglot, when up, wins xref).  All
;; three commands are autoloaded from declarations in init-languages.el.
(add-hook 'python-ts-mode-hook #'eglot-ensure)
(add-hook 'python-ts-mode-hook #'combobulate-mode)
(add-hook 'python-mode-hook    #'ggtags-mode)
(add-hook 'python-ts-mode-hook #'ggtags-mode)

;; pyright / basedpyright: workspace-wide diagnostics (default "openFilesOnly"
;; silently misses cross-file regressions) plus type-checking on "basic" --
;; catches the obvious wrongs without the false-positive flood of "strict".
;; Bump to "strict" via `.dir-locals.el' for codebases that warrant it.
(with-eval-after-load 'eglot
  (setf (alist-get :python eglot-workspace-configuration)
        '(:analysis (:typeCheckingMode "basic"
                     :diagnosticMode "workspace"
                     :autoImportCompletions t
                     :inlayHints (:variableTypes t
                                  :functionReturnTypes t
                                  :callArgumentNames t)))))

(provide 'init-python)
;;; init-python.el ends here
