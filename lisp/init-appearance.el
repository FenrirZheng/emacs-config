;;; init-appearance.el --- Appearance (doom-themes + doom-modeline + nerd-icons) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 11 of the pre-split monolithic init.el (see git log for the move).

;;; Code:

(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-tokyo-night t)       ; swap for any `doom-*' you like
  (doom-themes-org-config))              ; tweak org-mode faces to match

;; nerd-icons: glyph set used by doom-modeline and (optionally) Dired/Corfu.
;; Run `M-x nerd-icons-install-fonts' ONCE after install to fetch the font.
;; `:defer t' is safe -- doom-modeline `require's it explicitly when it loads.
(use-package nerd-icons :defer t)

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :custom (doom-modeline-height 25))

;; Daemon-aware per-frame setup.
;;
;; `load-theme' above runs ONCE -- when the daemon starts up (or, in the
;; non-daemon case, when init.el is loaded).  That's correct for the theme
;; itself (which is global, not per-frame), but anything frame-specific has
;; to run AGAIN for every new `emacsclient -c' frame, or it inherits the
;; daemon's pre-init defaults and shows up wrong on the first paint.
;;
;; A transparent background is exactly such a per-frame thing:
;;   - TTY : Emacs paints its own background over the terminal cells.
;;           Setting the `default' face background to the magic value
;;           "unspecified-bg" makes Emacs skip that paint, so the
;;           terminal's (or compositor's) transparency shows through.
;;           Only visible if the terminal emulator itself is transparent.
;;   - GUI : `alpha-background' (Emacs 29+) makes ONLY the background
;;           translucent; text and faces stay fully opaque.  Contrast
;;           `alpha', which fades the whole frame including the text.
(defvar fenrir/gui-alpha-background 90
  "Background opacity percentage (0-100) for GUI frames; 100 = opaque.")

(defun fenrir/setup-frame (&optional frame)
  "Per-frame setup that must run for every new frame in daemon mode.
Currently gives FRAME a transparent background on both TTY and GUI."
  (let ((frame (or frame (selected-frame))))
    (if (display-graphic-p frame)
        (set-frame-parameter frame 'alpha-background fenrir/gui-alpha-background)
      (set-face-background 'default "unspecified-bg" frame))))

(if (daemonp)
    (add-hook 'server-after-make-frame-hook #'fenrir/setup-frame)
  (fenrir/setup-frame))

(provide 'init-appearance)
;;; init-appearance.el ends here
