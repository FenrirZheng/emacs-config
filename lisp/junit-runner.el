;;; junit-runner.el --- Run JUnit tests via the junit-core C++ module -*- lexical-binding: t; -*-

;; Author: fenrir
;; Keywords: java, tools, tests

;;; Commentary:
;;
;; Thin elisp front-end over the `junit-core' Emacs dynamic module (built from
;; the cpp/ workspace, see cpp/junit-core/src/junit-core.cpp).  The C++ side
;; does the tree-sitter Java parsing and figures out the build tool + exact
;; shell command; this side loads the module on demand and runs that command
;; through `compile' so the user gets compilation-mode error navigation and
;; `recompile'.
;;
;; Entry points (typically bound under `C-c t' in java(-ts)-mode, wired in
;; lisp/languages/init-java.el):
;;
;;   `junit-run-method-at-point'  -- run the @Test method enclosing point
;;   `junit-run-file'             -- run every test in the current file
;;   `junit-run-dwim'             -- method at point if it is a test, else file
;;
;; The module reads the file *from disk*, so a modified buffer is saved first
;; (mvn/gradle would read the on-disk copy anyway).
;;
;; Build the module once with `M-x junit-runner-build' (or cpp/build.sh); a
;; fresh clone falls back to a helpful error until then.  See cpp/README.md.

;;; Code:

(require 'compile)
(require 'subr-x)

(defgroup junit-runner nil
  "Run JUnit tests for the current Java buffer via the junit-core module."
  :group 'tools
  :prefix "junit-runner-")

(defcustom junit-runner-module
  (expand-file-name "cpp/lib/junit-core.so" user-emacs-directory)
  "Absolute path to the built junit-core dynamic module.
Produced by cpp/build.sh into the workspace-wide cpp/lib/ directory."
  :type 'file)

(defcustom junit-runner-save-before-run t
  "When non-nil, save a modified buffer before running its tests.
The module parses the file from disk and the build tool compiles the
on-disk copy, so an unsaved buffer would otherwise test stale code."
  :type 'boolean)

;; ---------------------------------------------------------------------------
;; Module loading / building
;; ---------------------------------------------------------------------------

(defun junit-runner--loaded-p ()
  "Non-nil when the junit-core module functions are available."
  (and (fboundp 'junit-core-command)
       (fboundp 'junit-core-method-at-line)
       (fboundp 'junit-core-class-info)))

(defun junit-runner--ensure-module ()
  "Load the junit-core module, signalling an actionable error if it is missing."
  (unless (junit-runner--loaded-p)
    (unless (and module-file-suffix (file-exists-p junit-runner-module))
      (user-error
       "junit-core module not built: %s -- run M-x junit-runner-build (or cpp/build.sh)"
       junit-runner-module))
    (module-load junit-runner-module)
    (unless (junit-runner--loaded-p)
      (error "Loaded %s but junit-core functions are missing" junit-runner-module))))

(defun junit-runner-build ()
  "Build the junit-core module by running cpp/build.sh, then load it.
Compilation runs in a `compilation-mode' buffer; load happens on success."
  (interactive)
  (let* ((script (expand-file-name "cpp/build.sh" user-emacs-directory))
         (default-directory (file-name-directory script)))
    (unless (file-exists-p script)
      (user-error "Build script not found: %s" script))
    (let ((buf (compilation-start (concat (shell-quote-argument script))
                                  nil
                                  (lambda (&rest _) "*junit-core build*"))))
      (with-current-buffer buf
        (add-hook 'compilation-finish-functions
                  #'junit-runner--after-build nil t)))))

(defun junit-runner--after-build (buffer status)
  "Load the freshly built module when BUFFER's build STATUS is success."
  (when (and (buffer-live-p buffer)
             (string-prefix-p "finished" status)
             (file-exists-p junit-runner-module))
    ;; module-load refuses to load the same file twice in one session; only
    ;; load if not already present.
    (unless (junit-runner--loaded-p)
      (condition-case err
          (progn (module-load junit-runner-module)
                 (message "junit-core module loaded"))
        (error (message "junit-core built but load failed: %s"
                        (error-message-string err)))))))

;; ---------------------------------------------------------------------------
;; Running
;; ---------------------------------------------------------------------------

(defun junit-runner--this-file ()
  "Return the saved file name of the current buffer, or signal an error."
  (let ((file (buffer-file-name)))
    (unless file (user-error "Buffer is not visiting a file"))
    (unless (string-suffix-p ".java" file)
      (user-error "Not a .java file: %s" (file-name-nondirectory file)))
    (when (and junit-runner-save-before-run (buffer-modified-p))
      (save-buffer))
    file))

(defun junit-runner--run (info)
  "Run the test described by INFO (a plist from `junit-core-command')."
  (let ((default-directory (file-name-as-directory (plist-get info :directory)))
        (command (plist-get info :command)))
    (message "%s" (plist-get info :description))
    ;; A dedicated buffer name keeps test output from clobbering ordinary
    ;; `M-x compile' results, and makes `g' (recompile) re-run the same test.
    (let ((compilation-buffer-name-function
           (lambda (&rest _) "*junit*")))
      (compile command))))

;;;###autoload
(defun junit-run-method-at-point ()
  "Run the JUnit test method enclosing point in the current Java buffer."
  (interactive)
  (junit-runner--ensure-module)
  (let* ((file (junit-runner--this-file))
         (line (line-number-at-pos (point) t))
         (info (junit-core-command file line)))
    (if info
        (junit-runner--run info)
      ;; Distinguish "not a test method" from "no build tool" for the user.
      (let ((m (junit-core-method-at-line file line)))
        (cond
         ((null m)
          (user-error "No method at line %d" line))
         ((not (plist-get m :test))
          (user-error "%s is not a JUnit test method" (plist-get m :method)))
         (t
          (user-error "No Maven/Gradle build tool found above %s"
                      (file-name-nondirectory file))))))))

;;;###autoload
(defun junit-run-file ()
  "Run all JUnit tests in the current Java file."
  (interactive)
  (junit-runner--ensure-module)
  (let* ((file (junit-runner--this-file))
         (info (junit-core-command file nil)))
    (if info
        (junit-runner--run info)
      (let ((ci (junit-core-class-info file)))
        (cond
         ((not (plist-get ci :is-test-file))
          (user-error "%s does not look like a JUnit test file"
                      (file-name-nondirectory file)))
         ((not (plist-get ci :tool))
          (user-error "No Maven/Gradle build tool found above %s"
                      (file-name-nondirectory file)))
         (t (user-error "Could not build a test command for %s"
                        (file-name-nondirectory file))))))))

;;;###autoload
(defun junit-run-dwim ()
  "Run the test method at point if it is a JUnit test, else the whole file."
  (interactive)
  (junit-runner--ensure-module)
  (let* ((file (junit-runner--this-file))
         (line (line-number-at-pos (point) t))
         (m (junit-core-method-at-line file line)))
    (if (and m (plist-get m :test))
        (junit-run-method-at-point)
      (junit-run-file))))

(provide 'junit-runner)
;;; junit-runner.el ends here
