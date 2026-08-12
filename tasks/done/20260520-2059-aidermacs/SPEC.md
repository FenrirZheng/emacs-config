; -*- mode: markdown -*-

# Spec: add aidermacs (the aider AI pair-programmer) to the Emacs config

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
This SPEC lives in its own task directory. The immediately prior task —
add Dirvish, [`tasks/20260519-1650-no-name/SPEC.md`](../20260519-1650-no-name/SPEC.md)
— has landed (`lisp/init-dirvish.el` is in the loader and `init-dirvish`
is in the [`init.el`](init.el) require list). This file is self-contained;
it supersedes nothing in place.

## Objective

Add [aidermacs](https://github.com/MatthewZMD/aidermacs) — an Emacs
front-end for the terminal AI pair-programming tool
[aider](https://aider.chat) — to this Emacs 30.1 config as a **new
per-package module** [`lisp/init-aidermacs.el`](lisp/init-aidermacs.el),
loaded by the [`init.el`](init.el) thin loader as the **last** entry,
right after [`init-ai.el`](lisp/init-ai.el).

aidermacs runs the `aider` subprocess inside a `vterm` buffer and drives
it through a Magit-style transient menu bound to `C-c a`. AI file edits
are surfaced with `ediff` before they are accepted.

Why this matters:
- The config already has two AI surfaces in [`init-ai.el`](lisp/init-ai.el)
  — `gptel` (free-form LLM chat, no repo awareness) and `claude-code-ide`
  (the `claude` CLI bridged over MCP). aidermacs is a third, distinct
  surface: `aider` is **repo-map-aware** and **diff-first** — you add
  specific files to a chat, request a change, and review every edit in
  `ediff`. None of the existing tooling covers that workflow.
- aider is model-agnostic via litellm; pointing it at Gemini keeps the
  whole config consistent with `gptel`'s existing Gemini default.

### Target user

The single operator of this repo (one machine, TTY-first: Emacs daemon +
`emacsclient -c -nw` inside tmux). Like every prior section, this is for
that operator's daily use, not for packaging or sharing.

### Assumptions I'm making

1. **New module file, not a fold-in.** aidermacs gets its own
   [`lisp/init-aidermacs.el`](lisp/init-aidermacs.el). It is **not** folded
   into [`init-ai.el`](lisp/init-ai.el), even though that module is the
   thematic "AI / agent tooling" home — this matches the one-package-per-
   module granularity of `init-corfu.el`, `init-dirvish.el`,
   `init-obsidian.el`, and was the operator's explicit choice.
2. **`vterm` backend.** `aidermacs-backend` is `'vterm`, not the pure-Elisp
   `'comint` default. `vterm` is already installed and configured in
   [`init-terminal.el`](lisp/init-terminal.el); its native module is
   already compiled because `claude-code-ide` uses `vterm` too. Full ANSI
   emulation renders aider's colored, streamed output cleanly.
3. **Gemini is the default model.** `aidermacs-default-model` is a Gemini
   model string (`gemini/...`, resolved by litellm), matching `gptel`'s
   `gemini-pro-latest` default in [`init-ai.el`](lisp/init-ai.el).
4. **The key reaches aider via the process environment, NOT `~/.authinfo`.**
   `aider` reads `GEMINI_API_KEY` from its environment. The operator
   exports it in the login-shell rc; the Emacs daemon harvests it via a
   lazy `exec-path-from-shell-copy-env` call inside the module. This
   diverges from the `~/.authinfo` + auth-source pattern that
   [`init-ai.el`](lisp/init-ai.el)'s `fenrir/gptel-set-api-key` uses for
   `gptel` — aider simply has no auth-source path, and shell-env delivery
   was the operator's explicit choice.
5. **`aider` and `pipx` are NOT installed by this config.** `aider` is a
   Python CLI; `pipx` is absent on this machine. Installing both is a
   one-shot manual prerequisite (see [Commands](#commands)), not part of
   the Emacs change. Folding `aider` into
   [`shell/install-user.sh`](shell/install-user.sh) is deferred (see
   [Open Questions](#open-questions)).
6. **Plain `code` chat mode for the initial install.** `architect` mode
   and its dual reasoning/editor model split are reachable via the
   transient menu but are NOT configured by default — deferred (see
   [Open Questions](#open-questions)).
7. **aider auto-commits are OFF.** Magit owns commits in this repo
   ([`init-git.el`](lisp/init-git.el) is Magit-centric, `vc-handled-backends`
   is `nil`). aider's auto-commit would fragment the small-system-scoped
   commit discipline this repo follows.
8. **Network-free boot survives.** [`init.el`](init.el) deliberately skips
   `package-refresh-contents` at startup. First-time install requires
   `M-x my/package-refresh` once, then a restart — same drill as every
   other package added to this config.

→ Correct any of these now or the implementation will assume them.

## Tech Stack

- Emacs 30.1 with `use-package` (built-in since Emacs 29) — unchanged.
- New MELPA package: `aidermacs` (current release line, no version pin).
- New system-level dependency: `aider` — the Python CLI, distributed as
  the `aider-chat` package. Installed via `pipx`, which itself must be
  installed first (`pipx` is absent on this machine).
- Reuses existing packages: `vterm` (declared `:defer` in
  [`init-terminal.el`](lisp/init-terminal.el)), `exec-path-from-shell`
  (loaded `:demand t` in [`init.el`](init.el)'s bootstrap), and
  `transient` — aidermacs's menu needs `transient` 0.7.8+, already
  satisfied on this machine by the MELPA `transient` pulled in
  transitively by `magit` (identical situation to `gptel`, documented in
  [`init-ai.el`](lisp/init-ai.el)).
- LLM: Google Gemini, reached by `aider` through litellm. The API key
  lives in the `GEMINI_API_KEY` environment variable.

## Commands

After the change:

| step | command | notes |
|---|---|---|
| install pipx (one-shot) | `sudo apt install pipx` | Debian package; `aider` is a Python CLI and pipx isolates it |
| install aider (one-shot) | `pipx install aider-chat && pipx ensurepath` | lands `aider` in `~/.local/bin`; `exec-path-from-shell` harvests `PATH` so the daemon finds it |
| confirm aider | `aider --version` | prints a non-empty version string |
| confirm Gemini model strings | `aider --list-models gemini` | lists the exact litellm strings; pick the newest Pro for `aidermacs-default-model` |
| export the key (one-shot) | add `export GEMINI_API_KEY=…` to the login-shell rc | aider reads the key from the environment, NOT `~/.authinfo` |
| install the Emacs package (one-shot, online) | `M-x my/package-refresh` then restart | boot is network-free; `use-package` then auto-installs `aidermacs` from MELPA on next launch |
| batch sanity | `emacs --batch -l init.el --eval '(message "ok")'` | exits 0, prints `ok`, no `Symbol's function definition is void`, no `Cannot open load file` |
| daemon smoke | `emacs --daemon` then `emacsclient -c -nw` | all modules load as before |
| feature audit | `emacsclient -e '(featurep (quote init-aidermacs))'` | must return `t` |
| open the menu | `C-c a` in any frame | opens the `aidermacs-transient-menu` transient |
| start a session | from the menu: `a` | `aider` launches in a `vterm` buffer at the project root |
| key-propagation check | inside the aider vterm, send any prompt | a successful Gemini reply proves `GEMINI_API_KEY` reached the subprocess |

## Project Structure

```
init.el                  → loader; the `mapc #'require '(...)' list gains
                           `init-aidermacs` as the LAST entry (after
                           `init-ai`), plus a one-line module-list update
                           in the file's header comment
lisp/init-aidermacs.el   → NEW. Sole `use-package aidermacs' block plus the
                           lazy `exec-path-from-shell-copy-env' key shim
lisp/init-ai.el          → unchanged (aidermacs is a sibling module, NOT
                           folded in — see Objective / Assumption 1)
lisp/init-terminal.el    → unchanged (`vterm' already declared here;
                           aidermacs reuses it)
CLAUDE.md                → follow-up commit, NOT bundled: "15 modules" → 16,
                           add `init-aidermacs` to the module list
FEATURES.md              → follow-up commit, NOT bundled: extend §14
                           "AI / agent tooling" with an aidermacs entry and
                           the `C-c a` key
SPEC.md                  → this file
```

The [`init.el`](init.el) require list after the change:

```elisp
(mapc #'require
      '(init-defaults
        init-system-packages
        init-completion
        init-corfu
        init-snippets
        init-editing
        init-languages
        init-git
        init-terminal
        init-appearance
        init-dirvish
        init-org
        init-obsidian
        init-org-roam
        init-ai
        init-aidermacs))    ; ← new, last
```

Placement rationale: aidermacs is AI tooling, so it groups naturally
right after [`init-ai.el`](lisp/init-ai.el). It needs `vterm` (declared in
[`init-terminal.el`](lisp/init-terminal.el), position 9) and
`exec-path-from-shell` (the [`init.el`](init.el) bootstrap) — both are
fully loaded long before the require list reaches this last entry, so no
`use-package :after` edge is required.

## Code Style

The new file follows the same canonical header used by every other module
(see [`lisp/init-corfu.el`](lisp/init-corfu.el),
[`lisp/init-dirvish.el`](lisp/init-dirvish.el)):

```elisp
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
;; Prerequisites (NOT installed by this config -- see SPEC.md):
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
  ;; transient menu key `3' -- see SPEC.md Open Questions.
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
```

## Testing Strategy

No test framework. Verification is smoke + behaviour spot-checks, matching
the discipline of the prior init-split and Dirvish SPECs:

- **Batch load**: `emacs --batch -l init.el --eval '(message "ok")'` exits
  0, prints `ok`, no `Symbol's function definition is void`, no `Cannot
  open load file`. Run before and after to confirm parity.
- **Feature presence**: `(featurep 'init-aidermacs)` is `t` after a clean
  daemon start. `(featurep 'aidermacs)` is `nil` until the first `C-c a`
  (the package is deferred behind the `:bind` autoload), then becomes `t`.
- **Keybinding**: `C-c a` is free in the current config — verified against
  every `C-c` binding in `lisp/*.el` + `init.el` (`C-c t`, `C-c f`,
  `C-c s`, `C-c d`, `C-c C-'`, and the `C-c r` / `C-c n` / `C-c o`
  prefixes). `C-c a` opens `aidermacs-transient-menu` with no collision.
- **Behaviour spot-checks**:
  - `C-c a` opens the transient menu.
  - Menu key `a` starts a session: `aider` launches in a `vterm` buffer
    rooted at the project; aider's banner reports the configured Gemini
    model.
  - Sending a prompt in that buffer returns a Gemini completion — this
    proves both the model string and `GEMINI_API_KEY` propagation.
- **Key propagation**: after the first `C-c a`, `(getenv "GEMINI_API_KEY")`
  is non-`nil` in the running Emacs (the `:config` copy ran), or it was
  already non-`nil` (TTY-direct launch).
- **vterm / TTY rendering**: the aider `vterm` buffer renders without the
  flicker that bit `claude-code-ide` in this TTY-inside-tmux setup (see
  the `claude-code-ide-no-flicker` note in [`init-ai.el`](lisp/init-ai.el)).
  If it flickers, that is the known risk recorded in
  [Open Questions](#open-questions) — do NOT silently swap the backend.
- **Diff hygiene**:
  - `git diff init.el` shows two changes: the require list gains
    `init-aidermacs` (one line) and the loader header comment grows by one
    module-list line — nothing else.
  - `git status` shows one new file: `lisp/init-aidermacs.el`.
  - No edits to [`init-ai.el`](lisp/init-ai.el),
    [`init-terminal.el`](lisp/init-terminal.el),
    [`custom.el`](custom.el), or any other module.

## Boundaries

- **Always**:
  - Keep the change additive — the only edits outside the new file are the
    one-line require-list addition and the one-line header-comment update
    in [`init.el`](init.el).
  - End the new file with `(provide 'init-aidermacs)` and the canonical
    `;;; init-aidermacs.el ends here` trailer.
  - Put the file's lexical-binding cookie on line 1, matching every other
    module.
  - Guard the `exec-path-from-shell-copy-env` call with `fboundp` so a
    TTY-direct launch (where `exec-path-from-shell` is not loaded) does not
    raise a void-function error.
- **Ask first**:
  - Enabling `architect` mode by default and configuring the dual
    `aidermacs-architect-model` (reasoning) + `aidermacs-editor-model`
    (editor) split.
  - Pinning the `aidermacs` MELPA version via `package-vc-selected-packages`
    or a `:vc` form — current install tracks MELPA's latest release.
  - Folding the `aider` install into
    [`shell/install-user.sh`](shell/install-user.sh).
  - Hardcoding a specific Gemini version string instead of the
    verified-via-`aider --list-models` latest, or switching the default
    model away from Gemini.
  - Setting `aidermacs-project-read-only-files` (e.g. to pin a
    `CONVENTIONS.md` into every session as read-only context).
  - Enabling aider's optional extras (voice input, web fetch, browser
    mode).
- **Never**:
  - Put the aidermacs `use-package` block or its key in
    [`init-ai.el`](lisp/init-ai.el) or any other existing module — the
    operator explicitly chose a separate per-package module.
  - Write `GEMINI_API_KEY` (or any API key) into a tracked file —
    `lisp/init-aidermacs.el` IS git-tracked. The key lives only in the
    login-shell rc / process environment. (The pre-commit `gitleaks` hook
    would catch an obvious paste, but do not rely on it.)
  - Commit the byte-compiled `lisp/init-aidermacs.elc` — `.gitignore`
    already excludes `*.elc`; verify before commit.
  - Re-enable aider auto-commits — that bypasses Magit and fragments the
    repo's commit discipline.
  - Silently swap `aidermacs-backend` to `'comint` as a "quick fix" if
    `vterm` misbehaves — a flicker is an Open Question to resolve
    deliberately, not a hidden backend change.
  - Inline `(load ".../init-aidermacs.el")` — use
    `(require 'init-aidermacs)` so duplicate loads are no-ops.

## Success Criteria

1. `emacs --batch -l init.el --eval '(message "ok")'` exits 0 with `ok` on
   stdout, no errors / warnings.
2. `(featurep 'init-aidermacs)` is `t` after a clean daemon start.
3. `C-c a` opens the `aidermacs-transient-menu` transient — no keybinding
   collision (`C-c a` verified free).
4. Menu key `a` starts a session: `aider` launches in a `vterm` buffer and
   reports the configured Gemini model.
5. A prompt sent in that buffer returns a Gemini completion — proving the
   model string is valid and `GEMINI_API_KEY` reached the subprocess.
6. `wc -l lisp/init-aidermacs.el` is in the 45–75 line range — matches the
   density of the other small-package modules
   ([`lisp/init-corfu.el`](lisp/init-corfu.el) is the size benchmark).
7. `git diff --stat` shows one new file (`lisp/init-aidermacs.el`) and a
   tiny edit to [`init.el`](init.el). Nothing else.
8. Restart-cycle proof: `emacs --daemon` → `emacsclient -c -nw` → close →
   re-open is uneventful; `*Messages*` shows no new warnings against the
   pre-aidermacs baseline.

## Open Questions

Non-blocking. Decide after the minimal install is in:

- **Exact Gemini model string**: `aidermacs-default-model` ships as the
  conservative `gemini/gemini-2.5-pro`. Run `aider --list-models gemini`
  and upgrade to the newest Pro string litellm exposes. `gptel` tracks the
  rolling `gemini-pro-latest` alias (currently ≈ a Gemini 3.x Pro preview);
  litellm's equivalent string for `aider` must be confirmed, not guessed.
- **architect mode**: enable `aidermacs-default-chat-mode 'architect` and
  configure `aidermacs-architect-model` (reasoning) + `aidermacs-editor-model`
  (editor)? A Gemini Pro architect + Gemini Flash editor split is the
  obvious pairing. Defer until the plain-`code` install has had real use.
- **`shell/install-user.sh`**: that script already provisions user-level
  toolchains (cargo / go / rustup / npm). Adding `pipx` + `aider-chat`
  there is the natural home — but as a separate follow-up, not bundled
  with the Emacs change.
- **`CLAUDE.md` + `FEATURES.md`**: update the module count ("15 modules" →
  16) and the §14 AI tooling cheat-sheet. Follow-up commit, kept out of
  the implementation diff to keep it reviewable.
- **vterm flicker risk**: `claude-code-ide` hit a flicker in this
  TTY-inside-tmux setup (see [`init-ai.el`](lisp/init-ai.el)). If aider's
  `vterm` buffer flickers too, decide deliberately: tolerate it, tune
  aidermacs's vterm settings, or fall back to the `comint` backend.
- **read-only convention files**: `aidermacs-project-read-only-files` /
  `aidermacs-global-read-only-files` can pin files (a `CONVENTIONS.md`, an
  AI-rules doc) into every session as read-only context. Not set in the
  minimal install; revisit once a house style for aider sessions emerges.
