;;; init-aidermacs.el --- aidermacs: the aider AI pair-programmer -*- lexical-binding: t; -*-

;;; Commentary:
;; aidermacs (https://github.com/MatthewZMD/aidermacs) is an Emacs
;; front-end for `aider' -- a terminal AI pair-programming tool.  aidermacs
;; runs the `aider' subprocess inside a `vterm' buffer and drives it through
;; a Magit-style transient menu (`C-c a').  AI file edits are surfaced with
;; `ediff' before they are accepted.
;;
;; This config's three AI surfaces, kept as separate modules:
;;   gptel           -- free-form LLM chat, no repo awareness   (init-ai.el)
;;   claude-code-ide -- the `claude' CLI bridged over MCP       (init-ai.el)
;;   aidermacs       -- the `aider' CLI; repo-map-aware, diff-first (here)
;; aidermacs lives in its own module -- not folded into init-ai.el -- to
;; keep the one-package-per-module granularity of init-corfu / init-dirvish
;; / init-obsidian.
;;
;; Prerequisites (NOT installed by this config -- see the task SPEC.md):
;;   * `aider' on PATH -- `pipx install aider-chat'.
;;   * `vterm' -- already present (init-terminal.el); its native module is
;;     already compiled because claude-code-ide uses vterm too.
;;   * GEMINI_API_KEY -- aider reads the key from its process environment,
;;     NOT from ~/.authinfo (where gptel keeps its copy).  Export it in the
;;     login-shell rc; the daemon then harvests it lazily via the
;;     `exec-path-from-shell-copy-env' call in `:config' below.
;;
;; First install: `M-x my/package-refresh' then restart Emacs (the archive
;; is not auto-refreshed at startup -- see init.el).

;;; Code:

(use-package aidermacs
  :ensure t
  :bind ("C-c a" . aidermacs-transient-menu)
  :custom
  ;; Run aider inside vterm, not the pure-Elisp comint backend.  vterm is
  ;; already a dependency here (init-terminal.el, also used by
  ;; claude-code-ide); its full ANSI emulation renders aider's colored,
  ;; streamed output cleanly.
  (aidermacs-backend 'vterm)
  ;; Default model: Gemini, matching gptel's default in init-ai.el.  aider
  ;; resolves model strings through litellm, hence the `gemini/' prefix.
  ;; CONFIRM / upgrade the exact newest string with `aider --list-models
  ;; gemini' -- gptel tracks the rolling `gemini-pro-latest' alias, but
  ;; litellm's string for the current Pro model must be verified, not
  ;; guessed.  `gemini-2.5-pro' is the conservative known-good default.
  (aidermacs-default-model "gemini/gemini-2.5-pro")
  ;; Start sessions in plain `code' mode (direct edits).  architect mode
  ;; and its dual reasoning/editor model split are an opt-in via the
  ;; transient menu key `3' -- see the task SPEC.md Open Questions.
  (aidermacs-default-chat-mode 'code)
  ;; Open an `ediff' on every AI-made change before it is accepted.
  (aidermacs-show-diff-after-change t)
  ;; Let Magit own commits.  aider's auto-commit would fragment the
  ;; small-system-scoped commit discipline this repo follows (init-git.el
  ;; is Magit-centric; `vc-handled-backends' is nil there).
  (aidermacs-auto-commits nil)
  :config
  ;; aider reads GEMINI_API_KEY from its process environment.  When Emacs
  ;; runs as a daemon, `exec-path-from-shell' (init.el) only harvested
  ;; PATH/MANPATH -- so pull the key in here, lazily, the first time
  ;; aidermacs loads (on the first `C-c a').  Skip the shell spawn if the
  ;; var is already present: in a TTY-direct launch `exec-path-from-shell'
  ;; is not even loaded (its `:if' guard fails) and the env was inherited
  ;; from the launching shell, so the `fboundp' guard correctly no-ops.
  (when (and (not (getenv "GEMINI_API_KEY"))
             (fboundp 'exec-path-from-shell-copy-env))
    (exec-path-from-shell-copy-env "GEMINI_API_KEY")))

(provide 'init-aidermacs)
;;; init-aidermacs.el ends here
