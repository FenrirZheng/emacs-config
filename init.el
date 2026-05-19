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
        init-languages))

;; ---------------------------------------------------------------------------
;; 9. Git -- Magit + diff-hl
;; ---------------------------------------------------------------------------

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
;; `:defer t' is safe -- doom-modeline `require's it explicitly when it loads.
(use-package nerd-icons :defer t)

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
         (org-agenda-finalize . org-modern-agenda))
  :custom
  ;; Keep tables as plain ASCII `|' separators -- the default Unicode box-
  ;; drawing replacements (│ / ┃) read as visually heavy column dividers,
  ;; especially with CJK content.  Other restyling (headings, lists, blocks)
  ;; stays on.
  (org-modern-table nil))

;; org-appear: temporarily reveal the *bold* / =verbatim= / [[link]] markup of
;; whichever element point is on -- the complement to `org-hide-emphasis-markers'
;; above, so you can still edit the markers without globally un-hiding them.
(use-package org-appear
  :hook (org-mode . org-appear-mode))

;; ---------------------------------------------------------------------------
;; 13. Obsidian note vault -- obsidian.el
;; ---------------------------------------------------------------------------
;; The vault at ~/code/obsidian/ is plain Markdown, so `markdown-mode' (section
;; 8) already opens its notes.  obsidian.el adds the Obsidian-specific layer on
;; top: `[[wikilink]]' following, `#tag' awareness, YAML front-matter, daily
;; notes and a quick "jump to any note" command.  It's a global minor mode that
;; activates only inside files under `obsidian-directory', so it never touches
;; Markdown buffers elsewhere.
;;
;; First-run note: `use-package-always-ensure' is t but the archive is NOT
;; refreshed at startup (see section 1).  If obsidian isn't installed yet, run
;; `M-x my/package-refresh' then restart Emacs once.

(use-package obsidian
  :custom
  (obsidian-directory "~/code/obsidian")
  ;; New notes from `obsidian-capture' land here (relative to the vault);
  ;; leave at the vault root by default -- adjust if you keep an "Inbox/" dir.
  (obsidian-inbox-directory nil)
  :config
  (global-obsidian-mode 1)
  :bind
  (;; vault-wide commands (available everywhere, "n" = notes)
   ("C-c n n" . obsidian-jump)            ; open / switch to any note
   ("C-c n c" . obsidian-capture)         ; create a new note
   ("C-c n s" . obsidian-search)          ; full-text search the vault
   ;; in-vault editing (obsidian-mode is a minor mode -> these win over
   ;; markdown-mode's own C-c C-o / C-c C-l while inside the vault)
   :map obsidian-mode-map
   ("C-c C-o" . obsidian-follow-link-at-point)
   ("C-c C-l" . obsidian-insert-wikilink)))
;; More via `M-x obsidian-' : obsidian-daily-note, obsidian-backlink-jump,
;; obsidian-move-file, obsidian-rename, obsidian-update, ...

;; ---------------------------------------------------------------------------
;; 14. org-roam -- Zettelkasten over ~/code/org-roam
;; ---------------------------------------------------------------------------
;; ~/code/org-roam/ holds the .org notes converted from the Obsidian vault by
;; ~/code/obsidian-to-org-roam.py (re-runnable; see CONVERSION-REPORT.txt in
;; that directory).  org-roam adds an SQLite-backed link cache on top of plain
;; .org files: every note (a file with a top-level `:ID:' property) is a "node",
;; `[[id:...]]' links between them are bidirectional, and `org-roam-buffer'
;; shows the backlinks of whatever you're viewing.
;;
;; This is parallel to the Obsidian section above, not a replacement -- obsidian.el
;; still drives the original .md vault at ~/code/obsidian/.  Drop section 13 if
;; and when you fully move over.
;;
;; First run (the archive isn't refreshed at startup -- see section 1):
;;   M-x my/package-refresh  ->  restart Emacs  ->  M-x org-roam-db-sync
;; org-roam pulls in `emacsql'; Emacs 30's built-in SQLite covers it.
;;
;; `org-roam-graph' (M-x) renders a static link graph via Graphviz -- it needs
;; the `dot' binary (`apt install graphviz'); use `C-u M-x org-roam-graph' to
;; draw a local subgraph rather than all ~1400 nodes at once.  `org-roam-ui'
;; below is the nicer option for a vault this size: an interactive in-browser
;; D3 graph, no Graphviz required.

(use-package org-roam
  :custom
  (org-roam-directory (file-truename "~/code/org-roam"))
  ;; New note from `C-c r f' / `C-c r c': timestamp-${slug}.org with a #+title:
  ;; and a tag prompt.  `%(my/org-roam-prompt-filetags)' (defined in :config)
  ;; runs `completing-read-multiple' against the tags already in the roam DB --
  ;; so you pick from your existing vocabulary instead of inventing typo-variants;
  ;; entering nothing yields no #+filetags: line at all.  `%?' is where point
  ;; lands after capture; `:unnarrowed t' shows the whole file while capturing.
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
      :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                         "#+title: ${title}\n%(my/org-roam-prompt-filetags)")
      :unnarrowed t)))
  ;; The converted daily notes (2026-05-08.org, ...) sit at the vault root, not
  ;; in a `daily/' subdir, so point org-roam-dailies there with an empty subdir.
  (org-roam-dailies-directory "")
  ;; Fixed header for daily notes.  `file+head' inserts HEAD only when the day's
  ;; file doesn't exist yet; org-roam itself prepends the :ID: drawer above it,
  ;; so a brand-new daily ends up as:
  ;;   :PROPERTIES:  /  :ID: <auto>  /  :END:
  ;;   #+title: 2026-05-13 Tuesday
  ;;   #+filetags: :daily:
  ;;   * 14:32 <point>
  ;; The `entry' body "* %<%H:%M> %?" means every C-c r d capture adds a fresh
  ;; timestamped top-level heading (a running journal); `:unnarrowed t' keeps the
  ;; whole file visible while capturing.  `%A' is the locale's full weekday name.
  ;; For a fixed content skeleton instead, put the headings in HEAD and switch
  ;; the target to `(file+head+olp "%<%Y-%m-%d>.org" HEAD ("Log"))'.
  (org-roam-dailies-capture-templates
   '(("d" "default" entry
      "* %<%H:%M> %?"
      :target (file+head "%<%Y-%m-%d>.org"
                         "#+title: %<%Y-%m-%d %A>\n#+filetags: :daily:\n")
      :unnarrowed t)))
  (org-roam-completion-everywhere t)       ; complete [[ links from any buffer text
  :bind (("C-c r f" . org-roam-node-find)        ; open / create a note ("r" = roam)
         ("C-c r i" . org-roam-node-insert)      ; insert an [[id:...]] link to a note
         ("C-c r b" . org-roam-buffer-toggle)    ; backlinks side window
         ("C-c r c" . org-roam-capture)          ; capture a new note via a template
         ("C-c r d" . org-roam-dailies-goto-today))
  :config
  ;; Tag prompt used by `org-roam-capture-templates' above.  Completes against
  ;; every tag currently in the roam DB; returns a "#+filetags: :a:b:" line, or
  ;; "" when no tags are entered (so empty input leaves no stray header line).
  (defun my/org-roam-prompt-filetags ()
    "Prompt for org-roam file tags and return a `#+filetags:' line (or \"\")."
    (let ((tags (seq-remove #'string-empty-p
                            (completing-read-multiple
                             "Tags (comma-separated, empty = none): "
                             (org-roam-tag-completions)))))
      (if tags (format "#+filetags: :%s:\n" (string-join tags ":")) "")))
  ;; Keep the cache DB in sync as you edit/visit files.  The DB itself must be
  ;; built once first with `M-x org-roam-db-sync' (see the first-run note above).
  (org-roam-db-autosync-mode 1))

;; org-roam-ui: an interactive graph of the roam DB rendered in the browser
;; (D3 force-directed; click a node to jump to it, follows point in Emacs,
;; matches the Emacs theme).  Pulls in `websocket' + `simple-httpd' and runs a
;; local HTTP server while `org-roam-ui-mode' is on.  No Graphviz needed -- this
;; is the practical alternative to `org-roam-graph' for a large vault.
(use-package org-roam-ui
  :after org-roam
  :custom
  (org-roam-ui-sync-theme t)
  (org-roam-ui-follow t)                   ; the graph tracks the note you're in
  (org-roam-ui-update-on-save t)
  (org-roam-ui-open-on-start nil)          ; don't auto-launch a browser tab
  :bind ("C-c r g" . org-roam-ui-mode))    ; "g" = graph; toggles the server + tab

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
