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
;;   routing, treesit-auto, combobulate (package only -- hooks live per
;;   language), flymake, sideline, apheleia, dape.  (gtags/GNU Global moved to
;;   [`init-tags.el'](init-tags.el) in the 2026-07-30 toolchain rebuild.)
;;
;; The per-language modules attach their own hooks via `add-hook' /
;; `use-package' and register their server's `eglot-workspace-configuration'
;; entry via `(with-eval-after-load 'eglot (setf (alist-get :SERVER ...) ...))'.
;; This module MUST load before them (it declares the eglot / combobulate
;; packages whose autoloaded commands those hooks reference).

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
in [`init-tags.el'](init-tags.el), the gtags-side guard against the same
degeneration)."
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
  ;; The default `((t . maybe-summary))' pops a confirmation/diff prompt --
  ;; noisy for any rename that touches more than three files.  nil applies
  ;; refactors in one go; the aggregate diff still lands in `git diff' for
  ;; review before commit.  (This is the Eglot 1.16+ name; the old
  ;; `eglot-confirm-server-initiated-edits' is an obsolete alias -- custom.el
  ;; already recorded the value under the new name.)
  (eglot-confirm-server-edits nil)
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
;; Bound on `M-g e' ("eglot symbols") only inside `eglot-mode-map' -- the key
;; is meaningless in non-LSP buffers.  NOT `M-g s': avy already claims that
;; globally for `avy-goto-symbol-1' (init-editing.el), so binding it here too
;; would shadow avy in every Eglot buffer instead of "a future major mode".
;; Needs an Eglot session live in the current buffer; in a buffer without
;; one, the command errors out clearly rather than silently returning
;; nothing.  (`languages/init-java.el' advises `consult-eglot--transformer'
;; to survive jdt:// results.)
(use-package consult-eglot
  :after (consult eglot)
  :bind (:map eglot-mode-map
              ("M-g e" . consult-eglot-symbols)))

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

;; Eglot progress reporting -> echo area (rust-analyzer indexing, gopls, jdtls
;; import, ...).  `eglot-report-progress' = `messages' routes every server's
;; `$/progress' work-done reports through a `progress-reporter', so each update
;; shows transiently in the echo area -- WITHOUT touching the header line
;; (breadcrumb keeps it) or the mode line.  (Verified: the spinner updates are
;; echo-area only; they are NOT accumulated into *Messages*, which is cleaner --
;; visible while running, no log spam after.)  Rationale for not using the
;; default `t': that draws Eglot's built-in mode-line progress segment, which
;; doom-modeline (init-appearance.el) drops, so nothing showed; and a custom
;; header-line renderer looked cluttered against breadcrumb.  The `messages'
;; path is built-in and needs no renderer.  NOTE: this is read at connection
;; time (it also gates the `workDoneProgress' client capability), so it only
;; affects servers started AFTER it is set -- a live server needs
;; `M-x eglot-reconnect'.
(setq eglot-report-progress 'messages)

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
  ;; Both modes are still hooked to eglot in their language modules; we just
  ;; lose the tree-sitter font-lock / structural navigation, which is no real
  ;; loss for these grammars.
  ;;
  ;; NOT excluded (handled by an ABI-14 pin instead -- the better fix when an
  ;; ABI-14 tag exists upstream): c, lua, rust.  These stay in
  ;; `treesit-auto-langs' and their language modules pin the grammar to its
  ;; newest ABI-14 tag via the `abi14-revision' recipe slot, so treesit-auto
  ;; auto-installs a loadable grammar instead of ABI-15 HEAD -- see
  ;; `languages/init-c-cpp.el' (c, v0.23.6), `languages/init-lua.el' (lua,
  ;; v0.3.0; was excluded here until 2026-06-08, when v0.3.0 was found to be a
  ;; valid ABI-14 tag), and `languages/init-rust.el' (rust, v0.23.3).  Each pin
  ;; also has a standalone Makefile deployer under `rust/treesit-grammar*/'.
  (setq treesit-auto-langs (seq-difference treesit-auto-langs '(css json)))
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
;; Coexistence with hideshow: where NO parser exists (css / json --
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

;; Make error-hopping repeatable: after `M-n' / `M-p' (flymake-goto-next/prev-
;; error above), bare `n' / `p' continue stepping through diagnostics until any
;; other key -- the "cycle problems" gesture of a modern IDE.  `repeat-mode' is
;; already on (init-defaults.el); `:repeat t' joins these commands to it.
(defvar-keymap fenrir/flymake-error-repeat-map
  :doc "Repeat map for flymake error navigation (see `repeat-mode')."
  :repeat t
  "n" #'flymake-goto-next-error
  "p" #'flymake-goto-prev-error)

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
  :hook (after-init . apheleia-global-mode))

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
