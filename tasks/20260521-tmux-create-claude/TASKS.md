# TASKS — Emacs command: split a tmux pane running the Claude CLI

> Durable checklist. Live progress notes in [TODO.md](./TODO.md).
> Design doc: [plan.md](../plan.md). Requirements: [SPEC.md](./SPEC.md).
> Status: ☐ todo · ⧗ in-progress · ☑ done.

## Implementation

- ☑ **T1** Create `lisp/init-tmux-claude.el` — new module with the interactive
  command `fenrir/tmux-claude-split` (standard header, `user-error` guards for
  not-in-tmux and missing `claude`, `call-process` to `tmux split-window -h` +
  `select-pane -T`, `provide` footer).
- ☑ **T2** Register the module in `init.el` — add `init-tmux-claude` to the
  header-comment module list and to the `(mapc #'require …)` list, appended
  after `init-aidermacs`. Depends on T1.
- ☑ **T3** Update docs — add the module/command to [`FEATURES.md`](../../FEATURES.md)
  §14 and bump the module count (16 → 17) + list in [`CLAUDE.md`](../../CLAUDE.md).
  Depends on T1.
- ☑ **T5** Fix tmux detection under an Emacs daemon — follow-up from the user's
  acceptance test (`getenv "TMUX"` is nil in a daemon started outside tmux).
  Read `TMUX`/`TMUX_PANE` from the invoking frame's `environment` parameter
  (set by server.el for `emacsclient` frames) via a `fenrir/tmux-claude--getenv`
  helper, and re-inject them into `process-environment` for the child `tmux`
  processes so `split-window` targets the Emacs frame's pane.

## Verification

- ☑ **T4** Exercise the command — load the module, then run the happy path
  (inside tmux, `claude` on PATH), the not-in-tmux guard, and the
  missing-`claude` guard. Depends on T1, T2, T3.

## Checkpoints

- ☑ After T1 — `lisp/init-tmux-claude.el` loads / byte-compiles with no error;
  `fenrir/tmux-claude-split` is a defined interactive command.
- ☑ After T2 — a fresh Emacs start loads the module; `(featurep 'init-tmux-claude)`
  returns `t`.
- ☑ After T4 — both guards abort with a `user-error` and create no pane;
  `split-window`/`select-pane -T` mechanics verified in an isolated session
  (pane titled `claude-%21`). Live `M-x` happy-path run is the user's final
  acceptance check (SPEC §4).

## References

| doc | why |
|-----|-----|
| [TODO.md](./TODO.md) | live progress + decision log |
| [plan.md](../plan.md) | full design doc — rationale, code shape, design notes |
| [SPEC.md](./SPEC.md) | original requirements (objective, functional reqs, edge cases) |
