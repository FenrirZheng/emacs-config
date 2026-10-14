;;; magit-subtree-test.el --- ERT for lisp/fenrir-magit-subtree.el -*- lexical-binding: t; -*-

;; emacs -Q --batch -l test/magit-subtree-test.el -f ert-run-tests-batch-and-exit
;;
;; Like magit-time-test.el this needs Magit, so it activates elpa/ and loads the
;; real init-git.  The integration tests build a throwaway repo with two
;; subtrees (one full-history, one --squash) under `temporary-file-directory'
;; and need `git-subtree-status' on PATH; they are skipped without it.

(require 'ert)
(defconst magit-subtree-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(setq package-user-dir (expand-file-name "elpa" magit-subtree-test--root))
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" magit-subtree-test--root))
(setq forge-database-file
      (expand-file-name "magit-subtree-test-forge.sqlite" temporary-file-directory))
(require 'init-git)
(require 'magit)
(require 'fenrir-magit-subtree)

(defconst magit-subtree-test--porcelain
  "# git-subtree-status v1
libs/a\t2\t-\tsame\t0\t-\t-\t0\t1111111111111111111111111111111111111111
libs/a/b\t0\t3\tchanged\t4\tb/main\tdiffers\t5\tb/main
libs/c\t0\t0\tchanged\t9\tc/main\tsame\t0\tc/main
")

;;;; Pure functions

(ert-deftest magit-subtree-parse-v1 ()
  (let ((rows (fenrir/magit-subtree--parse magit-subtree-test--porcelain)))
    (should (= (length rows) 3))
    (should (equal (plist-get (nth 0 rows) :prefix) "libs/a"))
    (should (= (plist-get (nth 0 rows) :uncommitted) 2))
    (should (null (plist-get (nth 0 rows) :since)))         ; "-" -> nil
    (should (null (plist-get (nth 0 rows) :upstream-ref)))
    (should (= (plist-get (nth 1 rows) :since) 3))
    (should (equal (plist-get (nth 1 rows) :project-rev) "b/main"))))

(ert-deftest magit-subtree-parse-rejects-unknown-format ()
  (should (null (fenrir/magit-subtree--parse "libs/a\t0\n")))
  (should (null (fenrir/magit-subtree--parse ""))))

(ert-deftest magit-subtree-changed-uses-upstream-when-set ()
  (let ((rows (fenrir/magit-subtree--parse magit-subtree-test--porcelain)))
    (should (fenrir/magit-subtree--changed-p (nth 0 rows)))       ; uncommitted
    (should (fenrir/magit-subtree--changed-p (nth 1 rows)))       ; since + differs
    ;; Changed since import but same as its upstream ref: not changed.
    (should-not (fenrir/magit-subtree--changed-p (nth 2 rows)))))

(ert-deftest magit-subtree-owner-longest-prefix ()
  (let ((rows (fenrir/magit-subtree--parse magit-subtree-test--porcelain)))
    (should (equal (plist-get (fenrir/magit-subtree--owner "libs/a/b/x.rs" rows) :prefix) "libs/a/b"))
    (should (equal (plist-get (fenrir/magit-subtree--owner "libs/a/x.rs" rows) :prefix) "libs/a"))
    (should (null (fenrir/magit-subtree--owner "libs/ab/x.rs" rows)))))

;;;; Integration, against a real subtree repo

(defun magit-subtree-test--fixture ()
  "Build a host repo with subtrees libs/full and libs/sq; return its directory."
  (let ((dir (make-temp-file "magit-subtree-fixture" t)))
    (unless (zerop (call-process
                    "bash" nil nil nil "-ec"
                    "g(){ git -c user.name=t -c user.email=t@t -c init.defaultBranch=main \"$@\"; }
cd \"$1\"
g init -q up; cd up; echo a>a.txt; mkdir src; echo x>src/x.rs; g add .; g commit -qm up1; cd ..
g init -q host; cd host; echo r>README; g add .; g commit -qm root
g subtree add -q --prefix=libs/full ../up main >/dev/null 2>&1
g subtree add -q --squash --prefix=libs/sq ../up main >/dev/null 2>&1"
                    "fixture" dir))
      (error "fixture build failed in %s" dir))
    (file-name-as-directory (expand-file-name "host" dir))))

(defmacro magit-subtree-test--with-fixture (var &rest body)
  "Bind VAR to a fresh fixture host repo for BODY; skip without the CLI."
  (declare (indent 1))
  `(progn
     (skip-unless (executable-find fenrir/magit-subtree-program))
     (let* ((,var (magit-subtree-test--fixture))
            (default-directory ,var))
       (fenrir/magit-subtree-forget)
       (unwind-protect (progn ,@body)
         (delete-directory (file-name-directory (directory-file-name ,var)) t)))))

(ert-deftest magit-subtree-rows-from-real-repo ()
  (magit-subtree-test--with-fixture dir
    (let ((rows (fenrir/magit-subtree--rows)))
      (should (equal (mapcar (lambda (r) (plist-get r :prefix)) rows) '("libs/full" "libs/sq")))
      (should-not (seq-some #'fenrir/magit-subtree--changed-p rows)))))

(ert-deftest magit-subtree-status-section-lists-edited-subtree ()
  (magit-subtree-test--with-fixture dir
    (with-temp-file (expand-file-name "libs/full/a.txt" dir) (insert "edited\n"))
    (let ((buf (magit-status-setup-buffer dir)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (should (re-search-forward "^Subtrees (1 changed of 2)" nil t))
            (should (re-search-forward "^libs/full +U:1" nil t))
            (should-not (save-excursion (goto-char (point-min))
                                        (re-search-forward "^libs/sq" nil t))))
        (kill-buffer buf)))))

(ert-deftest magit-subtree-log-opens-project-history ()
  (magit-subtree-test--with-fixture dir
    (let* ((rows (fenrir/magit-subtree--rows))
           (full (fenrir/magit-subtree--owner "libs/full/a.txt" rows))
           (buf (fenrir/magit-subtree--log full nil)))
      (unwind-protect
          (with-current-buffer buf
            (should (derived-mode-p 'magit-log-mode))
            (goto-char (point-min))
            (should (re-search-forward "up1" nil t))           ; the project's own commit
            (should-not (save-excursion (goto-char (point-min))
                                        (re-search-forward "\\broot\\b" nil t))))
        (kill-buffer buf)))))

(ert-deftest magit-subtree-status-counts-untracked-from-magit ()
  (magit-subtree-test--with-fixture dir
    ;; An untracked file under libs/sq: U comes from Magit's Untracked section,
    ;; since the CLI runs with --no-status.
    (with-temp-file (expand-file-name "libs/sq/new.txt" dir) (insert "new\n"))
    (let ((buf (magit-status-setup-buffer dir)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (should (re-search-forward "^Subtrees (1 changed of 2)" nil t))
            (should (re-search-forward "^libs/sq +U:1" nil t)))
        (kill-buffer buf)))))

(ert-deftest magit-subtree-revision-shows-owner ()
  (magit-subtree-test--with-fixture dir
    (let* ((sha (string-trim (shell-command-to-string
                              "git log --format=%H --grep='^up1$' -1")))
           (buf (magit-revision-setup-buffer sha nil nil)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (should (re-search-forward "^Subtree: libs/full$" nil t)))
        (kill-buffer buf)))))

(defun magit-subtree-test--section (prefix)
  "The Subtrees line section for PREFIX in the current status buffer."
  (seq-find (lambda (c) (equal (oref c value) prefix))
            (oref (seq-find (lambda (c) (eq (oref c type) 'fenrir-subtrees))
                            (oref magit-root-section children))
                  children)))

(defun magit-subtree-test--visible-text (section)
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

(defun magit-subtree-test--git (dir &rest args)
  (let ((default-directory dir))
    (apply #'call-process "git" nil nil nil "-c" "user.name=t" "-c" "user.email=t@t" args)))

(ert-deftest magit-subtree-tab-lists-files-by-kind ()
  (magit-subtree-test--with-fixture dir
    ;; libs/full: a.txt staged AND further edited (unstaged); src/x.rs unstaged.
    ;; libs/sq: an untracked file.
    (with-temp-file (expand-file-name "libs/full/a.txt" dir) (insert "staged\n"))
    (magit-subtree-test--git dir "add" "libs/full/a.txt")
    (with-temp-file (expand-file-name "libs/full/a.txt" dir) (insert "staged then edited\n"))
    (with-temp-file (expand-file-name "libs/full/src/x.rs" dir) (insert "edited\n"))
    (with-temp-file (expand-file-name "libs/sq/new.txt" dir) (insert "new\n"))
    (let ((buf (magit-status-setup-buffer dir)))
      (unwind-protect
          (with-current-buffer buf
            (let ((full (magit-subtree-test--section "libs/full"))
                  (sq (magit-subtree-test--section "libs/sq")))
              ;; a.txt counted once although it is both staged and unstaged.
              (should (string-match-p "^libs/full +U:2" (magit-subtree-test--visible-text full)))
              ;; Folded by default: no file lines visible.
              (should-not (string-match-p "a\\.txt" (magit-subtree-test--visible-text full)))
              (magit-section-show full)
              (let ((text (magit-subtree-test--visible-text full)))
                (should (string-match-p "^  staged +libs/full/a\\.txt$" text))
                (should (string-match-p "^  unstaged +libs/full/a\\.txt$" text))
                (should (string-match-p "^  unstaged +libs/full/src/x\\.rs$" text)))
              (magit-section-show sq)
              (should (string-match-p "^  untracked +libs/sq/new\\.txt$"
                                      (magit-subtree-test--visible-text sq)))))
        (kill-buffer buf)))))

(ert-deftest magit-subtree-tab-state-survives-refresh ()
  (magit-subtree-test--with-fixture dir
    (with-temp-file (expand-file-name "libs/full/a.txt" dir) (insert "edited\n"))
    (let ((buf (magit-status-setup-buffer dir)))
      (unwind-protect
          (with-current-buffer buf
            (magit-section-show (magit-subtree-test--section "libs/full"))
            ;; A second change alters the row's counts; the section must stay open.
            (with-temp-file (expand-file-name "libs/full/src/x.rs" dir) (insert "edited\n"))
            (magit-refresh-buffer)
            (let ((full (magit-subtree-test--section "libs/full")))
              (should-not (oref full hidden))
              (should (string-match-p "src/x\\.rs" (magit-subtree-test--visible-text full)))))
        (kill-buffer buf)))))

(ert-deftest magit-subtree-ret-on-file-visits-it ()
  (magit-subtree-test--with-fixture dir
    (with-temp-file (expand-file-name "libs/sq/new.txt" dir) (insert "new\n"))
    (let ((buf (magit-status-setup-buffer dir)) visited)
      (unwind-protect
          (with-current-buffer buf
            (let ((sq (magit-subtree-test--section "libs/sq")))
              (magit-section-show sq)
              (goto-char (oref (car (oref sq children)) start))
              (call-interactively (key-binding (kbd "RET")))
              (setq visited (current-buffer))
              (should (equal buffer-file-name (expand-file-name "libs/sq/new.txt" dir)))))
        (when (buffer-live-p visited) (kill-buffer visited))
        (kill-buffer buf)))))

(ert-deftest magit-subtree-no-subtree-repo-shows-nothing ()
  (skip-unless (executable-find fenrir/magit-subtree-program))
  (let ((dir (file-name-as-directory (make-temp-file "magit-subtree-plain" t))))
    (unwind-protect
        (let ((default-directory dir))
          (call-process "bash" nil nil nil "-ec"
                        "git -c init.defaultBranch=main init -q . && echo x>f && git add f && git -c user.name=t -c user.email=t@t commit -qm one")
          (fenrir/magit-subtree-forget)
          (should (null (fenrir/magit-subtree--rows)))
          (should (gethash (directory-file-name (magit-toplevel)) fenrir/magit-subtree--none
                           (gethash (magit-toplevel) fenrir/magit-subtree--none))))
      (delete-directory dir t))))

;;; magit-subtree-test.el ends here
