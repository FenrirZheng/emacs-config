;;; init-tags.el --- GNU Global (gtags) create/update/xref via gtags-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; GNU Global integration, rebuilt 2026-07-30 around `gtags-mode' (GNU ELPA,
;; maintained) after the ggtags + ~1000-line hand-rolled stack was judged
;; "almost unusable" -- plan and design decisions in
;; [the toolchain rebuild plan](../tasks/gtags-xref-toolchain.md), operational
;; doc in [TAGS.md](../_doc/TAGS.md).
;;
;; Division of labor:
;;   * `gtags-mode' (one global minor mode) supplies the xref backend and the
;;     on-save `global --single-update' refresh.  Its backend answers only in
;;     buffers under an indexed root and declines silently elsewhere; Eglot
;;     registers its own backend BUFFER-LOCALLY on attach, and buffer-local
;;     `xref-backend-functions' entries run before global ones -- so Eglot
;;     wins whenever a server is live, gtags is the no-LSP fallback.  Both
;;     facts verified in source (gtags-mode 1.9.5 / eglot) before adoption.
;;   * This module keeps only the thin guard layer those packages lack:
;;     daemon-wide GTAGSCONF/GTAGSLABEL env, a root-guarded validated create,
;;     a nested-index diagnose command, and the etags-prompt suppression.

;;; Code:

;; --- Environment, daemon-wide -----------------------------------------------
;; Every gtags/global subprocess -- create, `global -u', the on-save
;; single-update, and every xref query -- inherits `process-environment', so
;; setting these ONCE here replaces the old per-call injection plumbing (whose
;; "one call site forgot the env" bug class caused the 2.5 MB -> 3.85 GB
;; re-bloat incident: a bare `global -u' re-traversed without the skip list).
;;
;;   GTAGSCONF  -> the tracked [gtags.conf](../gtags.conf): system copy plus an
;;                 extended common skip list (node_modules/ vendor/ dist/ ...).
;;                 Falls back to the Debian system conf if the tracked copy is
;;                 missing so a half-set-up checkout still works.
;;   GTAGSLABEL -> native-pygments: gtags' built-in parser is C/Java/PHP-only
;;                 (Go/Python/TS-blind), and plain ctags labels miss TS too.
;;                 Only CREATE consumes the label (gtags records it in the DB;
;;                 updates reuse the recorded one), but exporting it always is
;;                 harmless -- only the gtags/global family reads these vars.
(let ((conf (expand-file-name "gtags.conf" user-emacs-directory)))
  (setenv "GTAGSCONF" (if (file-exists-p conf) conf "/etc/gtags/gtags.conf"))
  (setenv "GTAGSLABEL" "native-pygments"))

;; --- gtags-mode: xref backend + on-save incremental update ------------------
;; Features trimmed to the two plan pillars:
;;   xref  -- the backend (import layer).
;;   hooks -- after-save `global --single-update <file>' (update layer): per
;;            file, no re-traversal, so the index tracks edits automatically.
;; Deliberately NOT enabled:
;;   project    -- would prepend a gtags project backend onto
;;                 `project-find-functions', fighting the tuned project.el
;;                 setup in init-defaults ($HOME-repo ignore, .project marks).
;;   completion -- a global capf; Corfu/Cape composition is curated in
;;                 init-corfu and doesn't want tag noise added everywhere.
;;   imenu      -- a :before-until advice that would REPLACE the (better)
;;                 tree-sitter/LSP imenu in every indexed buffer.
(use-package gtags-mode
  :demand t                     ; global mode: must be on before any M-. needs it
  :custom (gtags-mode-features '(xref hooks))   ; read at enable time, set first
  :config (gtags-mode 1))

;; Defensive: keep the etags fallback's globals empty so a stray
;; `visit-tags-table' can't seed them with a binary GTAGS file or a Java
;; source ("File CaptchaType.java is not a valid tags table").  Both default
;; to nil already; the explicit setq-default documents the invariant.
(setq-default tags-file-name nil
              tags-table-list nil)

;; `etags--xref-backend' is the always-present tail of `xref-backend-functions'.
;; In a buffer with no LSP and no gtags index it is still reached, and its
;; methods call `visit-tags-table-buffer', whose last resort -- after
;; `tags-file-name'/`tags-table-list' (nil'd above) and the TAGS-file walk all
;; miss -- is a `read-file-name' "Visit tags table" prompt meaningless outside
;; a 1990s etags workflow.  Replace exactly that last resort with a one-line
;; pointer at the build key; every legitimate path through the function (an
;; explicit table argument, a real TAGS file found on disk) is untouched.
(define-advice visit-tags-table-buffer
    (:around (orig &rest args) fenrir/gtags-instead-of-prompt)
  "Turn etags' last-resort file prompt into a gtags build hint."
  (cl-letf (((symbol-function 'read-file-name)
             (lambda (&rest _)
               (user-error
                (substitute-command-keys
                 "No tags here -- \\[fenrir/gtags-build] builds a gtags index \
(or open the file under a live LSP)")))))
    (apply orig args)))

;; --- Root guard --------------------------------------------------------------
(defvar fenrir/gtags-forbidden-roots
  (list (expand-file-name "~/")        ; the dotfiles repo -- $HOME is a git repo
        "/"                            ; filesystem root
        "/tmp/" "/usr/" "/etc/" "/var/" "/opt/")
  "Directories `fenrir/gtags-build' must never index.
project.el's `project-try-vc' can degenerate to $HOME (the dotfiles repo) or
`/' when no real VCS root is found; a gtags walk there is runaway.  Entries
are `expand-file-name'd, slash-terminated absolute paths, compared exactly.")

(defun fenrir/gtags--project-root ()
  "Current project.el root as a slash-terminated absolute path, or nil.
nil also when the root is in `fenrir/gtags-forbidden-roots'."
  (when-let* ((proj (project-current nil)))
    (let ((root (file-name-as-directory (expand-file-name (project-root proj)))))
      (unless (member root fenrir/gtags-forbidden-roots)
        root))))

;; --- Create (async, validated) ----------------------------------------------
;; `gtags-mode-create' exists but its sentinel is fixed -- no hook point for
;; the post-create validation invariant #4 of the plan ("never leave a 0-byte
;; index corpse").  So create is our own `make-process' (env inherited from
;; the setenv above); everything downstream of a finished build is still
;; gtags-mode's.  The 0-byte corpse is a real failure mode: a crashed parser
;; helper (missing interpreter, broken PATH) leaves GTAGS/GRTAGS/GPATH stubs
;; that every later `global -u' rejects with "GTAGS seems corrupted".

(defconst fenrir/gtags--index-files '("GTAGS" "GRTAGS" "GPATH")
  "Files a gtags run creates at the index root.")

(defvar fenrir/gtags--build-process nil
  "Live create process, or nil.  Re-entrancy guard: one build at a time.")

(defun fenrir/gtags--wipe-index (root)
  "Delete ROOT's GTAGS/GRTAGS/GPATH."
  (dolist (f fenrir/gtags--index-files)
    (let ((path (expand-file-name f root)))
      (when (file-exists-p path) (ignore-errors (delete-file path))))))

(defun fenrir/gtags--index-valid-p (root)
  "Non-nil when ROOT's GTAGS is non-empty and `global' accepts it."
  (let ((gtags (expand-file-name "GTAGS" root)))
    (and (file-exists-p gtags)
         (> (or (file-attribute-size (file-attributes gtags)) 0) 0)
         (let ((default-directory root))
           (eq 0 (ignore-errors
                   (call-process "global" nil nil nil "--completion" "")))))))

(declare-function gtags-mode--update-buffers-plist "gtags-mode")

(defun fenrir/gtags--build-sentinel (root buf)
  "Sentinel closure body for the create process at ROOT with output BUF."
  (lambda (proc _event)
    (unless (process-live-p proc)
      (setq fenrir/gtags--build-process nil)
      (let ((disp (abbreviate-file-name root))
            (output (when (buffer-live-p buf)
                      (with-current-buffer buf
                        (string-trim (buffer-string))))))
        (when (buffer-live-p buf) (kill-buffer buf))
        (cond
         ((not (eq 0 (process-exit-status proc)))
          (fenrir/gtags--wipe-index root)   ; never leave a corpse
          (message "gtags failed in %s (exit %d): %s"
                   disp (process-exit-status proc)
                   (car (last (string-lines (or output "") t)))))
         ((not (fenrir/gtags--index-valid-p root))
          (fenrir/gtags--wipe-index root)
          (message "gtags produced a corrupt/empty index in %s -- wiped.  \
Parser failure?  Check `python3 -m pygments' and GTAGSLABEL" disp))
         (t
          ;; Let open buffers (whose backend cached "no index here") re-resolve
          ;; against the fresh DB.
          (when (fboundp 'gtags-mode--update-buffers-plist)
            (gtags-mode--update-buffers-plist))
          (message "gtags index built in %s" disp)))))))

(defun fenrir/gtags-build (root)
  "Build a GTAGS index at ROOT asynchronously, with validation.
Interactively, ROOT defaults to the current project root; the prompt is the
last chance to redirect a potentially-huge walk.  Refuses
`fenrir/gtags-forbidden-roots'.  A pre-existing 0-byte stub index is wiped
first (gtags refuses to overwrite it); on failure or an invalid result the
stubs are wiped again so no corpse survives."
  (interactive
   (list (read-directory-name "gtags index root: "
                              (or (fenrir/gtags--project-root) default-directory)
                              nil t)))
  (unless (and (executable-find "gtags") (executable-find "global"))
    (user-error "GNU Global not found (Debian: sudo apt install global)"))
  (when (process-live-p fenrir/gtags--build-process)
    (user-error "A gtags build is already running"))
  (let ((root (file-name-as-directory (expand-file-name root))))
    (when (member root fenrir/gtags-forbidden-roots)
      (user-error "Refusing to index %s (forbidden root)" root))
    (let ((gtags (expand-file-name "GTAGS" root)))
      (when (and (file-exists-p gtags)
                 (eq 0 (or (file-attribute-size (file-attributes gtags)) 0)))
        (fenrir/gtags--wipe-index root)
        (message "Wiped 0-byte GTAGS stub in %s" (abbreviate-file-name root))))
    (let* ((default-directory root)
           (buf (generate-new-buffer " *fenrir-gtags*")))
      (setq fenrir/gtags--build-process
            (make-process :name "fenrir-gtags"
                          :buffer buf
                          :command '("gtags")
                          :sentinel (fenrir/gtags--build-sentinel root buf)))
      (message "gtags: building index in %s ..." (abbreviate-file-name root)))))

;; --- Diagnose: nested indexes shadow the root -------------------------------
(defun fenrir/gtags-diagnose (dir)
  "List every GTAGS index under DIR and offer to delete the nested ones.
GNU Global resolves against the NEAREST ancestor GTAGS, so an index in a
subdirectory silently hides the root index for every file beneath it (the
backend/GTAGS-shadowed-coinsasia/GTAGS bug).  Interactively DIR defaults to
the project root; prefix arg prompts."
  (interactive
   (list (let ((default (or (fenrir/gtags--project-root)
                            (expand-file-name default-directory))))
           (if current-prefix-arg
               (read-directory-name "Diagnose GTAGS under: " default default t)
             default))))
  (let* ((root (file-name-as-directory (expand-file-name dir)))
         (all (let (acc)
                (dolist (f (ignore-errors
                             (directory-files-recursively
                              root (rx bos "GTAGS" eos) nil
                              ;; Skip heavy/vendored trees: an index inside
                              ;; node_modules/ shadows nothing the user visits.
                              (lambda (d)
                                (not (member (file-name-nondirectory d)
                                             '(".git" "node_modules" "vendor"
                                               "target" ".venv" "venv"
                                               "dist" "build")))))))
                  (push (file-name-as-directory (file-name-directory f)) acc))
                (sort acc #'string<)))       ; shallow-first: root before shadows
         (nested (remove root all)))
    (cond
     ((null all)
      (message "No GTAGS index under %s" (abbreviate-file-name root)))
     ((null nested)
      (message "Single GTAGS index at %s -- no shadowing"
               (abbreviate-file-name (car all))))
     (t
      (with-current-buffer (get-buffer-create "*gtags-diagnose*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (dolist (d all)
            (let ((attr (file-attributes (expand-file-name "GTAGS" d))))
              (insert (format "%-8s %9s  %s\n"
                              (if (equal d root) "[root]" "[nested]")
                              (if attr (file-size-human-readable
                                        (file-attribute-size attr))
                                "?")
                              (abbreviate-file-name d)))))
          (insert "\n[nested] indexes SHADOW the root for files beneath them.\n")
          (goto-char (point-min))
          (special-mode))
        (display-buffer (current-buffer)))
      (when (yes-or-no-p (format "Delete %d nested GTAGS index%s? "
                                 (length nested)
                                 (if (= (length nested) 1) "" "es")))
        (dolist (d nested) (fenrir/gtags--wipe-index d))
        (when (fboundp 'gtags-mode--update-buffers-plist)
          (gtags-mode--update-buffers-plist))
        (message "Deleted %d nested index%s -- %s is authoritative"
                 (length nested) (if (= (length nested) 1) "" "es")
                 (abbreviate-file-name root)))))))

;; --- Entry points ------------------------------------------------------------
;; `C-c g' prefix: build / update / diagnose.  Navigation itself has no keys
;; here on purpose -- it is plain xref (M-. / M-? / M-,), backend-dispatched.
(defvar-keymap fenrir/gtags-map
  :doc "gtags index management."
  "g" #'fenrir/gtags-build
  "u" #'gtags-mode-update            ; bulk `global -u' (async), after pulls etc.
  "d" #'fenrir/gtags-diagnose)
(keymap-global-set "C-c g" fenrir/gtags-map)

(provide 'init-tags)
;;; init-tags.el ends here
