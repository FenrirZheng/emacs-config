;;; init-dirvish.el --- Dirvish: polished Dired with icons + preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish (https://github.com/alexluigit/dirvish) layers icons, preview,
;; history, a side panel, and a `?'-driven transient cheat-sheet on top of
;; Dired.  `dirvish-override-dired-mode' makes every `C-x d' / `C-x C-f'
;; into-a-directory route through Dirvish without a separate keybind.
;;
;; Attribute choices vs. upstream's sample config:
;;   * No VC attribute is enabled.  `git-msg' (inline last-commit subject)
;;     was tried -- scoped to non-$HOME repos via a `:vc-backend' advice --
;;     but dropped: the per-directory vc fetch behind it (`vc-state-refresh'
;;     plus a `git log -1' per file) made opening a dirvish buffer lag, and
;;     the inline commit subject was not worth that cost in daily use.
;;   * `vc-state' was never enabled either -- it renders in the left fringe
;;     (dirvish-vc.el: "only works on graphic displays"), invisible on the
;;     TTY frames (`emacsclient -nw') this setup runs in.
;; With no vc attribute in `dirvish-attributes', dirvish skips `(require
;; 'dirvish-vc)' entirely, so no per-file git work runs on buffer creation.

;;; Code:

(use-package dired
  :ensure nil
  :config
  (setq dired-listing-switches
        "-l --almost-all --human-readable --group-directories-first --no-group")
  ;; Let `a' (dired-find-alternate-file) reuse the current Dired buffer
  ;; instead of leaving a trail of stale Dired buffers behind every descent.
  ;; Also lets `dirvish-side' auto-close its window when opening a file.
  (put 'dired-find-alternate-file 'disabled nil))

(use-package dirvish
  :ensure t
  :init
  (dirvish-override-dired-mode)
  :custom
  (dirvish-quick-access-entries
   ;; Curated personal launcher -- order = quick-key order in `o'.
   '(("h" "~/"                            "Home")
     ("e" "~/.emacs.d/"                   "Emacs config")
     ("c" "~/.claude/"                    "Claude config")
     ("o" "~/code/obsidian/"              "Obsidian vault")
     ("r" "~/code/org-roam/"              "org-roam vault")
     ("t" "~/fenrir-tools/"               "fenrir-tools")))
  :config
  (setq dirvish-mode-line-format
        '(:left (sort symlink) :right (omit yank index)))
  ;; Attribute order MATTERS (upstream warning).  See header comment for
  ;; why no VC attribute (`git-msg' / `vc-state') is enabled.
  (setq dirvish-attributes
        '(subtree-state nerd-icons collapse file-time file-size))
  (setq dirvish-side-attributes
        '(nerd-icons collapse file-size))
  ;; Hand off >20k-entry dirs to `fd' so the UI doesn't block.  `fdfind' is
  ;; the Debian binary name; upstream calls it `fd'.
  (setq dirvish-large-directory-threshold 20000)
  (setq dirvish-fd-program (or (executable-find "fdfind")
                               (executable-find "fd")))
  ;; Extend the `y' yank transient with a "copy absolute path" entry.
  ;; `dirvish-yank-keys' is the documented extension point -- its `:set'
  ;; (`dirvish-yank--menu-setter') regenerates the `dirvish-yank-menu'
  ;; transient.  `dirvish-copy-file-path' already yields the absolute path
  ;; of the marked files (or the file at point): `dired-get-marked-files'
  ;; returns expanded names and `file-local-name' is a no-op off TRAMP.
  ;; `with-eval-after-load' so the defcustom exists before `setopt' fires;
  ;; the `assoc' guard keeps it idempotent across module reloads.
  (with-eval-after-load 'dirvish-yank
    (unless (assoc "w" dirvish-yank-keys)
      (setopt dirvish-yank-keys
              (append dirvish-yank-keys
                      '(("w" "Copy absolute path of marked file(s)"
                         dirvish-copy-file-path))))))
  :bind
  (("C-c f" . dirvish)
   ("C-c s" . dirvish-side)
   :map dirvish-mode-map
   (";"   . dired-up-directory)
   ("?"   . dirvish-dispatch)
   ("a"   . dirvish-setup-menu)
   ("f"   . dirvish-file-info-menu)
   ("o"   . dirvish-quick-access)
   ("s"   . dirvish-quicksort)
   ("r"   . dirvish-history-jump)
   ("l"   . dirvish-ls-switches-menu)
   ("v"   . dirvish-vc-menu)
   ("y"   . dirvish-yank-menu)
   ("N"   . dirvish-narrow)
   ("TAB" . dirvish-subtree-toggle)
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)))

(provide 'init-dirvish)
;;; init-dirvish.el ends here
