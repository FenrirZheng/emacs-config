;;; init-completion.el --- Minibuffer / completion UI (Vertico ecosystem) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 4 of the pre-split monolithic init.el (see git log for the move).
;; Five small, orthogonal packages that together replace ido/ivy/helm:
;;   vertico    -- vertical candidate list in the minibuffer
;;   orderless  -- space-separated, any-order fuzzy matching
;;   marginalia -- annotations (docstrings, file sizes, ...) beside candidates
;;   consult    -- richer commands: buffer switch, line search, project grep
;;   embark     -- a "context menu" you can invoke on the current candidate
;; Plus the built-in helpers (savehist, recentf, saveplace) that the ecosystem
;; pulls double-duty from, and wgrep for editable grep buffers.

;;; Code:

(use-package vertico
  :init (vertico-mode 1)
  :custom
  (vertico-cycle t))                     ; wrap around at top/bottom

;; vertico-directory: an extension that ships INSIDE the vertico package -- so
;; `:ensure nil'.  Makes RET/DEL operate on whole path components when you're
;; editing a file name in the minibuffer (RET descends into the dir under
;; point; DEL deletes back to the previous `/').
(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
              ("RET"   . vertico-directory-enter)
              ("DEL"   . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  ;; Collapse the "//" / "~/" shadow when you type an absolute path mid-prompt.
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; Persist minibuffer history; also lets Vertico put recent picks first.
;; `savehist-additional-variables' bolts on the kill-ring and the two search
;; rings -- so M-y / C-s history survive a restart, not just M-x history.
(use-package savehist
  :ensure nil
  :init (savehist-mode 1)
  :custom
  (savehist-additional-variables '(kill-ring search-ring regexp-search-ring)))

;; recentf (built-in): tracks recently-opened files.  Once enabled,
;; `consult-buffer' (C-x b) gains a "Recent files" virtual source -- so the
;; same key that switches buffers also re-opens recent files, no separate
;; "recentf-open" command needed.  no-littering already redirected the
;; recentf save file out of `~/.emacs.d/' root, so no path tweak required.
(use-package recentf
  :ensure nil
  :init (recentf-mode 1)
  :custom
  (recentf-max-saved-items 200)
  (recentf-max-menu-items 25))

;; saveplace (built-in): remembers point position per file across sessions.
;; Reopen a file and the cursor lands where you left off -- no need to
;; manually `C-s' for your spot.  Pairs naturally with `recentf' above
;; (recent files come back via `consult-buffer'; opening them lands at the
;; right line).  no-littering already redirects the on-disk state file
;; under `var/places/'.
(use-package saveplace
  :ensure nil
  :init (save-place-mode 1))

(use-package orderless
  :custom
  ;; Use orderless for ordinary completion; keep the built-in file-name style
  ;; so partial path components (e.g. "/u/s/b" -> /usr/share/bin) still work.
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package consult
  :bind (;; C-x bindings -- `C-x b' is reserved for ibuffer (see section 2),
         ;; so the consult fuzzy switcher lives on `C-x B' (shift) instead.
         ("C-x B"   . consult-buffer)         ; switch buffer (with previews)
         ("C-x 4 b" . consult-buffer-other-window)
         ("C-x p b" . consult-project-buffer) ; project-scoped buffer switch
         ;; search
         ("M-y"     . consult-yank-pop)       ; browse the kill-ring
         ("C-s"     . consult-line)           ; search lines in this buffer
         ("M-g g"   . consult-goto-line)
         ("M-g i"   . consult-imenu)          ; jump to a definition in this file
         ("M-s r"   . consult-ripgrep)        ; grep across the project
         ("M-s f"   . consult-find))          ; find files by name
  :custom
  ;; Let `consult-line' etc. drive the live preview at this key:
  (consult-narrow-key "<")
  :init
  ;; Route in-buffer completion (`M-TAB' / `C-M-i' / `completion-at-point')
  ;; to the minibuffer via Vertico, instead of corfu's at-point popup.
  ;; See the section-5 header comment for the rationale.  `:init' (rather
  ;; than `:config') so the override is in place before any buffer's first
  ;; completion call, even if consult itself loads lazily afterwards.
  (setq completion-in-region-function #'consult-completion-in-region))

(use-package embark
  :bind (("C-." . embark-act)            ; act on the thing at point / candidate
         ("C-;" . embark-dwim)           ; "do what I mean" -- default action
         ("C-h B" . embark-bindings)))   ; like `describe-bindings' via completing-read

;; Glue: when you `embark-act' inside a consult command, show the export buffer
;; using consult's nicer formatting.
(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; wgrep: make grep / ripgrep result buffers editable, then commit the edits
;; back to every file at once.  The payoff with the setup above: run
;; `consult-ripgrep' (M-s r), `embark-export' (C-. then E) the matches into a
;; grep buffer, `C-c C-p' to make it writable, edit freely, `C-c C-c' to save
;; -- a project-wide search-and-replace with ordinary undo on each file.
(use-package wgrep
  :defer t                               ; loads when you C-c C-p in a grep buffer
  :custom (wgrep-auto-save-buffer t))    ; write edited files out immediately

(provide 'init-completion)
;;; init-completion.el ends here
