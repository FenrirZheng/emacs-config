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
  :custom
  (doom-modeline-height 25)
  ;; LSP/Eglot segment.  `doom-modeline-lsp' is already t by default, so the
  ;; `lsp' segment is already in the 'main RHS -- but it only RENDERS once an
  ;; Eglot server actually manages the buffer.  That makes it the load-bearing
  ;; "did the server connect?" signal: Java's jdtls can silently fail to start
  ;; (the corp Nexus mirror in ~/.m2/settings.xml TCP-times-out on import), and
  ;; without this segment there is NO other visual cue that gopls/clangd/jdtls
  ;; never came up.  Stated explicitly here so the intent survives a future
  ;; doom-modeline default flip.
  (doom-modeline-lsp t)
  (doom-modeline-lsp-icon t)
  ;; Density tuning for narrow tmux panes.  doom-modeline silently TRUNCATES
  ;; right-side segments when the window is too narrow; on a split tmux pane the
  ;; vcs/check/lsp segments are the first to vanish.  Trim low-value width first:
  ;;   - check 'simple : compact error/warning counter (vs 'auto which widens
  ;;     with the window).  NOTE: the knob is `doom-modeline-check' set to the
  ;;     symbol 'simple -- the roadmap's `doom-modeline-check-simple-format' does
  ;;     NOT exist (verified: not a defcustom).
  ;;   - minor-modes nil : already the default, kept explicit as documentation.
  ;;   - buffer-encoding nil : drop the UTF-8/LF segment (rarely non-default here).
  ;;   - file-name-style truncate-upto-project : show only the project-relative
  ;;     tail instead of the full path.
  ;;   - vcs-max-length 18 : allow slightly longer branch names (default 15).
  (doom-modeline-check 'simple)
  (doom-modeline-minor-modes nil)
  (doom-modeline-buffer-encoding nil)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-vcs-max-length 18))

;; nerd-icons-completion: icons in the minibuffer completion / marginalia column
;; (Vertico drives completion in this config).  GOTCHA: `marginalia-mode' has
;; ALREADY fired by the time this module loads (it is turned on at startup in
;; init-completion), so adding `nerd-icons-completion-marginalia-setup' to the
;; hook alone will NOT retro-fire for the already-active session.  We therefore
;; ALSO call `(nerd-icons-completion-mode 1)' explicitly so the icons attach to
;; the live marginalia, and keep the hook so a later marginalia toggle re-wires
;; them.  (TTY caveat: glyphs render only if the terminal's font is a Nerd Font.)
(use-package nerd-icons-completion
  :after marginalia
  :config
  (nerd-icons-completion-mode 1)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

;; nerd-icons-ibuffer: a glyph per row in ibuffer.  Relevant because this config
;; rebinds `C-x b' to ibuffer (the consult fuzzy switcher lives on `C-x B'), so
;; ibuffer is the everyday buffer list and benefits from the major-mode icons.
(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

;; ef-themes: an OPT-IN alternative palette family.  doom-tokyo-night stays the
;; default loaded theme (see the doom-themes block above) -- ef is only a toggle.
;; `ef-themes-to-toggle' picks the two themes `ef-themes-toggle' flips between.
;;   C-c e t : ef-themes-toggle (flip between the two ef themes above)
;;   C-c e T : consult-theme    (live-preview pick ANY installed theme, incl.
;;                               jumping back to a doom-* one)
;; C-c e / C-c e t / C-c e T verified free.  Tab management deliberately stays on
;; the native `C-x t' prefix -- no C-c key is invented for it.
(use-package ef-themes
  :custom (ef-themes-to-toggle '(ef-day ef-night))
  :bind (("C-c e t" . ef-themes-toggle)
         ("C-c e T" . consult-theme)))

;; tab-bar: a TTY-native text workspace row (built-in, hence :ensure nil).
;; `tab-bar-show' set to the INTEGER 1 (not t) auto-hides the row when only one
;; tab exists, so it stays invisible until you actually open a second tab --
;; non-intrusive on a single-pane TTY.  TTY cleanups: drop the mouse-oriented
;; [x] close button and the [+] new-tab button; show numeric hints so the
;; native `C-x t <n>'-style navigation has visible targets.  Tab commands live
;; on the fully-populated native `C-x t' map (C-x t 2 new, C-x t 0 close,
;; C-x t o next, C-x t RET switch, C-x t r rename) -- do NOT shadow with C-c.
(use-package tab-bar
  :ensure nil
  :custom
  (tab-bar-show 1)
  (tab-bar-tab-hints t)
  (tab-bar-close-button-show nil)
  (tab-bar-new-button-show nil)
  :config (tab-bar-mode 1))

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
