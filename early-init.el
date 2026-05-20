;;; early-init.el --- Pre-init: runs before package system / first frame -*- lexical-binding: t; -*-

;;; Commentary:
;; Runs BEFORE init.el, before `package-initialize', and before the first
;; frame is created.  This is the only correct place for:
;;   * GC tuning during startup (avoids the ~50 minor GCs init.el provokes)
;;   * `file-name-handler-alist' suspension (every `require' walks it)
;;   * Frame chrome via `default-frame-alist' (no flash of menu/tool bar)
;;   * Telling Emacs NOT to auto-activate packages -- init.el does it explicitly
;;
;; Doing any of these inside init.el is "too late": the cost has already been
;; paid (GC counts already accumulating, the first frame already painted with
;; chrome that has to be torn down, etc.).

;;; Code:

;; ---------------------------------------------------------------------------
;; GC during startup
;; ---------------------------------------------------------------------------
;; Default `gc-cons-threshold' is 800k -- with 60+ use-package blocks that
;; triggers ~50 minor GCs (~300-500ms total).  Disable GC entirely during init
;; by raising the threshold to the largest fixnum, then drop to a 16 MB FLOOR
;; on `emacs-startup-hook'.  `gcmh-mode' (configured in
;; `init-defaults.el') takes over from there and adapts the threshold upward
;; on user activity, sweeping during idle -- so 16 MB is just the lower bound
;; that holds between `emacs-startup-hook' and the first gcmh adjustment.
;; A fixed 32 MB without GCMH used to be the sweet spot here, but it still
;; produced visible pauses on heavy `consult-ripgrep' / Magit refresh; GCMH
;; eliminates those.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)
                  gc-cons-percentage 0.1)))

;; ---------------------------------------------------------------------------
;; file-name-handler-alist suspension
;; ---------------------------------------------------------------------------
;; Every `load' / `require' walks this alist looking for tramp:/, ange-ftp,
;; jka-compr (.gz/.bz2 decoders), ... handlers.  During startup we don't open
;; any remote/compressed file, so emptying the list speeds up every package
;; require.  Restore it on `emacs-startup-hook' so Tramp/jka-compr work once
;; the user starts opening files.
(defvar fenrir/file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist fenrir/file-name-handler-alist)))

;; ---------------------------------------------------------------------------
;; Package system: defer activation to init.el
;; ---------------------------------------------------------------------------
;; Emacs 27+ auto-runs `package-activate-all' before init.el by default.  We
;; do `(require 'package)' + use-package bootstrap explicitly in init.el, so
;; the implicit pre-init pass is pure duplicated work.  Disable it here.
(setq package-enable-at-startup nil)

;; ---------------------------------------------------------------------------
;; Frame chrome -- set BEFORE the first frame paints
;; ---------------------------------------------------------------------------
;; In a GUI Emacs, calling `menu-bar-mode -1' inside init.el causes the first
;; frame to be born WITH the bars and then torn down once init.el runs --
;; a visible flash and wasted layout work.  Setting these via
;; `default-frame-alist' here means the first frame is constructed without
;; them in the first place.  Harmless in a TUI.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; Suppress implicit frame resize when toolbar/menubar visibility changes --
;; saves several geometry round-trips on GUI startup.
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t)

;; ---------------------------------------------------------------------------
;; Misc startup-time crud
;; ---------------------------------------------------------------------------
(setq site-run-file nil           ; skip /etc/emacs/site-start.d/*.el
      inhibit-default-init t      ; skip /usr/share/emacs/.../default.el
      load-prefer-newer t)        ; prefer foo.el over a stale foo.elc

;; ---------------------------------------------------------------------------
;; Native compilation
;; ---------------------------------------------------------------------------
;; Third-party packages routinely produce harmless redefinition / docstring
;; warnings on first native compile.  Silencing prevents the *Warnings*
;; buffer from popping into focus the first time you open Emacs after a
;; package upgrade.  JIT compilation stays on (background async compile).
;;
;; `native-comp-async-jobs-number' defaults to 1 -- a single background
;; compile worker.  0 means "half the CPU's execution units", so native
;; compilation (JIT and `M-x my/native-compile-config' alike) runs in
;; parallel and post-upgrade compile waves drain much faster.
(setq native-comp-async-report-warnings-errors 'silent
      native-comp-jit-compilation t
      native-comp-async-jobs-number 0)

(provide 'early-init)
;;; early-init.el ends here
