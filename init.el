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
;;   13. AI / agent tooling               (eca, acp, shell-maker) -- pre-existing
;;   14. Custom-set-variables block       (managed by M-x customize)
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

;; ---------------------------------------------------------------------------
;; 2. Better built-in defaults (no external packages)
;; ---------------------------------------------------------------------------

(use-package emacs
  :ensure nil
  :init
  ;; --- chrome ---
  (menu-bar-mode -1)                     ; no menu bar
  (tool-bar-mode -1)                     ; no tool bar
  (scroll-bar-mode -1)                   ; no scroll bar
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
  ;; Put `M-x customize' output in its own file rather than appending to this
  ;; one.  (The block at the bottom of this file pre-dates this and is kept
  ;; for compatibility; new customisations go to custom.el.)
  (setq custom-file (expand-file-name "custom.el" user-emacs-directory))
  (when (file-exists-p custom-file) (load custom-file)))

;; which-key: after a prefix key (C-x, C-c, ...) pops up a panel listing the
;; follow-up keys.  Built into Emacs 30 -- hence :ensure nil.
(use-package which-key
  :ensure nil
  :init (which-key-mode 1)
  :custom (which-key-idle-delay 0.5))

;; ---------------------------------------------------------------------------
;; 3. system-packages -- thin wrapper over apt/brew/pacman/...
;; ---------------------------------------------------------------------------
;; The `:ensure-system-package' use-package keyword was removed from MELPA, so
;; call `system-packages-ensure' directly when you need an OS package present.

(use-package system-packages
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
(use-package savehist
  :ensure nil
  :init (savehist-mode 1))

(use-package orderless
  :custom
  ;; Use orderless for ordinary completion; keep the built-in file-name style
  ;; so partial path components (e.g. "/u/s/b" -> /usr/share/bin) still work.
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package consult
  :bind (;; C-x bindings
         ("C-x b"   . consult-buffer)         ; switch buffer (with previews)
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
  (corfu-quit-no-match 'separator))

;; corfu-popupinfo: another in-package extension (hence `:ensure nil') -- shows
;; the selected candidate's docstring / signature in a second popup beside the
;; completion list.  The delay is (visible-delay . next-candidate-delay): wait
;; 0.5s before the first doc popup, then 0.2s when stepping between candidates.
(use-package corfu-popupinfo
  :ensure nil
  :after corfu
  :init (corfu-popupinfo-mode 1)
  :custom (corfu-popupinfo-delay '(0.5 . 0.2)))

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
  (eglot-events-buffer-size 0))          ; don't log the (huge) JSON-RPC traffic

;; tree-sitter (built-in in 30): faster, more accurate syntax via *-ts-mode.
;; `treesit-auto' installs grammars on demand and remaps classic modes to their
;; tree-sitter equivalents (python-mode -> python-ts-mode, etc.).
(use-package treesit-auto
  :custom (treesit-auto-install 'prompt)  ; ask before downloading a grammar
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
         ("C-x M-g" . magit-dispatch)))

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
  :init (magit-todos-mode 1))

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
(use-package nerd-icons)

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
;; 13. AI / agent tooling -- pre-existing setup, kept as-is
;; ---------------------------------------------------------------------------
;;   eca          -- Editor Code Assistant client
;;   acp          -- Agent Client Protocol library
;;   shell-maker  -- shared shell framework these build on
;; These were installed via `M-x customize' (see `package-selected-packages'
;; in the block below).  Add explicit `(use-package eca ...)' configuration
;; here if/when you want to bind keys or tweak behaviour.

;; ---------------------------------------------------------------------------
;; 14. Custom-set-variables -- managed by `M-x customize'; leave at end of file
;; ---------------------------------------------------------------------------
;; (New customisations are redirected to custom.el via `custom-file' set in
;; section 2; this legacy block stays so an older Emacs still finds it valid.)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages '(acp eca shell-maker system-packages)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;;; init.el ends here
