;;; org-roam-sync-test.el --- ERT tests for org-roam-sync integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Run with:
;;   emacs -Q --batch -l test/org-roam-sync-test.el -f ert-run-tests-batch-and-exit
;;
;; All state (`org-roam-db-location', `org-id-locations-file',
;; `org-persist-directory', and per-test vaults) is strictly isolated to
;; temporary directories under /tmp so `~/code/org-roam' and `var/org/' are
;; never modified.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst orst--root
  (file-name-as-directory
   (expand-file-name
    ".." (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root derived from this test file's path.")

(setq user-emacs-directory orst--root
      package-user-dir (expand-file-name "elpa" orst--root))

(require 'package)
(package-initialize)

(require 'use-package)
(setq use-package-always-ensure nil)

(defconst orst--state
  (file-name-as-directory (make-temp-file "orst-state-" t))
  "Throwaway state directory so tests never touch var/org/.")
(add-hook 'kill-emacs-hook
          (lambda ()
            (when (file-directory-p orst--state)
              (delete-directory orst--state t))))

(setq org-roam-db-location (expand-file-name "boot-roam.db" orst--state)
      org-id-locations-file (expand-file-name "boot-id-locations.el" orst--state)
      org-persist-directory (expand-file-name "org-persist/" orst--state)
      org-roam-db-autosync-mode nil)

(add-to-list 'load-path (expand-file-name "lisp" orst--root))
(require 'init-org)
(require 'init-org-roam)
(require 'org-roam)
(require 'org-id)

(defun orst--write-file (path content)
  "Write CONTENT to PATH, creating parent directories as needed."
  (make-directory (file-name-directory path) t)
  (let ((coding-system-for-write 'utf-8-unix)
        (file-name-handler-alist nil))
    (write-region content nil path nil 'silent)))

(defmacro orst-with-vault (vars &rest body)
  "Create an isolated temp vault and bind VARS (`tmp', `vault', `db', `idfile')."
  (declare (indent 1))
  (let ((tmp-sym (nth 0 vars))
        (vault-sym (nth 1 vars))
        (db-sym (nth 2 vars))
        (idfile-sym (nth 3 vars)))
    `(let* ((,tmp-sym (file-name-as-directory (make-temp-file "orst-vault-" t)))
            (,vault-sym (file-name-as-directory (expand-file-name "vault" ,tmp-sym)))
            (,db-sym (expand-file-name "org-roam.db" ,tmp-sym))
            (,idfile-sym (expand-file-name "id-locations.el" ,tmp-sym)))
       (make-directory ,vault-sym t)
       (let ((org-roam-directory (file-truename ,vault-sym))
             (org-roam-db-location ,db-sym)
             (org-roam-file-exclude-regexp '("\\`records/"))
             (org-roam-db--connection (make-hash-table :test #'equal))
             (org-roam-db-autosync-mode nil)
             (org-id-locations-file ,idfile-sym)
             (org-id-locations nil)
             (org-id-files nil)
             (org-id--locations-checksum nil)
             (org-agenda-files nil)
             (org-id-extra-files nil))
         (unwind-protect
             (progn ,@body)
           (ignore-errors (org-roam-db--close-all))
           (when (file-directory-p ,tmp-sym)
             (delete-directory ,tmp-sym t)))))))

;;; Pure Elisp unit tests

(ert-deftest orst-test-translate-exclude ()
  "Verify Elisp regexp translation to Rust regex and unsupported rejection."
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\`records/") "^records/"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "archive\\.org\\'") "archive\\.org$"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\(a\\|b\\)/\\(c\\)") "(a|b)/(c)"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "dir(1)/") "dir\\(1\\)/"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "a|b/") "a\\|b/"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\\\(") "\\\\\\("))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[a-z]+/") "[a-z]+/"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[[:digit:]\\`a]") "[[:digit:]\\\\`a]"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[[:digit:]()]") "[[:digit:]()]"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "foo^bar") "foo\\^bar"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "baz$qux") "baz\\$qux"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\(foo\\|^bar\\)") "(foo|^bar)"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "(a|^b)") "\\(a\\|\\^b\\)"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\(a$\\|b\\)") "(a$|b)"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\(?:^bar\\)") "(?:^bar)"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[[]") "[\\[]"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[a&&b]") "[a\\&\\&b]"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[a--b]") "[b]"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "[a~~b]") "[a\\~\\~b]"))
  (should-not (fenrir/org-roam-sync--translate-exclude "\\(?1:foo\\)"))
  (should-not (fenrir/org-roam-sync--translate-exclude "\\(?i:A\\)"))
  (should-not (fenrir/org-roam-sync--translate-exclude "\\(?"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\(?:foo\\)") "(?:foo)"))
  (should-not (fenrir/org-roam-sync--translate-exclude "[[:alpha:]--[:digit:]]"))
  (should-not (fenrir/org-roam-sync--translate-exclude "[a-[:digit:]]"))
  (should-not (fenrir/org-roam-sync--translate-exclude "[[:alpha:]-z]"))
  (should-not (fenrir/org-roam-sync--translate-exclude "\\`[[:word:]]\\."))
  (should-not (fenrir/org-roam-sync--translate-exclude "[^[:word:]]"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\d\\n\\A\\z") "dnAz"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\*foo\\/") "\\*foo\\/"))
  (should-not (fenrir/org-roam-sync--translate-exclude "\\_<word\\_>"))
  (should-not (fenrir/org-roam-sync--translate-exclude "foo\\s-bar"))
  (should-not (fenrir/org-roam-sync--translate-exclude "\\(a\\)\\1"))
  ;; Verify global match-data is preserved
  (let ((sample "sentinel-match"))
    (should (string-match "sentinel" sample))
    (should (equal (fenrir/org-roam-sync--translate-exclude "[[:digit:]]\\(?1:x\\)") nil))
    (should (equal (match-string 0 sample) "sentinel")))
  ;; Non-leading `\{\}` -> `{0,0}` vs leading `\{\}` -> literal `\{\}`, and `\{...\}?` rejected
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\{\\}") "\\{\\}"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "^\\{\\}") "^\\{\\}"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\{\\}?b") "\\{\\}?b"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "a\\{\\}b") "a{0,0}b"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "\\(a\\)\\{\\}b") "(a){0,0}b"))
  (should (equal (fenrir/org-roam-sync--translate-exclude "a\\{1,2\\}\\?") "a{1,2}\\?"))
  (should-not (fenrir/org-roam-sync--translate-exclude "a\\{\\}?"))
  (should-not (fenrir/org-roam-sync--translate-exclude "a\\{1,2\\}?"))
  (should-not (fenrir/org-roam-sync--translate-exclude "a\\{1,2\\}\\{1,2\\}?"))
  (should (equal (fenrir/org-roam-sync--translate-excludes '("\\`records/" "tmp/"))
                 '(t "^records/" "tmp/")))
  (should (equal (fenrir/org-roam-sync--translate-excludes nil) '(t)))
  (should-not (car (fenrir/org-roam-sync--translate-excludes '("\\`records/" "\\_<x\\_>")))))

(ert-deftest orst-test-build-args ()
  "Verify CLI argument construction for `org-roam-sync'."
  (orst-with-vault (_tmp _vault db _idfile)
    (let ((org-roam-file-exclude-regexp '("\\`records/" "scratch/"))
          (org-roam-file-extensions '("org")))
      (let ((case-fold-search t))
        (should (equal (fenrir/org-roam-sync--build-args nil)
                       (list "--dir" (expand-file-name org-roam-directory)
                             "--db" (expand-file-name db)
                             "--exclude" "^records/"
                             "--exclude" "scratch/"
                             "--ext" "org"
                             "--ignore-case")))
        (should (equal (fenrir/org-roam-sync--build-args t)
                       (list "--dir" (expand-file-name org-roam-directory)
                             "--db" (expand-file-name db)
                             "--exclude" "^records/"
                             "--exclude" "scratch/"
                             "--ext" "org"
                             "--ignore-case"
                             "--force"))))
      (let ((case-fold-search nil))
        (should (equal (fenrir/org-roam-sync--build-args nil)
                       (list "--dir" (expand-file-name org-roam-directory)
                             "--db" (expand-file-name db)
                             "--exclude" "^records/"
                             "--exclude" "scratch/"
                             "--ext" "org")))))))

(ert-deftest orst-test-fallback-guards ()
  "Verify fallback to pure Elisp when binary missing or include fn customized."
  (orst-with-vault (_tmp vault db _idfile)
    (orst--write-file
     (expand-file-name "a.org" vault)
     ":PROPERTIES:\n:ID: fallback-id-1\n:END:\n#+title: Fallback Note\n")
    (let ((fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
      (should-not (fenrir/org-roam-sync--can-use-rust-p))
      (org-roam-db-sync t)
      (should (file-exists-p db))
      (let ((nodes (org-roam-node-list)))
        (should (= (length nodes) 1))
        (should (equal (org-roam-node-id (car nodes)) "fallback-id-1"))))
    (when (file-executable-p fenrir/org-roam-sync-program)
      (should (fenrir/org-roam-sync--can-use-rust-p))
      (let ((org-roam-db-node-include-function (lambda () nil)))
        (should-not (fenrir/org-roam-sync--can-use-rust-p))
        (org-roam-db-sync t)
        (should (= (length (org-roam-node-list)) 0))))))

(ert-deftest orst-test-encrypted-exit-code-2-and-fallback ()
  "Verify `org-roam-sync' returns exit 2 without touching DB on .org.gpg files."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (_tmp vault db _idfile)
    (orst--write-file (expand-file-name "secret.org.gpg" vault) "dummy-cipher")
    (let ((status (call-process fenrir/org-roam-sync-program nil nil nil
                                "--dir" org-roam-directory
                                "--db" db
                                "--exclude" "^records/")))
      (should (eql status 2))
      (should-not (file-exists-p db)))
    ;; If encrypted file is excluded by --exclude, Rust succeeds with exit 0.
    (orst--write-file (expand-file-name "records/secret.org.age" vault) "dummy")
    (delete-file (expand-file-name "secret.org.gpg" vault))
    (orst--write-file (expand-file-name "plain.org" vault)
                      ":PROPERTIES:\n:ID: plain-1\n:END:\n#+title: Plain\n")
    (org-roam-db-sync t)
    (should (= (length (org-roam-node-list)) 1))))

;;; Rust + Emacs integration & parity tests

(ert-deftest orst-test-cold-sync-queries-and-elisp-parity ()
  "Verify cold Rust sync matches pure-Elisp `org-roam-db-sync' row-for-row."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp-roam.db" tmp)))
      ;; Excluded top-level records/
      (orst--write-file
       (expand-file-name "records/ignored.org" vault)
       ":PROPERTIES:\n:ID: rec-ignored\n:END:\n#+title: Ignored Record\n")
      ;; Included nested */records/
      (orst--write-file
       (expand-file-name "sub/records/kept.org" vault)
       ":PROPERTIES:\n:ID: sub-kept\n:END:\n#+title: Nested Kept\n#+filetags: :kept:\n\n* Target Heading\n")
      ;; Dotdir included
      (orst--write-file
       (expand-file-name ".dotdir/dot.org" vault)
       ":PROPERTIES:\n:ID: dot-1\n:END:\n#+title: Dot Note\n")
      ;; Rich note: CJK, headings, TODO, [#A], SCHEDULED/DEADLINE, ROAM_EXCLUDE, aliases, refs, citations, links
      (orst--write-file
       (expand-file-name "rich.org" vault)
       (concat
        ":PROPERTIES:\n"
        ":ID: rich-file\n"
        ":ROAM_ALIASES: simple \"two words\"\n"
        ":ROAM_REFS: @citeRef \"https://example.com/a b\"\n"
        ":END:\n"
        "#+title: 筆記 [[id:sub-kept][Kept]]\n"
        "#+filetags: :ftag:ftag:\n\n"
        "See [cite:@citeKey] and [[file:sub/records/kept.org::*Target Heading]] and [[Fuzzy::opt]].\n\n"
        "* TODO [#A] Parent [1/2] [[id:dot-1][Dot]] :ptag:\n"
        "SCHEDULED: <2026-05-01 Fri 09:30> DEADLINE: <2026-05-10 Sun>\n"
        ":PROPERTIES:\n"
        ":ID: head-1\n"
        ":ROAM_EXCLUDE: nil\n"
        ":END:\n"
        "** Excluded Sub\n"
        ":PROPERTIES:\n"
        ":ID: head-excl\n"
        ":ROAM_EXCLUDE:\n"
        ":END:\n"
        "Link under excluded: [[id:sub-kept::*Target Heading]]\n"
        "*** Grandchild\n"
        ":PROPERTIES:\n"
        ":ID: head-grand\n"
        ":END:\n"))

      ;; 1. Run advised (Rust-backed) sync
      (org-roam-db-sync t)
      (let ((rust-nodes (sort (mapcar (lambda (n)
                                        (list (org-roam-node-id n)
                                              (org-roam-node-title n)
                                              (org-roam-node-level n)
                                              (org-roam-node-point n)
                                              (org-roam-node-todo n)
                                              (org-roam-node-priority n)
                                              (org-roam-node-olp n)
                                              (org-roam-node-tags n)
                                              (org-roam-node-aliases n)
                                              (org-roam-node-refs n)))
                                      (org-roam-node-list))
                              (lambda (a b) (string< (car a) (car b)))))
            (rust-tags (sort (copy-sequence (org-roam-tag-completions)) #'string<))
            (rust-backlinks (length (org-roam-backlinks-get (org-roam-node-from-id "sub-kept")))))
        (should (= (length rust-nodes) 7))
        (should (= (length (seq-uniq (mapcar #'car rust-nodes))) 5))
        (should (equal rust-tags '("ftag" "kept" "ptag")))
        ;; Links to sub-kept: #+title link + head-excl body link = 2 backlinks
        (should (= rust-backlinks 2))
        (let ((h1 (assoc "head-1" rust-nodes))
              (hg (assoc "head-grand" rust-nodes)))
          (should h1)
          (should (equal (nth 4 h1) "TODO"))
          (should (eql (nth 5 h1) ?A))
          (should (equal (nth 6 hg) '("Parent  Dot" "Excluded Sub"))))

        ;; 2. Run pure-Elisp sync to separate DB and assert identical query results + tables
        (org-roam-db--close-all)
        (let ((org-roam-db-location db-elisp)
              (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
          (org-roam-db-sync t)
          (let ((elisp-nodes (sort (mapcar (lambda (n)
                                             (list (org-roam-node-id n)
                                                   (org-roam-node-title n)
                                                   (org-roam-node-level n)
                                                   (org-roam-node-point n)
                                                   (org-roam-node-todo n)
                                                   (org-roam-node-priority n)
                                                   (org-roam-node-olp n)
                                                   (org-roam-node-tags n)
                                                   (org-roam-node-aliases n)
                                                   (org-roam-node-refs n)))
                                           (org-roam-node-list))
                                   (lambda (a b) (string< (car a) (car b)))))
                (elisp-tags (sort (copy-sequence (org-roam-tag-completions)) #'string<))
                (elisp-backlinks (length (org-roam-backlinks-get (org-roam-node-from-id "sub-kept")))))
            (should (equal rust-nodes elisp-nodes))
            (should (equal rust-tags elisp-tags))
            (should (= rust-backlinks elisp-backlinks))

            ;; Compare raw tables directly via sqlite-open
            (let ((c-rust (sqlite-open db-rust))
                  (c-elisp (sqlite-open db-elisp)))
              (unwind-protect
                  (dolist (tbl '("aliases" "citations" "refs" "tags" "links"))
                    (should (equal (sort (sqlite-select c-rust (format "SELECT * FROM %s" tbl))
                                         (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b))))
                                   (sort (sqlite-select c-elisp (format "SELECT * FROM %s" tbl))
                                         (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b)))))))
                (sqlite-close c-rust)
                (sqlite-close c-elisp)))))))))

(ert-deftest orst-test-incremental-modify-add-delete ()
  "Verify incremental sync updates modified files and cascade-deletes removed files."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (_tmp vault _db _idfile)
    (let ((fa (expand-file-name "a.org" vault))
          (fb (expand-file-name "b.org" vault))
          (fc (expand-file-name "c.org" vault)))
      (orst--write-file fa ":PROPERTIES:\n:ID: id-a\n:END:\n#+title: Note A\n#+filetags: :t1:\n[[id:id-b]]\n")
      (orst--write-file fb ":PROPERTIES:\n:ID: id-b\n:END:\n#+title: Note B\n")
      (org-roam-db-sync t)
      (should (= (length (org-roam-node-list)) 2))
      (should (= (length (org-roam-backlinks-get (org-roam-node-from-id "id-b"))) 1))

      ;; Modify a.org, delete b.org, add c.org
      (orst--write-file fa ":PROPERTIES:\n:ID: id-a\n:END:\n#+title: Note A2\n#+filetags: :t2:\n[[id:id-c]]\n")
      (delete-file fb)
      (orst--write-file fc ":PROPERTIES:\n:ID: id-c\n:END:\n#+title: Note C\n")
      (org-roam-db-sync)

      (should (= (length (org-roam-node-list)) 2))
      (should-not (org-roam-node-from-id "id-b"))
      (should (equal (org-roam-node-title (org-roam-node-from-id "id-a")) "Note A2"))
      (should (equal (sort (copy-sequence (org-roam-tag-completions)) #'string<) '("t2")))
      (should (= (length (org-roam-backlinks-get (org-roam-node-from-id "id-c"))) 1)))))

(ert-deftest orst-test-org-id-index-directory-preserves-external ()
  "Verify `fenrir/org-id-index-directory' preserves unrelated trees on disk & in memory."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault _db idfile)
    (let ((ext-file (expand-file-name "ext/kb.org" tmp)))
      (orst--write-file ext-file ":PROPERTIES:\n:ID: ext-id-1\n:END:\n#+title: Ext\n")
      (orst--write-file
       (expand-file-name "v1.org" vault)
       ":PROPERTIES:\n:ID: v-id-1\n:END:\n#+title: V1\n#+begin_src org\n:PROPERTIES:\n:ID: ignored-src\n:END:\n#+end_src\n* Excl\n:PROPERTIES:\n:ID: v-excl-id\n:ROAM_EXCLUDE: t\n:END:\n")
      ;; Seed external tree in id-locations.el while in-memory `org-id-locations' is nil.
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file idfile
          (print (list (list (abbreviate-file-name ext-file) "ext-id-1")
                       (list (abbreviate-file-name (expand-file-name "stale.org" vault)) "stale-id"))
                 (current-buffer))))

      (fenrir/org-id-index-directory vault)
      ;; External entry preserved; vault entries added; stale vault entry pruned; src block ID ignored.
      (should (equal (gethash "ext-id-1" org-id-locations) (abbreviate-file-name ext-file)))
      (should (equal (gethash "v-id-1" org-id-locations)
                     (abbreviate-file-name (file-truename (expand-file-name "v1.org" vault)))))
      (should (equal (gethash "v-excl-id" org-id-locations)
                     (abbreviate-file-name (file-truename (expand-file-name "v1.org" vault)))))
      (should-not (gethash "ignored-src" org-id-locations))
      (should-not (gethash "stale-id" org-id-locations))

      ;; Reload from disk in fresh state to confirm persistence
      (setq org-id-locations nil org-id-files nil)
      (org-id-locations-load)
      (should (equal (gethash "ext-id-1" org-id-locations) (abbreviate-file-name ext-file)))
      (should (gethash "v-id-1" org-id-locations))

      ;; Also test Elisp fallback preserves external entry when binary missing
      (setq org-id-locations nil org-id-files nil org-id--locations-checksum nil)
      (let ((fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (fenrir/org-id-index-directory vault)
        (should (equal (gethash "ext-id-1" org-id-locations) (abbreviate-file-name ext-file)))
        (should (gethash "v-id-1" org-id-locations))))))

(ert-deftest orst-test-cli-org-id-out-merge ()
  "Verify `--org-id-out' merges on disk without clobbering unrelated trees."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (_tmp vault _db idfile)
    (orst--write-file
     (expand-file-name "note.org" vault)
     ":PROPERTIES:\n:ID: cli-id-1\n:END:\n#+title: CLI\n")
    (with-temp-file idfile
      (print (list (list "~/code/camhr/kb/note.org" "camhr-1")
                   (list (abbreviate-file-name (expand-file-name "old.org" vault)) "old-1"))
             (current-buffer)))
    (let ((status (call-process fenrir/org-roam-sync-program nil nil nil
                                "--dir" vault
                                "--org-id-out" idfile)))
      (should (eql status 0)))
    (org-id-locations-load)
    (should (equal (gethash "camhr-1" org-id-locations) "~/code/camhr/kb/note.org"))
    (should (gethash "cli-id-1" org-id-locations))
    (should-not (gethash "old-1" org-id-locations))))

(defun orst--strip-props (obj)
  "Recursively strip Emacs text properties from strings inside OBJ."
  (cond
   ((stringp obj) (substring-no-properties obj))
   ((consp obj) (cons (orst--strip-props (car obj))
                      (orst--strip-props (cdr obj))))
   ((vectorp obj) (cl-map 'vector #'orst--strip-props obj))
   (t obj)))

(defun orst--read-cell (val)
  "Read an EmacSQL-encoded SQLite cell VAL and strip text properties."
  (cond
   ((null val) nil)
   ((numberp val) val)
   ((stringp val) (orst--strip-props (car (read-from-string val))))
   (t val)))

(defun orst--assert-db-parity (db-rust db-elisp)
  "Assert full 7-table parity between DB-RUST and DB-ELISP (excluding ephemeral atime/mtime)."
  (let ((c-rust (sqlite-open db-rust))
        (c-elisp (sqlite-open db-elisp)))
    (unwind-protect
        (progn
          (should (equal (sqlite-select c-rust "PRAGMA user_version") '((20))))
          (should (equal (sqlite-select c-elisp "PRAGMA user_version") '((20))))
          (should (equal (sqlite-select c-rust "SELECT file, title, hash FROM files ORDER BY file")
                         (sqlite-select c-elisp "SELECT file, title, hash FROM files ORDER BY file")))
          (let ((r-nodes (mapcar (lambda (row)
                                   (list (nth 0 row) (nth 1 row) (nth 2 row) (nth 3 row)
                                         (nth 4 row) (nth 5 row) (nth 6 row) (nth 7 row)
                                         (nth 8 row)
                                         (orst--read-cell (nth 9 row))
                                         (nth 10 row)))
                                 (sqlite-select c-rust "SELECT id, file, level, pos, todo, priority, scheduled, deadline, title, properties, olp FROM nodes ORDER BY id, file, pos")))
                (e-nodes (mapcar (lambda (row)
                                   (list (nth 0 row) (nth 1 row) (nth 2 row) (nth 3 row)
                                         (nth 4 row) (nth 5 row) (nth 6 row) (nth 7 row)
                                         (nth 8 row)
                                         (orst--read-cell (nth 9 row))
                                         (nth 10 row)))
                                 (sqlite-select c-elisp "SELECT id, file, level, pos, todo, priority, scheduled, deadline, title, properties, olp FROM nodes ORDER BY id, file, pos"))))
            (should (equal r-nodes e-nodes)))
          (dolist (tbl '("aliases" "citations" "refs" "tags" "links"))
            (should (equal (sort (sqlite-select c-rust (format "SELECT * FROM %s" tbl))
                                 (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b))))
                           (sort (sqlite-select c-elisp (format "SELECT * FROM %s" tbl))
                                 (lambda (a b) (string< (prin1-to-string a) (prin1-to-string b))))))))
      (sqlite-close c-rust)
      (sqlite-close c-elisp))))

(ert-deftest orst-test-exclude-regexp-end-to-end-parity ()
  "Verify `org-roam-file-exclude-regexp' parity for parens, pipes, POSIX classes, and backslashes."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      (orst--write-file (expand-file-name "dir(1)/excl.org" vault)
                        ":PROPERTIES:\n:ID: id-excl-paren\n:END:\n#+title: Excl Paren\n")
      (orst--write-file (expand-file-name "dir1/keep.org" vault)
                        ":PROPERTIES:\n:ID: id-keep-dir1\n:END:\n#+title: Keep Dir1\n")
      (orst--write-file (expand-file-name "a|b/excl.org" vault)
                        ":PROPERTIES:\n:ID: id-excl-pipe\n:END:\n#+title: Excl Pipe\n")
      (orst--write-file (expand-file-name "sub/keep.org" vault)
                        ":PROPERTIES:\n:ID: id-keep-sub\n:END:\n#+title: Keep Sub\n")
      (orst--write-file (expand-file-name "9.org" vault)
                        ":PROPERTIES:\n:ID: id-excl-digit\n:END:\n#+title: Excl Digit\n")
      (orst--write-file (expand-file-name "^.org" vault)
                        ":PROPERTIES:\n:ID: id-keep-caret\n:END:\n#+title: Keep Caret\n")
      (orst--write-file (expand-file-name ".org" vault)
                        ":PROPERTIES:\n:ID: id-dotfile\n:END:\n#+title: Dotfile\n")
      (orst--write-file (expand-file-name "x(y.org" vault)
                        ":PROPERTIES:\n:ID: id-paren-file\n:END:\n#+title: Paren File\n")

      (let ((org-roam-file-exclude-regexp '("dir(1)/" "a|b/")))
        (org-roam-db-sync t)
        (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
          (should (equal rust-ids '("id-excl-digit" "id-keep-caret" "id-keep-dir1" "id-keep-sub" "id-paren-file")))
          (org-roam-db--close-all)
          (let ((org-roam-db-location db-elisp)
                (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
            (org-roam-db-sync t)
            (let ((elisp-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
              (should (equal rust-ids elisp-ids)))
            (org-roam-db--close-all)
            (orst--assert-db-parity db-rust db-elisp))))

      ;; Also verify POSIX class + literal backslash inside `[...]` matches Elisp
      (let ((org-roam-file-exclude-regexp '("[[:digit:]\\`a]")))
        (org-roam-db-sync t)
        (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
          (should (member "id-keep-caret" rust-ids))
          (should-not (member "id-excl-digit" rust-ids))
          (org-roam-db--close-all)
          (let ((org-roam-db-location db-elisp)
                (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
            (org-roam-db-sync t)
            (should (equal rust-ids
                           (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
            (org-roam-db--close-all)
            (orst--assert-db-parity db-rust db-elisp))))

      ;; Also verify literal `\\(` exclude pattern matches Elisp without error
      (let ((org-roam-file-exclude-regexp '("\\\\(")))
        (org-roam-db-sync t)
        (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
          (should (member "id-keep-sub" rust-ids))
          (org-roam-db--close-all)
          (let ((org-roam-db-location db-elisp)
                (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
            (org-roam-db-sync t)
            (should (equal rust-ids
                           (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))))))))

(ert-deftest orst-test-iter3-category-citations-and-exclude-regressions ()
  "Verify file-level :CATEGORY: inheritance, nested citation brackets, and mid-^/$/class exclude regexps."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      ;; File-level :CATEGORY: without #+CATEGORY:
      (orst--write-file
       (expand-file-name "cat-drawer.org" vault)
       ":PROPERTIES:\n:ID: f-cat-drawer\n:CATEGORY: FileDrawerCat\n:END:\n#+title: Cat Drawer\n\n* Heading 1\n:PROPERTIES:\n:ID: h-cat-drawer\n:END:\n")
      ;; File-level :CATEGORY: overriding #+CATEGORY: + nested bracketed citations
      (orst--write-file
       (expand-file-name "cat-both.org" vault)
       ":PROPERTIES:\n:ID: f-cat-both\n:CATEGORY: DrawerCat\n:END:\n#+CATEGORY: KwCat\n#+title: Cat Both\n\n* Heading Both\n:PROPERTIES:\n:ID: h-cat-both\n:END:\nMulti [cite:@m4 p. [10]; @m5] and [cite:@a [b [c]]; @d].\n")

      ;; 1. Verify file-level :CATEGORY: inheritance and nested citations parity
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all))
      (orst--assert-db-parity db-rust db-elisp)

      ;; 2. Verify exclude regexps '("foo^bar" "baz$qux" "[a&&b]" "[a--b]" "[[]") with zero status-1 warnings
      (orst--write-file (expand-file-name "foo^bar.org" vault)
                        ":PROPERTIES:\n:ID: id-caret\n:END:\n#+title: Caret\n")
      (orst--write-file (expand-file-name "baz$qux.org" vault)
                        ":PROPERTIES:\n:ID: id-dollar\n:END:\n#+title: Dollar\n")
      (orst--write-file (expand-file-name "&.org" vault)
                        ":PROPERTIES:\n:ID: id-amp\n:END:\n#+title: Amp\n")
      (orst--write-file (expand-file-name "-.org" vault)
                        ":PROPERTIES:\n:ID: id-dash\n:END:\n#+title: Dash\n")
      (orst--write-file (expand-file-name "b.org" vault)
                        ":PROPERTIES:\n:ID: id-b\n:END:\n#+title: B\n")
      (orst--write-file (expand-file-name "[.org" vault)
                        ":PROPERTIES:\n:ID: id-lbrack\n:END:\n#+title: Lbrack\n")
      (orst--write-file (expand-file-name "keep.org" vault)
                        ":PROPERTIES:\n:ID: id-keep\n:END:\n#+title: Keep\n")

      (let ((org-roam-file-exclude-regexp '("foo^bar" "baz$qux" "[a&&b]" "[a--b]" "[[]"))
            (warning-buf (get-buffer-create " *orst-warnings*")))
        (unwind-protect
            (progn
              (with-current-buffer warning-buf (erase-buffer))
              (cl-letf (((symbol-function 'display-warning)
                         (lambda (type message &optional _level _buffer-name)
                           (with-current-buffer warning-buf
                             (insert (format "%S: %s\n" type message))))))
                (org-roam-db-sync t))
              ;; Zero status-1 fallback warnings
              (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
              ;; Note: [a&&b] also matches 'a' in cat-drawer.org / cat-both.org, leaving -.org and keep.org.
              (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                (should (equal rust-ids '("id-dash" "id-keep"))))
              ;; Verify Elisp parity across all 7 tables
              (org-roam-db--close-all)
              (let ((org-roam-db-location db-elisp)
                    (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                (org-roam-db-sync t)
                (org-roam-db--close-all))
              (orst--assert-db-parity db-rust db-elisp)

              ;; 3. Also verify [a--b] alone matches only 'b', keeping 'a' (cat-drawer) and '-'
              (let ((org-roam-file-exclude-regexp '("[a--b]")))
                (org-roam-db-sync t)
                (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                  (should (member "f-cat-drawer" rust-ids))
                  (should (member "id-dash" rust-ids))
                  (should-not (member "id-b" rust-ids)))
                (org-roam-db--close-all)
                (let ((org-roam-db-location db-elisp)
                      (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                  (org-roam-db-sync t)
                  (org-roam-db--close-all))
                (orst--assert-db-parity db-rust db-elisp)))
          (kill-buffer warning-buf))))))

(ert-deftest orst-test-incremental-id-move-z-to-a ()
  "Verify incremental ID move from `z-old.org' to `a-new.org' preserves moved node and tags."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((fa (expand-file-name "a-new.org" vault))
          (fz (expand-file-name "z-old.org" vault))
          (db-elisp (expand-file-name "elisp.db" tmp)))
      (orst--write-file fa ":PROPERTIES:\n:ID: other-id\n:END:\n#+title: A\n")
      (orst--write-file fz ":PROPERTIES:\n:ID: moved-id\n:END:\n#+title: Z\n")
      (org-roam-db-sync t)
      (should (equal (file-name-nondirectory (org-roam-node-file (org-roam-node-from-id "moved-id")))
                     "z-old.org"))

      ;; Move `moved-id' from z-old.org -> a-new.org in a single incremental sync
      (orst--write-file fa ":PROPERTIES:\n:ID: moved-id\n:END:\n#+title: A Moved\n#+filetags: :new:\n")
      (orst--write-file fz ":PROPERTIES:\n:ID: z-new-id\n:END:\n#+title: Z New\n")
      (org-roam-db-sync)
      (let ((moved (org-roam-node-from-id "moved-id")))
        (should moved)
        (should (equal (file-name-nondirectory (org-roam-node-file moved)) "a-new.org"))
        (should (equal (org-roam-node-tags moved) '("new"))))
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all)
        (orst--assert-db-parity db-rust db-elisp)))))

(ert-deftest orst-test-adversarial-parser-and-properties-parity ()
  "Verify parity for custom TODO, BLOCKED, tabs, CATEGORY, timestamps, PRIORITY, ALLTAGS, citations, \\f, and refs."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      (orst--write-file
       (expand-file-name "adv.org" vault)
       (concat
        ":PROPERTIES:\n"
        ":ID: adv-file\n"
        ":ROAM_REFS: [cite:@k2;@k3] [cite/t:@k4]\n"
        ":END:\n"
        "#+title: Adv \fTitle\n"
        "#+TODO: TODO NEXT | DONE CANCELLED\n"
        "#+filetags: :ft1:ft2:ft1:\n"
        "#+filetags: :ft3:\n\n"
        "*\tTabAfterStar\n"
        ":PROPERTIES:\n:ID: bogus-tab\n:END:\n\n"
        "* NEXT Parent :p_tag:\n"
        ":PROPERTIES:\n:ID: h-next\n:A_PROP: a\n:CATEGORY: ParentCat\n:Z_PROP: z\n:END:\n"
        "[2026-05-01 Fri]\n<2026-05-02 Sat>\n"
        "** CANCELLED Child :c@1:ft2:\n"
        ":PROPERTIES:\n:ID: h-canc\n:END:\n"
        "* DONE DoneParent\n"
        ":PROPERTIES:\n:ID: h-done\n:END:\n"
        "** TODO OpenChild\n"
        ":PROPERTIES:\n:ID: h-open\n:END:\n"
        "*** Skipped lvl 3 TODO [#A] HasChildDone\n"
        ":PROPERTIES:\n:ID: h-prio\n:END:\n"
        "* TODO\t[#A]\tTabbed heading\t:tabtag:\n"
        ":PROPERTIES:\n:ID: h-tab\n:END:\n"
        "中文🚀 [cite:@k1; @k2] and [cite/t:pre @k3 post].\n"))
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all))
      (orst--assert-db-parity db-rust db-elisp))))

(ert-deftest orst-test-org-id-malformed-stdout-fallback ()
  "Verify `fenrir/org-id-index-directory' falls back to Elisp on empty/malformed stdout with status 0."
  (orst-with-vault (tmp vault _db idfile)
    (let ((note (expand-file-name "note.org" vault))
          (mock-bin (expand-file-name "mock-bad-sync.sh" tmp)))
      (orst--write-file note ":PROPERTIES:\n:ID: fallback-org-id-1\n:END:\n#+title: Note\n")
      ;; Mock binary exits 0 with empty stdout
      (orst--write-file mock-bin "#!/bin/sh\nexit 0\n")
      (set-file-modes mock-bin #o755)
      (let ((fenrir/org-roam-sync-program mock-bin))
        (fenrir/org-id-index-directory vault)
        (should (gethash "fallback-org-id-1" org-id-locations)))
      ;; Mock binary exits 0 with malformed Lisp stdout
      (setq org-id-locations nil org-id-files nil org-id--locations-checksum nil)
      (orst--write-file mock-bin "#!/bin/sh\nprintf '(\"unterminated'\nexit 0\n")
      (let ((fenrir/org-roam-sync-program mock-bin))
        (fenrir/org-id-index-directory vault)
        (should (gethash "fallback-org-id-1" org-id-locations))))))

(ert-deftest orst-test-iter4-parity-regressions ()
  "Verify parity for :CATEGORY+: inheritance, citation/link edge cases, POSIX-dash fallback, escapes, and case-fold-search."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      ;; 1. :CATEGORY+: without #+CATEGORY:, with #+CATEGORY:, heading :CATEGORY+:, and reverse order
      (orst--write-file
       (expand-file-name "catplus-nokw.org" vault)
       ":PROPERTIES:\n:ID: f-cp-nk\n:CATEGORY+: FilePlus\n:END:\n#+title: CatPlus NoKw\n\n* H1\n:PROPERTIES:\n:ID: h-cp-nk\n:END:\n")
      (orst--write-file
       (expand-file-name "catplus-kw.org" vault)
       ":PROPERTIES:\n:ID: f-cp-kw\n:CATEGORY+: FilePlus\n:END:\n#+CATEGORY: KwCat\n#+title: CatPlus Kw\n\n* H1\n:PROPERTIES:\n:ID: h-cp-kw1\n:CATEGORY+: HeadPlus\n:END:\n** H2\n:PROPERTIES:\n:ID: h-cp-kw2\n:END:\n")
      (orst--write-file
       (expand-file-name "catplus-rev.org" vault)
       ":PROPERTIES:\n:ID: f-cp-rev\n:CATEGORY+: Plus\n:CATEGORY: Base\n:END:\n#+CATEGORY: KwCat\n\n* H1\n:PROPERTIES:\n:ID: h-cp-rev\n:END:\n")

      ;; 2. Citations & links inside citations
      (orst--write-file
       (expand-file-name "cites.org" vault)
       (concat
        ":PROPERTIES:\n:ID: f-c\n:END:\n#+title: Cites\n\n"
        "* H\n:PROPERTIES:\n:ID: h-c\n:END:\n"
        "[cite:@semi [10;20]; @aftersemi].\n"
        "[cite:@link [[id:f-c][desc]]; @afterlink].\n"
        "[cite:@br [[id:f-c][]]] and [[id:f-cp-kw][keep]].\n"
        "[[id:f-c][[cite:@inner]]].\n"
        "C [cite:@bad [10; @next].\nD [cite:@e \\] p. 1; @f].\n"
        "Nested [cite:@a [cite:@b] ; @c].\n"
        "Unclosed [cite:@unclosed [loc\n\nNext para ] and [cite:@good].\n"))

      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all))
      (orst--assert-db-parity db-rust db-elisp)

      ;; 3. Exclude regexps: \d, \n, \A, \z, case-fold-search, and POSIX+dash fallback
      (orst--write-file (expand-file-name "0.org" vault) ":PROPERTIES:\n:ID: id-0\n:END:\n")
      (orst--write-file (expand-file-name "d.org" vault) ":PROPERTIES:\n:ID: id-d\n:END:\n")
      (orst--write-file (expand-file-name "n.org" vault) ":PROPERTIES:\n:ID: id-n\n:END:\n")
      (orst--write-file (expand-file-name "A.org" vault) ":PROPERTIES:\n:ID: id-A\n:END:\n")
      (orst--write-file (expand-file-name "z.org" vault) ":PROPERTIES:\n:ID: id-z\n:END:\n")
      (orst--write-file (expand-file-name "foo.org" vault) ":PROPERTIES:\n:ID: id-foo\n:END:\n")
      (orst--write-file (expand-file-name "keep.org" vault) ":PROPERTIES:\n:ID: id-keep\n:END:\n")

      (let ((warning-buf (get-buffer-create " *orst-iter4-warn*")))
        (unwind-protect
            (cl-letf (((symbol-function 'display-warning)
                       (lambda (type message &optional _level _buffer-name)
                         (with-current-buffer warning-buf
                           (insert (format "%S: %s\n" type message))))))
              ;; 3a. Backslash escapes (\d, \n, \A, \z) with case-fold-search = t (no warnings)
              (with-current-buffer warning-buf (erase-buffer))
              (let ((org-roam-file-exclude-regexp '("\\d" "\\n" "\\A" "\\z"))
                    (case-fold-search t))
                (org-roam-db-sync t)
                (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
                (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                  (should (member "id-0" rust-ids))
                  (should-not (member "id-d" rust-ids))
                  (should-not (member "id-n" rust-ids))
                  (should-not (member "id-A" rust-ids))
                  (should-not (member "id-z" rust-ids)))
                (org-roam-db--close-all)
                (let ((org-roam-db-location db-elisp)
                      (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                  (org-roam-db-sync t)
                  (org-roam-db--close-all))
                (orst--assert-db-parity db-rust db-elisp))

              ;; 3b. case-fold-search = t vs nil on '("FOO")
              (dolist (cfs '(t nil))
                (with-current-buffer warning-buf (erase-buffer))
                (let ((org-roam-file-exclude-regexp '("FOO"))
                      (case-fold-search cfs))
                  (org-roam-db-sync t)
                  (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
                  (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                    (if cfs
                        (should-not (member "id-foo" rust-ids))
                      (should (member "id-foo" rust-ids))))
                  (org-roam-db--close-all)
                  (let ((org-roam-db-location db-elisp)
                        (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                    (org-roam-db-sync t)
                    (org-roam-db--close-all))
                  (orst--assert-db-parity db-rust db-elisp)))

              ;; 3c. POSIX + dash '[[:alpha:]--[:digit:]]' falls back cleanly to Elisp (0 warnings, 0 diffs)
              (with-current-buffer warning-buf (erase-buffer))
              (let ((org-roam-file-exclude-regexp '("[[:alpha:]--[:digit:]]")))
                (should-not (fenrir/org-roam-sync--can-use-rust-p))
                (org-roam-db-sync t)
                (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
                (org-roam-db--close-all)
                (let ((org-roam-db-location db-elisp)
                      (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                  (org-roam-db-sync t)
                  (org-roam-db--close-all))
                (orst--assert-db-parity db-rust db-elisp)))
          (kill-buffer warning-buf))))))

(ert-deftest orst-test-iter5-parity-regressions ()
  "Verify parity for `[[:word:]]` exclude fallback, empty `#+CATEGORY:`, and `:ROAM_REFS:` `[cite:...]`."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      ;; 1. Empty #+CATEGORY: alone, with file :CATEGORY+:, and with heading :CATEGORY+:
      (orst--write-file
       (expand-file-name "empty-kw.org" vault)
       ":PROPERTIES:\n:ID: f-ek\n:END:\n#+CATEGORY:\n#+title: Empty Kw\n\n* H1\n:PROPERTIES:\n:ID: h-ek\n:END:\n")
      (orst--write-file
       (expand-file-name "empty-kw-fileplus.org" vault)
       ":PROPERTIES:\n:ID: f-ekfp\n:CATEGORY+: Plus\n:END:\n#+CATEGORY:\n#+title: Empty Kw FilePlus\n\n* H1\n:PROPERTIES:\n:ID: h-ekfp\n:END:\n")
      (orst--write-file
       (expand-file-name "empty-kw-subplus.org" vault)
       ":PROPERTIES:\n:ID: f-eksp\n:END:\n#+CATEGORY:\n#+title: Empty Kw SubPlus\n\n* H1\n:PROPERTIES:\n:ID: h-eksp1\n:CATEGORY+: Plus\n:END:\n** H2\n:PROPERTIES:\n:ID: h-eksp2\n:END:\n")

      ;; 2. :ROAM_REFS: [cite:...] unclosed, space-split, nested, and multi-object tokens
      (orst--write-file
       (expand-file-name "refs-cite.org" vault)
       (concat
        ":PROPERTIES:\n"
        ":ID: r-unq\n"
        ":ROAM_REFS: [cite:@r1; @r2] [cite:@unclosed \"https://example.com/a?x=1&y=2\"\n"
        ":END:\n"
        "#+title: Refs Cite\n\n"
        "* Quoted Refs\n"
        ":PROPERTIES:\n"
        ":ID: r-quo\n"
        ":ROAM_REFS: \"[cite:@a [10; @b]; @c]\" \"[cite:@x [cite:@nest]; @d]\" \"[cite:@a [10;20]; @b]\" \"[cite:@u [cite:@inner]\" \"[cite:@k1] [[id:f-ek][[cite:@k2]]]\" \"[cite:@p] [cite/t:@q]\"\n"
        ":END:\n"))

      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all))
      (orst--assert-db-parity db-rust db-elisp)

      ;; 3. [[:word:]] exclude fallback parity on _.org vs a.org
      (orst--write-file (expand-file-name "_.org" vault) ":PROPERTIES:\n:ID: id-under\n:END:\n#+title: Under\n")
      (orst--write-file (expand-file-name "a.org" vault) ":PROPERTIES:\n:ID: id-a\n:END:\n#+title: A\n")
      (orst--write-file (expand-file-name "0.org" vault) ":PROPERTIES:\n:ID: id-0\n:END:\n#+title: Zero\n")
      (orst--write-file (expand-file-name "-.org" vault) ":PROPERTIES:\n:ID: id-dash\n:END:\n#+title: Dash\n")

      ;; CLI --exclude-elisp rejects [[:word:]] with non-zero status
      (should-not (eql 0 (call-process fenrir/org-roam-sync-program nil nil nil
                                       "--dir" org-roam-directory
                                       "--db" (expand-file-name "cli-word.db" tmp)
                                       "--exclude-elisp" "\\`[[:word:]]\\.")))

      (let ((warning-buf (get-buffer-create " *orst-iter5-warn*"))
            (org-roam-file-exclude-regexp '("\\`[[:word:]]\\.")))
        (unwind-protect
            (cl-letf (((symbol-function 'display-warning)
                       (lambda (type message &optional _level _buffer-name)
                         (with-current-buffer warning-buf
                           (insert (format "%S: %s\n" type message))))))
              (with-current-buffer warning-buf (erase-buffer))
              (should-not (fenrir/org-roam-sync--can-use-rust-p))
              (org-roam-db-sync t)
              (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
              (let ((ids (mapcar #'org-roam-node-id (org-roam-node-list))))
                (should (member "id-under" ids))
                (should (member "id-dash" ids))
                (should-not (member "id-a" ids))
                (should-not (member "id-0" ids)))
              (org-roam-db--close-all)
              (let ((org-roam-db-location db-elisp)
                    (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                (org-roam-db-sync t)
                (org-roam-db--close-all))
              (orst--assert-db-parity db-rust db-elisp))
          (kill-buffer warning-buf))))))

(ert-deftest orst-test-iter6-parity-regressions ()
  "Verify parity for `CATEGORY` `\"nil\"` -> `\"???\"` and bridge-link `bracket_link_ranges`."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      ;; 1. CATEGORY "nil" -> "???" (keyword, file stem, inherited drawer) vs own drawer "nil" vs "NIL"
      (orst--write-file
       (expand-file-name "nil.org" vault)
       ":PROPERTIES:\n:ID: f-filenil\n:END:\n* H1\n:PROPERTIES:\n:ID: h-filenil\n:END:\n")
      (orst--write-file
       (expand-file-name "kw-nil.org" vault)
       ":PROPERTIES:\n:ID: f-kwnil\n:END:\n#+CATEGORY: nil\n* H1\n:PROPERTIES:\n:ID: h-kwnil\n:END:\n")
      (orst--write-file
       (expand-file-name "drawer-nil.org" vault)
       ":PROPERTIES:\n:ID: f-dnil\n:CATEGORY: nil\n:END:\n* H1\n:PROPERTIES:\n:ID: h-dnil\n:END:\n")
      (orst--write-file
       (expand-file-name "kw-nil-plus.org" vault)
       ":PROPERTIES:\n:ID: f-kwnp\n:CATEGORY+: Plus\n:END:\n#+CATEGORY: nil\n* H1\n:PROPERTIES:\n:ID: h-kwnp\n:END:\n")
      (orst--write-file
       (expand-file-name "kw-upper-nil.org" vault)
       ":PROPERTIES:\n:ID: f-kwNIL\n:END:\n#+CATEGORY: NIL\n* H1\n:PROPERTIES:\n:ID: h-kwNIL\n:END:\n")

      ;; 2. Empty-desc bridge links + nested citations in :ROAM_REFS: and body text
      (orst--write-file
       (expand-file-name "bridge-cite.org" vault)
       (concat
        ":PROPERTIES:\n"
        ":ID: bc-1\n"
        ":ROAM_REFS: \"[cite:@k1] [[id:f-kwnil][]] [[id:h-kwnil][[cite:@k2]]]\" \"[cite:@k3] [[id:f-dnil][]] [[id:h-dnil][]] [[id:f-kwnp][[cite:@k4]]]\" \"[cite:@k5] [[id:f-kwnil][]] [[id:h-kwnil][]] [[id:f-dnil][]] [[id:h-dnil][[cite:@k6]]]\"\n"
        ":END:\n"
        "#+title: Bridge Cite\n\n"
        "Body1 [cite:@b1] [[id:f-kwnil][]] [[id:h-kwnil][[cite:@b2]]].\n"
        "Body2 [[id:f-dnil][]] [[id:h-dnil][]] [[id:f-kwnp][[cite:@b3]]].\n"
        "Body3 [[id:f-kwnil][]] [[id:h-kwnil][]] [[id:f-dnil][]] [[id:h-dnil][[cite:@b4]]].\n"
        "Body4 [cite:@br [[id:f-kwnil][]]] and [cite:@other] and [[id:h-kwnil][[cite:@inner]]].\n"
        "Body5 =[[id:f-kwnil][]]= [[id:h-kwnil][[cite:@b5]]].\n"
        "Body6 [[id:f-kwnil][]]\n\n[[id:h-kwnil][[cite:@b6]]].\n"))

      (should (fenrir/org-roam-sync--can-use-rust-p))
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all))
      (orst--assert-db-parity db-rust db-elisp))))

(ert-deftest orst-test-tier5-empty-heading-crlf-symlink-and-regex-parity ()
  "Tier 5 (R2): Adversarial parity for empty-title headings with links, CRLF files, broken symlinks, and leading-quantifier regexps."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      ;; 1. Empty-title headings with :ID: and links/citations
      (orst--write-file
       (expand-file-name "empty-h.org" vault)
       (concat
        ":PROPERTIES:\n:ID: file-ok\n:END:\n#+title: File OK\n\n"
        "* Parent\n:PROPERTIES:\n:ID: parent-ok\n:END:\n"
        "** \n:PROPERTIES:\n:ID: empty-sub\n:END:\n[[id:file-ok][link]] [cite:@c1].\n"
        "* TODO\n:PROPERTIES:\n:ID: todo-only\n:END:\n[[id:file-ok][l1]]\n"
        "* :onlytag:\n:PROPERTIES:\n:ID: tag-only\n:END:\n[[id:file-ok][l2]]\n"))
      ;; 2. CRLF file
      (let ((coding-system-for-write 'utf-8-dos)
            (file-name-handler-alist nil))
        (make-directory vault t)
        (write-region
         (concat ":PROPERTIES:\n:ID: crlf-f\n:END:\n#+title: CRLF\n\n"
                 "* TODO Heading One :tag1:\n:PROPERTIES:\n:ID: crlf-h1\n:END:\n"
                 "Line [[id:crlf-f][back]].\n")
         nil (expand-file-name "crlf.org" vault) nil 'silent))
      ;; 3. Broken symlink + 0-byte file
      (make-symbolic-link "/nonexistent/target.org" (expand-file-name "broken.org" vault))
      (orst--write-file (expand-file-name "zero.org" vault) "")

      (should (fenrir/org-roam-sync--can-use-rust-p))
      (org-roam-db-sync t)
      (org-roam-db--close-all)
      (let ((org-roam-db-location db-elisp)
            (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
        (org-roam-db-sync t)
        (org-roam-db--close-all))
      (orst--assert-db-parity db-rust db-elisp))

    ;; 4. Leading quantifiers and upper-bound brace in org-roam-file-exclude-regexp
    (orst-with-vault (tmp2 vault2 db-rust2 _idfile2)
      (let ((db-elisp2 (expand-file-name "elisp2.db" tmp2)))
        (dolist (name '("normal.org" "*star.org" "?q.org" "b.org" "aaab.org" "aaaab.org"))
          (orst--write-file
           (expand-file-name name vault2)
           (format ":PROPERTIES:\n:ID: id-%s\n:END:\n#+title: %s\n" name name)))
        (dolist (rx '("^*" "^?" "\\`*" "\\(*star\\)" "^a\\{,3\\}b"))
          (let ((org-roam-file-exclude-regexp (list rx)))
            (org-roam-db-sync t)
            (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
              (org-roam-db--close-all)
              (let ((org-roam-db-location db-elisp2)
                    (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                (org-roam-db-sync t)
                (let ((elisp-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                  (should (equal rust-ids elisp-ids)))
                (org-roam-db--close-all))
              (orst--assert-db-parity db-rust2 db-elisp2))))))))

(ert-deftest orst-test-tier5-fallback-guards-corrupt-db-and-org-id-empty ()
  "Tier 5 (R2): Verify custom-var fallback guards, --force over corrupt DB, and org-id on ID-less vs empty dir."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  (orst-with-vault (_tmp vault db idfile)
    ;; Fallback guards
    (let ((org-enforce-todo-dependencies t))
      (should-not (fenrir/org-roam-sync--can-use-rust-p)))
    (let ((org-blocker-hook (list #'ignore)))
      (should-not (fenrir/org-roam-sync--can-use-rust-p)))
    (let ((org-todo-keywords '((sequence "TODO" "WAIT" "|" "DONE"))))
      (should-not (fenrir/org-roam-sync--can-use-rust-p)))
    (let ((org-roam-db-extra-links-elements '(keyword)))
      (should-not (fenrir/org-roam-sync--can-use-rust-p)))
    (dlet ((org-ref-cite-types '("cite")))
      (should-not (fenrir/org-roam-sync--can-use-rust-p)))

    ;; Corrupt DB fails without --force and recovers with --force
    (orst--write-file (expand-file-name "plain.org" vault) "No ID here.\n")
    (orst--write-file db "not-a-sqlite-database")
    (should-not (eql 0 (call-process fenrir/org-roam-sync-program nil nil nil
                                     "--dir" org-roam-directory "--db" db)))
    (org-roam-db-sync t)
    (let ((c (sqlite-open db)))
      (unwind-protect
          (should (equal (sqlite-select c "PRAGMA user_version") '((20))))
        (sqlite-close c)))

    ;; org-id-index-directory on .org files with zero :ID:s prunes stale under-dir entries without error
    (with-temp-file idfile
      (print (list (list (abbreviate-file-name (expand-file-name "stale.org" vault)) "stale-1")
                   (list "~/external/keep.org" "ext-1"))
             (current-buffer)))
    (fenrir/org-id-index-directory vault)
    (should-not (gethash "stale-1" org-id-locations))
    (should (equal (gethash "ext-1" org-id-locations) "~/external/keep.org"))

    ;; Directory with zero .org files signals user-error
    (delete-file (expand-file-name "plain.org" vault))
    (should-error (fenrir/org-id-index-directory vault) :type 'user-error)))

(ert-deftest orst-test-tier5-file-symlink-loops-and-brace-quantifier-parity ()
  "Tier 5 (R2): File-level symlink loops (ELOOP) and non-leading `\\{\\}` / `\\{m,n\\}?` parity."
  (skip-unless (file-executable-p fenrir/org-roam-sync-program))
  ;; 1. File-level symlink loops (`selfloop.org`, `cyc_a.org <-> cyc_b.org`, `dir_loop`)
  (orst-with-vault (tmp vault db-rust _idfile)
    (let ((db-elisp (expand-file-name "elisp.db" tmp)))
      (orst--write-file
       (expand-file-name "ok.org" vault)
       ":PROPERTIES:\n:ID: ok-loop\n:END:\n#+title: OK Loop\n")
      (make-symbolic-link (expand-file-name "selfloop.org" vault)
                          (expand-file-name "selfloop.org" vault))
      (make-symbolic-link (expand-file-name "cyc_b.org" vault)
                          (expand-file-name "cyc_a.org" vault))
      (make-symbolic-link (expand-file-name "cyc_a.org" vault)
                          (expand-file-name "cyc_b.org" vault))
      (make-symbolic-link "." (expand-file-name "dir_loop" vault))

      (let ((warning-buf (get-buffer-create " *orst-eloop-warn*")))
        (unwind-protect
            (cl-letf (((symbol-function 'display-warning)
                       (lambda (type message &optional _level _buffer-name)
                         (with-current-buffer warning-buf
                           (insert (format "%S: %s\n" type message))))))
              (with-current-buffer warning-buf (erase-buffer))
              (should (fenrir/org-roam-sync--can-use-rust-p))
              (org-roam-db-sync t)
              (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
              (should (equal (mapcar #'org-roam-node-id (org-roam-node-list)) '("ok-loop")))
              (org-roam-db--close-all)
              (let ((org-roam-db-location db-elisp)
                    (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                (org-roam-db-sync t)
                (org-roam-db--close-all))
              (orst--assert-db-parity db-rust db-elisp))
          (kill-buffer warning-buf)))

      ;; Also verify `fenrir/org-id-index-directory' and `--emit-org-ids' succeed via Rust
      (fenrir/org-id-index-directory vault)
      (should (eql (hash-table-count org-id-locations) 1))
      (should (equal (file-truename (gethash "ok-loop" org-id-locations))
                     (file-truename (expand-file-name "ok.org" vault))))
      (with-temp-buffer
        (should (eql 0 (call-process fenrir/org-roam-sync-program nil (current-buffer) nil
                                     "--dir" vault "--emit-org-ids")))
        (goto-char (point-min))
        (let ((alist (read (current-buffer))))
          (should (eql (length alist) 1))
          (should (equal (cdr (car alist)) '("ok-loop")))))
      ;; Compare against Elisp `fenrir/org-id-index-directory' after removing file symlink cycles
      ;; (`org-id-update-id-locations' throws on `file-truename' of file symlink cycles).
      (let ((rust-loc (gethash "ok-loop" org-id-locations)))
        (delete-file (expand-file-name "selfloop.org" vault))
        (delete-file (expand-file-name "cyc_a.org" vault))
        (delete-file (expand-file-name "cyc_b.org" vault))
        (setq org-id-locations (make-hash-table :test #'equal)
              org-id-files nil)
        (let ((fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
          (fenrir/org-id-index-directory vault))
        (should (eql (hash-table-count org-id-locations) 1))
        (should (equal (file-truename (gethash "ok-loop" org-id-locations))
                       (file-truename rust-loc))))))

  ;; 2. Exclude regex parity on leading `\{\}`, non-leading `\{\}`, and `\{m,n\}?`
  (orst-with-vault (tmp2 vault2 db-rust2 _idfile2)
    (let ((db-elisp2 (expand-file-name "elisp2.db" tmp2)))
      (dolist (name '("b.org" "ab.org" "aab.org" "aaab.org" "a{}b.org" "{}b.org" "a.org"))
        (orst--write-file
         (expand-file-name name vault2)
         (format ":PROPERTIES:\n:ID: id-%s\n:END:\n#+title: %s\n" name name)))
      (dolist (spec '(("\\{\\}" . t)
                      ("^\\{\\}" . t)
                      ("a\\{\\}b" . t)
                      ("\\(a\\)\\{\\}b" . t)
                      ("a\\{\\}?" . nil)
                      ("a\\{1,2\\}?" . nil)))
        (let ((org-roam-file-exclude-regexp (list (car spec)))
              (expect-rust (cdr spec))
              (warning-buf (get-buffer-create " *orst-brace-warn*")))
          (unwind-protect
              (cl-letf (((symbol-function 'display-warning)
                         (lambda (type message &optional _level _buffer-name)
                           (with-current-buffer warning-buf
                             (insert (format "%S: %s\n" type message))))))
                (with-current-buffer warning-buf (erase-buffer))
                (if expect-rust
                    (should (fenrir/org-roam-sync--can-use-rust-p))
                  (should-not (fenrir/org-roam-sync--can-use-rust-p)))
                (org-roam-db-sync t)
                (should (string-empty-p (with-current-buffer warning-buf (buffer-string))))
                (let ((rust-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                  (org-roam-db--close-all)
                  (let ((org-roam-db-location db-elisp2)
                        (fenrir/org-roam-sync-program "/nonexistent/org-roam-sync"))
                    (org-roam-db-sync t)
                    (let ((elisp-ids (sort (mapcar #'org-roam-node-id (org-roam-node-list)) #'string<)))
                      (should (equal rust-ids elisp-ids)))
                    (org-roam-db--close-all))
                  (orst--assert-db-parity db-rust2 db-elisp2)))
            (kill-buffer warning-buf)))))))

(provide 'org-roam-sync-test)
;;; org-roam-sync-test.el ends here
