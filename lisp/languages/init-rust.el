;;; init-rust.el --- Rust: rust-ts-mode + rust-analyzer -*- lexical-binding: t; -*-

;;; Commentary:
;; Rust language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter infrastructure lives in
;; [`lisp/init-languages.el'](../init-languages.el); this module only adds the
;; Rust mode hook and rust-analyzer's per-server workspace configuration.
;;
;; Note: combobulate has NO Rust support (as of 2026-05), so unlike Go / Python
;; / TypeScript there is deliberately no `combobulate-mode' hook here.

;;; Code:

;; Eglot attaches on `rust-ts-mode' (treesit-auto remaps .rs files to it).
(add-hook 'rust-ts-mode-hook #'eglot-ensure)

;; rust-analyzer: `clippy' as the on-save check (mirrors what you'd run in a
;; terminal) and proc-macros expanded so derive macros stop showing as
;; "unknown".  `closingBraceHints' 25-line threshold matches VSCode's default
;; -- short blocks don't get cluttered.
(with-eval-after-load 'eglot
  (setf (alist-get :rust-analyzer eglot-workspace-configuration)
        '(:checkOnSave (:command "clippy")
          :procMacro (:enable t)
          :cargo (:buildScripts (:enable t))
          :inlayHints (:bindingModeHints (:enable t)
                       :closingBraceHints (:enable t :minLines 25)
                       :parameterHints (:enable t)
                       :typeHints (:enable t)
                       :chainingHints (:enable t)))))

(provide 'init-rust)
;;; init-rust.el ends here
