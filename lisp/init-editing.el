;;; init-editing.el --- Editing enhancements -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 7 of the pre-split monolithic init.el (see git log for the move).
;; Quality-of-life editing packages: avy, expand-region, multiple-cursors,
;; rainbow-delimiters, helpful, vundo, hl-todo, pulsar, ace-window, popper,
;; winner (built-in), breadcrumb, jinx, hideshow (built-in).

;;; Code:

;; avy: jump to any visible position with a 2-3 keystroke "decision tree"
;; (the Emacs analogue of tmux-jump / ace-jump).
;;
;; Bindings beyond the obvious three:
;;   M-g s   symbol-aware jump -- uses `find-tag-default' boundaries so
;;           camelCase / snake_case identifiers stay whole, better than
;;           word-1 in code.
;;   M-g r   resume the previous avy with the same input -- press once to
;;           re-trigger after the buffer scrolled, instead of re-typing the
;;           search chars.
;;   M-g 2   two-character input -- candidate set shrinks fast, typically a
;;           one-key jump; complements `avy-goto-char-timer' (which is
;;           variable-length + timeout-driven).
;;
;; `avy-keys' rationale: the default `(a s d f g h j k l)' is left-hand
;; heavy (only `j k l' on the right, no `;'); for multi-key labels,
;; alternating hands is measurably faster than same-hand chains.  Dropping
;; `g'/`h' also removes the worst label/search-char visual collisions
;; (both are high-frequency in English text and code).  The chosen set
;; matches `aw-keys' below, so the home-row picker intuition is shared
;; between window jumps (`M-o') and char jumps (`C-:').
;;
;; `avy-timeout-seconds' 0.3: default 0.5 feels laggy on quick taps; 0.3
;; activates the label overlay promptly without cutting off slower typers
;; -- raise to 0.4 if multi-char input regularly misses.
(use-package avy
  :bind (("C-:"   . avy-goto-char-timer)  ; type a few chars, then pick
         ("M-g w" . avy-goto-word-1)
         ("M-g l" . avy-goto-line)
         ("M-g s" . avy-goto-symbol-1)
         ("M-g r" . avy-resume)
         ("M-g 2" . avy-goto-char-2))
  :custom
  (avy-keys '(?a ?s ?d ?f ?j ?k ?l ?\;))
  (avy-timeout-seconds 0.3)
  :config
  ;; magit-section collapses regions with overlays carrying `invisible t' while
  ;; leaving `buffer-invisibility-spec' at its default value `t'.  Emacs hides
  ;; that text on display; avy's own `avy--visible-p' reads `(eq t spec)' as
  ;; "nothing is hidden" (the opposite of Emacs' actual rule) and emits jump
  ;; labels INSIDE collapsed Magit sections -- the overlay hides the labels,
  ;; the user sees a sparse set and a `M-g s' pick often jumps to an off-screen
  ;; position.  Delegate to the built-in `invisible-p' (C) which honours every
  ;; spec form correctly.  Fixes avy-goto-{char-timer,symbol-1,word-1,char-2}
  ;; inside any magit-section-derived buffer (status / log / diff / ...).
  (advice-add 'avy--visible-p :override
              (lambda (s) (not (invisible-p s)))))

;; ace-link: in Help / Info / EWW / Compilation / Customize / Woman /
;; Helpful buffers, press `o' to avy-jump to the next link / URL / file
;; reference visible in the buffer.  Saves a lot of `n'/`p'/`TAB' walking
;; through helpful pages and helper-info screens.  GNU ELPA, pure elisp,
;; no native deps.  `ace-link-setup-default' wires the `o' binding into
;; every mode it knows about (idempotent -- safe to call once at init).
;;
;; `ace-link-setup-default' deliberately skips three modes we care about:
;;   * magit-mode-map -- `o' is already `magit-submodule' (the submodule
;;     transient), too valuable to silently shadow.
;;   * org-mode-map / markdown-mode-map -- they're text-editing majors, so
;;     a bare `o' would self-insert; ace-link doesn't presume a key.
;; We rebind on `C-c o' in those three modes instead -- `C-c <letter>' is
;; the Elisp-convention space reserved for users, so no major mode should
;; collide.  `ace-link-org' is org-link-syntax-aware; magit and markdown
;; have no specialised function so fall back to `ace-link-addr', which
;; scans the visible buffer for URLs / email / file references.
(use-package ace-link
  :init (ace-link-setup-default)
  :config
  ;; org / markdown / magit keymaps belong to packages that load AFTER this
  ;; module (init-editing loads before init-org / init-git, and markdown-mode
  ;; is deferred).  Binding them eagerly via `:bind (:map org-mode-map ...)'
  ;; therefore errors on a cold-daemon load -- "void variable org-mode-map",
  ;; because the map doesn't exist yet -- and use-package's :catch aborts the
  ;; rest of the block, so ALL three `C-c o' bindings silently fail to apply.
  ;; Defer each binding to its owning package's load instead.
  (with-eval-after-load 'org
    (keymap-set org-mode-map "C-c o" #'ace-link-org))
  (with-eval-after-load 'markdown-mode
    (keymap-set markdown-mode-map "C-c o" #'ace-link-addr))
  (with-eval-after-load 'magit
    (keymap-set magit-mode-map "C-c o" #'ace-link-addr)))

;; avy-zap: replace `M-z' with `avy-zap-to-char-dwim'.  Native
;; `zap-to-char' is forward-only + first-occurrence; avy-zap labels every
;; candidate char in the visible buffer (both directions) so you can pick
;; the Nth or a backward one.  `C-u M-z' still falls back to native.
;;
;; CALIBRATION (added 2026-05-27 after honest re-assessment): this is an
;; insurance binding, ~2-5% of kill operations.  Structural commands cover
;; the rest -- `M-d' / `M-DEL' (word), `C-M-k' (sexp), `C-k' (line),
;; `C-=' + `C-w' (semantic region via expand-region).  `M-z' only wins
;; when ALL three hold: (a) target isn't on a structural boundary,
;; (b) it's a specific char visible on screen, (c) the Nth occurrence or
;; a backward direction matters.  Real hot spots: YAML/JSON `:'
;; delimiters, string-internal partial cuts, zap-to-punctuation past
;; abbreviations (`e.g.', `i.e.', ...).  If a month passes with no `M-z'
;; reach, drop this whole `use-package' block -- `M-z' returns to native
;; `zap-to-char' automatically and nothing else depends on avy-zap.
(use-package avy-zap
  :bind ("M-z" . avy-zap-to-char-dwim))

;; expreg: grow the region along the tree-sitter PARSE TREE (word -> string ->
;; node -> enclosing node -> ...).  Where `expand-region' (next block) grows by
;; Lisp sexps -- accurate in Lisp, only approximate elsewhere -- expreg climbs
;; the real treesit tree, so if-statement / parameter-list / JSX-element
;; boundaries come out exact in every grammar-backed language (Go, Python, TS,
;; Java, ...).  GNU ELPA, maintained.  Orthogonal to combobulate (`C-c o',
;; init-languages.el): combobulate transforms / navigates nodes, expreg only
;; grows the region.
;;
;; `C-=' expand / `C-+' contract (`C-+' = shift-`C-=', the same chord
;; expand-region used for shrink, so muscle memory carries over).
;;
;; First-run note: not in elpa/ on a fresh clone -- `M-x my/package-refresh'
;; then restart once so it installs.
(use-package expreg
  :bind (("C-=" . expreg-expand)
         ("C-+" . expreg-contract)))

;; expand-region: kept as the NO-GRAMMAR fallback for expreg above, moved off
;; `C-=' onto `C-M-='.  css / json have no tree-sitter parser (excluded
;; from `treesit-auto-langs', init-languages.el), so expreg has nothing to climb
;; there; expand-region's sexp/heuristic growth still works.  Grows the region
;; semantically (word -> sexp -> string -> defun -> ...).
(use-package expand-region
  :bind ("C-M-=" . er/expand-region))

;; multiple-cursors: edit many places at once.
(use-package multiple-cursors
  :bind (("C->"         . mc/mark-next-like-this)
         ("C-<"         . mc/mark-previous-like-this)
         ("C-c C-<"     . mc/mark-all-like-this)
         ("C-S-<mouse-1>" . mc/add-cursor-on-click)))

;; rainbow-delimiters: colour-code nested parens by depth -- invaluable in Lisp.
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; helpful: much richer *Help* buffers (source, callers, edebug, ...).
(use-package helpful
  :bind (("C-h f" . helpful-callable)     ; functions + macros
         ("C-h v" . helpful-variable)
         ("C-h k" . helpful-key)
         ("C-h x" . helpful-command)
         ("C-h o" . helpful-symbol)))

;; vundo: draw the undo history as a tree in a transient side buffer and walk
;; it with the arrow keys.  Unlike `undo-tree' it stores nothing on disk and
;; doesn't replace Emacs' native undo machinery -- it just visualises it, so
;; there's no risk of a corrupted on-disk history on huge files.
(use-package vundo
  :bind ("C-x u" . vundo)                ; was `undo' (still on C-/ and C-_)
  :custom
  ;; Default glyph set is ASCII (`+--o-+'); branches in a non-trivial undo
  ;; history blur into a wall of dashes.  `vundo-unicode-symbols' uses
  ;; box-drawing characters (┌─┬─┐ / └─┴─┘) so the tree is actually
  ;; readable.  Nerd-icons font in this config already covers them on TTY.
  (vundo-glyph-alist vundo-unicode-symbols))

;; undo-fu-session: PERSIST the native undo history to disk per file, so undo
;; survives closing and reopening a buffer (and a daemon restart) -- the
;; "undo doesn't reset when I reopen the file" behaviour every modern editor
;; has.  Pairs with vundo above: vundo *visualises* the in-memory native undo
;; tree, undo-fu-session *saves and restores* it.  It hooks plain Emacs undo
;; (no `undo-fu' package required) and works with `undo-tree'-free setups like
;; this one.  no-littering already redirects `undo-fu-session-directory' into
;; `var/', so nothing lands at the repo root.  Compresses sessions when zstd /
;; gzip is available; the incremental on-disk format is bounded by
;; `undo-fu-session-file-limit', so large repos don't accumulate unbounded
;; history files.
(use-package undo-fu-session
  :init (undo-fu-session-global-mode 1))

;; hl-todo: colour-code TODO / FIXME / HACK / NOTE / BUG keywords in comments.
;; (magit-todos in section 9 reuses this keyword set for its repo-wide list.)
(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))

;; pulsar: briefly pulse the current line after a big motion -- an avy jump, a
;; window switch, `consult-line', `recenter-top-bottom', ... -- so your eye
;; re-acquires the cursor.  Pairs naturally with the avy/consult bindings above.
(use-package pulsar
  :init (pulsar-global-mode 1)
  :config
  (dolist (fn '(avy-goto-char-timer
                avy-goto-line
                avy-goto-word-1
                avy-goto-symbol-1
                avy-goto-char-2
                avy-resume))
    (add-to-list 'pulsar-pulse-functions fn))
  ;; consult exposes this hook on every jump (consult-line/imenu/ripgrep ...).
  (add-hook 'consult-after-jump-hook #'pulsar-recenter-center)
  (add-hook 'consult-after-jump-hook #'pulsar-reveal-entry))

;; ace-window: window picker.  With more than two windows, `C-x o' starts
;; rotating through them and you can't predict which lands focus.  ace-window
;; overlays each window with a one-character label -- press the letter, jump
;; there.  Rebind onto `M-o' (whose default `facemenu-keymap' is rarely used)
;; instead of replacing `C-x o' so muscle memory still works in a pinch.
;;
;; `aw-keys' uses home-row letters (asdf-jkl) -- left-hand picks are
;; physically faster than the default `1 2 3 ... 9 0' digit row.  `aw-scope'
;; `frame' limits ace-window to the current frame; the default `global' will
;; try to switch across frames (and even daemon-served TTY frames count),
;; which makes `M-o' unpredictable when more than one frame is alive.
(use-package ace-window
  :bind (("M-o" . ace-window))
  :custom
  (aw-keys '(?a ?s ?d ?f ?j ?k ?l ?\;))
  (aw-scope 'frame))

;; popper: triage transient "popup" buffers (help, compile, vterm, *Warnings*,
;; magit-process, ...) and treat them as a stack you can show/hide with a
;; single key, instead of leaving them squatting in your window layout.
;;
;; Why this matters here: this config opens a lot of side buffers --
;; `helpful', `magit-status' subprocess output, `vterm', `*Async Shell
;; Command*', `compilation-mode' results, flymake diagnostics.  Without
;; popper, each `q' / `C-x 0' / `C-x 1' is a little decision; with popper
;; they all live on one toggle and never permanently fragment the layout.
;;
;; Bindings (chosen so they don't shadow anything in this config):
;;   C-`     popper-toggle         show/hide the latest popup
;;   M-`     popper-cycle          rotate through visible-able popups
;;   C-M-`   popper-toggle-type    mark/unmark the current buffer as a popup
;;
;; `popper-reference-buffers' is a mixed list of regexps (matched against
;; buffer-name) and major-mode symbols.  Add a new popup class by appending
;; either form -- e.g. `"^\\*eat\\*"' if you switch to `eat' later.
;;
;; eldoc-doc-buffer is INTENTIONALLY OMITTED from this list: section 8's
;; `display-buffer-alist' already pins it as a right-side window via
;; `display-buffer-in-side-window'.  Side windows live in their own slot
;; and popper doesn't manage them -- letting both rules touch the same
;; buffer would race on every `C-c d'.
;;
;; `popper-echo-mode' shows a one-line summary of the current popup stack
;; in the echo area after each toggle (e.g. "[*Help*] [*compilation*]" with
;; the active one highlighted) -- pure information, no behaviour change.
(use-package popper
  :bind (("C-`"   . popper-toggle)
         ("M-`"   . popper-cycle)
         ("C-M-`" . popper-toggle-type))
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Warnings\\*"
          "\\*Backtrace\\*"
          "\\*Async Shell Command\\*"
          "Output\\*$"                  ; *Shell Command Output* etc.
          "\\*compilation\\*"
          compilation-mode
          help-mode                     ; *Help*
          helpful-mode                  ; helpful's own buffers
          "^\\*vterm\\*"
          vterm-mode
          "^\\*eshell.*\\*$" eshell-mode
          "^\\*shell.*\\*$"  shell-mode
          "^\\*magit-process"           ; transient subprocess output
          flymake-diagnostics-buffer-mode))
  (popper-mode 1)
  (popper-echo-mode 1))

;; winner (built-in): undo / redo window-layout changes.  `C-c <left>'
;; restores the previous window configuration; `C-c <right>' moves forward
;; again.  Concrete saves: you `C-x 1' a window expecting to keep the other
;; visible -- `C-c <left>' brings it back.  Magit / Org / Help often
;; re-arrange windows aggressively; winner is the universal undo for that.
;; Pairs with ace-window (jump to a window) and popper (toggle popups)
;; above as the third leg of window management: pick / hide / undo.
(use-package winner
  :ensure nil
  :init (winner-mode 1))

;; breadcrumb: header-line shows `project / file / class / function' path of
;; point, powered by `project.el', `imenu', and (when active) Eglot's symbol
;; information.  Concrete use: deep inside a 500-line file, the header tells
;; you which function / class you're inside without scrolling up; the
;; project segment makes it obvious which repo when several are open.
;; Pairs with combobulate's node navigation (§8) -- as you climb the tree,
;; the breadcrumb updates to reflect the enclosing scope.
;;
;; Header-line wasn't shown before this package; `breadcrumb-mode' turns it
;; on globally and steals one line per window.  Toggle off in a specific
;; buffer with `M-x breadcrumb-local-mode' or globally with the same
;; command name (the global mode is a toggle).
;;
;; Source: GNU ELPA (`gnu' archive, already enabled in section 1).  Same
;; author as `eglot-booster' (§8) and `vertico-posframe' / `indent-bars'.
(use-package breadcrumb
  :init (breadcrumb-mode 1))

;; jinx: spell checker backed by `enchant-2' (C binary; orders of magnitude
;; faster than the elisp-only `flyspell').  Active in every text-mode buffer
;; (org, markdown, gfm, fundamental text, ...) via `global-jinx-mode'.
;; Misspellings underlined inline as you type; `M-$' (was `ispell-word')
;; opens a minibuffer correction menu -- vertico + orderless deliver the
;; suggestion list with the same UI as the rest of section 4.  `C-M-$'
;; switches between configured languages mid-buffer.
;;
;; Requires `enchant-2' on the system (`apt install enchant-2
;; libenchant-2-dev'); the elisp side compiles a small C module on first
;; load (~2 s, one-off).  Without enchant, jinx fails loudly at startup
;; rather than silently no-op-ing.
;;
;; `jinx-languages' default is read from the locale; pin to `"en_US"' so
;; behaviour is consistent across machines.  Enchant doesn't ship Chinese
;; dictionaries by default, so no point listing `zh_TW' here -- mixed-
;; language buffers can opt-in per-buffer with `C-M-$' if you ever wire a
;; CJK backend (Hunspell + zh dict, etc.).
(use-package jinx
  :hook (emacs-startup . global-jinx-mode)
  :bind (("M-$"   . jinx-correct)
         ("C-M-$" . jinx-languages))
  :custom (jinx-languages "en_US"))

;; editorconfig (built-in since Emacs 30 -- hence `:ensure nil', or
;; use-package-always-ensure would pull a redundant MELPA copy that shadows
;; the bundled one).  On `find-file' it walks up from the visited file for a
;; `.editorconfig', then sets the buffer-local editing-time policy that
;; project ships: `indent_style'/`indent_size'/`tab_width' (-> the per-mode
;; offset var + `indent-tabs-mode'), `trim_trailing_whitespace',
;; `insert_final_newline', `charset', `max_line_length' (-> `fill-column').
;; This is the cross-IDE indentation handshake every collaborator's editor
;; already honours -- without it an Emacs save can re-tab a 2-space repo.
;;
;; How this divides labour with apheleia (init-languages.el): apheleia runs
;; an *external* formatter on save and only fires for files whose language
;; has one registered.  editorconfig sets the *interactive* buffer-local
;; vars, so manual `TAB' / `indent-region' / newline-electric-indent obey
;; project policy too -- and it covers the long tail of files apheleia has
;; no formatter for (Makefiles, .conf, shell, YAML, prose).  They don't
;; fight: a formatter, when present, still has the final say on save.
;; No display path -- pure buffer-local logic, so TTY-irrelevant.
(use-package editorconfig
  :ensure nil
  :hook (emacs-startup . editorconfig-mode))

;; hideshow (built-in): code folding.  `C-c @' is hideshow's own default
;; prefix, but its native sub-keys are unmemorable multi-modifier chords
;; (`C-c @ C-M-h', `C-c @ C-c', ...).  Rebind the whole prefix to a
;; `transient' "cockpit" instead -- one entry point, every fold action
;; visible and labelled, and the menu stays open so you can navigate +
;; fold repeatedly before quitting with `q'.
;;
;; Why transient and not which-key / hydra:
;;   * which-key (init-defaults.el) only *displays* whatever bindings
;;     exist -- it can't fix the bad native chords and closes after one
;;     command.  It still helps: `C-c' then a pause shows `@' as the
;;     route into this menu.
;;   * hydra would be a brand-new MELPA dependency.
;;   * transient is already installed (gptel / magit pull it in) and this
;;     config already drives a menu this way -- `aidermacs-transient-menu'
;;     on `C-c a' (init-aidermacs.el).  Zero new dependency.
;;
;; `hs-minor-mode' is auto-enabled in every `prog-mode' buffer, so `C-c @'
;; is always live in code; it is bound in `hs-minor-mode-map' (not global)
;; to keep it hideshow-specific.  hideshow folds by sexp/braces -- great
;; for C-like / Lisp / JSON, weaker for indentation-structured languages
;; like Python (a hideshow limitation, not this config's).
(use-package hideshow
  :ensure nil
  :hook (prog-mode . hs-minor-mode)
  :bind (:map hs-minor-mode-map
              ("C-c @" . fenrir/hideshow-menu))   ; shadows the native prefix
  :config
  ;; transient is already on `load-path' (an elpa/ package, pulled in by
  ;; gptel / magit); require it here so the menu is defined the first time
  ;; a prog buffer loads hideshow -- no startup cost.
  (require 'transient)
  (defvar fenrir/hideshow-menu--show-nav nil
    "When non-nil, `fenrir/hideshow-menu' also draws its Navigation group.
The navigation keys (n/p/C-v/M-v/C-s) stay bound and usable either way --
this only controls whether the popup lists them.  Toggled with `?'.")
  (defun fenrir/hideshow-menu--toggle-nav ()
    "Toggle whether `fenrir/hideshow-menu' lists its navigation keys."
    (interactive)
    (setq fenrir/hideshow-menu--show-nav
          (not fenrir/hideshow-menu--show-nav)))
  (transient-define-prefix fenrir/hideshow-menu ()
    "Code folding (HideShow) cockpit -- stays open until `q'.
The navigation keys (`n'/`p'/`C-v'/`M-v'/`C-s') are bound and usable but
hidden from the popup to keep it uncluttered; press `?' to list (or
re-hide) them."
    [["Block at point"
      ("t" "Toggle"     hs-toggle-hiding :transient t)
      ("h" "Hide"       hs-hide-block    :transient t)
      ("s" "Show"       hs-show-block    :transient t)]
     ["Whole buffer"
      ("H" "Hide all"   hs-hide-all      :transient t)
      ("S" "Show all"   hs-show-all      :transient t)
      ("l" "Hide level" hs-hide-level    :transient t)]
     ["Menu"
      ("?" fenrir/hideshow-menu--toggle-nav
       :description (lambda ()
                      (if fenrir/hideshow-menu--show-nav
                          "Hide navigation keys"
                        "Show navigation keys (n/p/C-v/M-v/C-s)"))
       :transient t)
      ("q" "Quit" transient-quit-one)]]
    ;; Navigation is a SEPARATE top-level group, NOT a column nested in the
    ;; row above.  transient only consults `:hide' for top-level groups (see
    ;; `transient--insert-groups'); the `transient-columns' renderer draws its
    ;; child columns without checking their `:hide' slot, so a `:hide' on a
    ;; nested column is silently ignored.  As its own top-level group the
    ;; predicate is honoured: hidden by default, revealed by `?'.  `:hide' is
    ;; display-only -- the suffixes stay bound either way, so `n'/`p'/`C-v'/
    ;; `M-v'/`C-s' work whether or not they are listed.  `C-s' uses
    ;; `consult-line' (the config's own `C-s', init-completion.el) not
    ;; isearch: isearch's `isearch-mode-map' would fight the transient
    ;; keymap, whereas consult-line reads its pattern in the minibuffer.
    ["Navigation"
     :hide (lambda () (not fenrir/hideshow-menu--show-nav))
     ("n"   "Next line" next-line           :transient t)
     ("p"   "Prev line" previous-line       :transient t)
     ("C-v" "Page down" scroll-up-command   :transient t)
     ("M-v" "Page up"   scroll-down-command :transient t)
     ("C-s" "Search"    consult-line        :transient t)]))

(provide 'init-editing)
;;; init-editing.el ends here
