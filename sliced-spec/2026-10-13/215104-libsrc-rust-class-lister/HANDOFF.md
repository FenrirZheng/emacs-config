# Handoff: libsrc — list jar classes with a Rust helper binary

Updated: 2026-10-13 23:38 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Slice 1: crate `rust/libsrc-classes/`, the engine's class-index step runs it, frozen-oracle
  `check-equivalence.el`, ERT + `cargo test`, docs — commit
  `libsrc: list jar classes with a Rust helper`. Checked: criterion 1 (distclean + verify), 2
  (EQUIVALENT, one accepted `++` → `λ` pair), 8 (ERT 34/34, cargo 8/8), 10 (grep hits in
  all four files); criterion 6's ERT test exists (`libsrc-index-helper-not-built`).

## 決定與原因

- Helper binary, not a dynamic module; build-hint error when not built, no `sh` + `unzip`
  fallback; `zip` crate allowed — user answers, 2026-10-13.
- Non-ASCII class names keep their real spelling (`λ`), not Debian `unzip -Z1`'s one `+` per
  byte; criterion 2 and the Gradle fixture facts amended — user approved the SPEC diff,
  2026-10-13.
- Crate dir `rust/libsrc-classes/`, deployed to `rust/lib/libsrc-classes`, found through
  `fenrir/libsrc-classes-program`; `/rust/libsrc-classes/target/` has its own `.gitignore`
  line. Cargo must run with the crate dir as cwd for `.cargo/config.toml` (mold) to apply —
  the Makefile `cd`s.
- Helper output is one Lisp form, `(:class-index #s(hash-table …) :unreadable (…))`, which
  the engine `read`s (`fenrir/libsrc--parse-classes-output`). GAV and simple-name rules
  live in the helper, case-folded like the old regexps; `:unparsed` stays in Elisp because
  `fenrir/libsrc--jar-gav` has other callers.
- The engine's old listing parsers are deleted; `check-equivalence.el` holds the frozen copy.

## 下一步

Slice 2: `bench.el` (criterion 3: 5 runs after a warm-up on the fixture, medians for the
whole step and the helper alone, plus the 0.79 s baseline); the `/tmp/libsrc-classes-fixture`
broken/missing-jar cases as a Rust integration test and ERT (criteria 4, 5); run
`measure.sh` on the crate and record its dated numbers in the crate README, which today says
"Unmeasured" (criterion 9). Commit: `libsrc: benchmark and test the class lister`.

## 卡住・待確認

- Stray file, not from this spec's code: `~/.cache/fenrir-libsrc/proj/e7ad2368a9224d8bdc303b4ac58430620eeb43f7.eld`
  (2.7 MB, 2026-10-13 21:45) — a copy of kjw-web's state keyed by `/tmp/x`, written by a
  timing probe of `fenrir/libsrc--write-state` in the session before this spec. Harmless
  (no root `/tmp/x` exists); delete on the user's yes.
- Unrelated uncommitted changes in the repo (staged rename `SPEC.md` →
  `tasks/done/20260520-dape/SPEC.md`, modified `tasks/done/README.md`, untracked
  `AGENTS.md`, `plans/`, `records/`): not this spec's; slice commits name only their own
  paths.
