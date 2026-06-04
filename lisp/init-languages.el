;;; init-languages.el --- Project, LSP & shared language infra -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 8 of the pre-split monolithic init.el (see git log for the move).
;;
;; Originally one giant file holding every language; the per-language config was
;; split into `lisp/languages/init-<lang>.el' modules (loaded after this one --
;; see the require list in [`init.el'](../init.el)).  What stays here is the
;; LANGUAGE-AGNOSTIC infrastructure every language module builds on:
;;   project.el (+ ignore-$HOME advice, cache reset), envrc, the Eglot core
;;   (settings / glyphs / faces / debug toggles -- but NOT per-language hooks or
;;   workspace-config), eglot-booster, consult-eglot, xref, breadcrumb, eldoc
;;   routing, ggtags (package only -- hooks live per language), treesit-auto,
;;   combobulate (package only -- hooks live per language), flymake, sideline,
;;   apheleia, dape.
;;
;; The per-language modules attach their own hooks via `add-hook' /
;; `use-package' and register their server's `eglot-workspace-configuration'
;; entry via `(with-eval-after-load 'eglot (setf (alist-get :SERVER ...) ...))'.
;; This module MUST load before them (it declares the eglot / combobulate /
;; ggtags packages whose autoloaded commands those hooks reference).

;;; Code:

;; project.el (built-in): project-aware file/buffer/command commands under C-x p.
;; ~/ itself is a git repo (the dotfiles tree).  Two interacting problems:
;;   1. project.el would otherwise treat all of $HOME as one giant project and
;;      project-find-file would walk the whole home directory.  Fixed by the
;;      :around advice on `project-try-vc' that returns nil when the root is
;;      $HOME -- or the filesystem root `/' (the latter also dodges a breadcrumb
;;      crash on /tmp buffers; see the advice's docstring).
;;   2. Sub-directories inside the dotfiles repo that don't have their own .git
;;      (e.g. ~/.emacs.d/, ~/.config/<foo>/) would also be killed by (1) because
;;      `vc-find-root' walks up to ~/.git.  Fixed by `project-vc-extra-root-markers':
;;      if any of those marker files exists in a closer ancestor, that ancestor
;;      becomes the project root, the advice sees a non-$HOME root, and lets it
;;      through.  Drop an empty `.project' file in any dir you want treated as
;;      a project (or rely on the language-native markers below).
;;
;; Java needs an even earlier hook than `project-vc-extra-root-markers' (Eclipse
;; m2e regenerates `.project' inside every module, defeating the deepest-wins
;; markers heuristic); its `fenrir/project-find-java-build-root' is prepended to
;; `project-find-functions' from [`languages/init-java.el'](languages/init-java.el).
(use-package project
  :ensure nil
  :custom
  (project-vc-extra-root-markers
   '(".project"          ; explicit opt-in marker for arbitrary directories
     "Cargo.toml"        ; Rust
     "go.mod"            ; Go
     "pyproject.toml"    ; Python (PEP 518)
     "CLAUDE.md"
     "package.json"      ; Node
     "Makefile"))        ; generic
  :config
  (defun my-project-ignore-home (orig-fun dir)
    "If `project-try-vc' would return $HOME or the filesystem root, ignore it.
$HOME is the dotfiles repo (~1500 tracked files) -- treating it as a project
makes `project-find-file' walk the whole home directory.  `/' is
`project-try-vc' degenerating when DIR has no VCS root anywhere above it (e.g.
a buffer under /tmp): besides the same runaway-walk risk, a `/' root makes
`breadcrumb--project-crumbs-1' build an empty-string base crumb -- and an
empty string cannot carry the `bc-dont-shorten' text property, so
`breadcrumb--summarize' wrongly tries to `(substring \"\" 0 1)' and signals
`args-out-of-range', uncaught, during `normal-mode' -- which aborts the whole
`find-file' (cf. the filesystem-root note on `fenrir/gtags-forbidden-roots'
below, the gtags-side guard against the same degeneration)."
    (let ((proj (funcall orig-fun dir)))
      (if (and proj
               (member (expand-file-name (project-root proj))
                       (list (expand-file-name "~/") "/")))
          nil
        proj)))
  (advice-add 'project-try-vc :around #'my-project-ignore-home))

;; `project-try-vc' caches its search result on each `dir' via `vc-file-setprop'
;; (see project.el's own FIXME at the top of the defun).  That means changes to
;; `project-vc-extra-root-markers' don't retroactively re-detect already-visited
;; directories -- a daemon that first saw ~/code/foo/ before CLAUDE.md was in
;; the markers list keeps returning the old (vc Git "~/") answer forever.  This
;; helper replaces the whole obarray so the next access recomputes from scratch.
;; Emacs 30 made obarray a distinct type (no longer a vector), so we go through
;; `obarray-make' rather than `fillarray'.  Used by the Java workspace-marker
;; commands in `languages/init-java.el'.
(defun fenrir/project-reset-cache ()
  "Wipe all `vc-file-setprop' caches.  Use after editing
`project-vc-extra-root-markers' or any time project root detection
seems stuck on a stale answer."
  (interactive)
  (setq vc-file-prop-obarray (obarray-make 17))
  (message "vc-file-prop-obarray cleared"))

;; envrc: direnv integration -- when you enter a buffer whose file lives under
;; a directory with an `.envrc', envrc runs `direnv export json' and applies
;; the resulting env vars BUFFER-LOCALLY (sets `process-environment' and
;; `exec-path' just in that buffer).  Two concrete wins on this setup:
;;   * Eglot picks the right server binary per project -- e.g. a Go monorepo
;;     pinning `PATH=./bin:$PATH' in its .envrc gets that repo's gopls, not
;;     the global one harvested by `exec-path-from-shell' at startup.
;;   * Node projects using `nvm' / `volta' / `asdf' switch versions per
;;     project, so apheleia/prettier and `M-x compile' run the right tool.
;;
;; Why buffer-local matters: `exec-path-from-shell' (section 1) is a one-shot
;; global harvest at daemon launch -- great for "Emacs needs to see my login
;; PATH", useless for "this project needs a different toolchain than that
;; one".  envrc is the per-project complement, not a replacement.
;;
;; Loaded as a global mode (only enables in buffers under a direnv-allowed
;; dir, so it's free in $HOME or unrelated buffers).  Requires the `direnv'
;; binary on PATH (`apt install direnv'); without it the mode silently
;; no-ops.  Per-project setup: drop an `.envrc', then `direnv allow' once.
(use-package envrc
  :hook (after-init . envrc-global-mode))

;; Eglot (built-in since Emacs 29): a small, zero-config LSP client.  It
;; auto-starts when you open a file in a supported mode AND a language server
;; binary is on PATH (gopls, pyright, rust-analyzer, typescript-language-server,
;; clangd, ...).  Reach for `lsp-mode' only if you need its heavier extras.
;;
;; This block holds only the language-AGNOSTIC eglot setup.  Each language's
;; `eglot-ensure' hook and its `eglot-workspace-configuration' entry live in the
;; matching `languages/init-<lang>.el' module: those hooks call `eglot-ensure'
;; (autoloaded from the package installed here), and each module appends its
;; server's config to the shared `eglot-workspace-configuration' alist via
;; `(with-eval-after-load 'eglot (setf (alist-get :SERVER ...) ...))'.
;;
;; Eglot is UPGRADED from the copy bundled with Emacs 30.1 to the GNU ELPA
;; release (`:ensure t', not `:ensure nil').  Why: native call hierarchy and
;; type hierarchy (`eglot-show-call-hierarchy' / `eglot-show-type-hierarchy',
;; bound below) only landed in Eglot 1.19 (2025-10); the bundled 30.1 copy has
;; no client code for `callHierarchy/*' at all, so jdtls / gopls / rust-analyzer
;; advertising those server-side was unreachable -- "server answers, client
;; never asks".  Gotcha: `:ensure t' ALONE cannot upgrade a built-in package --
;; use-package's ensure gates on `package-installed-p', which is already t for a
;; bundled package, so it never reaches `package-install'.  The real upgrade
;; needs `package-install-upgrade-built-in' (set in init.el) plus a ONE-TIME
;; `M-x package-install RET eglot' on a fresh clone (elpa/ is gitignored) -- see
;; CLAUDE.md "Eglot upgraded to the GNU ELPA release".  eglot-booster's
;; `eglot--connect' / `jsonrpc--json-read' advice was verified to still apply
;; against 1.23, so the booster keeps working across the bump.
(use-package eglot
  :ensure t
  ;; Inlay hints: parameter names, inferred types, `&` references etc. rendered
  ;; inline by the language server.  Built-in in Emacs 30 -- no external package.
  ;; `eglot-managed-mode' fires once Eglot has attached to ANY buffer (every
  ;; language's `eglot-ensure' eventually lands there), so this single line
  ;; covers all hooked languages.  Toggle per-buffer at runtime with
  ;; `M-x eglot-inlay-hints-mode'.  If a specific language's hints turn out too
  ;; noisy, disable in that mode's hook (in its `languages/init-<lang>.el')
  ;; rather than globally.
  :hook (eglot-managed-mode . eglot-inlay-hints-mode)
  :custom
  (eglot-autoshutdown t)                 ; kill the server when its last buffer closes
  ;; Don't log the (huge) JSON-RPC traffic.  The old defcustom name
  ;; `eglot-events-buffer-size' went obsolete in Eglot 1.16 (Emacs 30.x);
  ;; the replacement is a plist with `:size' (bytes, 0 = disabled) and
  ;; `:format' (`full' / `lisp' / `short' -- controls how messages are
  ;; pretty-printed when logging IS on).  Toggle live via
  ;; `fenrir/eglot-debug-on' / `-off' below.
  (eglot-events-buffer-config '(:size 0 :format full))
  ;; Block up to 1s for the server's initial handshake before returning
  ;; control; longer than that, finish async.  Default `nil' means "wait
  ;; forever synchronously" which freezes the UI while gopls indexes a big
  ;; monorepo.
  (eglot-sync-connect 1)
  ;; Total timeout for the TCP/stdio handshake (default 30s is fine; spelled
  ;; out so the value is visible next to its siblings).
  (eglot-connect-timeout 30)
  ;; Let `xref-find-definitions' (M-.) follow into vendored / library files
  ;; the LSP knows about, even when those files have no Eglot session of
  ;; their own.  Default `nil' silently stops at the project boundary.
  (eglot-extend-to-xref t)
  ;; Server-initiated `applyEdit' requests (organize-imports, project-wide
  ;; rename, batch quickfix code actions) hit multiple files at once.
  ;; Default `'confirm' prompts per file -- noisy for any rename that
  ;; touches more than three.  Set to nil so refactors apply in one go;
  ;; the aggregate diff still lands in `git diff' for review before commit.
  (eglot-confirm-server-initiated-edits nil)
  ;; IDE refactor / action keys, all scoped to `eglot-mode-map' so they do
  ;; nothing in non-LSP buffers and never shadow a major mode's own `C-c'
  ;; keys when no server is attached.
  ;;
  ;;   `C-c .'  -- `eglot-code-actions': the unified Quick-Fix transient
  ;;               (VSCode `Ctrl+.').  `C-.' is already `embark-act' globally
  ;;               (init-completion), so the `C-c' prefix sidesteps that clash.
  ;;   `C-c r'  -- `eglot-rename': project-wide rename (VSCode F2 / IntelliJ
  ;;               Shift-F6).  `eglot-confirm-server-initiated-edits nil' above
  ;;               makes the multi-file apply land in one go.
  ;;   `C-c i'  -- `eglot-code-action-organize-imports' (VSCode Shift-Alt-O):
  ;;               the single most-used code action for Java / Go / TS, lifted
  ;;               out of the `C-c .' transient onto its own key.
  ;;   `C-c x'  -- `eglot-code-action-extract': extract method / variable
  ;;               (server-dependent -- rich in jdtls / rust-analyzer, sparse
  ;;               in gopls).
  ;;   `C-c f'  -- `eglot-format': format region (if active) else buffer, ON
  ;;               DEMAND only.  apheleia owns format-on-save (see the apheleia
  ;;               block below); this key is the manual escape hatch for buffers
  ;;               with no apheleia formatter.  It is deliberately NOT added to
  ;;               `before-save-hook' -- doing so would double-format against
  ;;               apheleia and reintroduce a synchronous save-time cursor jump.
  ;;
  ;; NOTE: these refactor keys are intentionally NOT placed under the `C-c o'
  ;; prefix -- that prefix belongs to combobulate (`combobulate-key-prefix',
  ;; see its block below; `C-c o n' is combobulate-rename) and would collide in
  ;; any buffer where both minor modes are live (Java, Python, ...).
  ;;
  ;; Call / type hierarchy (native, Eglot 1.19+ -- see the `:ensure t' note at
  ;; the top of this block).  `C-c h c' = call hierarchy (callers / callees as an
  ;; interactive tree), `C-c h t' = type hierarchy (super- / sub-types).  jdtls,
  ;; gopls and rust-analyzer all implement these server-side.  Two per-buffer
  ;; display toggles share the `C-c h' ("hierarchy / hints") cluster:
  ;;   `C-c h i' -- `eglot-inlay-hints-mode': flip inlay hints off/on in this
  ;;                buffer.  Hints are globally default-on via the
  ;;                `eglot-managed-mode' hook above; this is the quiet-it-down key
  ;;                for a dense file.
  ;;   `C-c h s' -- `eglot-semantic-tokens-mode' (native, Eglot 1.20+):
  ;;                server-driven semantic highlighting.  Per-buffer opt-in, NOT
  ;;                a global hook -- it can fight tree-sitter font-lock and on an
  ;;                8/16-colour TTY the extra face distinctions collapse, so its
  ;;                value is real only on a truecolour terminal.
  :bind (:map eglot-mode-map
              ("C-c ." . eglot-code-actions)
              ("C-c r" . eglot-rename)
              ("C-c i" . eglot-code-action-organize-imports)
              ("C-c x" . eglot-code-action-extract)
              ("C-c f" . eglot-format)
              ("C-c h c" . eglot-show-call-hierarchy)
              ("C-c h t" . eglot-show-type-hierarchy)
              ("C-c h i" . eglot-inlay-hints-mode)
              ("C-c h s" . eglot-semantic-tokens-mode)))

;; Call-hierarchy glyphs (TTY: pure text, no image theme -- all frames here are
;; `emacsclient -nw').  Two independent layers in the `*EGLOT call hierarchy*'
;; buffer:
;;  (A) The direction bullets (` <- ' incoming / ` -> ' outgoing) are BAKED into
;;      `eglot-show-call-hierarchy' by the internal `eglot--define-hierarchy-
;;      command' macro -- there is no defcustom or variable seam.  Override by
;;      re-expanding the SAME macro with new bullet strings (this is exactly how
;;      Eglot defines the command, so it tracks Eglot's own rendering).  The
;;      `(eval '(...) t)' wrapper defers macroexpansion to RUNTIME: a bare macro
;;      call here would be expanded when this module is byte-compiled, at which
;;      point Eglot may be unloaded -> "function definition void".  Only call
;;      hierarchy is touched; type hierarchy keeps its ` up '/` down ' arrows.
;;  (B) The [+]/[-]/[X] expand toggles come from built-in `tree-widget' icon
;;      `:tag's.  Eglot maps each node's :empty-icon to its :leaf-icon, so the
;;      leaf icon (not the empty icon) governs childless expanded nodes.  NOTE:
;;      redefining these widgets is GLOBAL -- it restyles every `tree-widget' UI
;;      and Eglot's type-hierarchy toggles too (no per-buffer seam without
;;      advising `eglot--hierarchy-2', not worth the surface).
(with-eval-after-load 'eglot
  (eval '(eglot--define-hierarchy-command
          eglot-show-call-hierarchy "call"
          :callHierarchyProvider :textDocument/prepareCallHierarchy
          ((:callHierarchy/incomingCalls " ⮜ " incoming "incoming calls" "called by"
                                         :from :fromRanges)
           (:callHierarchy/outgoingCalls " ⮞ " base "outgoing calls" "calls"
                                         :to :fromRanges)))
        t))

(with-eval-after-load 'tree-widget
  (define-widget 'tree-widget-open-icon  'tree-widget-icon "" :tag "▾" :glyph-name "open")
  (define-widget 'tree-widget-close-icon 'tree-widget-icon "" :tag "▸" :glyph-name "close")
  (define-widget 'tree-widget-leaf-icon  'tree-widget-icon "" :tag "·" :glyph-name "leaf")
  (define-widget 'tree-widget-empty-icon 'tree-widget-icon "" :tag "·" :glyph-name "empty"))

;; Diagnostic-tag faces (TTY visibility).  LSP servers tag certain diagnostics
;; semantically instead of erroring: tag 1 = `Unnecessary' (unused import /
;; local / unreachable branch), tag 2 = `Deprecated' (@Deprecated API).  Eglot
;; renders them with the two faces below (eglot.el `eglot--tag-faces'), both
;; defaulting to `:inherit shadow' -- which on a low-contrast TTY theme can be
;; invisible, making the feature look dead.  Keep the theme-relative dimming
;; (inherit shadow tracks the active theme) but add a SECOND visual channel --
;; italic for unused, strike-through for deprecated -- so the signal survives
;; even when `shadow' barely differs from the background.  These are eglot-wide
;; faces (every language, not just Java).  `with-eval-after-load' so the faces
;; exist (defined by eglot's defface) before we override them.
(with-eval-after-load 'eglot
  (set-face-attribute 'eglot-diagnostic-tag-unnecessary-face nil
                      :inherit 'shadow :slant 'italic)
  (set-face-attribute 'eglot-diagnostic-tag-deprecated-face nil
                      :inherit 'shadow :strike-through t))

;; Events-buffer debug toggle.  `eglot-events-buffer-config' is set to
;; `:size 0' above (no logging) -- when a server hangs, returns nonsense,
;; or you want to inspect a specific JSON-RPC message, flip these on, repro
;; the issue, then visit the `*EGLOT events*' buffer.  Both helpers
;; reconnect the current session so the new size takes effect (Eglot reads
;; the config when the events buffer is materialised, not per message).
(defun fenrir/eglot-debug-on ()
  "Turn ON Eglot's JSON-RPC events log (2MB) and reconnect."
  (interactive)
  (setq eglot-events-buffer-config '(:size 2000000 :format full))
  (when (eglot-current-server) (eglot-reconnect (eglot-current-server)))
  (message "eglot: events log ON (2MB); reconnected"))

(defun fenrir/eglot-debug-off ()
  "Turn OFF Eglot's JSON-RPC events log and reconnect."
  (interactive)
  (setq eglot-events-buffer-config '(:size 0 :format full))
  (when (eglot-current-server) (eglot-reconnect (eglot-current-server)))
  (message "eglot: events log OFF"))

;; eglot-booster: speed up Eglot by routing the LSP server's stdio through
;; `emacs-lsp-booster' (Rust binary, blahgeek/emacs-lsp-booster v0.2.1).
;; Two mechanisms:
;;   1. Threaded I/O on the booster side -- Emacs no longer blocks the UI
;;      waiting for a slow server response.  Win regardless of message size.
;;   2. JSON -> Elisp bytecode pre-parse -- `read' on bytecode beats
;;      `json-parse-string' on Emacs 29.  Win SHRINKS on Emacs 30 (native
;;      parser already fast); still meaningful for large payloads:
;;      `consult-eglot-symbols' workspace/symbol responses, gopls hovers on
;;      heavy structs, rust-analyzer full type info, workspace diagnostics.
;;      Tiny per-keystroke completion deltas may go marginally SLOWER -- if
;;      that's perceptible, add `--disable-bytecode' via
;;      `eglot-booster-no-remote-boost' / `eglot-booster-program-args' to
;;      keep the threaded-I/O win without the bytecode trick.
;;
;; Trust posture (decided 2026-05-18): built from source via
;; `cargo install --locked --version 0.2.1 emacs-lsp-booster' rather than
;; downloading the pre-built release binary.  `--locked' pins every
;; transitive dep to the upstream Cargo.lock SHA, eliminating
;; compiler-supply-chain ambiguity in the prebuilt zip.  Trade: 3-5 min
;; compile on first install.  Binary lands at ~/.cargo/bin/, on PATH via
;; rustup.
;;
;; Compatibility: monkey-patches `eglot--connect'.  Built-in Eglot evolves
;; with Emacs releases; an Emacs upgrade may break the patch (historically
;; fixed quickly upstream).  If broken: `M-x eglot-booster-mode' to disable
;; at runtime, no permanent harm.  All LSP servers this config talks to
;; (pyright, gopls, rust-analyzer, typescript-language-server, vscode-*,
;; clangd) use stdio JSON-RPC and are compatible.
;;
;; Source GitHub-only, installed via Emacs 30's `:vc' keyword (same pattern
;; as combobulate below).  Update later: `M-x package-vc-upgrade RET
;; eglot-booster RET'.
(use-package eglot-booster
  :vc (:url "https://github.com/jdtsmith/eglot-booster" :rev :newest)
  :after eglot
  :config (eglot-booster-mode 1))

;; consult-eglot: project-wide LSP symbol search via `workspace/symbol'.
;;
;; Fills a gap in the consult bindings (section 4): `consult-imenu' is THIS
;; file only, `consult-imenu-multi' is the currently-open buffers of the
;; same major mode -- neither sees a symbol in a file you haven't visited
;; yet.  `consult-eglot-symbols' asks the running language server for every
;; symbol in the project's index, so you can jump to `NewFooBar' in a Go
;; monorepo without opening its file first.  Same vertico + orderless +
;; marginalia UI as the rest of the minibuffer stack.
;;
;; Bound on `M-g s' ("goto symbol") only inside `eglot-mode-map' -- the key
;; is meaningless in non-LSP buffers, and scoping the binding avoids
;; shadowing whatever a future major mode might want on `M-g s'.  Needs an
;; Eglot session live in the current buffer; in a buffer without one, the
;; command errors out clearly rather than silently returning nothing.
;; (`languages/init-java.el' advises `consult-eglot--transformer' to survive
;; jdt:// results.)
(use-package consult-eglot
  :after (consult eglot)
  :bind (:map eglot-mode-map
              ("M-g s" . consult-eglot-symbols)))

;; xref backend tuning -- affects M-. (find-definitions) and M-? (find-
;; references) across both LSP and non-LSP buffers.
;;   * `xref-search-program' picks the search engine for
;;     `xref-find-references' / `xref-find-apropos' when there's no
;;     LSP / GTAGS backend on the buffer.  Default is `grep'; switch to
;;     `ripgrep' to align with the project-wide rg/fdfind mandate
;;     (CLAUDE.md, "Tool Preferences").  Pure speedup -- no UI change.
;;   * `xref-show-xrefs-function' / `xref-show-definitions-function'
;;     replace the default *xref* list buffer with consult's minibuffer
;;     UI -- vertico + orderless + live preview, same look and ergonomics
;;     as `consult-imenu' (M-g i) and `consult-eglot-symbols' (M-g s).
;;     `consult-xref' is autoloaded by `consult', so no extra `:after'
;;     wiring needed; the function symbol resolves on first xref hit.
(use-package xref
  :ensure nil
  :custom
  (xref-search-program 'ripgrep)
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref))

;; breadcrumb: header-line "module > class > method" path of the location
;; at point -- VSCode's breadcrumb bar.  Backed by imenu (regex /
;; structural) and, when Eglot is attached, LSP `textDocument/document-
;; Symbol'.  So the path reflects the same symbol tree `consult-imenu'
;; (M-g i) and `consult-eglot-symbols' (M-g s) walk, just rendered as a
;; persistent header instead of a transient minibuffer list.
;;
;; Why this works on TTY frames: header-line is a buffer-local STRING,
;; not a fringe glyph or child frame.  Renders identically in
;; `emacsclient -nw' and a GUI frame.  Same author as Eglot
;; (joaotavora), so the LSP integration tracks Eglot's documentSymbol
;; output without a custom adapter.
;;
;; Hooked on `prog-mode' only -- text-mode (org / markdown) has its own
;; heading-navigation surfaces (`org-mode' outline, `consult-outline')
;; and a redundant breadcrumb would clash visually in long org buffers.
;; (`languages/init-java.el' advises `breadcrumb-project-crumbs' to skip
;; jdt:// buffers.)
(use-package breadcrumb
  :hook (prog-mode . breadcrumb-local-mode))

;; eldoc on TTY: echo area is the default display path (single line, brief,
;; gets clobbered by Corfu / other `message' callers but cheap and unobtrusive).
;; For longer signatures or godoc-on-hover, summon `M-x eldoc-doc-buffer'
;; on demand -- the `display-buffer-alist' entry below docks it as a 60-col
;; side window on the right.  No auto-pop; the side window only appears
;; when you ask for it.
;;
;; Why not eldoc-box: child frames are GUI-only.  In TTY frames (our default,
;; Emacs runs in tmux) eldoc-box silently no-ops AND bypasses the echo area
;; fallback, so the user sees nothing at all.
(setq eldoc-echo-area-use-multiline-p t)

;; Multiple eldoc sources can be live at the same point: Eglot hover, Flymake
;; at point, the major mode's own ElDoc (e.g. emacs-lisp-mode signature info).
;; Default strategy `eldoc-documentation-default' shows ONLY the first source
;; that returns content -- the rest are silently dropped.  `compose' renders
;; them all, separated, in the doc buffer.  Concretely: a line with both a
;; flymake error AND a function-signature hover now shows both at once when
;; you hit `C-c d' (the docked side window from above renders multi-source
;; content cleanly; the single-line echo area still truncates).
(setq eldoc-documentation-strategy #'eldoc-documentation-compose)

;; Eldoc names its dedicated doc buffer " *eldoc for SYMBOL*" with a leading
;; space (Emacs' "hidden internal buffer" convention).  Once `eldoc-doc-buffer'
;; is called interactively the buffer is renamed to drop the leading space.
;; Match both forms.
(add-to-list 'display-buffer-alist
             `(,(rx bos (? " ") "*eldoc")
               (display-buffer-in-side-window)
               (side . right)
               (window-width . 60)
               (slot . 1)
               (window-parameters . ((no-other-window . t)))))

;; On-demand summon: cursor anywhere with eldoc content, hit `C-c d' to dock
;; the full doc in the side window.  No prefix arg needed; `eldoc-doc-buffer'
;; is its own command and reads `eldoc--doc-buffer' (buffer-local) to find
;; the right doc buffer.
(global-set-key (kbd "C-c d") #'eldoc-doc-buffer)

;; ggtags: xref backend for GNU Global's binary `GTAGS' index.
;;
;; Without this, `xref-find-references' (M-?) in a non-LSP buffer falls
;; through to the built-in etags backend.  Etags walks parent directories
;; looking for a plain-text `TAGS' file, picks up a `GTAGS' file (binary,
;; GNU Global's format) by name match, and signals:
;;     File .../GTAGS is not a valid tags table
;; Worse, `tags-file-name' is buffer-local-when-set: a stray
;; `visit-tags-table' (or a misbehaving package) can bind it to the
;; current source file, after which every M-? in that buffer crashes
;; with "File CaptchaType.java is not a valid tags table".  ggtags
;; registers `ggtags--xref-backend' on `xref-backend-functions', which
;; reads GTAGS correctly and short-circuits the etags fallback.
;;
;; Eglot, when active, prepends itself to `xref-backend-functions' and
;; wins -- so the ggtags hooks (in `languages/init-c-cpp.el' and
;; `languages/init-python.el') only matter in buffers without a running
;; language server.  This block only DECLARES the package (autoloading
;; `ggtags-mode'); the per-language `add-hook' calls live in those modules.
;;
;; First-run note: as with all use-package blocks here, the archive isn't
;; refreshed at startup.  If ggtags isn't installed yet, `M-x my/package-refresh'
;; then restart Emacs once.  Also requires the `gtags' / `global' CLIs
;; (apt: `global'; for Go/Python/TS coverage also `python3-pygments' and
;; `universal-ctags').  Run `gtags' at a repo root to generate the index.
;;
;; The "seems corrupted" failure has TWO distinct 0-byte causes, neither of
;; which is "indexing a source-less monorepo top dir" (the original guess):
;;   1. An aborted/crashed gtags run -- gtags creates GTAGS/GRTAGS/GPATH on
;;      disk, then the external parser helper FAILS at build time (missing
;;      interpreter, crashed ctags, broken PATH in the subprocess) -> gtags
;;      reads back empty parser output, dies with "unexpected EOF", and leaves
;;      all three files at 0 bytes.  Every later `global -u' / `gtags -i' then
;;      rejects that 0-byte stub with "<path>/GTAGS seems corrupted." (the
;;      user's exact error in ~/code/coinsasia/backend/).
;;   2. (Separate, NOT corrupt) A Go-BLIND label: gtags' built-in parser langmap
;;      is only c/yacc/asm/java/cpp/php, and ggtags' own "Use `ctags' backend?"
;;      prompt sets GTAGSLABEL=ctags -> exuberant-ctags, also Go-blind.  Both
;;      produce a VALID 16 KB index with ZERO Go symbols -- structurally fine,
;;      useless.  Go/Python/TS need GTAGSLABEL=pygments (this config's default,
;;      see `fenrir/gtags-label'), or new-ctags (Universal Ctags, but it MISSES
;;      TypeScript).
;; The conf that DEFINES those labels ships at /etc/gtags/gtags.conf on Debian
;; (the [sysconfdir] path, baked into the gtags binary's search order), so
;; pygments/new-ctags resolve with NO env vars -- no ~/.globalrc or repo-local
;; gtags.conf is generated.  The durable defenses are post-build validation +
;; corrupt-index recovery + a Go-capable label, not the pre-build file count.
;; gtags-on-Go is a FALLBACK: gopls is strictly better -- see `fenrir/gtags--go-dominant-p'.
(use-package ggtags
  :commands ggtags-mode)

;; Neutralize ggtags' own M-. / C-M-. so `ggtags-mode' contributes ONLY its xref
;; backend, never a keymap takeover.  WHY this is load-bearing: `ggtags-mode' is
;; a minor mode whose `ggtags-mode-map' binds M-. -> `ggtags-find-tag-dwim' and
;; C-M-. -> `ggtags-find-tag-regexp'.  Those minor-mode bindings SHADOW the
;; global M-. / C-M-. (`xref-find-definitions' / `xref-find-apropos'), and
;; `ggtags-find-tag-dwim' shells out to `global' DIRECTLY -- it never consults
;; `xref-backend-functions'.  So in any buffer where both Eglot and ggtags-mode
;; are live (every C/C++/Python/Go/TS buffer with a server AND a GTAGS index),
;; bare ggtags-mode would route M-. to gtags and silently bypass Eglot -- the
;; "Eglot, when active, prepends itself and wins" invariant above only holds for
;; xref DISPATCH, which M-. never reaches once ggtags grabs the key.  Unbinding
;; both keys returns M-. / C-M-. to the global xref commands, which dispatch over
;; `xref-backend-functions' where Eglot prepends (wins when attached) and
;; `ggtags--xref-backend' answers as the fallback when no server is up.  M-? / M-,
;; are left alone -- this ggtags version never bound them, so references already
;; flow through xref.  (`ggtags-mode-map' also adds the gtags-only M-] and its
;; C-c prefix map; those collide with nothing and stay.)
(with-eval-after-load 'ggtags
  (define-key ggtags-mode-map (kbd "M-.") nil)
  (define-key ggtags-mode-map (kbd "C-M-.") nil))

;; Defensive: keep the etags fallback's globals empty so a stray
;; `visit-tags-table' can't seed them with a binary GTAGS file or a Java
;; source.  Both default to nil already; the explicit setq-default
;; documents the invariant and re-asserts it after any package that
;; auto-sets them on load.
(setq-default tags-file-name nil
              tags-table-list nil)

;; ---------------------------------------------------------------------------
;; GTAGS-on-demand: guide M-. / M-? in a non-LSP, un-indexed project to build a
;; GNU Global index instead of dumping the cryptic etags "Visit tags table"
;; prompt.
;;
;; THE PROBLEM.  `xref-find-definitions' (M-.) and `xref-find-references' (M-?)
;; dispatch over `xref-backend-functions'.  Three backends matter here:
;;   * Eglot prepends `eglot-xref-backend' ONLY while a server is attached.
;;   * ggtags adds `ggtags--xref-backend' while `ggtags-mode' is on -- BUT that
;;     backend returns nil (declines) when `ggtags-find-project' finds no GTAGS
;;     index, so an un-indexed buffer falls straight through it.
;;   * `etags--xref-backend' is the always-present global fallback.  Its methods
;;     call `visit-tags-table-buffer', which -- finding no `tags-file-name' /
;;     `tags-table-list' (we nil them above) and no TAGS file -- reaches its last
;;     resort: (read-file-name "Visit tags table (default TAGS): ...").  That
;;     prompt is meaningless to anyone who isn't running a 1990s etags workflow.
;;
;; THE FIX.  Two pieces, both Eglot-safe by construction:
;;   (a) `fenrir/gtags-create-or-update' (C-c g g) -- an explicit, project-aware
;;       command that builds or incrementally refreshes the index.  Never touches
;;       xref dispatch; safe to run anywhere.
;;   (b) an :around advice on `visit-tags-table-buffer' that, INSTEAD of the
;;       etags prompt, offers to run (a).  It can only ever fire AFTER the etags
;;       backend was already chosen -- which already means no Eglot and no usable
;;       GTAGS -- but we still re-check Eglot defensively so a future caller of
;;       `visit-tags-table-buffer' from within a managed buffer can't be hijacked.
;;
;; Rejected alternative: globalizing `ggtags-mode' so its own create-offer
;; (`ggtags-ensure-project', reached via `ggtags-find-tag-dwim') fires.  That
;; rebinds M-. to `ggtags-find-tag-dwim' in EVERY buffer, shadowing Eglot's xref
;; M-. wherever both modes are live -- a direct violation of "Eglot must keep
;; winning".  Advising the etags fallback leaves Eglot's and ggtags' own xref
;; paths completely untouched.

(defun fenrir/gtags--global-available-p ()
  "Return non-nil iff both GNU Global CLIs (`gtags' and `global') are on PATH.
gtags BUILDS the index; global QUERIES it -- ggtags shells out to both, so a
half-install (only one present) still leaves xref broken.  We check both up
front to give one clear install hint instead of a later cryptic process error."
  (and (executable-find "gtags") (executable-find "global")))

(defun fenrir/gtags--guide-install ()
  "Tell the user how to install GNU Global, then return nil.
Returning nil lets callers treat \"no toolchain\" the same as \"declined\"."
  (message
   (substitute-command-keys
    "GNU Global not found.  Install it (Debian: `sudo apt install global'), \
then \\[fenrir/gtags-create-or-update] to build the index."))
  nil)

(defvar fenrir/gtags-forbidden-roots
  (list (expand-file-name "~/")        ; the dotfiles repo -- ~1500 tracked files
        "/"                            ; filesystem root
        "/tmp/" "/usr/" "/etc/" "/var/" "/opt/")
  "Directories `fenrir/gtags--project-root' must never return for indexing.
project.el's `project-try-vc' can degenerate to the filesystem root (or to
$HOME, the dotfiles repo) when no real VCS root is found -- indexing any of
those would spawn a runaway `gtags' walk.  Each entry is compared as an
`expand-file-name'd, slash-terminated absolute path.")

(defun fenrir/gtags--project-root ()
  "Resolve the current buffer's project root for indexing, or nil.
Goes through project.el so the `my-project-ignore-home' advice applies -- we
must NEVER index $HOME (the dotfiles repo has ~1500 tracked files; the gtags
walk would be enormous).  Additionally rejects the filesystem root and other
system dirs (see `fenrir/gtags-forbidden-roots'), because `project-try-vc'
degenerates to `/' when a buffer under, e.g., /tmp has no VCS root above it.
Returns an `expand-file-name'd, slash-terminated absolute directory, or nil."
  (when-let* ((proj (project-current nil)))
    (let ((root (file-name-as-directory (expand-file-name (project-root proj)))))
      (unless (member root fenrir/gtags-forbidden-roots)
        root))))

(defun fenrir/gtags--existing-index-root ()
  "Return the directory of the GTAGS index covering the current buffer, or nil.
Delegates to ggtags' own resolver (`global -pr', then a GTAGS dominating-file
walk) so detection matches exactly what the ggtags xref backend will later use
to answer -- no second, divergent notion of \"is there an index\"."
  (when (require 'ggtags nil t)
    (ignore-errors (ggtags-current-project-root))))

(defun fenrir/gtags--source-file-count (root)
  "Count source files under ROOT that GNU Global would index, capped at 1.
Returns 0 or 1 -- we only need \"is there ANY source here\".  This is a cheap
pre-build sanity gate (don't run `gtags' in a dir with no code at all), NOT the
corrupt-index defense: a source-less dir was only one of several 0-byte causes,
and the user's real failure (~/code/coinsasia/backend, 1231 files) sailed past
this guard.  The authoritative defense is `fenrir/gtags--index-corrupt-p'
post-build validation; this only avoids a pointless empty build.  `global
--explain'-style file selection is hard to mirror exactly, so we approximate
with a cheap recursive scan for common extensions and stop at the first hit."
  (let ((case-fold-search t)
        ;; gtags' default parser covers C/C++/Java/PHP/Yacc plus, via the ctags
        ;; backend, most everything else.  This list is a heuristic \"does real
        ;; code live here\" probe, not a faithful gtags file filter.
        (re (rx "." (or "c" "h" "cc" "cpp" "cxx" "hpp" "hh"
                        "java" "py" "go" "rs" "js" "jsx" "ts" "tsx"
                        "el" "lua" "php" "rb" "sh" "sql" "vue")
                eos)))
    (catch 'found
      (dolist (f (ignore-errors
                   (directory-files-recursively root re nil
                                                ;; Skip the usual heavy / vendored
                                                ;; trees so the probe stays fast.
                                                (lambda (dir)
                                                  (not (member (file-name-nondirectory dir)
                                                               '(".git" "node_modules"
                                                                 "vendor" "target"
                                                                 ".venv" "venv"
                                                                 "dist" "build")))))))
        (when (file-regular-p f) (throw 'found 1)))
      0)))

(defcustom fenrir/gtags-label "native-pygments"
  "GTAGSLABEL passed to `gtags' so it uses a non-built-in parser, or nil.

WHY \"native-pygments\" (mirroring the user's gtags.sh skill script): this label
runs GNU Global's BUILT-IN parser FIRST for the languages it natively understands
(c/c++/java/php/yacc/asm) -- faster, and the native parser is more accurate for
those than pygments -- and falls back to pygments for EVERYTHING ELSE
(Go/Python/TS/JS/Vue/Rust/...).  Best of both worlds, hence the default.

WHY a non-built-in parser is needed at all.  GNU Global's BUILT-IN parser only knows
c/yacc/asm/java/cpp/php; ggtags' own \"Use `ctags' backend?\" prompt sets
GTAGSLABEL=ctags which maps to exuberant-ctags (NOT installed here -- only
Universal Ctags) and is ALSO Go-blind.  Either way a Go/Python/TypeScript repo
gets a structurally-valid 16 KB index with ZERO of its symbols.  To actually
index those languages we must set GTAGSLABEL ourselves to a plugin label.

Choices, measured on a Go+Python+TypeScript tree mirroring ~/code/coinsasia/backend:
  * \"native-pygments\" -- built-in parser for c/c++/java/php/yacc/asm, pygments
                        for the rest (Go/Python/TS/JS/Vue/Rust/...).  DEFAULT --
                        broadest coverage, native parser where it's better.
  * \"pygments\"     -- pygments for everything; indexes Go + Python + TypeScript.
  * \"new-ctags\"    -- Universal Ctags; indexes Go + Python but MISSES TypeScript;
                        ~4.5x faster and a self-contained binary (no interpreter).
These labels are DEFINED by /etc/gtags/gtags.conf, which
Debian ships at the [sysconfdir] path baked into the gtags binary, so they
resolve with NO GTAGSCONF / ~/.globalrc / repo-local conf.

FRAGILITY (why post-build validation is mandatory regardless): the pygments
helper /usr/share/global/gtags/script/pygments_parser.py shebangs
`#!/usr/bin/env python' (python, NOT python3).  If `python' is unreachable in
the gtags build subprocess (Debian without `python-is-python3'), gtags creates
the files then dies with \"unexpected EOF\" -> the 0-byte corrupt stub.  On THIS
box `python-is-python3' is installed so pygments works; on a box where it isn't,
flip this to \"new-ctags\" (no interpreter dependency) -- and either way the
validation below catches the failure and removes the stub.

nil => don't inject GTAGSLABEL at all; the async build runs bare `gtags', which
uses GNU Global's built-in parser (or a project-local .globalrc / gtags.conf it
discovers on its own).  Escape hatch for the rare project that supplies its own
config or only has built-in-parser languages (c/yacc/asm/java/cpp/php).  No
backend prompt can appear -- the build runs in a `make-process' subprocess."
  :type '(choice (const :tag "native-pygments (builtin C-likes + pygments rest; DEFAULT)" "native-pygments")
                 (const :tag "pygments (Go+Python+TS)" "pygments")
                 (const :tag "new-ctags (Go+Python, no TS; fast)" "new-ctags")
                 (const :tag "none -- let ggtags prompt" nil)
                 (string :tag "other label"))
  :group 'fenrir)

(defcustom fenrir/gtags-conf (expand-file-name "gtags.conf" user-emacs-directory)
  "Path to the gtags.conf the async build injects as GTAGSCONF, or nil.
A tracked, self-contained copy of the system /etc/gtags/gtags.conf whose `common'
label carries an EXTENDED skip list (node_modules/, vendor/, venv/, dist/, build/,
target/, ...) so neither a fresh `gtags' build nor a `global -u' update indexes
dependency / build trees -- the stock system conf skips none of those, which let
~/code/coinsasia balloon to 3.8 GB of node_modules/venv junk and re-bloat on every
update.  The skip list lives in the CONFIG (not a `gtags -f' file list) because it
is the only lever that reaches BOTH create and the `global -u' re-traversal.

WHY a tracked copy rather than editing /etc/gtags/gtags.conf: keeps the exclusion
reproducible on a fresh clone with no root/sudo write to a system file.  See the
file's own header for the exact delta vs upstream and how to refresh it.

If this file is missing, `fenrir/gtags--build-async' falls back to
/etc/gtags/gtags.conf (which lacks the extra skips) so a half-set-up checkout
still gets working parser labels.  Set to nil to force the system conf."
  :type '(choice file (const :tag "fall back to /etc/gtags/gtags.conf" nil))
  :group 'fenrir)

(defun fenrir/gtags--index-files (root)
  "Return the absolute paths of the three GTAGS index files under ROOT.
Used by both the validity probe and the wipe.  GTAGSDB/ID are deliberately not
listed -- gtags' default plugin labels write only GTAGS/GRTAGS/GPATH, and those
three are exactly what `global' reads to decide \"seems corrupted\"."
  (mapcar (lambda (f) (expand-file-name f root))
          '("GTAGS" "GRTAGS" "GPATH")))

(defun fenrir/gtags--index-corrupt-p (root)
  "Return non-nil iff the GTAGS index under ROOT is corrupt / 0-byte.

Discriminates THREE states (all reproduced in /tmp):
  * CORRUPT / 0-byte  -> returns t.  GTAGS missing or 0 bytes, OR `global -c'
                         exits non-zero / prints \"seems corrupted\".
  * VALID-but-EMPTY   -> returns nil.  `global -c' exits 0 with empty output
                         (parser ran, found no symbols / wrong-parser-for-lang).
                         This is a LEGIT state -- never wipe it as if corrupt.
  * VALID-with-symbols-> returns nil.

WHY `global -c' and not `global -p': `global -p' merely prints the DB directory
and exits 0 even on a 0-byte stub -- it does NOT detect corruption.  `global -c'
actually READS GTAGS and surfaces \"seems corrupted\" on stderr with a non-zero
exit.  WHY process-file with the exit code: a bare shell `global -c | head'
masks the non-zero exit (stderr-only) -- but through `process-file' the exit IS
non-zero (verified =1 via the live daemon), so we trust process-file's return
plus a stderr scan, never a shell idiom that swallows the code.  The 0-byte size
check catches the \"gtags made stubs then aborted before writing\" case."
  (let ((gtags (car (fenrir/gtags--index-files root))))
    (cond
     ;; No GTAGS at all -> not "corrupt", just "absent" (caller handles create).
     ((not (file-exists-p gtags)) nil)
     ;; 0-byte stub -> the aborted-build corpse.  Corrupt.
     ((zerop (file-attribute-size (file-attributes gtags))) t)
     ;; Non-empty: run the authoritative `global -c' probe with stderr captured
     ;; SEPARATELY (DESTINATION (list stdout-buf stderr-file)), default-directory
     ;; pinned to ROOT.  No source file is opened -> no eglot-ensure -> daemon-safe.
     (t
      (let ((errf (make-temp-file "fenrir-gtags-probe-stderr"))
            (default-directory (file-name-as-directory root)))
        (unwind-protect
            (with-temp-buffer
              (let ((rc (process-file "global" nil (list t errf) nil "-c" ""))
                    (err (with-temp-buffer
                           (ignore-errors (insert-file-contents errf))
                           (buffer-string))))
                (or (not (eq rc 0))
                    (string-match-p "seems corrupted" err))))
          (ignore-errors (delete-file errf))))))))

(defun fenrir/gtags--index-empty-p (root)
  "Return non-nil iff ROOT's index is VALID but contains no symbols.
Run only on a non-corrupt index.  `global -c' exits 0 but emits nothing => the
parser didn't index any symbols (wrong/Go-blind parser, or genuinely no code).
Used to warn the user their index is useless even though it's not corrupt."
  (let ((default-directory (file-name-as-directory root)))
    (with-temp-buffer
      ;; stderr discarded here -- we already know it's not corrupt; we only care
      ;; whether stdout is empty.
      (let ((rc (process-file "global" nil (list t nil) nil "-c" "")))
        (and (eq rc 0)
             (zerop (buffer-size)))))))

(defun fenrir/gtags--wipe-index (root)
  "Delete ROOT's GTAGS/GRTAGS/GPATH and drop ggtags' cached project struct.
NEVER leave a corrupt index behind.  We delete the files DIRECTLY rather than
call interactive `ggtags-delete-tags' -- that one prompts, opens a *GTags File
List* buffer, and needs a resolvable `ggtags-current-project-root', which a
corrupt 0-byte GTAGS breaks (`ggtags-make-project' stats GTAGS and poisons its
struct).  After wiping we replicate ggtags-delete-tags' bookkeeping: remhash the
stale entry from `ggtags-projects' and invalidate the buffer-local root, so the
next xref call re-resolves cleanly instead of answering from a cached corpse."
  (dolist (f (fenrir/gtags--index-files root))
    (when (file-exists-p f) (ignore-errors (delete-file f))))
  (when (require 'ggtags nil t)
    (when (boundp 'ggtags-projects)
      (remhash (file-name-as-directory root) ggtags-projects))
    (when (fboundp 'ggtags-invalidate-buffer-project-root)
      (ignore-errors
        (ggtags-invalidate-buffer-project-root (file-truename root))))))

;; ===========================================================================
;; ASYNC BUILD CORE.  `gtags' (create) on ~/code/coinsasia/backend (1108 Go
;; files via pygments) runs for many seconds; `global -u' (update) likewise on a
;; large dirty tree.  Run synchronously they BLOCK the single-threaded Emacs
;; DAEMON -- the whole editor freezes.  So the RUN is moved off the main thread
;; via `make-process': the kick-off returns immediately and a sentinel does the
;; post-processing when the subprocess exits.
;;
;; We run the `gtags' / `global' CLI DIRECTLY here rather than through
;; `ggtags-create-tags' / `ggtags-update-tags' (both synchronous) -- driving the
;; CLI ourselves is what makes async possible AND lets us inject GTAGSLABEL
;; without ggtags' "Use `ctags' backend?" prompt ever entering the picture (we
;; never reach that code path).  WHY GTAGSLABEL still matters: GNU Global's
;; built-in parser only knows c/yacc/asm/java/cpp/php; without a plugin label a
;; Go/Python/TypeScript repo gets a structurally-valid but symbol-EMPTY index
;; (see `fenrir/gtags-label').  Injected on CREATE only -- `gtags' records the
;; label in GTAGS, so `global -u' re-reads it and needs no re-injection (verified
;; in /tmp: an async `global -u' picked up a freshly-added C file with no
;; GTAGSLABEL set).  A project-local .globalrc / gtags.conf still wins via the
;; gtags binary's own --gtagsconf discovery, which is intended.

(defvar fenrir/gtags--builds (make-hash-table :test 'equal)
  "In-progress async GTAGS builds: normalized ROOT (slash-terminated) -> process.
The RE-ENTRANCY GUARD: `fenrir/gtags--build-async' refuses to spawn a second
`gtags' for a ROOT whose entry here is still `process-live-p'.  Without it a
double C-c g g (or an update fired while a create is mid-flight) would race two
writers over the same GTAGS/GRTAGS/GPATH and corrupt them.  The sentinel
`remhash'es ROOT on exit, so the guard self-clears.")

(defun fenrir/gtags--invalidate-ggtags-cache (root)
  "Drop ggtags' cached project struct + buffer-local roots for ROOT.
Safe to call from a process sentinel: never prompts, never signals (every step
is guarded), operates only over `buffer-list' / the `ggtags-projects' hash.  Run
after a successful build/update so the next M-. / M-? re-resolves against the
fresh index instead of answering from a stale cached project.  Mirrors the
bookkeeping `fenrir/gtags--wipe-index' does, minus the file deletion."
  (when (require 'ggtags nil t)
    (when (boundp 'ggtags-projects)
      (remhash (file-name-as-directory root) ggtags-projects))
    (when (fboundp 'ggtags-invalidate-buffer-project-root)
      (ignore-errors
        (ggtags-invalidate-buffer-project-root (file-truename root))))))

;; ===========================================================================
;; NESTED-INDEX SHADOWING.  GNU Global resolves a lookup to the NEAREST ANCESTOR
;; GTAGS walking up from the file's directory -- it never reaches a higher index
;; once a lower one exists.  So a GTAGS in a SUBDIRECTORY silently SHADOWS the
;; root index for every file beneath it.  Real bite: ~/code/coinsasia/backend/
;; GTAGS hid ~/code/coinsasia/GTAGS, so xref on a Go file under backend/ answered
;; from the stale, junk-laden backend index and the top-level one looked "unread".
;;
;; Two defenses below: a non-interactive SWEEP that a (re)build runs to delete
;; nested indexes (so the freshly-built root is the only resolvable one), and an
;; interactive DIAGNOSE command for when symptoms appear and you want to see /
;; remove the duplicates by hand.

(defcustom fenrir/gtags-sweep-nested t
  "When non-nil, a GTAGS (re)build first deletes nested indexes under the root.
A nested index shadows the root index for every file beneath it (GNU Global stops
at the nearest ancestor GTAGS -- the backend/GTAGS-vs-top-GTAGS bug).  With this
on, `fenrir/gtags--fresh-build' sweeps those nested indexes before building so the
freshly-built root index is the only one any descendant file can resolve to.  The
deleted files are regenerable and ggtags' caches for them are invalidated.  Set to
nil if you intentionally keep independent per-subdirectory GTAGS indexes."
  :type 'boolean
  :group 'fenrir)

(defun fenrir/gtags--nested-index-dirs (root)
  "Return the directories of GTAGS indexes in STRICT subdirectories of ROOT.
ROOT's own index directory is excluded -- only nested copies that would SHADOW
ROOT's index are returned.  Skips the usual heavy / vendored trees while walking
so the scan stays fast on a large repo (a nested index inside node_modules/ etc.
shadows nothing the user navigates, so missing it is harmless)."
  (let ((root (file-name-as-directory (expand-file-name root)))
        (acc '()))
    (dolist (f (ignore-errors
                 (directory-files-recursively
                  root (rx bos "GTAGS" eos) nil
                  (lambda (d)
                    (not (member (file-name-nondirectory d)
                                 '(".git" "node_modules" "vendor" "target"
                                   ".venv" "venv" "dist" "build")))))))
      (let ((d (file-name-as-directory (file-name-directory f))))
        (unless (equal d root) (push d acc))))
    (nreverse acc)))

(defun fenrir/gtags--ancestor-index-root (dir)
  "Return the nearest STRICT ancestor directory of DIR holding a GTAGS, or nil.
Detects the inverse-shadow case: DIR's own index is itself hidden under a higher
index, so updating DIR perpetuates the split (the buffer's index resolved to
backend/, but coinsasia/ above it also has one).  Walks up from DIR's parent,
stopping at a forbidden root (`fenrir/gtags-forbidden-roots') or the filesystem
root."
  (let ((cur (file-name-directory (directory-file-name (expand-file-name dir))))
        (result nil))
    (catch 'done
      (while cur
        (let ((cur* (file-name-as-directory cur)))
          (when (and (not (member cur* fenrir/gtags-forbidden-roots))
                     (file-exists-p (expand-file-name "GTAGS" cur*)))
            (setq result cur*)
            (throw 'done nil))
          (let ((up (file-name-directory (directory-file-name cur*))))
            (if (equal up cur*) (throw 'done nil)   ; reached the filesystem root
              (setq cur up))))))
    result))

(defun fenrir/gtags--sweep-nested-indexes (root &optional quiet)
  "Delete GTAGS/GRTAGS/GPATH in every STRICT subdirectory of ROOT; return the dirs.
A nested index shadows ROOT's index for every file beneath it, silently routing
xref to the wrong (often stale) index.  Removing them on each (re)build guarantees
ROOT's index is the only one a descendant file can resolve to.  Also invalidates
ggtags' cached project struct per swept directory so a stale buffer does not keep
answering from a deleted index.  Non-interactive and signal-free -> safe to call
from a process sentinel; pass QUIET to suppress the summary `message'."
  (let ((dirs (fenrir/gtags--nested-index-dirs root)))
    (dolist (d dirs)
      (dolist (f (fenrir/gtags--index-files d))
        (when (file-exists-p f) (ignore-errors (delete-file f))))
      (fenrir/gtags--invalidate-ggtags-cache d))
    (when (and dirs (not quiet))
      (message "Swept %d nested GTAGS index%s under %s: %s"
               (length dirs) (if (= (length dirs) 1) "" "es")
               (abbreviate-file-name root)
               (mapconcat #'abbreviate-file-name dirs ", ")))
    dirs))

;;;###autoload
(defun fenrir/gtags-diagnose-duplicates (&optional dir)
  "Find GTAGS indexes that SHADOW each other under DIR and offer to remove them.
Interactively DIR defaults to the buffer's existing-index root, else the
project.el root, else `default-directory'; a prefix arg prompts for it.  GNU
Global resolves M-. / M-? against the NEAREST ancestor GTAGS, so any index in a
subdirectory silently hides the root index for every file beneath it -- the bug
where ~/code/coinsasia/backend/GTAGS shadowed ~/code/coinsasia/GTAGS.

Lists every GTAGS found in the subtree (size + mtime) in a `*gtags-duplicates*'
buffer, marks the top-most as [root] and the rest as [nested] (the shadows), then
offers to delete the nested ones.  Deletions are regenerable; ggtags' cached
project structs for the removed dirs are invalidated so the next lookup
re-resolves to the surviving root index.  This is the on-error / on-suspicion
counterpart to the build-time `fenrir/gtags--sweep-nested-indexes'."
  (interactive
   (list (let ((default (or (fenrir/gtags--existing-index-root)
                            (fenrir/gtags--project-root)
                            (expand-file-name default-directory))))
           (if current-prefix-arg
               (read-directory-name "Diagnose GTAGS duplicates under: "
                                    default default t)
             default))))
  (let* ((root (file-name-as-directory (expand-file-name dir)))
         ;; ALL GTAGS in the subtree, ROOT's own included, shallow-first so the
         ;; authoritative top index sorts before the shadows it hides.
         (all (let (acc)
                (dolist (f (ignore-errors
                             (directory-files-recursively
                              root (rx bos "GTAGS" eos) nil
                              (lambda (d)
                                (not (member (file-name-nondirectory d)
                                             '(".git" "node_modules" "vendor" "target"
                                               ".venv" "venv" "dist" "build")))))))
                  (push (file-name-as-directory (file-name-directory f)) acc))
                (sort acc #'string<)))
         (nested (cl-remove root all :test #'equal)))
    (cond
     ((null all)
      (message "No GTAGS index found under %s" (abbreviate-file-name root)))
     ((null nested)
      (message "Single GTAGS index under %s (at %s) -- no shadowing"
               (abbreviate-file-name root)
               (abbreviate-file-name (car all))))
     (t
      (with-current-buffer (get-buffer-create "*gtags-duplicates*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "GTAGS indexes under %s\n" (abbreviate-file-name root))
                  (make-string 64 ?=) "\n")
          (dolist (d all)
            (let* ((attr (file-attributes (expand-file-name "GTAGS" d)))
                   (size (and attr (file-attribute-size attr)))
                   (mtime (and attr (format-time-string
                                     "%Y-%m-%d %H:%M"
                                     (file-attribute-modification-time attr)))))
              (insert (format "%-8s %9s  %s  %s\n"
                              (if (equal d root) "[root]" "[nested]")
                              (if size (file-size-human-readable size) "?")
                              (or mtime "?")
                              (abbreviate-file-name d)))))
          (insert "\n[nested] indexes SHADOW the index above them for every file "
                  "beneath them.\n")
          (goto-char (point-min)))
        (display-buffer (current-buffer)))
      (when (yes-or-no-p
             (format "Delete %d nested (shadowing) GTAGS index%s under %s? "
                     (length nested) (if (= (length nested) 1) "" "es")
                     (abbreviate-file-name root)))
        (dolist (d nested)
          (dolist (f (fenrir/gtags--index-files d))
            (when (file-exists-p f) (ignore-errors (delete-file f))))
          (fenrir/gtags--invalidate-ggtags-cache d))
        (message "Deleted %d nested GTAGS index%s -- %s is now authoritative"
                 (length nested) (if (= (length nested) 1) "" "es")
                 (abbreviate-file-name root)))))))

(defun fenrir/gtags--last-output-line (buf)
  "Return the last non-blank line of process-output BUF, or a placeholder.
Used by the sentinel to surface the real failure reason (gtags/global write the
useful diagnostic -- \"label '...' not found\", \"seems corrupted\" -- on the
last line of stderr, which we merge into BUF)."
  (if (buffer-live-p buf)
      (with-current-buffer buf
        (let ((s (string-trim (buffer-string))))
          (if (string-empty-p s)
              "(no output)"
            (car (last (split-string s "\n" t))))))
    "(no output)"))

(defun fenrir/gtags--build-sentinel (root update buf shimdir)
  "Build the process sentinel closure for an async GTAGS build of ROOT.
UPDATE non-nil => this was `global -u' (incremental), else `gtags' (create).
BUF is the merged stdout+stderr buffer.
SHIMDIR is the throwaway temp dir holding the python->python3 PATH shim
(`fenrir/gtags--build-async' creates it when the box lacks `python'), or nil
when no shim was needed.  The sentinel deletes it after the process exits, in
the same `unwind-protect' that reclaims BUF -- a nil SHIMDIR is a no-op.

A sentinel MUST be non-interactive: it can fire at any time (including while the
user is in the minibuffer), so it NEVER prompts (`y-or-n-p' / `yes-or-no-p') and
NEVER lets an error escape -- post-processing runs inside `ignore-errors' and the
buffer is always killed via `unwind-protect'.  It reuses the SAME validation
helpers the old synchronous path used (`fenrir/gtags--index-corrupt-p',
`fenrir/gtags--index-empty-p', `fenrir/gtags--wipe-index') -- those are already
non-interactive (process-file probes + direct `delete-file'), so they drop into a
sentinel unchanged; we only swapped the `user-error' the sync path raised on a
corrupt result for a plain `message' (a sentinel can't signal to the user)."
  (lambda (proc _event)
    (when (memq (process-status proc) '(exit signal))
      ;; Clear the re-entrancy guard FIRST, unconditionally, so a future build
      ;; is never blocked by a finished one even if post-processing throws.
      (remhash (file-name-as-directory root) fenrir/gtags--builds)
      (let ((code (process-exit-status proc))
            (disp (abbreviate-file-name root)))
        (unwind-protect
            (ignore-errors
              (cond
               ;; ---- success, UPDATE: index already existed; just refresh cache.
               ((and (eq code 0) update)
                (fenrir/gtags--invalidate-ggtags-cache root)
                (message "✓ GTAGS updated in %s" disp))
               ;; ---- success, CREATE: validate before declaring victory.  gtags
               ;; can exit 0 yet leave a 0-byte / corrupt stub (parser helper
               ;; crashed -- e.g. pygments' python shebang unreachable) or a valid
               ;; but symbol-less index (wrong parser for the repo's languages).
               ((eq code 0)
                (cond
                 ((fenrir/gtags--index-corrupt-p root)
                  (fenrir/gtags--wipe-index root)   ; never leave a corpse
                  (message
                   "✗ gtags produced a corrupt/0-byte index in %s (parser \
failure? try `fenrir/gtags-label'=new-ctags, or use gopls for Go)" disp))
                 ((fenrir/gtags--index-empty-p root)
                  (message
                   "GTAGS built in %s but indexed NO symbols -- wrong parser for \
this repo's languages (set `fenrir/gtags-label' to \"pygments\" for Go/Python/TS, \
or use gopls for Go)" disp))
                 (t
                  (fenrir/gtags--invalidate-ggtags-cache root)
                  (message "✓ GTAGS built in %s -- re-run M-. / M-?" disp))))
               ;; ---- non-zero exit.  On CREATE, clean the half-written stub so a
               ;; later `global -u' doesn't choke on it; on UPDATE leave the
               ;; pre-existing index alone (don't destroy the user's index without
               ;; consent -- route them to C-u C-c g g, which offers wipe+rebuild).
               (t
                (let ((line (fenrir/gtags--last-output-line buf)))
                  (unless update
                    (fenrir/gtags--wipe-index root))
                  ;; NB: a literal "C-u C-c g g", NOT a `\\[...]' key escape --
                  ;; `message' does not run `substitute-command-keys', so an
                  ;; escape would print verbatim.  `C-c g g' is the fixed global
                  ;; binding for `fenrir/gtags-create-or-update'.
                  (if (string-match-p "seems corrupted" line)
                      (message "✗ gtags/global exited %d in %s: %s -- rebuild \
with C-u C-c g g"
                               code disp line)
                    (message "✗ gtags/global exited %d in %s: %s"
                             code disp line))))))
          ;; Always reclaim the output buffer AND the python-shim temp dir (if the
          ;; build created one).  `delete-directory ... t' removes it recursively;
          ;; `ignore-errors' so a vanished/already-cleaned dir can't break teardown.
          (when (buffer-live-p buf) (kill-buffer buf))
          (when shimdir (ignore-errors (delete-directory shimdir t))))))))

(defun fenrir/gtags--build-async (root &optional update)
  "Run the GTAGS build for ROOT in the background via `make-process'; return now.
With UPDATE non-nil run `global -u' (incremental refresh of an existing index);
otherwise run `gtags' (full create) with GTAGSLABEL injected.  Output (stdout +
stderr merged) goes to a fresh \" *fenrir-gtags*\" buffer the sentinel reads for
the failure reason and then kills.

RE-ENTRANCY GUARD: keyed on the normalized ROOT in `fenrir/gtags--builds'.  If a
live build already owns ROOT, message \"already building\" and return nil WITHOUT
spawning a second writer (concurrent writers would corrupt the index files).

Returns the process (or nil if rejected by the guard) -- the caller does NOT wait
on it; all post-processing/validation happens in the sentinel.  Daemon-safe:
opens no source file (no `eglot-ensure'), and the heavy CLI runs off the main
thread so the daemon stays responsive."
  (let* ((root (file-name-as-directory (expand-file-name root)))
         (live (gethash root fenrir/gtags--builds)))
    (if (and live (process-live-p live))
        (progn
          (message "Already building GTAGS in %s -- ignoring this request"
                   (abbreviate-file-name root))
          nil)
      (let* ((default-directory root)
             ;; Build the subprocess environment in layers, mirroring the user's
             ;; gtags.sh skill script (GTAGSLABEL + GTAGSCONF + a python->python3
             ;; PATH shim).  `shimdir' captures the throwaway temp dir created for
             ;; the shim (or nil if none was needed) so the sentinel can clean it up
             ;; after the process exits.
             (shimdir nil)
             ;; (1) GTAGSLABEL -- inject on CREATE only (see the ASYNC BUILD CORE
             ;; comment): `gtags' stores the label in GTAGS, so `global -u'
             ;; re-reads it -- re-injecting on update is unnecessary and a no-op.
             (process-environment
              (if (and (not update) fenrir/gtags-label)
                  (cons (concat "GTAGSLABEL=" fenrir/gtags-label) process-environment)
                process-environment))
             ;; (2) GTAGSCONF -- point gtags at OUR tracked gtags.conf
             ;; (`fenrir/gtags-conf', ~/.emacs.d/gtags.conf): a self-contained copy
             ;; of the system conf whose `common' skip list ALSO drops node_modules/
             ;; vendor/ venv/ dist/ build/ target/ ... -- the dirs the stock conf
             ;; does NOT skip.  Injected on BOTH create AND update because the skip
             ;; list is the only lever that reaches `global -u's full re-traversal
             ;; (a `gtags -f' file list cannot): without it, every update re-added
             ;; the dependency trees (~/code/coinsasia: 2.5 MB of symbols vs 3.8 GB
             ;; with the junk, re-bloated on each `global -u').  Owning the conf
             ;; under version control keeps the exclusion reproducible without
             ;; editing the root-owned system file.  Falls back to the system conf
             ;; if ours is missing (a half-set-up checkout still gets parser labels)
             ;; or `fenrir/gtags-conf' is nil; GTAGSCONF still also defines the
             ;; pygments/native-pygments labels the build relies on.
             (process-environment
              (let ((conf (if (and fenrir/gtags-conf (file-exists-p fenrir/gtags-conf))
                              fenrir/gtags-conf
                            "/etc/gtags/gtags.conf")))
                (if (file-exists-p conf)
                    (cons (concat "GTAGSCONF=" conf) process-environment)
                  process-environment)))
             ;; (3) python->python3 PATH shim -- mirrors gtags.sh's PYSHIM block.
             ;; pygments_parser.py shebangs `#!/usr/bin/env python', so a box without
             ;; the `python-is-python3' package (only `python3', no `python') makes
             ;; the parser silently fail and gtags writes a corrupt/0-byte index.
             ;; We create a fresh temp dir holding a `python' symlink to the real
             ;; python3 and PREPEND it to PATH.  This PROACTIVELY PREVENTS the very
             ;; corruption the post-build validation (`fenrir/gtags--index-corrupt-p')
             ;; otherwise only detects-and-wipes.  The dir is cleaned up by the
             ;; sentinel once the subprocess exits.
             (process-environment
              (if (and (not (executable-find "python"))
                       (executable-find "python3"))
                  (let* ((dir (make-temp-file "fenrir-gtags-pyshim" t))
                         (link (expand-file-name "python" dir)))
                    (make-symbolic-link (executable-find "python3") link t)
                    (setq shimdir dir)
                    ;; Prepend the shim dir to the PATH entry that make-process will
                    ;; inherit (mutate the just-copied process-environment, not the
                    ;; global one).
                    (cons (concat "PATH=" dir path-separator (getenv "PATH"))
                          process-environment))
                process-environment))
             (buf (generate-new-buffer " *fenrir-gtags*"))
             (cmd (if update '("global" "-u") '("gtags")))
             (proc (make-process
                    :name (format "fenrir-gtags[%s]" (abbreviate-file-name root))
                    :buffer buf
                    :command cmd
                    :connection-type 'pipe   ; no PTY -- a batch CLI, not a REPL
                    :noquery t               ; don't prompt on Emacs exit
                    :sentinel (fenrir/gtags--build-sentinel root update buf shimdir))))
        (puthash root proc fenrir/gtags--builds)
        proc))))

(defun fenrir/gtags--go-dominant-p (root)
  "Return non-nil iff ROOT looks like a Go project (cheap, bounded scan).
True when a go.mod exists anywhere reasonably shallow under ROOT, or when the
first source file the cheap probe finds is a .go file.  Used to STEER the user
to gopls (semantic, cross-package, no stale index) before building a GTAGS
fallback -- gtags-on-Go is the explicit opt-in fallback, not the silent default."
  (or (file-exists-p (expand-file-name "go.mod" root))
      ;; A bounded recursive look for go.mod / a .go file (skip heavy trees).
      (catch 'go
        (dolist (f (ignore-errors
                     (directory-files-recursively
                      root (rx (or "go.mod" (seq "." "go")) eos) nil
                      (lambda (dir)
                        (not (member (file-name-nondirectory dir)
                                     '(".git" "node_modules" "vendor"
                                       "target" ".venv" "venv" "dist" "build")))))))
          (when (file-regular-p f) (throw 'go t)))
        nil)))

(defun fenrir/gtags--fresh-build (build-root)
  "Kick off an ASYNC GTAGS create for BUILD-ROOT after a synchronous pre-flight.
Shared by the no-index create path and the corrupt-index recovery path (both in
`fenrir/gtags-create-or-update').  Steps, in order:
  1. Steer Go-dominant repos to gopls (`fenrir/gtags--maybe-steer-to-gopls' --
     signals `user-error' and unwinds if the user picks gopls).
  2. Refuse a source-less dir (the cheap empty-build gate).
  3. Kick off the build via `fenrir/gtags--build-async' and RETURN immediately.

WHY the split.  Steps 1-2 are interactive / fast and MUST stay synchronous (a
prompt cannot run in a sentinel; the source-count probe is a cheap bounded scan).
The actual `gtags' RUN -- the part that took many seconds on a 1108-file repo and
froze the daemon -- is what goes async.  POST-BUILD VALIDATION (corrupt/empty
checks, stub wipe, ggtags cache invalidation) therefore moves OUT of here and
INTO the sentinel (`fenrir/gtags--build-sentinel'): it can only run once the
subprocess has exited, which is now after this function has already returned.

Because the build is async, the M-. that triggered the etags-fallback offer will
NOT find symbols immediately -- the user is told to re-run M-. / M-? when the
\"✓ GTAGS built\" message lands.  TTY-safe (only minibuffer y-or-n-p / messages)
and daemon-safe (opens no source file -> no `eglot-ensure' to block the daemon,
and the heavy CLI runs off the main thread)."
  (fenrir/gtags--maybe-steer-to-gopls build-root)
  (when (zerop (fenrir/gtags--source-file-count build-root))
    (user-error
     "No source files under %s -- indexing here would write an empty, corrupt \
GTAGS.  Pick a directory that contains code"
     (abbreviate-file-name build-root)))
  ;; Remove any nested indexes that would SHADOW the about-to-be-built root index
  ;; (GNU Global resolves to the nearest ancestor GTAGS).  Gated on
  ;; `fenrir/gtags-sweep-nested' so a deliberate per-subdir index setup can opt out.
  ;; Runs BEFORE the async kick-off so the sweep is synchronous and done by the
  ;; time the build (and the user's next M-. / M-?) sees the tree.
  (when fenrir/gtags-sweep-nested
    (fenrir/gtags--sweep-nested-indexes build-root))
  ;; Fire-and-forget: validation + cache invalidation happen in the sentinel.
  (when (fenrir/gtags--build-async build-root)
    (message
     "Building GTAGS in %s... (async; you'll get a message when it finishes -- \
then re-run M-. / M-?)"
     (abbreviate-file-name build-root))))

(defun fenrir/gtags--maybe-steer-to-gopls (root)
  "If ROOT is Go-dominant and gopls is installed, offer to abort in favor of gopls.
Returns nil if the user wants to proceed with GTAGS; signals `user-error' (which
unwinds the build) if they choose gopls.  WHY: gopls is strictly better for Go,
and the user only fell to gtags because gopls didn't ATTACH -- most often because
there is no go.mod at the project root (the buffer's repo is a subdir of a larger
git repo, e.g. ~/code/coinsasia/backend under ~/code/coinsasia).  We name that
likely cause and the fix instead of silently building a slow, inferior index."
  (when (and (executable-find "gopls")
             (fenrir/gtags--go-dominant-p root))
    (unless (y-or-n-p
             (format
              "%s looks like a Go project and gopls is installed -- gopls gives \
far better Go navigation than GTAGS.  gopls likely didn't attach because there's \
no go.mod at the project root.  Build a GTAGS index anyway? "
              (abbreviate-file-name root)))
      (user-error
       "Aborted -- prefer gopls for Go (run `go mod init' at the project root, \
or open the file from a directory that has go.mod; inspect with \
`M-x eglot-events-buffer')"))))

;;;###autoload
(defun fenrir/gtags-create-or-update (&optional force-create)
  "Build or refresh the GNU Global (GTAGS) index for the current project.
With prefix arg FORCE-CREATE, rebuild from scratch even if an index exists.

Prompts for the directory to build the index in -- defaulting to the project.el
root (honoring `my-project-ignore-home', so $HOME is never the default), so you
can confirm or pick a sub-module / sibling root before a potentially-huge gtags
walk.  Verifies the `gtags' / `global' CLIs are installed, and refuses to index
a root with no source files (the empty-GTAGS gotcha) or a forbidden system dir.
After (re)building, invalidates ggtags' cached project so its xref backend
answers M-. / M-? immediately -- no buffer revisit needed.

Three durable safeguards beyond the old behavior:
  * Go-DOMINANT repos with gopls installed get a steer toward gopls first
    (`fenrir/gtags--maybe-steer-to-gopls') -- gtags-on-Go is the opt-in fallback.
  * CREATE is followed by POST-BUILD VALIDATION (`fenrir/gtags--index-corrupt-p'):
    if gtags produced a 0-byte / corrupt index, the stub files are DELETED and
    the real reason is reported -- never leaving a corpse for the next `global -u'.
  * UPDATE first checks the existing index; a corrupt / 0-byte one (the
    \"seems corrupted\" dead-end) triggers an offer to WIPE + rebuild from scratch
    with the working parser label instead of erroring out.

This is the durable entry point; the `visit-tags-table-buffer' advice below
routes the cryptic etags prompt here."
  (interactive "P")
  (unless (fenrir/gtags--global-available-p)
    (fenrir/gtags--guide-install)
    (user-error "GNU Global not installed"))
  (require 'ggtags)
  ;; ALWAYS prompt for WHERE to build the index, defaulting to the auto-resolved
  ;; root (an existing index's root, else the project.el root, else this buffer's
  ;; directory).  Indexing the wrong dir -- a too-high reactor container, or a
  ;; source-less tree -- is the central gtags gotcha, so the root is your explicit
  ;; choice every run: hit RET to take the default, or navigate to a sub-module /
  ;; sibling root.  `read-directory-name' MUSTMATCH=t so the dir must exist; the
  ;; result is normalised to the slash-terminated absolute form the helpers expect.
  (let* ((default-root (or (and (not force-create) (fenrir/gtags--existing-index-root))
                           (fenrir/gtags--project-root)
                           (expand-file-name default-directory)))
         (root (file-name-as-directory
                (expand-file-name
                 (read-directory-name "Build GTAGS index in directory: "
                                      default-root default-root t))))
         ;; Does the CHOSEN root already carry its OWN index?  `--existing-index-
         ;; root' is buffer-relative and walks UP to a parent GTAGS; here you named
         ;; the root, so test THAT dir directly -- a parent's index must not turn an
         ;; explicit "index this subdir" into a silent parent update.
         (existing (and (not force-create)
                        (file-exists-p (expand-file-name "GTAGS" root))
                        root)))
    ;; Re-apply the $HOME / system-dir guard: you can now type any path, so
    ;; `fenrir/gtags--project-root's own filtering no longer protects us.
    (when (member root fenrir/gtags-forbidden-roots)
      (user-error "Refusing to index %s (forbidden root)"
                  (abbreviate-file-name root)))
    (cond
     ;; Existing index -> normally an incremental update (`global -u', via
     ;; ggtags), far cheaper than a full rebuild and keeps the index warm.  But
     ;; FIRST check it isn't the 0-byte / corrupt stub that makes `global -u'
     ;; dead-end with \"seems corrupted\" (FIX 2).
     (existing
      (cond
       ;; Corrupt / 0-byte existing index -> offer wipe + rebuild instead of the
       ;; cryptic error.  Direct cure for the user's `global -u ... seems
       ;; corrupted' failure.
       ((fenrir/gtags--index-corrupt-p existing)
        (if (yes-or-no-p
             (format
              "GTAGS index in %s is corrupt / 0-byte (would error with \"seems \
corrupted\").  Wipe the 3 index files and rebuild from scratch? "
              (abbreviate-file-name existing)))
            (progn
              (fenrir/gtags--wipe-index existing)
              (fenrir/gtags--fresh-build existing))
          (user-error
           "GTAGS index in %s is corrupt; leaving it in place (rebuild with \
\\[universal-argument] \\[fenrir/gtags-create-or-update], or delete \
GTAGS/GRTAGS/GPATH by hand)"
           (abbreviate-file-name existing))))
       ;; Healthy index -> incremental update, ASYNC (`global -u' off the main
       ;; thread so a large dirty tree doesn't freeze the daemon).  The sync
       ;; `condition-case' wrapper the old code used to catch a \"seems corrupted\"
       ;; race is gone -- a synchronous handler can't catch a failure that now
       ;; happens in a subprocess.  The sentinel handles it instead: a non-zero
       ;; `global -u' exit whose stderr says \"seems corrupted\" gets reported with
       ;; a \"rebuild with C-u C-c g g\" hint (which re-enters this command's
       ;; corrupt-index branch above and offers the wipe + rebuild).
       (t
        (when (fenrir/gtags--build-async existing 'update)
          ;; If the index covering this buffer is ITSELF nested under a higher
          ;; index, plain update keeps refreshing the shadow -- surface that and
          ;; point at the diagnose command rather than silently doing the wrong
          ;; thing.  One combined message (a second `message' would clobber it).
          (let ((shadow (fenrir/gtags--ancestor-index-root existing)))
            (message
             (if shadow
                 (format "Updating GTAGS in %s (async) -- NOTE: a higher index at \
%s shadows this one; M-x fenrir/gtags-diagnose-duplicates to fix, or \
C-u C-c g g at %s to rebuild the root"
                         (abbreviate-file-name existing)
                         (abbreviate-file-name shadow)
                         (abbreviate-file-name shadow))
               (format "Updating GTAGS in %s... (async; you'll get a message \
when it finishes)"
                       (abbreviate-file-name existing)))))))))
     ;; No index yet -> fresh build (gopls steer + validation inside the helper).
     (t
      (fenrir/gtags--fresh-build root)))))

(defun fenrir/visit-tags-table-buffer--guide-to-gtags (orig &rest args)
  "Intercept the etags \"Visit tags table\" prompt and offer GTAGS instead.
Around-advice on `visit-tags-table-buffer'.  When etags is about to fall back to
its file-picker prompt -- meaning no `tags-file-name', no `tags-table-list', no
TAGS file -- and we're in a real project with no live Eglot server and no GTAGS
index, ask the user (TTY-safe `y-or-n-p') whether to build a GTAGS index and run
`fenrir/gtags-create-or-update' if they say yes.

Falls through to the original prompt (ORIG) in every case it does NOT handle:
already have a tags table, no project, GNU Global missing, an Eglot server is
attached (paranoia -- the etags backend shouldn't run then), or the user
declines.  So legitimate etags users keep their prompt; we only catch the
\"there's nothing to fall back to\" case this config actually hits."
  (let ((cont (car args)))
    (if (or
         ;; CONT is 'same / t / a string -> the caller already knows which table
         ;; it wants; not the unguided fall-through prompt we mean to replace.
         (and cont (not (eq cont nil)))
         ;; A tags table is already in play -- let etags use it.
         tags-file-name tags-table-list
         ;; Eglot owns this buffer -> its xref backend should have handled M-.;
         ;; never divert.  `fboundp' guard because Eglot loads lazily.
         (and (fboundp 'eglot-managed-p) (eglot-managed-p))
         ;; Toolchain missing -> we can't offer anything useful; guide + fall
         ;; through so the user at least learns what to install.
         (not (fenrir/gtags--global-available-p))
         ;; Already have an index covering this buffer -> ggtags will answer;
         ;; no reason to prompt.  (Shouldn't reach here, but cheap to check.)
         (fenrir/gtags--existing-index-root)
         ;; No project -> nothing sane to index; don't hijack the prompt.
         (not (fenrir/gtags--project-root)))
        (apply orig args)
      ;; The interceptable case: project, no Eglot, no index, gtags available.
      (if (y-or-n-p
           (format "No tags index for %s.  Build a GNU Global (GTAGS) index now? "
                   (abbreviate-file-name (fenrir/gtags--project-root))))
          (progn
            (fenrir/gtags-create-or-update)
            ;; Returning nil signals `visit-tags-table-buffer' "no table" so the
            ;; etags machinery aborts cleanly; the user re-runs M-. / M-? and the
            ;; freshly-built GTAGS now answers via ggtags' xref backend.
            nil)
        ;; Declined -> honor the original etags behavior (the prompt).
        (apply orig args)))))

(with-eval-after-load 'etags
  (advice-add 'visit-tags-table-buffer :around
              #'fenrir/visit-tags-table-buffer--guide-to-gtags))

(defun fenrir/gtags-prefer-here ()
  "Toggle, in THIS buffer, whether ggtags answers `M-.' / `M-?' BEFORE the LSP.
By default xref dispatches to Eglot first (semantic, scope-aware, one precise
target) and `ggtags--xref-backend' answers only as the no-server fallback.  GNU
Global's flat index is faster for some queries (references / cross-language whole
-repo sweeps) and exists even where no server is attached, so this command flips
the buffer-local `xref-backend-functions' to consult ggtags FIRST; a second call
flips back.  Buffer-local only -- never changes the global default, and never
touches the careful Eglot-first ordering in other buffers.  Trade-off when on:
ggtags is text/symbol based, so `M-.' on a common name (`Get', `New') returns
every textual definition across the repo rather than the single correct one."
  (interactive)
  (require 'ggtags)
  (if (eq (car xref-backend-functions) #'ggtags--xref-backend)
      ;; Currently ggtags-first -> demote back to the appended fallback ggtags-mode
      ;; would normally install (or remove entirely if ggtags-mode isn't on here).
      (progn
        (remove-hook 'xref-backend-functions #'ggtags--xref-backend t)
        (when (bound-and-true-p ggtags-mode)
          (add-hook 'xref-backend-functions #'ggtags--xref-backend nil t))
        (message "gtags: LSP-first restored (ggtags is fallback) in this buffer"))
    ;; Promote ggtags to the front (negative depth); add-hook repositions the
    ;; existing entry rather than duplicating it.
    (add-hook 'xref-backend-functions #'ggtags--xref-backend -90 t)
    (message "gtags: ggtags-first for M-. / M-? in this buffer (C-c g p again to undo)")))

;; Project-scoped keybindings.  `C-c g' is free (the Eglot refactor keys live
;; under `C-c .' / `C-c h' in `eglot-mode-map'; `C-c g' is unused globally).
;;   g g  build / update the index           g d  diagnose & remove nested shadows
;;   g .  find-tag-dwim (def<->ref)           g r  find references
;;   g s  find symbols with no definition     g f  find file by name (via GTAGS)
;;   g /  full-text grep over indexed files   g p  toggle ggtags-first M-. here
;; The g.{.,r,s,f,/} group puts the explicit ggtags searches (which bypass xref
;; dispatch and hit `global' directly) one chord away, so gtags is always usable
;; even in a buffer where Eglot owns M-. -- "resident" access without a daemon
;; (global is a stateless CLI over the on-disk index; there is nothing to keep
;; running, only the index to keep present + the keys to keep handy).
(global-set-key (kbd "C-c g g") #'fenrir/gtags-create-or-update)
(global-set-key (kbd "C-c g d") #'fenrir/gtags-diagnose-duplicates)
(global-set-key (kbd "C-c g .") #'ggtags-find-tag-dwim)
(global-set-key (kbd "C-c g r") #'ggtags-find-reference)
(global-set-key (kbd "C-c g s") #'ggtags-find-other-symbol)
(global-set-key (kbd "C-c g f") #'ggtags-find-file)
(global-set-key (kbd "C-c g /") #'ggtags-grep)
(global-set-key (kbd "C-c g p") #'fenrir/gtags-prefer-here)

;; tree-sitter (built-in in 30): faster, more accurate syntax via *-ts-mode.
;; `treesit-auto' installs grammars on demand and remaps classic modes to their
;; tree-sitter equivalents (python-mode -> python-ts-mode, etc.).
;;
;; `treesit-install-language-grammar' installs to ~/.emacs.d/tree-sitter/ and
;; adds that dir to `treesit-extra-load-path' for the current session only.
;; Without this `add-to-list', next startup can't find the installed .so files
;; and we get "cannot open shared object file" warnings for go/gomod/etc.
(add-to-list 'treesit-extra-load-path
             (expand-file-name "tree-sitter" user-emacs-directory))

(use-package treesit-auto
  :custom (treesit-auto-install t)        ; auto-install missing grammars on first use
  :config
  ;; Opt out of tree-sitter for languages where the built-in mode is good
  ;; enough and the ABI churn isn't worth it.  Currently:
  ;;   css  -- upstream grammar jumped to ABI 15 in v0.25.0 (May 2024);
  ;;           Emacs 30.1 maxes at ABI 14, so every css-ts-mode buffer
  ;;           emits "version-mismatch: 15" warnings.  Built-in `css-mode'
  ;;           covers our use cases (Vue <style> blocks go through Volar).
  ;;   json -- simple grammar; built-in `js-json-mode' is fine and the
  ;;           LSP (vscode-json-language-server) does the heavy lifting.
  ;;   lua  -- `tree-sitter-grammars/tree-sitter-lua' is also ABI 15 at HEAD
  ;;           (verified 2026-05-19: `treesit-auto-install' freshly cloned +
  ;;           compiled the grammar and STILL produced ABI 15).  No
  ;;           ABI-14-compatible tag exists upstream.  Fall back to MELPA
  ;;           `lua-mode' (regex-based, see `languages/init-lua.el') for
  ;;           highlighting; revisit if/when upstream tags ABI 14 or Emacs
  ;;           lifts the ABI cap.
  ;; All three modes are still hooked to eglot in their language modules; we
  ;; just lose the tree-sitter font-lock / structural navigation, which is
  ;; no real loss for these grammars.
  (setq treesit-auto-langs (seq-difference treesit-auto-langs '(css json lua)))
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;; combobulate: structural editing driven by the tree-sitter parse tree.
;; Where `expand-region' grows by lisp sexps (and gets it wrong in most
;; non-Lisp languages), combobulate operates on REAL syntactic nodes -- "the
;; if-statement", "this function's parameter list", "the current JSX element"
;; -- so motions and edits respect language structure.
;;
;; Why this earns its slot in a config that already has multiple-cursors,
;; expand-region and Eglot's LSP rename:
;;   * Sibling navigation (`M-a' / `M-e') jumps between cases of a switch, list
;;     elements, JSX children, method definitions in a class -- without
;;     fiddling with regex search.
;;   * `M-<' / `M->' swap siblings -- reorder list items / function args / JSX
;;     attributes without re-indenting by hand.
;;   * `M-h' marks the current node; repeat to climb to the enclosing node.
;;     Composes with delete-selection-mode: mark `M-h M-h`, type replacement.
;;   * `C-c o n' renames the current identifier across its lexical scope WITHOUT
;;     an LSP -- works in buffers where Eglot isn't attached (e.g. JSON/YAML
;;     keys, Markdown code blocks) and is instant.
;;
;; This block only DECLARES the package (`:vc' install + `:commands' autoload +
;; the key prefix).  The per-language `combobulate-mode' hooks live in the
;; language modules: python / go / js / ts / tsx (in `languages/init-python.el',
;; `init-go.el', `init-typescript.el').  rust-ts-mode, c-ts-mode and c++-ts-mode
;; are deliberately NOT hooked -- combobulate has no support for them (2026-05).
;; Inside .vue files combobulate doesn't activate in the embedded js / ts chunks
;; -- vue-mode's MMM sub-buffer mechanism doesn't fire combobulate's mode hook
;; there (a known limitation, not a bug here).
;;
;; Source: GitHub only -- not on MELPA.  `:vc' is the Emacs 30 use-package
;; keyword that calls `package-vc-install' on first run (no straight.el /
;; quelpa needed).  Subsequent starts are no-ops.  To update later:
;;   M-x package-vc-upgrade RET combobulate RET
;; First load may take ~3s as Emacs byte-compiles the language adapters.
(use-package combobulate
  :vc (:url "https://github.com/mickeynp/combobulate" :rev :newest)
  :commands combobulate-mode
  :custom
  ;; Default `C-c o' -- spelled out so the prefix is visible at the call
  ;; site (and easy to retarget if it ever clashes with a new mode binding).
  (combobulate-key-prefix "C-c o"))

;; treesit-fold: code folding driven by the tree-sitter PARSE TREE -- the
;; structural complement to hideshow (`C-c @' cockpit, init-editing.el).
;; hideshow folds by braces / sexps / indentation: fine for C-like and Lisp,
;; weak for Python and other indentation-structured languages.  treesit-fold
;; folds REAL nodes (function bodies, class bodies, if / for blocks, JSX
;; elements), so Python and every grammar-backed language fold accurately --
;; fixing hideshow's documented Python weakness.
;;
;; Coexistence with hideshow: where NO parser exists (css / json / lua --
;; excluded from `treesit-auto-langs' above) treesit-fold silently no-ops and
;; hideshow stays the fold mechanism, so the two never fight over the same
;; buffer.
;;
;; Own prefix `C-c z' -- deliberately NOT `C-c @' (hideshow owns it) and NOT
;; `C-c o' (combobulate's `combobulate-key-prefix').  All three minor modes can
;; be live in one tree-sitter buffer, so a shared prefix would collide.  Keys:
;;   z t  toggle      z h  hide (close)   z s  show (open)
;;   z H  hide all    z S  show all       z r  open recursively
;;
;; TTY: folds render as an overlay ellipsis on the folded line -- no fringe, no
;; child frame.  `treesit-fold-indicators-mode' (fringe gutter bitmaps) is left
;; OFF on purpose: the fringe doesn't exist in `emacsclient -nw' frames.
;;
;; First-run note: already in elpa/ (was installed but unwired before this
;; block), so no refresh needed.  `global-treesit-fold-mode' turns it on
;; wherever a tree-sitter parser is active.
(use-package treesit-fold
  :init (global-treesit-fold-mode 1)
  :bind (:map treesit-fold-mode-map
              ("C-c z t" . treesit-fold-toggle)
              ("C-c z h" . treesit-fold-close)
              ("C-c z s" . treesit-fold-open)
              ("C-c z H" . treesit-fold-close-all)
              ("C-c z S" . treesit-fold-open-all)
              ("C-c z r" . treesit-fold-open-recursively)))

;; flymake (built-in): on-the-fly diagnostics; Eglot feeds it from the LSP.
;;
;; `M-n' / `M-p' walk the diagnostics in THIS buffer.  The `C-c !' cluster
;; (flymake's own conventional prefix, verified free here) adds the list views:
;;   `C-c ! l'  this buffer's diagnostics as a jumpable tabulated list
;;   `C-c ! p'  the PROJECT-WIDE diagnostics list -- the cross-file error
;;              surface the config otherwise lacks (consult-flymake on `M-g f'
;;              and sideline-flymake are both single-buffer).  Pairs with Eglot
;;              workspace `diagnosticMode'.
;;   `C-c ! c'  show the full diagnostic at point in a help buffer (more than
;;              the one-line echo-area / sideline rendering).
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :bind (:map flymake-mode-map
              ("M-n" . flymake-goto-next-error)
              ("M-p" . flymake-goto-prev-error)
              ("C-c ! l" . flymake-show-buffer-diagnostics)
              ("C-c ! p" . flymake-show-project-diagnostics)
              ("C-c ! c" . flymake-show-diagnostic)))

;; sideline + sideline-flymake: VSCode-style "Error Lens" inline diagnostics.
;;
;; Why this matters on a TTY-only setup: Flymake's default surfaces are the
;; fringe (GUI-only bitmaps -- invisible in `emacsclient -nw') and the echo
;; area (single line, gets clobbered by `message' callers, dies the moment
;; you move point).  `M-n' / `M-p' let you walk the diagnostic list but the
;; full text only ever shows in that narrow echo slot.  sideline renders the
;; message to the RIGHT of the line in the buffer itself via overlay
;; `after-string' -- works identically in TTY and GUI, no fringe / child
;; frame dependency.
;;
;; `sideline-flymake-display-mode 'point' shows the diagnostic ONLY for the
;; line containing point; the alternative `line' shows on every diagnostic
;; line which is unbearable in any non-toy buffer.  `point' tracks cursor
;; movement, so the message follows you to the next error (M-n / M-p).
;; `'point' is already sideline-flymake's default; spelled out so the value
;; is visible at the call site rather than buried in upstream's defcustom.
;;
;; Hooked on `flymake-mode' rather than `prog-mode' so sideline only activates
;; where there's actually something to display -- Flymake itself is hooked on
;; `prog-mode' above, so the net effect is identical, but the dependency is
;; explicit ("UI follows the data source").
;;
;; sideline + sideline-flymake aren't in elpa/ on a fresh clone -- run
;; `M-x my/package-refresh' once and restart the daemon to pull them.
(use-package sideline
  :hook (flymake-mode . sideline-mode)
  :custom
  (sideline-backends-right '(sideline-flymake)))

(use-package sideline-flymake
  :after sideline
  :custom
  (sideline-flymake-display-mode 'point))

;; apheleia: async format-on-save.  Why not `eglot-format-buffer':
;; typescript-language-server explicitly does NOT implement textDocument/
;; formatting (their README points at Prettier).  Apheleia runs the formatter
;; in a subprocess, diffs the output against the buffer, and applies the
;; minimal edit -- so point / mark / window-start don't jump, and the save
;; isn't blocked on the formatter.  Default formatter table maps:
;;     js/ts/tsx/jsx/css/scss/html/json/md  -> prettier
;;     python  -> black + isort
;;     go      -> gofmt + goimports
;;     rust    -> rustfmt
;; Override on a per-mode basis via `apheleia-mode-alist' if a project pins
;; a different tool (e.g. biome, ruff format).  `apheleia-global-mode' is
;; opt-in per buffer -- it only formats when the formatter binary is on PATH
;; AND the major mode has an entry, so it stays quiet in unrelated buffers.
;; (`languages/init-vue.el' adds the `vue-mode' -> prettier entry.)
(use-package apheleia
  :config
  (apheleia-global-mode +1))

;; ansi-color (built-in): interpret SGR escape sequences in `compilation-mode'
;; buffers so colorized build/test output renders as faces instead of raw
;; `^[[32m' noise.  Wired here (shared build infra) rather than in any one
;; language module because `compilation-filter-hook' is global -- it benefits
;; every `M-x compile' / `recompile' command (cargo, npm, pytest, and the Go
;; test runner `fenrir/go-run-test' in lisp/languages/init-go.el).
;;
;; KEY PROPERTY: this preserves error navigation.  The filter only consumes the
;; SGR control bytes and applies the equivalent `face' text property to the
;; surrounding text -- it never moves or rewrites the `file:line' tokens, so
;; `compilation-mode's error regexp still matches and `M-g M-n' /
;; `next-error' jump to failures exactly as before.  vterm would give colors
;; too but throws those clickable jumps away; this keeps both.
;;
;; CAVEAT for Go: plain `go test -v' emits NO color, so this filter is a no-op
;; for `fenrir/go-run-test' as written -- it lights up only once the command is
;; swapped for a colorizing runner (e.g. `gotestsum --format testname',
;; `richgo test', or rakyll's `gotest').  The filter is wired now so any such
;; tool -- and every other already-colorizing compile command -- just works.
(use-package ansi-color
  :ensure nil
  :hook (compilation-filter . ansi-color-compilation-filter))

;; dape: Debug Adapter Protocol client.  The Eglot-spirit counterpart to
;; dap-mode -- core-only deps (jsonrpc), no lsp-mode, no child frames.
;; Breakpoints render in the buffer MARGIN ("B"), not the fringe, so they
;; stay visible on TTY frames (this whole config is daemon + emacsclient -nw).
;; That margin-vs-fringe difference is exactly why dap-mode is rejected here:
;; its fringe-bitmap breakpoints are invisible on a terminal frame.
;;
;; dape ships built-in `dape-configs' entries for debugpy / dlv / codelldb /
;; gdb / js-debug -- you install the adapter BINARY, not write configs.  Only
;; `dlv' (Go) is on PATH today; other languages need their adapter installed
;; before `M-x dape' can debug them.  Per-project overrides: `.dir-locals.el'.
;;
;; `repeat-mode' (enabled in init-defaults) makes step/continue repeatable
;; without re-pressing the `C-x C-a' prefix each time.
(use-package dape
  :custom
  (dape-buffer-window-arrangement 'right)  ; info + REPL docked right
  (dape-info-hide-mode-line t)             ; reclaim modeline in info buffers
  (dape-inlay-hints t)                     ; variable values shown inline
  :hook
  ;; Persist breakpoints across Emacs sessions.
  (kill-emacs . dape-breakpoint-save)
  (after-init . dape-breakpoint-load)
  :config
  ;; Save modified buffers before a run -- matters for interpreted langs.
  (add-hook 'dape-start-hook (lambda () (save-some-buffers t t))))

(provide 'init-languages)
;;; init-languages.el ends here
