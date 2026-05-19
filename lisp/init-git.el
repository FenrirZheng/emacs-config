;;; init-git.el --- Git -- Magit + diff-hl -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 9 of the pre-split monolithic init.el (see git log for the move).
;; Magit, diff-hl, magit-todos, magit-delta, difftastic.

;;; Code:

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
;; `diff-hl-dired-mode' is intentionally NOT hooked: in $HOME (which is itself
;; a git repo with ~1500 tracked files), opening dired triggered a `git status'
;; + `git ls-files' sweep through the vc framework on every revert -- the
;; `emacs ./' in $HOME CPU spike. magit covers dired-side git status anyway.
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
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

;; magit-delta: pipe Magit's diff buffers through git-delta for syntax-
;; highlighted, side-by-side-capable diffs.  `magit-delta-mode' scopes the
;; integration to Magit buffers only -- your CLI `git diff' keeps whatever
;; pager you have configured (or none); it does NOT clobber `[core] pager'
;; globally.
;;
;; Requires the `delta' binary on PATH (Debian: `apt install git-delta',
;; provides /usr/bin/delta).  Without it, the mode loads but Magit just shows
;; the plain diff -- no error.
(use-package magit-delta
  :after magit
  :hook (magit-mode . magit-delta-mode))

;; difftastic: an AST-aware "structural" differ -- compares parse trees, not
;; lines.  Use it when a traditional diff shows "whole function deleted and
;; re-added" but the only real change was a rename, an indent tweak, or moving
;; a block by 20 lines.  Complements (does not replace) magit-delta: delta
;; renders every status-buffer diff cheaply on every refresh; difft is the
;; slower, on-demand option you reach for during code review on a specific
;; commit.
;;
;; Requires the `difft' binary on PATH (no apt package on Debian 13; install
;; via `cargo install --locked difftastic', lands in ~/.cargo/bin/difft).
;;
;; Integration: appends two suffixes to Magit's diff dispatch (press `d' in
;; any Magit buffer to open the transient):
;;     d D  -> difftastic-magit-diff   (dwim on the section / range at point)
;;     d S  -> difftastic-magit-show   (full diff of the commit at point)
;;
;; First-run note: as with every use-package block here, the archive isn't
;; refreshed at startup (see section 1).  After adding magit-delta and this
;; one: `M-x my/package-refresh' then restart Emacs once so both install.
(use-package difftastic
  :after magit
  :config
  (transient-append-suffix 'magit-diff '(-1 -1)
    [("D" "Difftastic diff (dwim)" difftastic-magit-diff)
     ("S" "Difftastic show"        difftastic-magit-show)]))

(provide 'init-git)
;;; init-git.el ends here
