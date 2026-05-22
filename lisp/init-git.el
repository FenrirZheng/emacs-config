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

;; C-x v : retire vc.el's prefix, hand it to Magit.
;; `vc-handled-backends' is nil (set in the magit block above), so vc.el's
;; stock `C-x v ...' prefix map is 23 keys that all error "not under version
;; control". Replace the whole map: each Magit command keeps the slot vc.el
;; used, so vc muscle memory carries straight over. Six targets are transient
;; prefixes (diff/blame/pull/push/merge/tag) -- the key opens that menu, as in
;; any Magit buffer. vc keys with no crisp Magit counterpart (vc-register,
;; vc-log-incoming/outgoing, vc-region-history, vc-edit-next-command,
;; vc-update-change-log) are dropped -- those `C-x v' slots become undefined.
;;
;; One slot is an addition vc.el never had: `E' pairs with lowercase `e'
;; (magit-ediff-dwim) -- `e' is the quick dwim, `E' compares the visited
;; file against a revision you pick.  It runs the custom command
;; `fenrir/ediff-buffer-vs-revision' (defined below), NOT `ediff-revision'.
(defvar-keymap fenrir/magit-vc-map
  :doc "Magit replacements bound on the retired `C-x v' (vc.el) prefix."
  "e" #'magit-ediff-dwim          ; vc-ediff
  "E" #'fenrir/ediff-buffer-vs-revision  ; addition (see below)
  "=" #'magit-diff-buffer-file    ; vc-diff
  "D" #'magit-diff                ; vc-root-diff
  "l" #'magit-log-buffer-file     ; vc-print-log
  "L" #'magit-log-current         ; vc-print-root-log
  "g" #'magit-blame               ; vc-annotate
  "d" #'magit-status              ; vc-dir
  "v" #'magit-stage-buffer-file   ; vc-next-action
  "u" #'magit-file-checkout       ; vc-revert
  "+" #'magit-pull                ; vc-update
  "P" #'magit-push                ; vc-push
  "m" #'magit-merge               ; vc-merge
  "s" #'magit-tag                 ; vc-create-tag
  "r" #'magit-branch-checkout     ; vc-retrieve-tag
  "G" #'magit-gitignore           ; vc-ignore
  "~" #'magit-find-file           ; vc-revision-other-window
  "x" #'magit-file-delete)        ; vc-delete-file
(keymap-set ctl-x-map "v" fenrir/magit-vc-map)

;; The `E' key of `fenrir/magit-vc-map' (C-x v E).  Emacs' own
;; `ediff-revision' / `vc-diff' can't be used here: both route through
;; vc.el, and `vc-handled-backends' is nil (set in the Magit block above),
;; so they error "not under version control".  This goes through Magit
;; instead -- `magit-find-file-noselect' shells out to git directly.
(defun fenrir/ediff-buffer-vs-revision (rev)
  "Ediff the current buffer against a past version of the visited file.
Pick a branch, then a revision from that branch's commit history of the
file (each commit annotated with date + subject) -- two steps, no hash
to type from memory.  The current buffer is compared as-is, so unsaved
edits are part of the diff."
  (interactive
   ;; `magit-*' helpers are not autoloaded, and an `interactive' form runs
   ;; before the body -- so the require has to happen right here.
   (progn
     (require 'magit)
     (unless buffer-file-name
       (user-error "Buffer %s is not visiting a file" (buffer-name)))
     (let* ((branch (magit-read-branch "Compare against a revision on branch"))
            ;; Step 2's candidates: the file's modification history reachable
            ;; from BRANCH (newest first) -- the revisions on that branch
            ;; where an ediff against this file is meaningful.
            (log    (magit-git-lines "log" branch "--max-count=200"
                                     "--format=%h  %cs  %s"
                                     "--" buffer-file-name)))
       (unless log
         (user-error "%s has no history on branch %s"
                     (file-name-nondirectory buffer-file-name) branch))
       ;; A candidate is "<hash>  <date>  <subject>" -- keep the first token
       ;; (a hash typed by hand passes straight through too).
       (list (car (split-string
                   (magit-completing-read
                    (format "Revision on %s" branch)
                    log nil nil nil 'magit-revision-history)))))))
  (unless rev
    (user-error "No revision selected"))
  (ediff-buffers (magit-find-file-noselect rev buffer-file-name)
                 (current-buffer)))

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
