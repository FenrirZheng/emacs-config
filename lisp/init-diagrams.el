;;; init-diagrams.el --- Text-to-diagram: PlantUML + Mermaid -*- lexical-binding: t; -*-

;;; Commentary:
;; Author UML / flow / sequence / ER diagrams as plain text and render them to
;; an image in-editor -- the modern "diagrams-as-code" workflow (the in-Emacs
;; twin of VSCode's PlantUML / Mermaid Preview extensions).  Kept standalone so
;; it's easy to drop, like init-docker.
;;
;; Renderers (NOT tracked -- they live outside the repo):
;;   * PlantUML -> a Java jar.  This config points at `var/plantuml/plantuml.jar'
;;     and runs it with the system `java' (sdkman build is on PATH).  `var/' is
;;     gitignored, so a FRESH CLONE must re-fetch the jar once -- either
;;     `M-x plantuml-download-jar', or the same curl used to seed it:
;;       mkdir -p var/plantuml && curl -fsSL \
;;         "$(curl -fsSL https://api.github.com/repos/plantuml/plantuml/releases/latest \
;;           | grep -oE 'https://[^\"]*plantuml-[0-9.]+\\.jar' | head -1)" \
;;         -o var/plantuml/plantuml.jar
;;     Graphviz `dot' (/usr/bin/dot here) is needed for class/state diagrams.
;;   * Mermaid -> the `mmdc' CLI (npm `@mermaid-js/mermaid-cli'); install once:
;;       npm install -g @mermaid-js/mermaid-cli
;;
;; TTY note: PNG output renders only in a GUI frame.  On a pure-TTY frame set
;; `(setq plantuml-output-type "txt")' for ASCII-art preview instead.

;;; Code:

;; plantuml-mode: `.puml' / `.plantuml' major mode; `C-c C-c' renders the diagram
;; and `C-c C-p' previews it.  `jar' exec-mode keeps everything local (no diagram
;; text sent to the public PlantUML server, the alternative `server' mode).
(use-package plantuml-mode
  :mode (("\\.puml\\'"      . plantuml-mode)
         ("\\.plantuml\\'"  . plantuml-mode)
         ("\\.pdiag\\'"     . plantuml-mode))
  :custom
  (plantuml-default-exec-mode 'jar)
  (plantuml-jar-path (no-littering-expand-var-file-name "plantuml/plantuml.jar"))
  (plantuml-output-type "png")           ; GUI; set "txt" for TTY ASCII preview
  :config
  ;; org-babel: let `#+begin_src plantuml :file foo.png' blocks render too,
  ;; reusing the same jar.
  (with-eval-after-load 'ob
    (setq org-plantuml-jar-path plantuml-jar-path)))

;; mermaid-mode: `.mmd' / `.mermaid' major mode driving the `mmdc' CLI.
;; `C-c C-c' compiles the buffer to an image, `C-c C-o' opens it, `C-c C-d c'
;; compiles the region.  `mermaid-mmdc-location' defaults to "mmdc" on PATH
;; (exec-path-from-shell already synced the npm-global bin into the daemon).
(use-package mermaid-mode
  :mode (("\\.mmd\\'"     . mermaid-mode)
         ("\\.mermaid\\'" . mermaid-mode))
  :custom
  (mermaid-output-format ".png"))

;; ob-mermaid: `#+begin_src mermaid :file foo.png' blocks in org, via the same
;; `mmdc' binary.
(use-package ob-mermaid
  :after org
  :custom
  (ob-mermaid-cli-path (or (executable-find "mmdc") "mmdc")))

;; Wire them into org-babel.  No prior `org-babel-load-languages' customisation
;; exists in this config (default is just emacs-lisp), so extend that default.
;; `dot' rides along here rather than in init-org.el because it's a diagram
;; language: ob-dot ships with org (no package), needs only the system
;; Graphviz binary this file already depends on for PlantUML class/state
;; diagrams -- and the graph-context plan format (~/.claude/plans/
;; graph-context-template.org) renders its dependency graph through it.
(with-eval-after-load 'org
  (org-babel-do-load-languages
   'org-babel-load-languages
   (append org-babel-load-languages
           '((plantuml . t)
             (mermaid . t)
             (dot . t)))))

(provide 'init-diagrams)
;;; init-diagrams.el ends here
