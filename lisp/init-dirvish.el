;;; init-dirvish.el --- Dirvish: polished Dired with icons + preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish (https://github.com/alexluigit/dirvish) layers icons, preview,
;; history, a side panel, and a `?'-driven transient cheat-sheet on top of
;; Dired.  `dirvish-override-dired-mode' makes every `C-x d' / `C-x C-f'
;; into-a-directory route through Dirvish without a separate keybind.
;;
;; Attribute choices vs. upstream's sample config:
;;   * `git-msg' (inline last-commit subject) IS enabled -- but scoped:
;;     the `my/dirvish-vc-scope-to-projects' advice below keeps it (and
;;     the per-file vc fetch behind it) OFF in $HOME itself, a ~1500-file
;;     git repo where the per-file `git log -1' is the churn that got
;;     `diff-hl-dired-mode' dropped in init-git.el.  It stays live in real
;;     project dirs.  NOTE: the gate is the `:vc-backend' dirvish prop,
;;     NOT `vc-handled-backends' -- dirvish resolves the backend in an
;;     `emacs -Q -batch' subprocess that never sees init-git.el's `(setq
;;     vc-handled-backends nil)'.  See the advice's comment below.
;;   * `vc-state' is NOT enabled -- it renders in the left fringe
;;     (dirvish-vc.el: "only works on graphic displays"), so it is
;;     invisible on TTY frames (`emacsclient -nw').  `git-msg' is the
;;     TTY-visible git indicator; `vc-state' would be dead config here.

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
  ;; why `git-msg' is scoped and `vc-state' is omitted.
  (setq dirvish-attributes
        '(subtree-state nerd-icons collapse git-msg file-time file-size))
  (setq dirvish-side-attributes
        '(nerd-icons collapse file-size))
  ;; Hand off >20k-entry dirs to `fd' so the UI doesn't block.  `fdfind' is
  ;; the Debian binary name; upstream calls it `fd'.
  (setq dirvish-large-directory-threshold 20000)
  (setq dirvish-fd-program (or (executable-find "fdfind")
                               (executable-find "fd")))
  ;; Scope `git-msg' to non-$HOME git repos.  `:vc-backend' is dirvish's
  ;; master vc gate: the per-directory vc fetch (`vc-state-refresh' +
  ;; `git log -1' per file) and the `git-msg' attribute both fire only
  ;; when that prop holds a backend symbol.  dirvish resolves the backend
  ;; in an `emacs -Q -batch' subprocess, so init-git.el's `(setq
  ;; vc-handled-backends nil)' never reaches it -- without this advice
  ;; `git-msg' would run `git log -1' across $HOME's ~1500 tracked files.
  ;; Pre-setting the prop to a non-symbol (0) for $HOME-rooted dirs makes
  ;; the subprocess skip `vc-responsible-backend' and the `git-msg'
  ;; `:when' predicate fail.
  (defun my/dirvish-vc-scope-to-projects (dir buffer &rest _)
    "Disable dirvish git-msg unless DIR sits in a non-$HOME git repo.
:before advice for `dirvish--dir-data-async'."
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((root (locate-dominating-file
                     (or dir default-directory) ".git")))
          (when (or (null root)
                    (file-equal-p root (expand-file-name "~/")))
            (dirvish-prop :vc-backend 0))))))
  (advice-add 'dirvish--dir-data-async :before
              #'my/dirvish-vc-scope-to-projects)
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
