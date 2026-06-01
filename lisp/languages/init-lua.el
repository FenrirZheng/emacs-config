;;; init-lua.el --- Lua: lua-mode + lua-language-server -*- lexical-binding: t; -*-

;;; Commentary:
;; Lua language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot infrastructure lives in
;; [`lisp/init-languages.el'](../init-languages.el).
;;
;; Lua uses the regex-based `lua-mode' (MELPA), NOT the built-in `lua-ts-mode':
;; upstream tree-sitter-lua is ABI 15 (verified 2026-05-19) and Emacs 30.1 caps
;; at ABI 14, so it's excluded from `treesit-auto-langs' in init-languages.el.
;; We therefore lose tree-sitter font-lock / structural navigation but keep
;; everything else.

;;; Code:

;; lua-mode (MELPA): regex-based highlighting for .lua files.
;;
;; LSP: Eglot attaches `lua-language-server' (LuaLS) via the hook below --
;; go-to-def, hover, workspace symbols, flymake diagnostics.  Eglot 30.1's
;; default `eglot-server-programs' already maps `lua-mode' to the
;; `lua-language-server' binary.  The server isn't on apt; it's installed from
;; upstream GitHub releases as a self-contained bundle:
;;     ~/.local/share/lua-language-server/    (extracted tarball)
;;     ~/.local/bin/lua-language-server       (symlink to bin/ launcher)
;; `shell/install-user.sh' performs this install on a fresh clone.  If the
;; binary is missing, Eglot just declines to start -- highlighting still works.
;; No formatter / REPL wired; add `stylua' to `apheleia-mode-alist' if
;; format-on-save is wanted.
(use-package lua-mode
  :mode "\\.lua\\'"
  :hook (lua-mode . eglot-ensure))

(provide 'init-lua)
;;; init-lua.el ends here
