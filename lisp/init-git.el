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
  ;; diff-hl computes its gutter through vc.el (`vc-backend'), so vc.el needs a
  ;; backend enabled -- keep ONLY Git, since the stock list also probes
  ;; CVS/SVN/Hg/Bzr/... once per file for nothing. Interactive VC still goes
  ;; exclusively through Magit (see the `C-x v' remap below).
  (setq vc-handled-backends '(Git))
  ;; $HOME is tracked with `status.showUntrackedFiles=no' (~1M hidden entries);
  ;; Magit doesn't honour that config and would still walk them. Drop the
  ;; section -- in normal repos `git status -s` is one keystroke away anyway.
  (remove-hook 'magit-status-sections-hook 'magit-insert-untracked-files))

;; C-x v : retire vc.el's prefix, hand it to Magit.
;; vc.el's stock `C-x v ...' commands work again (the Git backend is enabled
;; in the magit block above) -- but every interactive VC task here goes
;; through Magit by preference, so replace the whole prefix map: each Magit
;; command keeps the slot vc.el used, so vc muscle memory carries straight
;; over. Six targets are transient prefixes (diff/blame/pull/push/merge/tag)
;; -- the key opens that menu, as in any Magit buffer. vc keys with no crisp
;; Magit counterpart (vc-register, vc-log-incoming/outgoing, vc-region-history,
;; vc-edit-next-command, vc-update-change-log) are dropped -- those `C-x v'
;; slots become undefined.
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

;; The `E' key of `fenrir/magit-vc-map' (C-x v E).  A Magit-native take on
;; Emacs' `ediff-revision': a two-step branch->revision picker (no hash to
;; type) that also works from a Magit revision buffer, not just a working-
;; tree file.  `magit-find-file-noselect' fetches the chosen blob via git.
(defun fenrir/ediff-buffer-vs-revision (rev file)
  "Ediff the current buffer against REV's version of FILE.
Works whether the current buffer is a working-tree file or a Magit
revision buffer (a \"FILE.~REV~\" blob from `magit-find-file'): pick a
branch, then a revision from that branch's commit history of the file,
and that revision is Ediff'd against the current buffer.  A working-
tree buffer is compared as-is, so unsaved edits are part of the diff;
from a revision buffer it is a plain revision-vs-revision comparison."
  (interactive
   ;; `magit-*' helpers are not autoloaded, and an `interactive' form runs
   ;; before the body -- so the require has to happen right here.
   (progn
     (require 'magit)
     ;; A Magit revision buffer has no `buffer-file-name' -- the path it
     ;; shows lives in `magit-buffer-file-name'. Falling back to it lets
     ;; `C-x v E' work while reading a blob, not only the working file.
     (let* ((file   (or buffer-file-name
                        (bound-and-true-p magit-buffer-file-name)
                        (user-error
                         "Buffer %s visits neither a file nor a revision"
                         (buffer-name))))
            (branch (magit-read-branch "Compare against a revision on branch"))
            ;; Step 2's candidates: the file's modification history reachable
            ;; from BRANCH (newest first) -- the revisions on that branch
            ;; where an ediff against this file is meaningful.
            (log    (magit-git-lines "log" branch "--max-count=200"
                                     "--format=%h  %cs  %s"
                                     "--" file)))
       (unless log
         (user-error "%s has no history on branch %s"
                     (file-name-nondirectory file) branch))
       ;; A candidate is "<hash>  <date>  <subject>" -- keep the first token
       ;; (a hash typed by hand passes straight through too).
       (list (car (split-string
                   (magit-completing-read
                    (format "Revision on %s" branch)
                    log nil nil nil 'magit-revision-history)))
             file))))
  (unless rev
    (user-error "No revision selected"))
  (let ((rev-buffer (magit-find-file-noselect rev file)))
    ;; From a revision buffer, picking the very revision it shows would feed
    ;; the same buffer to both sides of the ediff.
    (when (eq rev-buffer (current-buffer))
      (user-error "Pick a revision other than the one this buffer shows"))
    (ediff-buffers rev-buffer (current-buffer))))

;; diff-hl: show added/changed/removed lines in the window margin, live.
;;
;; Chosen over git-gutter: diff-hl integrates cleanly with Magit (the
;; pre/post-refresh hooks below keep the margin in sync after a stage/commit)
;; and is actively maintained. The price is a vc.el dependency -- diff-hl
;; computes its diff via `vc-backend', which is why `vc-handled-backends' has
;; to keep the Git backend (see the Magit block above).
;;
;; `diff-hl-dired-mode' is intentionally NOT hooked: in $HOME (which is itself
;; a git repo with ~1500 tracked files), opening dired triggered a `git status'
;; + `git ls-files' sweep through the vc framework on every revert -- the
;; `emacs ./' in $HOME CPU spike. magit covers dired-side git status anyway.
(use-package diff-hl
  :hook
  ;; pre/post pair: `pre' snapshots state before a Magit refresh so `post'
  ;; redraws the margin accurately after a commit/stage/unstage/...
  ((magit-pre-refresh  . diff-hl-magit-pre-refresh)
   (magit-post-refresh . diff-hl-magit-post-refresh))
  ;; Hunk-level gutter actions on a `C-c v' prefix ("VCS changes") -- the modern
  ;; IDE "jump between changes / preview / revert / stage this hunk" the gutter
  ;; offers, without opening a full Magit buffer.  (The `C-x v' prefix is taken
  ;; by `fenrir/magit-vc-map' above, so diff-hl's own command map is unreachable
  ;; -- hence these explicit binds.)  `diff-hl-show-hunk' previews inline on TTY;
  ;; `diff-hl-stage-current-hunk' stages just the hunk at point.
  :bind (("C-c v n" . diff-hl-next-hunk)
         ("C-c v p" . diff-hl-previous-hunk)
         ("C-c v s" . diff-hl-show-hunk)
         ("C-c v r" . diff-hl-revert-hunk)
         ("C-c v S" . diff-hl-stage-current-hunk))
  :init
  ;; Enable in every file buffer, not just `prog-mode': org notes, config
  ;; files and prose are version-controlled too.
  (global-diff-hl-mode 1)
  :config
  ;; Draw indicators in the margin, not the fringe: this config is TTY-only
  ;; (emacsclient -nw in tmux) and TTY frames have no fringe -- without this
  ;; diff-hl-mode is enabled but renders into nothing.
  (diff-hl-margin-mode 1)
  ;; Refresh as you type, not only on save / VC op / Magit refresh -- flydiff
  ;; diffs the buffer against its committed blob, per-buffer, cheap in $HOME.
  (diff-hl-flydiff-mode 1))

;; Make hunk-hopping repeatable: after the first `C-c v n' (or `p'/`s'/`r'),
;; bare `n'/`p'/`s'/`r' continue without the `C-c v' prefix until any other
;; key.  `repeat-mode' is already on (init-defaults.el); `:repeat t' stamps the
;; `repeat-map' property on each command so it joins that machinery.  Stepping
;; through every change in a file is the canonical repeat case.
(defvar-keymap fenrir/diff-hl-hunk-repeat-map
  :doc "Repeat map for diff-hl hunk navigation (see `repeat-mode')."
  :repeat t
  "n" #'diff-hl-next-hunk
  "p" #'diff-hl-previous-hunk
  "s" #'diff-hl-show-hunk
  "r" #'diff-hl-revert-hunk)

;; forge: Magit-native GitHub PR / Issue browsing.  Adds two sections to the
;; magit-status buffer ("Pull requests" and "Issues") and a `@' transient
;; (e.g. `@ p l' to fetch PRs, `@ p p' to act on the PR at point) that lives
;; alongside Magit's other transients.  Same keybindings + UI as the rest of
;; Magit, no second tool to learn.
;;
;; First-time setup (per machine, NOT in this repo):
;;   1.  Mint a GitHub PAT with scopes `repo' + `read:org' --
;;       `gh auth token' already prints one if `gh' is logged in; otherwise
;;       create a fine-grained token under
;;       https://github.com/settings/tokens.
;;   2.  Store it in `~/.authinfo.gpg' as:
;;          machine api.github.com login <user>^forge password <token>
;;       The `^forge' suffix is how forge namespaces the credential apart
;;       from any other api.github.com entry (e.g. `gh' / glab / hub).
;;   3.  In the target repo: `M-x forge-add-repository' (or `@ a').  Forge
;;       clones the issue/PR metadata into a local sqlite DB under
;;       `forge-database-file' (no-littering parks it in `var/').
;;
;; Intentionally NOT enabled: `forge-pull-notifications' -- it polls
;; api.github.com periodically and surfaces results via `message', which
;; dirties the minibuffer in a TTY workflow where every echo-area line is
;; precious.  Reach for `M-x forge-pull' on demand instead.
;;
;; First-run note: not in elpa/ on a fresh clone -- `M-x my/package-refresh'
;; then restart the daemon once so the install runs.  The first
;; `forge-add-repository' will also run a sqlite schema migration; let it.
(use-package forge
  :after magit)

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

;; smerge (built-in): the merge-conflict resolver -- the IDE "accept current /
;; incoming / both" UI for `<<<<<<< ======= >>>>>>>' markers.  Two ergonomics
;; fixes over the bare built-in:
;;   1. AUTO-ENABLE: `smerge-mode' is normally off until you `M-x' it, so a
;;      freshly-merged file with conflicts looks like plain broken text.  The
;;      `find-file' / revert hook scans for a conflict marker and turns it on
;;      automatically -- conflicts light up the moment you open the file.
;;   2. MEMORABLE PREFIX: the native prefix is `C-c ^' (awkward, like hideshow's
;;      old chords).  Move it to `C-c m' ("merge"); which-key then lists the
;;      single-letter actions (`n'/`p' next/prev, `RET' keep-current,
;;      `a' keep-all, `u'/`l' keep-upper/lower, `b' keep-base, `R' refine,
;;      `E' ediff) after the prefix.
;; `smerge-command-prefix' is read when the keymap is constructed, so set it via
;; `:custom' (before the mode's map is built) rather than after the fact.
(defun fenrir/smerge-maybe-enable ()
  "Turn on `smerge-mode' if the buffer contains a git conflict marker.
Top-level (not inside the `use-package' `:init') so the byte-compiler sees
the definition before the `add-hook' references it."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^<<<<<<< " nil t)
      (smerge-mode 1))))

(use-package smerge-mode
  :ensure nil
  :custom (smerge-command-prefix (kbd "C-c m"))
  :init
  (add-hook 'find-file-hook #'fenrir/smerge-maybe-enable)
  (add-hook 'after-revert-hook #'fenrir/smerge-maybe-enable))

;; consult-todo: jump to any hl-todo keyword (TODO / FIXME / HACK / BUG / ...)
;; via a consult minibuffer with live preview -- the "navigate to TODO" picker.
;; Complements magit-todos above (which lists them statically in the Magit
;; status buffer): this is the interactive jump-to-one, reusing the same
;; `hl-todo-keyword-faces' set (init-editing.el) so what's coloured in the
;; buffer is exactly what's listed.  `M-g t' = this buffer, `M-g T' = every
;; open buffer (the `M-g' "goto" prefix already holds consult-imenu / -flymake).
(use-package consult-todo
  :after (consult hl-todo)
  :bind (("M-g t" . consult-todo)
         ("M-g T" . consult-todo-all)))

(provide 'init-git)
;;; init-git.el ends here
