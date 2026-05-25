# TODO — add aidermacs to the Emacs config (live progress log)

> Durable checklist: [TASKS.md](./TASKS.md). Plan of record: [SPEC.md](./SPEC.md).
> Append-only progress/decision notes below.

## Current focus

**All 11 tasks done.** aidermacs is wired into the config, the package is
installed, the Gemini key is delivered, and the aider → Gemini path is
verified end-to-end (non-interactively). Nothing is blocked.

## Next steps

Operator actions only — nothing left for the implementer:

1. Restart the Emacs daemon (or `M-x load-file RET init.el`) so the running
   session picks up `init-aidermacs` — the daemon predates the change.
2. Interactive smoke check: `C-c a` → start a session → confirm the `aider`
   `vterm` buffer renders without flicker and a real edit round-trips
   through `ediff`.
3. Commit when ready (nothing is committed yet). Suggested split:
   - `.emacs.d` repo — commit 1: `init.el` + `lisp/init-aidermacs.el`
     (implementation); commit 2: `CLAUDE.md` + `FEATURES.md` (docs).
   - `/home/fenrir` parent repo — separate commit: `.profile` (the
     secret-free `source` line; `~/.profile.local` stays untracked).

## Decisions / notes

- 2026-05-20 — Module placement: aidermacs gets its **own**
  `lisp/init-aidermacs.el`, NOT folded into `init-ai.el`, despite init-ai.el
  being the thematic AI module. Operator's explicit choice; matches the
  one-package-per-module granularity of init-corfu / init-dirvish /
  init-obsidian.
- 2026-05-20 — Backend: `vterm` (not the comint default). vterm is already
  a dependency (init-terminal.el, used by claude-code-ide); its native
  module is already compiled.
- 2026-05-20 — API key delivery: aider reads `GEMINI_API_KEY` from the
  **process environment** — it has no auth-source path. Operator chose
  shell-env delivery: export in the login-shell rc, harvested into the
  daemon by a lazy `exec-path-from-shell-copy-env` call in the module's
  `:config`. This diverges from the `~/.authinfo` pattern that
  `fenrir/gptel-set-api-key` uses for gptel.
- 2026-05-20 — Default model: Gemini, matching gptel's default. SPEC ships
  the conservative litellm string `gemini/gemini-2.5-pro`; the exact newest
  Pro string is to be confirmed via `aider --list-models gemini` (open
  question, non-blocking).
- 2026-05-20 — Keybinding: `C-c a` → `aidermacs-transient-menu`. Verified
  free against every `C-c` binding in the config — no collision with
  `C-c t/f/s/d`, `C-c C-'`, or the `C-c r/n/o` prefixes.
- 2026-05-20 — `aidermacs-auto-commits nil` — Magit owns commits; aider
  auto-commit would fragment the repo's small-system-scoped commit discipline.
- 2026-05-20 — `aider` and `pipx` are NOT installed on this machine;
  installing them is a manual one-shot prerequisite, kept out of the Emacs
  change.
- 2026-05-20 — Default chat mode `code`; architect mode + dual-model split
  deferred to open questions.
- 2026-05-20 — `CLAUDE.md` / `FEATURES.md` updates are follow-up commits
  (T10 / T11), deliberately not bundled with the implementation diff to
  keep it reviewable.
- 2026-05-20 — T6 implemented: `lisp/init-aidermacs.el` created verbatim
  from the SPEC Code Style block; `init.el` gained `init-aidermacs` as the
  last require-list entry plus one header-comment line. Verified —
  `check-parens` balanced on both files; `emacs --batch -l init.el` exits 0
  and prints `BATCHLOAD-OK`, so `init-aidermacs` `require`d cleanly.
- 2026-05-20 — T7 done early (unplanned): the T6 batch-load verification
  triggered `use-package` `:ensure`, which `package-install`ed
  `aidermacs-20260428.828` from MELPA. The archive index was already cached
  from a prior refresh, so the network-free-boot caveat did not bite — no
  separate `M-x my/package-refresh` was needed. Package now in `elpa/`
  (gitignored); a running daemon needs a restart to pick it up.
- 2026-05-20 — The byte-compile warnings emitted during the install are all
  upstream aidermacs code (`aidermacs-models.el` / `-output.el` / `.el`:
  docstring quoting, unused / free variables). None come from
  `init-aidermacs.el` — our module compiled clean.
- 2026-05-20 — T3 install saga: `pipx install aider-chat` failed — pipx
  defaults to Python 3.13, pip backtracks aider versions until one pinning
  `numpy==1.24.3` (no 3.13 wheel; source build fails). `pipx install
  --python 3.12 --fetch-missing-python` then 404'd — pipx 1.7.1's
  python-build-standalone URL is stale (the project moved orgs). Resolved:
  `pipx install uv` then `uv tool install --python 3.12 aider-chat` →
  `aider 0.86.2`. Lesson for the SPEC: the bare `pipx install aider-chat`
  command does not work on a Python-3.13-only host.
- 2026-05-20 — `aider --list-models` was run inside `~/.emacs.d`; aider
  auto-appended `.aider*` to that repo's tracked `.gitignore` and dropped
  `.aider.chat.history.md`. Both reverted / removed. Lesson: run `aider`
  from a non-repo dir, or pass `--no-gitignore`.
- 2026-05-20 — T4: `gemini/gemini-2.5-pro` is the only GA (non-preview) Pro
  model litellm exposes. `gemini/gemini-3-pro-preview`,
  `gemini/gemini-3.1-pro-preview`, and the rolling `gemini/gemini-pro-latest`
  alias all exist but are preview-tier. Kept the conservative GA default;
  `init-aidermacs.el` unchanged. Operator can switch live via menu `o`.
- 2026-05-20 — T8 verified via batch load: `(featurep 'init-aidermacs)` is
  `t`, `C-c a` → `aidermacs-transient-menu`, exit 0. NOTE: the operator's
  running daemon predates the `init.el` change — restart it (or
  `M-x load-file init.el`) to pick up the new module.
- 2026-05-20 — T5 blocker: `~/.bashrc` AND `~/.profile` are both tracked in
  the `/home/fenrir` parent repo, so `export GEMINI_API_KEY=…` cannot go
  straight into either (SPEC boundary: no secret in a tracked file). The
  Gemini key already exists in `~/.authinfo` (gptel's entry, host
  `generativelanguage.googleapis.com`).
- 2026-05-20 — T5 resolved (operator chose the untracked-sidecar option):
  the Gemini key was read from `~/.authinfo` and written to a new untracked
  `~/.profile.local` (mode 600); the tracked `~/.profile` gained one
  secret-free guarded line `[ -f ~/.profile.local ] && . ~/.profile.local`
  at its end. Mirrors the repo's `Include ~/.ssh/config.local` precedent.
  Verified — `bash -lc` shows `GEMINI_API_KEY` set (39-char key).
- 2026-05-20 — T9 verified: `aider --model gemini/gemini-2.5-pro
  --message …` run via `bash -lc` (the same login-shell path
  `exec-path-from-shell-copy-env` uses) returned a correct Gemini reply
  (2.6k sent / 43 received, $0.0037). Proves key + model + aider end to
  end. The interactive `C-c a` / `vterm`-flicker / edit-through-`ediff`
  check remains for the operator to do live.
- 2026-05-20 — T10 / T11 done: `CLAUDE.md` module count 15 → 16 with
  `init-aidermacs` listed; `FEATURES.md` §14 extended with an aidermacs
  entry + the `C-c a` binding table.

## Blockers

- None. All 11 tasks complete; only operator-side actions remain (daemon
  restart + interactive smoke check + commits) — see Next steps.
