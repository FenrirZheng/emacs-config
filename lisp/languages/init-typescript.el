;;; init-typescript.el --- TypeScript / JavaScript / JSX / TSX -*- lexical-binding: t; -*-

;;; Commentary:
;; JS / TS / JSX / TSX language support, split out of the monolithic
;; init-languages.el.  The language-agnostic Eglot / tree-sitter / combobulate
;; infrastructure lives in [`lisp/init-languages.el'](../init-languages.el);
;; this module owns the JS-ecosystem specifics:
;;
;;   * eglot-ensure + combobulate hooks for js-ts-mode / typescript-ts-mode /
;;     tsx-ts-mode.
;;   * `:typescript' + `:javascript' inlay-hint workspace configuration.
;;   * the `vtsls' server override.
;;   * `flymake-eslint' (the package is installed here; init-vue.el also reuses
;;     `flymake-eslint-enable' for .vue files).
;;
;; Node.js / frontend server install (one-time, npm globals):
;;     npm i -g typescript typescript-language-server     ; JS / TS / TSX
;;     npm i -g vscode-langservers-extracted              ; HTML / CSS / JSON / ESLint
;;     npm i -g prettier                                  ; used by apheleia
;;
;; TSX / JSX note: `.tsx' files open in `tsx-ts-mode' (not `typescript-ts-mode'),
;; courtesy of `treesit-auto'.  `.jsx' likewise reuses the TSX parser.  Both are
;; covered by the `tsx-ts-mode' hook below.

;;; Code:

;; Eglot + combobulate attach on all three modes.  treesit-auto opens .ts in
;; typescript-ts-mode, .tsx / .jsx in tsx-ts-mode, .js in js-ts-mode.  The
;; commands are autoloaded from declarations in init-languages.el.
(dolist (hook '(js-ts-mode-hook typescript-ts-mode-hook tsx-ts-mode-hook))
  (add-hook hook #'eglot-ensure)
  (add-hook hook #'combobulate-mode))

;; typescript-language-server / vtsls: parameter + return-type + variable type
;; hints all on.  Servers default these to "none" -- without this block
;; `eglot-inlay-hints-mode' renders nothing in .ts / .tsx buffers.  Both
;; `:typescript' and `:javascript' need the same payload because tsserver
;; routes .js / .jsx through the javascript section, not typescript.
(with-eval-after-load 'eglot
  (setf (alist-get :typescript eglot-workspace-configuration)
        '(:inlayHints (:includeInlayParameterNameHints "all"
                       :includeInlayParameterNameHintsWhenArgumentMatchesName t
                       :includeInlayFunctionParameterTypeHints t
                       :includeInlayVariableTypeHints t
                       :includeInlayVariableTypeHintsWhenTypeMatchesName t
                       :includeInlayPropertyDeclarationTypeHints t
                       :includeInlayFunctionLikeReturnTypeHints t
                       :includeInlayEnumMemberValueHints t)))
  (setf (alist-get :javascript eglot-workspace-configuration)
        '(:inlayHints (:includeInlayParameterNameHints "all"
                       :includeInlayFunctionParameterTypeHints t
                       :includeInlayVariableTypeHints t
                       :includeInlayFunctionLikeReturnTypeHints t)))

  ;; vtsls: VSCode's bundled TypeScript server wrapped in an LSP shim
  ;; (yioneko/vtsls).  Two practical wins over the stock
  ;; `typescript-language-server' (Eglot's default for *-ts-mode):
  ;;   * Implements `textDocument/formatting' -- a project without Prettier
  ;;     can rely on `M-x eglot-format-buffer'.  Apheleia still wins when a
  ;;     project pins Prettier (it's a sibling subprocess, not LSP).
  ;;   * Diagnostics closer to VSCode: catches unused imports, narrows better
  ;;     in conditional blocks, picks up `tsconfig.json' changes without a
  ;;     manual restart.
  ;; Install once: `npm i -g @vtsls/language-server'.  The override is gated on
  ;; `executable-find' so a missing binary silently falls back to the default
  ;; Eglot wiring.  The override claims all three major modes; otherwise
  ;; tsserver would still own .js while vtsls owned .ts, splitting projects
  ;; across two server processes for no benefit.
  (when (executable-find "vtsls")
    (add-to-list 'eglot-server-programs
                 '((typescript-ts-mode tsx-ts-mode js-ts-mode)
                   . ("vtsls" "--stdio")))))

;; flymake-eslint: runs `node_modules/.bin/eslint' on save / change and feeds
;; the JSON diagnostics into Flymake -- so ESLint errors show up next to
;; tsserver's type errors in the same buffer (M-n / M-p walks both).  Why not
;; the LSP ESLint server: Eglot binds one server per major mode and
;; typescript-language-server already owns JS/TS/TSX.  Running ESLint as a
;; sibling Flymake backend sidesteps the multi-server problem entirely.
;;
;; `flymake-eslint-defer-binary-check' (t) skips probing for the `eslint'
;; binary at hook time -- otherwise opening a JS file outside any project
;; (scratch snippet, gist, dotfile) prints a "cannot find eslint" warning.
;; When the binary really is missing, the backend silently no-ops.
;;
;; NOTE: this `use-package' is the single point that INSTALLS flymake-eslint.
;; [`init-vue.el'](init-vue.el) reuses `flymake-eslint-enable' (autoloaded by
;; this package) for .vue files, so it relies on this module being present.
(use-package flymake-eslint
  :hook ((js-ts-mode typescript-ts-mode tsx-ts-mode) . flymake-eslint-enable)
  :custom (flymake-eslint-defer-binary-check t))

(provide 'init-typescript)
;;; init-typescript.el ends here
