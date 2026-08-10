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

;; Pin the tree-sitter-rust grammar to an ABI-14 tag.  Emacs 30.1 caps the
;; tree-sitter ABI at 14 (`treesit-library-abi-version' => 14); tree-sitter-rust
;; master is ABI 15 since v0.24.0, so a freshly-built grammar loads with
;; `(nil version-mismatch 15)' and `rust-ts-mode' silently falls back / errors
;; (same trap that excludes css/json from `treesit-auto-langs' in the core, and
;; that c (init-c-cpp.el) and lua (init-lua.el) pin around the same way).
;; treesit-auto already honours an `abi14-revision' slot per recipe -- it just
;; ships none for rust (it has them for several other langs), so rust defaults to
;; master.  Fill the gap: v0.23.3 is the newest tag still at LANGUAGE_VERSION 14
;; (v0.24.0 is the first ABI-15 tag).  This makes both treesit-auto auto-install
;; and a manual `M-x treesit-install-language-grammar' fetch the ABI-14 grammar.
;; A standalone (Emacs-free) deployer that builds the same pinned grammar lives
;; at [`rust/treesit-grammar/Makefile'](../../rust/treesit-grammar/Makefile)
;; (`make' in that dir) -- keep its GRAMMAR_TAG in sync with the
;; `abi14-revision' below.
(with-eval-after-load 'treesit-auto
  (when-let* ((r (seq-find (lambda (x) (eq (treesit-auto-recipe-lang x) 'rust))
                           treesit-auto-recipe-list)))
    (setf (treesit-auto-recipe-abi14-revision r) "v0.23.3")))

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

;; eglot-x: rust-analyzer's LSP *protocol extensions* surfaced through Eglot.
;; Plain Eglot speaks only standard LSP and silently drops ra's custom requests
;; (macro expansion, cargo runnables, docs.rs, reload-workspace, SSR, move-item,
;; crate graph, MIR/HIR/memory-layout views).  This is THE thing that closes the
;; gap between Eglot-driven Rust and the rustic/lsp-mode experience.
;;
;; GitHub-only -- not on MELPA/ELPA -- so `:vc' like eglot-booster / combobulate
;; (URL recorded in [`custom.el'](../../custom.el) `package-vc-selected-packages').
;;
;; `eglot-x-setup' binds NO keys; it only advises a few Eglot internals to
;; advertise ra's extra client capabilities (negotiated per-server, so non-Rust
;; servers ignore them).  All keys are ours, below.
;;
;; Server-agnostic caveat: `eglot-x-setup' is global, so its file-handling
;; advice is live for every Eglot server (gopls, clangd, ...), not just
;; rust-analyzer.  Lives here (not the core) because its payoff and every
;; binding are Rust; if another language's navigation ever misbehaves, suspect
;; an interaction and verify with `eglot-x--enabled'.
(use-package eglot-x
  :vc (:url "https://github.com/nemethf/eglot-x" :rev :newest)
  :after eglot
  :config
  (eglot-x-setup)
  ;; Rust-analyzer cockpit on `C-c R' (capital R -- distinct from the core's
  ;; lowercase `C-c r' = eglot-rename).  Bound into `rust-ts-mode-map' so these
  ;; ra-only commands never shadow anything in non-Rust Eglot buffers.
  ;;
  ;; LOAD-BEARING `with-eval-after-load': eglot-x is `:after eglot', so this
  ;; `:config' fires the first time ANY language starts Eglot -- e.g. opening a
  ;; Go file launches gopls -> loads `eglot' -> runs this block.  At that
  ;; point `rust-ts-mode-map' is void (rust-ts-mode hasn't loaded), so a bare
  ;; `(define-key rust-ts-mode-map ...)' errors "void: rust-ts-mode-map" on the
  ;; first non-Rust Eglot session.  Defer the keymap wiring until rust-ts-mode
  ;; actually loads (i.e. a Rust buffer is opened).
  (with-eval-after-load 'rust-ts-mode
    (define-prefix-command 'fenrir/rust-x-map)
    (define-key rust-ts-mode-map (kbd "C-c R") 'fenrir/rust-x-map)
    (let ((m 'fenrir/rust-x-map))
      (define-key (symbol-value m) (kbd "e")      #'eglot-x-expand-macro)              ; expand macro at point
      (define-key (symbol-value m) (kbd "r")      #'eglot-x-ask-runnables)             ; cargo run/test/bench, pick
      (define-key (symbol-value m) (kbd "t")      #'eglot-x-ask-related-tests)         ; tests touching this fn
      (define-key (symbol-value m) (kbd "d")      #'eglot-x-open-external-documentation) ; docs.rs for symbol
      (define-key (symbol-value m) (kbd "w")      #'eglot-x-reload-workspace)          ; re-scan Cargo.toml
      (define-key (symbol-value m) (kbd "p")      #'eglot-x-rebuild-proc-macros)       ; rebuild proc-macros
      (define-key (symbol-value m) (kbd "s")      #'eglot-x-structural-search-replace) ; syntax-tree SSR
      (define-key (symbol-value m) (kbd "g")      #'eglot-x-view-crate-graph)          ; dep graph (needs graphviz)
      (define-key (symbol-value m) (kbd "m")      #'eglot-x-view-recursive-memory-layout) ; type memory layout
      (define-key (symbol-value m) (kbd "a")      #'eglot-x-analyzer-status)           ; ra server status
      (define-key (symbol-value m) (kbd "<up>")   #'eglot-x-move-item-up)              ; move fn/struct/variant up
      (define-key (symbol-value m) (kbd "<down>") #'eglot-x-move-item-down))))         ; ... down

(provide 'init-rust)
;;; init-rust.el ends here
