;;; fenrir-python-root.el --- engine: pick pyright's workspace root -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Eglot hands pyright the project.el root as its workspace, and pyright
;; registers a `**' file watcher on it.  In a repo whose root is not a Python
;; project -- `~/code/ig_lottery_hotfix' keeps loose scripts in `scripts/' next
;; to `repos/' (1.4 GB, ~7.6k dirs) -- that blew past `eglot-max-file-watches',
;; pyright exited 1 about 4 s after starting, and since that is just over
;; `eglot-autoreconnect''s 3 s threshold Eglot restarted it forever, pinning the
;; daemon at 70-110% CPU (2026-10-22).
;;
;; `fenrir/python--lsp-root' picks a narrower root, without writing any file:
;;
;;   Tier 1  the nearest ancestor of the file, up to and including VC-ROOT,
;;           holding a Python marker (`fenrir/python-root-markers').  `.project'
;;           is in the list, so dropping one by hand still overrides everything.
;;   Tier 2  no marker anywhere in the repo: the first-level subdirectory of
;;           VC-ROOT holding the file (`scripts/hooks/x.py' -> `scripts/'), so
;;           sibling scripts share one server.  A file directly in VC-ROOT gets
;;           VC-ROOT.
;;
;; Known costs of Tier 2:
;;   - A markerless repo laid out as `src/' + `tests/' gives `tests/' its own
;;     root, and `import pkg' there silently fails to resolve.  Fix: put a
;;     marker (`pyrightconfig.json', `.project', ...) at the repo root.
;;   - A `.py' directly in a big markerless VC-ROOT still gets VC-ROOT, so the
;;     runaway watch loop can come back for root-level files.
;;
;; This file is pure (no Eglot, no project.el) so `test/python-root-test.el'
;; can load it under `emacs -Q'.  The `project-find-functions' wiring, gated on
;; `eglot-lsp-context' so `C-x p' keeps the ordinary project root, lives in
;; [`init-python.el'](init-python.el).

;;; Code:

(require 'seq)

(defvar fenrir/python-root-markers
  '("pyrightconfig.json" "pyproject.toml" "setup.py" "setup.cfg"
    "requirements.txt" "Pipfile" "tox.ini" "conftest.py" ".venv" ".project")
  "Files or directories that mark a directory as a Python LSP root.")

(defun fenrir/python--lsp-root (dir vc-root)
  "Return the directory pyright should use as its root for a file in DIR.
VC-ROOT is the enclosing project.el VC root; when it is nil, return nil so the
caller defers.  See the Commentary for the two tiers."
  (when vc-root
    (let* ((root (file-name-as-directory (expand-file-name vc-root)))
           (cur  (file-name-as-directory (expand-file-name dir)))
           (found nil))
      (when (string-prefix-p root cur)
        ;; Tier 1: walk up from DIR, stopping at VC-ROOT inclusive.
        (while (and (not found) cur)
          (when (seq-some (lambda (m) (file-exists-p (expand-file-name m cur)))
                          fenrir/python-root-markers)
            (setq found cur))
          (setq cur (and (not (string-equal cur root))
                         (file-name-directory (directory-file-name cur)))))
        (or found
            ;; Tier 2: first path component below VC-ROOT, if any.
            (let ((rel (file-relative-name (expand-file-name dir) root)))
              (if (or (string-equal rel ".") (string-equal rel "./"))
                  root
                (file-name-as-directory
                 (expand-file-name (car (split-string rel "/" t)) root)))))))))

(provide 'fenrir-python-root)
;;; fenrir-python-root.el ends here
