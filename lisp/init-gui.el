;;; init-gui.el --- GUI-frame-only enhancements -*- lexical-binding: t; -*-

;;; Commentary:
;; Eye-candy / child-frame packages that only make sense on a GRAPHICAL frame.
;; This config is daemon-first and *mostly* reached via `emacsclient -nw' (TTY),
;; but the same daemon also serves the occasional GUI frame (`emacsclient -c'),
;; so this module installs the GUI niceties and -- crucially -- gates each one so
;; it NEVER degrades the TTY frames the daemon also serves.
;;
;; Three safety tiers, decided by reading each package's fallback path:
;;
;;   TIER A -- safe to enable globally (the package self-checks and falls back
;;             to a TTY-correct rendering on its own, or its effect is a pure
;;             overlay/face flash that simply renders plainer on a terminal):
;;               * vertico-posframe  (per-display `posframe-workable-p' guard ->
;;                                    plain Vertico minibuffer on TTY)
;;               * ligature          (font-feature ligatures; a TTY just ignores
;;                                    the OpenType features -> no-op, no breakage)
;;               * beacon            (cursor flash; overlay background -> works on
;;                                    TTY, richer on GUI)
;;               * dimmer            (dims inactive windows by adjusting the
;;                                    foreground colour -> degrades but never
;;                                    breaks on a low-colour TTY)
;;               * solaire-mode      (subtly different background for "real" file
;;                                    buffers; a face remap, harmless on TTY)
;;               * highlight-numbers (font-lock keyword for numeric literals)
;;               * goggles           (pulse the just-edited region; overlay)
;;               * volatile-highlights (transient highlight of yank/undo regions)
;;               * nerd-icons-corfu  (kind glyphs in the corfu popup; renders if
;;                                    the terminal font is a Nerd Font, else text)
;;               * lin               (a tasteful `hl-line' for list/selection
;;                                    buffers -- dired/ibuffer/grep/... ; a face)
;;               * pulsar            (pulses the current line after jump/scroll
;;                                    commands; overlay-based, harmless on TTY)
;;
;;   TIER B -- on-demand only, fired by a command that ADAPTS per display
;;             (child frame / variable-pitch / font preset on GUI, an explicit
;;             TTY fallback or a no-op `user-error' on a terminal), because the
;;             always-on form would hijack a display-only path:
;;               * eldoc-box        (child-frame hover -> doc-buffer on TTY)
;;               * frog-jump-buffer (posframe buffer grid -> `consult-buffer' TTY)
;;               * mixed-pitch      (variable-pitch prose -> no-op on TTY)
;;               * fontaine         (named font-size presets -> refuses on TTY)
;;               * prism            (depth-coloured code; opt-in per buffer --
;;                                   striking on truecolor GUI, noisy on 8-colour)
;;               * dashboard        (graphical startup screen; a plain command)
;;
;;   TIER C -- installed but NOT auto-enabled; flipped on by a command for a
;;             GUI-only session, because they are GLOBAL display-replacing modes
;;             with NO per-display fallback, and this daemon genuinely serves a
;;             TTY frame and a GUI frame at the SAME time (verified: a live
;;             `emacsclient -c' X frame coexists with the `-nw' tmux frame).
;;             Enabling them globally for the GUI frame BREAKS the TTY frame:
;;               * which-key-posframe   -- sets `which-key-popup-type' to `custom'
;;                                         globally; its show fn no-ops on TTY, so
;;                                         which-key shows NOTHING on the terminal.
;;               * transient-posframe   -- its show fn *errors* on TTY, so every
;;                                         magit / transient menu breaks there.
;;               * spacious-padding     -- adds internal borders / fringe padding
;;                                         (graphical frame parameters only).
;;               * nyan-mode            -- an IMAGE progress indicator in the
;;                                         mode line; renders as broken text on a
;;                                         terminal.
;;               * good-scroll          -- animated pixel scrolling; GUI only.
;;               * mlscroll             -- a graphical, mouse-draggable scrollbar
;;                                         drawn in the mode line; GUI only.
;;             So they're folded into `fenrir/gui-popups-toggle' (M-x, or the key
;;             below) -- turn them on when you're in a GUI-only Emacs, off before
;;             you go back to a terminal frame.  Auto-enabling them was tried and
;;             reverted precisely because of the live mixed-frame breakage.
;;             Two more TIER-C tools stay command-driven with their own
;;             display-graphic guard rather than living in the batch toggle:
;;               * minimap       -- a code minimap side window (GUI-guarded cmd).
;;               * centaur-tabs  -- a graphical buffer tab bar (on-demand cmd).

;;; Code:

;; ------------------------------------------------------------------ TIER A ---

;; x-gtk-resize-child-frames: this daemon runs under GNOME Shell + mutter
;; (confirmed via `XDG_CURRENT_DESKTOP'/`ps'), the exact desktop this GTK3
;; variable's own docstring names as refusing to resize child frames under
;; the default (nil) setting -- which is the GTK3 flicker this item targets.
;; `resize-mode' is the no-flicker option; the docstring also warns it "may
;; freeze Emacs when used with OTHER desktop environments" (GTK's resize
;; mode is deprecated upstream), i.e. environments other than the
;; GNOME-shell/mutter case this workaround exists for -- since we ARE on
;; mutter, that freeze risk is the one the docstring implies this setting is
;; safe against.  Still: this is a single GLOBAL variable read by every GTK
;; child-frame resize in this one Emacs process (vertico-posframe below,
;; corfu's popup, eldoc-box, transient-posframe/which-key-posframe when
;; toggled on) -- were it ever to freeze, it freezes the whole daemon,
;; TTY frame included, since there is only one process.  `boundp'-guarded
;; because it's GTK-build-only (absent on a non-GTK Emacs build).
(when (boundp 'x-gtk-resize-child-frames)
  (setq x-gtk-resize-child-frames 'resize-mode))

;; vertico-posframe: show the Vertico minibuffer as a centred child frame on
;; GUI.  `:global t' mode, but every display goes through `posframe-workable-p',
;; so on a TTY frame it transparently falls back to the normal bottom-of-frame
;; Vertico (see `vertico-posframe-mode' in the package) -- safe to leave on.
(use-package vertico-posframe
  :after vertico
  :config (vertico-posframe-mode 1))

;; ligature: render programming ligatures (-> => != >= |> ... ) on GUI with a
;; ligature-capable font (Fira Code / Cascadia / JetBrains Mono / Iosevka ...).
;; On a TTY the OpenType features are simply not applied -- `global-ligature-mode'
;; is a harmless no-op there, so it's safe to enable unconditionally.  The set
;; below is the maintainer's recommended "works in most coding fonts" list.
(use-package ligature
  :config
  (ligature-set-ligatures
   'prog-mode
   '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
     ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
     "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
     "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
     "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
     "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
     "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
     "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
     ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
     "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
     "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
     "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
     "\\\\" "://"))
  (global-ligature-mode 1))

;; beacon: when point teleports across the screen (window switch, big scroll,
;; an avy/consult jump) a coloured beam briefly flashes the line so the eye
;; re-acquires the cursor.  Pure overlay -> works on a TTY, just plainer.
;; Vertical single-line moves are excluded so ordinary editing doesn't flash.
(use-package beacon
  :config
  (setq beacon-blink-when-window-scrolls t
        beacon-blink-when-window-changes t
        beacon-blink-when-point-moves-vertically nil
        beacon-size 24)
  (beacon-mode 1))

;; dimmer: dim every window EXCEPT the one with focus, so the active buffer
;; pops.  It adjusts the foreground colour by `dimmer-fraction', degrading
;; gracefully on a low-colour TTY (never an error).  The `dimmer-configure-*'
;; calls keep transient UIs (which-key/magit/org src) at full brightness.
(use-package dimmer
  :config
  (setq dimmer-fraction 0.30
        dimmer-adjustment-mode :foreground)
  (dimmer-configure-which-key)
  (dimmer-configure-magit)
  (dimmer-configure-org)
  (dimmer-mode 1))

;; solaire-mode: give "real" file buffers a slightly different background from
;; transient/UI buffers (minibuffer, sidebars, popups) so the eye separates
;; content from chrome.  Implemented as a face remap -> harmless on a TTY.
(use-package solaire-mode
  :config (solaire-global-mode 1))

;; highlight-numbers: font-lock numeric literals in their own face so magic
;; numbers stand out from identifiers.  A font-lock keyword -> TTY-safe.
(use-package highlight-numbers
  :hook (prog-mode . highlight-numbers-mode))

;; goggles: pulse a soft highlight over the region you just changed (yank,
;; delete, kill, undo).  Overlay-based -> renders plainer but works on a TTY.
(use-package goggles
  :hook ((prog-mode text-mode) . goggles-mode)
  :config (setq-default goggles-pulse t))

;; volatile-highlights: transient highlight of the text a command just inserted
;; (yank, undo, ...), cleared on the next keystroke.  Overlay -> TTY-safe.
(use-package volatile-highlights
  :config (volatile-highlights-mode 1))

;; nerd-icons-corfu: a kind glyph (function / variable / keyword / ...) in the
;; left margin of each corfu candidate.  Corfu is installed (init-corfu.el) but
;; deferred; this just registers the margin formatter, so icons appear whenever
;; corfu pops.  On a TTY the glyphs render only if the terminal font is a Nerd
;; Font (corfu-terminal handles the popup itself) -> graceful text fallback.
(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

;; lin: a more stylish, mode-aware `hl-line' for selection/list buffers --
;; dired, ibuffer, grep, occur, packages, ... -- where the current ROW matters.
;; It only lights up in those modes (not every buffer), and it's a face, so it
;; is completely TTY-safe.
(use-package lin
  :config
  (setq lin-face 'lin-cyan)
  (lin-global-mode 1))

;; pulsar: listed in the TIER A commentary above, but its `use-package' block
;; lives in `init-editing.el' (loaded earlier), where the avy/consult pulse
;; wiring is -- a second block here would just re-run `pulsar-global-mode'.

;; ------------------------------------------------------------------ TIER B ---

;; eldoc-box: rich hover documentation in a child frame (the VSCode "hover
;; card").  DELIBERATELY not hooked on -- its display function builds a child
;; frame, which errors / shows nothing on a TTY AND can swallow the echo-area
;; fallback.  Instead, one command that adapts: child frame on a GUI frame, the
;; existing eldoc doc-buffer (`C-c d', init-languages.el) on a TTY frame.  In a
;; GUI-only session you can still `M-x eldoc-box-hover-at-point-mode' for
;; always-on hover.
(use-package eldoc-box
  :commands (eldoc-box-help-at-point eldoc-box-hover-at-point-mode eldoc-box-hover-mode)
  :init
  (defun fenrir/eldoc-box-dwim ()
    "Show docs for the symbol at point.
GUI frame: an `eldoc-box' child frame.  TTY frame: the eldoc doc buffer
(`eldoc-doc-buffer'), since child frames don't exist on a terminal."
    (interactive)
    (if (display-graphic-p)
        (eldoc-box-help-at-point)
      (eldoc-doc-buffer)))
  :bind ("C-c H" . fenrir/eldoc-box-dwim))   ; "Hover" -- C-c h is eglot's prefix

;; frog-jump-buffer: a posframe grid of recent buffers, each labelled with an
;; avy key -- press the letter to jump.  Child frame -> a GUI-only display, so
;; the command adapts: the posframe grid on a graphical frame, `consult-buffer'
;; (the everyday fuzzy switcher, init-completion.el) on a TTY frame.
(use-package frog-jump-buffer
  :commands (frog-jump-buffer)
  :init
  (defun fenrir/jump-buffer-dwim ()
    "Buffer switcher: a posframe grid on a GUI frame (`frog-jump-buffer'),
falling back to `consult-buffer' on a TTY frame (no child frames there)."
    (interactive)
    (if (display-graphic-p)
        (frog-jump-buffer)
      (consult-buffer)))
  :bind ("C-c J" . fenrir/jump-buffer-dwim))

;; mixed-pitch: render prose (org/markdown/text) in a proportional font while
;; keeping code/tables monospaced.  Variable-pitch fonts exist only on a
;; graphical frame, so the dwim command turns it on there and reports a no-op on
;; a TTY rather than silently doing nothing.
(use-package mixed-pitch
  :commands (mixed-pitch-mode)
  :init
  (defun fenrir/mixed-pitch-dwim ()
    "Toggle variable-pitch prose rendering in this buffer.
Variable-pitch fonts only exist on a graphical frame, so on a TTY this
reports a no-op instead of silently doing nothing."
    (interactive)
    (if (display-graphic-p)
        (call-interactively #'mixed-pitch-mode)
      (user-error "Variable-pitch fonts need a graphical frame -- no-op on TTY")))
  :bind ("C-c M-v" . fenrir/mixed-pitch-dwim))   ; "Variable-pitch" (C-c M-p is copilot)

;; fontaine: named font-size presets (small/regular/large/huge) you can flip
;; between live -- handy when sharing a GUI screen or moving to an external
;; monitor.  Fonts are a graphical concept, so the dwim refuses on a TTY.
(use-package fontaine
  :commands (fontaine-set-preset)
  :init
  (setq fontaine-presets
        '((small   :default-height 110)
          (regular :default-height 130)
          (large   :default-height 160)
          (huge    :default-height 200)
          (t       :default-family "monospace")))
  (defun fenrir/fontaine-set-preset-dwim ()
    "Pick a `fontaine' font-size preset (graphical frames only)."
    (interactive)
    (unless (display-graphic-p)
      (user-error "Font presets need a graphical frame -- no-op on TTY"))
    (call-interactively #'fontaine-set-preset))
  :bind ("C-c M-f" . fenrir/fontaine-set-preset-dwim))

;; prism: repaint code by NESTING DEPTH rather than syntax category -- each
;; level of (), [], {} indentation gets its own colour.  Striking on a GUI
;; truecolor frame, but it collapses to noise on an 8/16-colour TTY, so it's
;; opt-in PER BUFFER via a command, never a global hook.
(use-package prism
  :commands (prism-mode prism-whitespace-mode)
  :init
  (defun fenrir/prism-toggle ()
    "Toggle `prism-mode' depth-based syntax colouring in this buffer.
Opt-in per buffer -- prism repaints all font-lock by nesting depth, which is
striking on a GUI truecolor frame but collapses to noise on an 8/16-colour TTY."
    (interactive)
    (call-interactively #'prism-mode))
  :bind ("C-c M-r" . fenrir/prism-toggle))

;; dashboard: a graphical startup screen (logo banner + recent files / projects
;; / bookmarks).  NOT wired as the daemon's initial buffer (that would fight the
;; server's buffer setup) -- it's an on-demand command instead.  The text list
;; works anywhere; the logo banner is the GUI flourish.
(use-package dashboard
  :commands (dashboard-open)
  :init
  (setq dashboard-startup-banner 'logo
        dashboard-center-content t
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-items '((recents . 8) (projects . 5) (bookmarks . 5)))
  :bind ("C-c M-d" . dashboard-open))

;; ------------------------------------------------------------------ TIER C ---

;; Global display-replacing GUI-only modes.  Installed but NOT auto-enabled --
;; see the commentary at the top of this file.  The first four are folded into
;; `fenrir/gui-popups-toggle' (one switch for "I'm in a GUI-only session"); the
;; last two are command-driven with their own `display-graphic-p' guard.
(use-package which-key-posframe :defer t)
(use-package transient-posframe :defer t)
(use-package spacious-padding   :defer t)
(use-package nyan-mode          :defer t)
(use-package good-scroll        :defer t)
(use-package mlscroll           :defer t)

;; minimap: a scaled-down overview of the buffer in a side window (the VSCode
;; minimap).  Rendered with a tiny font -> meaningless on a TTY, so the toggle
;; refuses there.
(use-package minimap
  :commands (minimap-mode)
  :init
  (setq minimap-window-location 'right
        minimap-width-fraction 0.10
        minimap-minimum-width 18)
  (defun fenrir/minimap-toggle-dwim ()
    "Toggle the code minimap sidebar (graphical frames only)."
    (interactive)
    (unless (display-graphic-p)
      (user-error "Minimap needs a graphical frame -- no-op on TTY"))
    (call-interactively #'minimap-mode))
  :bind ("C-c M-m" . fenrir/minimap-toggle-dwim))

;; centaur-tabs: a graphical buffer tab bar with mode icons and a modified
;; marker.  This config's everyday "tabs" are tab-bar + tabspaces workspaces
;; (C-c W); centaur-tabs is a different, GUI-flavoured *buffer* bar offered
;; on-demand for GUI sessions that want VSCode-style file tabs.
(use-package centaur-tabs
  :commands (centaur-tabs-mode centaur-tabs-local-mode)
  :init
  (setq centaur-tabs-style "bar"
        centaur-tabs-height 28
        centaur-tabs-set-icons t
        centaur-tabs-set-bar 'left
        centaur-tabs-set-modified-marker t
        centaur-tabs-cycle-scope 'tabs)
  :bind ("C-c M-t" . centaur-tabs-mode))

(defvar fenrir/gui-popups-enabled nil
  "Non-nil when `fenrir/gui-popups-toggle' has turned the TIER C modes on.")

(defun fenrir/gui-popups-toggle ()
  "Toggle the GUI-only global display modes (TIER C).
Covers the posframe popups (which-key / transient), animated smooth
scrolling (`good-scroll'), the graphical mode-line scrollbar
\(`mlscroll'), frame padding (`spacious-padding'), and the `nyan-mode'
mode-line indicator.  (`pixel-scroll-precision-mode' is NOT part of this
toggle -- init-defaults.el turns it on globally; it no-ops on TTY frames,
so there is nothing to switch off before returning to a terminal.)
These are GLOBAL display-replacing modes with no TTY fallback, so they are
manual: turn them on in a GUI-only Emacs, OFF before using a terminal frame
of the same daemon (otherwise which-key/transient break on the TTY frame).
Refuses to turn on unless the current frame is graphical."
  (interactive)
  (if fenrir/gui-popups-enabled
      (progn
        (when (fboundp 'which-key-posframe-mode) (which-key-posframe-mode -1))
        (when (fboundp 'transient-posframe-mode) (transient-posframe-mode -1))
        (when (fboundp 'good-scroll-mode) (good-scroll-mode -1))
        (when (fboundp 'mlscroll-mode) (mlscroll-mode -1))
        (when (fboundp 'spacious-padding-mode) (spacious-padding-mode -1))
        (when (fboundp 'nyan-mode) (nyan-mode -1))
        ;; which-key-posframe-mode / transient-posframe-mode don't reliably
        ;; restore their globals on disable -- put them back explicitly so the
        ;; TTY frame's which-key / transient work again.
        (setq which-key-popup-type 'side-window)
        (setq transient-display-buffer-action
              '(display-buffer-in-side-window
                (side . bottom) (dedicated . t) (inhibit-same-window . t)
                (window-parameters (no-other-window . t))))
        (setq fenrir/gui-popups-enabled nil)
        (message "GUI display modes OFF (which-key/transient restored to side-window)"))
    (unless (display-graphic-p)
      (user-error "Not a graphical frame -- TIER C modes would break this terminal"))
    (require 'which-key-posframe nil t)
    (require 'transient-posframe nil t)
    (require 'good-scroll nil t)
    (require 'mlscroll nil t)
    (require 'spacious-padding nil t)
    (require 'nyan-mode nil t)
    (when (fboundp 'which-key-posframe-mode) (which-key-posframe-mode 1))
    (when (fboundp 'transient-posframe-mode) (transient-posframe-mode 1))
    (when (fboundp 'good-scroll-mode) (good-scroll-mode 1))
    (when (fboundp 'mlscroll-mode) (mlscroll-mode 1))
    (when (fboundp 'spacious-padding-mode) (spacious-padding-mode 1))
    (when (fboundp 'nyan-mode) (nyan-mode 1))
    (setq fenrir/gui-popups-enabled t)
    (message "GUI display modes ON (turn OFF before using a TTY frame: C-c M-g)")))

(global-set-key (kbd "C-c M-g") #'fenrir/gui-popups-toggle)  ; "Gui popups"

(provide 'init-gui)
;;; init-gui.el ends here
