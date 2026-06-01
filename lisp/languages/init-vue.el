;;; init-vue.el --- Vue: vue-mode (SFC highlighting) -*- lexical-binding: t; -*-

;;; Commentary:
;; Vue Single-File-Component support, split out of the monolithic
;; init-languages.el.  The language-agnostic Eglot / apheleia / flymake
;; infrastructure lives in [`lisp/init-languages.el'](../init-languages.el),
;; and the JS-ecosystem flymake-eslint package is installed by
;; [`init-typescript.el'](init-typescript.el) (this module reuses its
;; autoloaded `flymake-eslint-enable').
;;
;; Eglot is intentionally NOT hooked here -- Vue's LSP options (Volar 3 in
;; "Hybrid Mode") are sluggish on cold start and the per-request jsonrpc
;; timeouts get noisy in any project bigger than a toy.  Tried it (commit
;; acdf8d6, reverted); reach for `M-s r' (consult-ripgrep) for cross-file
;; searches in Vue projects instead -- it catches references uniformly across
;; .vue / .ts / .md, which any LSP scoped to one filetype never can.
;;
;; If you want Volar back: see `git show acdf8d6' for the full wiring
;; (vue-language-server + @vue/typescript-plugin tsserver plugin, tsdk pointer,
;; etc.).  The npm globals (`@vue/language-server', `@vue/typescript-plugin')
;; are left installed -- harmless when unused.

;;; Code:

;; `vue-modes' override: the upstream default points `<script lang="ts">' at
;; `typescript-mode' (the legacy SMIE package, not installed here) and bare
;; `<script>' at `js-mode' (regex-based, no ES2020+).  Without this override TS
;; script blocks fall back to fundamental-mode and look unhighlighted.
;; Retarget to the tree-sitter modes the rest of the config already uses --
;; grammars live in `~/.emacs.d/tree-sitter' (see commit 8968757).
;;
;; flymake-eslint runs on .vue so `eslint-plugin-vue' lints both the <template>
;; and <script> blocks alongside the same ESLint config used elsewhere;
;; flymake-eslint feeds the file as a whole and the plugin handles the SFC
;; split internally.  `flymake-eslint-enable' is autoloaded by the
;; flymake-eslint package installed in init-typescript.el.
(use-package vue-mode
  :mode "\\.vue\\'"
  :hook (vue-mode . flymake-eslint-enable)
  :custom
  (vue-modes
   '((:type template :name nil   :mode vue-html-mode)
     (:type template :name html  :mode vue-html-mode)
     (:type script   :name nil   :mode js-ts-mode)
     (:type script   :name js    :mode js-ts-mode)
     (:type script   :name es6   :mode js-ts-mode)
     (:type script   :name babel :mode js-ts-mode)
     (:type script   :name ts          :mode typescript-ts-mode)
     (:type script   :name typescript  :mode typescript-ts-mode)
     (:type script   :name tsx         :mode tsx-ts-mode)
     (:type style    :name nil    :mode css-mode)
     (:type style    :name css    :mode css-mode)
     (:type style    :name scss   :mode css-mode)
     (:type style    :name postcss :mode css-mode)
     (:type style    :name sass   :mode ssass-mode)
     (:type i18n     :name nil    :mode js-json-mode)
     (:type i18n     :name json   :mode js-json-mode))))

;; Prettier formats .vue SFCs natively (template + script + style in one pass).
;; `apheleia-mode-alist' has no default entry for `vue-mode', so without this
;; nothing fires on save -- add it alongside the other prettier-driven modes.
;; apheleia is loaded eagerly in init-languages.el, so `with-eval-after-load'
;; here runs as soon as this module is required.
(with-eval-after-load 'apheleia
  (add-to-list 'apheleia-mode-alist '(vue-mode . prettier)))

(provide 'init-vue)
;;; init-vue.el ends here
