;;; init-snippets.el --- Templates: TempEl (primary) + YASnippet (Eglot LSP backend) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 6 of the pre-split monolithic init.el (see git log for the move).
;;
;; Two-engine split (decided 2026-06-01 after a maintenance/built-in survey):
;;
;;   * TempEl -- THE engine for hand-written templates.  On GNU ELPA, actively
;;     maintained by minad (same author as vertico / corfu / consult /
;;     orderless, all already in this config), and it reuses the syntax of the
;;     built-in `tempo.el' -- so it is the closest "official-flavoured" choice
;;     short of using core tempo/skeleton directly.  Templates live in the
;;     `templates' file at the repo root (tempel's default `tempel-path').
;;     Surfaced through `completion-at-point-functions', so it rides the exact
;;     same `consult-completion-in-region' (Vertico minibuffer) path as every
;;     other in-buffer completion -- no Corfu popup required (global-corfu-mode
;;     is intentionally off; see init-corfu.el).
;;
;;   * YASnippet -- kept ONLY as Eglot's LSP snippet expander, NOT for
;;     hand-written snippets.  When a language server returns a snippet-style
;;     completion (e.g. jdtls / gopls completing a call with parameter
;;     placeholders), Eglot expands it via `yas-expand-snippet' IFF
;;     `yas-minor-mode' is live in the buffer (see `eglot--snippet-expansion-fn').
;;     So we enable it narrowly on `eglot-managed-mode-hook' instead of the old
;;     `yas-global-mode' -- yasnippet stays dormant everywhere Eglot isn't
;;     managing the buffer.  With no snippet tables loaded (we no longer install
;;     `yasnippet-snippets'), yas-minor-mode's TAB is a harmless pass-through to
;;     the normal indent/complete command.
;;
;; The former `yasnippet-snippets' collection block was dropped -- hand-written
;; snippets are TempEl's job now.  The package may still sit in `elpa/' from the
;; old setup; `M-x package-delete RET yasnippet-snippets' removes it if desired.
;;
;; FIRST INSTALL: `tempel' is not bundled and won't be in `elpa/' on a fresh
;; clone -- run `M-x my/package-refresh' then restart so the archive resolves it
;; (the repo never refreshes at startup; see init.el).

;;; Code:

(use-package tempel
  :custom
  ;; Point tempel at the tracked `templates' file at the repo root.  This is a
  ;; DELIBERATE override of no-littering, which otherwise redirects the default
  ;; `tempel-path' to `etc/tempel/templates.eld' (gitignored) -- but our
  ;; templates are hand-authored CONFIG we want version-controlled, not state.
  (tempel-path (expand-file-name "templates" user-emacs-directory))
  ;; `M-+' list templates for the current mode and expand the chosen one;
  ;; `M-*' insert a template by name (completing-read -> Vertico browse).
  ;; (`M-*' was legacy `pop-tag-mark'; unused here -- navigation is on xref's
  ;; `M-,'.)  Inside an active template, TAB / S-TAB walk the fields.
  :bind (("M-+" . tempel-complete)
         ("M-*" . tempel-insert)
         :map tempel-map
         ("TAB"       . tempel-next)
         ("<tab>"     . tempel-next)
         ("S-TAB"     . tempel-previous)
         ("<backtab>" . tempel-previous))
  :init
  ;; Add `tempel-expand' to capf as the FIRST function so C-<tab> / C-M-i (the
  ;; `completion-at-point' keys; M-TAB is swallowed by GNOME -- see init-corfu.el)
  ;; expands a template when the word before point is an exact trigger name, and
  ;; otherwise falls straight through to Eglot / cape (tempel-expand returns nil
  ;; when it doesn't match -- safe to put ahead of the LSP backend).  Use
  ;; `tempel-expand' (low-noise: only fires on an exact trigger) rather than
  ;; `tempel-complete' here so ordinary completion lists aren't flooded with
  ;; every template name; reach the full browse list via `M-+' / `M-*' instead.
  (defun fenrir/tempel-setup-capf ()
    (setq-local completion-at-point-functions
                (cons #'tempel-expand completion-at-point-functions)))
  (add-hook 'prog-mode-hook #'fenrir/tempel-setup-capf)
  (add-hook 'text-mode-hook #'fenrir/tempel-setup-capf)
  (add-hook 'conf-mode-hook #'fenrir/tempel-setup-capf))

;; tempel-collection: a large community library of ready-made TempEl templates
;; for many major modes (the TempEl analogue of yasnippet-snippets, on MELPA).
;; Loading it adds its bundled file to `tempel-path', so it would coexist with
;; your own `templates' file.  Left OFF by default to keep the snippet set small,
;; fully-owned, and dependency-light (your stated built-in/minimal preference).
;; To opt in: uncomment, `M-x my/package-refresh', restart.
;; (use-package tempel-collection
;;   :after tempel)

;; YASnippet -- Eglot LSP snippet backend ONLY (see header).  No global mode, no
;; snippet collection: enabled per-buffer wherever Eglot takes over.
(use-package yasnippet
  :hook (eglot-managed-mode . yas-minor-mode))

(provide 'init-snippets)
;;; init-snippets.el ends here
