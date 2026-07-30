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
  (recentf-max-menu-items 25)
  :config
  ;; Without these, `consult-buffer's "Recent files" group fills up with:
  ;;   * `var/' state files (history, places, bookmarks, transient ...)
  ;;     -- no-littering redirects them here, so opening Emacs once is
  ;;     enough to seed recentf with a dozen irrelevant entries.
  ;;   * `etc/' config-ish state (TLS server cache, ...) -- same shape.
  ;;   * TRAMP `/sudo:' paths -- selecting one tries to re-elevate, which
  ;;     prompts for the password mid-buffer-switch.
  ;;   * `COMMIT_EDITMSG' -- Magit re-opens this on every commit; the file
  ;;     never has stable contents and re-opening it from recentf is noise.
  ;; no-littering exposes `recentf-expand-file-name' for the var/etc paths;
  ;; using it (vs. raw `no-littering-var-directory') normalises the form
  ;; recentf stores internally so exclusion matches reliably.
  (add-to-list 'recentf-exclude
               (recentf-expand-file-name no-littering-var-directory))
  (add-to-list 'recentf-exclude
               (recentf-expand-file-name no-littering-etc-directory))
  (add-to-list 'recentf-exclude "\\`/sudo:")
  (add-to-list 'recentf-exclude "COMMIT_EDITMSG\\'"))

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
         ("C-x r b" . consult-bookmark)       ; bookmark jump with preview
         ;; search
         ("M-y"     . consult-yank-pop)       ; browse the kill-ring
         ("C-s"     . consult-line)           ; search lines in this buffer
         ("M-s L"   . consult-line-multi)     ; same, across all open buffers
         ("M-s k"   . consult-keep-lines)     ; filter buffer to matching lines
         ("M-s u"   . consult-focus-lines)    ; hide non-matching lines (toggle)
         ;; goto -- `M-g' is the standard prefix for "jump to":
         ("M-g g"   . consult-goto-line)
         ("M-g i"   . consult-imenu)          ; jump to a definition in this file
         ("M-g I"   . consult-imenu-multi)    ; same, across project buffers
         ("M-g o"   . consult-outline)        ; jump to an outline heading
         ("M-g m"   . consult-mark)           ; jump to a recent mark in buffer
         ("M-g k"   . consult-global-mark)    ; jump to a recent mark globally
         ("M-g f"   . consult-flymake)        ; list diagnostics with preview
         ;; project search
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
  (setq completion-in-region-function #'consult-completion-in-region)
  :config
  ;; Debounce live preview for the expensive commands.  Default behaviour
  ;; re-runs ripgrep / re-renders the previewed buffer on every keystroke;
  ;; on a large project that's enough latency to feel laggy.  `:debounce 0.2'
  ;; waits 200ms of input idle before previewing; `any' means any key counts
  ;; as input (the alternative `'any' would also re-trigger on the
  ;; manual-preview key, which we don't want).
  ;;
  ;; Only command-level entries listed -- the `consult--source-*' variables
  ;; (bookmark, recent-file, file-register, project-recent-file) are
  ;; autoloaded lazily by `consult-buffer' and don't exist at the time this
  ;; `:config' block runs, so passing them here triggers
  ;; "neither a command nor a source" warnings.  The `consult-buffer' multi-
  ;; source flow has cheap buffer/file previewing anyway -- the commands
  ;; below are the ones that actually pay ripgrep / file-read cost per
  ;; keystroke.
  (consult-customize
   consult-ripgrep consult-grep consult-git-grep consult-find
   consult-bookmark consult-recent-file
   :preview-key '(:debounce 0.2 any)))

;; `:demand t' -- load embark at startup rather than waiting for C-. / C-; /
;; C-h B.  Load-bearing for the `prefix-help-command' wiring in
;; init-defaults.el: that `(with-eval-after-load 'embark ...)' body doesn't
;; run until embark is loaded, so without :demand, C-h after a prefix key
;; still falls through to the *Help* buffer (not the vertico-searchable
;; embark one) until embark happens to load some other way first in the
;; session.
(use-package embark
  :demand t
  :bind (("C-." . embark-act)            ; act on the thing at point / candidate
         ("C-;" . embark-dwim)           ; "do what I mean" -- default action
         ("C-h B" . embark-bindings)))   ; like `describe-bindings' via completing-read

;; Glue: when you `embark-act' inside a consult command, show the export buffer
;; using consult's nicer formatting.
(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; Delete entries from the mark rings from inside `consult-mark' /
;; `consult-global-mark' (M-g m / M-g k): `C-. d' on a candidate.  Neither
;; consult nor embark ships a remove action -- the candidate list is a
;; read-only view of the rings.
;;
;; Two non-obvious constraints shape the implementation:
;;   * The action MUST be a plain one-argument function, NOT a command.
;;     embark runs command actions through minibuffer re-injection, which
;;     strips text properties (`substring-no-properties' in `embark--act')
;;     -- and the marker we need lives in the candidate's `consult-location'
;;     property.  Non-command functions receive the raw propertized string,
;;     the same mechanism embark-consult's own `embark-consult-goto-location'
;;     relies on.
;;   * `consult-mark' candidates include the CURRENT mark (`mark-marker')
;;     on top of the `mark-ring' entries, so that one is cleared with
;;     `set-marker' rather than a ring removal.
;;
;; `consult-line' / `consult-outline' share the `consult-location' category;
;; pressing d there matches no ring entry and is a harmless no-op.  The open
;; minibuffer list does NOT refresh after a delete (consult computes its
;; candidates once) -- reopen M-g m to see the shrunken ring.
(defun fenrir/mark-ring-delete (cand)
  "Remove CAND's position from its buffer's mark rings.
CAND is a `consult-location' candidate string.  Drops every marker at
that position from the buffer-local `mark-ring' and the global
`global-mark-ring', and clears the buffer's current mark if it sits
there too."
  (when-let* ((marker (car (consult--get-location cand)))
              (buf (marker-buffer marker))
              (pos (marker-position marker)))
    (let ((at-pos (lambda (m) (and (markerp m)
                                   (eq (marker-buffer m) buf)
                                   (eql (marker-position m) pos)))))
      (with-current-buffer buf
        (setq mark-ring (seq-remove at-pos mark-ring))
        (when (funcall at-pos (mark-marker))
          (set-marker (mark-marker) nil)))
      (setq global-mark-ring (seq-remove at-pos global-mark-ring)))
    (message "Removed mark at %s:%d" (buffer-name buf) pos)))

(with-eval-after-load 'embark
  (defvar-keymap fenrir/embark-consult-location-map
    :doc "Embark actions for `consult-location' candidates (marks, lines)."
    :parent embark-general-map
    "d" #'fenrir/mark-ring-delete)
  ;; Entry format is (TYPE KEYMAP-SYMBOL...) -- a list, not a dotted pair
  ;; (`embark--raw-action-keymap' mapcars `symbol-value' over the cdr).
  (setf (alist-get 'consult-location embark-keymap-alist)
        (list 'fenrir/embark-consult-location-map)))

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
