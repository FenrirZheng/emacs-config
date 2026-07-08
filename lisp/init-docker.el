;;; init-docker.el --- Container tooling -*- lexical-binding: t; -*-

;;; Commentary:
;; Docker/Podman support: a `.dockerfile' major mode and a tablist-driven
;; management UI -- the in-editor equivalent of the VSCode Docker extension /
;; JetBrains Services tool window, for the everyday "what's running, tail its
;; logs, exec a shell, stop it" loop without leaving Emacs.  Kept as its own
;; standalone module (like init-aidermacs / init-tmux-claude) so it's trivial to
;; drop if you don't do containers.

;;; Code:

;; dockerfile-mode: syntax highlighting + indentation for Dockerfiles, and
;; `C-c C-b' to build the image from the visited Dockerfile.  Covers the bare
;; `Dockerfile', `*.dockerfile', and `Dockerfile.*' (e.g. `Dockerfile.prod')
;; spellings.  The `/' anchor matters: auto-mode-alist matches the FULL path
;; and an unanchored "Dockerfile\\'" would also claim `myDockerfile'.  (An
;; earlier "\\Dockerfile\\'" spelling was a no-op escape -- `\\D' is just a
;; literal `D' in Emacs regexps.)  (Compose files are YAML -- handled by the
;; yaml grammar elsewhere, not here.)
(use-package dockerfile-mode
  :mode (("/Dockerfile\\(?:\\..*\\)?\\'" . dockerfile-mode)
         ("\\.dockerfile\\'" . dockerfile-mode)))

;; docker.el: a `transient' menu over the docker (or podman) CLI -- press
;; `C-c D' to list/manage containers, images, volumes, networks and compose
;; projects as `tablist' buffers (mark rows, then operate: start/stop/restart,
;; tail logs, `exec' a shell in, inspect, remove).  Pure CLI wrapper, so it
;; works the same over TTY/SSH as in a GUI.
;;
;; Needs the `docker' binary on PATH (or set `docker-command' to `"podman"').
;; If absent, `C-c D' errors only when invoked -- no startup cost, nothing
;; loads until first use (autoloaded `docker' command).  `C-c D' is a free
;; global slot (eglot's `C-c .' refactors, the `C-c G' git-extras prefix, and
;; vterm's `C-c t'/`C-c T' don't collide).
(use-package docker
  :bind ("C-c D" . docker))

(provide 'init-docker)
;;; init-docker.el ends here
