;;; init-python.el --- Python: python-ts-mode + pyright -*- lexical-binding: t; -*-

;;; Commentary:
;; Python language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter / combobulate / ggtags
;; infrastructure lives in [`lisp/init-languages.el'](../init-languages.el);
;; this module only adds the Python mode hooks and pyright's per-server
;; workspace configuration.

;;; Code:

;; Eglot (gopls-style autoload) attaches on `python-ts-mode'.  combobulate adds
;; tree-sitter structural editing; ggtags is the GTAGS xref backend used only
;; in buffers without a live language server (Eglot, when up, wins xref).  All
;; three commands are autoloaded from declarations in init-languages.el.
(add-hook 'python-ts-mode-hook #'eglot-ensure)
(add-hook 'python-ts-mode-hook #'combobulate-mode)
(add-hook 'python-mode-hook    #'ggtags-mode)
(add-hook 'python-ts-mode-hook #'ggtags-mode)

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

(provide 'init-python)
;;; init-python.el ends here
