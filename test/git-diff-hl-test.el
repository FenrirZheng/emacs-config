;;; git-diff-hl-test.el --- ERT suite for git-diff-hl and init-git.el integration -*- lexical-binding: t; -*-

;; Run via:
;;   emacs -Q --batch -l test/git-diff-hl-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'vc)
(require 'vc-hooks)

(defconst gdh-test--root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))))

(defconst gdh-test--state-dir
  (file-name-as-directory (make-temp-file "gdh-test-state-" t)))

(add-hook 'kill-emacs-hook
          (lambda ()
            (when (file-directory-p gdh-test--state-dir)
              (delete-directory gdh-test--state-dir t))))

(setq user-emacs-directory gdh-test--root
      package-user-dir (expand-file-name "elpa" gdh-test--root)
      use-package-always-ensure nil
      forge-database-file (expand-file-name "forge.sqlite" gdh-test--state-dir)
      transient-history-file (expand-file-name "transient-history.el" gdh-test--state-dir)
      transient-levels-file (expand-file-name "transient-levels.el" gdh-test--state-dir)
      transient-values-file (expand-file-name "transient-values.el" gdh-test--state-dir))

(require 'package)
(package-initialize)
(require 'use-package)
(add-to-list 'load-path (expand-file-name "lisp" gdh-test--root))

(load (expand-file-name "lisp/init-git.el" gdh-test--root) nil t)
(require 'magit)
(require 'diff-hl)

(defvar fenrir/git-diff-hl-program)
(defvar diff-hl-margin-local-mode)
(defvar diff-hl-flydiff-modified-tick)
(declare-function fenrir/diff-hl--parse-porcelain "init-git")
(declare-function fenrir/diff-hl--run-batch "init-git")
(declare-function fenrir/diff-hl-magit-post-refresh "init-git")
(declare-function diff-hl-flydiff-update "diff-hl-flydiff")

;;;; Helpers

(defun gdh-test--git (repo &rest args)
  "Run git in REPO with ARGS, failing the test on non-zero exit (unless ignored)."
  (let ((default-directory (file-name-as-directory repo)))
    (with-temp-buffer
      (let ((rc (apply #'call-process "git" nil t nil args)))
        (unless (eql rc 0)
          (ert-fail (format "git %S failed (%s): %s" args rc (buffer-string))))
        (buffer-string)))))

(defun gdh-test--git-allow-fail (repo &rest args)
  "Run git in REPO with ARGS and return exit status."
  (let ((default-directory (file-name-as-directory repo)))
    (apply #'call-process "git" nil nil nil args)))

(defun gdh-test--write (repo rel content)
  "Write raw binary CONTENT to REL under REPO."
  (let* ((path (expand-file-name rel repo))
         (coding-system-for-write 'no-conversion))
    (make-directory (file-name-directory path) t)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert content)
      (write-region (point-min) (point-max) path nil 'silent))))

(defun gdh-test--init-repo (name)
  "Create a fresh git repo under temporary directory with NAME."
  (let ((dir (file-name-as-directory (make-temp-file (format "gdh-repo-%s-" name) t))))
    (gdh-test--git dir "init" "-q")
    (gdh-test--git dir "config" "user.name" "Test")
    (gdh-test--git dir "config" "user.email" "test@example.com")
    dir))

(defmacro gdh-test--with-repo (var name &rest body)
  "Bind VAR to a fresh temp git repo, cleaning it and its buffers afterward."
  (declare (indent 2))
  `(let ((,var (gdh-test--init-repo ,name))
         (gdh-test--opened-bufs nil))
     (unwind-protect
         (cl-letf (((symbol-function 'gdh-test--track-buf)
                    (lambda (b) (push b gdh-test--opened-bufs) b)))
           ,@body)
       (dolist (b gdh-test--opened-bufs)
         (when (buffer-live-p b)
           (with-current-buffer b
             (set-buffer-modified-p nil))
           (kill-buffer b)))
       (when (file-directory-p ,var)
         (delete-directory ,var t)))))

(defun gdh-test--open (repo rel)
  "Open REL in REPO cleanly, enabling `diff-hl-mode' and tracking for cleanup."
  (let ((buf (find-file-noselect (expand-file-name rel repo))))
    (with-current-buffer buf
      (unless diff-hl-mode
        (diff-hl-mode 1))
      (unless diff-hl-margin-local-mode
        (diff-hl-margin-local-mode 1)))
    (when (fboundp 'gdh-test--track-buf)
      (gdh-test--track-buf buf))
    buf))

(defun gdh-test--overlay-snapshot (buf)
  "Return deterministic snapshot of `diff-hl' overlays in BUF."
  (with-current-buffer buf
    (save-excursion
      (save-restriction
        (widen)
        (let (hunks margins)
          (dolist (o (overlays-in (point-min) (point-max)))
            (cond
             ((overlay-get o 'diff-hl-hunk)
              (push (list (line-number-at-pos (overlay-start o))
                          (line-number-at-pos (overlay-end o))
                          (overlay-get o 'diff-hl-hunk-type))
                    hunks))
             ((overlay-get o 'diff-hl)
              (let* ((bs (overlay-get o 'before-string))
                     (disp (and (stringp bs) (get-text-property 0 'display bs)))
                     (sym (and (consp disp) (stringp (cadr disp))
                               (substring-no-properties (cadr disp)))))
                (push (list (line-number-at-pos (overlay-start o)) sym)
                      margins)))))
          (list (sort hunks (lambda (a b)
                              (or (< (car a) (car b))
                                  (and (= (car a) (car b)) (< (cadr a) (cadr b))))))
                (sort margins (lambda (a b)
                                (or (< (car a) (car b))
                                    (and (= (car a) (car b))
                                         (string< (or (cadr a) "") (or (cadr b) ""))))))))))))

(defun gdh-test--assert-parity (repo bufs)
  "Assert `vc-state' and overlay snapshots match stock `diff-hl' across BUFS."
  (let ((stock (make-hash-table :test #'eq))
        (flydiff-was-on (bound-and-true-p diff-hl-flydiff-mode)))
    ;; 1. Collect true stock vc-git baseline in each buffer (with flydiff off so
    ;;    diff-hl calls vc-git `git diff-index' rather than diff-hl-create-revision,
    ;;    which errors on staged-added AM files absent from HEAD).
    (unwind-protect
        (progn
          (when flydiff-was-on
            (diff-hl-flydiff-mode -1))
          (dolist (buf bufs)
            (with-current-buffer buf
              (when-let* ((backend (vc-backend buffer-file-name)))
                (vc-state-refresh buffer-file-name backend))
              (diff-hl-update)
              (puthash buf
                       (cons (vc-file-getprop buffer-file-name 'vc-state)
                             (gdh-test--overlay-snapshot buf))
                       stock))))
      (when flydiff-was-on
        (diff-hl-flydiff-mode 1)))
    ;; 2. Reset overlays, vc-file props, and flydiff ticks.
    (dolist (buf bufs)
      (with-current-buffer buf
        (diff-hl-remove-overlays)
        (vc-file-clearprops buffer-file-name)
        (setq diff-hl-flydiff-modified-tick -1)))
    ;; 3. Run Rust-backed batch diff-hl-magit-post-refresh.
    (let ((default-directory repo))
      (diff-hl-magit-post-refresh))
    ;; 4. Compare every buffer against stock baseline.
    (dolist (buf bufs)
      (with-current-buffer buf
        (let* ((expected (gethash buf stock))
               (actual-state (vc-file-getprop buffer-file-name 'vc-state))
               (actual-ovls (gdh-test--overlay-snapshot buf)))
          (should (equal (list buffer-file-name actual-state actual-ovls)
                         (list buffer-file-name (car expected) (cdr expected)))))))))

;;;; Group A — Pure Parsing & CLI Contract

(ert-deftest gdh-parse-porcelain-v1 ()
  (with-temp-buffer
    (insert "# git-diff-hl v1\n"
            "F\tup-to-date\tlisp/clean.el\n"
            "F\tedited\tlisp/init-git.el\n"
            "H\t10\t2\t0\tinsert\n"
            "H\t42\t1\t3\tchange\n"
            "F\tunregistered\tnew.el\n"
            "F\tignored\tbuild.log\n")
    (let ((tbl (fenrir/diff-hl--parse-porcelain)))
      (should (hash-table-p tbl))
      (should (= (hash-table-count tbl) 4))
      (should (equal (gethash "lisp/clean.el" tbl) '(up-to-date)))
      (should (equal (gethash "lisp/init-git.el" tbl)
                     '(edited (10 2 0 insert) (42 1 3 change))))
      (should (equal (gethash "new.el" tbl) '(unregistered)))
      (should (equal (gethash "build.log" tbl) '(ignored))))))

(ert-deftest gdh-parse-rejects-invalid-header ()
  (dolist (bad '(""
                 "F\tedited\ta.el\n"
                 "# git-diff-hl v99\nF\tedited\ta.el\n"
                 "garbage\n"))
    (with-temp-buffer
      (insert bad)
      (should (null (fenrir/diff-hl--parse-porcelain))))))

(ert-deftest gdh-cli-porcelain-all-v1 ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "cli-v1"
    (gdh-test--write repo "a.txt" "hello\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "init")
    (with-temp-buffer
      (let ((rc (call-process fenrir/git-diff-hl-program nil t nil
                              "-C" repo "--porcelain" "--all")))
        (should (eql rc 0))
        (goto-char (point-min))
        (should (looking-at-p "\\`# git-diff-hl v1$"))
        (should (string-match-p "F\tup-to-date\ta\\.txt" (buffer-string)))))))

;;;; Group B — Parity Against Stock vc-git

(ert-deftest gdh-parity-standard-repo ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "std-parity"
    (gdh-test--write repo ".gitignore" "*.log\n")
    (gdh-test--write repo "clean.txt" "a\nb\nc\n")
    (gdh-test--write repo "ins-bof.txt" "a\nb\n")
    (gdh-test--write repo "ins-mid.txt" "1\n2\n3\n4\n")
    (gdh-test--write repo "ins-eof.txt" "1\n2\n")
    (gdh-test--write repo "del-bof.txt" "1\n2\n3\n")
    (gdh-test--write repo "del-mid.txt" "1\n2\n3\n4\n5\n")
    (gdh-test--write repo "del-eof.txt" "1\n2\n3\n")
    (gdh-test--write repo "del-all.txt" "1\n2\n3\n")
    (gdh-test--write repo "chg-1toN.txt" "a\nb\nc\n")
    (gdh-test--write repo "chg-Nto1.txt" "a\nx\ny\nc\n")
    (gdh-test--write repo "multi-hunk.txt" "1\n2\n3\n4\n5\n6\n7\n")
    (gdh-test--write repo "no-nl.txt" "x\ny")
    (gdh-test--write repo "rm-cached.txt" "keep on disk\n")
    (gdh-test--write repo "blob.bin" "\x00\x01\x02\x03")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "init")

    ;; Open rm-cached.txt while still tracked so vc-backend caches 'Git,
    ;; matching a live session where user runs `git rm --cached'.
    (let ((rm-cached-buf (gdh-test--open repo "rm-cached.txt")))
      (gdh-test--git repo "rm" "--cached" "-q" "rm-cached.txt")

      ;; Mutate working tree & staging area.
      (gdh-test--write repo "ins-bof.txt" "x\ny\na\nb\n")
      (gdh-test--write repo "ins-mid.txt" "1\n2\nx\n3\n4\n")
      (gdh-test--write repo "ins-eof.txt" "1\n2\n3\n")
      (gdh-test--write repo "del-bof.txt" "2\n3\n")
      (gdh-test--write repo "del-mid.txt" "1\n2\n4\n5\n")
      (gdh-test--write repo "del-eof.txt" "1\n2\n")
      (gdh-test--write repo "del-all.txt" "")
      (gdh-test--write repo "chg-1toN.txt" "a\nx\ny\nz\nc\n")
      (gdh-test--write repo "chg-Nto1.txt" "a\nb\nc\n")
      (gdh-test--write repo "multi-hunk.txt" "1\nX\n3\n4\n5\nY\n7\n")
      (gdh-test--write repo "no-nl.txt" "x\ny\nz\n")
      (gdh-test--write repo "blob.bin" "\x00\x01\x02\x03\x04")

      ;; Staged added (with and without trailing newline, plus empty)
      (gdh-test--write repo "added.txt" "line1\nline2\n")
      (gdh-test--write repo "added-nonl.txt" "line1\nline2")
      (gdh-test--write repo "added-empty.txt" "")
      (gdh-test--git repo "add" "added.txt" "added-nonl.txt" "added-empty.txt")

      ;; Staged + modified (AM)
      (gdh-test--write repo "am.txt" "one\n")
      (gdh-test--git repo "add" "am.txt")
      (gdh-test--write repo "am.txt" "one\ntwo\n")

      ;; Untracked and ignored
      (gdh-test--write repo "untracked.txt" "u\n")
      (gdh-test--write repo "ignored.log" "i\n")

      (let ((bufs
             (cons rm-cached-buf
                   (mapcar (lambda (f) (gdh-test--open repo f))
                           '("clean.txt" "ins-bof.txt" "ins-mid.txt" "ins-eof.txt"
                             "del-bof.txt" "del-mid.txt" "del-eof.txt" "del-all.txt"
                             "chg-1toN.txt" "chg-Nto1.txt" "multi-hunk.txt"
                             "no-nl.txt" "added.txt" "added-nonl.txt" "added-empty.txt"
                             "am.txt" "untracked.txt" "ignored.log" "blob.bin")))))
        ;; Also verify narrowed buffer parity on multi-hunk.txt.
        (let ((mh-buf (cl-find-if (lambda (b)
                                    (string-suffix-p "multi-hunk.txt" (buffer-file-name b)))
                                  bufs)))
          (with-current-buffer mh-buf
            (narrow-to-region (point-min) (+ (point-min) 4))))
        (gdh-test--assert-parity repo bufs)))))

(ert-deftest gdh-parity-conflict ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "conflict-parity"
    (gdh-test--write repo "c.txt" "base\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "base")
    (let ((main-br (string-trim (gdh-test--git repo "branch" "--show-current"))))
      (gdh-test--git repo "checkout" "-q" "-b" "side")
      (gdh-test--write repo "c.txt" "side\n")
      (gdh-test--git repo "add" "c.txt")
      (gdh-test--git repo "commit" "-q" "-m" "side")
      (gdh-test--git repo "checkout" "-q" main-br)
      (gdh-test--write repo "c.txt" "main\n")
      (gdh-test--git repo "add" "c.txt")
      (gdh-test--git repo "commit" "-q" "-m" "main")
      (should (eql 1 (gdh-test--git-allow-fail repo "merge" "-q" "side")))
      (let ((buf (gdh-test--open repo "c.txt")))
        (gdh-test--assert-parity repo (list buf))))))

(ert-deftest gdh-parity-unborn-head ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "unborn-parity"
    (gdh-test--write repo "added.txt" "l1\nl2\n")
    (gdh-test--git repo "add" "added.txt")
    (gdh-test--write repo "am.txt" "first\n")
    (gdh-test--git repo "add" "am.txt")
    (gdh-test--write repo "am.txt" "first\nsecond\n")
    (gdh-test--write repo "untracked.txt" "hi\n")
    (let ((bufs (mapcar (lambda (f) (gdh-test--open repo f))
                        '("added.txt" "am.txt" "untracked.txt"))))
      (gdh-test--assert-parity repo bufs))))

;;;; Group C — Edge Cases & Fallback Contracts

(ert-deftest gdh-zero-eligible-buffers-zero-subprocesses ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo outer "outer"
    (gdh-test--write outer "outer.txt" "o\n")
    (gdh-test--git outer "add" "-A")
    (gdh-test--git outer "commit" "-q" "-m" "outer")
    ;; Nested repo inside outer (like ~/.emacs.d inside ~/).
    (let ((inner (expand-file-name "nested/" outer)))
      (make-directory inner t)
      (gdh-test--git inner "init" "-q")
      (gdh-test--git inner "config" "user.name" "Test")
      (gdh-test--git inner "config" "user.email" "test@example.com")
      (gdh-test--write inner "inner.txt" "i\n")
      (gdh-test--git inner "add" "-A")
      (gdh-test--git inner "commit" "-q" "-m" "inner")

      ;; Create ineligible buffers in outer:
      ;; 1. unsaved (modified), 2. diff-hl-mode disabled, 3. indirect, 4. inner repo buffer.
      (let* ((mod-buf (gdh-test--open outer "outer.txt"))
             (nomode-buf (find-file-noselect (expand-file-name "outer.txt" outer)))
             (ind-buf (make-indirect-buffer mod-buf "gdh-indirect-test" t))
             (inner-buf (gdh-test--open inner "inner.txt"))
             (spawn-count 0))
        (unwind-protect
            (progn
              (with-current-buffer mod-buf
                (insert "unsaved")
                (set-buffer-modified-p t))
              ;; Ensure no other diff-hl-mode buffers interfere; count process calls.
              (cl-letf* ((orig-call-process (symbol-function 'call-process))
                         (orig-call-process-region (symbol-function 'call-process-region))
                         ((symbol-function 'call-process)
                          (lambda (prog &rest args)
                            (when (string-match-p "git" prog)
                              (cl-incf spawn-count))
                            (apply orig-call-process prog args)))
                         ((symbol-function 'call-process-region)
                          (lambda (start end prog &rest args)
                            (when (string-match-p "git" prog)
                              (cl-incf spawn-count))
                            (apply orig-call-process-region start end prog args)))
                         ((symbol-function 'magit-toplevel)
                          (lambda (&optional _dir) outer)))
                ;; Disable diff-hl-mode on any unrelated buffers from other tests if present
                (with-current-buffer nomode-buf
                  (diff-hl-mode -1))
                (let ((default-directory outer))
                  (diff-hl-magit-post-refresh))
                (should (= spawn-count 0))))
          (when (buffer-live-p ind-buf) (kill-buffer ind-buf))
          (when (buffer-live-p nomode-buf) (kill-buffer nomode-buf))
          (when (buffer-live-p inner-buf) (kill-buffer inner-buf)))))))

(ert-deftest gdh-missing-binary-fallback ()
  (gdh-test--with-repo repo "missing-bin"
    (gdh-test--write repo "a.txt" "1\n2\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "init")
    (gdh-test--write repo "a.txt" "1\n2\n3\n")
    (let ((buf (gdh-test--open repo "a.txt")))
      (with-current-buffer buf
        (diff-hl-remove-overlays))
      (let ((fenrir/git-diff-hl-program "/nonexistent/git-diff-hl")
            (default-directory repo))
        (diff-hl-magit-post-refresh))
      (should (equal (car (gdh-test--overlay-snapshot buf))
                     '((3 4 insert)))))))

(ert-deftest gdh-remote-path-fallback ()
  (gdh-test--with-repo repo "remote-fallback"
    (gdh-test--write repo "a.txt" "1\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "init")
    (let ((batch-called nil)
          (orig-called nil))
      (cl-letf (((symbol-function 'file-remote-p)
                 (lambda (file &rest _)
                   (equal file "/ssh:fake:/repo/")))
                ((symbol-function 'fenrir/diff-hl--run-batch)
                 (lambda (&rest _) (setq batch-called t) nil))
                ((symbol-function 'diff-hl-magit-post-refresh)
                 (lambda () (setq orig-called t))))
        ;; Call advice directly with fake orig-fn to verify remote skips batch helper.
        (let ((default-directory "/ssh:fake:/repo/")
              (diff-hl-disable-on-remote t))
          (fenrir/diff-hl-magit-post-refresh (lambda () (setq orig-called t)))
          (should orig-called)
          (should-not batch-called))))))

(ert-deftest gdh-reference-revision-and-no-staged-delegation ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "delegation"
    (gdh-test--write repo "norm.txt" "1\n")
    (gdh-test--write repo "ref.txt" "v1\n")
    (gdh-test--write repo "nostage.txt" "a\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "c1")
    (gdh-test--write repo "ref.txt" "v2\n")
    (gdh-test--git repo "add" "ref.txt")
    (gdh-test--git repo "commit" "-q" "-m" "c2")

    ;; Modify norm.txt in WT, stage change to nostage.txt + edit WT of nostage.txt
    (gdh-test--write repo "norm.txt" "1\n2\n")
    (gdh-test--write repo "nostage.txt" "a\nb\n")
    (gdh-test--git repo "add" "nostage.txt")
    (gdh-test--write repo "nostage.txt" "a\nb\nc\n")

    (let ((b-norm (gdh-test--open repo "norm.txt"))
          (b-ref (gdh-test--open repo "ref.txt"))
          (b-nostage (gdh-test--open repo "nostage.txt"))
          (batch-paths nil))
      (with-current-buffer b-ref
        (setq-local diff-hl-reference-revision "HEAD~1"))
      (with-current-buffer b-nostage
        (setq-local diff-hl-show-staged-changes nil))

      ;; Capture stock baselines for delegated buffers
      (let ((stock-ref (progn (with-current-buffer b-ref (diff-hl-update) (gdh-test--overlay-snapshot b-ref))))
            (stock-ns (progn (with-current-buffer b-nostage (diff-hl-update) (gdh-test--overlay-snapshot b-nostage))))
            (orig-run (symbol-function 'fenrir/diff-hl--run-batch)))
        (dolist (b (list b-norm b-ref b-nostage))
          (with-current-buffer b (diff-hl-remove-overlays)))
        (cl-letf (((symbol-function 'fenrir/diff-hl--run-batch)
                   (lambda (prog topdir rels)
                     (setq batch-paths rels)
                     (funcall orig-run prog topdir rels))))
          (let ((default-directory repo))
            (diff-hl-magit-post-refresh)))
        (should (equal batch-paths '("norm.txt")))
        (should (equal (car (gdh-test--overlay-snapshot b-norm)) '((2 3 insert))))
        (should (equal (gdh-test--overlay-snapshot b-ref) stock-ref))
        (should (equal (gdh-test--overlay-snapshot b-nostage) stock-ns))))))

(ert-deftest gdh-symlinked-paths ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (let* ((parent (file-name-as-directory (make-temp-file "gdh-sym-" t)))
         (real-repo (file-name-as-directory (expand-file-name "real" parent)))
         (link-repo (file-name-as-directory (expand-file-name "link" parent)))
         buf-root-sym buf-file-sym)
    (unwind-protect
        (progn
          (make-directory real-repo t)
          (gdh-test--git real-repo "init" "-q")
          (gdh-test--git real-repo "config" "user.name" "Test")
          (gdh-test--git real-repo "config" "user.email" "test@example.com")
          (gdh-test--write real-repo "sub/a.txt" "one\ntwo\n")
          (gdh-test--write real-repo "ext-target.txt" "target\n")
          (gdh-test--write real-repo "other-target.txt" "other\n")
          (make-symbolic-link "ext-target.txt" (expand-file-name "symfile.txt" real-repo))
          (gdh-test--git real-repo "add" "-A")
          (gdh-test--git real-repo "commit" "-q" "-m" "init")
          (make-symbolic-link (directory-file-name real-repo) (directory-file-name link-repo))

          ;; Edit sub/a.txt and update symfile.txt symlink target
          (gdh-test--write real-repo "sub/a.txt" "one\ntwo\nthree\n")
          (delete-file (expand-file-name "symfile.txt" real-repo))
          (make-symbolic-link "other-target.txt" (expand-file-name "symfile.txt" real-repo))

          ;; Visit via symlinked repo root!
          (let ((find-file-visit-truename nil)
                (vc-follow-symlinks nil))
            (setq buf-root-sym (find-file-noselect (expand-file-name "sub/a.txt" link-repo)))
            (setq buf-file-sym (find-file-noselect (expand-file-name "symfile.txt" real-repo))))
          (dolist (b (list buf-root-sym buf-file-sym))
            (with-current-buffer b
              (diff-hl-mode 1)
              (diff-hl-margin-local-mode 1)))
          (gdh-test--assert-parity real-repo (list buf-root-sym buf-file-sym)))
      (dolist (b (list buf-root-sym buf-file-sym))
        (when (buffer-live-p b)
          (with-current-buffer b (set-buffer-modified-p nil))
          (kill-buffer b)))
      (delete-directory parent t))))

(ert-deftest gdh-vc-state-flydiff-tick-and-autohide ()
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "state-tick-autohide"
    (gdh-test--write repo "a.txt" "one\ntwo\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "init")
    (let* ((buf (gdh-test--open repo "a.txt"))
           (file (buffer-file-name buf))
           (diff-hl-autohide-margin t))
      ;; 1. Clean initially -> up-to-date
      (let ((default-directory repo))
        (diff-hl-magit-post-refresh))
      (should (eq (vc-file-getprop file 'vc-state) 'up-to-date))

      ;; 2. Modify on disk, revert buffer, refresh -> edited & flydiff tick synced
      (gdh-test--write repo "a.txt" "one\ntwo\nthree\n")
      (with-current-buffer buf
        (revert-buffer t t t))
      (let ((default-directory repo))
        (diff-hl-magit-post-refresh))
      (should (eq (vc-file-getprop file 'vc-state) 'edited))
      (with-current-buffer buf
        (should (= diff-hl-flydiff-modified-tick (buffer-chars-modified-tick)))
        ;; Calling diff-hl-flydiff-update now must spawn 0 processes.
        (let ((flydiff-calls 0))
          (cl-letf (((symbol-function 'diff-hl-update)
                     (lambda (&rest _) (cl-incf flydiff-calls))))
            (diff-hl-flydiff-update))
          (should (= flydiff-calls 0))))

      ;; 3. Revert file on disk & buffer, refresh -> up-to-date & autohide margin
      (gdh-test--write repo "a.txt" "one\ntwo\n")
      (with-current-buffer buf
        (revert-buffer t t t)
        (setq left-margin-width 1))
      (let ((default-directory repo))
        (diff-hl-magit-post-refresh))
      (should (eq (vc-file-getprop file 'vc-state) 'up-to-date))
      (with-current-buffer buf
        (should (memq left-margin-width '(nil 0)))))))

(ert-deftest gdh-fallback-nonexec-nonzero-nonv1-and-partial ()
  "Fallback covers non-executable binary, non-zero exit, invalid header, and omitted files."
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "fallbacks"
    (gdh-test--write repo "a.txt" "1\n2\n")
    (gdh-test--write repo "b.txt" "x\ny\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "init")
    (gdh-test--write repo "a.txt" "1\n2\n3\n")
    (gdh-test--write repo "b.txt" "x\nY\n")
    (let ((ba (gdh-test--open repo "a.txt"))
          (bb (gdh-test--open repo "b.txt"))
          (nonexec (make-temp-file "gdh-nonexec-")))
      (unwind-protect
          (progn
            ;; 1. Non-executable program file falls back to stock vc-git
            (set-file-modes nonexec #o644)
            (dolist (b (list ba bb))
              (with-current-buffer b (diff-hl-remove-overlays)))
            (let ((fenrir/git-diff-hl-program nonexec)
                  (default-directory repo))
              (diff-hl-magit-post-refresh))
            (should (equal (car (gdh-test--overlay-snapshot ba)) '((3 4 insert))))
            (should (equal (car (gdh-test--overlay-snapshot bb)) '((2 3 change))))

            ;; 2. Non-zero exit code invokes orig-fn
            (let ((orig-called nil))
              (cl-letf (((symbol-function 'call-process-region)
                         (lambda (start end _prog delete _dest _disp &rest _args)
                           (when delete (delete-region start end))
                           2)))
                (let ((default-directory repo))
                  (fenrir/diff-hl-magit-post-refresh (lambda () (setq orig-called t)))))
              (should orig-called))

            ;; 3. Non-v1 header invokes orig-fn
            (let ((orig-called nil))
              (cl-letf (((symbol-function 'call-process-region)
                         (lambda (start end _prog delete _disp2 _disp3 &rest _args)
                           (when delete (delete-region start end))
                           (insert "# git-diff-hl v99\nF\tedited\ta.txt\n")
                           0)))
                (let ((default-directory repo))
                  (fenrir/diff-hl-magit-post-refresh (lambda () (setq orig-called t)))))
              (should orig-called))

            ;; 4. Partial output (b.txt omitted) falls back per-buffer for b.txt only
            (with-current-buffer bb (diff-hl-remove-overlays))
            (let ((orig-called nil))
              (cl-letf (((symbol-function 'call-process-region)
                         (lambda (start end _prog delete _dest _disp &rest _args)
                           (when delete (delete-region start end))
                           (insert "# git-diff-hl v1\nF\tedited\ta.txt\nH\t3\t1\t0\tinsert\n")
                           0)))
                (let ((default-directory repo))
                  (fenrir/diff-hl-magit-post-refresh (lambda () (setq orig-called t)))))
              (should-not orig-called)
              (should (equal (car (gdh-test--overlay-snapshot bb)) '((2 3 change))))))
        (ignore-errors (delete-file nonexec))))))

(ert-deftest gdh-parity-rename-chmod-and-mixed-amend-batch ()
  "Parity for `git mv', `chmod +x', and mixed `diff-hl-amend-mode' + normal batch."
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "mv-chmod-amend"
    (gdh-test--write repo "old.txt" "l1\nl2\n")
    (gdh-test--write repo "run.sh" "echo hi\n")
    (gdh-test--write repo "amend.txt" "v1\n")
    (gdh-test--git repo "add" "-A")
    (gdh-test--git repo "commit" "-q" "-m" "c1")
    (gdh-test--write repo "amend.txt" "v2\n")
    (gdh-test--git repo "commit" "-q" "-am" "c2")

    (gdh-test--git repo "mv" "old.txt" "new.txt")
    (set-file-modes (expand-file-name "run.sh" repo) #o755)
    (let ((b-new (gdh-test--open repo "new.txt"))
          (b-run (gdh-test--open repo "run.sh"))
          (b-amend (gdh-test--open repo "amend.txt"))
          (batch-paths nil))
      (gdh-test--assert-parity repo (list b-new b-run))
      (with-current-buffer b-amend
        (diff-hl-flydiff-mode -1)
        (diff-hl-amend-mode 1))
      (unwind-protect
          (let ((orig-run (symbol-function 'fenrir/diff-hl--run-batch)))
            (dolist (b (list b-new b-run b-amend))
              (with-current-buffer b (diff-hl-remove-overlays)))
            (cl-letf (((symbol-function 'fenrir/diff-hl--run-batch)
                       (lambda (prog topdir rels)
                         (setq batch-paths rels)
                         (funcall orig-run prog topdir rels))))
              (let ((default-directory repo))
                (diff-hl-magit-post-refresh)))
            (should (member "new.txt" batch-paths))
            (should (member "run.sh" batch-paths))
            (should-not (member "amend.txt" batch-paths))
            (should (equal (car (gdh-test--overlay-snapshot b-amend)) '((1 2 change)))))
        (with-current-buffer b-amend
          (diff-hl-amend-mode -1)
          (diff-hl-flydiff-mode 1))))))

(ert-deftest gdh-filename-with-newline-does-not-inject-hunks ()
  "A filename containing a newline must not inject F/H porcelain records into another buffer."
  (skip-unless (file-executable-p fenrir/git-diff-hl-program))
  (gdh-test--with-repo repo "nl-path"
    (let ((bad-name "foo\nH\t1\t9\t0\tinsert")
          (clean-name "foo"))
      (gdh-test--write repo clean-name "clean\n")
      (gdh-test--write repo bad-name "dirty\n")
      (gdh-test--git repo "add" "-A")
      (gdh-test--git repo "commit" "-q" "-m" "init")
      (gdh-test--write repo bad-name "dirty\nmore\n")
      (let ((b-clean (gdh-test--open repo clean-name))
            (b-bad (gdh-test--open repo bad-name)))
        (let ((default-directory repo))
          (diff-hl-magit-post-refresh))
        (should (eq (vc-file-getprop (buffer-file-name b-clean) 'vc-state) 'up-to-date))
        (should (null (car (gdh-test--overlay-snapshot b-clean))))
        (should (eq (vc-file-getprop (buffer-file-name b-bad) 'vc-state) 'edited))))))

(provide 'git-diff-hl-test)
;;; git-diff-hl-test.el ends here
