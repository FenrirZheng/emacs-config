# TASKS — add aidermacs to the Emacs config

> Durable checklist. Live progress + decisions in [TODO.md](./TODO.md).
> Plan of record: [SPEC.md](./SPEC.md).
> Status: ☐ todo · ⧗ in-progress · ☑ done.

## Phase 0 — Spec

- ☑ **T1** Write the aidermacs integration SPEC — `SPEC.md` authored;
  decisions locked (new `init-aidermacs.el` module, `vterm` backend,
  shell-env key delivery, Gemini default, `C-c a` binding).

## Phase 1 — Prerequisites (system-level, manual, one-shot)

- ☑ **T2** Install `pipx` — done (operator).
- ☑ **T3** Install `aider` — `aider 0.86.2` installed. `pipx install
  aider-chat` failed (Python 3.13 backtracks to an ancient aider pinning
  `numpy==1.24.3` that will not build); installed instead via
  `uv tool install --python 3.12 aider-chat`. See [TODO.md](./TODO.md).
- ☑ **T4** Confirm the Gemini model string — `gemini/gemini-2.5-pro` is the
  only GA Pro string litellm exposes; all 3.x Pro models are `-preview`
  tier. Conservative SPEC default retained, no file change.
- ☑ **T5** Deliver `GEMINI_API_KEY` to aider — key placed in untracked
  `~/.profile.local` (mode 600), sourced by a secret-free guarded line in
  the tracked `~/.profile`. Verified: a login shell exports it.

## Phase 2 — Emacs implementation

- ☑ **T6** Create `lisp/init-aidermacs.el` and register `init-aidermacs`
  in the `init.el` require list + header comment — per the SPEC Code Style
  block. Verified: parens balanced, batch load exits 0.
- ☑ **T7** Install the package — `aidermacs-20260428.828` installed from
  MELPA into `elpa/` as a side effect of the T6 batch-load verification
  (the archive index was already cached). See [TODO.md](./TODO.md).

## Phase 3 — Verification

- ☑ **T8** Smoke-verify — batch load exits 0; `(featurep 'init-aidermacs)`
  is `t`; `C-c a` resolves to `aidermacs-transient-menu`, no collision.
- ☑ **T9** Functional-verify — `aider --model gemini/gemini-2.5-pro` run
  through a login shell got a real Gemini reply (43 tokens, $0.0037),
  proving the model string + `GEMINI_API_KEY` propagation. The interactive
  `C-c a` / `vterm`-flicker check is the operator's to do live.

## Phase 4 — Follow-ups (separate commits, not bundled with the implementation diff)

- ☑ **T10** Update `CLAUDE.md` — module count 15 → 16, `init-aidermacs`
  added to the module list.
- ☑ **T11** Update `FEATURES.md` — §14 "AI / agent tooling" extended with
  an aidermacs entry + the `C-c a` binding table.

## Checkpoints

- ☑ After T1 — `SPEC.md` approved (operator proceeded to implementation).
- ☑ After T6 — `git diff` shows exactly one new file (`lisp/init-aidermacs.el`)
  plus a 2-line `init.el` edit, nothing else. *Confirmed.*
- ☑ After T8 — batch sanity + feature/keybinding checks green; no new
  `*Messages*` warnings vs the pre-aidermacs baseline.
- ☑ After T9 — a real Gemini-backed aider call round-trips (verified
  non-interactively via `aider --message`); the interactive edit-through-
  `ediff` path is the operator's live check.

## Deferred — open questions (not yet committed work; see [SPEC.md](./SPEC.md) §Open Questions)

- Exact newest Gemini model string (SPEC ships the conservative
  `gemini/gemini-2.5-pro`).
- architect mode + dual `aidermacs-architect-model` /
  `aidermacs-editor-model` split.
- Fold the `pipx` + `aider-chat` install into [`shell/install-user.sh`](../../shell/install-user.sh).
- `aidermacs-project-read-only-files` for pinned convention files.
- `vterm` flicker risk in TTY-inside-tmux (resolve only if observed during T9).

## References

| doc | why |
|-----|-----|
| [SPEC.md](./SPEC.md) | plan of record — objective, code, boundaries, success criteria |
| [TODO.md](./TODO.md) | live progress log + append-only decisions/notes |
| [`init.el`](../../init.el) | loader the new module is registered in (T6) |
| [`lisp/init-ai.el`](../../lisp/init-ai.el) | sibling AI module (gptel, claude-code-ide); aidermacs is kept separate from it |
| [`CLAUDE.md`](../../CLAUDE.md) | repo guide updated in the T10 follow-up |
| [`FEATURES.md`](../../FEATURES.md) | key cheat-sheet updated in the T11 follow-up |
