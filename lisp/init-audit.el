;;; init-audit.el --- Self-audit commands for this config  -*- lexical-binding: t; -*-

;;; Commentary:

;; Two "is this config still honest?" reports.  Neither is wired to a key by
;; default; both are plain `M-x' commands (Tier 3), reachable from the `<f5>'
;; hub's escape-hatch column.
;;
;;   `fenrir/features-audit'      -- does FEATURES.md still describe the keys?
;;   `fenrir/package-usage-audit' -- which installed packages do I never use?
;;
;; Both are deliberately TEXTUAL heuristics over the config sources rather
;; than introspection of live keymaps: the question is "does the documented
;; story match the file I would edit", and a keymap walk answers a different
;; one (it also drags in every package's own bindings).  They are advisory —
;; read the output, do not act on it mechanically.

;;; Code:

(require 'subr-x)

;; --------------------------------------------------------------------------
;; FEATURES.md drift
;; --------------------------------------------------------------------------

(defvar fenrir/features-audit-source
  (expand-file-name "lisp/init-keys.el" user-emacs-directory)
  "The routing layer whose bound commands FEATURES.md is supposed to describe.")

(defvar fenrir/features-audit-doc
  (expand-file-name "FEATURES.md" user-emacs-directory)
  "The user-facing key/feature reference audited against the routing layer.")

(defun fenrir/features-audit--file-string (file)
  "Return the contents of FILE as a string, or nil when it is missing."
  (when (file-readable-p file)
    (with-temp-buffer (insert-file-contents file) (buffer-string))))

(defun fenrir/features-audit--bound-commands (text)
  "Collect command symbols routed by TEXT (the source of `init-keys.el').
Covers the three shapes that file uses: `#'command' after a key form,
transient entries `(\"k\" \"label\" command ...)', and the `(\"key\" . command)'
cells of `use-package :bind'.  Heuristic on purpose — a false hit costs one
line of report noise."
  (let (out)
    (dolist (re '("#'\\([a-zA-Z0-9/-]+\\)"                       ; (kbd ..) #'cmd
                  "(\"[^\"]*\" +\"[^\"]*\" +\\([a-zA-Z0-9/-]+\\)" ; transient entry
                  "(\"[^\"]*\" +\\. +\\([a-zA-Z0-9/-]+\\))"))     ; :bind cell
      (let ((start 0))
        (while (string-match re text start)
          (setq start (match-end 0))
          (push (match-string 1 text) out))))
    (seq-uniq (seq-filter (lambda (name) (commandp (intern-soft name))) out))))

(defun fenrir/features-audit--documented-commands (text)
  "Collect command names mentioned in TEXT (the FEATURES.md source).
Any backtick-quoted token that names a live command counts as documented."
  (let (out (start 0))
    (while (string-match "`\\([a-zA-Z0-9/+-]+\\)`" text start)
      (setq start (match-end 0))
      (push (match-string 1 text) out))
    (seq-uniq (seq-filter (lambda (name) (commandp (intern-soft name))) out))))

;;;###autoload
(defun fenrir/features-audit ()
  "Diff the commands routed by `init-keys.el' against FEATURES.md.
Reports both directions of drift: bound-but-undocumented (the usual one —
a key was added and the table was not updated) and documented-but-unbound
\(a key was removed or renamed).  String matching, so treat the output as a
list of things to LOOK at, not as errors."
  (interactive)
  (let* ((src (or (fenrir/features-audit--file-string fenrir/features-audit-source)
                  (user-error "Cannot read %s" fenrir/features-audit-source)))
         (doc (or (fenrir/features-audit--file-string fenrir/features-audit-doc)
                  (user-error "Cannot read %s" fenrir/features-audit-doc)))
         (bound      (fenrir/features-audit--bound-commands src))
         (documented (fenrir/features-audit--documented-commands doc))
         (missing (seq-remove (lambda (c) (member c documented)) bound))
         ;; For the other direction, matching against `init-keys.el' alone
         ;; produces ~200 hits: FEATURES.md legitimately documents commands
         ;; bound in their OWNING module (that is the whole point of the
         ;; routing layer).  So diff against every hand-authored source
         ;; instead -- what is left is documented by no file at all.
         (all-src (mapconcat #'fenrir/features-audit--file-string
                             (append (directory-files
                                      (expand-file-name "lisp" user-emacs-directory)
                                      t "\\.el\\'")
                                     (directory-files
                                      (expand-file-name "lisp/languages" user-emacs-directory)
                                      t "\\.el\\'"))
                             "\n"))
         (stale   (seq-remove (lambda (c) (string-match-p (regexp-quote c) all-src))
                              documented)))
    (with-current-buffer (get-buffer-create "*features-audit*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "FEATURES.md drift audit\n"
                "=======================\n\n"
                (format "routing layer : %s\n" fenrir/features-audit-source)
                (format "documentation : %s\n\n" fenrir/features-audit-doc)
                "Heuristic string matching; a command documented only by prose\n"
                "(no backticks) reads as undocumented here.  Advisory, not a test.\n\n")
        (insert (format "Bound in init-keys.el but NOT in FEATURES.md (%d):\n" (length missing)))
        (dolist (c (sort missing #'string<)) (insert "  " c "\n"))
        (insert (format "\nIn FEATURES.md but named by NO module under lisp/ (%d):\n"
                        (length stale)))
        (insert "  (built-in commands documented as plain Emacs keys are expected here)\n")
        (dolist (c (sort stale #'string<)) (insert "  " c "\n"))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

;; --------------------------------------------------------------------------
;; keyfreq-driven package usage
;; --------------------------------------------------------------------------

(defun fenrir/package-usage-audit--declared-packages ()
  "Every package name declared with `use-package' under `lisp/'.
Read from the SOURCES, so a package that is installed but no longer
declared does not show up (that is `package-autoremove''s job)."
  (let ((files (append (directory-files (expand-file-name "lisp" user-emacs-directory)
                                        t "\\.el\\'")
                       (directory-files (expand-file-name "lisp/languages" user-emacs-directory)
                                        t "\\.el\\'")))
        out)
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^(use-package +\\([a-zA-Z0-9/+._-]+\\)" nil t)
          (push (match-string-no-properties 1) out))))
    (seq-uniq out)))

(defun fenrir/package-usage-audit--package-of (command)
  "Best-effort: the package COMMAND was defined in, as a string, or nil.
Uses `symbol-file', which knows both loaded definitions and autoloads, then
takes the elpa/ directory name minus its version suffix."
  ;; `symbol-file' may return a bare "ibuffer" (a preloaded built-in with no
  ;; directory component), hence the `file-name-directory' guard.
  (when-let* ((file (ignore-errors (symbol-file command 'defun)))
              (dir  (file-name-directory file))
              (base (file-name-nondirectory (directory-file-name dir))))
    (if (string-match "\\`\\(.+?\\)-[0-9][0-9.]*\\'" base)
        (match-string 1 base)
      ;; Not under elpa/ (built-in or lisp/): fall back to the file name.
      (file-name-base file))))

;;;###autoload
(defun fenrir/package-usage-audit ()
  "List `use-package'd packages with no command usage recorded by keyfreq.
Merges the on-disk `keyfreq-file' with the running session's table, maps each
used command to its defining package, and reports the declared packages that
never contributed one.

CAVEATS, read them before uninstalling anything: keyfreq only counts
INTERACTIVE COMMANDS.  A package that works through hooks, advice, minor
modes enabled at startup, faces, a completion backend, a `capf', an xref
backend or an apheleia formatter registers zero commands and will be listed
here while being load-bearing (no-littering, ws-butler, orderless, apheleia,
doom-themes ... are all expected false positives).  The list is a place to
start looking, never a prune script."
  (interactive)
  (require 'keyfreq)
  (let ((table (make-hash-table :test 'equal))
        (used (make-hash-table :test 'equal))
        (declared (fenrir/package-usage-audit--declared-packages))
        (total 0))
    ;; Session counts first, then whatever the autosave already flushed.
    (maphash (lambda (k v) (puthash k v table)) keyfreq-table)
    (ignore-errors (keyfreq-table-load table))
    (maphash (lambda (k v)
               (let ((command (cdr k)))
                 (setq total (+ total v))
                 (when-let ((pkg (fenrir/package-usage-audit--package-of command)))
                   (puthash pkg (+ (gethash pkg used 0) v) used))))
             table)
    (let ((unused (sort (seq-remove (lambda (p) (gethash p used)) declared) #'string<))
          (ranked (sort (let (acc) (maphash (lambda (k v) (push (cons k v) acc)) used) acc)
                        (lambda (a b) (> (cdr a) (cdr b))))))
      (with-current-buffer (get-buffer-create "*package-usage-audit*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Package usage audit (keyfreq)\n"
                  "=============================\n\n"
                  (format "%d command invocations recorded, %d packages declared.\n\n"
                          total (length declared))
                  "CAVEAT: keyfreq counts interactive commands only.  Packages that act\n"
                  "through hooks, advice, faces, capfs, xref/apheleia backends or a mode\n"
                  "enabled at startup record NOTHING and appear \"unused\" below while\n"
                  "being load-bearing.  Investigate before removing anything.\n\n")
          (insert (format "Declared but no recorded command usage (%d):\n" (length unused)))
          (dolist (p unused) (insert "  " p "\n"))
          (insert "\nMost-used packages, by recorded invocations:\n")
          (dolist (cell (seq-take ranked 25))
            (insert (format "  %6d  %s\n" (cdr cell) (car cell))))
          (goto-char (point-min))
          (special-mode))
        (display-buffer (current-buffer))))))

(provide 'init-audit)
;;; init-audit.el ends here
