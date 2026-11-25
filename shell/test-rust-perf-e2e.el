;;; test-rust-perf-e2e.el --- Opaque-box 4-tier E2E suite for R1/R2/R3 -*- lexical-binding: t; -*-

;;; Commentary:
;; Opaque-box, requirement-driven 4-tier ERT suite covering the three Rust
;; performance accelerators (`claude-jobs-scan`, `org-roam-sync`, `git-diff-hl`)
;; and their Elisp integrations (`lisp/claude-jobs-view.el`, `lisp/init-ai.el`,
;; `lisp/init-org.el`, `lisp/init-org-roam.el`, `lisp/init-git.el`).
;;
;; Run from the repository root:
;;
;;   Pre-build / default mode (skips tests requiring unbuilt binaries):
;;     emacs -Q --batch -l shell/test-rust-perf-e2e.el \
;;           -f ert-run-tests-batch-and-exit
;;
;;   Strict acceptance mode (FAILS if any required Rust binary is missing):
;;     EMACS_RUST_E2E_REQUIRE_BINARIES=1 emacs -Q --batch \
;;       -l shell/test-rust-perf-e2e.el -f ert-run-tests-batch-and-exit
;;
;; ISOLATION CONTRACT:
;; - Uses repository-local `elpa/' with `use-package-always-ensure' = nil.
;; - Redirects all mutable Emacs/package state (`custom-file`, `org-persist`,
;;   `forge-database-file`, `transient-*`, `org-roam-db-location`,
;;   `org-id-locations-file`) into a throwaway temp directory deleted on exit.
;; - Never creates `.elc` files and never mutates `~/code/org-roam`,
;;   `~/.emacs.d/var/org/{org-roam.db,id-locations.el}`, `~/.cache/jobctl`,
;;   or `~/.claude/`.

;;; Code:

;;;; Bootstrap & Isolation

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'sqlite)

(defconst e2e--repo-root
  (file-name-as-directory
   (expand-file-name
    ".." (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root derived from this test file's path.")

(defconst e2e--state-dir
  (file-name-as-directory (make-temp-file "e2e-rust-perf-state-" t))
  "Throwaway directory for package/Emacs state created during this run.")

(defun e2e--file-stat-snapshot (path)
  "Return (EXISTS SIZE MTIME) snapshot for PATH without mutating it."
  (if (file-exists-p path)
      (let ((attrs (file-attributes path 'integer)))
        (list t (file-attribute-size attrs)
              (file-attribute-modification-time attrs)))
    (list nil nil nil)))

(defconst e2e--live-state-paths
  (list (expand-file-name "var/org/org-roam.db" e2e--repo-root)
        (expand-file-name "var/org/id-locations.el" e2e--repo-root)
        (expand-file-name ".org-id-locations" e2e--repo-root)
        (expand-file-name "org-roam.db" e2e--repo-root)
        (expand-file-name "forge-database.sqlite" e2e--repo-root))
  "Live state paths that must remain untouched by the test harness.")

(defconst e2e--live-state-snapshots
  (mapcar (lambda (p) (cons p (e2e--file-stat-snapshot p)))
          e2e--live-state-paths)
  "Pre-load stat snapshots of live state files.")

(setq user-emacs-directory e2e--repo-root
      package-user-dir (expand-file-name "elpa" e2e--repo-root))

(add-to-list 'load-path (expand-file-name "lisp" e2e--repo-root))
(add-to-list 'load-path (expand-file-name "lisp/languages" e2e--repo-root))

;; Pre-redirect mutable package state BEFORE package/module initialization.
(setq custom-file (expand-file-name "custom.el" e2e--state-dir)
      org-persist-directory (expand-file-name "org-persist/" e2e--state-dir)
      forge-database-file (expand-file-name "forge.sqlite" e2e--state-dir)
      transient-history-file (expand-file-name "transient-history.el" e2e--state-dir)
      transient-levels-file (expand-file-name "transient-levels.el" e2e--state-dir)
      transient-values-file (expand-file-name "transient-values.el" e2e--state-dir)
      org-roam-db-location (expand-file-name "default-roam.db" e2e--state-dir)
      org-id-locations-file (expand-file-name "default-id-locations.el" e2e--state-dir)
      org-id-locations (make-hash-table :test #'equal))

(add-hook 'kill-emacs-hook
          (lambda () (ignore-errors (delete-directory e2e--state-dir t))))

(require 'package)
(package-initialize)

(require 'use-package)
(setq use-package-always-ensure nil)

;; Load real repository modules.
(load (expand-file-name "lisp/claude-jobs-view.el" e2e--repo-root) nil t)
(load (expand-file-name "lisp/init-ai.el" e2e--repo-root) nil t)
(load (expand-file-name "lisp/init-org.el" e2e--repo-root) nil t)
(load (expand-file-name "lisp/init-org-roam.el" e2e--repo-root) nil t)
(require 'magit)
(load (expand-file-name "lisp/init-git.el" e2e--repo-root) nil t)

;; Prevent autosync from firing and immediately override :custom paths set on load.
(remove-hook 'after-init-hook #'org-roam-db-autosync-mode)
(require 'org-roam)
(require 'org-id)
(require 'gptel)

(defconst e2e--default-vault-dir
  (let ((d (expand-file-name "default-vault/" e2e--state-dir)))
    (make-directory d t)
    d)
  "Throwaway default directory replacing `~/code/org-roam' after module load.")

(setq org-roam-directory e2e--default-vault-dir
      org-roam-db-location (expand-file-name "default-roam.db" e2e--state-dir)
      org-directory e2e--default-vault-dir
      org-agenda-files (list (expand-file-name "inbox.org" e2e--default-vault-dir))
      org-id-locations-file (expand-file-name "default-id-locations.el" e2e--state-dir)
      org-id-locations (make-hash-table :test #'equal)
      org-persist-directory (expand-file-name "org-persist/" e2e--state-dir))

;;;; Core Utilities & Binary Gating

(defun e2e--binary-path (name)
  "Return expected deployed binary path for NAME under `rust/lib/'."
  (expand-file-name (concat "rust/lib/" name) e2e--repo-root))

(defun e2e--require-binary (name)
  "Verify Rust binary NAME is executable in `rust/lib/'.
When missing: fail if `EMACS_RUST_E2E_REQUIRE_BINARIES' is non-empty,
otherwise skip the test cleanly."
  (let ((bin (e2e--binary-path name)))
    (if (file-executable-p bin)
        bin
      (let ((req (getenv "EMACS_RUST_E2E_REQUIRE_BINARIES")))
        (if (and req (not (string-empty-p req)))
            (ert-fail (format "Required Rust binary missing or not executable: %s" bin))
          (ert-skip (format "Rust binary not built yet: %s" bin)))))))

(defun e2e--run-command (program args &optional stdin-bytes env-overrides cwd)
  "Run PROGRAM with ARGS synchronously.
Optional STDIN-BYTES is sent to stdin (raw bytes via `no-conversion').
Optional ENV-OVERRIDES is a list of \"KEY=VAL\" entries prepended to
`process-environment'. Optional CWD sets `default-directory'.
Returns plist (:exit INT :stdout STRING :stderr STRING)."
  (let ((stderr-file (make-temp-file "e2e-stderr-"))
        (stdin-file (when stdin-bytes (make-temp-file "e2e-stdin-")))
        (process-environment (append env-overrides process-environment))
        (default-directory (or cwd e2e--repo-root)))
    (unwind-protect
        (progn
          (when stdin-file
            (let ((coding-system-for-write 'no-conversion))
              (with-temp-file stdin-file
                (set-buffer-multibyte nil)
                (insert stdin-bytes))))
          (with-temp-buffer
            (let* ((coding-system-for-read 'utf-8)
                   (exit (apply #'call-process
                                program stdin-file (list t stderr-file) nil args))
                   (stdout (buffer-string))
                   (stderr (with-temp-buffer
                             (insert-file-contents stderr-file)
                             (buffer-string))))
              (list :exit exit :stdout stdout :stderr stderr))))
      (ignore-errors (delete-file stderr-file))
      (when stdin-file (ignore-errors (delete-file stdin-file))))))

(defun e2e--write-raw (path bytes)
  "Write raw BYTES to PATH without coding conversion, creating parent dirs."
  (make-directory (file-name-directory path) t)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file path
      (set-buffer-multibyte nil)
      (insert bytes))))

(defun e2e--write-utf8 (path text)
  "Write UTF-8 TEXT to PATH, creating parent dirs."
  (make-directory (file-name-directory path) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file path
      (insert text))))

(defmacro e2e-with-temp-dir (var &rest body)
  "Bind VAR to a fresh throwaway directory and delete it in `unwind-protect'."
  (declare (indent 1))
  `(let ((,var (file-name-as-directory (make-temp-file "e2e-work-" t))))
     (unwind-protect
         (progn ,@body)
       (ignore-errors (delete-directory ,var t)))))

(defun e2e--run-child-emacs-no-rust (elisp-form &optional extra-env)
  "Spawn a clean child `emacs -Q --batch' with `user-emacs-directory' lacking `rust/'.
Symlinks `elpa/' and `lisp/' from repo root into a temp `user-emacs-directory',
creates an empty `rust/lib/' dir, redirects package state, evaluates ELISP-FORM
wrapped so it prints `:E2E-RESULT:' followed by the return value, and returns
plist (:exit INT :stdout STRING :stderr STRING :result SEXP)."
  (e2e-with-temp-dir fake-user
    (let* ((state (file-name-as-directory (expand-file-name "state" fake-user)))
           (script (expand-file-name "run.el" fake-user)))
      (make-directory state t)
      (make-directory (expand-file-name "rust/lib" fake-user) t)
      (make-symbolic-link (expand-file-name "elpa" e2e--repo-root)
                          (expand-file-name "elpa" fake-user))
      ;; Copy lisp/ rather than symlinking so `load-file-name' resolves inside
      ;; `fake-user/lisp/' and `../rust/lib/' resolves to empty `fake-user/rust/lib/'.
      (e2e--copy-dir-contents (expand-file-name "lisp" e2e--repo-root)
                              (expand-file-name "lisp" fake-user))
      (e2e--write-utf8
       script
       (let ((print-length nil)
             (print-level nil))
         (format "%S\n"
                 `(progn
                    (setq user-emacs-directory ,fake-user
                          package-user-dir ,(expand-file-name "elpa" fake-user)
                          custom-file ,(expand-file-name "custom.el" state)
                          org-persist-directory ,(expand-file-name "org-persist/" state)
                          forge-database-file ,(expand-file-name "forge.sqlite" state)
                          transient-history-file ,(expand-file-name "transient-history.el" state)
                          transient-levels-file ,(expand-file-name "transient-levels.el" state)
                          transient-values-file ,(expand-file-name "transient-values.el" state)
                          org-roam-db-location ,(expand-file-name "roam.db" state)
                          org-id-locations-file ,(expand-file-name "id-loc.el" state)
                          org-id-locations (make-hash-table :test #'equal))
                    (add-to-list 'load-path ,(expand-file-name "lisp" fake-user))
                    (add-to-list 'load-path ,(expand-file-name "lisp/languages" fake-user))
                    (require 'package)
                    (package-initialize)
                    (require 'use-package)
                    (setq use-package-always-ensure nil)
                    (let ((res ,elisp-form))
                      (princ (format "\n:E2E-RESULT:%S\n" res)))))))
      (let* ((res (e2e--run-command
                   (expand-file-name invocation-name invocation-directory)
                   (list "-Q" "--batch" "-l" script)
                   nil
                   extra-env
                   fake-user))
             (out (plist-get res :stdout))
             (parsed (when (string-match ":E2E-RESULT:\\(.*\\)$" out)
                       (car (read-from-string (match-string 1 out))))))
        (plist-put res :result parsed)))))

;;;; R1 Helpers (`claude-jobs-scan` & `claude-jobs-view`)

(defun e2e--r1-write-meta (state-dir sid lines)
  "Write SID.meta in STATE-DIR from LINES (list of strings)."
  (e2e--write-utf8
   (expand-file-name (concat sid ".meta") state-dir)
   (concat (string-join lines "\n") "\n")))

(defun e2e--r1-write-daemon-json (jobs-dir short json-text)
  "Write state.json for daemon SHORT under JOBS-DIR."
  (e2e--write-utf8
   (expand-file-name (format "%s/state.json" short) jobs-dir)
   json-text))

(defun e2e--r1-write-jsonl (projects-dir cwd-slug sid lines)
  "Write SID.jsonl under PROJECTS-DIR/CWD-SLUG/."
  (e2e--write-utf8
   (expand-file-name (format "%s/%s.jsonl" cwd-slug sid) projects-dir)
   (concat (string-join lines "\n") "\n")))

(defun e2e--r1-cwd-slug (cwd)
  "Mirror Claude's `tr / -' project directory slug for CWD."
  (replace-regexp-in-string "/" "-" cwd))

(defun e2e--r1-spawn-dummy-proc (flag sid)
  "Spawn a harmless sleep child whose `/proc/<pid>/cmdline' has FLAG SID.
FLAG is e.g. \"--session-id\" or \"--resume\". Caller must `delete-process'."
  (let ((proc (make-process
               :name (format "e2e-dummy-%s" (substring sid 0 8))
               :command (list "sh" "-c" "sleep 30; true" "e2e-claude" flag sid)
               :noquery t)))
    ;; Ensure process has started and /proc/<pid>/cmdline is visible.
    (sleep-for 0.05)
    proc))

(defun e2e--r1-scan (state-dir jobs-dir projects-dir &rest extra-args)
  "Run `claude-jobs-scan' with dirs and EXTRA-ARGS, returning plist of (:exit :stdout :stderr :sexp)."
  (let* ((bin (e2e--require-binary "claude-jobs-scan"))
         (args (append (list "--state-dir" state-dir
                             "--jobs-dir" jobs-dir
                             "--projects-dir" projects-dir)
                       extra-args))
         (res (e2e--run-command bin args))
         (out (plist-get res :stdout))
         (sexp (when (zerop (plist-get res :exit))
                 (car (read-from-string out)))))
    (plist-put res :sexp sexp)))

(defmacro e2e-with-r1-fixture (spec &rest body)
  "Create isolated R1 fixture dirs (SPEC = `(root state jobs projects home)') and run BODY.
Binds `claude-jobs-view-state-dir', `claude-jobs-view-projects-dir',
`claude-jobs-view-jobs-dir' (if bound), `process-environment' (`HOME', `JOBCTL_STATE'),
and kills any `*claude-jobs*' buffers created."
  (declare (indent 1))
  (let ((root-sym (nth 0 spec))
        (state-sym (nth 1 spec))
        (jobs-sym (nth 2 spec))
        (proj-sym (nth 3 spec))
        (home-sym (nth 4 spec)))
    `(e2e-with-temp-dir ,root-sym
       (let* ((,home-sym (file-name-as-directory (expand-file-name "home" ,root-sym)))
              (,state-sym (file-name-as-directory (expand-file-name "state" ,root-sym)))
              (,jobs-sym (file-name-as-directory (expand-file-name ".claude/jobs" ,home-sym)))
              (,proj-sym (file-name-as-directory (expand-file-name ".claude/projects" ,home-sym)))
              (claude-jobs-view-state-dir ,state-sym)
              (claude-jobs-view-projects-dir ,proj-sym)
              (default-directory ,root-sym)
              (process-environment
               (append (list (concat "HOME=" (directory-file-name ,home-sym))
                             (concat "JOBCTL_STATE=" (directory-file-name ,state-sym)))
                       process-environment))
              (orig-jobs-bound (boundp 'claude-jobs-view-jobs-dir))
              (orig-jobs-val (and (boundp 'claude-jobs-view-jobs-dir)
                                  (symbol-value 'claude-jobs-view-jobs-dir))))
         (make-directory ,state-sym t)
         (make-directory ,jobs-sym t)
         (make-directory ,proj-sym t)
         (unwind-protect
             (progn
               (when orig-jobs-bound
                 (set 'claude-jobs-view-jobs-dir ,jobs-sym))
               ,@body)
           (when orig-jobs-bound
             (set 'claude-jobs-view-jobs-dir orig-jobs-val))
           (dolist (b (buffer-list))
             (when (string-prefix-p "*claude-jobs" (buffer-name b))
               (kill-buffer b))))))))

(defun e2e--r1-find-session (sexp sid)
  "Find session plist in SEXP's `:sessions' matching SID."
  (seq-find (lambda (s) (equal (plist-get s :sid) sid))
            (plist-get sexp :sessions)))

(defun e2e--r1-find-daemon (sexp short)
  "Find daemon plist in SEXP's `:daemons' matching SHORT."
  (seq-find (lambda (d) (equal (plist-get d :short) short))
            (plist-get sexp :daemons)))

;;;; R2 Helpers (`org-roam-sync` & `org-id`)

(defmacro e2e-with-r2-fixture (spec &rest body)
  "Run BODY in an isolated Org-roam + org-id temp environment.
SPEC is `(root vault db idloc)'. Kills all temp connections and restores globals."
  (declare (indent 1))
  (let ((root-sym (nth 0 spec))
        (vault-sym (nth 1 spec))
        (db-sym (nth 2 spec))
        (idloc-sym (nth 3 spec)))
    `(e2e-with-temp-dir ,root-sym
       (let* ((,vault-sym (file-name-as-directory (expand-file-name "vault" ,root-sym)))
              (,db-sym (expand-file-name "org-roam.db" ,root-sym))
              (,idloc-sym (expand-file-name "id-locations.el" ,root-sym))
              (org-roam-directory ,vault-sym)
              (org-roam-db-location ,db-sym)
              (org-directory ,vault-sym)
              (org-agenda-files (list (expand-file-name "inbox.org" ,vault-sym)))
              (org-id-locations-file ,idloc-sym)
              (org-id-locations (make-hash-table :test #'equal))
              (org-id-files nil)
              (org-roam-db-autosync-mode nil)
              (recentf-list nil))
         (make-directory ,vault-sym t)
         (should-not (string-prefix-p (file-truename "~/code/org-roam")
                                      (file-truename org-roam-directory)))
         (should-not (file-equal-p org-roam-db-location
                                   (expand-file-name "var/org/org-roam.db" e2e--repo-root)))
         (org-roam-db--close-all)
         (clrhash org-roam-db--connection)
         (unwind-protect
             (progn ,@body)
           (org-roam-db--close-all)
           (clrhash org-roam-db--connection)
           (dolist (b (buffer-list))
             (when-let ((bf (buffer-file-name b)))
               (when (file-in-directory-p bf ,root-sym)
                 (with-current-buffer b (set-buffer-modified-p nil))
                 (kill-buffer b)))))))))

(defun e2e--r2-detect-org-id-flag (bin)
  "Inspect `org-roam-sync --help' to pick `--org-id-out' or `--emit-org-ids'."
  (let* ((res (e2e--run-command bin '("--help")))
         (txt (concat (plist-get res :stdout) "\n" (plist-get res :stderr))))
    (cond
     ((string-match-p "--org-id-out" txt) 'out)
     ((string-match-p "--emit-org-ids" txt) 'emit)
     (t (ert-fail (format "org-roam-sync --help lacks --org-id-out / --emit-org-ids:\n%s" txt))))))

(defun e2e--r2-run-sync (vault db &rest extra-args)
  "Run `org-roam-sync' on VAULT and DB with EXTRA-ARGS, asserting exit 0."
  (let* ((bin (e2e--require-binary "org-roam-sync"))
         (res (e2e--run-command
               bin
               (append (list "--dir" (directory-file-name vault) "--db" db)
                       extra-args))))
    (unless (zerop (plist-get res :exit))
      (ert-fail (format "org-roam-sync failed (exit %d):\nstdout:%s\nstderr:%s"
                        (plist-get res :exit)
                        (plist-get res :stdout)
                        (plist-get res :stderr))))
    res))

(defun e2e--sqlite-query (db-path sql &rest params)
  "Open DB-PATH via Emacs 30 built-in sqlite, run SQL with PARAMS, and close."
  (let ((db (sqlite-open db-path)))
    (unwind-protect
        (sqlite-select db sql params)
      (sqlite-close db))))

(defun e2e--emacsql-read (val)
  "Decode an EmacSQL-serialized column VAL via `read-from-string' (nil stays nil).
Signals an error if SQLite contains raw unquoted \"\" (expected \"\\\"\\\"\") or
raw text \"nil\" (expected SQL NULL)."
  (cond
   ((null val) nil)
   ((numberp val) val)
   ((stringp val)
    (when (string-empty-p val)
      (error "Invalid EmacSQL column: empty unquoted SQLite string (expected \"\\\"\\\"\")"))
    (when (string= val "nil")
      (error "Invalid EmacSQL column: unquoted \"nil\" text (expected SQL NULL)"))
    (car (read-from-string val)))
   (t val)))

(defun e2e--strip-text-props-deep (obj)
  "Recursively strip Emacs text properties from strings inside OBJ."
  (cond
   ((stringp obj) (substring-no-properties obj))
   ((consp obj) (cons (e2e--strip-text-props-deep (car obj))
                      (e2e--strip-text-props-deep (cdr obj))))
   ((vectorp obj) (cl-map 'vector #'e2e--strip-text-props-deep obj))
   (t obj)))

(defun e2e--normalize-node-props (raw-str)
  "Parse EmacSQL `nodes.properties' RAW-STR, strip text properties, and sort keys."
  (let ((alist (e2e--strip-text-props-deep (e2e--emacsql-read raw-str))))
    (sort (copy-sequence alist)
          (lambda (a b) (string< (format "%s" (car a)) (format "%s" (car b)))))))

(defun e2e--r2-elisp-clean-sync (vault db)
  "Run pure-Elisp `org-roam-db-sync t' in an isolated child Emacs on VAULT -> DB.
This guarantees pure-Elisp baseline even after M2 integrates Rust into `init-org-roam.el'."
  (let ((res (e2e--run-child-emacs-no-rust
              `(progn
                 (load (expand-file-name "lisp/init-org.el" user-emacs-directory) nil t)
                 (load (expand-file-name "lisp/init-org-roam.el" user-emacs-directory) nil t)
                 (remove-hook 'after-init-hook #'org-roam-db-autosync-mode)
                 (require 'org-roam)
                 (setq org-roam-directory ,vault
                       org-roam-db-location ,db
                       org-directory ,vault
                       org-agenda-files (list ,(expand-file-name "inbox.org" vault))
                       org-roam-db-autosync-mode nil)
                 (org-roam-db--close-all)
                 (clrhash org-roam-db--connection)
                 (org-roam-db-sync t)
                 (org-roam-db--close-all)
                 t))))
    (unless (and (zerop (plist-get res :exit)) (eq (plist-get res :result) t))
      (ert-fail (format "Pure-Elisp org-roam-db-sync baseline failed:\nstdout:%s\nstderr:%s"
                        (plist-get res :stdout) (plist-get res :stderr))))))

(defun e2e--r2-sort-rows (rows)
  "Sort SQL ROWS lexicographically by printed representation."
  (sort (copy-sequence rows)
        (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b)))))

(defun e2e--r2-normalize-path-rel (path root)
  "Return PATH relative to ROOT (resolving symlinks)."
  (file-relative-name (file-truename path) (file-truename root)))

(defun e2e--assert-roam-db-parity (rust-db rust-vault elisp-db elisp-vault)
  "Assert full semantic parity across all 7 tables between RUST-DB and ELISP-DB."
  ;; 1. Schema version
  (should (equal (e2e--sqlite-query rust-db "PRAGMA user_version") '((20))))
  (should (equal (e2e--sqlite-query elisp-db "PRAGMA user_version") '((20))))
  ;; 2. files (compare relative path, decoded title, hash; check 4-int atime/mtime)
  (let* ((r-files (e2e--r2-sort-rows
                   (mapcar (lambda (row)
                             (let ((atime (e2e--emacsql-read (nth 3 row)))
                                   (mtime (e2e--emacsql-read (nth 4 row))))
                               (should (and (listp atime) (= (length atime) 4)
                                            (cl-every #'integerp atime)))
                               (should (and (listp mtime) (= (length mtime) 4)
                                            (cl-every #'integerp mtime)))
                               (list (e2e--r2-normalize-path-rel
                                      (e2e--emacsql-read (nth 0 row)) rust-vault)
                                     (e2e--emacsql-read (nth 1 row))
                                     (e2e--emacsql-read (nth 2 row)))))
                           (e2e--sqlite-query
                            rust-db "SELECT file, title, hash, atime, mtime FROM files"))))
         (e-files (e2e--r2-sort-rows
                   (mapcar (lambda (row)
                             (list (e2e--r2-normalize-path-rel
                                    (e2e--emacsql-read (nth 0 row)) elisp-vault)
                                   (e2e--emacsql-read (nth 1 row))
                                   (e2e--emacsql-read (nth 2 row))))
                           (e2e--sqlite-query
                            elisp-db "SELECT file, title, hash FROM files")))))
    (should (equal r-files e-files)))
  ;; 3. nodes (normalize file relative path + props alist without text props)
  (let* ((norm-node
          (lambda (row vault)
            (let* ((id (e2e--emacsql-read (nth 0 row)))
                   (file (e2e--r2-normalize-path-rel (e2e--emacsql-read (nth 1 row)) vault))
                   (level (nth 2 row))
                   (pos (nth 3 row))
                   (todo (e2e--emacsql-read (nth 4 row)))
                   (prio (nth 5 row))
                   (sched (e2e--emacsql-read (nth 6 row)))
                   (dead (e2e--emacsql-read (nth 7 row)))
                   (title (e2e--emacsql-read (nth 8 row)))
                   (props (e2e--normalize-node-props (nth 9 row)))
                   ;; Replace volatile FILE entry inside properties with rel path
                   (props-rel (mapcar (lambda (kv)
                                        (if (equal (car kv) "FILE")
                                            (cons "FILE" (e2e--r2-normalize-path-rel (cdr kv) vault))
                                          kv))
                                      props))
                   (olp (e2e--emacsql-read (nth 10 row))))
              (list id file level pos todo prio sched dead title props-rel olp))))
         (r-nodes (e2e--r2-sort-rows
                   (mapcar (lambda (r) (funcall norm-node r rust-vault))
                           (e2e--sqlite-query
                            rust-db
                            "SELECT id, file, level, pos, todo, priority, scheduled, deadline, title, properties, olp FROM nodes"))))
         (e-nodes (e2e--r2-sort-rows
                   (mapcar (lambda (r) (funcall norm-node r elisp-vault))
                           (e2e--sqlite-query
                            elisp-db
                            "SELECT id, file, level, pos, todo, priority, scheduled, deadline, title, properties, olp FROM nodes")))))
    (should (equal r-nodes e-nodes)))
  ;; 4. aliases, tags, refs, citations, links
  (dolist (spec '(("SELECT node_id, alias FROM aliases" . (0 1))
                  ("SELECT node_id, tag FROM tags" . (0 1))
                  ("SELECT node_id, ref, type FROM refs" . (0 1 2))
                  ("SELECT node_id, cite_key, pos, properties FROM citations" . (0 1 3))
                  ("SELECT pos, source, dest, type, properties FROM links" . (1 2 3 4))))
    (let* ((sql (car spec))
           (decode-cols (cdr spec))
           (decode-row (lambda (row)
                         (cl-loop for v in row
                                  for idx from 0
                                  collect (if (memq idx decode-cols)
                                              (e2e--emacsql-read v)
                                            v))))
           (r-rows (e2e--r2-sort-rows (mapcar decode-row (e2e--sqlite-query rust-db sql))))
           (e-rows (e2e--r2-sort-rows (mapcar decode-row (e2e--sqlite-query elisp-db sql)))))
      (should (equal r-rows e-rows)))))

(defun e2e--copy-dir-contents (src dst)
  "Recursively copy contents of SRC directory into DST directory."
  (make-directory dst t)
  (dolist (entry (directory-files src t "\\`[^.]"))
    (let ((target (expand-file-name (file-name-nondirectory entry) dst)))
      (if (file-directory-p entry)
          (e2e--copy-dir-contents entry target)
        (copy-file entry target t t)))))

;;;; R3 Helpers (`git-diff-hl` & `diff-hl`)

(defun e2e--git (repo &rest args)
  "Run git ARGS in REPO, failing test on non-zero exit."
  (let ((res (e2e--run-command "git" args nil nil repo)))
    (unless (zerop (plist-get res :exit))
      (ert-fail (format "git %s failed (exit %d):\n%s"
                        (string-join args " ")
                        (plist-get res :exit)
                        (plist-get res :stderr))))
    (plist-get res :stdout)))

(defmacro e2e-with-git-repo (var &rest body)
  "Create a fresh throwaway Git repository bound to VAR and clean up buffers/files."
  (declare (indent 1))
  `(e2e-with-temp-dir ,var
     (e2e--git ,var "init" "-q" "-b" "main")
     (e2e--git ,var "config" "user.email" "e2e@example.invalid")
     (e2e--git ,var "config" "user.name" "E2E Tester")
     (e2e--git ,var "config" "commit.gpgsign" "false")
     (unwind-protect
         (let ((default-directory ,var))
           ,@body)
       (dolist (b (buffer-list))
         (when-let ((bf (buffer-file-name b)))
           (when (file-in-directory-p bf ,var)
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b)))))))

(defun e2e--parse-hunk-tuple (raw)
  "Normalize hunk tuple RAW into `(line inserts deletes type-sym)'."
  (cond
   ((and (listp raw) (= (length raw) 4))
    (list (nth 0 raw) (nth 1 raw) (nth 2 raw)
          (if (symbolp (nth 3 raw)) (nth 3 raw) (intern (format "%s" (nth 3 raw))))))
   ((and (stringp raw)
         (string-match "\\`[ \t]*(\\([0-9]+\\)[ \t]+\\([0-9]+\\)[ \t]+\\([0-9]+\\)[ \t]+\\([a-z]+\\))[ \t]*\\'" raw))
    (list (string-to-number (match-string 1 raw))
          (string-to-number (match-string 2 raw))
          (string-to-number (match-string 3 raw))
          (intern (match-string 4 raw))))
   (t nil)))

(defun e2e--parse-porcelain (stdout)
  "Parse `git-diff-hl --porcelain' STDOUT into alist `(rel-path . (:state STR :hunks TUPLES))'.
Asserts line 1 is `# git-diff-hl v1'. Supports both sexp-based and line/tab-based
porcelain schemas defined under `PROJECT.md § Interface Contracts'."
  (let ((lines (split-string stdout "\n" t)))
    (should (>= (length lines) 1))
    (should (equal (car lines) "# git-diff-hl v1"))
    (let* ((body-lines (cdr lines))
           (body (string-join body-lines "\n"))
           (trimmed (string-trim body)))
      (cond
       ((string-empty-p trimmed) nil)
       ;; Sexp payload (e.g. list of plists or file tuples)
       ((string-prefix-p "(" trimmed)
        (let ((sexp (car (read-from-string trimmed))))
          (when (and (listp sexp) (keywordp (car sexp)))
            (setq sexp (or (plist-get sexp :files) sexp)))
          (mapcar
           (lambda (item)
             (if (keywordp (car item))
                 (let ((path (or (plist-get item :path) (plist-get item :file)))
                       (st (format "%s" (or (plist-get item :state)
                                            (plist-get item :vc-state))))
                       (hunks (mapcar #'e2e--parse-hunk-tuple
                                      (plist-get item :hunks))))
                   (cons path (list :state st :hunks hunks)))
               (cons (car item)
                     (list :state (format "%s" (cadr item))
                           :hunks (mapcar #'e2e--parse-hunk-tuple (cl-caddr item))))))
           sexp)))
       ;; Line-based payload: F/H tagged lines or path\tstate lines
       (t
        (let ((results '())
              (cur-path nil)
              (cur-state nil)
              (cur-hunks '())
              (state-rx "\\`\\(up-to-date\\|edited\\|added\\|removed\\|conflict\\|unregistered\\|ignored\\)\\'"))
          (cl-flet ((flush ()
                      (when cur-path
                        (push (cons cur-path (list :state cur-state
                                                   :hunks (nreverse cur-hunks)))
                              results)
                        (setq cur-path nil cur-state nil cur-hunks nil))))
            (dolist (line body-lines)
              (let ((cols (split-string line "\t")))
                (cond
                 ;; F\t<state>\t<path> (or F\t<path>\t<state>)
                 ((and (equal (car cols) "F") (>= (length cols) 3))
                  (flush)
                  (if (string-match-p state-rx (nth 1 cols))
                      (setq cur-state (nth 1 cols)
                            cur-path (nth 2 cols))
                    (setq cur-path (nth 1 cols)
                          cur-state (nth 2 cols))))
                 ;; H\t<line>\t<ins>\t<del>\t<type>
                 ((and (equal (car cols) "H") (>= (length cols) 5))
                  (push (list (string-to-number (nth 1 cols))
                              (string-to-number (nth 2 cols))
                              (string-to-number (nth 3 cols))
                              (intern (nth 4 cols)))
                        cur-hunks))
                 ;; <path>\t<state>[\t<hunk>...]
                 ((and (>= (length cols) 2) (string-match-p state-rx (nth 1 cols)))
                  (flush)
                  (setq cur-path (nth 0 cols)
                        cur-state (nth 1 cols))
                  (dolist (cell (cddr cols))
                    (when-let ((h (e2e--parse-hunk-tuple cell)))
                      (push h cur-hunks))))
                 ;; <state>\t<path>
                 ((and (>= (length cols) 2) (string-match-p state-rx (nth 0 cols)))
                  (flush)
                  (setq cur-state (nth 0 cols)
                        cur-path (nth 1 cols))
                  (dolist (cell (cddr cols))
                    (when-let ((h (e2e--parse-hunk-tuple cell)))
                      (push h cur-hunks))))
                 ;; Standalone hunk line `(line ins del type)'
                 ((e2e--parse-hunk-tuple line)
                  (push (e2e--parse-hunk-tuple line) cur-hunks)))))
            (flush))
          (nreverse results)))))))

(defun e2e--collect-diff-hl-state (buf)
  "Extract normalized `diff-hl' state and overlays from BUF."
  (with-current-buffer buf
    (let* ((file (buffer-file-name buf))
           (hunks '())
           (marks '()))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (overlay-get ov 'diff-hl)
          (if (overlay-get ov 'diff-hl-hunk)
              (push (list (line-number-at-pos (overlay-start ov))
                          (line-number-at-pos (overlay-end ov))
                          (overlay-get ov 'diff-hl-hunk-type))
                    hunks)
            (let* ((bs (overlay-get ov 'before-string))
                   (disp (and bs (get-text-property 0 'display bs)))
                   (spec (and (consp disp) (cadr disp)))
                   (ch (and (stringp spec) (substring-no-properties spec)))
                   (fc (and (stringp spec) (get-text-property 0 'face spec))))
              (push (list (line-number-at-pos (overlay-start ov)) ch fc)
                    marks)))))
      (list :vc-state (and file (vc-backend file) (vc-state file 'Git))
            :margin-width left-margin-width
            :tick (and (boundp 'diff-hl-flydiff-modified-tick)
                       diff-hl-flydiff-modified-tick)
            :hunks (sort hunks (lambda (a b) (< (car a) (car b))))
            :line-marks (sort marks (lambda (a b) (< (car a) (car b))))))))

(defun e2e--vc-git-baseline-for-repo (repo rel-files &optional flydiff-p amend-files)
  "Compute stock `vc-git' `diff-hl-update' oracle states in a clean child Emacs.
Runs without `rust/lib/git-diff-hl' present. Returns alist `(rel-path . state-plist)'."
  (let ((res (e2e--run-child-emacs-no-rust
              `(progn
                 (require 'magit)
                 (load (expand-file-name "lisp/init-git.el" user-emacs-directory) nil t)
                 (diff-hl-flydiff-mode ,(if flydiff-p 1 -1))
                 (let ((out '()))
                   (dolist (rel ',rel-files)
                     (let* ((full (expand-file-name rel ,repo))
                            (buf (find-file-noselect full)))
                       (with-current-buffer buf
                         (when (member rel ',amend-files)
                           (diff-hl-amend-mode 1))
                         (when (vc-backend full)
                           (vc-state-refresh full 'Git))
                         (diff-hl-update)
                         (let ((hunks '())
                               (marks '()))
                           (dolist (ov (overlays-in (point-min) (point-max)))
                             (when (overlay-get ov 'diff-hl)
                               (if (overlay-get ov 'diff-hl-hunk)
                                   (push (list (line-number-at-pos (overlay-start ov))
                                               (line-number-at-pos (overlay-end ov))
                                               (overlay-get ov 'diff-hl-hunk-type))
                                         hunks)
                                 (let* ((bs (overlay-get ov 'before-string))
                                        (disp (and bs (get-text-property 0 'display bs)))
                                        (spec (and (consp disp) (cadr disp)))
                                        (ch (and (stringp spec) (substring-no-properties spec)))
                                        (fc (and (stringp spec) (get-text-property 0 'face spec))))
                                   (push (list (line-number-at-pos (overlay-start ov)) ch fc)
                                         marks)))))
                           (push (cons rel
                                       (list :vc-state (and (vc-backend full) (vc-state full 'Git))
                                             :hunks (sort hunks (lambda (a b) (< (car a) (car b))))
                                             :line-marks (sort marks (lambda (a b) (< (car a) (car b))))))
                                 out))
                         (kill-buffer buf))))
                   (nreverse out))))))
    (unless (zerop (plist-get res :exit))
      (ert-fail (format "Child vc-git baseline failed:\nstdout:%s\nstderr:%s"
                        (plist-get res :stdout) (plist-get res :stderr))))
    (plist-get res :result)))

;;;; =========================================================================
;;;; TIER 1 — Feature Coverage (23 tests)
;;;; =========================================================================

;;; F1 (R1): 6 tests

(ert-deftest e2e-r1-t1-cli-sexp-valid ()
  "Tier 1 (R1): `claude-jobs-scan' emits a valid Elisp plist with :sessions and :daemons."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let* ((res (e2e--r1-scan state jobs proj))
           (sexp (plist-get res :sexp)))
      (should (zerop (plist-get res :exit)))
      (should (listp sexp))
      (should (plist-member sexp :sessions))
      (should (plist-member sexp :daemons)))))

(ert-deftest e2e-r1-t1-meta-session-fields ()
  "Tier 1 (R1): `claude-jobs-scan' parses .meta fields and resolves liveness."
  (e2e-with-r1-fixture (root state jobs proj _home)
    (let* ((sid-alive "11111111-1111-4111-8111-111111111111")
           (sid-dead  "22222222-2222-4222-8222-222222222222")
           (proc (e2e--r1-spawn-dummy-proc "--session-id" sid-alive)))
      (unwind-protect
          (let ((live-pid (process-id proc)))
            (e2e--r1-write-meta
             state sid-alive
             (list (format "sid=%s" sid-alive)
                   (format "pid=%d" live-pid)
                   (format "cwd=%s" (directory-file-name root))
                   "agent=alpha-agent"
                   "started=2026-11-25T10:00:00+08:00"))
            (e2e--r1-write-meta
             state sid-dead
             (list (format "sid=%s" sid-dead)
                   "pid=999997"
                   (format "cwd=%s" (directory-file-name root))
                   "agent=beta-agent"
                   "started=2026-11-25T09:00:00+08:00"))
            (let* ((sexp (plist-get (e2e--r1-scan state jobs proj) :sexp))
                   (s1 (e2e--r1-find-session sexp sid-alive))
                   (s2 (e2e--r1-find-session sexp sid-dead)))
              (should s1)
              (should (= (plist-get s1 :pid) live-pid))
              (should (equal (plist-get s1 :state) "alive"))
              (should-not (plist-get s1 :resumed))
              (should (member live-pid (plist-get s1 :live-pids)))
              (should (equal (plist-get s1 :agent) "alpha-agent"))
              (should (equal (plist-get s1 :started) "2026-11-25T10:00:00+08:00"))
              (should (equal (plist-get s1 :cwd) (directory-file-name root)))
              (should s2)
              (should (= (plist-get s2 :pid) 999997))
              (should (equal (plist-get s2 :state) "dead"))
              (should-not (plist-get s2 :resumed))
              (should-not (plist-get s2 :live-pids))))
        (when (process-live-p proc) (delete-process proc))))))

(ert-deftest e2e-r1-t1-daemon-state-json ()
  "Tier 1 (R1): `claude-jobs-scan' parses daemon `state.json' fields cleanly."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (e2e--r1-write-daemon-json
     jobs "d1234567"
     (json-serialize
      '((daemonShort . "d1234567")
        (state . "running")
        (updatedAt . "2026-11-25T02:00:00Z")
        (intent . "Audit module dependencies")
        (name . "audit-daemon")
        (cwd . "/tmp/workspace"))))
    (let* ((sexp (plist-get (e2e--r1-scan state jobs proj) :sexp))
           (d (e2e--r1-find-daemon sexp "d1234567")))
      (should d)
      (should (equal (plist-get d :short) "d1234567"))
      (should (equal (plist-get d :state) "running"))
      (should (equal (plist-get d :updated) "2026-11-25T02:00:00Z"))
      (should (equal (plist-get d :intent) "Audit module dependencies"))
      (should (equal (plist-get d :raw-intent) "Audit module dependencies"))
      (should (equal (plist-get d :name) "audit-daemon"))
      (should (equal (plist-get d :cwd) "/tmp/workspace")))))

(ert-deftest e2e-r1-t1-transcript-cwd-and-first-user ()
  "Tier 1 (R1): Resolves .jsonl via `cwd' fast-path and extracts string user prompt."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let* ((sid "33333333-3333-4333-8333-333333333333")
           (cwd "/tmp/e2e/myproj")
           (slug (e2e--r1-cwd-slug cwd)))
      (e2e--r1-write-meta
       state sid
       (list (format "sid=%s" sid) "pid=999996" (format "cwd=%s" cwd)
             "agent=default" "started=2026-11-25T11:00:00+08:00"))
      (e2e--r1-write-jsonl
       proj slug sid
       (list "{\"type\":\"system\",\"subtype\":\"init\"}"
             (json-serialize
              `((type . "user")
                (cwd . ,cwd)
                (message . ((role . "user") (content . "Build the parser")))))))
      (let* ((sexp (plist-get (e2e--r1-scan state jobs proj) :sexp))
             (s (e2e--r1-find-session sexp sid)))
        (should s)
        (should (equal (plist-get s :cwd) cwd))
        (should (string-suffix-p (concat sid ".jsonl") (plist-get s :transcript-path)))
        (should (equal (plist-get s :first-user-text) "Build the parser"))))))

(ert-deftest e2e-r1-t1-uuid-single-session ()
  "Tier 1 (R1): `--uuid UUID' returns a single session plist matching that session."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let ((sid1 "44444444-4444-4444-8444-444444444444")
          (sid2 "55555555-5555-4555-8555-555555555555"))
      (e2e--r1-write-meta state sid1 (list (format "sid=%s" sid1) "pid=999995"
                                           "cwd=/tmp/w1" "agent=a1" "started=2026-11-25T01:00:00Z"))
      (e2e--r1-write-meta state sid2 (list (format "sid=%s" sid2) "pid=999994"
                                           "cwd=/tmp/w2" "agent=a2" "started=2026-11-25T02:00:00Z"))
      (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug "/tmp/w1") sid1
                           (list (json-serialize '((type . "user") (cwd . "/tmp/w1")
                                                   (message . ((role . "user") (content . "First prompt")))))))
      (let* ((res (e2e--r1-scan state jobs proj "--uuid" sid1))
             (s (plist-get res :sexp)))
        (should (zerop (plist-get res :exit)))
        (should (listp s))
        (should (equal (plist-get s :sid) sid1))
        (should (equal (plist-get s :cwd) "/tmp/w1"))
        (should (equal (plist-get s :first-user-text) "First prompt"))
        (should-not (plist-member s :sessions))))))

(ert-deftest e2e-r1-t1-claude-jobs-view-entries ()
  "Tier 1 (R1): `claude-jobs-view--entries' builds 6-column [TYPE SHORT STATE PID UPDATED INTENT] rows."
  (e2e--require-binary "claude-jobs-scan")
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let ((sid "66666666-6666-4666-8666-666666666666"))
      (e2e--r1-write-meta state sid (list (format "sid=%s" sid) "pid=999993"
                                          "cwd=/tmp/v1" "agent=worker"
                                          "started=2026-11-25T03:00:00Z"))
      (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug "/tmp/v1") sid
                           (list (json-serialize '((type . "user") (cwd . "/tmp/v1")
                                                   (message . ((role . "user") (content . "Check\nlines")))))))
      (e2e--r1-write-daemon-json
       jobs "abcd1234"
       (json-serialize '((daemonShort . "abcd1234")
                         (state . "done")
                         (updatedAt . "2026-11-25T03:05:00Z")
                         (intent . "Daemon task")
                         (name . "d-name"))))
      (let* ((entries (claude-jobs-view--entries))
             (s-row (assoc (cons 'session sid) entries))
             (d-row (assoc (cons 'daemon "abcd1234") entries)))
        (should s-row)
        (should d-row)
        (let ((sv (cadr s-row))
              (dv (cadr d-row)))
          (should (= (length sv) 6))
          (should (equal (substring-no-properties (aref sv 0)) "session"))
          (should (equal (substring-no-properties (aref sv 1)) "66666666"))
          (should (equal (substring-no-properties (aref sv 2)) "dead"))
          (should (equal (substring-no-properties (aref sv 3)) "999993"))
          (should (equal (substring-no-properties (aref sv 4)) "2026-11-25T03:00:00Z"))
          (should (equal (substring-no-properties (aref sv 5)) "Check lines"))
          (should (equal (get-text-property 0 'help-echo (aref sv 5)) "Check\nlines"))
          (should (= (length dv) 6))
          (should (equal (substring-no-properties (aref dv 0)) "daemon"))
          (should (equal (substring-no-properties (aref dv 1)) "abcd1234"))
          (should (equal (substring-no-properties (aref dv 2)) "done"))
          (should (equal (substring-no-properties (aref dv 3)) "—"))
          (should (equal (substring-no-properties (aref dv 4)) "2026-11-25T03:05:00Z")))))))

;;; F2 (R2): 6 tests

(ert-deftest e2e-r2-t1-schema-v20-and-pragmas ()
  "Tier 1 (R2): `org-roam-sync' creates DB with user_version=20, 7 tables, 3 indices, FK cascade."
  (e2e-with-r2-fixture (_root vault db _idloc)
    (e2e--write-utf8
     (expand-file-name "n1.org" vault)
     ":PROPERTIES:\n:ID: 10000000-0000-4000-8000-000000000001\n:END:\n#+title: One\n#+filetags: :alpha:\n")
    (e2e--r2-run-sync vault db)
    (should (equal (e2e--sqlite-query db "PRAGMA user_version") '((20))))
    (let ((tables (mapcar #'car
                          (e2e--sqlite-query
                           db "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")))
          (indices (mapcar #'car
                           (e2e--sqlite-query
                            db "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' ORDER BY name"))))
      (should (equal tables '("aliases" "citations" "files" "links" "nodes" "refs" "tags")))
      (should (equal indices '("alias_node_id" "refs_node_id" "tags_node_id"))))
    ;; Verify PRAGMA foreign_keys = ON cascades deletes from files -> nodes -> tags.
    (let ((conn (sqlite-open db)))
      (unwind-protect
          (progn
            (sqlite-execute conn "PRAGMA foreign_keys = ON")
            (sqlite-execute conn "DELETE FROM files")
            (should (equal (sqlite-select conn "SELECT count(*) FROM nodes") '((0))))
            (should (equal (sqlite-select conn "SELECT count(*) FROM tags") '((0)))))
        (sqlite-close conn)))))

(ert-deftest e2e-r2-t1-emacsql-serialization ()
  "Tier 1 (R2): EmacSQL column encoding uses prin1 strings, NULL for nil, bare ints, 4-int times, SHA-1."
  (e2e-with-r2-fixture (_root vault db _idloc)
    (let* ((note (expand-file-name "enc.org" vault))
           (notitle (expand-file-name "notitle.org" vault))
           (content ":PROPERTIES:\n:ID: 10000000-0000-4000-8000-000000000002\n:END:\n#+title: Encoded \"Quote\"\n"))
      (e2e--write-utf8 note content)
      (e2e--write-utf8 notitle "Title-less body.\n")
      (e2e--r2-run-sync vault db)
      (let* ((frow (car (e2e--sqlite-query
                         db "SELECT file, title, hash, atime, mtime FROM files WHERE file LIKE '%enc.org\"'")))
             (notitle-row (car (e2e--sqlite-query
                                db "SELECT title FROM files WHERE file LIKE '%notitle.org\"'")))
             (nrow (car (e2e--sqlite-query db "SELECT id, level, pos, todo, priority, scheduled, deadline, title, olp FROM nodes")))
             (expected-hash (secure-hash 'sha1 (encode-coding-string content 'utf-8-unix))))
        ;; Raw SQLite strings are prin1-to-string quoted (empty title is literal "\"\"")
        (should (string-prefix-p "\"" (nth 0 frow)))
        (should (string-suffix-p "\"" (nth 0 frow)))
        (should (equal (car notitle-row) "\"\""))
        (should (equal (e2e--emacsql-read (car notitle-row)) ""))
        (should (equal (e2e--emacsql-read (nth 1 frow)) "Encoded \"Quote\""))
        (should (equal (e2e--emacsql-read (nth 2 frow)) expected-hash))
        (let ((atime (e2e--emacsql-read (nth 3 frow)))
              (mtime (e2e--emacsql-read (nth 4 frow))))
          (should (and (listp atime) (= (length atime) 4) (cl-every #'integerp atime)))
          (should (and (listp mtime) (= (length mtime) 4) (cl-every #'integerp mtime))))
        ;; Bare integers for level/pos, SQL NULL (nil) for nil todo/priority/scheduled/deadline/olp
        (should (equal (e2e--emacsql-read (nth 0 nrow)) "10000000-0000-4000-8000-000000000002"))
        (should (integerp (nth 1 nrow)))
        (should (= (nth 1 nrow) 0))
        (should (integerp (nth 2 nrow)))
        (should (= (nth 2 nrow) 1))
        (should (null (nth 3 nrow)))
        (should (null (nth 4 nrow)))
        (should (null (nth 5 nrow)))
        (should (null (nth 6 nrow)))
        (should (null (nth 8 nrow)))))))

(ert-deftest e2e-r2-t1-file-and-headline-nodes ()
  "Tier 1 (R2): Indexes file-level and nested headline :ID: nodes with olp, TODO, priority, dates."
  (e2e-with-r2-fixture (_root vault db _idloc)
    (e2e--write-utf8
     (expand-file-name "head.org" vault)
     (concat ":PROPERTIES:\n:ID: 10000000-0000-4000-8000-000000000010\n:END:\n"
             "#+title: Top File\n\n"
             "* Parent Section\n"
             "** TODO [#A] Child Task\n"
             "SCHEDULED: <2026-11-25 Wed> DEADLINE: <2026-12-01 Tue>\n"
             ":PROPERTIES:\n:ID: 10000000-0000-4000-8000-000000000011\n:END:\n"
             "Body text.\n"))
    (e2e--r2-run-sync vault db)
    (let* ((rows (e2e--sqlite-query
                  db "SELECT id, level, todo, priority, scheduled, deadline, title, olp FROM nodes ORDER BY level"))
           (fnode (nth 0 rows))
           (hnode (nth 1 rows)))
      (should (= (length rows) 2))
      (should (equal (e2e--emacsql-read (nth 0 fnode)) "10000000-0000-4000-8000-000000000010"))
      (should (= (nth 1 fnode) 0))
      (should (equal (e2e--emacsql-read (nth 0 hnode)) "10000000-0000-4000-8000-000000000011"))
      (should (= (nth 1 hnode) 2))
      (should (equal (e2e--emacsql-read (nth 2 hnode)) "TODO"))
      (should (= (nth 3 hnode) ?A))
      (should (string-prefix-p "2026-11-25" (e2e--emacsql-read (nth 4 hnode))))
      (should (string-prefix-p "2026-12-01" (e2e--emacsql-read (nth 5 hnode))))
      (should (equal (e2e--emacsql-read (nth 6 hnode)) "Child Task"))
      (should (equal (e2e--emacsql-read (nth 7 hnode)) '("Parent Section"))))))

(ert-deftest e2e-r2-t1-tags-aliases-refs-links ()
  "Tier 1 (R2): Indexes #+filetags:, inherited tags, ROAM_ALIASES, ROAM_REFS, [[id:...]], [cite:@...]."
  (e2e-with-r2-fixture (_root vault db _idloc)
    (let ((id-a "10000000-0000-4000-8000-000000000020")
          (id-h "10000000-0000-4000-8000-000000000021")
          (id-b "10000000-0000-4000-8000-000000000022"))
      (e2e--write-utf8
       (expand-file-name "a.org" vault)
       (format ":PROPERTIES:\n:ID: %s\n:ROAM_ALIASES: Alpha \"Alpha One\"\n:ROAM_REFS: @refKey\n:END:\n#+title: Note A\n#+filetags: :ftag:\n\nLink to [[id:%s][B]] and [cite:@myCite].\n\n* Sub :htag:\n:PROPERTIES:\n:ID: %s\n:END:\n"
               id-a id-b id-h))
      (e2e--write-utf8
       (expand-file-name "b.org" vault)
       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Note B\n" id-b))
      (e2e--r2-run-sync vault db)
      (let ((tags (mapcar (lambda (r) (mapcar #'e2e--emacsql-read r))
                          (e2e--sqlite-query db "SELECT node_id, tag FROM tags ORDER BY node_id, tag")))
            (aliases (sort (mapcar (lambda (r) (mapcar #'e2e--emacsql-read r))
                                   (e2e--sqlite-query db "SELECT node_id, alias FROM aliases"))
                           (lambda (a b) (string< (cadr a) (cadr b)))))
            (refs (mapcar (lambda (r) (mapcar #'e2e--emacsql-read r))
                          (e2e--sqlite-query db "SELECT node_id, ref, type FROM refs")))
            (cites (mapcar (lambda (r) (e2e--emacsql-read (car r)))
                           (e2e--sqlite-query db "SELECT cite_key FROM citations")))
            (links (mapcar (lambda (r) (mapcar #'e2e--emacsql-read r))
                           (e2e--sqlite-query db "SELECT source, dest, type FROM links"))))
        (should (member (list id-a "ftag") tags))
        (should (member (list id-h "ftag") tags))
        (should (member (list id-h "htag") tags))
        (should (equal aliases (list (list id-a "Alpha") (list id-a "Alpha One"))))
        (should (equal refs (list (list id-a "refKey" "cite"))))
        (should (equal cites '("myCite")))
        (should (member (list id-a id-b "id") links))))))

(ert-deftest e2e-r2-t1-org-id-emit ()
  "Tier 1 (R2): `org-roam-sync' emits readable `(path id ...)' alist resolving indexed IDs."
  (e2e-with-r2-fixture (root vault db idloc)
    (let* ((bin (e2e--require-binary "org-roam-sync"))
           (mode (e2e--r2-detect-org-id-flag bin))
           (id1 "10000000-0000-4000-8000-000000000030")
           (note (expand-file-name "idnote.org" vault)))
      (e2e--write-utf8 note (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: ID Note\n" id1))
      (let* ((flag (if (eq mode 'out)
                       (list "--org-id-out" idloc)
                     (list "--emit-org-ids")))
             (res (apply #'e2e--r2-run-sync vault db flag))
             (alist (if (eq mode 'out)
                        (with-temp-buffer
                          (insert-file-contents idloc)
                          (read (current-buffer)))
                      (car (read-from-string (plist-get res :stdout))))))
        (should (listp alist))
        (let ((found (cl-find-if (lambda (entry) (member id1 (cdr entry))) alist)))
          (should found)
          (should (file-equal-p (expand-file-name (car found)) note)))
        ;; Ensure root temp path stays clean
        (should (file-directory-p root))))))

(ert-deftest e2e-r2-t1-init-org-roam-sync ()
  "Tier 1 (R2): Calling `(org-roam-db-sync)' via `init-org-roam.el' populates `org-roam-db-location'."
  (e2e--require-binary "org-roam-sync")
  (e2e-with-r2-fixture (_root vault db _idloc)
    (let ((id1 "10000000-0000-4000-8000-000000000040"))
      (e2e--write-utf8
       (expand-file-name "hello.org" vault)
       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Hello Sync\n" id1))
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (should (file-exists-p db))
      (let ((node (org-roam-node-from-title-or-alias "Hello Sync")))
        (should node)
        (should (equal (org-roam-node-id node) id1))))))

;;; F3 (R3): 6 tests

(ert-deftest e2e-r3-t1-init-git-wiring ()
  "Tier 1 (R3): `lisp/init-git.el' wires `diff-hl', `vc-handled-backends', and `magit-post-refresh-hook'."
  (should global-diff-hl-mode)
  (should diff-hl-margin-mode)
  (should diff-hl-flydiff-mode)
  (should (equal vc-handled-backends '(Git)))
  (should (memq 'diff-hl-magit-post-refresh magit-post-refresh-hook)))

(ert-deftest e2e-r3-t1-porcelain-header-and-all ()
  "Tier 1 (R3): `git-diff-hl -C <repo> --porcelain --all' emits `# git-diff-hl v1' and exits 0."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      (e2e--write-utf8 (expand-file-name "a.txt" repo) "one\ntwo\n")
      (e2e--git repo "add" "a.txt")
      (e2e--git repo "commit" "-q" "-m" "init")
      (let* ((res (e2e--run-command bin (list "-C" (directory-file-name repo)
                                              "--porcelain" "--all")))
             (parsed (e2e--parse-porcelain (plist-get res :stdout))))
        (should (zerop (plist-get res :exit)))
        (should (listp parsed))))))

(ert-deftest e2e-r3-t1-vc-states-core ()
  "Tier 1 (R3): `git-diff-hl' classifies all 7 VC states."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      ;; Base commit with clean, edited, removed, conflict base
      (e2e--write-utf8 (expand-file-name ".gitignore" repo) "*.ign\n")
      (e2e--write-utf8 (expand-file-name "clean.txt" repo) "clean\n")
      (e2e--write-utf8 (expand-file-name "edited.txt" repo) "line1\nline2\n")
      (e2e--write-utf8 (expand-file-name "removed.txt" repo) "bye\n")
      (e2e--write-utf8 (expand-file-name "conflict.txt" repo) "base\n")
      (e2e--git repo "add" ".")
      (e2e--git repo "commit" "-q" "-m" "base")
      ;; Create real merge conflict on conflict.txt
      (e2e--git repo "checkout" "-q" "-b" "side")
      (e2e--write-utf8 (expand-file-name "conflict.txt" repo) "side\n")
      (e2e--git repo "commit" "-q" "-am" "side")
      (e2e--git repo "checkout" "-q" "main")
      (e2e--write-utf8 (expand-file-name "conflict.txt" repo) "main\n")
      (e2e--git repo "commit" "-q" "-am" "main")
      (e2e--run-command "git" '("merge" "--no-commit" "side") nil nil repo)
      ;; Apply remaining working-tree / index states
      (e2e--write-utf8 (expand-file-name "edited.txt" repo) "line1\nchanged\n")
      (e2e--write-utf8 (expand-file-name "added.txt" repo) "brand new\n")
      (e2e--git repo "add" "added.txt")
      (e2e--git repo "rm" "-q" "removed.txt")
      (e2e--write-utf8 (expand-file-name "untracked.txt" repo) "untracked\n")
      (e2e--write-utf8 (expand-file-name "secret.ign" repo) "ignored\n")
      (let* ((files '("clean.txt" "edited.txt" "added.txt" "removed.txt"
                      "conflict.txt" "untracked.txt" "secret.ign"))
             (res (e2e--run-command
                   bin
                   (append (list "-C" (directory-file-name repo) "--porcelain")
                           files)))
             (parsed (e2e--parse-porcelain (plist-get res :stdout))))
        (should (zerop (plist-get res :exit)))
        (should (equal (plist-get (cdr (assoc "clean.txt" parsed)) :state) "up-to-date"))
        (should (equal (plist-get (cdr (assoc "edited.txt" parsed)) :state) "edited"))
        (should (equal (plist-get (cdr (assoc "added.txt" parsed)) :state) "added"))
        (should (equal (plist-get (cdr (assoc "removed.txt" parsed)) :state) "removed"))
        (should (equal (plist-get (cdr (assoc "conflict.txt" parsed)) :state) "conflict"))
        (should (equal (plist-get (cdr (assoc "untracked.txt" parsed)) :state) "unregistered"))
        (should (equal (plist-get (cdr (assoc "secret.ign" parsed)) :state) "ignored"))))))

(ert-deftest e2e-r3-t1-hunk-types-insert-delete-change ()
  "Tier 1 (R3): Emits accurate 4-tuple (line inserts deletes type) for insert, delete, change."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      (e2e--write-utf8 (expand-file-name "ins.txt" repo) "a\nb\nc\n")
      (e2e--write-utf8 (expand-file-name "del.txt" repo) "a\nb\nc\nd\n")
      (e2e--write-utf8 (expand-file-name "chg.txt" repo) "a\nb\nc\n")
      (e2e--git repo "add" ".")
      (e2e--git repo "commit" "-q" "-m" "init")
      (e2e--write-utf8 (expand-file-name "ins.txt" repo) "a\nb\nx\ny\nc\n")
      (e2e--write-utf8 (expand-file-name "del.txt" repo) "a\nd\n")
      (e2e--write-utf8 (expand-file-name "chg.txt" repo) "a\nB1\nB2\nc\n")
      (let* ((res (e2e--run-command
                   bin (list "-C" (directory-file-name repo) "--porcelain" "--all")))
             (parsed (e2e--parse-porcelain (plist-get res :stdout))))
        (should (zerop (plist-get res :exit)))
        (should (equal (plist-get (cdr (assoc "ins.txt" parsed)) :hunks) '((3 2 0 insert))))
        (should (equal (plist-get (cdr (assoc "del.txt" parsed)) :hunks) '((2 0 2 delete))))
        (should (equal (plist-get (cdr (assoc "chg.txt" parsed)) :hunks) '((2 2 1 change))))))))

(ert-deftest e2e-r3-t1-stdin-and-positional-paths ()
  "Tier 1 (R3): `--stdin', `--stdin -z', and positional `<path>...' return identical results."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      (e2e--write-utf8 (expand-file-name "f1.txt" repo) "a\nb\n")
      (e2e--write-utf8 (expand-file-name "f2.txt" repo) "x\ny\n")
      (e2e--git repo "add" ".")
      (e2e--git repo "commit" "-q" "-m" "init")
      (e2e--write-utf8 (expand-file-name "f1.txt" repo) "a\nb\nc\n")
      (let* ((dir (directory-file-name repo))
             (r-pos (e2e--run-command bin (list "-C" dir "--porcelain" "f1.txt" "f2.txt")))
             (r-in  (e2e--run-command bin (list "-C" dir "--porcelain" "--stdin") "f1.txt\nf2.txt\n"))
             (r-inz (e2e--run-command bin (list "-C" dir "--porcelain" "--stdin" "-z") "f1.txt\0f2.txt\0"))
             (p-pos (e2e--parse-porcelain (plist-get r-pos :stdout)))
             (p-in  (e2e--parse-porcelain (plist-get r-in :stdout)))
             (p-inz (e2e--parse-porcelain (plist-get r-inz :stdout))))
        (should (zerop (plist-get r-pos :exit)))
        (should (zerop (plist-get r-in :exit)))
        (should (zerop (plist-get r-inz :exit)))
        (should (equal p-pos p-in))
        (should (equal p-pos p-inz))
        (should (equal (plist-get (cdr (assoc "f1.txt" p-pos)) :state) "edited"))
        (should (equal (plist-get (cdr (assoc "f2.txt" p-pos)) :state) "up-to-date"))))))

(ert-deftest e2e-r3-t1-magit-post-refresh-overlays ()
  "Tier 1 (R3): `diff-hl-magit-post-refresh' creates `diff-hl-hunk' overlays and margin marks."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (let ((f (expand-file-name "mod.txt" repo)))
      (e2e--write-utf8 f "one\ntwo\nthree\n")
      (e2e--git repo "add" "mod.txt")
      (e2e--git repo "commit" "-q" "-m" "init")
      ;; Modify before opening so both baseline and M3 refresh this tracked file.
      (e2e--write-utf8 f "one\nTWO\nthree\nfour\n")
      (let ((buf (find-file-noselect f)))
        (with-current-buffer buf
          (should diff-hl-mode)
          (diff-hl-magit-post-refresh)
          (let ((st (e2e--collect-diff-hl-state buf)))
            (should (eq (plist-get st :vc-state) 'edited))
            (should (equal (plist-get st :hunks)
                           '((2 3 change) (4 5 insert))))
            (should (equal (plist-get st :line-marks)
                           '((2 "!" diff-hl-margin-change)
                             (4 "+" diff-hl-margin-insert))))))))))

;;; F4 (M4 Build, CLI & Hygiene): 5 tests

(ert-deftest e2e-m4-t1-binaries-present-and-executable ()
  "Tier 1 (M4): All three Rust binaries are deployed and executable in `rust/lib/'."
  (dolist (name '("claude-jobs-scan" "org-roam-sync" "git-diff-hl"))
    (let ((bin (e2e--require-binary name)))
      (should (file-regular-p bin))
      (should (file-executable-p bin)))))

(ert-deftest e2e-m4-t1-cli-help-flags ()
  "Tier 1 (M4): All three binaries exit 0 on `--help' and document contracted CLI flags."
  (let ((b1 (e2e--require-binary "claude-jobs-scan"))
        (b2 (e2e--require-binary "org-roam-sync"))
        (b3 (e2e--require-binary "git-diff-hl")))
    (let ((r1 (e2e--run-command b1 '("--help")))
          (r2 (e2e--run-command b2 '("--help")))
          (r3 (e2e--run-command b3 '("--help"))))
      (let ((t1 (concat (or (plist-get r1 :stdout) "") "\n" (or (plist-get r1 :stderr) "")))
            (t2 (concat (or (plist-get r2 :stdout) "") "\n" (or (plist-get r2 :stderr) "")))
            (t3 (concat (or (plist-get r3 :stdout) "") "\n" (or (plist-get r3 :stderr) ""))))
        (should (zerop (plist-get r1 :exit)))
        (dolist (flag '("--state-dir" "--jobs-dir" "--projects-dir" "--head-bytes" "--uuid"))
          (should (string-match-p (regexp-quote flag) t1)))
        (should (zerop (plist-get r2 :exit)))
        (dolist (flag '("--dir" "--db" "--exclude" "--ext" "--force"))
          (should (string-match-p (regexp-quote flag) t2)))
        (should (zerop (plist-get r3 :exit)))
        (dolist (flag '("-C" "--porcelain" "--all" "--stdin" "-z"))
          (should (string-match-p (regexp-quote flag) t3)))))))

(ert-deftest e2e-m4-t1-invalid-cli-args-nonzero ()
  "Tier 1 (M4): Invalid flags and nonexistent directories exit non-zero cleanly."
  (let ((b1 (e2e--require-binary "claude-jobs-scan"))
        (b2 (e2e--require-binary "org-roam-sync"))
        (b3 (e2e--require-binary "git-diff-hl")))
    (let ((r1 (e2e--run-command b1 '("--definitely-unknown-flag")))
          (r2 (e2e--run-command b2 (list "--dir" "/nonexistent/e2e/dir"
                                         "--db" (expand-file-name "nope.db" e2e--state-dir))))
          (r3 (e2e--run-command b3 '("-C" "/nonexistent/e2e/repo" "--porcelain" "--all"))))
      (should-not (zerop (plist-get r1 :exit)))
      (should-not (zerop (plist-get r2 :exit)))
      (should-not (zerop (plist-get r3 :exit))))))

(ert-deftest e2e-m4-t1-lisp-syntax-check-parens ()
  "Tier 1 (M4): Target Elisp modules and this test file pass `check-parens' in `emacs-lisp-mode'."
  (dolist (rel '("lisp/claude-jobs-view.el"
                 "lisp/init-ai.el"
                 "lisp/init-org-roam.el"
                 "lisp/init-org.el"
                 "lisp/init-git.el"
                 "shell/test-rust-perf-e2e.el"))
    (let ((full (expand-file-name rel e2e--repo-root)))
      (should (file-readable-p full))
      (with-temp-buffer
        (insert-file-contents full)
        (delay-mode-hooks (emacs-lisp-mode))
        (check-parens)))))

(ert-deftest e2e-m4-t1-no-elc-or-live-db-pollution ()
  "Tier 1 (M4): No `.elc' files exist in `lisp/'/`shell/', and live DB/state files are untouched."
  (let ((elc-files
         (append (directory-files-recursively (expand-file-name "lisp" e2e--repo-root) "\\.elc\\'")
                 (directory-files-recursively (expand-file-name "shell" e2e--repo-root) "\\.elc\\'"))))
    (should (null elc-files)))
  (should-not (file-equal-p org-roam-directory (file-truename "~/code/org-roam")))
  (should-not (file-equal-p org-roam-db-location
                            (expand-file-name "var/org/org-roam.db" e2e--repo-root)))
  (should-not (file-equal-p org-id-locations-file
                            (expand-file-name "var/org/id-locations.el" e2e--repo-root)))
  (dolist (entry e2e--live-state-snapshots)
    (should (equal (e2e--file-stat-snapshot (car entry)) (cdr entry)))))

;;;; =========================================================================
;;;; TIER 2 — Boundary & Corner Cases (23 tests)
;;;; =========================================================================

;;; F1 (R1): 6 tests

(ert-deftest e2e-r1-t2-empty-and-missing-dirs ()
  "Tier 2 (R1): Empty and nonexistent dirs produce `(:sessions nil :daemons nil)' with exit 0."
  (e2e-with-r1-fixture (root state jobs proj _home)
    (let ((r-empty (e2e--r1-scan state jobs proj))
          (r-miss  (e2e--r1-scan (expand-file-name "missing-s" root)
                                 (expand-file-name "missing-j" root)
                                 (expand-file-name "missing-p" root))))
      (should (zerop (plist-get r-empty :exit)))
      (should (null (plist-get (plist-get r-empty :sexp) :sessions)))
      (should (null (plist-get (plist-get r-empty :sexp) :daemons)))
      (should (zerop (plist-get r-miss :exit)))
      (should (null (plist-get (plist-get r-miss :sexp) :sessions)))
      (should (null (plist-get (plist-get r-miss :sexp) :daemons))))))

(ert-deftest e2e-r1-t2-meta-bash-percent-q-and-legacy ()
  "Tier 2 (R1): Unescapes bash `%q' escapes in `.meta' and handles legacy `.meta' lacking cwd/agent."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let ((sid-q "77777777-7777-4777-8777-777777777771")
          (sid-c "77777777-7777-4777-8777-777777777772")
          (sid-l "77777777-7777-4777-8777-777777777773"))
      ;; Backslash space & escaped single quote
      (e2e--r1-write-meta
       state sid-q
       (list (format "sid=%s" sid-q)
             "pid=999991"
             "cwd=/tmp/my\\ dir/sub\\'quote"
             "agent=my\\ agent"
             "started=2026-11-25T10:00:00Z"))
      ;; ANSI-C $'...\n...' quoting and empty '' agent
      (e2e--r1-write-meta
       state sid-c
       (list (format "sid=%s" sid-c)
             "pid=999992"
             "cwd=$'/tmp/ansic\\tdir'"
             "agent=''"
             "started=2026-11-25T10:01:00Z"))
      ;; Legacy .meta omitting cwd= and agent=
      (e2e--r1-write-meta
       state sid-l
       (list (format "sid=%s" sid-l)
             "pid=999993"
             "started=2026-11-25T10:02:00Z"))
      (let* ((sexp (plist-get (e2e--r1-scan state jobs proj) :sexp))
             (sq (e2e--r1-find-session sexp sid-q))
             (sc (e2e--r1-find-session sexp sid-c))
             (sl (e2e--r1-find-session sexp sid-l)))
        (should (equal (plist-get sq :cwd) "/tmp/my dir/sub'quote"))
        (should (equal (plist-get sq :agent) "my agent"))
        (should (equal (plist-get sc :cwd) "/tmp/ansic\tdir"))
        (should (member (plist-get sc :agent) '(nil "" "-")))
        (should sl)
        (should (null (plist-get sl :cwd)))))))

(ert-deftest e2e-r1-t2-proc-alive-dead-resumed ()
  "Tier 2 (R1): Detects alive, dead, and resumed PIDs from real `/proc/<pid>/cmdline'."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let* ((sid-alive   "88888888-8888-4888-8888-888888888881")
           (sid-resumed "88888888-8888-4888-8888-888888888882")
           (sid-dead    "88888888-8888-4888-8888-888888888883")
           (p1 (e2e--r1-spawn-dummy-proc "--session-id" sid-alive))
           (p2 (e2e--r1-spawn-dummy-proc "--resume" sid-resumed)))
      (unwind-protect
          (let ((pid1 (process-id p1))
                (pid2 (process-id p2)))
            (e2e--r1-write-meta state sid-alive
                                (list (format "sid=%s" sid-alive) (format "pid=%d" pid1)
                                      "cwd=/tmp" "agent=a" "started=2026-11-25T10:00:00Z"))
            (e2e--r1-write-meta state sid-resumed
                                (list (format "sid=%s" sid-resumed) "pid=999990"
                                      "cwd=/tmp" "agent=b" "started=2026-11-25T10:00:00Z"))
            (e2e--r1-write-meta state sid-dead
                                (list (format "sid=%s" sid-dead) "pid=999989"
                                      "cwd=/tmp" "agent=c" "started=2026-11-25T10:00:00Z"))
            (let* ((sexp (plist-get (e2e--r1-scan state jobs proj) :sexp))
                   (sa (e2e--r1-find-session sexp sid-alive))
                   (sr (e2e--r1-find-session sexp sid-resumed))
                   (sd (e2e--r1-find-session sexp sid-dead)))
              (should (equal (plist-get sa :state) "alive"))
              (should-not (plist-get sa :resumed))
              (should (equal (plist-get sa :live-pids) (list pid1)))
              (should (equal (plist-get sr :state) "alive"))
              (should (eq (plist-get sr :resumed) t))
              (should (member pid2 (plist-get sr :live-pids)))
              (should (equal (plist-get sd :state) "dead"))
              (should-not (plist-get sd :resumed))
              (should-not (plist-get sd :live-pids))))
        (when (process-live-p p1) (delete-process p1))
        (when (process-live-p p2) (delete-process p2))))))

(ert-deftest e2e-r1-t2-daemon-missing-malformed-and-cjk-slice ()
  "Tier 2 (R1): Skips missing/malformed state.json, slices >60-char CJK intent, falls back to name."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    ;; Dir without state.json (only tmp/)
    (make-directory (expand-file-name "nojson/tmp" jobs) t)
    ;; Dir with malformed JSON
    (e2e--r1-write-daemon-json jobs "badjson" "{broken json")
    ;; Dir with 70-char CJK intent
    (let ((cjk70 (make-string 70 ?漢)))
      (e2e--r1-write-daemon-json
       jobs "cjkjob01"
       (json-serialize `((daemonShort . "cjkjob01")
                         (state . "running")
                         (updatedAt . "2026-11-25T04:00:00Z")
                         (intent . ,cjk70)
                         (name . "cjk"))))
      ;; Dir with null intent falling back to name
      (e2e--r1-write-daemon-json
       jobs "nullint1"
       (json-serialize '((daemonShort . "nullint1")
                         (state . "stopped")
                         (updatedAt . "2026-11-25T04:01:00Z")
                         (intent . :null)
                         (name . "fallback-name"))))
      (let* ((res (e2e--r1-scan state jobs proj))
             (sexp (plist-get res :sexp))
             (dc (e2e--r1-find-daemon sexp "cjkjob01"))
             (dn (e2e--r1-find-daemon sexp "nullint1")))
        (should (zerop (plist-get res :exit)))
        (should-not (e2e--r1-find-daemon sexp "nojson"))
        (should-not (e2e--r1-find-daemon sexp "badjson"))
        (should dc)
        (should (= (length (plist-get dc :intent)) 60))
        (should (equal (plist-get dc :intent) (substring cjk70 0 60)))
        (should (equal (plist-get dc :raw-intent) cjk70))
        (should dn)
        (should (equal (plist-get dn :intent) "fallback-name"))))))

(ert-deftest e2e-r1-t2-jsonl-array-content-fallback-scan-and-head-cut ()
  "Tier 2 (R1): Array message.content, projects fallback scan without cwd=, >64KB head & mid-UTF-8 cut."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let ((sid-arr "99999999-9999-4999-8999-999999999991")
          (sid-big "99999999-9999-4999-8999-999999999992"))
      ;; Session 1: meta lacks cwd=, transcript in arbitrary subdir, array content
      (e2e--r1-write-meta
       state sid-arr
       (list (format "sid=%s" sid-arr) "pid=999981" "started=2026-11-25T05:00:00Z"))
      (e2e--r1-write-jsonl
       proj "-unrelated-slug" sid-arr
       (list (json-serialize
              '((type . "user")
                (cwd . "/tmp/discovered-from-jsonl")
                (message . ((role . "user")
                            (content . [((type . "tool_result") (content . "skip"))
                                        ((type . "text") (text . "Array block prompt"))])))))))
      ;; Session 2: >64KB queue-operation containing 3-byte CJK across byte 65536 boundary
      (e2e--r1-write-meta
       state sid-big
       (list (format "sid=%s" sid-big) "pid=999982" "cwd=/tmp/big"
             "agent=big" "started=2026-11-25T05:01:00Z"))
      (let* ((pad (make-string 22000 ?中)) ; 66,000 bytes in UTF-8
             (line0 (json-serialize `((type . "queue-operation") (cwd . "/tmp/big") (data . ,pad))))
             (line1 (json-serialize '((type . "user") (cwd . "/tmp/big")
                                      (message . ((role . "user") (content . "Past 64KB")))))))
        (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug "/tmp/big") sid-big (list line0 line1)))
      ;; Run at 65536 bytes: must not crash on mid-UTF-8 cut; sid-arr resolves; sid-big text is nil
      (let* ((res64 (e2e--r1-scan state jobs proj "--head-bytes" "65536"))
             (s64 (plist-get res64 :sexp))
             (sa (e2e--r1-find-session s64 sid-arr))
             (sb64 (e2e--r1-find-session s64 sid-big)))
        (should (zerop (plist-get res64 :exit)))
        (should (equal (plist-get sa :cwd) "/tmp/discovered-from-jsonl"))
        (should (equal (plist-get sa :first-user-text) "Array block prompt"))
        (should sb64)
        (should-not (plist-get sb64 :first-user-text)))
      ;; Run at 131072 bytes: sid-big resolves first-user-text
      (let* ((res128 (e2e--r1-scan state jobs proj "--head-bytes" "131072"))
             (sb128 (e2e--r1-find-session (plist-get res128 :sexp) sid-big)))
        (should (equal (plist-get sb128 :first-user-text) "Past 64KB"))))))

(ert-deftest e2e-r1-t2-uuid-not-found-and-session-rx-fix ()
  "Tier 2 (R1): `--uuid nonexistent' returns nil; `claude-jobs-view--parse' handles AGENT and alive,resumed."
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let* ((res (e2e--r1-scan state jobs proj "--uuid" "00000000-0000-4000-8000-000000000000")))
      (should (zerop (plist-get res :exit)))
      (should (null (plist-get res :sexp))))
    (let* ((uuid1 "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1")
           (uuid2 "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2")
           (sample (concat
                    "=== Dispatched sessions ===\n"
                    (format "%s  pid=58855(dead)  style-test-default   2026-05-14T22:47:33+08:00\n" uuid1)
                    (format "%s  pid=1234,5678(alive,resumed)  my-agent   2026-05-14T22:50:00+08:00\n" uuid2)
                    "\n=== Daemon jobs ===\n(none with state.json)\n"))
           (entries (claude-jobs-view--parse sample))
           (r1 (assoc (cons 'session uuid1) entries))
           (r2 (assoc (cons 'session uuid2) entries)))
      (should r1)
      (should r2)
      ;; UPDATED must be timestamp, NOT agent name
      (should (equal (substring-no-properties (aref (cadr r1) 4)) "2026-05-14T22:47:33+08:00"))
      (should (equal (substring-no-properties (aref (cadr r2) 4)) "2026-05-14T22:50:00+08:00"))
      (should (string-match-p "alive" (substring-no-properties (aref (cadr r2) 2)))))))

;;; F2 (R2): 6 tests

(ert-deftest e2e-r2-t2-exclude-records-anchored ()
  "Tier 2 (R2): `^records/' excludes top-level `records/' only, keeps `sub/records/', indexes ID-less files."
  (e2e-with-r2-fixture (root vault db _idloc)
    (e2e--write-utf8
     (expand-file-name "records/skip.org" vault)
     ":PROPERTIES:\n:ID: 20000000-0000-4000-8000-000000000001\n:END:\n#+title: Skip Me\n")
    (e2e--write-utf8
     (expand-file-name "sub/records/keep.org" vault)
     ":PROPERTIES:\n:ID: 20000000-0000-4000-8000-000000000002\n:END:\n#+title: Keep Me\n")
    (e2e--write-utf8
     (expand-file-name "plain.org" vault)
     "Plain note without ID or title.\n")
    (let ((db-elisp (expand-file-name "org-roam-elisp.db" root)))
      (e2e--r2-run-sync vault db "--exclude" "^records/")
      (e2e--r2-run-sync vault db-elisp "--exclude-elisp" "\\`records/")
      (let ((files (mapcar (lambda (r)
                             (file-relative-name (e2e--emacsql-read (car r)) vault))
                           (e2e--sqlite-query db "SELECT file FROM files ORDER BY file")))
            (files-elisp (mapcar (lambda (r)
                                   (file-relative-name (e2e--emacsql-read (car r)) vault))
                                 (e2e--sqlite-query db-elisp "SELECT file FROM files ORDER BY file")))
            (plain-title (car (e2e--sqlite-query
                               db "SELECT title FROM files WHERE file LIKE '%plain.org\"'")))
            (nodes (mapcar (lambda (r) (e2e--emacsql-read (car r)))
                           (e2e--sqlite-query db "SELECT id FROM nodes"))))
        (should-not (member "records/skip.org" files))
        (should (member "sub/records/keep.org" files))
        (should (member "plain.org" files))
        (should (equal files-elisp files))
        (should (equal (car plain-title) "\"\""))
        (should (equal (e2e--emacsql-read (car plain-title)) ""))
        (should (equal nodes '("20000000-0000-4000-8000-000000000002")))))))

(ert-deftest e2e-r2-t2-cjk-unicode-char-pos-and-search-option ()
  "Tier 2 (R2): Link `pos' is 1-based Unicode scalar offset and splits `::*Sub' search-option."
  (e2e-with-r2-fixture (root vault db _idloc)
    (let* ((elisp-vault (file-name-as-directory (expand-file-name "elisp-vault" root)))
           (elisp-db (expand-file-name "elisp.db" root))
           (id-src "20000000-0000-4000-8000-000000000010")
           (id-dst "20000000-0000-4000-8000-000000000011")
           (note-src (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: 中文筆記\n\n繁體中文測試前綴 [[id:%s::*Sub Heading][目標]]。\n"
                             id-src id-dst))
           (note-dst (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: 目標\n\n* Sub Heading\n" id-dst)))
      (e2e--write-utf8 (expand-file-name "src.org" vault) note-src)
      (e2e--write-utf8 (expand-file-name "dst.org" vault) note-dst)
      (e2e--copy-dir-contents vault elisp-vault)
      (e2e--r2-run-sync vault db)
      (e2e--r2-elisp-clean-sync elisp-vault elisp-db)
      (e2e--assert-roam-db-parity db vault elisp-db elisp-vault)
      (let* ((lrow (car (e2e--sqlite-query db "SELECT pos, dest, properties FROM links")))
             (props (e2e--emacsql-read (nth 2 lrow))))
        (should (equal (e2e--emacsql-read (nth 1 lrow)) id-dst))
        (should (equal (plist-get props :search-option) "*Sub Heading"))
        ;; Character offset must equal exact position of [[id:... in buffer, strictly less than UTF-8 byte pos
        (let ((char-pos (with-temp-buffer
                          (insert note-src)
                          (goto-char (point-min))
                          (search-forward "[[id:")
                          (match-beginning 0))))
          (should (= (nth 0 lrow) char-pos)))))))

(ert-deftest e2e-r2-t2-code-block-false-positives-and-roam-exclude ()
  "Tier 2 (R2): Ignores :ID:, [[id:...]], @cite in src/example blocks, and skips :ROAM_EXCLUDE: t."
  (e2e-with-r2-fixture (root vault db _idloc)
    (let* ((elisp-vault (file-name-as-directory (expand-file-name "elisp-vault" root)))
           (elisp-db (expand-file-name "elisp.db" root))
           (id-real "20000000-0000-4000-8000-000000000020")
           (id-excl "20000000-0000-4000-8000-000000000021")
           (id-fake "20000000-0000-4000-8000-000000000099"))
      (e2e--write-utf8
       (expand-file-name "blocks.org" vault)
       (format (concat ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Blocks\n\n"
                       "#+begin_src org\n,* Fake\n:PROPERTIES:\n:ID: %s\n:END:\n"
                       "[[id:%s]] [cite:@fakeCite]\n#+end_src\n\n"
                       "#+begin_example\n[[id:%s]] [cite:@fakeEx]\n#+end_example\n\n"
                       "* Excluded\n:PROPERTIES:\n:ID: %s\n:ROAM_EXCLUDE: t\n:END:\n")
               id-real id-fake id-fake id-fake id-excl))
      (e2e--copy-dir-contents vault elisp-vault)
      (e2e--r2-run-sync vault db)
      (e2e--r2-elisp-clean-sync elisp-vault elisp-db)
      (e2e--assert-roam-db-parity db vault elisp-db elisp-vault)
      (let ((nodes (mapcar (lambda (r) (e2e--emacsql-read (car r)))
                           (e2e--sqlite-query db "SELECT id FROM nodes"))))
        (should (equal nodes (list id-real)))
        (should (null (e2e--sqlite-query db "SELECT * FROM links")))
        (should (null (e2e--sqlite-query db "SELECT * FROM citations")))))))

(ert-deftest e2e-r2-t2-quoted-aliases-refs-and-fk-cascade ()
  "Tier 2 (R2): Mixed quoted/unquoted ROAM_ALIASES, protocol-stripped ROAM_REFS, FK cascade."
  (e2e-with-r2-fixture (root vault db _idloc)
    (let* ((elisp-vault (file-name-as-directory (expand-file-name "elisp-vault" root)))
           (elisp-db (expand-file-name "elisp.db" root))
           (id1 "20000000-0000-4000-8000-000000000030"))
      (e2e--write-utf8
       (expand-file-name "refs.org" vault)
       (format (concat ":PROPERTIES:\n:ID: %s\n"
                       ":ROAM_ALIASES: 連線池 \"connection pooler\" pool_mode\n"
                       ":ROAM_REFS: https://example.com/a @citeRef\n"
                       ":END:\n#+title: Refs Note\n")
               id1))
      (e2e--copy-dir-contents vault elisp-vault)
      (e2e--r2-run-sync vault db)
      (e2e--r2-elisp-clean-sync elisp-vault elisp-db)
      (e2e--assert-roam-db-parity db vault elisp-db elisp-vault)
      (let ((aliases (mapcar (lambda (r) (e2e--emacsql-read (car r)))
                             (e2e--sqlite-query db "SELECT alias FROM aliases ORDER BY alias")))
            (refs (mapcar (lambda (r) (mapcar #'e2e--emacsql-read r))
                          (e2e--sqlite-query db "SELECT ref, type FROM refs ORDER BY type"))))
        (should (equal aliases '("connection pooler" "pool_mode" "連線池")))
        (should (member '("//example.com/a" "https") refs))
        (should (member '("citeRef" "cite") refs)))
      (let ((conn (sqlite-open db)))
        (unwind-protect
            (progn
              (sqlite-execute conn "PRAGMA foreign_keys = ON")
              (sqlite-execute conn "DELETE FROM files")
              (should (equal (sqlite-select conn "SELECT count(*) FROM nodes") '((0))))
              (should (equal (sqlite-select conn "SELECT count(*) FROM aliases") '((0))))
              (should (equal (sqlite-select conn "SELECT count(*) FROM refs") '((0)))))
          (sqlite-close conn))))))

(ert-deftest e2e-r2-t2-incremental-add-modify-delete-and-force ()
  "Tier 2 (R2): Incremental add/modify/preserve/delete and `--force' match clean Elisp sync."
  (e2e-with-r2-fixture (root vault db _idloc)
    (let* ((elisp-vault (file-name-as-directory (expand-file-name "elisp-vault" root)))
           (elisp-db (expand-file-name "elisp.db" root))
           (id-keep "20000000-0000-4000-8000-000000000040")
           (id-mod  "20000000-0000-4000-8000-000000000041")
           (id-del  "20000000-0000-4000-8000-000000000042")
           (id-add  "20000000-0000-4000-8000-000000000043"))
      (e2e--write-utf8 (expand-file-name "keep.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Keep\n" id-keep))
      (e2e--write-utf8 (expand-file-name "mod.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Mod V1\n#+filetags: :v1:\n" id-mod))
      (e2e--write-utf8 (expand-file-name "del.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Delete Me\n" id-del))
      (e2e--r2-run-sync vault db)
      ;; Mutate vault: modify mod.org, delete del.org, add add.org, leave keep.org untouched
      (sleep-for 0.02)
      (e2e--write-utf8 (expand-file-name "mod.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Mod V2\n#+filetags: :v2:\n[[id:%s][Keep]]\n"
                               id-mod id-keep))
      (delete-file (expand-file-name "del.org" vault))
      (e2e--write-utf8 (expand-file-name "add.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Added\n" id-add))
      ;; Incremental sync
      (e2e--r2-run-sync vault db)
      (e2e--copy-dir-contents vault elisp-vault)
      (e2e--r2-elisp-clean-sync elisp-vault elisp-db)
      (e2e--assert-roam-db-parity db vault elisp-db elisp-vault)
      ;; --force rebuild produces identical parity
      (e2e--r2-run-sync vault db "--force")
      (e2e--assert-roam-db-parity db vault elisp-db elisp-vault))))

(ert-deftest e2e-r2-t2-org-id-merge-preserves-external ()
  "Tier 2 (R2): Merging org-id locations preserves external trees and matches `fenrir/org-id-index-directory'."
  (e2e-with-r2-fixture (root vault db idloc)
    (let* ((bin (e2e--require-binary "org-roam-sync"))
           (mode (e2e--r2-detect-org-id-flag bin))
           (ext-dir (file-name-as-directory (expand-file-name "external" root)))
           (ext-file (expand-file-name "ext.org" ext-dir))
           (ext-id "20000000-0000-4000-8000-000000000090")
           (id1 "20000000-0000-4000-8000-000000000091")
           (id2 "20000000-0000-4000-8000-000000000092"))
      (e2e--write-utf8 ext-file (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Ext\n" ext-id))
      (e2e--write-utf8 (expand-file-name "n1.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: N1\n" id1))
      (e2e--write-utf8 (expand-file-name "sub/n2.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: N2\n* H\n" id2))
      ;; Seed external entry in id-locations.el
      (e2e--write-utf8 idloc (format "((%S %S))\n" ext-file ext-id))
      (org-id-locations-load)
      (let* ((flag (if (eq mode 'out)
                       (list "--org-id-out" idloc)
                     (list "--emit-org-ids")))
             (res (apply #'e2e--r2-run-sync vault db flag)))
        (when (eq mode 'emit)
          ;; When CLI only emits alist to stdout, test merging via org-id-update-id-locations or sync
          (let ((emitted (car (read-from-string (plist-get res :stdout)))))
            (dolist (entry emitted)
              (let ((f (expand-file-name (car entry))))
                (dolist (id (cdr entry))
                  (puthash id f org-id-locations))))
            (org-id-locations-save)))
        (org-id-locations-load)
        ;; External entry preserved
        (let ((ext-loc (org-id-find ext-id)))
          (should ext-loc)
          (should (file-equal-p (car ext-loc) ext-file)))
        ;; Baseline via fenrir/org-id-index-directory on a parallel hash
        (let ((baseline-idloc (expand-file-name "baseline-idloc.el" root)))
          (let ((org-id-locations-file baseline-idloc)
                (org-id-locations (make-hash-table :test #'equal)))
            (fenrir/org-id-index-directory vault)
            (dolist (id (list id1 id2))
              (let ((b-loc (org-id-find id)))
                (should b-loc)
                (let ((org-id-locations-file idloc)
                      (org-id-locations nil))
                  (org-id-locations-load)
                  (let ((r-loc (org-id-find id)))
                    (should r-loc)
                    (should (file-equal-p (car r-loc) (car b-loc)))
                    (should (= (cdr r-loc) (cdr b-loc)))))))))))))

;;; F3 (R3): 6 tests

(ert-deftest e2e-r3-t2-bof-eof-empty-file-hunks ()
  "Tier 2 (R3): BOF delete/insert, EOF delete/insert, empty-to-text, text-to-empty match vc-git parity."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (e2e--write-utf8 (expand-file-name "bof-del.txt" repo) "a\nb\nc\n")
    (e2e--write-utf8 (expand-file-name "bof-ins.txt" repo) "b\nc\n")
    (e2e--write-utf8 (expand-file-name "eof-del.txt" repo) "a\nb\nc\n")
    (e2e--write-utf8 (expand-file-name "eof-ins.txt" repo) "a\nb\n")
    (e2e--write-utf8 (expand-file-name "empty2text.txt" repo) "")
    (e2e--write-utf8 (expand-file-name "text2empty.txt" repo) "x\ny\n")
    (e2e--git repo "add" ".")
    (e2e--git repo "commit" "-q" "-m" "init")
    (e2e--write-utf8 (expand-file-name "bof-del.txt" repo) "b\nc\n")
    (e2e--write-utf8 (expand-file-name "bof-ins.txt" repo) "a\nb\nc\n")
    (e2e--write-utf8 (expand-file-name "eof-del.txt" repo) "a\nb\n")
    (e2e--write-utf8 (expand-file-name "eof-ins.txt" repo) "a\nb\nc\n")
    (e2e--write-utf8 (expand-file-name "empty2text.txt" repo) "x\ny\n")
    (e2e--write-utf8 (expand-file-name "text2empty.txt" repo) "")
    (let* ((files '("bof-del.txt" "bof-ins.txt" "eof-del.txt" "eof-ins.txt"
                    "empty2text.txt" "text2empty.txt"))
           (oracle (e2e--vc-git-baseline-for-repo repo files t))
           (bufs (mapcar (lambda (rel) (cons rel (find-file-noselect (expand-file-name rel repo))))
                         files)))
      (diff-hl-magit-post-refresh)
      (dolist (pair bufs)
        (let* ((rel (car pair))
               (got (e2e--collect-diff-hl-state (cdr pair)))
               (exp (cdr (assoc rel oracle))))
          (should (eq (plist-get got :vc-state) (plist-get exp :vc-state)))
          (should (equal (plist-get got :hunks) (plist-get exp :hunks)))
          (should (equal (plist-get got :line-marks) (plist-get exp :line-marks))))))))

(ert-deftest e2e-r3-t2-no-trailing-newline ()
  "Tier 2 (R3): Adding/removing trailing newline matches `vc-git' `diff-hl' hunk parity."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (e2e--write-raw (expand-file-name "add-nl.txt" repo) "alpha\nbeta")
    (e2e--write-raw (expand-file-name "drop-nl.txt" repo) "alpha\nbeta\n")
    (e2e--git repo "add" ".")
    (e2e--git repo "commit" "-q" "-m" "init")
    (e2e--write-raw (expand-file-name "add-nl.txt" repo) "alpha\nbeta\n")
    (e2e--write-raw (expand-file-name "drop-nl.txt" repo) "alpha\nbeta")
    (let* ((files '("add-nl.txt" "drop-nl.txt"))
           (oracle (e2e--vc-git-baseline-for-repo repo files t))
           (bufs (mapcar (lambda (rel) (cons rel (find-file-noselect (expand-file-name rel repo))))
                         files)))
      (diff-hl-magit-post-refresh)
      (dolist (pair bufs)
        (let* ((rel (car pair))
               (got (e2e--collect-diff-hl-state (cdr pair)))
               (exp (cdr (assoc rel oracle))))
          (should (eq (plist-get got :vc-state) (plist-get exp :vc-state)))
          (should (equal (plist-get got :hunks) (plist-get exp :hunks))))))))

(ert-deftest e2e-r3-t2-unborn-head-repo ()
  "Tier 2 (R3): Repo with `git init' + `git add' and no commits classifies `added' and renders insert overlays."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      (e2e--write-utf8 (expand-file-name "new.txt" repo) "one\ntwo\nthree\n")
      (e2e--git repo "add" "new.txt")
      (let* ((res (e2e--run-command bin (list "-C" (directory-file-name repo) "--porcelain" "--all")))
             (parsed (e2e--parse-porcelain (plist-get res :stdout))))
        (should (zerop (plist-get res :exit)))
        (should (equal (plist-get (cdr (assoc "new.txt" parsed)) :state) "added")))
      (let* ((oracle (e2e--vc-git-baseline-for-repo repo '("new.txt") t))
             (buf (find-file-noselect (expand-file-name "new.txt" repo))))
        (diff-hl-magit-post-refresh)
        (let ((got (e2e--collect-diff-hl-state buf))
              (exp (cdr (assoc "new.txt" oracle))))
          (should (eq (plist-get got :vc-state) 'added))
          (should (equal (plist-get got :hunks) (plist-get exp :hunks))))))))

(ert-deftest e2e-r3-t2-binary-file-graceful ()
  "Tier 2 (R3): Binary NUL-byte tracked file reports `edited' VC state with 0 hunk overlays."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      (e2e--write-raw (expand-file-name "bin.dat" repo) "\0\1\2hello\0\n")
      (e2e--git repo "add" "bin.dat")
      (e2e--git repo "commit" "-q" "-m" "bin")
      (e2e--write-raw (expand-file-name "bin.dat" repo) "\0\1\200world\0\n")
      (let* ((res (e2e--run-command bin (list "-C" (directory-file-name repo) "--porcelain" "--all")))
             (parsed (e2e--parse-porcelain (plist-get res :stdout)))
             (entry (cdr (assoc "bin.dat" parsed))))
        (should (zerop (plist-get res :exit)))
        (should (equal (plist-get entry :state) "edited"))
        (should (null (plist-get entry :hunks))))
      (let ((buf (find-file-noselect (expand-file-name "bin.dat" repo))))
        (diff-hl-magit-post-refresh)
        (let ((got (e2e--collect-diff-hl-state buf)))
          (should (eq (plist-get got :vc-state) 'edited))
          (should (null (plist-get got :hunks)))
          (should (null (plist-get got :line-marks))))))))

(ert-deftest e2e-r3-t2-staged-only-and-staged-plus-unstaged ()
  "Tier 2 (R3): Staged-only (M ) and staged+unstaged (MM) changes match `vc-git' parity."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (e2e--write-utf8 (expand-file-name "staged.txt" repo) "a\nb\nc\n")
    (e2e--write-utf8 (expand-file-name "both.txt" repo) "1\n2\n3\n")
    (e2e--git repo "add" ".")
    (e2e--git repo "commit" "-q" "-m" "init")
    (e2e--write-utf8 (expand-file-name "staged.txt" repo) "a\nB\nc\n")
    (e2e--write-utf8 (expand-file-name "both.txt" repo) "1\nTWO\n3\n")
    (e2e--git repo "add" "staged.txt" "both.txt")
    (e2e--write-utf8 (expand-file-name "both.txt" repo) "1\nTWO\n3\n4\n")
    (let* ((files '("staged.txt" "both.txt"))
           (oracle (e2e--vc-git-baseline-for-repo repo files t))
           (bufs (mapcar (lambda (rel) (cons rel (find-file-noselect (expand-file-name rel repo))))
                         files)))
      (diff-hl-magit-post-refresh)
      (dolist (pair bufs)
        (let* ((rel (car pair))
               (got (e2e--collect-diff-hl-state (cdr pair)))
               (exp (cdr (assoc rel oracle))))
          (should (eq (plist-get got :vc-state) 'edited))
          (should (equal (plist-get got :hunks) (plist-get exp :hunks)))
          (should (equal (plist-get got :line-marks) (plist-get exp :line-marks))))))))

(ert-deftest e2e-r3-t2-out-of-repo-and-modified-buffer-skip ()
  "Tier 2 (R3): `diff-hl-magit-post-refresh' skips unsaved modified, non-file, and out-of-repo buffers."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo1
    (e2e-with-git-repo repo2
      (e2e--write-utf8 (expand-file-name "r1-edit.txt" repo1) "a\nb\n")
      (e2e--write-utf8 (expand-file-name "r1-dirty.txt" repo1) "x\ny\n")
      (e2e--git repo1 "add" ".")
      (e2e--git repo1 "commit" "-q" "-m" "init1")
      (e2e--write-utf8 (expand-file-name "r1-edit.txt" repo1) "a\nB\n")
      (e2e--write-utf8 (expand-file-name "r2-edit.txt" repo2) "p\nq\n")
      (e2e--git repo2 "add" ".")
      (e2e--git repo2 "commit" "-q" "-m" "init2")
      (e2e--write-utf8 (expand-file-name "r2-edit.txt" repo2) "p\nQ\n")
      (let ((b-edit (find-file-noselect (expand-file-name "r1-edit.txt" repo1)))
            (b-dirty (find-file-noselect (expand-file-name "r1-dirty.txt" repo1)))
            (b-other (find-file-noselect (expand-file-name "r2-edit.txt" repo2)))
            (b-nonfile (generate-new-buffer " *e2e-nonfile*")))
        (unwind-protect
            (progn
              ;; Make b-dirty modified unsaved; leave b-other clean against its own initial state
              (with-current-buffer b-dirty
                (goto-char (point-max))
                (insert "unsaved\n")
                (should (buffer-modified-p)))
              (with-current-buffer b-other
                (diff-hl-remove-overlays))
              (let ((default-directory repo1))
                (diff-hl-magit-post-refresh))
              ;; r1-edit refreshed
              (should (equal (plist-get (e2e--collect-diff-hl-state b-edit) :hunks)
                             '((2 3 change))))
              ;; r1-dirty keeps unsaved edits
              (with-current-buffer b-dirty
                (should (buffer-modified-p))
                (should (string-match-p "unsaved" (buffer-string))))
              ;; r2-edit outside repo1 was not refreshed by repo1's post-refresh
              (should (null (plist-get (e2e--collect-diff-hl-state b-other) :hunks))))
          (when (buffer-live-p b-nonfile) (kill-buffer b-nonfile)))))))

;;; F4 (M4 Fallback & Special Paths): 5 tests

(ert-deftest e2e-m4-t2-r1-missing-binary-fallback ()
  "Tier 2 (M4): Child Emacs without `rust/lib/claude-jobs-scan' falls back cleanly and keeps gptel helpers."
  (e2e-with-temp-dir fix
    (let* ((bin-dir (file-name-as-directory (expand-file-name "bin" fix)))
           (home-dir (file-name-as-directory (expand-file-name "home" fix)))
           (state (file-name-as-directory (expand-file-name "state" fix)))
           (jobs (file-name-as-directory (expand-file-name ".claude/jobs" home-dir)))
           (proj (file-name-as-directory (expand-file-name ".claude/projects" home-dir)))
           (sid "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
           (stub (expand-file-name "jobctl" bin-dir)))
      (make-directory bin-dir t)
      (make-directory state t)
      (make-directory jobs t)
      (make-directory proj t)
      (e2e--write-utf8
       stub
       (format "#!/bin/sh\necho '=== Dispatched sessions ==='\necho '%s  pid=1234(alive)  default  2026-11-25T10:00:00Z'\n" sid))
      (set-file-modes stub #o755)
      (e2e--write-utf8 (expand-file-name (concat sid ".meta") state)
                       (format "sid=%s\npid=1234\ncwd=/tmp/fb\n" sid))
      (let ((res (e2e--run-child-emacs-no-rust
                  `(progn
                     (load (expand-file-name "lisp/claude-jobs-view.el" user-emacs-directory) nil t)
                     (load (expand-file-name "lisp/init-ai.el" user-emacs-directory) nil t)
                     (require 'gptel)
                     (setq claude-jobs-view-state-dir ,state
                           claude-jobs-view-projects-dir ,proj)
                     (when (boundp 'claude-jobs-view-jobs-dir)
                       (set 'claude-jobs-view-jobs-dir ,jobs))
                     (let* ((default-directory ,fix)
                            (entries-res
                             (condition-case err
                                 (list :ok (length (claude-jobs-view--entries)))
                               (error (list :err (error-message-string err)))))
                            (helpers-ok
                             (and (fboundp 'claude-jobs-view--run-list)
                                  (fboundp 'claude-jobs-view--resolve-cwd)
                                  (fboundp 'claude-jobs-view--transcript-first-user-text)
                                  (fboundp 'claude-jobs-view--jobctl-string)
                                  (stringp (fenrir/gptel--safely
                                            (lambda () (error "probe")))))))
                       (list :entries entries-res :helpers helpers-ok)))
                  (list (concat "HOME=" (directory-file-name home-dir))
                        (concat "PATH=" (directory-file-name bin-dir) ":" (getenv "PATH"))
                        (concat "JOBCTL_STATE=" (directory-file-name state))))))
        (should (zerop (plist-get res :exit)))
        (let ((r (plist-get res :result)))
          (should (eq (plist-get r :helpers) t))
          (should (equal (plist-get r :entries) '(:ok 1))))))))

(ert-deftest e2e-m4-t2-r2-missing-binary-fallback ()
  "Tier 2 (M4): Child Emacs without `rust/lib/org-roam-sync' falls back to pure-Elisp `org-roam-db-sync'."
  (e2e-with-temp-dir fix
    (let ((vault (file-name-as-directory (expand-file-name "vault" fix)))
          (db (expand-file-name "roam.db" fix))
          (id1 "30000000-0000-4000-8000-000000000001")
          (id2 "30000000-0000-4000-8000-000000000002"))
      (e2e--write-utf8 (expand-file-name "a.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: FB A\n[[id:%s][B]]\n" id1 id2))
      (e2e--write-utf8 (expand-file-name "b.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: FB B\n" id2))
      (let ((res (e2e--run-child-emacs-no-rust
                  `(progn
                     (load (expand-file-name "lisp/init-org.el" user-emacs-directory) nil t)
                     (load (expand-file-name "lisp/init-org-roam.el" user-emacs-directory) nil t)
                     (remove-hook 'after-init-hook #'org-roam-db-autosync-mode)
                     (require 'org-roam)
                     (setq org-roam-directory ,vault
                           org-roam-db-location ,db
                           org-directory ,vault
                           org-agenda-files (list ,(expand-file-name "inbox.org" vault))
                           org-roam-db-autosync-mode nil)
                     (org-roam-db--close-all)
                     (clrhash org-roam-db--connection)
                     (org-roam-db-sync t)
                     (list :nodes (length (org-roam-node-list))
                           :backlinks (length (org-roam-backlinks-get
                                               (org-roam-node-from-id ,id2))))))))
        (should (zerop (plist-get res :exit)))
        (should (equal (plist-get res :result) '(:nodes 2 :backlinks 1)))))))

(ert-deftest e2e-m4-t2-r2-gpg-or-custom-predicate-fallback ()
  "Tier 2 (M4): `org-roam-db-sync' respects custom predicate fallback and `org-roam-sync' rejects `.org.gpg'."
  (e2e-with-r2-fixture (_root vault db _idloc)
    (let ((id-keep "30000000-0000-4000-8000-000000000010")
          (id-skip "30000000-0000-4000-8000-000000000011"))
      (e2e--write-utf8 (expand-file-name "keep.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Keep\n" id-keep))
      (e2e--write-utf8 (expand-file-name "skip.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Skip\n#+filetags: :skipme:\n" id-skip))
      (let ((org-roam-db-node-include-function
             (lambda () (not (member "skipme" (org-get-tags))))))
        (org-roam-db-sync t)
        (let ((ids (mapcar #'org-roam-node-id (org-roam-node-list))))
          (should (member id-keep ids))
          (should-not (member id-skip ids))))))
  (let ((bin (e2e--require-binary "org-roam-sync")))
    (e2e-with-r2-fixture (_root2 gpg-vault gpg-db _idloc2)
      ;; Bypass `epa-file-handler' so writing a dummy `.org.gpg' does not invoke `gpg'.
      (let ((file-name-handler-alist nil))
        (e2e--write-utf8 (expand-file-name "secret.org.gpg" gpg-vault) "dummy-pgp-ciphertext\n"))
      (let ((res (e2e--run-command
                  bin
                  (list "--dir" (directory-file-name gpg-vault) "--db" gpg-db))))
        (should-not (zerop (plist-get res :exit)))
        (should (= (plist-get res :exit) 2))))))

(ert-deftest e2e-m4-t2-r3-missing-binary-fallback ()
  "Tier 2 (M4): Child Emacs without `rust/lib/git-diff-hl' falls back cleanly to `vc-git'."
  (e2e-with-git-repo repo
    (let ((f (expand-file-name "fb.txt" repo)))
      (e2e--write-utf8 f "one\ntwo\n")
      (e2e--git repo "add" "fb.txt")
      (e2e--git repo "commit" "-q" "-m" "init")
      (e2e--write-utf8 f "one\nTWO\n")
      (let ((res (e2e--run-child-emacs-no-rust
                  `(progn
                     (require 'magit)
                     (load (expand-file-name "lisp/init-git.el" user-emacs-directory) nil t)
                     (let ((buf (find-file-noselect ,f))
                           (default-directory ,repo))
                       (diff-hl-magit-post-refresh)
                       (with-current-buffer buf
                         (let ((types (delq nil
                                            (mapcar (lambda (o)
                                                      (when (overlay-get o 'diff-hl-hunk)
                                                        (overlay-get o 'diff-hl-hunk-type)))
                                                    (overlays-in (point-min) (point-max))))))
                           (list :vc-state (vc-state ,f 'Git) :types types))))))))
        (should (zerop (plist-get res :exit)))
        (should (equal (plist-get res :result) '(:vc-state edited :types (change))))))))

(ert-deftest e2e-m4-t2-r3-special-path-chars ()
  "Tier 2 (M4): `git-diff-hl --stdin -z' handles spaces and non-ASCII UTF-8 paths."
  (let ((bin (e2e--require-binary "git-diff-hl")))
    (e2e-with-git-repo repo
      (let ((p1 "dir with space/中文 筆記.txt")
            (p2 "plain file.txt"))
        (e2e--write-utf8 (expand-file-name p1 repo) "a\nb\n")
        (e2e--write-utf8 (expand-file-name p2 repo) "x\ny\n")
        (e2e--git repo "add" ".")
        (e2e--git repo "commit" "-q" "-m" "special")
        (e2e--write-utf8 (expand-file-name p1 repo) "a\nb\nc\n")
        (let* ((payload (encode-coding-string (concat p1 "\0" p2 "\0") 'utf-8))
               (res (e2e--run-command
                     bin
                     (list "-C" (directory-file-name repo) "--porcelain" "--stdin" "-z")
                     payload))
               (parsed (e2e--parse-porcelain (plist-get res :stdout))))
          (should (zerop (plist-get res :exit)))
          (should (equal (plist-get (cdr (assoc p1 parsed)) :state) "edited"))
          (should (equal (plist-get (cdr (assoc p1 parsed)) :hunks) '((3 1 0 insert))))
          (should (equal (plist-get (cdr (assoc p2 parsed)) :state) "up-to-date")))))))

;;;; =========================================================================
;;;; TIER 3 — Cross-Feature Combinations (8 tests)
;;;; =========================================================================

(ert-deftest e2e-x-t3-r1-list-inspect-and-gptel ()
  "Tier 3 (R1): `claude-jobs-view' refresh + `i` inspect + `init-ai.el' `gptel` tools on one fixture."
  (e2e--require-binary "claude-jobs-scan")
  (e2e-with-r1-fixture (root state jobs proj _home)
    (let* ((sid "cccccccc-cccc-4ccc-8ccc-ccccccccccc1")
           (cwd (expand-file-name "proj-a" root))
           (slug (e2e--r1-cwd-slug cwd)))
      (make-directory cwd t)
      (e2e--r1-write-meta state sid (list (format "sid=%s" sid) "pid=999971"
                                          (format "cwd=%s" cwd) "agent=default"
                                          "started=2026-11-25T12:00:00Z"))
      (e2e--r1-write-jsonl proj slug sid
                           (list (json-serialize
                                  `((type . "user") (cwd . ,cwd)
                                    (message . ((role . "user")
                                                (content . "Inspect this prompt verbatim")))))))
      (save-window-excursion
        (claude-jobs-view))
      (with-current-buffer "*claude-jobs*"
        (goto-char (point-min))
        (while (and (not (eobp))
                    (not (equal (tabulated-list-get-id) (cons 'session sid))))
          (forward-line 1))
        (should (equal (tabulated-list-get-id) (cons 'session sid)))
        (save-window-excursion
          (claude-jobs-view-show-info))
        (let ((info-buf (get-buffer (format "*claude-jobs info %s*" (substring sid 0 8)))))
          (should (buffer-live-p info-buf))
          (with-current-buffer info-buf
            (let ((txt (buffer-string)))
              (should (string-match-p (regexp-quote sid) txt))
              (should (string-match-p "Inspect this prompt verbatim" txt))))))
      ;; Exercise gptel tools from init-ai.el (stage minimal jobctl stub only if missing on PATH)
      (let* ((has-jobctl (executable-find claude-jobs-view-jobctl-program))
             (stub-dir (unless has-jobctl
                         (let ((d (file-name-as-directory (expand-file-name "bin" root))))
                           (make-directory d t)
                           (let ((stub (expand-file-name "jobctl" d)))
                             (e2e--write-utf8
                              stub
                              (format "#!/bin/sh\necho '=== Dispatched sessions ==='\necho '%s  pid=999971(dead)  default  2026-11-25T12:00:00Z'\n" sid))
                             (set-file-modes stub #o755))
                           d)))
             (exec-path (if stub-dir (cons stub-dir exec-path) exec-path))
             (process-environment
              (if stub-dir
                  (cons (concat "PATH=" (directory-file-name stub-dir) ":" (getenv "PATH"))
                        process-environment)
                process-environment))
             (t-list (gptel-get-tool "claude_jobs_list"))
             (t-info (gptel-get-tool "claude_job_info"))
             (list-out (funcall (gptel-tool-function t-list)))
             (info-out (funcall (gptel-tool-function t-info) sid)))
        (should (stringp list-out))
        (should (string-match-p (regexp-quote sid) list-out))
        (should (stringp info-out))
        (should (string-match-p "Inspect this prompt verbatim" info-out))))))

(ert-deftest e2e-x-t3-r1-session-daemon-sort-and-help-echo ()
  "Tier 3 (R1): Mixed alive/dead/resumed sessions + CJK/missing-json daemons sort and render help-echo."
  (e2e--require-binary "claude-jobs-scan")
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (let* ((sid-a "dddddddd-dddd-4ddd-8ddd-ddddddddddd1")
           (sid-r "dddddddd-dddd-4ddd-8ddd-ddddddddddd2")
           (sid-d "dddddddd-dddd-4ddd-8ddd-ddddddddddd3")
           (p1 (e2e--r1-spawn-dummy-proc "--session-id" sid-a))
           (p2 (e2e--r1-spawn-dummy-proc "--resume" sid-r)))
      (unwind-protect
          (progn
            (e2e--r1-write-meta state sid-a (list (format "sid=%s" sid-a) (format "pid=%d" (process-id p1))
                                                  "cwd=/tmp/sa" "agent=a" "started=2026-11-25T10:00:00Z"))
            (e2e--r1-write-meta state sid-r (list (format "sid=%s" sid-r) "pid=999972"
                                                  "cwd=/tmp/sr" "agent=r" "started=2026-11-25T12:00:00Z"))
            (e2e--r1-write-meta state sid-d (list (format "sid=%s" sid-d) "pid=999973"
                                                  "cwd=/tmp/sd" "agent=d" "started=2026-11-25T08:00:00Z"))
            (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug "/tmp/sa") sid-a
                                 (list (json-serialize '((type . "user") (cwd . "/tmp/sa")
                                                         (message . ((role . "user") (content . "Line1\nLine2")))))))
            (make-directory (expand-file-name "skipme/tmp" jobs) t)
            (let ((long-cjk (make-string 75 ?語)))
              (e2e--r1-write-daemon-json
               jobs "cjk00001"
               (json-serialize `((daemonShort . "cjk00001") (state . "active")
                                 (updatedAt . "2026-11-25T13:00:00Z")
                                 (intent . ,long-cjk) (name . "cjk"))))
              (save-window-excursion (claude-jobs-view))
              (with-current-buffer "*claude-jobs*"
                (should (= (length tabulated-list-entries) 4))
                (tabulated-list-sort 0)
                (let ((d-row (assoc (cons 'daemon "cjk00001") tabulated-list-entries))
                      (s-row (assoc (cons 'session sid-a) tabulated-list-entries)))
                  (should d-row)
                  (should (= (length (substring-no-properties (aref (cadr d-row) 5))) 60))
                  (should (equal (get-text-property 0 'help-echo (aref (cadr d-row) 5)) long-cjk))
                  (should (equal (get-text-property 0 'help-echo (aref (cadr s-row) 5)) "Line1\nLine2"))))))
        (when (process-live-p p1) (delete-process p1))
        (when (process-live-p p2) (delete-process p2))))))

(ert-deftest e2e-x-t3-r2-sync-parity-vs-elisp-full ()
  "Tier 3 (R2): Full semantic parity across 7 tables and `org-roam-*' query APIs."
  (e2e-with-r2-fixture (root vault db _idloc)
    (let* ((elisp-vault (file-name-as-directory (expand-file-name "elisp-vault" root)))
           (elisp-db (expand-file-name "elisp.db" root))
           (id1 "40000000-0000-4000-8000-000000000001")
           (id2 "40000000-0000-4000-8000-000000000002")
           (id3 "40000000-0000-4000-8000-000000000003"))
      (e2e--write-utf8
       (expand-file-name "n1.org" vault)
       (format (concat ":PROPERTIES:\n:ID: %s\n:ROAM_ALIASES: \"First Alias\" AliasTwo\n"
                       ":ROAM_REFS: https://orgroam.com/doc\n:END:\n"
                       "#+title: 知識節點一\n#+filetags: :tag1:標籤2:\n\n"
                       "See [[id:%s][N2]] and [cite/t:@export].\n\n"
                       "* TODO [#B] Child\n:PROPERTIES:\n:ID: %s\n:END:\n"
                       "Backlink to [[id:%s::*Target][sub]].\n")
               id1 id2 id3 id2))
      (e2e--write-utf8
       (expand-file-name "n2.org" vault)
       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Node Two\n#+filetags: :tag2:\n\n* Target\n" id2))
      (e2e--copy-dir-contents vault elisp-vault)
      (e2e--r2-run-sync vault db)
      (e2e--r2-elisp-clean-sync elisp-vault elisp-db)
      (e2e--assert-roam-db-parity db vault elisp-db elisp-vault)
      ;; High-level org-roam API queries on Rust DB vs Elisp DB
      (let* ((rust-q
              (progn
                (org-roam-db--close-all)
                (clrhash org-roam-db--connection)
                (list
                 :nodes (sort (mapcar (lambda (n) (list (org-roam-node-id n)
                                                        (org-roam-node-title n)
                                                        (sort (copy-sequence (org-roam-node-aliases n)) #'string<)
                                                        (sort (copy-sequence (org-roam-node-tags n)) #'string<)
                                                        (org-roam-node-level n)))
                                      (org-roam-node-list))
                              (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b))))
                 :backlinks (length (org-roam-backlinks-get (org-roam-node-from-id id2)))
                 :by-alias (org-roam-node-id (org-roam-node-from-title-or-alias "First Alias"))
                 :by-ref (org-roam-node-id (org-roam-node-from-ref "https://orgroam.com/doc"))
                 :tags (sort (org-roam-tag-completions) #'string<))))
             (elisp-q
              (let ((org-roam-directory elisp-vault)
                    (org-roam-db-location elisp-db))
                (org-roam-db--close-all)
                (clrhash org-roam-db--connection)
                (list
                 :nodes (sort (mapcar (lambda (n) (list (org-roam-node-id n)
                                                        (org-roam-node-title n)
                                                        (sort (copy-sequence (org-roam-node-aliases n)) #'string<)
                                                        (sort (copy-sequence (org-roam-node-tags n)) #'string<)
                                                        (org-roam-node-level n)))
                                      (org-roam-node-list))
                              (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b))))
                 :backlinks (length (org-roam-backlinks-get (org-roam-node-from-id id2)))
                 :by-alias (org-roam-node-id (org-roam-node-from-title-or-alias "First Alias"))
                 :by-ref (org-roam-node-id (org-roam-node-from-ref "https://orgroam.com/doc"))
                 :tags (sort (org-roam-tag-completions) #'string<)))))
        (should (equal rust-q elisp-q))))))

(ert-deftest e2e-x-t3-r2-incremental-sync-plus-org-id-find ()
  "Tier 3 (R2): Incremental add/modify/delete combined with `org-id-locations' merge and `org-id-find'."
  (e2e-with-r2-fixture (root vault db idloc)
    (let* ((bin (e2e--require-binary "org-roam-sync"))
           (mode (e2e--r2-detect-org-id-flag bin))
           (ext-file (expand-file-name "ext/outside.org" root))
           (id-ext "40000000-0000-4000-8000-000000000090")
           (id-1   "40000000-0000-4000-8000-000000000091")
           (id-2   "40000000-0000-4000-8000-000000000092"))
      (e2e--write-utf8 ext-file (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Outside\n" id-ext))
      (e2e--write-utf8 (expand-file-name "one.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: One\n" id-1))
      (e2e--write-utf8 idloc (format "((%S %S))\n" ext-file id-ext))
      (org-id-locations-load)
      (org-roam-db-sync t)
      ;; Add note 2, run sync + org-id merge
      (e2e--write-utf8 (expand-file-name "two.org" vault)
                       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Two\n[[id:%s][One]]\n" id-2 id-1))
      (let ((flag (if (eq mode 'out) (list "--org-id-out" idloc) '("--emit-org-ids"))))
        (let ((res (apply #'e2e--r2-run-sync vault db flag)))
          (when (eq mode 'emit)
            (dolist (entry (car (read-from-string (plist-get res :stdout))))
              (dolist (id (cdr entry))
                (puthash id (expand-file-name (car entry)) org-id-locations)))
            (org-id-locations-save))))
      (org-id-locations-load)
      (org-roam-db--close-all)
      (clrhash org-roam-db--connection)
      (should (org-roam-node-from-id id-2))
      (should (file-equal-p (car (org-id-find id-ext)) ext-file))
      (should (file-equal-p (car (org-id-find id-2)) (expand-file-name "two.org" vault))))))

(ert-deftest e2e-x-t3-r3-magit-refresh-margin-autohide-flydiff ()
  "Tier 3 (R3): `diff-hl-magit-post-refresh' updates margins, autohide, and `diff-hl-flydiff-modified-tick'."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (let ((f (expand-file-name "auto.txt" repo)))
      (e2e--write-utf8 f "l1\nl2\nl3\n")
      (e2e--git repo "add" "auto.txt")
      (e2e--git repo "commit" "-q" "-m" "init")
      (e2e--write-utf8 f "l1\nL2\nl3\n")
      (let ((buf (find-file-noselect f))
            (diff-hl-autohide-margin t))
        (with-current-buffer buf
          (diff-hl-magit-post-refresh)
          (let ((st1 (e2e--collect-diff-hl-state buf)))
            (should (eq (plist-get st1 :vc-state) 'edited))
            (should (= (plist-get st1 :margin-width) 1))
            (should (= (plist-get st1 :tick) (buffer-chars-modified-tick)))
            (should (equal (plist-get st1 :hunks) '((2 3 change)))))
          ;; Stage and commit the change, revert buffer on disk, refresh
          (e2e--git repo "commit" "-q" "-am" "update")
          (diff-hl-magit-post-refresh)
          (let ((st2 (e2e--collect-diff-hl-state buf)))
            (should (eq (plist-get st2 :vc-state) 'up-to-date))
            (should (null (plist-get st2 :hunks)))
            (should (= (plist-get st2 :margin-width) 0))))))))

(ert-deftest e2e-x-t3-r3-amend-mode-and-reference-revision ()
  "Tier 3 (R3): `diff-hl-amend-mode' (HEAD^) survives `diff-hl-magit-post-refresh' with `vc-git' parity."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (let ((f (expand-file-name "amend.txt" repo)))
      (e2e--write-utf8 f "v1-line1\nv1-line2\nv1-line3\n")
      (e2e--git repo "add" "amend.txt")
      (e2e--git repo "commit" "-q" "-m" "c1")
      (e2e--write-utf8 f "v1-line1\nv2-line2\nv1-line3\n")
      (e2e--git repo "commit" "-q" "-am" "c2")
      ;; Compare with flydiff disabled to avoid upstream -U3 lexical bug on HEAD^
      (let ((oracle (e2e--vc-git-baseline-for-repo repo '("amend.txt") nil '("amend.txt")))
            (buf (find-file-noselect f)))
        (with-current-buffer buf
          (diff-hl-flydiff-mode -1)
          (unwind-protect
              (progn
                (diff-hl-amend-mode 1)
                (should (equal diff-hl-reference-revision "HEAD^"))
                (diff-hl-magit-post-refresh)
                (let ((got (e2e--collect-diff-hl-state buf))
                      (exp (cdr (assoc "amend.txt" oracle))))
                  (should (equal (plist-get got :hunks) (plist-get exp :hunks)))))
            (diff-hl-flydiff-mode 1)))))))

(ert-deftest e2e-x-t3-r1-r3-git-repo-with-claude-session ()
  "Tier 3 (R1+R3): Git-tracked project with active Claude session and open edited buffer in one Emacs."
  (e2e--require-binary "claude-jobs-scan")
  (e2e--require-binary "git-diff-hl")
  (e2e-with-r1-fixture (_root state jobs proj _home)
    (e2e-with-git-repo repo
      (let* ((f (expand-file-name "app.el" repo))
             (sid "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1")
             (proc (e2e--r1-spawn-dummy-proc "--session-id" sid)))
        (unwind-protect
            (progn
              (e2e--write-utf8 f "(defun foo () 1)\n")
              (e2e--git repo "add" "app.el")
              (e2e--git repo "commit" "-q" "-m" "init")
              (e2e--write-utf8 f "(defun foo () 2)\n")
              (e2e--r1-write-meta state sid (list (format "sid=%s" sid)
                                                  (format "pid=%d" (process-id proc))
                                                  (format "cwd=%s" (directory-file-name repo))
                                                  "agent=coder"
                                                  "started=2026-11-25T14:00:00Z"))
              (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug (directory-file-name repo)) sid
                                   (list (json-serialize
                                          `((type . "user")
                                            (cwd . ,(directory-file-name repo))
                                            (message . ((role . "user") (content . "Fix foo")))))))
              (let ((buf (find-file-noselect f)))
                (diff-hl-magit-post-refresh)
                (should (equal (plist-get (e2e--collect-diff-hl-state buf) :hunks)
                               '((1 2 change)))))
              (save-window-excursion (claude-jobs-view))
              (with-current-buffer "*claude-jobs*"
                (let ((row (assoc (cons 'session sid) tabulated-list-entries)))
                  (should row)
                  (should (equal (substring-no-properties (aref (cadr row) 2)) "alive")))))
          (when (process-live-p proc) (delete-process proc)))))))

(ert-deftest e2e-x-t3-r2-r3-org-vault-in-git-repo ()
  "Tier 3 (R2+R3): Git-tracked Org-roam vault syncs DB and updates `diff-hl' overlays on edited notes."
  (e2e--require-binary "org-roam-sync")
  (e2e--require-binary "git-diff-hl")
  (e2e-with-r2-fixture (_root vault db _idloc)
    (let ((id1 "40000000-0000-4000-8000-000000000101")
          (id2 "40000000-0000-4000-8000-000000000102")
          (f1 (expand-file-name "one.org" vault))
          (f2 (expand-file-name "two.org" vault)))
      (e2e--git vault "init" "-q" "-b" "main")
      (e2e--git vault "config" "user.email" "e2e@example.invalid")
      (e2e--git vault "config" "user.name" "E2E")
      (e2e--git vault "config" "commit.gpgsign" "false")
      (e2e--write-utf8 f1 (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: One\n" id1))
      (e2e--write-utf8 f2 (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Two\n" id2))
      (e2e--git vault "add" ".")
      (e2e--git vault "commit" "-q" "-m" "notes")
      ;; Edit f1 to add link to f2
      (e2e--write-utf8 f1 (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: One\nSee [[id:%s][Two]].\n" id1 id2))
      (let ((buf (find-file-noselect f1))
            (default-directory vault))
        (diff-hl-magit-post-refresh)
        (should (equal (plist-get (e2e--collect-diff-hl-state buf) :hunks)
                       '((5 6 insert)))))
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (should (= (length (org-roam-backlinks-get (org-roam-node-from-id id2))) 1)))))

;;;; =========================================================================
;;;; TIER 4 — Real-World Application Scenarios (6 tests)
;;;; =========================================================================

(ert-deftest e2e-r1-t4-full-jobs-dashboard-workflow ()
  "Tier 4 (R1): Realistic jobs dashboard workflow + optional read-only parity vs live `jobctl list'."
  (e2e--require-binary "claude-jobs-scan")
  (e2e-with-r1-fixture (root state jobs proj _home)
    (let* ((sid-a "ffffffff-ffff-4fff-8fff-fffffffffff1")
           (sid-r "ffffffff-ffff-4fff-8fff-fffffffffff2")
           (sid-d "ffffffff-ffff-4fff-8fff-fffffffffff3")
           (cwd1 (expand-file-name "repo-one" root))
           (proc1 (e2e--r1-spawn-dummy-proc "--session-id" sid-a))
           (proc2 (e2e--r1-spawn-dummy-proc "--resume" sid-r)))
      (unwind-protect
          (progn
            (make-directory cwd1 t)
            (e2e--r1-write-meta state sid-a (list (format "sid=%s" sid-a) (format "pid=%d" (process-id proc1))
                                                  (format "cwd=%s" cwd1) "agent=default"
                                                  "started=2026-11-25T15:00:00+08:00"))
            (e2e--r1-write-meta state sid-r (list (format "sid=%s" sid-r) "pid=999961"
                                                  "cwd=/tmp/resumed" "agent=reviewer"
                                                  "started=2026-11-25T14:00:00+08:00"))
            (e2e--r1-write-meta state sid-d (list (format "sid=%s" sid-d) "pid=999962"
                                                  "cwd=/tmp/dead" "agent=style"
                                                  "started=2026-11-25T13:00:00+08:00"))
            ;; Large transcript with >32KB init noise + CJK prompt
            (e2e--r1-write-jsonl
             proj (e2e--r1-cwd-slug cwd1) sid-a
             (list (json-serialize `((type . "system") (cwd . ,cwd1) (blob . ,(make-string 35000 ?x))))
                   (json-serialize `((type . "user") (cwd . ,cwd1)
                                     (message . ((role . "user") (content . "檢查並重構效能瓶頸")))))))
            (e2e--r1-write-jsonl
             proj (e2e--r1-cwd-slug "/tmp/resumed") sid-r
             (list (json-serialize '((type . "user") (cwd . "/tmp/resumed")
                                     (message . ((role . "user")
                                                 (content . [((type . "text") (text . "Resume review"))])))))))
            (e2e--r1-write-daemon-json
             jobs "daem0001"
             (json-serialize '((daemonShort . "daem0001") (state . "running")
                               (updatedAt . "2026-11-25T07:00:00Z")
                               (intent . "夜間索引排程任務") (name . "nightly"))))
            (save-window-excursion (claude-jobs-view))
            (with-current-buffer "*claude-jobs*"
              (should (= (length tabulated-list-entries) 4))
              (goto-char (point-min))
              (while (and (not (eobp))
                          (not (equal (tabulated-list-get-id) (cons 'session sid-a))))
                (forward-line 1))
              (save-window-excursion (claude-jobs-view-show-info))
              (let ((ibuf (get-buffer (format "*claude-jobs info %s*" (substring sid-a 0 8)))))
                (should (buffer-live-p ibuf))
                (with-current-buffer ibuf
                  (should (string-match-p "檢查並重構效能瓶頸" (buffer-string))))))
            (let ((gptel-info (funcall (gptel-tool-function (gptel-get-tool "claude_job_info")) sid-r)))
              (should (string-match-p "Resume review" gptel-info))))
        (when (process-live-p proc1) (delete-process proc1))
        (when (process-live-p proc2) (delete-process proc2)))))
  ;; Optional read-only parity against real ~/.cache/jobctl when present
  (let* ((real-home (getenv "HOME"))
         (real-state (or (getenv "JOBCTL_STATE") (expand-file-name ".cache/jobctl" real-home)))
         (real-jobs (expand-file-name ".claude/jobs" real-home))
         (real-proj (expand-file-name ".claude/projects" real-home)))
    (when (and (executable-find "jobctl") (file-directory-p real-state))
      (let* ((scan-res (e2e--run-command
                        (e2e--binary-path "claude-jobs-scan")
                        (list "--state-dir" real-state "--jobs-dir" real-jobs "--projects-dir" real-proj)))
             (jctl-res (e2e--run-command "jobctl" '("list")))
             (sexp (car (read-from-string (plist-get scan-res :stdout)))))
        (should (zerop (plist-get scan-res :exit)))
        (dolist (line (split-string (plist-get jctl-res :stdout) "\n" t))
          (when (string-match
                 "\\`\\([0-9a-f-]+\\)[ \t]+pid=\\([0-9,]+\\)(\\([a-z,]+\\))[ \t]+\\([^ \t]+\\)[ \t]+\\([^ \t]+\\)"
                 line)
            (let* ((sid (match-string 1 line))
                   (pids-str (match-string 2 line))
                   (st  (match-string 3 line))
                   (s   (e2e--r1-find-session sexp sid))
                   (scan-pid-str
                    (cond
                     ((plist-get s :live-pids)
                      (mapconcat #'number-to-string (plist-get s :live-pids) ","))
                     ((integerp (plist-get s :pid))
                      (number-to-string (plist-get s :pid)))
                     (t ""))))
              (should s)
              (should (equal (plist-get s :state)
                             (if (string-prefix-p "alive" st) "alive" "dead")))
              (should (equal scan-pid-str pids-str)))))))))

(ert-deftest e2e-r2-t4-multi-note-knowledge-graph-workflow ()
  "Tier 4 (R2): 120-file synthetic knowledge graph with edit/delete cycle and `org-roam' queries."
  (e2e--require-binary "org-roam-sync")
  (e2e-with-r2-fixture (root vault db idloc)
    (let ((ids (cl-loop for i from 1 to 120
                        collect (format "50000000-0000-4000-8000-%012d" i))))
      (dotimes (idx 120)
        (let* ((i (1+ idx))
               (id (nth idx ids))
               (next-id (nth (mod i 120) ids))
               (sub (if (zerop (mod i 3)) "sub/records" "topic")))
          (e2e--write-utf8
           (expand-file-name (format "%s/note-%03d.org" sub i) vault)
           (format (concat ":PROPERTIES:\n:ID: %s\n:ROAM_ALIASES: \"別名 %d\"\n:END:\n"
                           "#+title: 筆記 %03d\n#+filetags: :grp%d:\n\n"
                           "Links to [[id:%s][Next]].\n")
                   id i i (mod i 5) next-id))))
      (e2e--write-utf8
       (expand-file-name "records/excluded.org" vault)
       ":PROPERTIES:\n:ID: 50000000-0000-4000-8000-999999999999\n:END:\n#+title: Excluded\n")
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (clrhash org-roam-db--connection)
      (should (= (length (e2e--sqlite-query db "SELECT id FROM nodes")) 120))
      (should (= (length (org-roam-node-list)) 240)) ; 120 titles + 120 aliases
      ;; Incremental edit + delete cycle
      (delete-file (expand-file-name "topic/note-001.org" vault))
      (e2e--write-utf8
       (expand-file-name "topic/note-002.org" vault)
       (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Updated 002\n" (nth 1 ids)))
      (org-roam-db-sync)
      (org-roam-db--close-all)
      (clrhash org-roam-db--connection)
      (should (= (length (e2e--sqlite-query db "SELECT id FROM nodes")) 119))
      (should-not (org-roam-node-from-id (nth 0 ids)))
      (should (equal (org-roam-node-title (org-roam-node-from-id (nth 1 ids))) "Updated 002"))
      ;; org-id resolution check
      (fenrir/org-id-index-directory vault)
      (should (file-exists-p idloc))
      (should (org-id-find (nth 1 ids)))
      (should (file-directory-p root)))))

(ert-deftest e2e-r3-t4-multi-buffer-git-edit-stage-commit-refresh ()
  "Tier 4 (R3): 40-buffer tracked repo through edit/stage/commit/revert cycles with sub-65ms batch refresh."
  (e2e--require-binary "git-diff-hl")
  (e2e-with-git-repo repo
    (let ((files (cl-loop for i from 1 to 40 collect (format "mod-%02d.el" i)))
          (bufs '()))
      (dolist (rel files)
        (e2e--write-utf8
         (expand-file-name rel repo)
         (mapconcat (lambda (n) (format "(defun fn-%s-%d () %d)" rel n n))
                    (number-sequence 1 20) "\n")))
      (e2e--git repo "add" ".")
      (e2e--git repo "commit" "-q" "-m" "40 files")
      ;; Edit 12 files on disk
      (dotimes (i 12)
        (let* ((rel (nth i files))
               (p (expand-file-name rel repo)))
          (e2e--write-utf8
           p
           (concat (mapconcat (lambda (n) (format "(defun fn-%s-%d () %d)" rel n (if (= n 5) 999 n)))
                              (number-sequence 1 20) "\n")
                   "\n;; extra\n"))))
      (setq bufs (mapcar (lambda (rel) (cons rel (find-file-noselect (expand-file-name rel repo))))
                         files))
      ;; Warmup + median of 3 measured batch refreshes
      (diff-hl-magit-post-refresh)
      (let* ((samples-ms
              (cl-loop repeat 3
                       collect (let ((t0 (current-time)))
                                 (diff-hl-magit-post-refresh)
                                 (* 1000.0 (float-time (time-subtract (current-time) t0))))))
             (sorted (sort (copy-sequence samples-ms) #'<))
             (median-ms (nth 1 sorted)))
        (message "e2e-r3-t4: 40-buffer diff-hl-magit-post-refresh samples=%S median=%.2fms"
                 samples-ms median-ms)
        (should (< median-ms 65.0)))
      ;; Verify vc-git oracle parity on subset of clean and edited buffers
      (let* ((check-files '("mod-01.el" "mod-05.el" "mod-12.el" "mod-25.el" "mod-40.el"))
             (oracle (e2e--vc-git-baseline-for-repo repo check-files t)))
        (dolist (rel check-files)
          (let ((got (e2e--collect-diff-hl-state (cdr (assoc rel bufs))))
                (exp (cdr (assoc rel oracle))))
            (should (eq (plist-get got :vc-state) (plist-get exp :vc-state)))
            (should (equal (plist-get got :hunks) (plist-get exp :hunks))))))
      ;; Stage + commit one edited file, revert another, refresh and check state transitions
      (e2e--git repo "add" "mod-01.el")
      (e2e--git repo "commit" "-q" "-m" "commit mod-01")
      (e2e--git repo "checkout" "--" "mod-02.el")
      (diff-hl-magit-post-refresh)
      (should (eq (plist-get (e2e--collect-diff-hl-state (cdr (assoc "mod-01.el" bufs))) :vc-state)
                  'up-to-date))
      (should (null (plist-get (e2e--collect-diff-hl-state (cdr (assoc "mod-01.el" bufs))) :hunks)))
      (should (eq (plist-get (e2e--collect-diff-hl-state (cdr (assoc "mod-02.el" bufs))) :vc-state)
                  'up-to-date)))))

(ert-deftest e2e-r3-t4-repo-readonly-batch-diff-hl ()
  "Tier 4 (R3): Read-only `git-diff-hl --porcelain --stdin' across 35+ tracked files in repo root."
  (let* ((bin (e2e--require-binary "git-diff-hl"))
         (ls-res (e2e--run-command "git" '("ls-files" "--" "lisp/*.el" "lisp/languages/*.el")
                                   nil nil e2e--repo-root))
         (tracked (seq-take (split-string (plist-get ls-res :stdout) "\n" t) 40)))
    (should (zerop (plist-get ls-res :exit)))
    (should (>= (length tracked) 30))
    (let* ((res (e2e--run-command
                 bin
                 (list "-C" (directory-file-name e2e--repo-root) "--porcelain" "--stdin")
                 (concat (string-join tracked "\n") "\n")))
           (parsed (e2e--parse-porcelain (plist-get res :stdout)))
           (valid-states '("up-to-date" "edited" "added" "removed" "conflict" "unregistered" "ignored")))
      (should (zerop (plist-get res :exit)))
      (should (= (length parsed) (length tracked)))
      (dolist (f tracked)
        (let ((entry (cdr (assoc f parsed))))
          (should entry)
          (should (member (plist-get entry :state) valid-states)))))))

(ert-deftest e2e-r2-t4-vault-readonly-parity-subset ()
  "Tier 4 (R2): Read-only copy/temp-DB parity on representative vault notes with zero live writes."
  (e2e--require-binary "org-roam-sync")
  (let* ((live-vault (file-truename "~/code/org-roam"))
         (live-db (expand-file-name "var/org/org-roam.db" e2e--repo-root))
         (live-db-snap (e2e--file-stat-snapshot live-db))
         (use-live (let ((v (getenv "EMACS_RUST_E2E_LIVE_VAULT")))
                     (and v (not (string-empty-p v)) (file-directory-p live-vault)))))
    (e2e-with-r2-fixture (root vault db _idloc)
      (if use-live
          (progn
            (e2e--r2-run-sync live-vault db "--exclude" "^records/")
            (should (equal (e2e--sqlite-query db "PRAGMA user_version") '((20))))
            (should (> (caar (e2e--sqlite-query db "SELECT count(*) FROM nodes")) 100))
            (when (file-directory-p (expand-file-name "records" live-vault))
              (should (null (e2e--sqlite-query
                             db "SELECT file FROM files WHERE file LIKE '%/org-roam/records/%'"))))
            (when (file-directory-p (expand-file-name "BETB/records" live-vault))
              (should (>= (caar (e2e--sqlite-query
                                 db "SELECT count(*) FROM files WHERE file LIKE '%/BETB/records/%'"))
                          1))))
        ;; Build temp copy of representative real vault patterns (or up to 15 read-only real files)
        (let ((elisp-vault (file-name-as-directory (expand-file-name "elisp-vault" root)))
              (elisp-db (expand-file-name "elisp.db" root))
              (real-samples (when (file-directory-p live-vault)
                              (seq-take (directory-files live-vault t "\\.org\\'") 15))))
          (if real-samples
              (dolist (f real-samples)
                (copy-file f (expand-file-name (file-name-nondirectory f) vault) t t))
            (dotimes (i 15)
              (e2e--write-utf8
               (expand-file-name (format "sample-%02d.org" i) vault)
               (format ":PROPERTIES:\n:ID: 60000000-0000-4000-8000-%012d\n:END:\n#+title: Sample %d\n#+filetags: :real:\n"
                       i i))))
          (e2e--copy-dir-contents vault elisp-vault)
          (e2e--r2-run-sync vault db "--exclude" "^records/")
          (e2e--r2-elisp-clean-sync elisp-vault elisp-db)
          (e2e--assert-roam-db-parity db vault elisp-db elisp-vault)))
      (should (equal (e2e--file-stat-snapshot live-db) live-db-snap)))))

(ert-deftest e2e-x-t4-unified-emacs-session-workflow ()
  "Tier 4 (R1+R2+R3): Single long-lived session exercising R1, R2, and R3 sequentially without leakage."
  (e2e--require-binary "claude-jobs-scan")
  (e2e--require-binary "org-roam-sync")
  (e2e--require-binary "git-diff-hl")
  (e2e-with-r1-fixture (_r1-root state jobs proj _home)
    (e2e-with-r2-fixture (_r2-root vault db idloc)
      (e2e-with-git-repo repo
        ;; 1. R1 jobs workflow
        (let ((sid "70000000-0000-4000-8000-000000000001"))
          (e2e--r1-write-meta state sid (list (format "sid=%s" sid) "pid=999951"
                                              (format "cwd=%s" (directory-file-name repo))
                                              "agent=unified" "started=2026-11-25T16:00:00Z"))
          (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug (directory-file-name repo)) sid
                               (list (json-serialize
                                      `((type . "user") (cwd . ,(directory-file-name repo))
                                        (message . ((role . "user") (content . "Unified task")))))))
          (save-window-excursion (claude-jobs-view))
          (with-current-buffer "*claude-jobs*"
            (should (assoc (cons 'session sid) tabulated-list-entries))))
        ;; 2. R2 org-roam + org-id workflow
        (let ((nid1 "70000000-0000-4000-8000-000000000011")
              (nid2 "70000000-0000-4000-8000-000000000012"))
          (e2e--write-utf8 (expand-file-name "u1.org" vault)
                           (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Unified 1\n[[id:%s][U2]]\n"
                                   nid1 nid2))
          (e2e--write-utf8 (expand-file-name "u2.org" vault)
                           (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Unified 2\n" nid2))
          (org-roam-db-sync t)
          (fenrir/org-id-index-directory vault)
          (should (file-exists-p db))
          (should (file-exists-p idloc))
          (should (= (length (org-roam-backlinks-get (org-roam-node-from-id nid2))) 1)))
        ;; 3. R3 git diff-hl workflow
        (let ((gf (expand-file-name "u.el" repo)))
          (e2e--write-utf8 gf "(message \"v1\")\n")
          (e2e--git repo "add" "u.el")
          (e2e--git repo "commit" "-q" "-m" "u")
          (e2e--write-utf8 gf "(message \"v2\")\n")
          (let ((buf (find-file-noselect gf)))
            (diff-hl-magit-post-refresh)
            (should (equal (plist-get (e2e--collect-diff-hl-state buf) :hunks)
                           '((1 2 change))))))
        ;; 4. Live state remained completely untouched
        (dolist (entry e2e--live-state-snapshots)
          (should (equal (e2e--file-stat-snapshot (car entry)) (cdr entry))))))))

(ert-deftest e2e-m4-t2-magit-status-overview-suite-standalone ()
  "Tier 2 (M4): `shell/test-magit-status-overview.el' runs standalone under `emacs -Q --batch'."
  (let* ((emacs-bin (expand-file-name invocation-name invocation-directory))
         (suite (expand-file-name "shell/test-magit-status-overview.el" e2e--repo-root))
         (res (e2e--run-command
               emacs-bin
               (list "-Q" "--batch" "-l" suite "-f" "ert-run-tests-batch-and-exit"))))
    (should (zerop (plist-get res :exit)))))

(ert-deftest e2e-m4-t2-all-binaries-invalid-flags-and-missing-values ()
  "Tier 2 (M4): All 3 binaries exit non-zero on unknown flags, short flags, and missing flag values."
  (let ((b1 (e2e--require-binary "claude-jobs-scan"))
        (b2 (e2e--require-binary "org-roam-sync"))
        (b3 (e2e--require-binary "git-diff-hl")))
    (dolist (case-spec
             (list (list b1 '("--unknown-flag"))
                   (list b1 '("-x"))
                   (list b1 '("--state-dir"))
                   (list b1 '("--head-bytes" "notanint"))
                   (list b1 '("--uuid" "../bad"))
                   (list b2 '("--unknown-flag"))
                   (list b2 '("-x"))
                   (list b2 '()) ; missing required --dir
                   (list b2 '("--dir"))
                   (list b3 '("--unknown-flag"))
                   (list b3 '("-x"))
                   (list b3 '("-C"))
                   (list b3 '("-z")) ; requires --stdin
                   (list b3 '("--porcelain" "--sexp"))
                   (list b3 '("--all" "foo"))
                   (list b3 '("--stdin" "foo"))))
      (let ((res (e2e--run-command (car case-spec) (cadr case-spec))))
        (should-not (zerop (plist-get res :exit)))))))

(ert-deftest e2e-m4-t2-r1-r2-special-path-chars ()
  "Tier 2 (M4): `claude-jobs-scan' and `org-roam-sync' handle spaces, quotes, %, and CJK in paths."
  (e2e--require-binary "claude-jobs-scan")
  (e2e--require-binary "org-roam-sync")
  ;; R1 special paths
  (e2e-with-temp-dir root
    (let* ((base (expand-file-name "r1 空間 dir" root))
           (state (file-name-as-directory (expand-file-name "state" base)))
           (jobs (file-name-as-directory (expand-file-name "jobs" base)))
           (proj (file-name-as-directory (expand-file-name "proj" base)))
           (sid "88888888-8888-4888-8888-888888888899")
           (cwd "/tmp/cjk 筆記 dir"))
      (make-directory state t)
      (make-directory jobs t)
      (make-directory proj t)
      (e2e--r1-write-meta state sid
                          (list (format "sid=%s" sid) "pid=999998"
                                "cwd=/tmp/cjk\\ 筆記\\ dir" "agent=a"
                                "started=2026-11-25T10:00:00Z"))
      (e2e--r1-write-jsonl proj (e2e--r1-cwd-slug cwd) sid
                           (list (json-serialize `((type . "user") (cwd . ,cwd)
                                                   (message . ((role . "user") (content . "CJK path ok")))))))
      (let* ((res (e2e--r1-scan state jobs proj))
             (s (e2e--r1-find-session (plist-get res :sexp) sid)))
        (should (zerop (plist-get res :exit)))
        (should s)
        (should (equal (plist-get s :cwd) cwd))
        (should (equal (plist-get s :first-user-text) "CJK path ok")))))
  ;; R2 special paths (spaces, quotes, %, CJK in vault dir and filename)
  (e2e-with-temp-dir root
    (let* ((vault (file-name-as-directory (expand-file-name "r2 筆記 \"dir\" %1" root)))
           (db (expand-file-name "r2.db" root))
           (idloc (expand-file-name "r2-ids.el" root))
           (note (expand-file-name "sub 空間/筆記 \"1\" %test.org" vault))
           (nid "80000000-0000-4000-8000-000000000001"))
      (e2e--write-utf8 note (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: Special Path\n" nid))
      (e2e--r2-run-sync vault db "--org-id-out" idloc)
      (let ((files (mapcar (lambda (r) (e2e--emacsql-read (car r)))
                           (e2e--sqlite-query db "SELECT file FROM files")))
            (ids (with-temp-buffer
                   (insert-file-contents idloc)
                   (read (current-buffer)))))
        (should (= (length files) 1))
        (should (file-equal-p (car files) note))
        (should (member nid (cdr (car ids))))))))

(provide 'test-rust-perf-e2e)
;;; test-rust-perf-e2e.el ends here
