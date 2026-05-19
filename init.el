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

;; ---------------------------------------------------------------------------
;; 2. Better built-in defaults (no external packages)
;; ---------------------------------------------------------------------------

(use-package emacs
  :ensure nil
  :init
  ;; --- chrome ---
  ;; menu/tool/scroll bars are suppressed in early-init.el via
  ;; `default-frame-alist' so the first frame is painted without them.  Only
  ;; the startup-screen toggles belong here.
  (setq inhibit-startup-screen t)        ; straight to *scratch*
  (setq initial-scratch-message nil)
  ;; --- editing ---
  (setq-default indent-tabs-mode nil)    ; spaces, not tabs
  (delete-selection-mode 1)              ; typing replaces the active region
  (electric-pair-mode 1)                 ; auto-insert matching brackets/quotes
  (global-so-long-mode 1)                ; survive opening huge minified files
  ;; --- files / backups ---
  (setq make-backup-files nil)           ; no foo~ litter next to the file
  (setq auto-save-default t)             ; keep #foo# autosaves (recovery)
  (setq create-lockfiles nil)            ; no .#foo lockfiles
  (global-auto-revert-mode 1)            ; reload buffers when files change on disk
  (setq global-auto-revert-non-file-buffers t) ; ...including Dired
  ;; --- niceties ---
  (column-number-mode 1)                 ; show column in the modeline
  (setq use-short-answers t)             ; y/n instead of yes/no
  (setq ring-bell-function 'ignore)      ; no audible bell
  (setq sentence-end-double-space nil)
  ;; repeat-mode (built-in, Emacs 28+): after a prefixed command like `C-x o',
  ;; pressing the LAST key (`o', `o', `o') keeps invoking it without re-typing
  ;; the `C-x' prefix.  Also works for `C-x ^' (enlarge-window) etc.  Pure
  ;; ergonomics win, no setup beyond turning it on.
  (repeat-mode 1)
  ;; Put `M-x customize' output in its own file rather than appending to this
  ;; one.  (The block at the bottom of this file pre-dates this and is kept
  ;; for compatibility; new customisations go to custom.el.)
  (setq custom-file (expand-file-name "custom.el" user-emacs-directory))
  (when (file-exists-p custom-file) (load custom-file)))

;; Terminal clipboard bridge: in a TTY frame Emacs' default cut path is GUI-only,
;; so `M-w' fills the internal kill-ring but nothing outside Emacs sees it.
;; Emit OSC 52 on every cut; tmux's `set-clipboard on' in
;; [.tmux.conf](../.tmux.conf) relays the escape to the outer terminal, which
;; writes the real system clipboard.  Works across SSH; no xclip/wl-copy needed.
(unless (display-graphic-p)
  (defun fenrir/osc52-copy (text)
    (let ((b64 (base64-encode-string (encode-coding-string text 'utf-8) t)))
      (send-string-to-terminal (format "\e]52;c;%s\a" b64))))
  (setq interprogram-cut-function #'fenrir/osc52-copy))

;; which-key: after a prefix key (C-x, C-c, ...) pops up a panel listing the
;; follow-up keys.  Built into Emacs 30 -- hence :ensure nil.
(use-package which-key
  :ensure nil
  :init (which-key-mode 1)
  :custom (which-key-idle-delay 0.5))

;; ibuffer: replace the default `switch-to-buffer' on `C-x b' with ibuffer
;; (grouping, marking, batch operations).  `C-x C-b' is avoided because tmux'
;; default prefix is `C-b' and swallows the second keystroke in a TTY frame.
(use-package ibuffer
  :ensure nil
  :bind ("C-x b" . ibuffer))

;; ---------------------------------------------------------------------------
;; 3. system-packages -- thin wrapper over apt/brew/pacman/...
;; ---------------------------------------------------------------------------
;; The `:ensure-system-package' use-package keyword was removed from MELPA, so
;; call `system-packages-ensure' directly when you need an OS package present.

(use-package system-packages
  :defer t                               ; only used via M-x system-packages-...
  :custom (system-packages-use-sudo t))

;; ---------------------------------------------------------------------------
;; 4. Minibuffer / completion UI -- the "Vertico ecosystem"
;; ---------------------------------------------------------------------------
;; Five small, orthogonal packages that together replace ido/ivy/helm:
;;   vertico    -- vertical candidate list in the minibuffer
;;   orderless  -- space-separated, any-order fuzzy matching
;;   marginalia -- annotations (docstrings, file sizes, ...) beside candidates
;;   consult    -- richer commands: buffer switch, line search, project grep
;;   embark     -- a "context menu" you can invoke on the current candidate

(use-package vertico
  :init (vertico-mode 1)
  :custom
  (vertico-cycle t))                     ; wrap around at top/bottom

;; vertico-directory: an extension that ships INSIDE the vertico package -- so
;; `:ensure nil'.  Makes RET/DEL operate on whole path components when you're
;; editing a file name in the minibuffer (RET descends into the dir under
;; point; DEL deletes back to the previous `/').
(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
              ("RET"   . vertico-directory-enter)
              ("DEL"   . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  ;; Collapse the "//" / "~/" shadow when you type an absolute path mid-prompt.
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; Persist minibuffer history; also lets Vertico put recent picks first.
;; `savehist-additional-variables' bolts on the kill-ring and the two search
;; rings -- so M-y / C-s history survive a restart, not just M-x history.
(use-package savehist
  :ensure nil
  :init (savehist-mode 1)
  :custom
  (savehist-additional-variables '(kill-ring search-ring regexp-search-ring)))

;; recentf (built-in): tracks recently-opened files.  Once enabled,
;; `consult-buffer' (C-x b) gains a "Recent files" virtual source -- so the
;; same key that switches buffers also re-opens recent files, no separate
;; "recentf-open" command needed.  no-littering already redirected the
;; recentf save file out of `~/.emacs.d/' root, so no path tweak required.
(use-package recentf
  :ensure nil
  :init (recentf-mode 1)
  :custom
  (recentf-max-saved-items 200)
  (recentf-max-menu-items 25))

;; saveplace (built-in): remembers point position per file across sessions.
;; Reopen a file and the cursor lands where you left off -- no need to
;; manually `C-s' for your spot.  Pairs naturally with `recentf' above
;; (recent files come back via `consult-buffer'; opening them lands at the
;; right line).  no-littering already redirects the on-disk state file
;; under `var/places/'.
(use-package saveplace
  :ensure nil
  :init (save-place-mode 1))

(use-package orderless
  :custom
  ;; Use orderless for ordinary completion; keep the built-in file-name style
  ;; so partial path components (e.g. "/u/s/b" -> /usr/share/bin) still work.
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package consult
  :bind (;; C-x bindings -- `C-x b' is reserved for ibuffer (see section 2),
         ;; so the consult fuzzy switcher lives on `C-x B' (shift) instead.
         ("C-x B"   . consult-buffer)         ; switch buffer (with previews)
         ("C-x 4 b" . consult-buffer-other-window)
         ("C-x p b" . consult-project-buffer) ; project-scoped buffer switch
         ;; search
         ("M-y"     . consult-yank-pop)       ; browse the kill-ring
         ("C-s"     . consult-line)           ; search lines in this buffer
         ("M-g g"   . consult-goto-line)
         ("M-g i"   . consult-imenu)          ; jump to a definition in this file
         ("M-s r"   . consult-ripgrep)        ; grep across the project
         ("M-s f"   . consult-find))          ; find files by name
  :custom
  ;; Let `consult-line' etc. drive the live preview at this key:
  (consult-narrow-key "<")
  :init
  ;; Route in-buffer completion (`M-TAB' / `C-M-i' / `completion-at-point')
  ;; to the minibuffer via Vertico, instead of corfu's at-point popup.
  ;; See the section-5 header comment for the rationale.  `:init' (rather
  ;; than `:config') so the override is in place before any buffer's first
  ;; completion call, even if consult itself loads lazily afterwards.
  (setq completion-in-region-function #'consult-completion-in-region))

(use-package embark
  :bind (("C-." . embark-act)            ; act on the thing at point / candidate
         ("C-;" . embark-dwim)           ; "do what I mean" -- default action
         ("C-h B" . embark-bindings)))   ; like `describe-bindings' via completing-read

;; Glue: when you `embark-act' inside a consult command, show the export buffer
;; using consult's nicer formatting.
(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; wgrep: make grep / ripgrep result buffers editable, then commit the edits
;; back to every file at once.  The payoff with the setup above: run
;; `consult-ripgrep' (M-s r), `embark-export' (C-. then E) the matches into a
;; grep buffer, `C-c C-p' to make it writable, edit freely, `C-c C-c' to save
;; -- a project-wide search-and-replace with ordinary undo on each file.
(use-package wgrep
  :defer t                               ; loads when you C-c C-p in a grep buffer
  :custom (wgrep-auto-save-buffer t))    ; write edited files out immediately

;; ---------------------------------------------------------------------------
;; 5. In-buffer code completion -- Corfu + Cape
;; ---------------------------------------------------------------------------
;; Corfu is the lightweight `company' alternative: a small popup at point.
;; Cape provides extra completion-at-point backends to feed it.

;; In-buffer completion frontend: Vertico minibuffer, NOT Corfu popup.
;;
;; `completion-in-region-function' is the single switch that decides which UI
;; handles in-buffer completion (`M-TAB' / `C-M-i' / `completion-at-point').
;; Below we route it to `consult-completion-in-region' (set on the consult
;; block in section 4), which renders the candidates in the minibuffer with
;; the same Vertico + orderless + marginalia stack used by `C-x C-f' / `M-x'.
;;
;; `global-corfu-mode' is intentionally NOT enabled here -- if it were, corfu
;; would set its own buffer-local `completion-in-region-function' and override
;; the consult routing.  The package stays installed (via `:defer t') so a
;; future switch back to the popup workflow is a one-line edit: add
;; `:init (global-corfu-mode 1)' here and set `corfu-auto t'.
;;
;; Trade-off vs. corfu's popup: no auto-popup as you type, the trigger is now
;; manual (M-TAB / C-M-i); but the candidate UI is unified with the rest of
;; the minibuffer ecosystem (orderless multi-token search, marginalia
;; annotations, embark actions on candidates).
(use-package corfu
  :defer t                              ; installed but not auto-loaded
  :custom
  (corfu-auto nil)
  (corfu-auto-delay 0.2)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  (corfu-quit-no-match 'separator))

;; corfu-popupinfo: in-package extension that shows the selected candidate's
;; docstring / signature beside Corfu's popup.  CURRENTLY DORMANT -- only fires
;; when a Corfu popup is visible, and `global-corfu-mode' is off (see section-5
;; header).  Kept installed so flipping back to the popup workflow is one line.
(use-package corfu-popupinfo
  :ensure nil
  :after corfu
  :init (corfu-popupinfo-mode 1)
  :custom (corfu-popupinfo-delay '(0.5 . 0.2)))

;; corfu-terminal: swaps Corfu's child-frame popup for a popon overlay in TTY
;; frames.  CURRENTLY DORMANT alongside Corfu itself (see section-5 header) --
;; with no popup, there's nothing to re-render.  Kept installed so flipping
;; back to the popup workflow doesn't also require re-adding a package.
(use-package corfu-terminal
  :after corfu
  :config (corfu-terminal-mode +1))


(use-package cape
  :init
  ;; Generic backends useful in every buffer: dabbrev (words in open buffers),
  ;; file paths, and elisp symbols.  Eglot adds language-aware ones on top.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block))

;; ---------------------------------------------------------------------------
;; 6. Snippets -- YASnippet
;; ---------------------------------------------------------------------------

(use-package yasnippet
  :init (yas-global-mode 1))

;; A large collection of ready-made snippets for many major modes.
(use-package yasnippet-snippets
  :after yasnippet)

;; ---------------------------------------------------------------------------
;; 7. Editing enhancements
;; ---------------------------------------------------------------------------

;; avy: jump to any visible position with a 2-3 keystroke "decision tree"
;; (the Emacs analogue of tmux-jump / ace-jump).
(use-package avy
  :bind (("C-:"   . avy-goto-char-timer)  ; type a few chars, then pick
         ("M-g w" . avy-goto-word-1)
         ("M-g l" . avy-goto-line)))

;; expand-region: C-= grows the region semantically (word -> sexp -> string ->
;; defun -> ...); shift-C-= shrinks it again.
(use-package expand-region
  :bind ("C-=" . er/expand-region))

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
  :bind ("C-x u" . vundo))               ; was `undo' (still on C-/ and C-_)

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
  (dolist (fn '(avy-goto-char-timer avy-goto-line avy-goto-word-1))
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

;; ---------------------------------------------------------------------------
;; 8. Project, LSP & languages
;; ---------------------------------------------------------------------------

;; project.el (built-in): project-aware file/buffer/command commands under C-x p.
;; ~/ itself is a git repo (the dotfiles tree).  Two interacting problems:
;;   1. project.el would otherwise treat all of $HOME as one giant project and
;;      project-find-file would walk the whole home directory.  Fixed by the
;;      :around advice on `project-try-vc' that returns nil when the root is $HOME.
;;   2. Sub-directories inside the dotfiles repo that don't have their own .git
;;      (e.g. ~/.emacs.d/, ~/.config/<foo>/) would also be killed by (1) because
;;      `vc-find-root' walks up to ~/.git.  Fixed by `project-vc-extra-root-markers':
;;      if any of those marker files exists in a closer ancestor, that ancestor
;;      becomes the project root, the advice sees a non-$HOME root, and lets it
;;      through.  Drop an empty `.project' file in any dir you want treated as
;;      a project (or rely on the language-native markers below).
(use-package project
  :ensure nil
  :custom
  (project-vc-extra-root-markers
   '(".project"          ; explicit opt-in marker for arbitrary directories
     "Cargo.toml"        ; Rust
     "go.mod"            ; Go
     "pyproject.toml"    ; Python (PEP 518)
     "CLAUDE.md"
     "package.json"      ; Node
     "Makefile"))        ; generic
  :config
  (defun my-project-ignore-home (orig-fun dir)
    "If `project-try-vc' would return $HOME as the project root, ignore it."
    (let ((proj (funcall orig-fun dir)))
      (if (and proj
               (string= (expand-file-name (project-root proj))
                        (expand-file-name "~/")))
          nil
        proj)))
  (advice-add 'project-try-vc :around #'my-project-ignore-home))

;; `project-try-vc' caches its search result on each `dir' via `vc-file-setprop'
;; (see project.el's own FIXME at the top of the defun).  That means changes to
;; `project-vc-extra-root-markers' don't retroactively re-detect already-visited
;; directories -- a daemon that first saw ~/code/foo/ before CLAUDE.md was in
;; the markers list keeps returning the old (vc Git "~/") answer forever.  This
;; helper replaces the whole obarray so the next access recomputes from scratch.
;; Emacs 30 made obarray a distinct type (no longer a vector), so we go through
;; `obarray-make' rather than `fillarray'.
(defun fenrir/project-reset-cache ()
  "Wipe all `vc-file-setprop' caches.  Use after editing
`project-vc-extra-root-markers' or any time project root detection
seems stuck on a stale answer."
  (interactive)
  (setq vc-file-prop-obarray (obarray-make 17))
  (message "vc-file-prop-obarray cleared"))

;; envrc: direnv integration -- when you enter a buffer whose file lives under
;; a directory with an `.envrc', envrc runs `direnv export json' and applies
;; the resulting env vars BUFFER-LOCALLY (sets `process-environment' and
;; `exec-path' just in that buffer).  Two concrete wins on this setup:
;;   * Eglot picks the right server binary per project -- e.g. a Go monorepo
;;     pinning `PATH=./bin:$PATH' in its .envrc gets that repo's gopls, not
;;     the global one harvested by `exec-path-from-shell' at startup.
;;   * Node projects using `nvm' / `volta' / `asdf' switch versions per
;;     project, so apheleia/prettier and `M-x compile' run the right tool.
;;
;; Why buffer-local matters: `exec-path-from-shell' (section 1) is a one-shot
;; global harvest at daemon launch -- great for "Emacs needs to see my login
;; PATH", useless for "this project needs a different toolchain than that
;; one".  envrc is the per-project complement, not a replacement.
;;
;; Loaded as a global mode (only enables in buffers under a direnv-allowed
;; dir, so it's free in $HOME or unrelated buffers).  Requires the `direnv'
;; binary on PATH (`apt install direnv'); without it the mode silently
;; no-ops.  Per-project setup: drop an `.envrc', then `direnv allow' once.
(use-package envrc
  :hook (after-init . envrc-global-mode))

;; Eglot (built-in since Emacs 29): a small, zero-config LSP client.  It
;; auto-starts when you open a file in a supported mode AND a language server
;; binary is on PATH (gopls, pyright, rust-analyzer, typescript-language-server,
;; clangd, ...).  Reach for `lsp-mode' only if you need its heavier extras.
;;
;; Node.js / frontend server install (one-time, npm globals):
;;     npm i -g typescript typescript-language-server     ; JS / TS / TSX
;;     npm i -g vscode-langservers-extracted              ; HTML / CSS / JSON / ESLint
;;     npm i -g prettier                                  ; used by apheleia, see below
;; `vscode-langservers-extracted' ships four binaries Eglot's default
;; `eglot-server-programs' already knows about:
;;     vscode-html-language-server  vscode-css-language-server
;;     vscode-json-language-server  vscode-eslint-language-server
;; The ESLint one is NOT auto-attached -- Eglot binds one server per major
;; mode and TypeScript already wins.  ESLint runs via `flymake-eslint' below
;; (no LSP -- it execs `node_modules/.bin/eslint' directly), which co-exists
;; cleanly with the running tsserver.
;;
;; TSX / JSX note: `.tsx' files open in `tsx-ts-mode' (not `typescript-ts-mode'),
;; courtesy of `treesit-auto'.  `.jsx' likewise reuses the TSX parser.  Both
;; are covered by the `tsx-ts-mode' hook below.
(use-package eglot
  :ensure nil
  :hook ((python-ts-mode . eglot-ensure)
         (go-ts-mode      . eglot-ensure)
         (rust-ts-mode    . eglot-ensure)
         (js-ts-mode      . eglot-ensure)
         (typescript-ts-mode . eglot-ensure)
         (tsx-ts-mode     . eglot-ensure)   ; React .tsx / .jsx
         ;; CSS / HTML / JSON intentionally use the *built-in* modes (not the
         ;; *-ts-mode tree-sitter variants).  These grammars are simple enough
         ;; that the regex-based built-ins are accurate, and skipping them
         ;; sidesteps the tree-sitter ABI treadmill (Emacs 30 caps at ABI 14,
         ;; tree-sitter-css v0.25+ is ABI 15 -> warnings).  Inside .vue files
         ;; the <style> / <template> blocks are handled by Volar anyway.
         (css-mode        . eglot-ensure)
         (html-mode       . eglot-ensure)   ; covers mhtml-mode (derived)
         (js-json-mode    . eglot-ensure)   ; built-in JSON mode
         (c-ts-mode       . eglot-ensure)
         (c++-ts-mode     . eglot-ensure))
  :custom
  (eglot-autoshutdown t)                 ; kill the server when its last buffer closes
  (eglot-events-buffer-size 0)           ; don't log the (huge) JSON-RPC traffic
  ;; Block up to 1s for the server's initial handshake before returning
  ;; control; longer than that, finish async.  Default `nil' means "wait
  ;; forever synchronously" which freezes the UI while gopls indexes a big
  ;; monorepo.
  (eglot-sync-connect 1)
  ;; Total timeout for the TCP/stdio handshake (default 30s is fine; spelled
  ;; out so the value is visible next to its siblings).
  (eglot-connect-timeout 30)
  ;; Let `xref-find-definitions' (M-.) follow into vendored / library files
  ;; the LSP knows about, even when those files have no Eglot session of
  ;; their own.  Default `nil' silently stops at the project boundary.
  (eglot-extend-to-xref t))

;; eglot-booster: speed up Eglot by routing the LSP server's stdio through
;; `emacs-lsp-booster' (Rust binary, blahgeek/emacs-lsp-booster v0.2.1).
;; Two mechanisms:
;;   1. Threaded I/O on the booster side -- Emacs no longer blocks the UI
;;      waiting for a slow server response.  Win regardless of message size.
;;   2. JSON -> Elisp bytecode pre-parse -- `read' on bytecode beats
;;      `json-parse-string' on Emacs 29.  Win SHRINKS on Emacs 30 (native
;;      parser already fast); still meaningful for large payloads:
;;      `consult-eglot-symbols' workspace/symbol responses, gopls hovers on
;;      heavy structs, rust-analyzer full type info, workspace diagnostics.
;;      Tiny per-keystroke completion deltas may go marginally SLOWER -- if
;;      that's perceptible, add `--disable-bytecode' via
;;      `eglot-booster-no-remote-boost' / `eglot-booster-program-args' to
;;      keep the threaded-I/O win without the bytecode trick.
;;
;; Trust posture (decided 2026-05-18): built from source via
;; `cargo install --locked --version 0.2.1 emacs-lsp-booster' rather than
;; downloading the pre-built release binary.  `--locked' pins every
;; transitive dep to the upstream Cargo.lock SHA, eliminating
;; compiler-supply-chain ambiguity in the prebuilt zip.  Trade: 3-5 min
;; compile on first install.  Binary lands at ~/.cargo/bin/, on PATH via
;; rustup.
;;
;; Compatibility: monkey-patches `eglot--connect'.  Built-in Eglot evolves
;; with Emacs releases; an Emacs upgrade may break the patch (historically
;; fixed quickly upstream).  If broken: `M-x eglot-booster-mode' to disable
;; at runtime, no permanent harm.  All LSP servers this config talks to
;; (pyright, gopls, rust-analyzer, typescript-language-server, vscode-*,
;; clangd) use stdio JSON-RPC and are compatible.
;;
;; Source GitHub-only, installed via Emacs 30's `:vc' keyword (same pattern
;; as combobulate above).  Update later: `M-x package-vc-upgrade RET
;; eglot-booster RET'.
(use-package eglot-booster
  :vc (:url "https://github.com/jdtsmith/eglot-booster" :rev :newest)
  :after eglot
  :config (eglot-booster-mode 1))

;; consult-eglot: project-wide LSP symbol search via `workspace/symbol'.
;;
;; Fills a gap in the consult bindings (section 4): `consult-imenu' is THIS
;; file only, `consult-imenu-multi' is the currently-open buffers of the
;; same major mode -- neither sees a symbol in a file you haven't visited
;; yet.  `consult-eglot-symbols' asks the running language server for every
;; symbol in the project's index, so you can jump to `NewFooBar' in a Go
;; monorepo without opening its file first.  Same vertico + orderless +
;; marginalia UI as the rest of the minibuffer stack.
;;
;; Bound on `M-g s' ("goto symbol") only inside `eglot-mode-map' -- the key
;; is meaningless in non-LSP buffers, and scoping the binding avoids
;; shadowing whatever a future major mode might want on `M-g s'.  Needs an
;; Eglot session live in the current buffer; in a buffer without one, the
;; command errors out clearly rather than silently returning nothing.
(use-package consult-eglot
  :after (consult eglot)
  :bind (:map eglot-mode-map
              ("M-g s" . consult-eglot-symbols)))

;; vue-mode: syntax highlighting for .vue files only.  Eglot is intentionally
;; NOT hooked here -- Vue's LSP options (Volar 3 in "Hybrid Mode") are
;; sluggish on cold start and the per-request jsonrpc timeouts get noisy in
;; any project bigger than a toy.  Tried it (commit acdf8d6, reverted in
;; favour of this simpler setup); reach for `M-s r' (consult-ripgrep, bound
;; in section 4) for cross-file searches in Vue projects instead -- it
;; catches references uniformly across .vue / .ts / .md, which any LSP
;; scoped to one filetype never can.
;;
;; If you want Volar back: see `git show acdf8d6' for the full wiring
;; (vue-language-server + @vue/typescript-plugin tsserver plugin, tsdk
;; pointer, etc.).  The npm globals (`@vue/language-server',
;; `@vue/typescript-plugin') are left installed -- harmless when unused.
;;
;; `vue-modes' override: the upstream default points `<script lang="ts">' at
;; `typescript-mode' (the legacy SMIE package, not installed here) and bare
;; `<script>' at `js-mode' (regex-based, no ES2020+).  Without this override
;; TS script blocks fall back to fundamental-mode and look unhighlighted.
;; Retarget to the tree-sitter modes the rest of the config already uses --
;; grammars live in `~/.emacs.d/tree-sitter' (see commit 8968757).
(use-package vue-mode
  :mode "\\.vue\\'"
  :custom
  (vue-modes
   '((:type template :name nil   :mode vue-html-mode)
     (:type template :name html  :mode vue-html-mode)
     (:type script   :name nil   :mode js-ts-mode)
     (:type script   :name js    :mode js-ts-mode)
     (:type script   :name es6   :mode js-ts-mode)
     (:type script   :name babel :mode js-ts-mode)
     (:type script   :name ts          :mode typescript-ts-mode)
     (:type script   :name typescript  :mode typescript-ts-mode)
     (:type script   :name tsx         :mode tsx-ts-mode)
     (:type style    :name nil    :mode css-mode)
     (:type style    :name css    :mode css-mode)
     (:type style    :name scss   :mode css-mode)
     (:type style    :name postcss :mode css-mode)
     (:type style    :name sass   :mode ssass-mode)
     (:type i18n     :name nil    :mode js-json-mode)
     (:type i18n     :name json   :mode js-json-mode))))

;; eldoc on TTY: echo area is the default display path (single line, brief,
;; gets clobbered by Corfu / other `message' callers but cheap and unobtrusive).
;; For longer signatures or godoc-on-hover, summon `M-x eldoc-doc-buffer'
;; on demand -- the `display-buffer-alist' entry below docks it as a 60-col
;; side window on the right.  No auto-pop; the side window only appears
;; when you ask for it.
;;
;; Why not eldoc-box: child frames are GUI-only.  In TTY frames (our default,
;; Emacs runs in tmux) eldoc-box silently no-ops AND bypasses the echo area
;; fallback, so the user sees nothing at all.
(setq eldoc-echo-area-use-multiline-p t)

;; Eldoc names its dedicated doc buffer " *eldoc for SYMBOL*" with a leading
;; space (Emacs' "hidden internal buffer" convention).  Once `eldoc-doc-buffer'
;; is called interactively the buffer is renamed to drop the leading space.
;; Match both forms.
(add-to-list 'display-buffer-alist
             `(,(rx bos (? " ") "*eldoc")
               (display-buffer-in-side-window)
               (side . right)
               (window-width . 60)
               (slot . 1)
               (window-parameters . ((no-other-window . t)))))

;; On-demand summon: cursor anywhere with eldoc content, hit `C-c d' to dock
;; the full doc in the side window.  No prefix arg needed; `eldoc-doc-buffer'
;; is its own command and reads `eldoc--doc-buffer' (buffer-local) to find
;; the right doc buffer.
(global-set-key (kbd "C-c d") #'eldoc-doc-buffer)

;; ggtags: xref backend for GNU Global's binary `GTAGS' index.
;;
;; Without this, `xref-find-references' (M-?) in a non-LSP buffer falls
;; through to the built-in etags backend.  Etags walks parent directories
;; looking for a plain-text `TAGS' file, picks up a `GTAGS' file (binary,
;; GNU Global's format) by name match, and signals:
;;     File .../GTAGS is not a valid tags table
;; Worse, `tags-file-name' is buffer-local-when-set: a stray
;; `visit-tags-table' (or a misbehaving package) can bind it to the
;; current source file, after which every M-? in that buffer crashes
;; with "File CaptchaType.java is not a valid tags table".  ggtags
;; registers `ggtags--xref-backend' on `xref-backend-functions', which
;; reads GTAGS correctly and short-circuits the etags fallback.
;;
;; Eglot, when active, prepends itself to `xref-backend-functions' and
;; wins -- so this hook list only matters in buffers without a running
;; language server (e.g. Java, which isn't in the eglot hook above).
;;
;; First-run note: as with all use-package blocks here, the archive isn't
;; refreshed at startup.  If ggtags isn't installed yet, `M-x my/package-refresh'
;; then restart Emacs once.  Also requires the `gtags' / `global' CLIs
;; (apt: `global'); run `gtags' at a repo root to generate the index.
(use-package ggtags
  :commands ggtags-mode
  :hook ((c-mode      c-ts-mode
          c++-mode    c++-ts-mode
          java-mode   java-ts-mode
          python-mode python-ts-mode) . ggtags-mode))

;; Defensive: keep the etags fallback's globals empty so a stray
;; `visit-tags-table' can't seed them with a binary GTAGS file or a Java
;; source.  Both default to nil already; the explicit setq-default
;; documents the invariant and re-asserts it after any package that
;; auto-sets them on load.
(setq-default tags-file-name nil
              tags-table-list nil)

;; tree-sitter (built-in in 30): faster, more accurate syntax via *-ts-mode.
;; `treesit-auto' installs grammars on demand and remaps classic modes to their
;; tree-sitter equivalents (python-mode -> python-ts-mode, etc.).
;;
;; `treesit-install-language-grammar' installs to ~/.emacs.d/tree-sitter/ and
;; adds that dir to `treesit-extra-load-path' for the current session only.
;; Without this `add-to-list', next startup can't find the installed .so files
;; and we get "cannot open shared object file" warnings for go/gomod/etc.
(add-to-list 'treesit-extra-load-path
             (expand-file-name "tree-sitter" user-emacs-directory))

(use-package treesit-auto
  :custom (treesit-auto-install t)        ; auto-install missing grammars on first use
  :config
  ;; Opt out of tree-sitter for languages where the built-in mode is good
  ;; enough and the ABI churn isn't worth it.  Currently:
  ;;   css  -- upstream grammar jumped to ABI 15 in v0.25.0 (May 2024);
  ;;           Emacs 30.1 maxes at ABI 14, so every css-ts-mode buffer
  ;;           emits "version-mismatch: 15" warnings.  Built-in `css-mode'
  ;;           covers our use cases (Vue <style> blocks go through Volar).
  ;;   json -- simple grammar; built-in `js-json-mode' is fine and the
  ;;           LSP (vscode-json-language-server) does the heavy lifting.
  ;;   lua  -- `tree-sitter-grammars/tree-sitter-lua' is also ABI 15 at HEAD
  ;;           (verified 2026-05-19: `treesit-auto-install' freshly cloned +
  ;;           compiled the grammar and STILL produced ABI 15).  No
  ;;           ABI-14-compatible tag exists upstream.  Fall back to MELPA
  ;;           `lua-mode' (regex-based, see use-package clause below) for
  ;;           highlighting; revisit if/when upstream tags ABI 14 or Emacs
  ;;           lifts the ABI cap.
  ;; All three modes are still hooked to eglot above where applicable; we
  ;; just lose the tree-sitter font-lock / structural navigation, which is
  ;; no real loss for these grammars.
  (setq treesit-auto-langs (seq-difference treesit-auto-langs '(css json lua)))
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;; lua-mode (MELPA): regex-based highlighting for .lua files.  Picked over
;; the built-in `lua-ts-mode' because upstream tree-sitter-lua is ABI 15
;; (see the treesit-auto exclusion comment above).  Highlighting only --
;; no LSP / formatter / REPL wired; reach for `M-s r' (consult-ripgrep)
;; for cross-file work in a Lua project.
(use-package lua-mode
  :mode "\\.lua\\'")

;; combobulate: structural editing driven by the tree-sitter parse tree.
;; Where `expand-region' grows by lisp sexps (and gets it wrong in most
;; non-Lisp languages), combobulate operates on REAL syntactic nodes -- "the
;; if-statement", "this function's parameter list", "the current JSX element"
;; -- so motions and edits respect language structure.
;;
;; Why this earns its slot in a config that already has multiple-cursors,
;; expand-region and Eglot's LSP rename:
;;   * Sibling navigation (`M-a' / `M-e') jumps between cases of a switch, list
;;     elements, JSX children, method definitions in a class -- without
;;     fiddling with regex search.
;;   * `M-<' / `M->' swap siblings -- reorder list items / function args / JSX
;;     attributes without re-indenting by hand.
;;   * `M-h' marks the current node; repeat to climb to the enclosing node.
;;     Composes with delete-selection-mode: mark `M-h M-h`, type replacement.
;;   * `C-c o n' renames the current identifier across its lexical scope WITHOUT
;;     an LSP -- works in buffers where Eglot isn't attached (e.g. JSON/YAML
;;     keys, Markdown code blocks) and is instant.
;;
;; Hooks: every *-ts-mode this config opens Eglot on, except `rust-ts-mode'
;; (combobulate has no Rust support as of 2026-05).  `c-ts-mode' / `c++-ts-mode'
;; likewise unsupported.  Inside .vue files combobulate doesn't activate in
;; the embedded `js-ts-mode' / `typescript-ts-mode' chunks -- vue-mode's MMM
;; sub-buffer mechanism doesn't fire combobulate's mode hook there (a known
;; limitation, not a bug here).
;;
;; Source: GitHub only -- not on MELPA.  `:vc' is the Emacs 30 use-package
;; keyword that calls `package-vc-install' on first run (no straight.el /
;; quelpa needed).  Subsequent starts are no-ops.  To update later:
;;   M-x package-vc-upgrade RET combobulate RET
;; First load may take ~3s as Emacs byte-compiles the language adapters.
(use-package combobulate
  :vc (:url "https://github.com/mickeynp/combobulate" :rev :newest)
  :hook ((python-ts-mode     . combobulate-mode)
         (go-ts-mode         . combobulate-mode)
         (js-ts-mode         . combobulate-mode)
         (typescript-ts-mode . combobulate-mode)
         (tsx-ts-mode        . combobulate-mode))
  :custom
  ;; Default `C-c o' -- spelled out so the prefix is visible at the call
  ;; site (and easy to retarget if it ever clashes with a new mode binding).
  (combobulate-key-prefix "C-c o"))

;; flymake (built-in): on-the-fly diagnostics; Eglot feeds it from the LSP.
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :bind (:map flymake-mode-map
              ("M-n" . flymake-goto-next-error)
              ("M-p" . flymake-goto-prev-error)))

;; flymake-eslint: runs `node_modules/.bin/eslint' on save / change and feeds
;; the JSON diagnostics into Flymake -- so ESLint errors show up next to
;; tsserver's type errors in the same buffer (M-n / M-p above walks both).
;; Why not the LSP ESLint server: Eglot binds one server per major mode and
;; typescript-language-server already owns JS/TS/TSX.  Running ESLint as a
;; sibling Flymake backend sidesteps the multi-server problem entirely.
;;
;; `flymake-eslint-defer-binary-check' (t) skips probing for the `eslint'
;; binary at hook time -- otherwise opening a JS file outside any project
;; (scratch snippet, gist, dotfile) prints a "cannot find eslint" warning.
;; When the binary really is missing, the backend silently no-ops.
;; vue-mode is included so `eslint-plugin-vue' lints both the <template> and
;; <script> blocks of .vue files alongside the same ESLint config used for
;; the rest of the project.  flymake-eslint feeds the file as a whole; the
;; plugin handles the SFC split internally.
(use-package flymake-eslint
  :hook ((js-ts-mode typescript-ts-mode tsx-ts-mode vue-mode) . flymake-eslint-enable)
  :custom (flymake-eslint-defer-binary-check t))

;; apheleia: async format-on-save.  Why not `eglot-format-buffer':
;; typescript-language-server explicitly does NOT implement textDocument/
;; formatting (their README points at Prettier).  Apheleia runs the formatter
;; in a subprocess, diffs the output against the buffer, and applies the
;; minimal edit -- so point / mark / window-start don't jump, and the save
;; isn't blocked on the formatter.  Default formatter table maps:
;;     js/ts/tsx/jsx/css/scss/html/json/md  -> prettier
;;     python  -> black + isort
;;     go      -> gofmt + goimports
;;     rust    -> rustfmt
;; Override on a per-mode basis via `apheleia-mode-alist' if a project pins
;; a different tool (e.g. biome, ruff format).  `apheleia-global-mode' is
;; opt-in per buffer -- it only formats when the formatter binary is on PATH
;; AND the major mode has an entry, so it stays quiet in unrelated buffers.
(use-package apheleia
  :config
  ;; Prettier formats .vue SFCs natively (template + script + style in one
  ;; pass).  `apheleia-mode-alist' has no default entry for `vue-mode', so
  ;; without this nothing fires on save -- add it alongside the other
  ;; prettier-driven modes.
  (add-to-list 'apheleia-mode-alist '(vue-mode . prettier))
  (apheleia-global-mode +1))

;; markdown-mode (already installed): pulled in by some of the AI tools too.
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode))   ; GitHub-flavoured Markdown for READMEs
  :custom (markdown-command "pandoc"))

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
