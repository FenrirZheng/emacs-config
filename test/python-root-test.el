;;; python-root-test.el --- ERT for pyright's root picker, lisp/languages/fenrir-python-root.el -*- lexical-binding: t; -*-

;; emacs -Q --batch -l test/python-root-test.el -f ert-run-tests-batch-and-exit
;;
;; Loads only fenrir-python-root (no package system, no Eglot): the pure
;; `fenrir/python--lsp-root' against throwaway directory trees.

(require 'ert)
(add-to-list 'load-path
             (expand-file-name "../lisp/languages" (file-name-directory
                                                    (or load-file-name buffer-file-name))))
(require 'fenrir-python-root)

(defmacro python-root-test--with-tree (paths &rest body)
  "Create a temp dir bound to `top', make PATHS under it, run BODY, clean up.
A path ending in / is a directory, anything else an empty file."
  (declare (indent 1))
  `(let ((top (file-name-as-directory (make-temp-file "pyroot" t))))
     (unwind-protect
         (progn
           (dolist (p ,paths)
             (let ((full (expand-file-name p top)))
               (if (string-suffix-p "/" p)
                   (make-directory full t)
                 (make-directory (file-name-directory full) t)
                 (write-region "" nil full))))
           ,@body)
       (delete-directory top t))))

(defun python-root-test--rel (top dir)
  (let ((r (fenrir/python--lsp-root (expand-file-name dir top) (expand-file-name "repo" top))))
    (and r (file-relative-name r top))))

(ert-deftest python-root-marker-in-subdir-wins ()
  (python-root-test--with-tree '("repo/svc/pyproject.toml" "repo/svc/pkg/")
    (should (equal (python-root-test--rel top "repo/svc/pkg/") "repo/svc/"))))

(ert-deftest python-root-marker-at-vc-root ()
  ;; an ordinary Python repo keeps its git root
  (python-root-test--with-tree '("repo/pyproject.toml" "repo/src/pkg/")
    (should (equal (python-root-test--rel top "repo/src/pkg/") "repo/"))))

(ert-deftest python-root-no-marker-first-level-subdir ()
  (python-root-test--with-tree '("repo/scripts/hooks/" "repo/repos/big/")
    (should (equal (python-root-test--rel top "repo/scripts/hooks/") "repo/scripts/"))
    (should (equal (python-root-test--rel top "repo/scripts/") "repo/scripts/"))))

(ert-deftest python-root-no-marker-file-in-vc-root ()
  (python-root-test--with-tree '("repo/")
    (should (equal (python-root-test--rel top "repo/") "repo/"))))

(ert-deftest python-root-marker-above-vc-root-ignored ()
  (python-root-test--with-tree '("pyproject.toml" "repo/scripts/")
    (should (equal (python-root-test--rel top "repo/scripts/") "repo/scripts/"))))

(ert-deftest python-root-nil-vc-root-defers ()
  ;; no repo (or the $HOME dotfiles repo, which project-try-vc refuses)
  (python-root-test--with-tree '("pyproject.toml" "x/")
    (should-not (fenrir/python--lsp-root (expand-file-name "x/" top) nil))))

(ert-deftest python-root-venv-dir-is-marker ()
  (python-root-test--with-tree '("repo/app/.venv/bin/" "repo/app/sub/")
    (should (equal (python-root-test--rel top "repo/app/sub/") "repo/app/"))))

(ert-deftest python-root-conftest-not-a-marker ()
  ;; tests/conftest.py must not split tests/ from the pyproject root
  (python-root-test--with-tree '("repo/pyproject.toml" "repo/tests/conftest.py")
    (should (equal (python-root-test--rel top "repo/tests/") "repo/"))))

(ert-deftest python-root-dot-project-is-marker ()
  (python-root-test--with-tree '("repo/scripts/.project" "repo/scripts/hooks/")
    (should (equal (python-root-test--rel top "repo/scripts/hooks/") "repo/scripts/"))))

;;; python-root-test.el ends here
