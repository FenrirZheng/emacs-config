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
;;             to a TTY-correct rendering on its own):
;;               * vertico-posframe  (per-display `posframe-workable-p' guard ->
;;                                    plain Vertico minibuffer on TTY)
;;               * ligature          (font-feature ligatures; a TTY just ignores
;;                                    the OpenType features -> no-op, no breakage)
;;
;;   TIER B -- on-demand only, with an explicit TTY fallback, because the
;;             always-on mode would hijack a display path and break it on TTY:
;;               * eldoc-box  (its display fn builds a child frame -> errors /
;;                             shows nothing on TTY; so DON'T hook it -- bind a
;;                             command that uses the child frame on GUI and the
;;                             eldoc doc-buffer on TTY)
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
;;               * pixel-scroll-precision-mode (built-in) -- pixel scrolling is
;;                                         meaningless on a TTY.
;;             So they're bound to `fenrir/gui-popups-toggle' (M-x, or the key
;;             below) -- turn them on when you're in a GUI-only Emacs, off before
;;             you go back to a terminal frame.  Auto-enabling them was tried and
;;             reverted precisely because of the live mixed-frame breakage.

;;; Code:

;; ------------------------------------------------------------------ TIER A ---

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

;; ------------------------------------------------------------------ TIER C ---

(use-package which-key-posframe :defer t)
(use-package transient-posframe :defer t)

(defvar fenrir/gui-popups-enabled nil
  "Non-nil when `fenrir/gui-popups-toggle' has turned the TIER C modes on.")

(defun fenrir/gui-popups-toggle ()
  "Toggle the GUI-only posframe popups + pixel scrolling (TIER C).
These are GLOBAL display-replacing modes with no TTY fallback, so they are
manual: turn them on in a GUI-only Emacs, OFF before using a terminal frame
of the same daemon (otherwise which-key/transient break on the TTY frame).
Refuses to turn on unless the current frame is graphical."
  (interactive)
  (if fenrir/gui-popups-enabled
      (progn
        (when (fboundp 'which-key-posframe-mode) (which-key-posframe-mode -1))
        (when (fboundp 'transient-posframe-mode) (transient-posframe-mode -1))
        (when (fboundp 'pixel-scroll-precision-mode) (pixel-scroll-precision-mode -1))
        ;; which-key-posframe-mode / transient-posframe-mode don't reliably
        ;; restore their globals on disable -- put them back explicitly so the
        ;; TTY frame's which-key / transient work again.
        (setq which-key-popup-type 'side-window)
        (setq transient-display-buffer-action
              '(display-buffer-in-side-window
                (side . bottom) (dedicated . t) (inhibit-same-window . t)
                (window-parameters (no-other-window . t))))
        (setq fenrir/gui-popups-enabled nil)
        (message "GUI posframe popups OFF (which-key/transient restored to side-window)"))
    (unless (display-graphic-p)
      (user-error "Not a graphical frame -- TIER C popups would break this terminal"))
    (require 'which-key-posframe nil t)
    (require 'transient-posframe nil t)
    (when (fboundp 'which-key-posframe-mode) (which-key-posframe-mode 1))
    (when (fboundp 'transient-posframe-mode) (transient-posframe-mode 1))
    (when (fboundp 'pixel-scroll-precision-mode) (pixel-scroll-precision-mode 1))
    (setq fenrir/gui-popups-enabled t)
    (message "GUI posframe popups ON (turn OFF before using a TTY frame: C-c M-g)")))

(global-set-key (kbd "C-c M-g") #'fenrir/gui-popups-toggle)  ; "Gui popups"

(provide 'init-gui)
;;; init-gui.el ends here
