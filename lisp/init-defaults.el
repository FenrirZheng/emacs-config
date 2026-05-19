;;; init-defaults.el --- Better built-in defaults (no external packages) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 2 of the pre-split monolithic init.el (see git log for the move).
;; Tunes built-in Emacs behaviour, sets up the OSC 52 clipboard bridge for
;; TTY frames, points `custom-file' at custom.el, and wires `which-key' and
;; `ibuffer' (both built-in).  No third-party packages here.

;;; Code:

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
  ;; bookmark-save-flag = 1: persist `bookmark-set' / `bookmark-rename' /
  ;; `bookmark-delete' to the bookmarks file IMMEDIATELY, not on Emacs exit.
  ;; In daemon mode the "on exit" path effectively never fires (daemon stays
  ;; alive across `emacsclient' sessions; a SIGKILL / power cut loses
  ;; everything you set since launch).  no-littering already redirects the
  ;; on-disk bookmarks file under `var/bookmark'.
  (setq bookmark-save-flag 1)
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

(provide 'init-defaults)
;;; init-defaults.el ends here
