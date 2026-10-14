;;; magit-nested-test.el --- ERT for lisp/fenrir-magit-nested.el -*- lexical-binding: t; -*-

;; emacs -Q --batch -l test/magit-nested-test.el -f ert-run-tests-batch-and-exit
;;
;; Like magit-subtree-test.el this needs Magit, so it activates elpa/ and loads
;; the real init-git.  The integration tests rebuild the spec's fixture,
;; /tmp/magit-nested-fixture, with its make-fixture.sh, and need the
;; `git-nested-status' binary in rust/lib/; they are skipped without it.  Each
;; one runs the binary through a wrapper that logs every run, so a test can
;; count how often the section asked.

(require 'ert)
(defconst magit-nested-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(setq package-user-dir (expand-file-name "elpa" magit-nested-test--root))
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" magit-nested-test--root))
(setq forge-database-file
      (expand-file-name "magit-nested-test-forge.sqlite" temporary-file-directory))
(require 'init-git)
(require 'magit)
(require 'fenrir-magit-subtree)
(require 'fenrir-magit-nested)

(defconst magit-nested-test--porcelain
  "# git-nested-status v1
R\trepos/clean\tmain\t69ca2b2\torigin/main\t0\t0\t0\t0\t0
R\trepos/detached\t-\t7384116\t-\t-\t-\t0\t0\t0
R\trepos/dirty\tmain\t5b2ee9f\torigin/main\t1\t0\t1\t1\t1
F\tstaged\ta.txt
F\tunstaged\ta.txt
F\tuntracked\tnew.txt
R\trepos/local\tmain\t1234567\t-\t-\t-\t0\t0\t0
")

;;;; Pure functions

(ert-deftest magit-nested-parse-v1 ()
  (let ((rows (fenrir/magit-nested--parse magit-nested-test--porcelain)))
    (should (equal (mapcar (lambda (r) (plist-get r :path)) rows)
                   '("repos/clean" "repos/detached" "repos/dirty" "repos/local")))
    (let ((dirty (nth 2 rows)))
      (should (equal (plist-get dirty :branch) "main"))
      (should (equal (plist-get dirty :upstream) "origin/main"))
      (should (= (plist-get dirty :ahead) 1))
      (should (= (plist-get dirty :behind) 0))
      (should (equal (plist-get dirty :files)
                     '((staged . "a.txt") (unstaged . "a.txt") (untracked . "new.txt")))))
    (should (null (plist-get (nth 1 rows) :branch)))       ; "-" -> nil
    (should (null (plist-get (nth 1 rows) :ahead)))
    (should (null (plist-get (nth 0 rows) :files)))))

(ert-deftest magit-nested-parse-rejects-unknown-format ()
  (should (null (fenrir/magit-nested--parse "R\trepos/a\tmain\n")))
  (should (null (fenrir/magit-nested--parse "")))
  (should (null (fenrir/magit-nested--parse "# git-nested-status v1\n"))))

(ert-deftest magit-nested-changed-and-uncommitted ()
  (let ((rows (fenrir/magit-nested--parse magit-nested-test--porcelain)))
    (should-not (fenrir/magit-nested--changed-p (nth 0 rows)))   ; clean
    (should (fenrir/magit-nested--changed-p (nth 1 rows)))       ; detached
    (should (fenrir/magit-nested--changed-p (nth 2 rows)))       ; dirty
    ;; No upstream alone is not a change (approved default).
    (should-not (fenrir/magit-nested--changed-p (nth 3 rows)))
    ;; a.txt is both staged and unstaged: two paths, not three.
    (should (= (fenrir/magit-nested--uncommitted (nth 2 rows)) 2))))

(ert-deftest magit-nested-skips-home ()
  (should (fenrir/magit-nested--skipped-p "~/"))
  (should (fenrir/magit-nested--skipped-p (expand-file-name "~")))
  (should-not (fenrir/magit-nested--skipped-p (expand-file-name "~/code/"))))

(ert-deftest magit-nested-hook-after-subtrees ()
  (let* ((hook (default-value 'magit-status-sections-hook))
         (staged (cl-position 'magit-insert-staged-changes hook))
         (subtree (cl-position #'fenrir/magit-subtree-insert-section hook))
         (nested (cl-position #'fenrir/magit-nested-insert-section hook)))
    (should (and staged subtree nested))
    (should (< staged subtree nested))))

;;;; Integration, against the spec's fixture

(defconst magit-nested-test--fixture "/tmp/magit-nested-fixture/"
  "The fixture directory the spec's 驗收條件 name.")

(defconst magit-nested-test--make-fixture
  (expand-file-name
   "sliced-spec/2026-10-14/120738-magit-nested-repos/make-fixture.sh"
   magit-nested-test--root))

(defvar magit-nested-test--log nil
  "File the wrapper appends one line to per helper run.")

(defun magit-nested-test--runs ()
  "How many times the helper ran since the log was created."
  (with-temp-buffer
    (insert-file-contents magit-nested-test--log)
    (count-lines (point-min) (point-max))))

(defmacro magit-nested-test--with-fixture (&rest body)
  "Rebuild the fixture, run BODY with the helper behind a counting wrapper.
Skip without the helper."
  (declare (indent 0))
  `(let ((real (expand-file-name "rust/lib/git-nested-status" magit-nested-test--root)))
     (skip-unless (file-executable-p real))
     (unless (zerop (call-process "bash" nil nil nil magit-nested-test--make-fixture
                                  (directory-file-name magit-nested-test--fixture)))
       (error "fixture build failed"))
     (let* ((tmp (make-temp-file "magit-nested-test" t))
            (magit-nested-test--log (expand-file-name "runs.log" tmp))
            (wrapper (expand-file-name "git-nested-status" tmp))
            (fenrir/magit-nested-program wrapper))
       (with-temp-file magit-nested-test--log)
       (with-temp-file wrapper
         (insert (format "#!/bin/sh\necho run >> %s\nexec %s \"$@\"\n"
                         (shell-quote-argument magit-nested-test--log)
                         (shell-quote-argument real))))
       (set-file-modes wrapper #o755)
       (fenrir/magit-nested-forget)
       (unwind-protect (progn ,@body)
         (delete-directory tmp t)))))

(defun magit-nested-test--section (&optional path)
  "The Nested repos section, or its line for PATH, in the current status buffer."
  (let ((top (seq-find (lambda (c) (eq (oref c type) 'fenrir-nested-repos))
                       (oref magit-root-section children))))
    (if (and top path)
        (seq-find (lambda (c) (equal (oref c value) path)) (oref top children))
      top)))

(defun magit-nested-test--visible-text (section)
  "SECTION's text with hidden (folded) parts removed."
  (let ((out ""))
    (save-excursion
      (goto-char (oref section start))
      (while (< (point) (oref section end))
        (let ((next (next-single-char-property-change (point) 'invisible nil (oref section end))))
          (unless (invisible-p (point))
            (setq out (concat out (buffer-substring-no-properties (point) next))))
          (goto-char next))))
    out))

(ert-deftest magit-nested-status-section ()
  "驗收條件 4."
  (magit-nested-test--with-fixture
    ;; A staged edit in the umbrella, so a Staged changes section exists to
    ;; come after.
    (let ((default-directory magit-nested-test--fixture))
      (with-temp-file "README.md" (insert "umbrella, edited\n"))
      (call-process "git" nil nil nil "add" "README.md"))
    (let ((buf (magit-status-setup-buffer magit-nested-test--fixture)))
      (unwind-protect
          (with-current-buffer buf
            (should (memq 'staged (mapcar (lambda (c) (oref c type))
                                          (oref magit-root-section children))))
            (let ((section (magit-nested-test--section)))
              (should section)
              (let ((text (buffer-substring-no-properties (oref section start)
                                                          (oref section end))))
                (should (string-match-p "\\`Nested repos (2 changed of 3)$" text))
                (should (string-match-p "^repos/detached +detached [0-9a-f]+" text))
                (should (string-match-p "^repos/dirty +main +↑1 +U:2$" text))
                (should-not (string-match-p "repos/clean" text))
                (should-not (string-match-p "deep/x/y\\|repos/plain" text)))
              ;; After the sections drawn before it (Untracked, Unstaged …).
              (let ((types (mapcar (lambda (c) (oref c type)) (oref magit-root-section children))))
                (dolist (earlier '(untracked unstaged staged fenrir-subtrees))
                  (when (memq earlier types)
                    (should (< (cl-position earlier types)
                               (cl-position 'fenrir-nested-repos types))))))
              (should (= (magit-nested-test--runs) 1))))
        (kill-buffer buf)))))

(ert-deftest magit-nested-row-actions ()
  "驗收條件 5."
  (magit-nested-test--with-fixture
    (let ((buf (magit-status-setup-buffer magit-nested-test--fixture))
          visited status)
      (unwind-protect
          (with-current-buffer buf
            (let ((dirty (magit-nested-test--section "repos/dirty")))
              ;; Folded by default.
              (should-not (string-match-p "a\\.txt" (magit-nested-test--visible-text dirty)))
              (goto-char (oref dirty start))
              (call-interactively (key-binding (kbd "TAB")))
              (let ((text (magit-nested-test--visible-text dirty)))
                (should (string-match-p "^  unstaged +a\\.txt$" text))
                (should (string-match-p "^  untracked +new\\.txt$" text))
                (should (= 2 (length (oref dirty children)))))
              ;; RET on a file line visits it.
              (goto-char (oref (car (oref dirty children)) start))
              (save-window-excursion
                (call-interactively (key-binding (kbd "RET")))
                (setq visited (current-buffer))
                (should (equal buffer-file-name
                               (expand-file-name "repos/dirty/a.txt" magit-nested-test--fixture))))
              ;; RET on the row opens the clone's own status.
              (set-buffer buf)
              (goto-char (oref dirty start))
              (save-window-excursion
                (call-interactively (key-binding (kbd "RET")))
                (setq status (current-buffer))
                (should (derived-mode-p 'magit-status-mode))
                (should (equal default-directory
                               (expand-file-name "repos/dirty/" magit-nested-test--fixture))))))
        (dolist (b (list visited status))
          (when (and (buffer-live-p b) (not (eq b buf))) (kill-buffer b)))
        (kill-buffer buf)))))

(ert-deftest magit-nested-tab-state-survives-refresh ()
  (magit-nested-test--with-fixture
    (let ((buf (magit-status-setup-buffer magit-nested-test--fixture)))
      (unwind-protect
          (with-current-buffer buf
            (magit-section-show (magit-nested-test--section "repos/dirty"))
            (with-temp-file (expand-file-name "repos/dirty/other.txt" magit-nested-test--fixture)
              (insert "x\n"))
            (magit-refresh-buffer)
            (let ((dirty (magit-nested-test--section "repos/dirty")))
              (should-not (oref dirty hidden))
              (should (string-match-p "other\\.txt" (magit-nested-test--visible-text dirty)))))
        (kill-buffer buf)))))

(ert-deftest magit-nested-home-skipped ()
  "驗收條件 9."
  (magit-nested-test--with-fixture
    (let ((buf (magit-status-setup-buffer (expand-file-name "~/"))))
      (unwind-protect
          (with-current-buffer buf
            (should-not (magit-nested-test--section))
            (goto-char (point-min))
            (should-not (re-search-forward "^Nested repos" nil t))
            (should (= (magit-nested-test--runs) 0)))
        (kill-buffer buf)))))

(ert-deftest magit-nested-none-remembered ()
  "驗收條件 10."
  (magit-nested-test--with-fixture
    (let ((buf (magit-status-setup-buffer
                (expand-file-name "repos/clean/" magit-nested-test--fixture))))
      (unwind-protect
          (with-current-buffer buf
            (should-not (magit-nested-test--section))
            (should (= (magit-nested-test--runs) 1))
            (magit-refresh-buffer)
            (should (= (magit-nested-test--runs) 1))
            (fenrir/magit-nested-forget)
            (magit-refresh-buffer)
            (should (= (magit-nested-test--runs) 2))
            (should-not (magit-nested-test--section)))
        (kill-buffer buf)))))

(ert-deftest magit-nested-unbuilt ()
  "驗收條件 11: the real rust/lib/git-nested-status is moved aside for the test."
  (magit-nested-test--with-fixture
    (let* ((fenrir/magit-nested-program
            (expand-file-name "rust/lib/git-nested-status" magit-nested-test--root))
           (aside (concat fenrir/magit-nested-program ".test-aside"))
           (fenrir/magit-nested--hinted nil)
           (messages (get-buffer-create "*Messages*"))
           (mark (with-current-buffer messages (point-max)))
           buf)
      (rename-file fenrir/magit-nested-program aside)
      (unwind-protect
          (progn
            (should-not (file-exists-p fenrir/magit-nested-program))
            (setq buf (magit-status-setup-buffer magit-nested-test--fixture))
            (with-current-buffer buf
              (should-not (magit-nested-test--section)))
            (let ((new (with-current-buffer messages
                         (buffer-substring-no-properties mark (point-max)))))
              (should-not (string-match-p "[Ee]rror" new))
              (should (string-match-p "Nested repos: .* is not built" new))))
        (rename-file aside fenrir/magit-nested-program)
        (when (buffer-live-p buf) (kill-buffer buf))))))

;;; magit-nested-test.el ends here
