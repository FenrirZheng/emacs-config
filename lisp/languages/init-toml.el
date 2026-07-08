;;; init-toml.el --- TOML: toml-ts-mode + taplo LSP -*- lexical-binding: t; -*-

;;; Commentary:
;; TOML support.  `.toml' already maps to the built-in `toml-ts-mode' (the
;; tree-sitter-toml grammar is installed and ABI-14-clean, `treesit-ready-p'
;; => t), and apheleia already ships a `taplo' formatter mapped to
;; `toml-ts-mode' -- so format-on-save works the moment the `taplo' binary is on
;; PATH, with NO config in this module.  What THIS module adds is the LSP:
;; taplo's language server (`taplo lsp stdio') gives schema-aware completion /
;; hover / diagnostics in Cargo.toml, pyproject.toml, and any other TOML (taplo
;; bundles a schema store keyed by filename), which is the daily win for a
;; Rust-heavy workflow editing Cargo.toml.
;;
;; The language-agnostic Eglot infra lives in
;; [`lisp/init-languages.el'](../init-languages.el); this module only adds the
;; mode hook and the server registration, exactly like the sibling language
;; modules (e.g. [`init-rust.el'](init-rust.el)).
;;
;; combobulate / ggtags are deliberately NOT hooked: combobulate has no TOML
;; support, and TOML has no cross-file symbol graph worth a GTAGS index.
;;
;; taplo is NOT on apt -- install with
;;   cargo install taplo-cli --locked --features lsp
;; The `lsp' feature is what enables the `taplo lsp' subcommand; the bare crate
;; ships only the `fmt' / `lint' CLI.  Wired into
;; [`shell/install-user.sh'](../../shell/install-user.sh) section 2.  Without the
;; binary, `toml-ts-mode' still edits + apheleia still formats (once taplo's fmt
;; is present); only the LSP is absent -- Eglot just fails to start quietly, no
;; error spam, so a fresh clone degrades gracefully until the cargo install runs.

;;; Code:

;; Eglot attaches taplo's LSP on `toml-ts-mode' (treesit-auto remaps .toml).
;; `eglot-ensure' is autoloaded from the eglot declaration in init-languages.el.
(add-hook 'toml-ts-mode-hook #'eglot-ensure)

;; Register taplo's language server.  `taplo lsp stdio' speaks LSP over stdio
;; (the transport Eglot drives).  Eglot ships NO toml entry in its default
;; `eglot-server-programs', so this is a pure addition; `add-to-list' prepends
;; it.  eglot-booster (init-languages.el) wraps this stdio connection like every
;; other Eglot server -- it prepends to the PROGRAM part only, so the "lsp"
;; "stdio" args survive.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(toml-ts-mode . ("taplo" "lsp" "stdio"))))

(provide 'init-toml)
;;; init-toml.el ends here
