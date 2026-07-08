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

;; Pin the tree-sitter-c grammar to an ABI-14 tag.  Emacs 30.1 caps the
;; tree-sitter ABI at 14 (`treesit-library-abi-version' => 14); tree-sitter-c
;; jumped to ABI 15 at v0.24.0, so a grammar built from a recent tag loads with
;; `(nil version-mismatch 15)' and `c-ts-mode' refuses to start with
;;   "Cannot activate tree-sitter ... grammar for c is unavailable
;;    (version-mismatch): 15"
;; (the same trap that excludes css/json from `treesit-auto-langs' in the core,
;; and that the rust grammar pins around in `init-rust.el').  treesit-auto
;; honours an `abi14-revision' slot per recipe but ships none for c, so c
;; defaults to master.  Fill the gap: v0.23.6 is the newest tag still at
;; LANGUAGE_VERSION 14 (v0.24.0 is the first ABI-15 tag).  This makes both
;; treesit-auto auto-install and `M-x treesit-install-language-grammar' fetch the
;; ABI-14 grammar.  A standalone (Emacs-free) deployer that builds the same
;; pinned grammar lives at
;; [`rust/treesit-grammar-c/Makefile'](../../rust/treesit-grammar-c/Makefile)
;; (`make' in that dir) -- keep its GRAMMAR_TAG in sync with the `abi14-revision'
;; below.
;;
;; NB: c++ (tree-sitter-cpp) is NOT pinned here -- its current grammar is ABI 14
;; and loads fine.  If a future treesit-auto re-install pulls an ABI-15 cpp and
;; `c++-ts-mode' starts emitting the same warning, add a sibling pin for `cpp'
;; (newest ABI-14 tag) the same way.
(with-eval-after-load 'treesit-auto
  (when-let* ((r (seq-find (lambda (x) (eq (treesit-auto-recipe-lang x) 'c))
                           treesit-auto-recipe-list)))
    (setf (treesit-auto-recipe-abi14-revision r) "v0.23.6")))

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

;; Brace-hop dwim (vim `%'-style), bound to `C-c %' in C / C++ buffers only.
;; combobulate has no C / C++ support (see header), so structural motion here is
;; the built-in sexp navigation -- this is a one-key wrapper that picks the right
;; direction from context instead of remembering C-M-f vs C-M-b:
;;   - point ON an opening bracket  (`([{') -> `forward-sexp'  (land past its match)
;;   - point just AFTER a closer    (`)]}') -> `backward-sexp' (land on its opener)
;;   - otherwise -> scan to the next opener on the line and hop to its match;
;;     with none on the line, fall back to a plain `forward-sexp'.
;; Uses `char-syntax' (not a literal bracket list) so it tracks the major mode's
;; syntax table -- C++ template `<>' are NOT paren-syntax, so they're skipped,
;; which matches clangd / c++-ts-mode behaviour.  Bound on `C-c %' (a free C-c
;; slot; bare `%' is left to self-insert).
(defun fenrir/c-sexp-dwim ()
  "Hop between matching brackets, vim `%'-style.
On an opening bracket jump just past its match; directly after a
closing bracket jump back to its opener; otherwise move to the
next opening bracket on the line and hop to its match (falling
back to `forward-sexp' when the line has none)."
  (interactive)
  (cond
   ((and (char-after)  (eq (char-syntax (char-after))  ?\()) (forward-sexp))
   ((and (char-before) (eq (char-syntax (char-before)) ?\))) (backward-sexp))
   (t (if (re-search-forward "\\s(" (line-end-position) t)
          (progn (backward-char) (forward-sexp))
        (forward-sexp)))))

(with-eval-after-load 'c-ts-mode
  (define-key c-ts-mode-map   (kbd "C-c %") #'fenrir/c-sexp-dwim)
  (define-key c++-ts-mode-map (kbd "C-c %") #'fenrir/c-sexp-dwim))

;; cmake-mode: font-lock + indentation for `CMakeLists.txt' / `*.cmake'.  This
;; config lives in a CMake-driven native-module workspace ([`cpp/'](../../cpp/README.md)
;; is an aggregator CMake tree; every module has its own `CMakeLists.txt'), yet
;; those files open in plain `text-mode' -- no highlighting, no `#'-comment
;; awareness, no indent.  cmake-mode fixes that.
;;
;; Why the regex mode, NOT `cmake-ts-mode': the built-in `cmake-ts-mode' needs
;; the tree-sitter-cmake grammar, which (a) is NOT installed here
;; (`treesit-ready-p 'cmake' => nil') and (b) has an UNPINNED treesit-auto recipe
;; (`abi14-revision' nil), so auto-install would pull master -- risking the same
;; ABI-15 `version-mismatch' trap the c / rust / lua grammars pin around.
;; cmake-mode is pure Elisp font-lock: zero grammar, zero ABI risk, TTY-identical.
;; If a pinned cmake grammar is ever added (mirror the c pin above), this can flip
;; to `cmake-ts-mode' then.
;;
;; First-run note: not in elpa/ on a fresh clone -- `M-x my/package-refresh' then
;; restart once so it installs (the archive isn't refreshed at startup).
(use-package cmake-mode
  :mode (("CMakeLists\\.txt\\'" . cmake-mode)
         ("\\.cmake\\'"         . cmake-mode)))

(provide 'init-c-cpp)
;;; init-c-cpp.el ends here
