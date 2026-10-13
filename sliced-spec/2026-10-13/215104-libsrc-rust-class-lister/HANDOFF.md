# Handoff: libsrc — list jar classes with a Rust helper binary

Updated: 2026-10-13 21:51 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

## 決定與原因

- Helper binary, not a dynamic module; build-hint error when not built, no `sh` + `unzip`
  fallback; `zip` crate allowed — user answers, 2026-10-13.
- Crate dir `rust/libsrc-classes/`, deployed to `rust/lib/libsrc-classes` (next to
  `question-queue-core.so`); `/rust/libsrc-classes/target/` needs its own line in the root
  `.gitignore` (the existing rule names only question-queue-core's target).
- The equivalence oracle in `check-equivalence.el` is a frozen copy of today's listing and
  parse functions, so deleting them from the engine does not delete the oracle.

## 下一步

Slice 1: scaffold `rust/libsrc-classes/` (Cargo.toml with the rust-build-speed profiles,
`.cargo/config.toml` for mold, Makefile with the five targets, `SUBPROJECTS` entry,
`.gitignore` line); the binary reads the jar paths it is given and prints class → `g:a:v`
plus unreadable jars; the engine's class-index step runs it; `check-equivalence.el` passes on
the kjw-web fixture. Moves 驗收條件 1, 2, 8 to passing. Commit:
`libsrc: list jar classes with a Rust helper`.

## 卡住・待確認

- Unrelated uncommitted changes in the repo (staged rename `SPEC.md` →
  `tasks/done/20260520-dape/SPEC.md`, modified `tasks/done/README.md`, untracked
  `AGENTS.md`, `plans/`, `records/`): not this spec's; slice commits name only their own
  paths.
