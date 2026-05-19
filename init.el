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

;; Local-lisp dir for hand-written packages (claude-jobs-view, future siblings)
;; and for the per-section `init-<area>.el' modules.  Added to `load-path' here,
;; ONCE, so every later `(require 'init-<area>)' / `use-package <local> :ensure
;; nil' resolves without touching MELPA.
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Per-section modules under `lisp/' carry the rest of this config.  Loaded
;; in the original section order; cross-section `use-package :after' wiring
;; relies on this order, so do not reshuffle without verifying.
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
        init-org
        init-obsidian
        init-org-roam))


;; ---------------------------------------------------------------------------
;; 15. AI / agent tooling -- pre-existing setup, kept as-is
;; ---------------------------------------------------------------------------
;;   eca          -- Editor Code Assistant client
;;   acp          -- Agent Client Protocol library
;;   shell-maker  -- shared shell framework these build on
;; These were installed via `M-x customize' (see `package-selected-packages'
;; in the block below).  Add explicit `(use-package eca ...)' configuration
;; here if/when you want to bind keys or tweak behaviour.

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
