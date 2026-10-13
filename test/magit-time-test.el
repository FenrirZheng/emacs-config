;;; magit-time-test.el --- ERT for the commit time beside Magit hashes, lisp/init-git.el -*- lexical-binding: t; -*-

;; TZ=Asia/Taipei emacs -Q --batch -l test/magit-time-test.el -f ert-run-tests-batch-and-exit
;;
;; Unlike the other suites this one needs Magit, so it activates the packages in
;; elpa/ and loads the real init-git.  Each test rebuilds the throwaway fixture
;; repo /tmp/magit-time-fixture with the spec's make-fixture.sh.
;; Spec: sliced-spec/2026-10-13/213125-magit-hash-commit-time/SPEC.md

(require 'ert)
(defconst magit-time-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(setq package-user-dir (expand-file-name "elpa" magit-time-test--root))
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" magit-time-test--root))
(require 'init-git)
(require 'magit)

(defconst magit-time-test--fixture "/tmp/magit-time-fixture/")
(defconst magit-time-test--script
  (expand-file-name
   "sliced-spec/2026-10-13/213125-magit-hash-commit-time/make-fixture.sh"
   magit-time-test--root))

(defun magit-time-test--status ()
  "Rebuild the fixture and return a fresh Magit status buffer for it."
  (let ((buf (get-buffer "magit: magit-time-fixture")))
    (when buf (kill-buffer buf)))
  (unless (zerop (call-process "bash" nil nil nil magit-time-test--script
                               (directory-file-name magit-time-test--fixture)))
    (error "make-fixture.sh failed"))
  (let ((default-directory magit-time-test--fixture))
    (magit-status-setup-buffer magit-time-test--fixture)))

(defun magit-time-test--commit-lines ()
  "Return (HASH LINE MARGIN) for each commit line in the current status buffer.
MARGIN is the right-margin text Magit put on that line, or nil."
  (let (out)
    (magit-map-sections
     (lambda (section)
       (when (magit-section-match 'commit section)
         (save-excursion
           (goto-char (oref section start))
           (let* ((bol (line-beginning-position)) (eol (line-end-position))
                  (margin
                   (seq-some
                    (lambda (o)
                      (let* ((s (overlay-get o 'before-string))
                             (d (and s (get-text-property 0 'display s))))
                        (and (equal (car-safe d) '(margin right-margin))
                             (substring-no-properties (cadr d)))))
                    (overlays-in bol (1+ eol)))))
             (push (list (oref section value)
                         (buffer-substring-no-properties bol eol)
                         margin)
                   out))))))
    (nreverse out)))

(defun magit-time-test--status-command (keys)
  "Return the command KEYS run in a status buffer, following one transient level."
  (let* ((prefix (lookup-key magit-status-mode-map (substring keys 0 1)))
         (suffix (transient-get-suffix prefix (substring keys 1))))
    (list prefix (plist-get (cdr suffix) :command))))

(ert-deftest status-committer-time ()
  ;; 驗收條件 1: hash and committer time on the same line; author date nowhere
  (with-current-buffer (magit-time-test--status)
    (let ((lines (magit-time-test--commit-lines)))
      (should (= (length lines) 2))
      (dolist (l lines)
        (pcase-let ((`(,hash ,text ,margin) l))
          (should (string-prefix-p hash text))
          (should (equal margin "2026-02-03 04:05"))
          (should-not (string-search "2026-01-02" text))
          (should-not (string-search "2026-01-02" margin)))))))

(ert-deftest status-margin-width ()
  ;; 驗收條件 3: the time column is at most 17 columns
  (with-current-buffer (magit-time-test--status)
    (should (<= (nth 2 magit--right-margin-config) 17))
    (dolist (l (magit-time-test--commit-lines))
      (should (<= (string-width (nth 2 l)) 17)))))

(ert-deftest margin-toggle ()
  ;; 驗收條件 4: `L L' hides the times, `L L' again shows them
  (should (equal (magit-time-test--status-command "LL")
                 '(magit-log-refresh magit-toggle-margin)))
  (with-current-buffer (magit-time-test--status)
    ;; Hiding keeps the margin overlays but shrinks the window's right margin
    ;; to nothing, so the times are measured where they render: the window.
    (let ((win (get-buffer-window (current-buffer))))
      (should win)
      (should (equal (cdr (window-margins win)) 16))
      (magit-toggle-margin)
      (should-not (magit--right-margin-active))
      (should (memq (cdr (window-margins win)) '(nil 0)))
      (magit-toggle-margin)
      (should (magit--right-margin-active))
      (should (equal (cdr (window-margins win)) 16))
      (should (equal (mapcar #'caddr (magit-time-test--commit-lines))
                     '("2026-02-03 04:05" "2026-02-03 04:05"))))))

;;; magit-time-test.el ends here
