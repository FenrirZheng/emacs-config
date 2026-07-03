;;; init-corfu.el --- In-buffer code completion (Corfu + Cape) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 5 of the pre-split monolithic init.el (see git log for the move).
;; Corfu is the lightweight `company' alternative: a small popup at point.
;; Cape provides extra completion-at-point backends to feed it.
;;
;; In-buffer completion frontend: Vertico minibuffer, NOT Corfu popup.
;;
;; `completion-in-region-function' is the single switch that decides which UI
;; handles in-buffer completion (`C-<tab>' / `C-M-i' / `completion-at-point';
;; see the `keymap-global-set' at the bottom of this file for the C-<tab> bind).
;; Below we route it to `consult-completion-in-region' (set on the consult
;; block in init-completion.el), which renders the candidates in the
;; minibuffer with the same Vertico + orderless + marginalia stack used by
;; `C-x C-f' / `M-x'.
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

;;; Code:

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
  :defer t
  :init
  ;; Generic backends useful in every buffer: dabbrev (words in open buffers),
  ;; file paths, and elisp symbols.  Eglot adds language-aware ones on top.
  ;; All three are autoloaded, so `:defer t' keeps cape itself unloaded until
  ;; `completion-at-point' actually calls one of them.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block))

;; In-buffer completion trigger.  Emacs' defaults are `M-TAB' and `C-M-i';
;; `M-TAB' never reaches Emacs under GNOME (the WM grabs Alt+Tab), so bind a
;; conflict-free `C-<tab>' to `completion-at-point' too.  This is the key that
;; fires TempEl `tempel-expand', Eglot, and the cape backends -- all rendered
;; through `consult-completion-in-region' (Vertico).  `C-M-i' still works.
(keymap-global-set "C-<tab>" #'completion-at-point)

(provide 'init-corfu)
;;; init-corfu.el ends here
