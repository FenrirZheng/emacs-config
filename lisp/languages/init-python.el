;;; init-python.el --- Python: python-ts-mode + pyright -*- lexical-binding: t; -*-

;;; Commentary:
;; Python language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter / combobulate
;; infrastructure lives in [`lisp/init-languages.el'](../init-languages.el);
;; this module adds the Python mode hooks, pyright's per-server workspace
;; configuration, the zero-config project-`.venv' detection, and a pure-elisp
;; IDE-style pytest runner on the buffer-local `C-c t' prefix (mirroring Go's
;; `C-c t t' and Java's JUnit `C-c t' -- see the "pytest runner" section below).

;;; Code:

;; Eglot (gopls-style autoload) attaches on `python-ts-mode'.  combobulate adds
;; tree-sitter structural editing.  Both commands are autoloaded from
;; declarations in init-languages.el.  (The gtags xref fallback is global --
;; see [`lisp/init-tags.el'](../init-tags.el) -- no per-mode hook needed.)
(add-hook 'python-ts-mode-hook #'eglot-ensure)
(add-hook 'python-ts-mode-hook #'combobulate-mode)

;; ---------------------------------------------------------------------------
;; Zero-config project-venv detection.
;;
;; pyright (unlike VSCode's Pylance) does NOT auto-discover a project's
;; `.venv/'; it needs VIRTUAL_ENV in its environment to locate the interpreter,
;; else it falls back to the first `python' on PATH (system python) and every
;; project-local import shows "could not be resolved".  The config's general
;; mechanism for supplying VIRTUAL_ENV is envrc/direnv (see init-languages.el)
;; -- but direnv's security model requires a per-project `.envrc' + `direnv
;; allow', so every new project repeats the same setup.  This hook removes that
;; friction for the overwhelmingly common case (a project with a `.venv/' in
;; its root): it walks up from the file, and when it finds a `.venv/bin/python',
;; exports VIRTUAL_ENV + prepends the venv `bin' to PATH/`exec-path'
;; BUFFER-LOCALLY, so the pyright process `eglot-ensure' spawns inherits the
;; right interpreter -- no per-project files at all.
;;
;; It DEFERS to envrc: if VIRTUAL_ENV is already set (an `.envrc' exported it,
;; or the buffer inherited an already-activated venv) the hook no-ops, so envrc
;; stays the single source of truth wherever a project opts into it and the two
;; never fight.  Only `.venv' is probed (the uv / `python -m venv .venv'
;; convention); a project using a differently-named venv still uses `.envrc'.
(defun fenrir/python-activate-project-venv ()
  "Buffer-locally point Eglot's pyright at a project-local `.venv'.
No-op unless in a Python buffer visiting a file whose tree contains a
`.venv/bin/python', and only when VIRTUAL_ENV is not already set (envrc/direnv
already resolved it)."
  (when (and (derived-mode-p 'python-base-mode)
             buffer-file-name
             (not (getenv-internal "VIRTUAL_ENV")))
    (when-let* ((dir  (locate-dominating-file buffer-file-name ".venv"))
                (venv (expand-file-name ".venv" dir))
                (bin  (expand-file-name "bin" venv))
                ((file-executable-p (expand-file-name "python" bin))))
      ;; Set all three PATH surfaces (exec-path, the PATH env string, and
      ;; process-environment) and keep them buffer-local so other buffers and
      ;; projects are unaffected.
      (make-local-variable 'process-environment)
      (setq process-environment (copy-sequence process-environment))
      (setenv "VIRTUAL_ENV" venv)
      (setenv "PATH" (concat bin path-separator (getenv "PATH")))
      (make-local-variable 'exec-path)
      (setq exec-path (cons bin exec-path))
      (setq-local python-shell-virtualenv-root venv))))

;; Registered on `after-change-major-mode-hook' -- the SAME hook envrc's
;; globalized enabler (`envrc-global-mode-enable-in-buffer') runs on -- but at a
;; deeper depth (90) so it fires AFTER envrc.  That ordering is load-bearing: on
;; a directory with no `.envrc', envrc's `envrc--clear' does
;; `(kill-local-variable 'process-environment)' / `exec-path', reverting to the
;; global default; a mode-hook registration would set VIRTUAL_ENV only to have
;; envrc wipe it a moment later.  Running after envrc, and no-opping when
;; VIRTUAL_ENV is already set, means envrc wins wherever an `.envrc' opts in and
;; we fill the gap everywhere else.  Eglot connects deferred (post-command-hook),
;; so the env is in place before pyright launches.
(add-hook 'after-change-major-mode-hook #'fenrir/python-activate-project-venv 90)

;; pyright / basedpyright: workspace-wide diagnostics (default "openFilesOnly"
;; silently misses cross-file regressions) plus type-checking on "basic" --
;; catches the obvious wrongs without the false-positive flood of "strict".
;; Bump to "strict" via `.dir-locals.el' for codebases that warrant it.
(with-eval-after-load 'eglot
  (setf (alist-get :python eglot-workspace-configuration)
        '(:analysis (:typeCheckingMode "basic"
                     :diagnosticMode "workspace"
                     :autoImportCompletions t
                     :inlayHints (:variableTypes t
                                  :functionReturnTypes t
                                  :callArgumentNames t)))))

;; ---------------------------------------------------------------------------
;; IDE-style pytest runner -- "run the test at point / in this file / project /
;; last-failed", the Python analogue of Go's `C-c t t' (init-go.el) and Java's
;; `C-c t' JUnit prefix (junit-runner.el).  PURE ELISP by deliberate choice: the
;; enclosing-test discovery parses the ONE already-open buffer via built-in
;; `treesit' -- sub-millisecond, so the "perf -> Rust/C++" argument (which is
;; about project-wide *collection*, already covered better by `pytest
;; --collect-only') does not apply here, and this path adds zero build step on a
;; fresh clone.  Everything runs through `compile' for compilation-mode error
;; navigation + `recompile' (`g' in the `*pytest*' buffer).
;;
;; nodeid mapping (how pytest addresses a single test) that discovery produces:
;;   top-level `def test_x'        -> FILE::test_x
;;   method in `class TestX'       -> FILE::TestX::test_x
;;   nested `class A: class B:'    -> FILE::A::B::test_x   (every enclosing class)
;;   `async def test_x'            -> FILE::test_x         (async is transparent:
;;                                     tree-sitter still tags it `function_definition')
;; The FUNCTION is keyed on a `test' prefix (pytest's `python_functions' default
;; is `test*'); EVERY enclosing `class_definition' is prepended to the structural
;; path -- pytest's `python_classes' = `Test*' filter is a *collection* concern,
;; not a nodeid-*shape* concern, so the addressed nodeid is always structurally
;; exact and `--collect-only' will show 0 for a cursor in a non-collected class.

(defun fenrir/python--venv-program (name)
  "Return executable NAME from a project-local `.venv/bin', or nil.
Reuses the same `.venv' walk-up as `fenrir/python-activate-project-venv' (the
pyright venv detector) so the test runner and the language server agree on the
interpreter -- never a hardcoded path."
  (when-let* ((file (buffer-file-name))
              (dir  (locate-dominating-file file ".venv"))
              (bin  (expand-file-name (concat ".venv/bin/" name) dir))
              ((file-executable-p bin)))
    bin))

(defun fenrir/python-pytest-program ()
  "The pytest invocation for the current buffer, as a list of argv tokens.
Prefers `<project>/.venv/bin/pytest'; else the venv python's `-m pytest'; else
a bare `python -m pytest' on PATH.  A list (not a string) so the caller quotes
each token exactly once."
  (cond
   ((fenrir/python--venv-program "pytest")
    (list (fenrir/python--venv-program "pytest")))
   ((fenrir/python--venv-program "python")
    (list (fenrir/python--venv-program "python") "-m" "pytest"))
   (t (list "python" "-m" "pytest"))))

(defun fenrir/python-pytest-rootdir (file)
  "Best-effort pytest rootdir for FILE: nearest ancestor with a config marker.
Mirrors pytest's own rootdir search order (pyproject.toml / pytest.ini /
tox.ini / setup.cfg / setup.py); falls back to FILE's directory.  `compile'
runs from here so `conftest.py' and `[tool.pytest]' are picked up exactly as a
hand-run pytest would -- and the FILE::... nodeid is rootdir-relative, matching
`pytest --collect-only' output."
  (or (locate-dominating-file
       file
       (lambda (dir)
         (seq-some (lambda (m) (file-exists-p (expand-file-name m dir)))
                   '("pyproject.toml" "pytest.ini" "tox.ini" "setup.cfg" "setup.py"))))
      (file-name-directory file)))

(defun fenrir/python-test-nodeid-at-point ()
  "Return the rootdir-relative pytest nodeid for the test enclosing point, or nil.
Nil when point is not inside a `test'-prefixed function.  Climbs to the NEAREST
enclosing test function (so a cursor in a nested helper still resolves to its
test), then prepends every enclosing class -> FILE::[Class::...]::func."
  (when-let* ((file (buffer-file-name))
              ((treesit-available-p))
              ((treesit-language-at (point))))
    (let ((n (treesit-node-at (point)))
          (func nil))
      ;; nearest enclosing `def'/`async def' whose name starts with `test'.
      ;; `decorated_definition' is matched too so a cursor ON a decorator line
      ;; (`@pytest.mark.parametrize', `@pytest.fixture'-adjacent, etc.) resolves
      ;; to the test it decorates -- the decorator sits OUTSIDE the inner
      ;; `function_definition' node, so without this a decorator cursor would
      ;; miss and fall back to the whole file.
      (while (and n (not func))
        (let ((type (treesit-node-type n)))
          (cond
           ((string= type "function_definition")
            (let ((nm (treesit-node-text
                       (treesit-node-child-by-field-name n "name") t)))
              (when (string-prefix-p "test" nm) (setq func n))))
           ((string= type "decorated_definition")
            (let ((def (treesit-node-child-by-field-name n "definition")))
              (when (and def (string= (treesit-node-type def) "function_definition"))
                (let ((nm (treesit-node-text
                           (treesit-node-child-by-field-name def "name") t)))
                  (when (string-prefix-p "test" nm) (setq func def))))))))
        (setq n (treesit-node-parent n)))
      (when func
        (let ((path (list (treesit-node-text
                           (treesit-node-child-by-field-name func "name") t)))
              (p (treesit-node-parent func)))
          ;; walk outward, pushing each enclosing class to the FRONT so the
          ;; final order is outermost-class ... innermost-class func
          (while p
            (when (string= (treesit-node-type p) "class_definition")
              (push (treesit-node-text
                     (treesit-node-child-by-field-name p "name") t)
                    path))
            (setq p (treesit-node-parent p)))
          (concat (file-relative-name file (fenrir/python-pytest-rootdir file))
                  "::" (mapconcat #'identity path "::")))))))

(defun fenrir/python--require-python ()
  "Guard: signal unless in a file-visiting Python buffer; save if modified.
pytest reads the file from disk, so an unsaved buffer would test stale code
(and a buffer-derived nodeid could then address a test the disk lacks)."
  (unless (derived-mode-p 'python-base-mode)
    (user-error "Not a Python buffer"))
  (unless (buffer-file-name)
    (user-error "Buffer is not visiting a file"))
  (when (buffer-modified-p) (save-buffer)))

(defun fenrir/python--run-pytest (args)
  "Run pytest with ARGS (a list of tokens) from the buffer's rootdir via `compile'.
Each token is `shell-quote-argument'd, so paths with spaces and the `::' nodeid
separator survive the shell.  A dedicated `*pytest*' buffer keeps results off
`M-x compile' and makes `g' re-run the same test."
  (let* ((default-directory
          (file-name-as-directory
           (fenrir/python-pytest-rootdir (buffer-file-name))))
         (cmd (mapconcat #'shell-quote-argument
                         (append (fenrir/python-pytest-program) args)
                         " "))
         (compilation-buffer-name-function (lambda (&rest _) "*pytest*")))
    (compile cmd)))

(defun fenrir/python-test-at-point ()
  "Run the pytest test enclosing point; fall back to the whole file if none.
The friendly default (`C-c t t'): a cursor inside any `test'-prefixed function
runs exactly that nodeid; a cursor on a blank line / import / decorator between
tests runs the whole file instead of guessing a wrong test."
  (interactive)
  (fenrir/python--require-python)
  (if-let* ((nodeid (fenrir/python-test-nodeid-at-point)))
      (progn (message "pytest: %s" nodeid)
             (fenrir/python--run-pytest (list nodeid "-v")))
    (message "No test at point -- running whole file")
    (fenrir/python-test-file)))

(defun fenrir/python-test-file ()
  "Run every pytest test in the current file."
  (interactive)
  (fenrir/python--require-python)
  (let* ((file (buffer-file-name))
         (rel  (file-relative-name file (fenrir/python-pytest-rootdir file))))
    (message "pytest: %s" rel)
    (fenrir/python--run-pytest (list rel "-v"))))

(defun fenrir/python-test-project ()
  "Run the whole pytest suite from the project rootdir (`testpaths')."
  (interactive)
  (fenrir/python--require-python)
  (message "pytest: whole project")
  (fenrir/python--run-pytest (list "-v")))

(defun fenrir/python-test-last-failed ()
  "Re-run only the tests that failed on the last pytest run (`--lf')."
  (interactive)
  (fenrir/python--require-python)
  (message "pytest: last-failed")
  (fenrir/python--run-pytest (list "--lf" "-v")))

;; Buffer-local `C-c t' prefix, bound in `python-base-mode-map' (the shared
;; parent of `python-mode-map' and `python-ts-mode-map', so one bind covers
;; both).  Like Go/Java, `C-c t' becomes a test prefix INSIDE Python buffers
;; only -- it shadows vterm's global `C-c t' there and nowhere else.  These do
;; NOT collide with Eglot's `C-c .'/`r'/`f'/`h' or combobulate's `C-c o'.
(with-eval-after-load 'python
  (define-key python-base-mode-map (kbd "C-c t t") #'fenrir/python-test-at-point)
  (define-key python-base-mode-map (kbd "C-c t f") #'fenrir/python-test-file)
  (define-key python-base-mode-map (kbd "C-c t a") #'fenrir/python-test-project)
  (define-key python-base-mode-map (kbd "C-c t l") #'fenrir/python-test-last-failed))

(provide 'init-python)
;;; init-python.el ends here
