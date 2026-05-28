;;; init-languages.el --- Project, LSP & languages -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 8 of the pre-split monolithic init.el (see git log for the move).
;; The largest section: project.el, envrc, Eglot (+ eglot-booster, consult-eglot),
;; vue-mode, eldoc display routing, ggtags, treesit-auto, lua-mode, combobulate,
;; flymake, flymake-eslint, apheleia, markdown-mode.

;;; Code:

(require 'cl-lib)        ; cl-letf* (jdt:// consult-eglot guard), cl-remove-if-not

;; project.el (built-in): project-aware file/buffer/command commands under C-x p.
;; ~/ itself is a git repo (the dotfiles tree).  Two interacting problems:
;;   1. project.el would otherwise treat all of $HOME as one giant project and
;;      project-find-file would walk the whole home directory.  Fixed by the
;;      :around advice on `project-try-vc' that returns nil when the root is $HOME.
;;   2. Sub-directories inside the dotfiles repo that don't have their own .git
;;      (e.g. ~/.emacs.d/, ~/.config/<foo>/) would also be killed by (1) because
;;      `vc-find-root' walks up to ~/.git.  Fixed by `project-vc-extra-root-markers':
;;      if any of those marker files exists in a closer ancestor, that ancestor
;;      becomes the project root, the advice sees a non-$HOME root, and lets it
;;      through.  Drop an empty `.project' file in any dir you want treated as
;;      a project (or rely on the language-native markers below).
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
    "If `project-try-vc' would return $HOME as the project root, ignore it."
    (let ((proj (funcall orig-fun dir)))
      (if (and proj
               (string= (expand-file-name (project-root proj))
                        (expand-file-name "~/")))
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
;; `obarray-make' rather than `fillarray'.
(defun fenrir/project-reset-cache ()
  "Wipe all `vc-file-setprop' caches.  Use after editing
`project-vc-extra-root-markers' or any time project root detection
seems stuck on a stale answer."
  (interactive)
  (setq vc-file-prop-obarray (obarray-make 17))
  (message "vc-file-prop-obarray cleared"))

;; Java/Maven workspace-root finder.  The default `project-try-vc' +
;; `project-vc-extra-root-markers' approach picks the FIRST (= deepest)
;; ancestor that has `.project' walking up from the file.  Eclipse m2e (which
;; jdtls bundles) auto-generates `.project' inside every Maven module on
;; import, so even if a developer drops a single `.project' at the monorepo
;; root, the import re-creates deeper ones and the next `project-current'
;; call snaps back to the wrong (too-deep) module.
;;
;; This finder resolves a Java buffer's project in two tiers:
;;
;;   Tier 1 (container marker): if any ancestor holds
;;     `fenrir/java-workspace-marker' (default `.eglot-java-workspace'), that
;;     ancestor is THE root for every Java file beneath it.  Use this to fuse
;;     several independent Maven/Gradle reactors sitting under one container
;;     dir (e.g. ~/code/hitok2/ holding im-combined-hitok + im-combined-api +
;;     hitok-java-backend) into a SINGLE Eglot server -> SINGLE jdtls Eclipse
;;     workspace, so cross-project find-references / navigation work and you
;;     never spawn a second jdtls (which would fight over the shared `-data').
;;     Pair with `java.import.exclusions' (see the :java workspace config) to
;;     keep jdtls from importing non-Java subtrees under the container.
;;
;;   Tier 2 (topmost-pom): otherwise return the TOPMOST consecutive ancestor
;;     with `pom.xml' / `build.gradle*' -- the multi-module reactor root for a
;;     standalone Maven/Gradle project.  Ignores `.project' markers entirely.
;;
;; Non-Java files (no marker in either tier) return nil so `project-try-vc'
;; still owns them.
;;
;; Return shape matches `project-try-vc's `(list 'vc BACKEND ROOT)' so that
;; eglot's session hash (keyed on the project object) sees the SAME key
;; regardless of which `project-find-functions' entry resolved a given
;; buffer.  Otherwise sibling buffers in the same workspace would spawn
;; separate jdtls sessions.
(defcustom fenrir/java-workspace-marker ".eglot-java-workspace"
  "Filename that pins a directory as a unified jdtls workspace root.
When present in an ancestor of a Java file, that ancestor becomes the
project root for ALL Java files beneath it, fusing multiple independent
Maven/Gradle reactors under one container into a single Eglot server.
Takes precedence over the topmost-pom heuristic."
  :type 'string
  :group 'fenrir)

(defun fenrir/project-find-java-build-root (dir)
  "Resolve DIR's Java project root as a project object (a (vc BACKEND ROOT) list).
Tier 1: the nearest ancestor containing `fenrir/java-workspace-marker'.
Tier 2: the topmost consecutive ancestor with a Maven/Gradle build file.
Returns nil if neither applies, deferring to other `project-find-functions'."
  (let* ((d (file-name-as-directory (expand-file-name (or dir default-directory))))
         ;; `abbreviate-file-name' so the project path matches what
         ;; `project-try-vc' produces elsewhere -- otherwise sibling buffers
         ;; spawn separate eglot sessions because `equal' on the project
         ;; struct compares "~/..." vs "/home/..." paths byte-for-byte.
         (as-project
          (lambda (root)
            (let ((r (file-name-as-directory (expand-file-name root))))
              (list 'vc (ignore-errors (vc-responsible-backend r))
                    (abbreviate-file-name r)))))
         (container (locate-dominating-file d fenrir/java-workspace-marker)))
    (if container
        (funcall as-project container)
      (let* ((markers '("pom.xml" "build.gradle" "build.gradle.kts"
                        "settings.gradle" "settings.gradle.kts"))
             (has-marker
              (lambda (dd)
                (and dd (seq-some (lambda (m) (file-exists-p (expand-file-name m dd)))
                                  markers))))
             (cur d)
             (root nil))
        (while (and cur (not (string-equal cur "/")) (not (funcall has-marker cur)))
          (let ((up (file-name-directory (directory-file-name cur))))
            (setq cur (and (not (string-equal up cur)) up))))
        (when (and cur (funcall has-marker cur))
          (setq root cur)
          (let ((up (file-name-directory (directory-file-name cur))))
            (while (and up (not (string-equal up "/")) (funcall has-marker up))
              (setq root up
                    up (file-name-directory (directory-file-name up))))))
        (when root (funcall as-project root))))))

;; Place AHEAD of `project-try-vc' so Java/Maven roots win the `.project'
;; race.  `project-find-functions' is run in order, first non-nil wins.
(add-to-list 'project-find-functions #'fenrir/project-find-java-build-root)

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
;; Node.js / frontend server install (one-time, npm globals):
;;     npm i -g typescript typescript-language-server     ; JS / TS / TSX
;;     npm i -g vscode-langservers-extracted              ; HTML / CSS / JSON / ESLint
;;     npm i -g prettier                                  ; used by apheleia, see below
;; `vscode-langservers-extracted' ships four binaries Eglot's default
;; `eglot-server-programs' already knows about:
;;     vscode-html-language-server  vscode-css-language-server
;;     vscode-json-language-server  vscode-eslint-language-server
;; The ESLint one is NOT auto-attached -- Eglot binds one server per major
;; mode and TypeScript already wins.  ESLint runs via `flymake-eslint' below
;; (no LSP -- it execs `node_modules/.bin/eslint' directly), which co-exists
;; cleanly with the running tsserver.
;;
;; TSX / JSX note: `.tsx' files open in `tsx-ts-mode' (not `typescript-ts-mode'),
;; courtesy of `treesit-auto'.  `.jsx' likewise reuses the TSX parser.  Both
;; are covered by the `tsx-ts-mode' hook below.
(use-package eglot
  :ensure nil
  :hook ((python-ts-mode . eglot-ensure)
         (go-ts-mode      . eglot-ensure)
         (rust-ts-mode    . eglot-ensure)
         (js-ts-mode      . eglot-ensure)
         (typescript-ts-mode . eglot-ensure)
         (tsx-ts-mode     . eglot-ensure)   ; React .tsx / .jsx
         ;; CSS / HTML / JSON intentionally use the *built-in* modes (not the
         ;; *-ts-mode tree-sitter variants).  These grammars are simple enough
         ;; that the regex-based built-ins are accurate, and skipping them
         ;; sidesteps the tree-sitter ABI treadmill (Emacs 30 caps at ABI 14,
         ;; tree-sitter-css v0.25+ is ABI 15 -> warnings).  Inside .vue files
         ;; the <style> / <template> blocks are handled by Volar anyway.
         (css-mode        . eglot-ensure)
         (html-mode       . eglot-ensure)   ; covers mhtml-mode (derived)
         (js-json-mode    . eglot-ensure)   ; built-in JSON mode
         (c-ts-mode       . eglot-ensure)
         (c++-ts-mode     . eglot-ensure)
         ;; Lua attaches on the regex-based `lua-mode', NOT `lua-ts-mode' --
         ;; tree-sitter-lua is ABI 15 (see the treesit-auto exclusion below),
         ;; so .lua files never reach the *-ts-mode.  Eglot 30.1's default
         ;; `eglot-server-programs' already maps `lua-mode' to the
         ;; `lua-language-server' binary (install per the lua-mode block).
         (lua-mode        . eglot-ensure)
         ;; Java attaches on BOTH `java-mode' (built-in regex) and `java-ts-mode'
         ;; (tree-sitter) -- treesit-auto remaps .java files to the ts variant
         ;; when the grammar is installed, but the non-ts hook is kept for
         ;; safety on machines that haven't grabbed the grammar yet.  The
         ;; jdtls launcher entry, `:java' workspace-configuration, and the
         ;; jdt:// URI handler all live in the dedicated Java block lower down
         ;; in this file -- see `fenrir/jdtls-launch-command'.
         (java-mode       . eglot-ensure)
         (java-ts-mode    . eglot-ensure)
         ;; Inlay hints: parameter names, inferred types, `&` references etc.
         ;; rendered inline by the language server.  Built-in in Emacs 30 --
         ;; no external package.  `eglot-managed-mode' is the hook that fires
         ;; once Eglot has attached to a buffer (every entry above eventually
         ;; lands there via `eglot-ensure'), so this single line covers all
         ;; the languages already hooked.  Toggle per-buffer at runtime with
         ;; `M-x eglot-inlay-hints-mode'.  If a specific language's hints turn
         ;; out too noisy, disable in that mode's hook rather than globally.
         (eglot-managed-mode . eglot-inlay-hints-mode))
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
  ;; Per-server `workspace/configuration': pushed via
  ;; `workspace/didChangeConfiguration' on session start, and re-served
  ;; when a server polls.  Eglot turns this alist into JSON; the section
  ;; keys mirror VSCode's `settings.json' structure.  Without this block
  ;; every server runs on its ship-default config, which on most servers
  ;; means inlay hints are silently OFF (the `eglot-inlay-hints-mode' hook
  ;; in `:hook' above produces nothing in .ts / .py / .go buffers until
  ;; the *server side* enables hint emission).  Per-project overrides go
  ;; in `.dir-locals.el' under the same variable name.
  (eglot-workspace-configuration
   '(;; gopls: extra static analyses + the full inlay-hint set VSCode's
     ;; Go extension enables by default.  `staticcheck' folds the
     ;; standalone tool's checks into LSP diagnostics; `gofumpt' is
     ;; stricter `gofmt' (apheleia / `M-x eglot-format-buffer' both pick
     ;; this up automatically).
     (:gopls .
             (:staticcheck t
              :gofumpt t
              :analyses (:unusedparams t
                         :shadow t
                         :unusedwrite t
                         :nilness t)
              :hints (:assignVariableTypes t
                      :compositeLiteralFields t
                      :compositeLiteralTypes t
                      :constantValues t
                      :functionTypeParameters t
                      :parameterNames t
                      :rangeVariableTypes t)))
     ;; pyright / basedpyright: workspace-wide diagnostics (default
     ;; "openFilesOnly" silently misses cross-file regressions) plus
     ;; type-checking on "basic" -- catches the obvious wrongs without
     ;; the false-positive flood of "strict".  Bump to "strict" via
     ;; `.dir-locals.el' for codebases that warrant it.
     (:python .
              (:analysis (:typeCheckingMode "basic"
                          :diagnosticMode "workspace"
                          :autoImportCompletions t
                          :inlayHints (:variableTypes t
                                       :functionReturnTypes t
                                       :callArgumentNames t))))
     ;; rust-analyzer: `clippy' as the on-save check (mirrors what you'd
     ;; run in a terminal) and proc-macros expanded so derive macros stop
     ;; showing as "unknown".  `closingBraceHints` 25-line threshold
     ;; matches VSCode's default -- short blocks don't get cluttered.
     (:rust-analyzer .
                     (:checkOnSave (:command "clippy")
                      :procMacro (:enable t)
                      :cargo (:buildScripts (:enable t))
                      :inlayHints (:bindingModeHints (:enable t)
                                   :closingBraceHints (:enable t :minLines 25)
                                   :parameterHints (:enable t)
                                   :typeHints (:enable t)
                                   :chainingHints (:enable t))))
     ;; typescript-language-server / vtsls: parameter + return-type +
     ;; variable type hints all on.  Servers default these to "none" --
     ;; without this block `eglot-inlay-hints-mode' renders nothing in
     ;; .ts / .tsx buffers.  Both `:typescript' and `:javascript' need
     ;; the same payload because tsserver routes .js / .jsx through the
     ;; javascript section, not typescript.
     (:typescript .
                  (:inlayHints (:includeInlayParameterNameHints "all"
                                :includeInlayParameterNameHintsWhenArgumentMatchesName t
                                :includeInlayFunctionParameterTypeHints t
                                :includeInlayVariableTypeHints t
                                :includeInlayVariableTypeHintsWhenTypeMatchesName t
                                :includeInlayPropertyDeclarationTypeHints t
                                :includeInlayFunctionLikeReturnTypeHints t
                                :includeInlayEnumMemberValueHints t)))
     (:javascript .
                  (:inlayHints (:includeInlayParameterNameHints "all"
                                :includeInlayFunctionParameterTypeHints t
                                :includeInlayVariableTypeHints t
                                :includeInlayFunctionLikeReturnTypeHints t)))))
  ;; `C-c .' on `eglot-code-actions' mirrors VSCode's `Ctrl+.' Quick Fix.
  ;; `C-.' is already bound to `embark-act' globally (see init-completion);
  ;; the `C-c' prefix avoids the clash and matches Emacs' convention of
  ;; user-facing commands living under `C-c'.  Scoped to `eglot-mode-map'
  ;; so it doesn't shadow anything in non-LSP buffers.  Two related actions
  ;; -- `eglot-code-action-organize-imports', `eglot-code-action-quickfix'
  ;; -- are intentionally NOT bound: the unified `eglot-code-actions'
  ;; transient already lists them, and adding separate keys clutters the map
  ;; without saving keystrokes.
  :bind (:map eglot-mode-map
              ("C-c ." . eglot-code-actions)))

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

;; vtsls: VSCode's bundled TypeScript server wrapped in an LSP shim
;; (yioneko/vtsls).  Two practical wins over the stock
;; `typescript-language-server' (Eglot's default for *-ts-mode):
;;   * Implements `textDocument/formatting' -- a project without Prettier
;;     can rely on `M-x eglot-format-buffer'.  Apheleia still wins when a
;;     project pins Prettier (it's a sibling subprocess, not LSP).
;;   * Diagnostics closer to VSCode: catches unused imports, narrows
;;     better in conditional blocks, picks up `tsconfig.json' changes
;;     without a manual restart.
;; Install once: `npm i -g @vtsls/language-server'.  The override is
;; gated on `executable-find' so a missing binary silently falls back to
;; the default Eglot wiring -- mirrors the `flymake-eslint-defer-binary-
;; check' pattern further down.  Note the hook list in the eglot block
;; covers `js-ts-mode' too, so the override deliberately claims all three
;; major modes; otherwise tsserver would still own .js while vtsls owned
;; .ts, splitting projects across two server processes for no benefit.
(with-eval-after-load 'eglot
  (when (executable-find "vtsls")
    (add-to-list 'eglot-server-programs
                 '((typescript-ts-mode tsx-ts-mode js-ts-mode)
                   . ("vtsls" "--stdio")))))

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
;; as combobulate above).  Update later: `M-x package-vc-upgrade RET
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
(use-package consult-eglot
  :after (consult eglot)
  :bind (:map eglot-mode-map
              ("M-g s" . consult-eglot-symbols)))

;; ----- Java: Eglot + jdtls --------------------------------------------------
;; Java migrated from lsp-mode to Eglot on the `try/java-on-eglot' branch.
;; Architecture:
;;
;;   * jdtls is launched directly from this config rather than via lsp-java's
;;     `lsp-install-server' machinery.  The bundle still lives at the
;;     historic path `var/lsp-java/eclipse.jdt.ls/server/' (~150 MB,
;;     originally downloaded by lsp-java) so no re-install is needed -- only
;;     the workspace metadata at `var/lsp-java/workspace/' may be wiped
;;     out-of-band to force re-import from scratch.
;;
;;   * `jdt://' URI scheme handler is registered as a `file-name-handler-
;;     alist' entry below.  Without it, M-. into JDK / third-party-jar
;;     classes (which jdtls returns as `jdt://contents/...' URIs) silently
;;     fails -- Eglot leaves non-`file://' URIs unchanged and `find-file-
;;     noselect' then doesn't know what to do with them.  Our handler
;;     resolves contents via jdtls' `java/classFileContents' LSP extension.
;;
;;   * eglot-booster (above) wraps the new connection automatically -- its
;;     `eglot--connect' advice is generic, no Java-specific wiring needed.
;;
;;   * consult-eglot-symbols (above) covers the new sessions through the
;;     same `eglot-mode-map' binding on M-g s.
;;
;;   * dap-java is gone with lsp-mode; Java debug is unsupported in this
;;     config until either dape grows a Java adapter or a manual
;;     java-debug bridge is added.  Use IntelliJ / VSCode for real Java
;;     debugging until then.

(defcustom fenrir/jdtls-bundle-dir
  (expand-file-name "var/lsp-java/eclipse.jdt.ls/server/" user-emacs-directory)
  "Root of the eclipse.jdt.ls server bundle.
Inherited from lsp-java's install location."
  :type 'directory
  :group 'fenrir)

(defcustom fenrir/jdtls-workspace-dir
  (expand-file-name "var/lsp-java/workspace/" user-emacs-directory)
  "Per-project workspace metadata directory for jdtls.
Re-created on first launch.  Delete this directory out-of-band to force
jdtls to re-import all projects from scratch."
  :type 'directory
  :group 'fenrir)

(defun fenrir/jdtls--equinox-launcher ()
  "Resolve the absolute path of org.eclipse.equinox.launcher_*.jar.
The version suffix changes per jdtls release, so we wildcard-glob."
  (car (file-expand-wildcards
        (expand-file-name "plugins/org.eclipse.equinox.launcher_*.jar"
                          fenrir/jdtls-bundle-dir))))

(defun fenrir/jdtls--config-dir ()
  "Resolve the platform-specific Equinox config directory."
  (expand-file-name
   (pcase system-type
     ('gnu/linux  (if (string-match-p "aarch64" system-configuration)
                      "config_linux_arm" "config_linux"))
     ('darwin     (if (string-match-p "aarch64" system-configuration)
                      "config_mac_arm" "config_mac"))
     ('windows-nt "config_win")
     (_ "config_linux"))
   fenrir/jdtls-bundle-dir))

(defun fenrir/jdtls--java-settings ()
  "Build the jdtls `:java' settings plist for the connecting buffer.
Starts from the global `:java' entry of `eglot-workspace-configuration',
then -- when the buffer sits inside a fused container workspace (see
`fenrir/java-workspace-marker') -- DISABLES the Gradle importer.

Why: jdtls' `import.exclusions' does NOT stop Buildship (its Gradle
importer) from descending into excluded subtrees.  A container like
~/code/hitok2/ holds a React Native app (im-pay) whose `android/' Gradle
build references an absent `@react-native/gradle-plugin'; Buildship's
sync of it fails and stalls jdtls' whole init.  The container's real
Java projects are all Maven, so turning Gradle off there loses nothing.
Standalone Gradle projects (no container marker -> their own server)
keep Gradle enabled."
  (let ((base (alist-get :java eglot-workspace-configuration)))
    (if (locate-dominating-file default-directory fenrir/java-workspace-marker)
        (let ((s (copy-tree base)))
          (setf (plist-get s :import)
                (plist-put (plist-get s :import) :gradle '(:enabled :json-false)))
          s)
      base)))

(defun fenrir/jdtls-launch-command (&optional _interactive)
  "Return the argv list to launch jdtls.
Used as the function-form value of an `eglot-server-programs' entry.
JVM args mirror the lsp-java preset: ParallelGC + GCTimeRatio +
AdaptiveSizePolicyWeight (throughput-oriented, beats G1 for index
build), 3G heap (jdtls' 1G default stalls hover/references on any
non-trivial Maven project).

The trailing `:initializationOptions' is Eglot's documented mechanism
for feeding a server its config at the `initialize' request (vs the
later `workspace/didChangeConfiguration').  jdtls reads
`initializationOptions.settings.java' DURING its initial project scan,
so `import.exclusions' there actually keeps Buildship from descending
into excluded subtrees -- pushing the same keys only via
didChangeConfiguration is too late (the Gradle/Maven scan already
started).  `classFileContentsSupport' enables the `jdt://' URI flow the
handler below relies on.  eglot-booster prepends its wrapper to the
PROGRAM part only; the trailing keyword survives untouched."
  (let* ((launcher (fenrir/jdtls--equinox-launcher))
         (config (fenrir/jdtls--config-dir))
         (workspace fenrir/jdtls-workspace-dir)
         (java-settings (fenrir/jdtls--java-settings)))
    (unless launcher
      (user-error
       "jdtls equinox launcher not found under %s -- check `fenrir/jdtls-bundle-dir' or reinstall jdtls"
       fenrir/jdtls-bundle-dir))
    (make-directory workspace t)
    `("java"
      "-Declipse.application=org.eclipse.jdt.ls.core.id1"
      "-Dosgi.bundles.defaultStartLevel=4"
      "-Declipse.product=org.eclipse.jdt.ls.core.product"
      "-Dlog.level=ALL"
      "-Xmx3G" "-Xms200m"
      "-XX:+UseParallelGC" "-XX:GCTimeRatio=4"
      "-XX:AdaptiveSizePolicyWeight=90"
      "-Dsun.zip.disableMemoryMapping=true"
      "--add-modules=ALL-SYSTEM"
      "--add-opens" "java.base/java.util=ALL-UNNAMED"
      "--add-opens" "java.base/java.lang=ALL-UNNAMED"
      "-jar" ,launcher
      "-configuration" ,config
      "-data" ,workspace
      :initializationOptions
      (:settings (:java ,java-settings)
       :extendedClientCapabilities (:classFileContentsSupport t)))))

;; Wire jdtls into Eglot.  The :hook entries that fire `eglot-ensure' for
;; java-mode / java-ts-mode live in the main eglot use-package block above
;; -- this block only adds the per-server launcher + workspace config.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((java-mode java-ts-mode) . ,#'fenrir/jdtls-launch-command))
  ;; Per-server settings (pushed via `workspace/didChangeConfiguration').
  ;; Keys mirror VSCode's Red Hat Java extension `settings.json' schema.
  ;; `:json-false' is Eglot's sentinel for JSON `false' -- bare `nil' would
  ;; serialize to JSON `null'.  Mirror of the lsp-java tuning:
  ;;   * references.includeDecompiledSources / includeAccessors -> false:
  ;;     speeds up find-references on dep-heavy projects.
  ;;   * referencesCodeLens / implementationsCodeLens -> false: removes
  ;;     the overlay that triggers continuous background references queries.
  ;;   * format.onType.enabled -> false: matches Eglot's general policy of
  ;;     not formatting per keystroke (apheleia / format-on-save covers it).
  ;;   * import.maven / import.gradle -> true: jdtls auto-detects which
  ;;     applies per project root.
  ;;   * configuration.maven.userSettings -> ~/.m2/settings-public.xml:
  ;;     the corp ~/.m2/settings.xml has a `mirrorOf=!nexus' HTTP blocker plus
  ;;     an active profile pointing at the internal Nexus at
  ;;     nexus.mosainet.com:8081 / 192.168.130.170:8081 -- both unreachable
  ;;     from the open net, and they make Maven import hang on TCP timeouts
  ;;     (75s+ per missing dep) which then blocks every LSP request through
  ;;     jdtls' main thread.  This points jdtls at a minimal settings.xml
  ;;     that shares ~/.m2/repository but skips the corp profile; CLI `mvn'
  ;;     still uses the default settings.xml unless explicitly given `-s'.
  ;;   * import.exclusions: when a container marker fuses several reactors
  ;;     under one root (see `fenrir/java-workspace-marker'), jdtls scans the
  ;;     WHOLE container.  The defaults skip node_modules / .metadata / etc.;
  ;;     `**/im-pay/**' is added because that subtree is a React Native app
  ;;     whose `android/` Gradle build references an absent
  ;;     `@react-native/gradle-plugin' and hangs/crashes the import.  Add more
  ;;     globs here for any other non-Java subtree under a fused container.
  (setf (alist-get :java eglot-workspace-configuration)
        `(:references (:includeDecompiledSources :json-false
                       :includeAccessors :json-false)
          :referencesCodeLens (:enabled :json-false)
          :implementationsCodeLens (:enabled :json-false)
          :format (:onType (:enabled :json-false))
          :import (:maven (:enabled t)
                   :gradle (:enabled t)
                   :exclusions ["**/node_modules/**"
                                "**/.metadata/**"
                                "**/archetype-resources/**"
                                "**/META-INF/maven/**"
                                "**/im-pay/**"])
          :configuration (:maven (:userSettings ,(expand-file-name "~/.m2/settings-public.xml"))))))

;; ----- jdt:// URI scheme handler --------------------------------------------
;; When M-. lands on a JDK or third-party-jar class, jdtls returns a URI
;; like `jdt://contents/java.base/java.lang/String.class?...'.  Eglot leaves
;; non-`file://' schemes as-is; the returned "path" then routes through
;; `file-name-handler-alist'.  Our handler intercepts `jdt://', finds the
;; live jdtls server, requests source via `java/classFileContents', and
;; inserts the result into the visiting buffer.

(defun fenrir/eglot--jdtls-servers ()
  "Return the list of live Eglot servers backing a jdtls process.
Matches by checking each server's process command line for our bundle path."
  (cl-remove-if-not
   (lambda (server)
     (let ((cmd (mapconcat #'identity
                           (process-command (jsonrpc--process server))
                           " ")))
       (string-match-p (regexp-quote
                        (directory-file-name fenrir/jdtls-bundle-dir))
                       cmd)))
   ;; `eglot--servers-by-project' is a hash-table (project-key -> server list);
   ;; iterating it with `cl-loop for ... in' errors "Wrong type argument: sequencep".
   (let ((all '()))
     (maphash (lambda (_k v) (setq all (append v all)))
              eglot--servers-by-project)
     all)))

(defun fenrir/eglot--find-jdtls-server ()
  "Return any one live Eglot server backing a jdtls process, or nil."
  (car (fenrir/eglot--jdtls-servers)))

(defun fenrir/eglot--jdt-uri-directory ()
  "Return a REAL existing directory to stand in for a `jdt://' URI's dir part.
A `jdt://' URI has no real directory; returning the empty string (the
naive choice) makes `find-file-noselect' set the visiting buffer's
`default-directory' to \"\", which then poisons every path helper that
runs on display / idle -- project.el, breadcrumb, doom-modeline -- with
`(file-name-directory nil)' / `(file-relative-name nil ...)' crashes
(\"Wrong type argument: stringp, nil\"), and only on the FIRST visit
before their caches populate.  Returning the originating jdtls server's
project root instead keeps those helpers on real directories AND lets
`eglot-ensure' in the jdt:// buffer attach to the SAME server (rather
than guessing a transient project).  Falls back to the jdtls bundle dir,
then HOME, so it is never empty or nil."
  (file-name-as-directory
   (expand-file-name
    (or (ignore-errors
          (when-let* ((server (fenrir/eglot--find-jdtls-server)))
            (project-root (eglot--project server))))
        (and (file-directory-p fenrir/jdtls-bundle-dir) fenrir/jdtls-bundle-dir)
        "~/"))))

(defun fenrir/eglot--jdt-uri-handler (operation &rest args)
  "File-name handler for `jdt://' URIs -- relays to `java/classFileContents'."
  (cond
   ((eq operation 'expand-file-name) (car args))
   ((memq operation '(file-exists-p file-readable-p)) t)
   ((memq operation '(file-attributes file-symlink-p file-directory-p)) nil)
   ;; A real directory, NOT "" -- see `fenrir/eglot--jdt-uri-directory'.
   ((eq operation 'file-name-directory) (fenrir/eglot--jdt-uri-directory))
   ((eq operation 'file-name-nondirectory) (car args))
   ((eq operation 'insert-file-contents)
    (let* ((uri (car args))
           (visit (cadr args))
           (server (fenrir/eglot--find-jdtls-server))
           (content (if server
                        (jsonrpc-request server :java/classFileContents
                                         `(:uri ,uri))
                      "// No jdtls Eglot session active. Open a project Java\n// file first so jdtls can serve this class.\n")))
      (insert (or content ""))
      ;; Record the URI as the buffer's file name (re-navigation + eglot need
      ;; it), but do NOT set `buffer-read-only' here.  `insert-file-contents'
      ;; runs BEFORE find-file's `normal-mode'; a read-only buffer makes
      ;; `java-ts-mode' setup (and its hooks) signal "Buffer is read-only",
      ;; which `normal-mode' catches and then leaves the buffer in
      ;; `fundamental-mode' -- the classic "first visit errors, second visit
      ;; (buffer already exists, no re-setup) works".  Read-only is applied
      ;; afterwards by `fenrir/jdt--make-buffer-read-only' on `find-file-hook'.
      (when visit (setq buffer-file-name uri))
      (list uri (length (or content "")))))
   (t
    ;; Fall through for any operation we don't handle: temporarily disable
    ;; ourselves and re-dispatch.
    (let ((inhibit-file-name-handlers
           (cons #'fenrir/eglot--jdt-uri-handler
                 (and (eq inhibit-file-name-operation operation)
                      inhibit-file-name-handlers)))
          (inhibit-file-name-operation operation))
      (apply operation args)))))

(add-to-list 'file-name-handler-alist
             '("\\`jdt://" . fenrir/eglot--jdt-uri-handler))

;; Route jdt:// "files" into java-ts-mode (or java-mode if the tree-sitter
;; grammar isn't available) so eldoc / xref / breadcrumb work in the
;; synthesized buffer.
(add-to-list 'auto-mode-alist
             `("\\`jdt://" . ,(if (treesit-language-available-p 'java)
                                  'java-ts-mode
                                'java-mode)))

;; Make jdt:// buffers read-only AFTER find-file has fully set them up (major
;; mode + mode hooks).  Setting read-only earlier (in the `insert-file-contents'
;; handler) breaks `normal-mode'; see the note there.  Appended (`t') so it runs
;; last on `find-file-hook', after any other hook that might still modify the
;; freshly-loaded buffer.
(defun fenrir/jdt--make-buffer-read-only ()
  "Mark the current buffer read-only if it visits a `jdt://' URI."
  (when (and buffer-file-name (string-prefix-p "jdt://" buffer-file-name))
    (setq buffer-read-only t)))
(add-hook 'find-file-hook #'fenrir/jdt--make-buffer-read-only t)

;; Keep diff-hl OUT of jdt:// buffers.  `global-diff-hl-mode' (init-git.el)
;; turns `diff-hl-mode' on in every buffer that merely HAS a `buffer-file-name'
;; -- and our jdt:// buffers do (the URI).  diff-hl then runs its flydiff timer,
;; whose only "skip" guard is `(file-exists-p buffer-file-name)' -- which our
;; handler answers `t' to.  So flydiff proceeds into `diff-hl-update', calls
;; `vc-backend' on the synthetic URI (-> nil), and the timer dies with
;; "Wrong type argument: stringp, nil" (intermittently, since it is a timer,
;; only on the FIRST visit before the buffer is reused).  A decompiled
;; read-only class has nothing to diff against VCS, so just don't activate.
;; `:before-while' so a nil return skips the real `turn-on-diff-hl-mode';
;; order-independent vs whenever global-diff-hl-mode's find-file-hook fires.
(advice-add 'turn-on-diff-hl-mode :before-while
            (lambda ()
              (not (and buffer-file-name
                        (string-prefix-p "jdt://" buffer-file-name))))
            '((name . fenrir/jdt-no-diff-hl)))

;; Keep org-roam OUT of jdt:// buffers.  `org-roam-db-autosync-mode'
;; (init-org-roam.el) puts `org-roam-db-autosync--setup-file-h' on
;; `find-file-hook'; it runs `org-roam-file-p' on EVERY opened file, which does
;; `(file-relative-name path org-roam-directory)'.  On a jdt:// URI that
;; signals "Wrong type argument: stringp, nil", and because it runs on
;; find-file-hook the error aborts the visit -> the buffer is left in
;; `fundamental-mode' and the user sees `file-relative-name: ... nil'
;; ("first visit errors, second reuses the buffer and works").  A decompiled
;; jar class is never an Org-roam note, so short-circuit `org-roam-file-p' to
;; nil for jdt:// buffers.  `with-eval-after-load' because org-roam loads after
;; this module; `:before-while' returning nil skips org-roam-file-p's body.
(with-eval-after-load 'org-roam
  (advice-add 'org-roam-file-p :before-while
              (lambda (&optional file)
                (let ((f (or file (buffer-file-name (buffer-base-buffer)))))
                  (not (and f (string-prefix-p "jdt://" f)))))
              '((name . fenrir/jdt-no-org-roam))))

;; Skip breadcrumb's PROJECT crumbs in jdt:// buffers.  `breadcrumb-mode'
;; (global) enables in the jdt:// buffer during `normal-mode' and immediately
;; builds its header line; `breadcrumb-project-crumbs' -> `file-relative-name'
;; chokes on the synthetic URI.  Root cause shared by the diff-hl and org-roam
;; cases: our `expand-file-name' handler returns the jdt:// URI verbatim (it
;; must, to keep the URI navigable), but it is NOT an absolute path, so
;; `file-relative-name's internal path split feeds `string-prefix-p' a nil ->
;; "Wrong type argument: stringp, nil".  Because this fires during normal-mode
;; the visit aborts (fundamental-mode + the error the user sees).  Returning nil
;; for jdt:// skips only the project crumbs; the imenu/symbol crumbs (the useful
;; part inside a decompiled class) still render.  `with-eval-after-load' for
;; load order; `:before-while' nil-return skips the crumbs body.
(with-eval-after-load 'breadcrumb
  (advice-add 'breadcrumb-project-crumbs :before-while
              (lambda (&rest _)
                (not (and buffer-file-name
                          (string-prefix-p "jdt://" buffer-file-name))))
              '((name . fenrir/jdt-no-breadcrumb-project))))

;; Skip `vc-refresh-state' in jdt:// buffers.  It runs on `find-file-hook' and
;; calls `(vc-backend buffer-file-name)', which on the non-absolute jdt:// URI
;; hits the same `string-prefix-p' nil (see the breadcrumb note above).  Here
;; the error is non-fatal -- vc-refresh-state wraps it in `with-demoted-errors
;; "VC refresh error: %S"' so the visit still succeeds -- but it spams that
;; message on every first visit.  A decompiled jar class is never under VC, so
;; short-circuit.  vc-hooks is preloaded, so a plain `advice-add' is fine.
(advice-add 'vc-refresh-state :before-while
            (lambda ()
              (not (and buffer-file-name
                        (string-prefix-p "jdt://" buffer-file-name))))
            '((name . fenrir/jdt-no-vc-refresh)))

;; Make `consult-eglot-symbols' (M-g s) survive jdt:// results.  jdtls returns
;; JDK / jar types as `jdt://contents/...' URIs.  consult-eglot's
;; `consult-eglot--transformer' builds each candidate's display label with
;; `(file-relative-name (eglot-uri-to-path uri))'; `eglot-uri-to-path' leaves a
;; jdt:// URI unchanged (it is not a `file://' URI), and `file-relative-name'
;; then signals "Wrong type argument: stringp, nil" on the non-absolute jdt://
;; path -- the SAME class of bug guarded for diff-hl / breadcrumb / org-roam /
;; vc-refresh above.  It bites harder here: the transformer runs per candidate
;; inside `consult--async-map', and one throwing candidate aborts the WHOLE
;; refresh, so any Java `workspace/symbol' search that returns a jar/JDK type
;; (i.e. nearly every type search -- even `Event' pulls in java.util.* etc.)
;; errors out before showing anything.  Scope a jdt://-safe `file-relative-name'
;; to the transformer via `cl-letf' (no global override, no per-call overhead
;; elsewhere): for a jdt:// URI return the URI minus its giant `?...' query
;; string as the display label (e.g. "jdt://contents/rt.jar/java.awt.event/
;; PaintEvent.java").  The JUMP path is untouched -- selecting a candidate goes
;; through `consult-eglot--symbol-information-to-grep-params' ->
;; `eglot-uri-to-path' -> `find-file' -> our jdt:// handler, none of which calls
;; `file-relative-name'.  `with-eval-after-load' because consult-eglot loads
;; lazily (`:after (consult eglot)').
(with-eval-after-load 'consult-eglot
  (advice-add 'consult-eglot--transformer :around
              (lambda (orig sym)
                (cl-letf* ((frn (symbol-function 'file-relative-name))
                           ((symbol-function 'file-relative-name)
                            (lambda (file &optional dir)
                              (if (and (stringp file) (string-prefix-p "jdt://" file))
                                  (car (split-string file "?"))
                                (funcall frn file dir)))))
                  (funcall orig sym)))
              '((name . fenrir/jdt-consult-eglot-transformer))))

;; ----- Workspace folder bulk-add (Maven / Gradle scan) ----------------------
;; Mirror of the old `fenrir/lsp-java-add-roots-under'.  For a single
;; monorepo, project.el's root detection is usually enough -- drop a
;; `.project' marker at the monorepo root and jdtls auto-imports every
;; pom.xml / build.gradle underneath.  This helper is for the rarer case
;; where one container dir holds multiple unrelated Java projects
;; (e.g. ~/code/ with sibling repos at varying depths).

(defvar fenrir/eglot-java-scan-skip-dirs
  '("target" "build" "node_modules" "out" "dist" "vendor"
    ".gradle" ".idea" ".mvn" ".m2")
  "Directory basenames never descended into during the Maven / Gradle scan.")

(defun fenrir/eglot-java--scan-roots (dir markers)
  "Return absolute paths of Java build roots reachable from DIR (inclusive).
A directory counts as a root if any of MARKERS exists at its top level;
once matched, descent into that directory stops."
  (let ((results '())
        (queue (list (expand-file-name dir))))
    (while queue
      (let ((d (pop queue)))
        (when (file-directory-p d)
          (if (seq-some (lambda (m) (file-exists-p (expand-file-name m d))) markers)
              (push d results)
            (dolist (child (directory-files d t "\\`[^.]"))
              (when (and (file-directory-p child)
                         (not (file-symlink-p child))
                         (not (member (file-name-nondirectory child)
                                      fenrir/eglot-java-scan-skip-dirs)))
                (push child queue)))))))
    (nreverse results)))

(defun fenrir/eglot-java-add-roots-under (dir)
  "Register every Maven / Gradle root under DIR as a jdtls workspace folder.
Sends `workspace/didChangeWorkspaceFolders' to the live jdtls Eglot
session.  Interactive call prompts for DIR (default ~/code/)."
  (interactive (list (read-directory-name "Container dir: " "~/code/")))
  (require 'eglot)
  (let* ((markers '("pom.xml"
                    "build.gradle" "build.gradle.kts"
                    "settings.gradle" "settings.gradle.kts"))
         (roots (fenrir/eglot-java--scan-roots dir markers))
         (server (fenrir/eglot--find-jdtls-server)))
    (unless server
      (user-error "No jdtls Eglot session active; open a Java file first"))
    (when roots
      (jsonrpc-notify
       server :workspace/didChangeWorkspaceFolders
       `(:event (:added
                 ,(apply #'vector
                         (mapcar (lambda (r)
                                   `(:uri ,(eglot-path-to-uri r)
                                     :name ,(file-name-nondirectory
                                             (directory-file-name r))))
                                 roots))
                 :removed []))))
    (message "eglot-java: registered %d root(s) under %s: %s"
             (length roots)
             (abbreviate-file-name (expand-file-name dir))
             roots)))

;; ----- Container workspace marker: set / unset ------------------------------
;; The durable counterpart to `fenrir/eglot-java-add-roots-under'.  Dropping a
;; `fenrir/java-workspace-marker' file makes `fenrir/project-find-java-build-root'
;; Tier 1 fuse every Java reactor beneath that dir into one jdtls workspace --
;; surviving restarts, with no per-session didChangeWorkspaceFolders dance.

(defun fenrir/eglot-java--restart-jdtls ()
  "Shut down all live jdtls sessions so buffers reconnect afresh.
Returns the count shut down.  jdtls re-reads the project layout on the
next connect, so toggling a workspace marker takes effect after this."
  (let ((servers (fenrir/eglot--jdtls-servers)))
    (dolist (s servers) (ignore-errors (eglot-shutdown s 1 nil t)))
    (length servers)))

(defun fenrir/eglot-java-set-workspace-root (dir)
  "Mark DIR as a unified jdtls workspace root.
Creates `fenrir/java-workspace-marker' in DIR so every Java file beneath
it resolves to DIR (Tier 1 of `fenrir/project-find-java-build-root'),
fusing independent Maven/Gradle reactors under DIR into one Eglot server
+ one jdtls Eclipse workspace -- the basis for cross-project
find-references / navigation.  Resets the project cache and offers to
restart any running jdtls session so the new root takes effect.

Interactive default is the current project root, else `default-directory'."
  (interactive
   (list (read-directory-name
          "Java workspace root (drop marker here): "
          (or (ignore-errors (project-root (project-current)))
              default-directory))))
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (marker (expand-file-name fenrir/java-workspace-marker dir)))
    (unless (file-directory-p dir)
      (user-error "Not a directory: %s" dir))
    (unless (file-exists-p marker)
      (with-temp-file marker
        (insert "Marks " (abbreviate-file-name dir) " as a unified jdtls/Eglot\n"
                "workspace root -- read by fenrir/project-find-java-build-root in\n"
                "~/.emacs.d/lisp/init-languages.el.  Every Java file beneath this\n"
                "dir resolves to THIS dir as its project root, so independent\n"
                "Maven/Gradle reactors here share one Eglot server + one jdtls\n"
                "Eclipse workspace (cross-project find-references).  See\n"
                "~/.emacs.d/_doc/JAVA.md.  Created by M-x "
                "fenrir/eglot-java-set-workspace-root.\n")))
    (fenrir/project-reset-cache)
    (let ((n (when (and (fenrir/eglot--jdtls-servers)
                        (y-or-n-p "Marker set.  Restart running jdtls session(s) now? "))
               (fenrir/eglot-java--restart-jdtls))))
      (message "Java workspace root: %s%s"
               (abbreviate-file-name dir)
               (cond ((and n (> n 0))
                      (format " (%d session(s) shut down; reopen a .java file to reconnect)" n))
                     (t " (reopen .java files or M-x eglot to apply)"))))))

(defun fenrir/eglot-java-unset-workspace-root (dir)
  "Remove `fenrir/java-workspace-marker' from DIR (inverse of
`fenrir/eglot-java-set-workspace-root').  Java files beneath DIR then
fall back to the topmost-pom heuristic (Tier 2).  Interactive default is
the nearest ancestor that currently holds the marker."
  (interactive
   (list (read-directory-name
          "Remove Java workspace marker from: "
          (or (locate-dominating-file default-directory fenrir/java-workspace-marker)
              default-directory))))
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (marker (expand-file-name fenrir/java-workspace-marker dir)))
    (unless (file-exists-p marker)
      (user-error "No %s in %s" fenrir/java-workspace-marker (abbreviate-file-name dir)))
    (delete-file marker)
    (fenrir/project-reset-cache)
    (let ((n (when (and (fenrir/eglot--jdtls-servers)
                        (y-or-n-p "Marker removed.  Restart running jdtls session(s) now? "))
               (fenrir/eglot-java--restart-jdtls))))
      (message "Removed Java workspace marker from %s%s"
               (abbreviate-file-name dir)
               (if (and n (> n 0))
                   (format " (%d session(s) shut down)" n) "")))))

;; ----- end Java / Eglot block -----------------------------------------------

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
(use-package breadcrumb
  :hook (prog-mode . breadcrumb-local-mode))

;; vue-mode: syntax highlighting for .vue files only.  Eglot is intentionally
;; NOT hooked here -- Vue's LSP options (Volar 3 in "Hybrid Mode") are
;; sluggish on cold start and the per-request jsonrpc timeouts get noisy in
;; any project bigger than a toy.  Tried it (commit acdf8d6, reverted in
;; favour of this simpler setup); reach for `M-s r' (consult-ripgrep, bound
;; in section 4) for cross-file searches in Vue projects instead -- it
;; catches references uniformly across .vue / .ts / .md, which any LSP
;; scoped to one filetype never can.
;;
;; If you want Volar back: see `git show acdf8d6' for the full wiring
;; (vue-language-server + @vue/typescript-plugin tsserver plugin, tsdk
;; pointer, etc.).  The npm globals (`@vue/language-server',
;; `@vue/typescript-plugin') are left installed -- harmless when unused.
;;
;; `vue-modes' override: the upstream default points `<script lang="ts">' at
;; `typescript-mode' (the legacy SMIE package, not installed here) and bare
;; `<script>' at `js-mode' (regex-based, no ES2020+).  Without this override
;; TS script blocks fall back to fundamental-mode and look unhighlighted.
;; Retarget to the tree-sitter modes the rest of the config already uses --
;; grammars live in `~/.emacs.d/tree-sitter' (see commit 8968757).
(use-package vue-mode
  :mode "\\.vue\\'"
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
;; wins -- so this hook list only matters in buffers without a running
;; language server.  Java was previously listed here as a fallback while
;; it ran on lsp-mode (separate xref machinery); after the Eglot
;; migration Eglot owns Java's xref end-to-end, so Java is no longer in
;; the hook below.  If you ever need ggtags on a Java buffer (e.g.
;; jdtls is down), run `M-x ggtags-mode' by hand.
;;
;; First-run note: as with all use-package blocks here, the archive isn't
;; refreshed at startup.  If ggtags isn't installed yet, `M-x my/package-refresh'
;; then restart Emacs once.  Also requires the `gtags' / `global' CLIs
;; (apt: `global'); run `gtags' at a repo root to generate the index.
;; Don't run `gtags' at a monorepo top-level dir that has no source
;; files of its own -- it writes empty 0-byte GTAGS / GRTAGS / GPATH
;; files that subsequently make `global' report "seems corrupted".
(use-package ggtags
  :commands ggtags-mode
  :hook ((c-mode      c-ts-mode
          c++-mode    c++-ts-mode
          python-mode python-ts-mode) . ggtags-mode))

;; Defensive: keep the etags fallback's globals empty so a stray
;; `visit-tags-table' can't seed them with a binary GTAGS file or a Java
;; source.  Both default to nil already; the explicit setq-default
;; documents the invariant and re-asserts it after any package that
;; auto-sets them on load.
(setq-default tags-file-name nil
              tags-table-list nil)

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
  ;;           `lua-mode' (regex-based, see use-package clause below) for
  ;;           highlighting; revisit if/when upstream tags ABI 14 or Emacs
  ;;           lifts the ABI cap.
  ;; All three modes are still hooked to eglot above where applicable; we
  ;; just lose the tree-sitter font-lock / structural navigation, which is
  ;; no real loss for these grammars.
  (setq treesit-auto-langs (seq-difference treesit-auto-langs '(css json lua)))
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;; lua-mode (MELPA): regex-based highlighting for .lua files.  Picked over
;; the built-in `lua-ts-mode' because upstream tree-sitter-lua is ABI 15
;; (see the treesit-auto exclusion comment above) -- so we lose tree-sitter
;; font-lock / structural navigation but keep everything else.
;;
;; LSP: Eglot attaches `lua-language-server' (LuaLS) via the `lua-mode' hook
;; in the eglot block above -- go-to-def, hover, workspace symbols, flymake
;; diagnostics.  The server isn't on apt; it's installed from upstream
;; GitHub releases as a self-contained bundle:
;;     ~/.local/share/lua-language-server/    (extracted tarball)
;;     ~/.local/bin/lua-language-server       (symlink to bin/ launcher)
;; `shell/install-user.sh' performs this install on a fresh clone.  If the
;; binary is missing, Eglot just declines to start -- highlighting still
;; works.  No formatter / REPL wired; add `stylua' to `apheleia-mode-alist'
;; if format-on-save is wanted.
(use-package lua-mode
  :mode "\\.lua\\'")

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
;; Hooks: every *-ts-mode this config opens Eglot on, except `rust-ts-mode'
;; (combobulate has no Rust support as of 2026-05).  `c-ts-mode' / `c++-ts-mode'
;; likewise unsupported.  Inside .vue files combobulate doesn't activate in
;; the embedded `js-ts-mode' / `typescript-ts-mode' chunks -- vue-mode's MMM
;; sub-buffer mechanism doesn't fire combobulate's mode hook there (a known
;; limitation, not a bug here).
;;
;; Source: GitHub only -- not on MELPA.  `:vc' is the Emacs 30 use-package
;; keyword that calls `package-vc-install' on first run (no straight.el /
;; quelpa needed).  Subsequent starts are no-ops.  To update later:
;;   M-x package-vc-upgrade RET combobulate RET
;; First load may take ~3s as Emacs byte-compiles the language adapters.
(use-package combobulate
  :vc (:url "https://github.com/mickeynp/combobulate" :rev :newest)
  :hook ((python-ts-mode     . combobulate-mode)
         (go-ts-mode         . combobulate-mode)
         (js-ts-mode         . combobulate-mode)
         (typescript-ts-mode . combobulate-mode)
         (tsx-ts-mode        . combobulate-mode))
  :custom
  ;; Default `C-c o' -- spelled out so the prefix is visible at the call
  ;; site (and easy to retarget if it ever clashes with a new mode binding).
  (combobulate-key-prefix "C-c o"))

;; flymake (built-in): on-the-fly diagnostics; Eglot feeds it from the LSP.
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :bind (:map flymake-mode-map
              ("M-n" . flymake-goto-next-error)
              ("M-p" . flymake-goto-prev-error)))

;; flymake-eslint: runs `node_modules/.bin/eslint' on save / change and feeds
;; the JSON diagnostics into Flymake -- so ESLint errors show up next to
;; tsserver's type errors in the same buffer (M-n / M-p above walks both).
;; Why not the LSP ESLint server: Eglot binds one server per major mode and
;; typescript-language-server already owns JS/TS/TSX.  Running ESLint as a
;; sibling Flymake backend sidesteps the multi-server problem entirely.
;;
;; `flymake-eslint-defer-binary-check' (t) skips probing for the `eslint'
;; binary at hook time -- otherwise opening a JS file outside any project
;; (scratch snippet, gist, dotfile) prints a "cannot find eslint" warning.
;; When the binary really is missing, the backend silently no-ops.
;; vue-mode is included so `eslint-plugin-vue' lints both the <template> and
;; <script> blocks of .vue files alongside the same ESLint config used for
;; the rest of the project.  flymake-eslint feeds the file as a whole; the
;; plugin handles the SFC split internally.
(use-package flymake-eslint
  :hook ((js-ts-mode typescript-ts-mode tsx-ts-mode vue-mode) . flymake-eslint-enable)
  :custom (flymake-eslint-defer-binary-check t))

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
(use-package apheleia
  :config
  ;; Prettier formats .vue SFCs natively (template + script + style in one
  ;; pass).  `apheleia-mode-alist' has no default entry for `vue-mode', so
  ;; without this nothing fires on save -- add it alongside the other
  ;; prettier-driven modes.
  (add-to-list 'apheleia-mode-alist '(vue-mode . prettier))
  (apheleia-global-mode +1))

;; markdown-mode (already installed): pulled in by some of the AI tools too.
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode))   ; GitHub-flavoured Markdown for READMEs
  :custom (markdown-command "pandoc"))

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
