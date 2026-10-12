;;; search-test.el --- ERT for the one-search WHERE/WHAT helpers, lisp/fenrir-search.el -*- lexical-binding: t; -*-

;; emacs -Q --batch -l test/search-test.el -f ert-run-tests-batch-and-exit
;;
;; Loads only fenrir-search (no package system, no consult): the pure scope /
;; kind helpers, plus the prompt keymap shape.

(require 'ert)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory
                                          (or load-file-name buffer-file-name))))
(require 'fenrir-search)

;; --- WHERE cycle -----------------------------------------------------------------

(ert-deftest search-scopes-project ()
  ;; root first, then the current folder, then its parents up to /, root once
  (should (equal (fenrir/search--scopes "/p/repo/" "/p/repo/src/a/")
                 '("/p/repo/" "/p/repo/src/a/" "/p/repo/src/" "/p/" "/"))))

(ert-deftest search-scopes-normalizes ()
  ;; missing trailing slashes are added
  (should (equal (fenrir/search--scopes "/p/repo" "/p/repo/src")
                 '("/p/repo/" "/p/repo/src/" "/p/" "/"))))

(ert-deftest search-scopes-no-project ()
  ;; no project: root = current folder, so the cycle starts there
  (should (equal (fenrir/search--scopes "/tmp/x/" "/tmp/x/")
                 '("/tmp/x/" "/tmp/" "/"))))

(ert-deftest search-next-scope-cycle ()
  (let ((root "/p/repo/") (origin "/p/repo/src/"))
    (should (equal (fenrir/search--next-scope "/p/repo/" root origin) "/p/repo/src/"))
    (should (equal (fenrir/search--next-scope "/p/repo/src/" root origin) "/p/"))
    (should (equal (fenrir/search--next-scope "/p/" root origin) "/"))))

(ert-deftest search-next-scope-wraps-at-root-dir ()
  (should (equal (fenrir/search--next-scope "/" "/p/repo/" "/p/repo/src/") "/p/repo/")))

(ert-deftest search-next-scope-off-cycle ()
  ;; a folder picked with consult-dir climbs to its parent, then wraps at /
  (should (equal (fenrir/search--next-scope "/home/u/code/" "/p/repo/" "/p/repo/")
                 "/home/u/"))
  (should (equal (fenrir/search--next-scope "/home/u/code" "/p/repo/" "/p/repo/")
                 "/home/u/")))

(ert-deftest search-parent ()
  (should (equal (fenrir/search--parent "/a/b/") "/a/"))
  (should (equal (fenrir/search--parent "/a") "/"))
  (should-not (fenrir/search--parent "/")))

;; --- WHAT toggle -----------------------------------------------------------------

(ert-deftest search-next-state-same-key-moves-where ()
  (should (equal (fenrir/search--next-state 'files 'files "/p/repo/" "/p/repo/" "/p/repo/src/")
                 '(files . "/p/repo/src/")))
  (should (equal (fenrir/search--next-state 'text 'text "/p/repo/src/" "/p/repo/" "/p/repo/src/")
                 '(text . "/p/"))))

(ert-deftest search-next-state-other-key-switches-what ()
  ;; same folder, other kind
  (should (equal (fenrir/search--next-state 'text 'files "/p/repo/src" "/p/repo/" "/p/repo/src/")
                 '(text . "/p/repo/src/")))
  (should (equal (fenrir/search--next-state 'files 'text "/p/" "/p/repo/" "/p/repo/src/")
                 '(files . "/p/"))))

;; --- no-project root ---------------------------------------------------------------

(ert-deftest search-root-without-project ()
  (let ((dir (file-name-as-directory (make-temp-file "search-test" t))))
    (unwind-protect
        (should (equal (fenrir/search--root dir) dir))
      (delete-directory dir t))))

;; --- C-x C-d result handling -------------------------------------------------------

(ert-deftest search-picked-dir-typed-existing-dir ()
  ;; typed input that matches no candidate: accepted when it is a folder
  (let ((dir (file-name-as-directory (make-temp-file "search-test" t))))
    (unwind-protect
        (progn
          (should (equal (fenrir/search--picked-dir
                          dir '(:match nil :category bookmark) #'ignore)
                         dir))
          ;; no trailing slash, and the bookmark resolver is never consulted
          (should (equal (fenrir/search--picked-dir
                          (directory-file-name dir) '(:match nil :category bookmark)
                          (lambda (_) (error "bookmark resolver called")))
                         dir)))
      (delete-directory dir t))))

(ert-deftest search-picked-dir-typed-tilde ()
  (should (equal (fenrir/search--picked-dir "~/" '(:match nil :category bookmark) #'ignore)
                 (file-name-as-directory (expand-file-name "~")))))

(ert-deftest search-picked-dir-typed-missing ()
  ;; not a folder -> nil, so the command reports it instead of erroring
  (should-not (fenrir/search--picked-dir "/no/such/dir-xyz/" '(:match nil :category bookmark)
                                         #'ignore))
  (should-not (fenrir/search--picked-dir (or load-file-name "/etc/hostname")
                                         '(:match nil :category file) #'ignore)))

(ert-deftest search-picked-dir-listed-candidates ()
  ;; listed candidates resolve by category, as consult-dir--pick does
  (should (equal (fenrir/search--picked-dir "~/proj/" '(:category file) #'ignore) "~/proj/"))
  (should (equal (fenrir/search--picked-dir "work" '(:category bookmark)
                                            (lambda (b) (concat "/bm/" b "/")))
                 "/bm/work/")))

;; --- C-u seed from the symbol at point ------------------------------------------

(defmacro search-test--at (text marker &rest body)
  "Run BODY in an `emacs-lisp-mode' buffer holding TEXT, point after MARKER."
  (declare (indent 2))
  `(with-temp-buffer
     (emacs-lisp-mode)
     (insert ,text)
     (goto-char (point-min))
     (search-forward ,marker)
     ,@body))

(ert-deftest search-seed-dotted-symbol ()
  ;; text seed is regexp-quoted so the dot matches literally; files seed is raw
  (search-test--at "(foo.bar 1)\n" "foo."
    (should (equal (fenrir/search--initial-from-point 'text) "foo\\.bar"))
    (should (equal (fenrir/search--initial-from-point 'files) "foo.bar"))))

(ert-deftest search-seed-plain-symbol ()
  (search-test--at "(defun fenrir/search--run (kind dir))\n" "fenrir/sea"
    (should (equal (fenrir/search--initial-from-point 'text) "fenrir/search--run"))
    (should (equal (fenrir/search--initial-from-point 'files) "fenrir/search--run"))))

(ert-deftest search-seed-empty-line ()
  (search-test--at "(a)\n\n(b)\n" "(a)\n"
    (should-not (fenrir/search--initial-from-point 'text))
    (should-not (fenrir/search--initial-from-point 'files))))

;; --- prompt keymap -----------------------------------------------------------------

(ert-deftest search-prompt-keys ()
  (should (eq (keymap-lookup fenrir/search-prompt-mode-map "C-t") #'fenrir/search-prompt-files))
  (should (eq (keymap-lookup fenrir/search-prompt-mode-map "C-z") #'fenrir/search-prompt-text))
  (should (eq (keymap-lookup fenrir/search-prompt-mode-map "C-x C-d")
              #'fenrir/search-prompt-pick-dir)))

;;; search-test.el ends here
