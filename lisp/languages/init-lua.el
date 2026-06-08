;;; init-lua.el --- Lua: lua-ts-mode (+ lua-mode fallback) + lua-language-server -*- lexical-binding: t; -*-

;;; Commentary:
;; Lua language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter infrastructure lives in
;; [`lisp/init-languages.el'](../init-languages.el).
;;
;; Lua uses the built-in tree-sitter `lua-ts-mode' when the grammar is present,
;; and falls back to the regex-based `lua-mode' (MELPA) when it is not -- the
;; same "hook both modes" graceful-degradation pattern as C/C++ in
;; [`init-c-cpp.el'](init-c-cpp.el).  `treesit-auto' remaps lua-mode ->
;; lua-ts-mode once the grammar is installed (and auto-installs it on first
;; visit), so on a machine with the grammar you get tree-sitter font-lock /
;; structural nav, and on one without you still get lua-mode highlighting + Eglot.
;;
;; ABI history (important): tree-sitter-grammars/tree-sitter-lua is ABI 15 at
;; HEAD, and Emacs 30.1 caps at ABI 14, so a grammar built from master loads as
;; `(nil version-mismatch 15)'.  An earlier pass (2026-05-19) concluded "no
;; ABI-14 tag exists" and excluded lua from `treesit-auto-langs' entirely,
;; pinning us to lua-mode.  Re-verified 2026-06-08: that was WRONG -- v0.3.0 is
;; the newest ABI-14 tag (v0.4.0 is the first ABI-15 one).  So lua is back in
;; `treesit-auto-langs' (see init-languages.el) and pinned to v0.3.0 via the
;; `abi14-revision' recipe slot below, exactly like rust (init-rust.el) and c
;; (init-c-cpp.el).

;;; Code:

;; Pin the tree-sitter-lua grammar to its newest ABI-14 tag (v0.3.0; v0.4.0 is
;; the first ABI-15 tag).  treesit-auto's lua recipe points at the right repo
;; (tree-sitter-grammars/tree-sitter-lua) but ships no `abi14-revision', so it
;; would auto-install ABI-15 HEAD -- fill the gap so both treesit-auto and
;; `M-x treesit-install-language-grammar' fetch the ABI-14 grammar.  A standalone
;; (Emacs-free) deployer that builds the same pinned grammar lives at
;; [`rust/treesit-grammar-lua/Makefile'](../../rust/treesit-grammar-lua/Makefile)
;; (`make' in that dir) -- keep its GRAMMAR_TAG in sync with the `abi14-revision'
;; below.
(with-eval-after-load 'treesit-auto
  (when-let* ((r (seq-find (lambda (x) (eq (treesit-auto-recipe-lang x) 'lua))
                           treesit-auto-recipe-list)))
    (setf (treesit-auto-recipe-abi14-revision r) "v0.3.0")))

;; lua-mode (MELPA): regex-based highlighting + the .lua auto-mode association.
;; When the tree-sitter grammar is available, `treesit-auto' remaps lua-mode ->
;; lua-ts-mode (via `major-mode-remap-alist'); when it is not, lua-mode stays.
;;
;; LSP: Eglot attaches `lua-language-server' (LuaLS) on BOTH modes (its default
;; `eglot-server-programs' maps `(lua-mode lua-ts-mode)' to the binary) --
;; go-to-def, hover, workspace symbols, flymake diagnostics.  The server isn't on
;; apt; it's installed from upstream GitHub releases as a self-contained bundle:
;;     ~/.local/share/lua-language-server/    (extracted tarball)
;;     ~/.local/bin/lua-language-server       (symlink to bin/ launcher)
;; `shell/install-user.sh' performs this install on a fresh clone.  If the binary
;; is missing, Eglot just declines to start -- highlighting still works.  No
;; formatter / REPL wired; add `stylua' to `apheleia-mode-alist' if format-on-save
;; is wanted.
(use-package lua-mode
  :mode "\\.lua\\'"
  :hook ((lua-mode lua-ts-mode) . eglot-ensure))

(provide 'init-lua)
;;; init-lua.el ends here
