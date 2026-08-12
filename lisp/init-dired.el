;;; init-dired.el --- Dired + small enhancers + consult-dir -*- lexical-binding: t; -*-

;;; Commentary:
;; Replaces the previous `init-dirvish' module.  Rather than one big package
;; (Dirvish) that wraps Dired in its own UI + transient cockpit, this module
;; keeps stock Dired and layers small, orthogonal helpers:
;;
;;   dired-x            -- built-in; only used for `dired-jump' on `C-x C-j'
;;   diredfl            -- per-column font-lock (perms / size / date / owner)
;;   nerd-icons-dired   -- file-type glyphs inline (reuses the existing
;;                         nerd-icons font, same one doom-modeline uses)
;;   dired-subtree      -- `TAB' expands a directory in place
;;   dired-narrow       -- `N' live-filters the current Dired buffer
;;   dired-collapse     -- collapse single-child dir chains onto one line
;;   async (dired-async-mode) -- non-blocking copy/rename/delete
;;   consult-dir        -- multi-source directory picker; integrates with
;;                         vertico/orderless/marginalia like the rest of the
;;                         minibuffer stack (see init-completion.el)
;;
;; Plus `wdired-allow-to-change-permissions = 'advanced' so `C-x C-q' edits
;; mode bits, not just filenames.
;;
;; Things from Dirvish we explicitly DROP:
;;   * the preview side panel (was unused; TTY frames at 80 columns can't
;;     spare the width).  Re-enable via `(use-package dired-preview :hook
;;     (dired-mode . dired-preview-mode))' if you want it back.
;;   * `dirvish-side' (the treemacs-like sidebar) -- already retired from
;;     Tier 1 in tasks/done/20260525-1808-vscode-parity-tier1/TASKS.md.
;;   * the `?' dispatch transient + setup-menu / ls-switches-menu /
;;     quicksort -- which-key (init-defaults.el) covers discoverability,
;;     and `dired-listing-switches' is pinned anyway.
;;   * `dirvish-fd-program' async listing for >20k-entry dirs -- daily
;;     edited dirs don't hit that; `consult-find' (`M-s f') is the escape
;;     hatch when needed.

;;; Code:

(use-package dired
  :ensure nil
  :custom
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group")
  ;; Reuse the current Dired buffer on descent instead of stacking a fresh
  ;; one per directory.  `dired-find-alternate-file' is disabled by default
  ;; because new users were surprised by the in-place replacement; we want
  ;; it on.
  (dired-kill-when-opening-new-dired-buffer t)
  ;; wdired (`C-x C-q' inside Dired) is editable-buffer mode for Dired:
  ;; rename files by editing the text.  `advanced' extends that to mode
  ;; bits -- edit "-rw-r--r--" → "-rwxr-xr-x" and save to chmod.
  (wdired-allow-to-change-permissions 'advanced)
  :config
  (put 'dired-find-alternate-file 'disabled nil))

;; dired-x: built-in companion module.  We only need `dired-jump' -- from
;; any buffer, pop a Dired on the directory containing the current file,
;; with point already on that file.  Conventionally bound on `C-x C-j'.
;; (`C-x C-j' in `vertico-map' is a separate binding for
;; `consult-dir-jump-file' -- that one only fires inside an active
;; minibuffer; this global one fires elsewhere.)
(use-package dired-x
  :ensure nil
  :after dired
  :bind (("C-x C-j" . dired-jump)))

;; diredfl: extra font-lock for Dired so permission bits, sizes, timestamps,
;; owner/group, and executable flags each get their own face.  Replaces
;; Dirvish's `file-time' / `file-size' coloured attributes.
(use-package diredfl
  :hook (dired-mode . diredfl-mode))

;; nerd-icons-dired: inline file-type glyphs at the start of each line.
;; Reuses the nerd-icons font stack that doom-modeline already requires
;; (`M-x nerd-icons-install-fonts' once -- already in the bootstrap notes).
(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

;; dired-subtree: `TAB' expands the directory at point as an inline subtree
;; (matches Dirvish's `subtree-state' + `TAB' binding).  `<backtab>'
;; (Shift-TAB) cycles fold depth.
(use-package dired-subtree
  :bind (:map dired-mode-map
              ("TAB"       . dired-subtree-toggle)
              ("<backtab>" . dired-subtree-cycle)))

;; dired-narrow: `N' opens a live minibuffer filter over the current Dired
;; buffer (matches `dirvish-narrow' on the same key).  `RET' commits and
;; leaves the buffer filtered; `g' (`revert-buffer') refreshes back to full.
(use-package dired-narrow
  :bind (:map dired-mode-map
              ("N" . dired-narrow)))

;; dired-collapse: collapse single-child directory chains onto one line.
;; `foo/bar/baz/file.txt' shows as a single entry when foo/, bar/, baz/
;; each contain only their next child -- huge readability win in deeply
;; nested project trees (Rust `target/`, Go `vendor/`, Java package paths).
(use-package dired-collapse
  :hook (dired-mode . dired-collapse-mode))

;; dired-async: file operations (`C' copy, `R' rename/move, `D' delete)
;; that would otherwise block Emacs run in a child process.  Pulls in
;; `async' as a dep.  The mode hooks into Dired's dispatch table -- no
;; per-command setup needed.
(use-package async
  :config (dired-async-mode 1))

;; consult-dir: the directory-picker counterpart to consult-buffer.  It
;; aggregates several sources -- recentf parent dirs, project roots,
;; bookmarks, the current `default-directory', and a custom "Quick" list
;; defined below -- into a single Vertico-driven prompt.
;;
;; Two entry points:
;;   * Globally on `C-x C-d' (was the rarely-used `list-directory'): pick a
;;     dir and `dired' opens it.
;;   * Inside `find-file' (vertico-map `C-x C-d'): pick a dir, the path is
;;     inserted into the current minibuffer prompt so you can keep typing
;;     a filename without `C-a C-k'-ing the partial input.
;;   * `C-x C-j' in vertico-map -- pick a dir and immediately jump to a
;;     file in it (consult-dir's own `consult-dir-jump-file').
;;
;; `narrow' keys (default consult narrow on `<'): r=recent, p=project,
;; b=bookmark, d=default, q=quick.  So `<' then `q' shows just the curated
;; quick-access entries from `dirvish-quick-access-entries' below.
(use-package consult-dir
  :bind (("C-x C-d" . consult-dir)
         :map vertico-map
         ("C-x C-d" . consult-dir)
         ("C-x C-j" . consult-dir-jump-file))
  :config
  ;; Replaces the old `dirvish-quick-access-entries' transient.  These are
  ;; the same six destinations, but routed through consult-dir's source
  ;; system so they live in the same minibuffer prompt as recents/projects/
  ;; bookmarks -- type `emacs' / `obs' / `roam' to filter, no quick-key
  ;; memorisation needed.  Narrow to this source alone with `< q'.
  (defvar fenrir/consult-dir--source-quick
    `(:name     "Quick"
      :narrow   ?q
      :category file
      :face     consult-file
      :history  file-name-history
      :items    ,(lambda ()
                   '("~/"
                     "~/.emacs.d/"
                     "~/.claude/"
                     "~/code/obsidian/"
                     "~/code/org-roam/"
                     "~/fenrir-tools/")))
    "consult-dir source -- the curated quick-access destinations.")
  (add-to-list 'consult-dir-sources 'fenrir/consult-dir--source-quick t))

;; Tiny replacement for Dirvish's `dirvish-yank-menu' -> `w' "copy absolute
;; path" entry.  Pushes the marked files' (or the file at point's) absolute
;; paths onto the kill ring AND the system clipboard, one per line.
;; `dired-get-marked-files' already returns expanded paths, so no need for
;; `expand-file-name'.  Routes via `fenrir/clipboard-push' (defined in
;; [init-defaults.el](init-defaults.el)) so the path crosses the
;; tmux/SSH boundary in TTY frames and reaches the X / Wayland selection in
;; GUI frames -- plain `kill-new' misses both in this config (see comments
;; at the top of `fenrir/clipboard-push' for the why).
;;
;; Bound on `C-c w' inside `dired-mode-map' to avoid colliding with stock
;; Dired's `w' (`dired-copy-filename-as-kill', which yanks BASENAMES -- a
;; useful sibling to keep around).
(defun fenrir/dired-copy-absolute-path ()
  "Copy the absolute path(s) of the marked file(s) to the system clipboard."
  (interactive)
  (let* ((files (dired-get-marked-files))
         (text  (mapconcat #'identity files "\n")))
    (fenrir/clipboard-push text)
    (message "Copied %d path%s: %s"
             (length files)
             (if (= 1 (length files)) "" "s")
             text)))

(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "C-c w") #'fenrir/dired-copy-absolute-path))

(provide 'init-dired)
;;; init-dired.el ends here
