;;; init.el --- Personal Emacs configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Organised, section-by-section config for Emacs 30.1.
;;
;; Layout:
;;   1.  Package system, use-package bootstrap, no-littering
;;   2.  Better built-in defaults (no external packages)
;;   3.  system-packages (OS package helper)
;;   4.  Minibuffer / completion UI      (Vertico ecosystem)
;;   5.  In-buffer code completion        (Corfu + Cape)
;;   6.  Snippets                         (YASnippet)
;;   7.  Editing enhancements             (which-key, avy, expand-region, ...)
;;   8.  Project, LSP & languages         (project.el, Eglot, tree-sitter)
;;   9.  Git                              (Magit, diff-hl)
;;   10. Terminal                         (vterm)
;;   11. Appearance                       (doom-themes, doom-modeline, nerd-icons)
;;   12. Org-mode                         (light touch)
;;   13. Obsidian note vault              (obsidian.el)
;;   14. org-roam                         (Zettelkasten over ~/code/org-roam)
;;   15. AI / agent tooling               (eca, acp, shell-maker) -- pre-existing
;;   16. Custom-set-variables block       (managed by M-x customize)
;;
;; Conventions:
;;   * `use-package-always-ensure' is t, so plain `(use-package foo ...)' will
;;     `package-install' foo from MELPA on first run.  Built-in packages must
;;     therefore say `:ensure nil' to avoid pulling a redundant MELPA copy.
;;   * The package archive is NOT refreshed at startup (network-free boot).
;;     Run `M-x my/package-refresh' before installing anything new, or the
;;     first launch after adding a package will fail to find it.

;;; Code:

;; ---------------------------------------------------------------------------
;; 1. Package system & use-package bootstrap
;; ---------------------------------------------------------------------------

(require 'package)
;; MELPA = the large community archive; GNU ELPA ("gnu") is already present by
;; default and stays enabled.
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; `early-init.el' set `package-enable-at-startup' to nil so Emacs would NOT
;; auto-`package-activate-all' before this file ran (that auto-pass duplicated
;; work and made load order opaque).  Activate the installed packages here,
;; explicitly -- exactly once, at a predictable point.
(package-initialize)

;; Deliberately skip `package-refresh-contents' on startup so launching Emacs
;; never blocks on the network.  Refresh on demand instead.
(defun my/package-refresh ()
  "Refresh package archive contents on demand."
  (interactive)
  (package-refresh-contents))

;; `use-package' has shipped with Emacs since 29; just require it.
(require 'use-package)
;; Every `(use-package foo ...)' implies `:ensure t' -- i.e. auto-install foo.
;; Use `:ensure nil' for packages that are part of Emacs itself.
(setq use-package-always-ensure t)

;; no-littering: many packages drop a state file straight into ~/.emacs.d/
;; (recentf, savehist, transient history, tramp, autosaves, ...).  This
;; redirects them into two tidy subdirs -- `var/' (volatile runtime state) and
;; `etc/' (config-ish data).  Load it as EARLY as possible so the packages
;; configured later in this file (savehist in section 4, ...) already see the
;; redirected paths.  The project .gitignore ignores `/var/' and `/etc/' in one
;; line each, replacing the per-file ignore rules; the pre-no-littering files
;; still sitting at the repo root (transient/, tramp, history, auto-save-list/)
;; are now orphaned litter -- safe to `rm' them whenever.
(use-package no-littering
  :demand t                              ; load now, don't defer
  :config
  ;; Keep #autosave# files under var/auto-save/ instead of next to the edited
  ;; file (canonical snippet from the no-littering README).
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))))

;; exec-path-from-shell: when Emacs is launched as a systemd/PAM daemon (or
;; from a GUI launcher), its PATH is the minimal login env -- no ~/go/bin,
;; ~/.local/bin, ~/.cargo/bin, etc.  Eglot then can't find gopls / pyright /
;; rust-analyzer, and `M-x compile' can't find the tools you installed for
;; yourself.  This runs the login shell, harvests PATH (+ a few other env
;; vars), and pushes them into Emacs' `exec-path' / `process-environment'.
;; Only needed when not started from a real terminal; the guard skips the
;; shell spawn (~50-200ms) in the TTY-launched case.
(use-package exec-path-from-shell
  :demand t
  :if (or (daemonp) (memq window-system '(x pgtk mac ns)))
  :config
  (exec-path-from-shell-initialize))

;; ---------------------------------------------------------------------------
;; 2. Better built-in defaults (no external packages)
;; ---------------------------------------------------------------------------

(use-package emacs
  :ensure nil
  :init
  ;; --- chrome ---
  ;; menu/tool/scroll bars are suppressed in early-init.el via
  ;; `default-frame-alist' so the first frame is painted without them.  Only
  ;; the startup-screen toggles belong here.
  (setq inhibit-startup-screen t)        ; straight to *scratch*
  (setq initial-scratch-message nil)
  ;; --- editing ---
  (setq-default indent-tabs-mode nil)    ; spaces, not tabs
  (delete-selection-mode 1)              ; typing replaces the active region
  (electric-pair-mode 1)                 ; auto-insert matching brackets/quotes
  (global-so-long-mode 1)                ; survive opening huge minified files
  ;; --- files / backups ---
  (setq make-backup-files nil)           ; no foo~ litter next to the file
  (setq auto-save-default t)             ; keep #foo# autosaves (recovery)
  (setq create-lockfiles nil)            ; no .#foo lockfiles
  (global-auto-revert-mode 1)            ; reload buffers when files change on disk
  (setq global-auto-revert-non-file-buffers t) ; ...including Dired
  ;; --- niceties ---
  (column-number-mode 1)                 ; show column in the modeline
  (setq use-short-answers t)             ; y/n instead of yes/no
  (setq ring-bell-function 'ignore)      ; no audible bell
  (setq sentence-end-double-space nil)
  ;; repeat-mode (built-in, Emacs 28+): after a prefixed command like `C-x o',
  ;; pressing the LAST key (`o', `o', `o') keeps invoking it without re-typing
  ;; the `C-x' prefix.  Also works for `C-x ^' (enlarge-window) etc.  Pure
  ;; ergonomics win, no setup beyond turning it on.
  (repeat-mode 1)
  ;; Put `M-x customize' output in its own file rather than appending to this
  ;; one.  (The block at the bottom of this file pre-dates this and is kept
  ;; for compatibility; new customisations go to custom.el.)
  (setq custom-file (expand-file-name "custom.el" user-emacs-directory))
  (when (file-exists-p custom-file) (load custom-file)))

;; Terminal clipboard bridge: in a TTY frame Emacs' default cut path is GUI-only,
;; so `M-w' fills the internal kill-ring but nothing outside Emacs sees it.
;; Emit OSC 52 on every cut; tmux's `set-clipboard on' in
;; [.tmux.conf](../.tmux.conf) relays the escape to the outer terminal, which
;; writes the real system clipboard.  Works across SSH; no xclip/wl-copy needed.
(unless (display-graphic-p)
  (defun fenrir/osc52-copy (text)
    (let ((b64 (base64-encode-string (encode-coding-string text 'utf-8) t)))
      (send-string-to-terminal (format "\e]52;c;%s\a" b64))))
  (setq interprogram-cut-function #'fenrir/osc52-copy))

;; which-key: after a prefix key (C-x, C-c, ...) pops up a panel listing the
;; follow-up keys.  Built into Emacs 30 -- hence :ensure nil.
(use-package which-key
  :ensure nil
  :init (which-key-mode 1)
  :custom (which-key-idle-delay 0.5))

;; ibuffer: replace the default `switch-to-buffer' on `C-x b' with ibuffer
;; (grouping, marking, batch operations).  `C-x C-b' is avoided because tmux'
;; default prefix is `C-b' and swallows the second keystroke in a TTY frame.
(use-package ibuffer
  :ensure nil
  :bind ("C-x b" . ibuffer))

;; ---------------------------------------------------------------------------
;; 3. system-packages -- thin wrapper over apt/brew/pacman/...
;; ---------------------------------------------------------------------------
;; The `:ensure-system-package' use-package keyword was removed from MELPA, so
;; call `system-packages-ensure' directly when you need an OS package present.

(use-package system-packages
  :defer t                               ; only used via M-x system-packages-...
  :custom (system-packages-use-sudo t))

;; ---------------------------------------------------------------------------
;; 4. Minibuffer / completion UI -- the "Vertico ecosystem"
;; ---------------------------------------------------------------------------
;; Five small, orthogonal packages that together replace ido/ivy/helm:
;;   vertico    -- vertical candidate list in the minibuffer
;;   orderless  -- space-separated, any-order fuzzy matching
;;   marginalia -- annotations (docstrings, file sizes, ...) beside candidates
;;   consult    -- richer commands: buffer switch, line search, project grep
;;   embark     -- a "context menu" you can invoke on the current candidate

(use-package vertico
  :init (vertico-mode 1)
  :custom
  (vertico-cycle t))                     ; wrap around at top/bottom

;; vertico-directory: an extension that ships INSIDE the vertico package -- so
;; `:ensure nil'.  Makes RET/DEL operate on whole path components when you're
;; editing a file name in the minibuffer (RET descends into the dir under
;; point; DEL deletes back to the previous `/').
(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
              ("RET"   . vertico-directory-enter)
              ("DEL"   . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  ;; Collapse the "//" / "~/" shadow when you type an absolute path mid-prompt.
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; Persist minibuffer history; also lets Vertico put recent picks first.
;; `savehist-additional-variables' bolts on the kill-ring and the two search
;; rings -- so M-y / C-s history survive a restart, not just M-x history.
(use-package savehist
  :ensure nil
  :init (savehist-mode 1)
  :custom
  (savehist-additional-variables '(kill-ring search-ring regexp-search-ring)))

;; recentf (built-in): tracks recently-opened files.  Once enabled,
;; `consult-buffer' (C-x b) gains a "Recent files" virtual source -- so the
;; same key that switches buffers also re-opens recent files, no separate
;; "recentf-open" command needed.  no-littering already redirected the
;; recentf save file out of `~/.emacs.d/' root, so no path tweak required.
(use-package recentf
  :ensure nil
  :init (recentf-mode 1)
  :custom
  (recentf-max-saved-items 200)
  (recentf-max-menu-items 25))

(use-package orderless
  :custom
  ;; Use orderless for ordinary completion; keep the built-in file-name style
  ;; so partial path components (e.g. "/u/s/b" -> /usr/share/bin) still work.
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package consult
  :bind (;; C-x bindings -- `C-x b' is reserved for ibuffer (see section 2),
         ;; so the consult fuzzy switcher lives on `C-x B' (shift) instead.
         ("C-x B"   . consult-buffer)         ; switch buffer (with previews)
         ("C-x 4 b" . consult-buffer-other-window)
         ("C-x p b" . consult-project-buffer) ; project-scoped buffer switch
         ;; search
         ("M-y"     . consult-yank-pop)       ; browse the kill-ring
         ("C-s"     . consult-line)           ; search lines in this buffer
         ("M-g g"   . consult-goto-line)
         ("M-g i"   . consult-imenu)          ; jump to a definition in this file
         ("M-s r"   . consult-ripgrep)        ; grep across the project
         ("M-s f"   . consult-find))          ; find files by name
  :custom
  ;; Let `consult-line' etc. drive the live preview at this key:
  (consult-narrow-key "<"))

(use-package embark
  :bind (("C-." . embark-act)            ; act on the thing at point / candidate
         ("C-;" . embark-dwim)           ; "do what I mean" -- default action
         ("C-h B" . embark-bindings)))   ; like `describe-bindings' via completing-read

;; Glue: when you `embark-act' inside a consult command, show the export buffer
;; using consult's nicer formatting.
(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; wgrep: make grep / ripgrep result buffers editable, then commit the edits
;; back to every file at once.  The payoff with the setup above: run
;; `consult-ripgrep' (M-s r), `embark-export' (C-. then E) the matches into a
;; grep buffer, `C-c C-p' to make it writable, edit freely, `C-c C-c' to save
;; -- a project-wide search-and-replace with ordinary undo on each file.
(use-package wgrep
  :defer t                               ; loads when you C-c C-p in a grep buffer
  :custom (wgrep-auto-save-buffer t))    ; write edited files out immediately

;; ---------------------------------------------------------------------------
;; 5. In-buffer code completion -- Corfu + Cape
;; ---------------------------------------------------------------------------
;; Corfu is the lightweight `company' alternative: a small popup at point.
;; Cape provides extra completion-at-point backends to feed it.

(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)                         ; pop up automatically as you type
  (corfu-auto-delay 0.2)
  (corfu-auto-prefix 2)                  ; ...after 2 chars
  (corfu-cycle t)
  (corfu-quit-no-match 'separator)
  :config
  ;; M-m while the corfu popup is visible: move the SAME candidate set into
  ;; vertico's minibuffer interface (via `consult-completion-in-region').  Gets
  ;; you a `C-x C-f'-style bottom prompt with orderless filtering when the
  ;; popup's narrow at-point view isn't enough.  Recipe is from corfu's README.
  ;; The auto-popup stays the typing-flow primary; M-m is the escape hatch.
  (defun fenrir/corfu-move-to-minibuffer ()
    "Move the current Corfu completion into the minibuffer via Consult."
    (interactive)
    (pcase completion-in-region--data
      (`(,beg ,end ,table ,pred ,extras)
       (let ((completion-extra-properties extras)
             completion-cycle-threshold completion-cycling)
         (consult-completion-in-region beg end table pred)))))
  (keymap-set corfu-map "M-m" #'fenrir/corfu-move-to-minibuffer))

;; corfu-popupinfo: another in-package extension (hence `:ensure nil') -- shows
;; the selected candidate's docstring / signature in a second popup beside the
;; completion list.  The delay is (visible-delay . next-candidate-delay): wait
;; 0.5s before the first doc popup, then 0.2s when stepping between candidates.
(use-package corfu-popupinfo
  :ensure nil
  :after corfu
  :init (corfu-popupinfo-mode 1)
  :custom (corfu-popupinfo-delay '(0.5 . 0.2)))

;; corfu-terminal: Corfu's default popup is a child frame, which only renders
;; in GUI frames.  In a TTY frame (`emacsclient -t' inside tmux -- the common
;; case for this daemon) the popup silently never paints: `global-corfu-mode'
;; IS active, candidates ARE being computed, you just can't see them.  This
;; package swaps the renderer to `popon' (overlay-based text popup) on TTY
;; frames and leaves GUI frames using the native child frame -- so the same
;; daemon serves both transports correctly.
(use-package corfu-terminal
  :after corfu
  :config (corfu-terminal-mode +1))


(use-package cape
  :init
  ;; Generic backends useful in every buffer: dabbrev (words in open buffers),
  ;; file paths, and elisp symbols.  Eglot adds language-aware ones on top.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block))

;; ---------------------------------------------------------------------------
;; 6. Snippets -- YASnippet
;; ---------------------------------------------------------------------------

(use-package yasnippet
  :init (yas-global-mode 1))

;; A large collection of ready-made snippets for many major modes.
(use-package yasnippet-snippets
  :after yasnippet)

;; ---------------------------------------------------------------------------
;; 7. Editing enhancements
;; ---------------------------------------------------------------------------

;; avy: jump to any visible position with a 2-3 keystroke "decision tree"
;; (the Emacs analogue of tmux-jump / ace-jump).
(use-package avy
  :bind (("C-:"   . avy-goto-char-timer)  ; type a few chars, then pick
         ("M-g w" . avy-goto-word-1)
         ("M-g l" . avy-goto-line)))

;; expand-region: C-= grows the region semantically (word -> sexp -> string ->
;; defun -> ...); shift-C-= shrinks it again.
(use-package expand-region
  :bind ("C-=" . er/expand-region))

;; multiple-cursors: edit many places at once.
(use-package multiple-cursors
  :bind (("C->"         . mc/mark-next-like-this)
         ("C-<"         . mc/mark-previous-like-this)
         ("C-c C-<"     . mc/mark-all-like-this)
         ("C-S-<mouse-1>" . mc/add-cursor-on-click)))

;; rainbow-delimiters: colour-code nested parens by depth -- invaluable in Lisp.
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; helpful: much richer *Help* buffers (source, callers, edebug, ...).
(use-package helpful
  :bind (("C-h f" . helpful-callable)     ; functions + macros
         ("C-h v" . helpful-variable)
         ("C-h k" . helpful-key)
         ("C-h x" . helpful-command)
         ("C-h o" . helpful-symbol)))

;; vundo: draw the undo history as a tree in a transient side buffer and walk
;; it with the arrow keys.  Unlike `undo-tree' it stores nothing on disk and
;; doesn't replace Emacs' native undo machinery -- it just visualises it, so
;; there's no risk of a corrupted on-disk history on huge files.
(use-package vundo
  :bind ("C-x u" . vundo))               ; was `undo' (still on C-/ and C-_)

;; hl-todo: colour-code TODO / FIXME / HACK / NOTE / BUG keywords in comments.
;; (magit-todos in section 9 reuses this keyword set for its repo-wide list.)
(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))

;; pulsar: briefly pulse the current line after a big motion -- an avy jump, a
;; window switch, `consult-line', `recenter-top-bottom', ... -- so your eye
;; re-acquires the cursor.  Pairs naturally with the avy/consult bindings above.
(use-package pulsar
  :init (pulsar-global-mode 1)
  :config
  (dolist (fn '(avy-goto-char-timer avy-goto-line avy-goto-word-1))
    (add-to-list 'pulsar-pulse-functions fn))
  ;; consult exposes this hook on every jump (consult-line/imenu/ripgrep ...).
  (add-hook 'consult-after-jump-hook #'pulsar-recenter-center)
  (add-hook 'consult-after-jump-hook #'pulsar-reveal-entry))

;; ---------------------------------------------------------------------------
;; 8. Project, LSP & languages
;; ---------------------------------------------------------------------------

;; project.el (built-in): project-aware file/buffer/command commands under C-x p.
(use-package project
  :ensure nil)

;; Eglot (built-in since Emacs 29): a small, zero-config LSP client.  It
;; auto-starts when you open a file in a supported mode AND a language server
;; binary is on PATH (gopls, pyright, rust-analyzer, typescript-language-server,
;; clangd, ...).  Reach for `lsp-mode' only if you need its heavier extras.
(use-package eglot
  :ensure nil
  :hook ((python-ts-mode . eglot-ensure)
         (go-ts-mode      . eglot-ensure)
         (rust-ts-mode    . eglot-ensure)
         (js-ts-mode      . eglot-ensure)
         (typescript-ts-mode . eglot-ensure)
         (c-ts-mode       . eglot-ensure)
         (c++-ts-mode     . eglot-ensure))
  :custom
  (eglot-autoshutdown t)                 ; kill the server when its last buffer closes
  (eglot-events-buffer-size 0)           ; don't log the (huge) JSON-RPC traffic
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
  (eglot-extend-to-xref t))

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
;; language server (e.g. Java, which isn't in the eglot hook above).
;;
;; First-run note: as with all use-package blocks here, the archive isn't
;; refreshed at startup.  If ggtags isn't installed yet, `M-x my/package-refresh'
;; then restart Emacs once.  Also requires the `gtags' / `global' CLIs
;; (apt: `global'); run `gtags' at a repo root to generate the index.
(use-package ggtags
  :commands ggtags-mode
  :hook ((c-mode      c-ts-mode
          c++-mode    c++-ts-mode
          java-mode   java-ts-mode
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
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;; flymake (built-in): on-the-fly diagnostics; Eglot feeds it from the LSP.
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :bind (:map flymake-mode-map
              ("M-n" . flymake-goto-next-error)
              ("M-p" . flymake-goto-prev-error)))

;; markdown-mode (already installed): pulled in by some of the AI tools too.
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode))   ; GitHub-flavoured Markdown for READMEs
  :custom (markdown-command "pandoc"))

;; ---------------------------------------------------------------------------
;; 9. Git -- Magit + diff-hl
;; ---------------------------------------------------------------------------

;; Magit: the reason a lot of people use Emacs at all.
(use-package magit
  :bind (("C-x g" . magit-status)
         ("C-x M-g" . magit-dispatch))
  :custom
  ;; Refine only the hunk at point, not 'all -- 'all turns large diffs into a
  ;; font-lock circus.
  (magit-diff-refine-hunk t)
  ;; Flip to t when investigating slow refreshes -- each section logs its
  ;; elapsed time to *Messages*. M-x magit-toggle-verbose-refresh does the same.
  ;; (magit-refresh-verbose t)
  :config
  ;; Built-in vc.el shells out to git for every file we open. With Magit doing
  ;; the heavy lifting, vc-mode is pure overhead.
  (setq vc-handled-backends nil)
  ;; $HOME is tracked with `status.showUntrackedFiles=no' (~1M hidden entries);
  ;; Magit doesn't honour that config and would still walk them. Drop the
  ;; section -- in normal repos `git status -s` is one keystroke away anyway.
  (remove-hook 'magit-status-sections-hook 'magit-insert-untracked-files))

;; diff-hl: show added/changed/removed lines in the fringe, live.
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode)
         ;; refresh the gutter right after a Magit commit/stage/...
         (magit-post-refresh . diff-hl-magit-post-refresh)))

;; magit-todos: add a "TODOs" section to the Magit status buffer listing the
;; hl-todo keywords found across the repo, jumpable like any other section.  It
;; auto-picks a scanner -- `rg' if present (it is here), else `git grep'.
(use-package magit-todos
  :after magit
  :custom
  ;; Don't re-scan TODOs on every status refresh -- in a $HOME-sized repo that
  ;; single section dominates the refresh budget. Press `j T' inside the status
  ;; buffer to update on demand.
  (magit-todos-update nil)
  ;; `:config' (runs after magit-todos is loaded, which `:after magit' gates)
  ;; -- using `:init' here would force magit-todos (and therefore magit) to
  ;; load eagerly at startup, defeating the whole point of `:after magit'.
  :config (magit-todos-mode 1))

;; ---------------------------------------------------------------------------
;; 10. Terminal -- vterm
;; ---------------------------------------------------------------------------
;; A real terminal emulator (libvterm-backed), far more capable than term/eshell.
;; NOTE: it compiles a C module on first install -- needs `cmake' and
;; `libvterm' headers (`apt install cmake libvterm-dev').  If you'd rather not,
;; comment this block out and use the built-in `M-x eshell'.

(use-package vterm
  :bind ("C-c t" . vterm)
  :custom
  (vterm-max-scrollback 10000)
  ;; Compile the C module when vterm.el loads, not on first `M-x vterm'.
  ;; Surfaces a missing cmake/libvterm-dev as a loud startup error.
  (vterm-always-compile-module t))

;; ---------------------------------------------------------------------------
;; 11. Appearance -- doom-themes + doom-modeline + nerd-icons
;; ---------------------------------------------------------------------------

(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-one t)               ; swap for any `doom-*' you like
  (doom-themes-org-config))              ; tweak org-mode faces to match

;; nerd-icons: glyph set used by doom-modeline and (optionally) Dired/Corfu.
;; Run `M-x nerd-icons-install-fonts' ONCE after install to fetch the font.
;; `:defer t' is safe -- doom-modeline `require's it explicitly when it loads.
(use-package nerd-icons :defer t)

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :custom (doom-modeline-height 25))

;; ---------------------------------------------------------------------------
;; 12. Org-mode -- minimal; expand later (org-roam, org-agenda, ...) as needed
;; ---------------------------------------------------------------------------

(use-package org
  :ensure nil
  :custom
  (org-startup-indented t)               ; visually indent by outline level
  (org-hide-emphasis-markers t)          ; show *bold* as bold, hide the stars
  (org-src-fontify-natively t))          ; syntax-highlight inside #+begin_src

;; org-modern: restyle headings, lists, checkboxes, tables, blocks and
;; timestamps for a cleaner look.  Pure display -- it never edits your files.
(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda)))

;; org-appear: temporarily reveal the *bold* / =verbatim= / [[link]] markup of
;; whichever element point is on -- the complement to `org-hide-emphasis-markers'
;; above, so you can still edit the markers without globally un-hiding them.
(use-package org-appear
  :hook (org-mode . org-appear-mode))

;; ---------------------------------------------------------------------------
;; 13. Obsidian note vault -- obsidian.el
;; ---------------------------------------------------------------------------
;; The vault at ~/code/obsidian/ is plain Markdown, so `markdown-mode' (section
;; 8) already opens its notes.  obsidian.el adds the Obsidian-specific layer on
;; top: `[[wikilink]]' following, `#tag' awareness, YAML front-matter, daily
;; notes and a quick "jump to any note" command.  It's a global minor mode that
;; activates only inside files under `obsidian-directory', so it never touches
;; Markdown buffers elsewhere.
;;
;; First-run note: `use-package-always-ensure' is t but the archive is NOT
;; refreshed at startup (see section 1).  If obsidian isn't installed yet, run
;; `M-x my/package-refresh' then restart Emacs once.

(use-package obsidian
  :custom
  (obsidian-directory "~/code/obsidian")
  ;; New notes from `obsidian-capture' land here (relative to the vault);
  ;; leave at the vault root by default -- adjust if you keep an "Inbox/" dir.
  (obsidian-inbox-directory nil)
  :config
  (global-obsidian-mode 1)
  :bind
  (;; vault-wide commands (available everywhere, "n" = notes)
   ("C-c n n" . obsidian-jump)            ; open / switch to any note
   ("C-c n c" . obsidian-capture)         ; create a new note
   ("C-c n s" . obsidian-search)          ; full-text search the vault
   ;; in-vault editing (obsidian-mode is a minor mode -> these win over
   ;; markdown-mode's own C-c C-o / C-c C-l while inside the vault)
   :map obsidian-mode-map
   ("C-c C-o" . obsidian-follow-link-at-point)
   ("C-c C-l" . obsidian-insert-wikilink)))
;; More via `M-x obsidian-' : obsidian-daily-note, obsidian-backlink-jump,
;; obsidian-move-file, obsidian-rename, obsidian-update, ...

;; ---------------------------------------------------------------------------
;; 14. org-roam -- Zettelkasten over ~/code/org-roam
;; ---------------------------------------------------------------------------
;; ~/code/org-roam/ holds the .org notes converted from the Obsidian vault by
;; ~/code/obsidian-to-org-roam.py (re-runnable; see CONVERSION-REPORT.txt in
;; that directory).  org-roam adds an SQLite-backed link cache on top of plain
;; .org files: every note (a file with a top-level `:ID:' property) is a "node",
;; `[[id:...]]' links between them are bidirectional, and `org-roam-buffer'
;; shows the backlinks of whatever you're viewing.
;;
;; This is parallel to the Obsidian section above, not a replacement -- obsidian.el
;; still drives the original .md vault at ~/code/obsidian/.  Drop section 13 if
;; and when you fully move over.
;;
;; First run (the archive isn't refreshed at startup -- see section 1):
;;   M-x my/package-refresh  ->  restart Emacs  ->  M-x org-roam-db-sync
;; org-roam pulls in `emacsql'; Emacs 30's built-in SQLite covers it.
;;
;; `org-roam-graph' (M-x) renders a static link graph via Graphviz -- it needs
;; the `dot' binary (`apt install graphviz'); use `C-u M-x org-roam-graph' to
;; draw a local subgraph rather than all ~1400 nodes at once.  `org-roam-ui'
;; below is the nicer option for a vault this size: an interactive in-browser
;; D3 graph, no Graphviz required.

(use-package org-roam
  :custom
  (org-roam-directory (file-truename "~/code/org-roam"))
  ;; New note from `C-c r f' / `C-c r c': timestamp-${slug}.org with a #+title:
  ;; and a tag prompt.  `%(my/org-roam-prompt-filetags)' (defined in :config)
  ;; runs `completing-read-multiple' against the tags already in the roam DB --
  ;; so you pick from your existing vocabulary instead of inventing typo-variants;
  ;; entering nothing yields no #+filetags: line at all.  `%?' is where point
  ;; lands after capture; `:unnarrowed t' shows the whole file while capturing.
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
      :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                         "#+title: ${title}\n%(my/org-roam-prompt-filetags)")
      :unnarrowed t)))
  ;; The converted daily notes (2026-05-08.org, ...) sit at the vault root, not
  ;; in a `daily/' subdir, so point org-roam-dailies there with an empty subdir.
  (org-roam-dailies-directory "")
  ;; Fixed header for daily notes.  `file+head' inserts HEAD only when the day's
  ;; file doesn't exist yet; org-roam itself prepends the :ID: drawer above it,
  ;; so a brand-new daily ends up as:
  ;;   :PROPERTIES:  /  :ID: <auto>  /  :END:
  ;;   #+title: 2026-05-13 Tuesday
  ;;   #+filetags: :daily:
  ;;   * 14:32 <point>
  ;; The `entry' body "* %<%H:%M> %?" means every C-c r d capture adds a fresh
  ;; timestamped top-level heading (a running journal); `:unnarrowed t' keeps the
  ;; whole file visible while capturing.  `%A' is the locale's full weekday name.
  ;; For a fixed content skeleton instead, put the headings in HEAD and switch
  ;; the target to `(file+head+olp "%<%Y-%m-%d>.org" HEAD ("Log"))'.
  (org-roam-dailies-capture-templates
   '(("d" "default" entry
      "* %<%H:%M> %?"
      :target (file+head "%<%Y-%m-%d>.org"
                         "#+title: %<%Y-%m-%d %A>\n#+filetags: :daily:\n")
      :unnarrowed t)))
  (org-roam-completion-everywhere t)       ; complete [[ links from any buffer text
  :bind (("C-c r f" . org-roam-node-find)        ; open / create a note ("r" = roam)
         ("C-c r i" . org-roam-node-insert)      ; insert an [[id:...]] link to a note
         ("C-c r b" . org-roam-buffer-toggle)    ; backlinks side window
         ("C-c r c" . org-roam-capture)          ; capture a new note via a template
         ("C-c r d" . org-roam-dailies-goto-today))
  :config
  ;; Tag prompt used by `org-roam-capture-templates' above.  Completes against
  ;; every tag currently in the roam DB; returns a "#+filetags: :a:b:" line, or
  ;; "" when no tags are entered (so empty input leaves no stray header line).
  (defun my/org-roam-prompt-filetags ()
    "Prompt for org-roam file tags and return a `#+filetags:' line (or \"\")."
    (let ((tags (seq-remove #'string-empty-p
                            (completing-read-multiple
                             "Tags (comma-separated, empty = none): "
                             (org-roam-tag-completions)))))
      (if tags (format "#+filetags: :%s:\n" (string-join tags ":")) "")))
  ;; Keep the cache DB in sync as you edit/visit files.  The DB itself must be
  ;; built once first with `M-x org-roam-db-sync' (see the first-run note above).
  (org-roam-db-autosync-mode 1))

;; org-roam-ui: an interactive graph of the roam DB rendered in the browser
;; (D3 force-directed; click a node to jump to it, follows point in Emacs,
;; matches the Emacs theme).  Pulls in `websocket' + `simple-httpd' and runs a
;; local HTTP server while `org-roam-ui-mode' is on.  No Graphviz needed -- this
;; is the practical alternative to `org-roam-graph' for a large vault.
(use-package org-roam-ui
  :after org-roam
  :custom
  (org-roam-ui-sync-theme t)
  (org-roam-ui-follow t)                   ; the graph tracks the note you're in
  (org-roam-ui-update-on-save t)
  (org-roam-ui-open-on-start nil)          ; don't auto-launch a browser tab
  :bind ("C-c r g" . org-roam-ui-mode))    ; "g" = graph; toggles the server + tab

;; ---------------------------------------------------------------------------
;; 15. AI / agent tooling -- pre-existing setup, kept as-is
;; ---------------------------------------------------------------------------
;;   eca          -- Editor Code Assistant client
;;   acp          -- Agent Client Protocol library
;;   shell-maker  -- shared shell framework these build on
;; These were installed via `M-x customize' (see `package-selected-packages'
;; in the block below).  Add explicit `(use-package eca ...)' configuration
;; here if/when you want to bind keys or tweak behaviour.

;; Local-lisp dir for hand-written packages (claude-jobs-view, future siblings).
;; Added to `load-path' here, ONCE, so any `use-package <local> :ensure nil'
;; below resolves without touching MELPA.
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; claude-jobs-view -- tabulated UI for the `jobctl' CLI (persistent Claude
;; Code background sessions).  Source: lisp/claude-jobs-view.el.  Entry point:
;; M-x claude-jobs-view.  `:commands' makes the autoload lazy -- the file is
;; only loaded the first time the command is invoked.
(use-package claude-jobs-view
  :ensure nil
  :commands (claude-jobs-view))

;; ---------------------------------------------------------------------------
;; 16. End of file
;; ---------------------------------------------------------------------------
;; `M-x customize' writes to `custom.el' (path set in section 2); that file is
;; the single source of truth for `custom-set-variables' / `custom-set-faces'.
;; There is intentionally NO custom-set-variables block here -- having one in
;; both files leads to whichever-loads-last wins, which is exactly the kind of
;; subtle bug `custom-file' was invented to prevent.

;;; init.el ends here
