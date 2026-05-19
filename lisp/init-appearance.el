;;; init-appearance.el --- Appearance (doom-themes + doom-modeline + nerd-icons) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 11 of the pre-split monolithic init.el (see git log for the move).

;;; Code:

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

;; Daemon-aware per-frame setup.
;;
;; `load-theme' above runs ONCE -- when the daemon starts up (or, in the
;; non-daemon case, when init.el is loaded).  That's correct for the theme
;; itself (which is global, not per-frame), but anything frame-specific --
;; font / face-attribute / fringe / cursor on a GUI frame -- has to run AGAIN
;; for every new `emacsclient -c' frame, or it inherits the daemon's
;; pre-init defaults and shows up wrong on the first paint.
;;
;; This hook is currently empty.  It exists so the next time we want to
;; add e.g. `set-face-attribute' for a Han / Hiragana fallback font, the
;; change is a one-liner inside `fenrir/setup-frame' instead of a refactor
;; that has to (a) discover the daemon caveat, (b) reroute through this
;; hook, (c) re-verify the non-daemon path.  All three are done here.
(defun fenrir/setup-frame (&optional frame)
  "Per-frame setup that must run for every new frame in daemon mode.
Add GUI-only face / font / fringe tweaks here; the body is intentionally
empty for now."
  (with-selected-frame (or frame (selected-frame))
    ;; placeholder -- future GUI-frame face/font setup goes here.
    (ignore frame)))

(if (daemonp)
    (add-hook 'server-after-make-frame-hook #'fenrir/setup-frame)
  (fenrir/setup-frame))

(provide 'init-appearance)
;;; init-appearance.el ends here
