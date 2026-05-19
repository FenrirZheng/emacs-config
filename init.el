;;; init.el --- Personal Emacs configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Thin loader for the per-section modules under `lisp/'.  Each `init-<area>.el'
;; module corresponds to one section of the pre-2026-05-19 monolithic init.el
;; (see git log for the split commits).
;;
;; Modules, in load order:
;;   init-defaults         -- Better built-in defaults, custom-file, which-key, ibuffer
;;   init-system-packages  -- OS package helper (apt/brew/...)
;;   init-completion      -- Minibuffer / completion UI (Vertico ecosystem)
;;   init-corfu           -- In-buffer code completion (Corfu + Cape)
;;   init-snippets        -- YASnippet
;;   init-editing        -- Editing enhancements (avy, pulsar, popper, jinx, ...)
;;   init-languages      -- Project, LSP (Eglot), tree-sitter, per-language
;;   init-git            -- Magit + diff-hl + magit-todos + delta + difftastic
;;   init-terminal       -- vterm
;;   init-appearance     -- doom-themes, doom-modeline, nerd-icons
;;   init-dirvish        -- Dirvish: polished Dired with icons + preview
;;   init-org            -- Org-mode (light touch)
;;   init-obsidian       -- Obsidian note vault (~/code/obsidian/)
;;   init-org-roam       -- org-roam Zettelkasten (~/code/org-roam/)
;;   init-ai             -- AI / agent tooling (eca, acp, shell-maker, claude-jobs-view)
;;
;; Conventions:
;;   * `use-package-always-ensure' is t, so plain `(use-package foo ...)' will
;;     `package-install' foo from MELPA on first run.  Built-in packages must
;;     therefore say `:ensure nil' to avoid pulling a redundant MELPA copy.
;;   * The package archive is NOT refreshed at startup (network-free boot).
;;     Run `M-x my/package-refresh' before installing anything new, or the
;;     first launch after adding a package will fail to find it.
;;   * `M-x customize' writes to custom.el; `custom-file' is set in
;;     init-defaults.el, which also calls `(load custom-file)'.  There is
;;     intentionally NO `custom-set-variables' block here -- a duplicate in
;;     both files would let "whichever loads last" silently win.

;;; Code:

;; ---------------------------------------------------------------------------
;; Package system & use-package bootstrap (kept inline -- `use-package' must be
;; loaded before any module file can call it).
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
;; configured later (savehist in init-completion, ...) already see the
;; redirected paths.  The project .gitignore ignores `/var/' and `/etc/' in one
;; line each, replacing the per-file ignore rules; the pre-no-littering files
;; still sitting at the repo root (transient/, tramp, history, auto-save-list/)
;; are now orphaned litter -- safe to `rm' them whenever.
(use-package no-littering
  :demand t)                             ; load now, don't defer
;; (Previously had an `auto-save-file-name-transforms' :config form to route
;; classic `#foo#' autosaves under `var/auto-save/'.  Dropped along with
;; `auto-save-default' in `init-defaults.el' -- `auto-save-visited-mode'
;; writes to the visited file directly, so nothing emits sidecar files
;; that would need redirecting.)

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

;; Local-lisp dir for hand-written packages (claude-jobs-view, future siblings)
;; and for the per-section `init-<area>.el' modules.  Added to `load-path' here,
;; ONCE, so every later `(require 'init-<area>)' / `use-package <local> :ensure
;; nil' resolves without touching MELPA.
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; ---------------------------------------------------------------------------
;; Per-section modules.  Loaded in the original section order; cross-section
;; `use-package :after' wiring relies on this order, so do not reshuffle
;; without verifying.
;; ---------------------------------------------------------------------------

(mapc #'require
      '(init-defaults
        init-system-packages
        init-completion
        init-corfu
        init-snippets
        init-editing
        init-languages
        init-git
        init-terminal
        init-appearance
        init-dirvish
        init-org
        init-obsidian
        init-org-roam
        init-ai))

;;; init.el ends here
