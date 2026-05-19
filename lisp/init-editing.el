;;; init-editing.el --- Editing enhancements -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 7 of the pre-split monolithic init.el (see git log for the move).
;; Quality-of-life editing packages: avy, expand-region, multiple-cursors,
;; rainbow-delimiters, helpful, vundo, hl-todo, pulsar, ace-window, popper,
;; winner (built-in), breadcrumb, jinx.

;;; Code:

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
  :bind ("C-x u" . vundo)                ; was `undo' (still on C-/ and C-_)
  :custom
  ;; Default glyph set is ASCII (`+--o-+'); branches in a non-trivial undo
  ;; history blur into a wall of dashes.  `vundo-unicode-symbols' uses
  ;; box-drawing characters (┌─┬─┐ / └─┴─┘) so the tree is actually
  ;; readable.  Nerd-icons font in this config already covers them on TTY.
  (vundo-glyph-alist vundo-unicode-symbols))

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

(provide 'init-editing)
;;; init-editing.el ends here
