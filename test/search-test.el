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

;; --- prompt keymap -----------------------------------------------------------------

(ert-deftest search-prompt-keys ()
  (should (eq (keymap-lookup fenrir/search-prompt-mode-map "C-t") #'fenrir/search-prompt-files))
  (should (eq (keymap-lookup fenrir/search-prompt-mode-map "C-z") #'fenrir/search-prompt-text))
  (should (eq (keymap-lookup fenrir/search-prompt-mode-map "C-x C-d")
              #'fenrir/search-prompt-pick-dir)))

;;; search-test.el ends here
