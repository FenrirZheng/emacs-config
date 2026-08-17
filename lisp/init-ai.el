;;; init-ai.el --- AI / agent tooling -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 15 of the pre-split monolithic init.el (see git log for the move).
;;   gptel             -- LLM chat client (OpenAI / Claude / Gemini / Ollama / ...)
;; Configured explicitly below; see `package-selected-packages' in custom.el
;; for the install source (gptel from MELPA / NonGNU ELPA).

;;; Code:

;; claude-jobs-view -- tabulated UI for the `jobctl' CLI (persistent Claude
;; Code background sessions).  Source: lisp/claude-jobs-view.el.  `C-c j'
;; ("jobs") is free at the top level -- no other module claims it.
;; `:commands' makes the autoload lazy -- the file is only loaded the first
;; time the command is invoked.
(use-package claude-jobs-view
  :ensure nil
  :bind ("C-c j" . claude-jobs-view)
  :commands (claude-jobs-view))

;; claude-open -- open files a Claude Code session mentions (rg hits, stack
;; frames, compiler errors) in THIS daemon at the right line, preferring the GUI
;; frame.  Source: lisp/claude-open.el, distributed by the `emacs-open' skill
;; (~/.claude/skills/emacs-open/references/claude-open.el is upstream; the
;; skill probes `claude-open-version' for drift).
;; `:demand t' rather than the lazy `:commands' used above ON PURPOSE: the entry
;; point is reached by `emacsclient -e (claude-open-from-file ...)', a
;; non-interactive eval, and the skill's probe reads `claude-open-version' --
;; under an autoload that variable is unbound and the probe reads the helper as
;; being SHADOWED by an unrelated definition, so it refuses to dispatch.
;; No keybinding here: `claude-open-setup-keys' is shipped but deliberately not
;; called -- binding `claude-open-goto-last' is the user's choice.
(use-package claude-open
  :ensure nil
  :demand t)

;; question-queue -- ship the highlighted region + a typed question into the
;; external file-queue (~/code/question-queue/input/) via the Rust
;; `question-queue-core' dynamic module, watch output/ with file-notify, and
;; drop the answer into a *question-queue* side buffer.  Source:
;; lisp/question-queue.el + rust/question-queue-core/.  `:commands'/`:bind' keep
;; it lazy (the .so loads on first use; M-x question-queue-build builds it).
(use-package question-queue
  :ensure nil
  :commands (question-queue-ask question-queue-build question-queue-set-dir)
  :bind (("C-c q q" . question-queue-ask)
         ("C-c q d" . question-queue-set-dir)))

;; copilot -- GitHub Copilot AI inline completion: greyed-out "ghost text"
;; suggestions as you type, the headline feature of every modern IDE that gptel
;; / aidermacs (chat-style) don't provide.  Renders via an overlay, so it works
;; on a TTY frame; the suggestion only appears when there's something to suggest.
;;
;; DELIBERATELY OPT-IN, not a `prog-mode' hook.  Two one-time setup steps gate
;; it: `M-x copilot-install-server' (downloads the Node language server -- node
;; v25 is on PATH here) and `M-x copilot-login' (device-code auth, needs a
;; Copilot subscription).  Hooking `prog-mode' before those are done would make
;; every code buffer spam "server not running" -- so instead `C-c M-c' toggles
;; `copilot-mode' per buffer.  Once set up, add `(add-hook 'prog-mode-hook
;; #'copilot-mode)' here to make it always-on.
;;
;; Keys: the accept/cycle keys live in `copilot-completion-map', which is only
;; active WHILE a ghost suggestion is showing -- so binding `TAB' there accepts
;; the suggestion when one is visible and indents normally otherwise (it does
;; not fight yasnippet / corfu / indent in the common case).
(use-package copilot
  :commands (copilot-mode copilot-login copilot-install-server)
  :bind (("C-c M-c" . copilot-mode)            ; per-buffer toggle (opt-in)
         :map copilot-completion-map
         ("<tab>"   . copilot-accept-completion)
         ("TAB"     . copilot-accept-completion)
         ("C-<tab>" . copilot-accept-completion-by-word)
         ("C-c M-n" . copilot-next-completion)
         ("C-c M-p" . copilot-previous-completion))
  :custom
  ;; copilot warns (once per buffer) when it can't match the major mode's indent
  ;; offset to a known variable; harmless here and just noise, so silence it.
  (copilot-indent-offset-warning-disable t))

;; gptel -- LLM chat client.  Available from MELPA / NonGNU ELPA.
;; Entry points (no key bindings claimed -- invoke via M-x):
;;   M-x gptel                     -- open / switch to a chat buffer
;;   M-x gptel-send                -- send the region or buffer up to point
;;   M-x gptel-menu                -- transient menu: backend, model, ...
;;   M-x fenrir/gptel-set-api-key  -- stash a provider key into ~/.authinfo
;;
;; API keys live in `~/.authinfo' (NOT here -- this file is tracked git).
;; The default `gptel-api-key' is the function
;; `gptel-api-key-from-auth-source', which reads `machine <host> login apikey
;; password <key>' for each backend's host.  Use
;; `M-x fenrir/gptel-set-api-key' to write those entries safely.
;;
;; Transient: gptel needs transient 0.7.8+, newer than the copy bundled
;; with Emacs 30.1.  The MELPA `transient' is already installed as a
;; transitive dep of magit (`elpa/transient-*'), so the requirement is
;; satisfied on this machine without setting `package-install-upgrade-built-in'.
;;
;; First install: run `M-x my/package-refresh' then restart Emacs (the
;; archive is not auto-refreshed at startup -- see init.el).

(defun fenrir/gptel-set-api-key (provider key)
  "Store API KEY for PROVIDER in `~/.authinfo' as an apikey entry.

PROVIDER is one of the symbols `anthropic', `gemini', `openai'.
The function writes the canonical auth-source shape that
`gptel-api-key-from-auth-source' expects:

    machine <host> login apikey password <key>

so gptel picks the key up automatically the next time a request
hits that backend -- no Emacs restart needed.  An existing line
for the same host is replaced, never duplicated.  The file is
re-locked to mode 0600 after writing.

Interactively prompts for the provider and reads the key with
`read-passwd' so it does not echo and does not enter
`minibuffer-history'.  This command is defined OUTSIDE the gptel
`use-package' block on purpose: you can run it on a fresh machine
before gptel is loaded, to seed the key first."
  (interactive
   (let* ((p (intern (completing-read "Provider: "
                                      '("anthropic" "gemini" "openai")
                                      nil t)))
          (k (read-passwd (format "%s API key (input hidden): " p))))
     (list p k)))
  (when (or (null key) (string-empty-p (string-trim key)))
    (user-error "Empty API key, aborting"))
  (let* ((host (pcase provider
                 ('anthropic "api.anthropic.com")
                 ('gemini    "generativelanguage.googleapis.com")
                 ('openai    "api.openai.com")
                 (_ (user-error "Unknown provider: %s" provider))))
         (path (expand-file-name "~/.authinfo"))
         (line (format "machine %s login apikey password %s" host key))
         (rx   (format "^machine[ \t]+%s[ \t]+login[ \t]+apikey.*\n?"
                       (regexp-quote host))))
    (with-temp-buffer
      (when (file-exists-p path)
        (insert-file-contents path))
      (goto-char (point-min))
      (while (re-search-forward rx nil t)
        (replace-match ""))                ; drop any previous entry for HOST
      (goto-char (point-max))
      (unless (or (bobp) (eq (char-before) ?\n))
        (insert "\n"))
      (insert line "\n")
      (let ((coding-system-for-write 'utf-8))
        (write-region (point-min) (point-max) path nil 'silent)))
    (set-file-modes path #o600)            ; belt-and-suspenders re-tighten
    ;; Bust auth-source's in-memory cache so the *next* gptel request
    ;; re-reads the file instead of returning the old (or nil) cached value.
    (when (require 'auth-source nil 'noerror)
      (auth-source-forget-all-cached))
    (message "gptel: wrote %s key for %s to %s" provider host path)))

(use-package gptel
  :commands (gptel gptel-send gptel-menu)
  :config
  ;; Register non-default backends.  `:key gptel-api-key' makes each backend
  ;; call the default `gptel-api-key-from-auth-source' lookup with ITS host
  ;; (api.anthropic.com / generativelanguage.googleapis.com), so a single
  ;; ~/.authinfo with the right machine entries unlocks all backends.
  ;; Seed those entries with `M-x fenrir/gptel-set-api-key'.
  (gptel-make-anthropic "Claude" :stream t :key gptel-api-key)
  (gptel-make-gemini    "Gemini" :stream t :key gptel-api-key)
  ;; Default to Gemini, not the out-of-the-box OpenAI ChatGPT.  Seed the
  ;; `generativelanguage.googleapis.com' entry in `~/.authinfo' with
  ;; `M-x fenrir/gptel-set-api-key gemini' before first send, otherwise
  ;; gptel raises "No `gptel-api-key' found in the auth source".
  ;; Using the rolling `gemini-pro-latest' alias so we automatically
  ;; track Google's newest Pro thinking model (currently 3.1-pro-preview)
  ;; without needing to bump the pin every release.  Switch live with
  ;; `M-x gptel-menu' (-p picks backend, -m picks model) if a specific
  ;; version is needed.
  (setq gptel-backend (gptel-get-backend "Gemini")
        gptel-model   'gemini-pro-latest))

;; ---------------------------------------------------------------------------
;; gptel tools -- expose the two local workflows above to the LLM
;; ---------------------------------------------------------------------------
;; gptel 20260519 registers tools with `gptel-make-tool' into `gptel--known-tools';
;; the user then picks them per-request from `gptel-menu' (`-t'), so registering
;; here does NOT arm them behind your back.  All of this sits inside
;; `with-eval-after-load' so nothing drags gptel into startup.
;;
;; Deliberately conservative:
;;   * three READ-ONLY tools (list jobs, inspect one session, show the queue
;;     state) and exactly one writer, `question_queue_ask', which carries
;;     `:confirm t' so a tool call always waits for a human keypress;
;;   * they call the same helpers the interactive commands do, so behaviour
;;     cannot drift from what `C-c j' / `C-c q' show;
;;   * NOTHING here requires the native `question-queue-core' module or a
;;     running `jobctl'.  Both front-ends degrade to an actionable error
;;     (`M-x question-queue-build', "jobctl list failed") -- the tools catch
;;     it and return that text as the tool RESULT rather than signalling, so a
;;     missing binary reads as information to the model, not as a broken tool.
(with-eval-after-load 'gptel
  (defun fenrir/gptel--safely (thunk)
    "Run THUNK, returning its value or the error text as a string.
A tool that signals aborts the whole gptel request; a tool that returns
\"jobctl: not built/installed\" lets the model explain the situation."
    (condition-case err (funcall thunk)
      (error (format "error: %s" (error-message-string err)))))

  (gptel-make-tool
   :name "claude_jobs_list"
   :category "fenrir"
   :description "List the persistent Claude Code background sessions and daemon \
jobs known to the local `jobctl' CLI.  Returns `jobctl list' output verbatim \
(sessions with uuid, state, pid, last-update and intent).  Read-only."
   :args nil
   :function
   (lambda ()
     (fenrir/gptel--safely
      (lambda ()
        (require 'claude-jobs-view)
        (claude-jobs-view--run-list)))))

  (gptel-make-tool
   :name "claude_job_info"
   :category "fenrir"
   :description "Describe one Claude Code background session: its transcript \
path, its working directory and the first user message of the transcript.  \
Takes the session uuid as printed by claude_jobs_list.  Read-only."
   :args (list '(:name "uuid"
                 :type string
                 :description "Full session uuid from claude_jobs_list"))
   :function
   (lambda (uuid)
     (fenrir/gptel--safely
      (lambda ()
        (require 'claude-jobs-view)
        (format "uuid:       %s\ncwd:        %s\ntranscript: %s\nfirst user message:\n%s"
                uuid
                (or (claude-jobs-view--resolve-cwd uuid) "(not resolved)")
                (or (ignore-errors (claude-jobs-view--jobctl-string "path" uuid))
                    "(unresolved)")
                (or (claude-jobs-view--transcript-first-user-text uuid)
                    "(none)"))))))

  (gptel-make-tool
   :name "question_queue_status"
   :category "fenrir"
   :description "Report the state of the file-based question queue: its root \
directory, whether the native question-queue-core module is loaded, and the \
questions still awaiting an answer in this Emacs session.  Read-only."
   :args nil
   :function
   (lambda ()
     (fenrir/gptel--safely
      (lambda ()
        (require 'question-queue)
        (let ((root (condition-case nil (question-queue--root)
                      (error "(unset -- M-x question-queue-set-dir)")))
              (pending '()))
          (maphash (lambda (name entry)
                     (push (format "  %s: %s" name (plist-get entry :question))
                           pending))
                   question-queue--pending)
          (concat (format "root: %s\nnative module loaded: %s\npending: %d\n"
                          root (if (question-queue--loaded-p) "yes" "no")
                          (length pending))
                  (string-join (nreverse pending) "\n")))))))

  (gptel-make-tool
   :name "question_queue_ask"
   :category "fenrir"
   :description "Submit a question (optionally with a code snippet as context) \
to the file-based question queue; the answer arrives asynchronously in the \
*question-queue* buffer.  Requires the native question-queue-core module and a \
queue directory to have been set."
   :confirm t                           ; the only writer here -- always ask
   :args (list '(:name "question"
                 :type string
                 :description "The question text")
               '(:name "context"
                 :type string
                 :optional t
                 :description "Optional code snippet sent as context"))
   :function
   (lambda (question &optional context)
     (fenrir/gptel--safely
      (lambda ()
        (require 'question-queue)
        (question-queue-ask (and context (not (string-empty-p context)) context)
                            question)
        "submitted; the answer will appear in *question-queue*")))))

(provide 'init-ai)
;;; init-ai.el ends here
