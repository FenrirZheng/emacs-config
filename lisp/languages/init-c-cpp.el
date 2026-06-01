;;; init-c-cpp.el --- C / C++: c-ts-mode + c++-ts-mode + clangd -*- lexical-binding: t; -*-

;;; Commentary:
;; C / C++ language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / ggtags infrastructure lives in
;; [`lisp/init-languages.el'](../init-languages.el); this module adds the
;; C / C++ mode hooks plus one explicit clangd flag (see below).
;;
;; combobulate is deliberately NOT hooked: it has no C / C++ support.

;;; Code:

;; Eglot attaches `clangd' on the tree-sitter modes (treesit-auto remaps .c /
;; .cc / .cpp / .h files).  `eglot-ensure' is autoloaded from init-languages.el.
(add-hook 'c-ts-mode-hook   #'eglot-ensure)
(add-hook 'c++-ts-mode-hook #'eglot-ensure)

;; Register clangd explicitly with `--inlay-hints'.  Honesty note: clangd >= 14
;; already emits inlay hints BY DEFAULT once the client advertises the
;; `inlayHint' capability (Eglot does, and the global `eglot-inlay-hints-mode'
;; in init-languages.el renders them) -- so this flag is belt-and-suspenders,
;; not a behaviour unlock.  Its real worth is giving C / C++ a per-server entry
;; that future clangd flags can join (mirroring the Go / Rust / TS modules'
;; explicitness, replacing the old "clangd defaults are fine, no entry" stance).
;; The MASTER switch is all the command line controls; FINE-GRAINED hint tuning
;; (parameter names vs. deduced types vs. designators) lives in clangd's own
;; `~/.config/clangd/config.yaml' under `InlayHints:', NOT here.  `add-to-list'
;; prepends, so this wins over Eglot's built-in `("clangd")' default entry.
;; Toggle hints off per-buffer with `C-c h i'.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((c-mode c-ts-mode c++-mode c++-ts-mode)
                 . ("clangd" "--inlay-hints"))))

;; eglot-inactive-regions: dim the inactive `#if' / `#ifdef' branches clangd
;; reports through its `inactiveRegions' extension (clangd >= 17).  Without it,
;; code behind a false preprocessor condition looks live -- you read and edit a
;; branch the compiler discards.  clangd already advertises the regions once the
;; client opts in; this package renders them.
;;
;; `'shadow-face' is the ONLY TTY-correct style: it dims via the theme-relative
;; `shadow' face (the same channel as the Eglot diagnostic-tag dimming in
;; init-languages.el), so the effect survives an 8 / 16-colour terminal.  The
;; alternatives are truecolour-only and collapse on a low-colour TTY:
;; `'darken-foreground' / `'opacity' need 24-bit blending, `'shade-background'
;; paints a background block that fights the theme.  Global minor mode -- it
;; hooks `eglot-managed-mode', so it only acts in buffers with a live server.
;;
;; First-run note: not in elpa/ on a fresh clone -- `M-x my/package-refresh'
;; then restart once so it installs.
(use-package eglot-inactive-regions
  :after eglot
  :custom (eglot-inactive-regions-style 'shadow-face)
  :config (eglot-inactive-regions-mode 1))

;; ggtags: GTAGS xref backend for buffers without a live language server (when
;; Eglot is up it prepends itself to `xref-backend-functions' and wins).  Both
;; the regex and tree-sitter modes are hooked so a machine without the C / C++
;; grammars still gets GTAGS.  `ggtags-mode' is autoloaded from the ggtags
;; declaration in init-languages.el; requires the `gtags' / `global' CLIs.
(add-hook 'c-mode-hook      #'ggtags-mode)
(add-hook 'c-ts-mode-hook   #'ggtags-mode)
(add-hook 'c++-mode-hook    #'ggtags-mode)
(add-hook 'c++-ts-mode-hook #'ggtags-mode)

(provide 'init-c-cpp)
;;; init-c-cpp.el ends here
