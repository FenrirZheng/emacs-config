;;; init-dirvish.el --- Dirvish: polished Dired with icons + preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish (https://github.com/alexluigit/dirvish) layers icons, preview,
;; history, a side panel, and a `?'-driven transient cheat-sheet on top of
;; Dired.  `dirvish-override-dired-mode' makes every `C-x d' / `C-x C-f'
;; into-a-directory route through Dirvish without a separate keybind.
;;
;; Two deliberate omissions vs. upstream's sample config:
;;   * `vc-state' is NOT in `dirvish-attributes' -- init-git.el sets
;;     `vc-handled-backends' to nil (Magit replaces vc), so vc-state would
;;     silently no-op while still costing a per-line query.
;;   * `git-msg' is NOT in `dirvish-attributes' -- $HOME is itself a git
;;     repo with ~1500 tracked files; `git-msg' calls `git log -1' per
;;     visible row, same hazard that motivated disabling
;;     `diff-hl-dired-mode' in init-git.el.  Toggle per-buffer with `a'
;;     (`dirvish-setup-menu') when you want it.

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
  ;; why vc-state and git-msg are omitted from the default set.
  (setq dirvish-attributes
        '(subtree-state nerd-icons collapse file-time file-size))
  (setq dirvish-side-attributes
        '(nerd-icons collapse file-size))
  ;; Hand off >20k-entry dirs to `fd' so the UI doesn't block.  `fdfind' is
  ;; the Debian binary name; upstream calls it `fd'.
  (setq dirvish-large-directory-threshold 20000)
  (setq dirvish-fd-program (or (executable-find "fdfind")
                               (executable-find "fd")))
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
