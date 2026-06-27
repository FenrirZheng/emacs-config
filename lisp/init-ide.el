;;; init-ide.el --- Modern-IDE enhancement layer -*- lexical-binding: t; -*-

;;; Commentary:
;; A cohesive "bring the VSCode / JetBrains conveniences to Emacs" layer,
;; kept as its OWN module (like init-aidermacs / init-tmux-claude) rather than
;; smeared across init-editing / init-appearance, so the whole initiative is
;; easy to read, document, and revert as a unit.  Everything here is chosen to
;; work on a TTY frame (the user runs `emacs --daemon' + `emacsclient -nw'
;; inside tmux) -- no child-frame / posframe packages.
;;
;; What lives where (the rest of the IDE story is already wired elsewhere):
;;   * LSP / refactor / hierarchy / inlay hints  -> init-languages.el (Eglot)
;;   * tree-sitter syntax + structural editing    -> init-languages.el
;;     (treesit-auto, combobulate, treesit-fold on C-c z)
;;   * debugger (DAP)                             -> init-languages.el (dape)
;;   * completion (in-buffer + minibuffer)        -> init-corfu / init-completion
;;   * snippets                                   -> init-snippets
;;   * git porcelain + gutter                     -> init-git.el (magit, diff-hl)
;;   * project diagnostics / symbols / grep       -> init-completion.el
;;     (consult-flymake M-g f, consult-imenu M-g i, consult-ripgrep M-s r, wgrep)
;;   * format-on-save                             -> init-languages.el (apheleia)
;;   * workspace tab row                          -> init-appearance.el (tab-bar)
;;
;; This module fills the remaining gaps a "modern IDE" user reaches for:
;;   current-line highlight, camelCase motion, indentation guides, highlight-
;;   all-occurrences, inline colour swatches, ripgrep jump fallback, offline
;;   API docs, goto-last-change, move-line-up/down, naming-convention cycling,
;;   on-save whitespace trim, git permalinks / time-machine / inline blame,
;;   a file-tree sidebar, project-scoped workspaces, and an in-editor REST
;;   client.  Each `use-package' block carries a WHY-comment in the house style.

;;; Code:

;; ---------------------------------------------------------------------------
;; Built-in toggles (no install) -- two cheap defaults every IDE has on.
;; ---------------------------------------------------------------------------

;; hl-line: highlight the line point is on.  Off by default in this config; a
;; modern IDE always marks the current line.  Enabled in `prog-mode' and the
;; list-style special buffers where a row cursor genuinely helps (dired,
;; ibuffer, grep/occur results, the package menu, any tabulated-list UI such as
;; `claude-jobs-view').  Deliberately NOT `global-hl-line-mode': a persistent
;; line highlight in vterm / the minibuffer / org prose is visual noise, and on
;; an 8/16-colour TTY a full-width highlight can fight region selection.
(dolist (hook '(prog-mode-hook
                dired-mode-hook
                ibuffer-mode-hook
                grep-mode-hook
                occur-mode-hook
                tabulated-list-mode-hook
                package-menu-mode-hook))
  (add-hook hook #'hl-line-mode))

;; subword: treat camelCase / PascalCase sub-words as word boundaries, so
;; `M-f' / `M-b' / `M-d' stop at `get|User|Name' instead of swallowing the
;; whole identifier -- the motion model every IDE uses in code.  `global-' so
;; it also helps in the minibuffer when editing a symbol name.  Pure motion
;; tweak, no display, TTY-irrelevant.
(global-subword-mode 1)

;; ---------------------------------------------------------------------------
;; Visual code aids
;; ---------------------------------------------------------------------------

;; indent-bars: vertical indentation guides (the VSCode "indent rainbow" /
;; JetBrains indent guides).  Crucial for indentation-structured code (Python,
;; YAML) and still useful for brace languages.  Same author as breadcrumb /
;; eglot-booster.
;;
;; TTY-critical knobs:
;;   * `indent-bars-prefer-character' t -- the default renders bars with a
;;     GUI-only stipple face that shows as a SOLID BLOCK (or nothing) on a TTY.
;;     Forcing the character backend draws a real glyph (`indent-bars-pattern')
;;     in each indent column, which is what works in `emacsclient -nw'.
;;   * tree-sitter scope is left OFF here: `indent-bars-treesit-support' adds a
;;     parser query per buffer and its main payoff (highlighting the *current*
;;     scope's bar) leans on colour depth a TTY palette can't show well.  Plain
;;     column bars are the high-value, low-cost part.
(use-package indent-bars
  :hook ((prog-mode . indent-bars-mode)
         (yaml-ts-mode . indent-bars-mode))
  :custom
  (indent-bars-prefer-character t)         ; mandatory for TTY frames
  (indent-bars-treesit-support nil)
  ;; Thin, low-contrast guides: a faint `│'-style column, not a loud ladder.
  (indent-bars-pattern ".")
  (indent-bars-width-frac 0.2)
  (indent-bars-color '(highlight :face-bg t :blend 0.225)))

;; symbol-overlay: highlight every occurrence of the symbol at point and jump
;; between them -- the JetBrains "highlight usages in file" / VSCode
;; double-click-to-highlight.  Pure overlays, full TTY support.  Distinct from
;; Eglot rename (whole-project, semantic) and from isearch: this is a fast,
;; buffer-local, lexical highlight you toggle to eyeball where a variable is
;; used, with an in-place rename for the quick same-buffer case.
;;
;; `C-c s' is a free prefix (eglot refactors sit on `C-c .'/`r'/`i'/`x'/`f',
;; combobulate on `C-c o', folding on `C-c z' -- none collide).
(use-package symbol-overlay
  :bind (("C-c s s" . symbol-overlay-put)        ; toggle highlight at point
         ("C-c s n" . symbol-overlay-jump-next)
         ("C-c s p" . symbol-overlay-jump-prev)
         ("C-c s r" . symbol-overlay-rename)     ; rename all in this buffer
         ("C-c s a" . symbol-overlay-remove-all)))

;; colorful-mode: render a swatch next to every `#rrggbb' / `rgb(...)' /
;; CSS-colour-name in the buffer (successor to rainbow-mode; GNU ELPA, actively
;; maintained).  On a truecolor tmux/TTY the swatch shows as the literal colour
;; behind the text, so editing themes / CSS / Tailwind values is WYSIWYG.
;; Scoped to the modes where colours actually appear rather than `global-' so it
;; doesn't scan prose buffers for stray hex.
(use-package colorful-mode
  :hook ((prog-mode . colorful-mode)
         (css-mode . colorful-mode)
         (css-ts-mode . colorful-mode)
         (web-mode . colorful-mode)
         (html-mode . colorful-mode)
         (conf-mode . colorful-mode))
  :custom
  ;; Also colourise bare CSS names like `tomato' / `rebeccapurple', not just
  ;; hex -- matches what VSCode's colour decorators do in stylesheets.
  (colorful-use-prefix nil))

;; ---------------------------------------------------------------------------
;; Navigation / code intelligence
;; ---------------------------------------------------------------------------

;; dumb-jump: a ripgrep/grep-driven "jump to definition" that needs NO language
;; server or tags DB -- the universal fallback for the long tail of files where
;; neither Eglot nor a prebuilt GTAGS exists (shell, config DSLs, a quick clone
;; you haven't set up LSP for).  Registered as the LAST xref backend so it only
;; answers when Eglot (front of the list when attached) and ggtags (the
;; no-server tags fallback) both decline -- it never shadows a real LSP `M-.'.
;; rg is already a hard dependency of this config (consult-ripgrep), so prefer
;; it over plain grep for speed.
(use-package dumb-jump
  :custom (dumb-jump-prefer-searcher 'rg)
  :init
  ;; Append (not prepend) so eglot-xref-backend / ggtags--xref-backend win when
  ;; present; see the xref layering note in init-languages.el.
  (add-hook 'xref-backend-functions #'dumb-jump-xref-activate 90))

;; devdocs: browse offline copies of devdocs.io API documentation inside Emacs
;; -- the equivalent of JetBrains "Quick Documentation" / the VSCode DevDocs
;; extension, but for any of ~500 languages/libraries.  One-off setup per
;; language: `M-x devdocs-install RET python RET' (etc.).  `C-c d' is taken
;; (eldoc-doc-buffer), so docs lookup lives on `C-c k' ("knowledge").
;; Keep the download cache out of the repo root, under no-littering's var/.
(use-package devdocs
  :bind (("C-c k" . devdocs-lookup)        ; look up symbol at point
         ("C-c K" . devdocs-peruse))       ; browse a whole doc set
  :custom
  (devdocs-data-dir (no-littering-expand-var-file-name "devdocs/")))

;; goto-chg: jump to the position of the last buffer edit, then the one before
;; that -- the IDE "navigate to last edit location" (JetBrains `Ctrl+Shift+Bksp',
;; VSCode `Ctrl+K Ctrl+Q').  Re-typing a paragraph above, then wanting to leap
;; back to where you were actually working, is the canonical case.  `C-;' is
;; embark-dwim globally, so this sits on the `C-c'-prefixed slots.
(use-package goto-chg
  :bind (("C-c ;" . goto-last-change)
         ("C-c '" . goto-last-change-reverse)))

;; imenu-list: a persistent side window showing the buffer's imenu tree
;; (functions / classes / headings) -- the VSCode "Outline" pane / JetBrains
;; "Structure" tool window.  Complements `consult-imenu' (M-g i, a transient
;; minibuffer pick): imenu-list is the always-visible map you navigate by, click
;; to jump, and which auto-refreshes as you move.  `*-smart-toggle' shows it if
;; hidden and hides it if it's the focused window, so `C-c O' ("Outline") is a
;; clean one-key toggle.  Pure side window -- TTY-safe.
(use-package imenu-list
  :bind ("C-c O" . imenu-list-smart-toggle)
  :custom
  (imenu-list-focus-after-activation t)
  (imenu-list-auto-resize t))

;; ---------------------------------------------------------------------------
;; Editing / lightweight refactoring
;; ---------------------------------------------------------------------------

;; move-text: drag the current line (or active region) up/down with
;; `M-<up>' / `M-<down>' -- VSCode's `Alt+Up' / `Alt+Down', reindenting as it
;; goes.  `move-text-default-bindings' installs exactly those two global keys;
;; org-mode rebinds `M-<up>'/`M-<down>' buffer-locally (`org-metaup' etc.), so
;; structure-editing in org still wins there -- no conflict in code buffers.
(use-package move-text
  :config (move-text-default-bindings))

;; string-inflection: cycle the identifier at point through naming conventions
;; -- snake_case -> SCREAMING_SNAKE -> CamelCase -> camelCase -> kebab-case.
;; The everyday refactor of pasting an API field in one convention and needing
;; it in another, without a regex.  `*-all-cycle' picks a sensible cycle for any
;; language; `C-c S' keeps the lowercase `C-c s' prefix (symbol-overlay) free.
(use-package string-inflection
  :bind ("C-c S" . string-inflection-all-cycle))

;; ws-butler: trim trailing whitespace, but ONLY on the lines you actually
;; touched this session -- the safe version of "trim on save" that every editor
;; ships.  A blunt `delete-trailing-whitespace' on save rewrites whitespace on
;; untouched lines too, exploding diffs in shared repos; ws-butler scopes the
;; cleanup to your edits.  Complements editorconfig (init-editing.el): where a
;; project's `.editorconfig' says `trim_trailing_whitespace = true', editorconfig
;; sets the policy and ws-butler is the well-behaved enforcer; where there's no
;; `.editorconfig', ws-butler is a conservative default that won't churn diffs.
(use-package ws-butler
  :hook (prog-mode . ws-butler-mode))

;; ---------------------------------------------------------------------------
;; Git collaboration (the GitLens-style conveniences Magit doesn't cover)
;; ---------------------------------------------------------------------------
;; A dedicated `C-c G' prefix ("Git extras") -- kept off Magit's own keys and
;; off the `C-c g' gtags prefix.  Magit (init-git.el) owns the heavy porcelain;
;; these are the three "share / time-travel / blame" gestures a modern IDE puts
;; one keystroke away.

;; git-link: copy (and optionally open) the forge URL for the current line or
;; region -- GitHub/GitLab/Bitbucket/etc. permalink to exactly what point is on.
;; The "right-click -> Copy Link / Open on GitHub" everyone reaches for to share
;; a line in chat or a review.  `git-link-open-in-browser' nil = copy to
;; kill-ring (the common case over SSH/TTY where there's no browser to launch);
;; use `M-x git-link-homepage' for the repo root.
(use-package git-link
  :bind (("C-c G l" . git-link)            ; permalink to line/region
         ("C-c G h" . git-link-homepage))  ; repo homepage URL
  :custom
  (git-link-use-commit t)                  ; pin to the commit SHA, not a branch
  (git-link-open-in-browser nil))          ; copy URL; TTY-friendly default

;; git-timemachine: step through a file's git history revision by revision in
;; place (`p'/`n' = older/newer), without leaving the buffer -- the IDE "Local
;; History" / "Show File History" walker.  Independent of vc.el (switched off in
;; this config, see init-git.el gotcha) -- it shells out to git directly, so it
;; works even with `vc-handled-backends' nil.
(use-package git-timemachine
  :bind ("C-c G t" . git-timemachine))

;; blamer: GitLens-style inline blame -- after a short idle, annotate the
;; current line's end with "author, relative-time, commit summary".  Off by
;; default (a persistent annotation on every line is noisy); `C-c G b' toggles
;; it per buffer for the "who wrote this and why" moment.  `blamer-type'
;; `visual' draws at end-of-line via an overlay after-string -- TTY-safe (the
;; pop-up/child-frame variants are not).
(use-package blamer
  :bind ("C-c G b" . blamer-mode)
  :custom
  (blamer-idle-time 0.5)
  (blamer-min-offset 40)
  (blamer-type 'visual)                    ; end-of-line overlay -- TTY-safe
  (blamer-max-commit-message-length 60))

;; ---------------------------------------------------------------------------
;; Project navigation & workspaces
;; ---------------------------------------------------------------------------

;; dired-sidebar: a persistent file-tree sidebar (the VSCode Explorer / JetBrains
;; Project pane) that REUSES dired -- so all the dired muscle memory and the
;; dired enhancers already configured (diredfl, nerd-icons-dired, dired-subtree,
;; dired-narrow in init-dired.el) carry straight over, instead of bolting on a
;; whole second tree implementation like treemacs.  Works on TTY.  `C-c B'
;; toggles it ("Browser"); it tracks the current file and follows the project
;; root.
(use-package dired-sidebar
  :bind ("C-c B" . dired-sidebar-toggle-sidebar)
  :commands (dired-sidebar-toggle-sidebar)
  :custom
  (dired-sidebar-theme 'nerd-icons)        ; reuse the nerd-icons already set up
  (dired-sidebar-use-term-integration t)
  (dired-sidebar-follow-file-at-point-on-toggle t))

;; tabspaces: turn the built-in tab-bar (init-appearance.el) into project-scoped
;; workspaces -- each tab gets its OWN buffer list, so `C-x b' in the "backend"
;; tab shows only backend buffers, not the 40 buffers from three other projects.
;; This is the VSCode "one window per workspace" / JetBrains "project window"
;; model layered on the tab row already present.  Filtered buffer switching is
;; the whole point, so `tabspaces-use-filtered-buffers-as-default' is on.
;; Commands live under a `C-c W' prefix ("Workspaces"); `C-c w' is dired's
;; copy-path (local to dired buffers), so the capital keeps them clear.
(use-package tabspaces
  :hook (emacs-startup . tabspaces-mode)
  :custom
  (tabspaces-use-filtered-buffers-as-default t)
  (tabspaces-default-tab "Main")
  (tabspaces-remove-to-default t)
  (tabspaces-include-buffers '("*scratch*"))
  :config
  ;; tabspaces ships a command keymap but binds no global prefix; wire it to a
  ;; free one.  Keys inside: C-c W c (create), C-c W s (switch), C-c W o
  ;; (open project as workspace), C-c W k (close workspace), C-c W r (remove
  ;; current buffer from workspace), C-c W b (switch buffer within workspace).
  (when (boundp 'tabspaces-command-map)
    (global-set-key (kbd "C-c W") tabspaces-command-map)))

;; ---------------------------------------------------------------------------
;; In-editor REST client
;; ---------------------------------------------------------------------------

;; restclient: send HTTP requests from a `.http' / `.rest' buffer and view the
;; response inline -- the in-editor twin of the VSCode "REST Client" extension /
;; JetBrains `.http' scratch files / Postman, for the backend-dev loop.  Write a
;; request, `C-c C-c' (restclient's own binding) fires it and pretty-prints the
;; response in a side buffer.  Just an auto-mode association is needed; the mode
;; provides its own keys.
(use-package restclient
  :mode (("\\.http\\'" . restclient-mode)
         ("\\.rest\\'" . restclient-mode)))

(provide 'init-ide)
;;; init-ide.el ends here
