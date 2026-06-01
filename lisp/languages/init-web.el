;;; init-web.el --- CSS / HTML / JSON (built-in modes + LSP) -*- lexical-binding: t; -*-

;;; Commentary:
;; CSS / HTML / JSON support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot infrastructure lives in
;; [`lisp/init-languages.el'](../init-languages.el); this module only adds the
;; eglot-ensure hooks.
;;
;; These three intentionally use the *built-in* modes (`css-mode', `html-mode'
;; / `mhtml-mode', `js-json-mode'), NOT the *-ts-mode tree-sitter variants:
;; the grammars are simple enough that the regex-based built-ins are accurate,
;; and skipping them sidesteps the tree-sitter ABI treadmill (Emacs 30 caps at
;; ABI 14, tree-sitter-css v0.25+ is ABI 15 -> warnings).  css / json are
;; excluded from `treesit-auto-langs' in init-languages.el for the same reason.
;; Inside .vue files the <style> / <template> blocks are handled by Volar (when
;; enabled) anyway.
;;
;; LSP servers come from one npm package:
;;     npm i -g vscode-langservers-extracted
;; which ships vscode-{html,css,json}-language-server (Eglot's default
;; `eglot-server-programs' already knows about them).

;;; Code:

;; `eglot-ensure' is autoloaded from the eglot package in init-languages.el.
;; `html-mode' covers `mhtml-mode' (derived); `js-json-mode' is the built-in
;; JSON mode.
(add-hook 'css-mode-hook     #'eglot-ensure)
(add-hook 'html-mode-hook    #'eglot-ensure)
(add-hook 'js-json-mode-hook #'eglot-ensure)

(provide 'init-web)
;;; init-web.el ends here
