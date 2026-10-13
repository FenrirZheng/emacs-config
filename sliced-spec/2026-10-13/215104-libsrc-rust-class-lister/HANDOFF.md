# Handoff: libsrc — list jar classes with a Rust helper binary

Updated: 2026-10-13 23:35 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

## 決定與原因

- Helper binary, not a dynamic module; build-hint error when not built, no `sh` + `unzip`
  fallback; `zip` crate allowed — user answers, 2026-10-13.
- Crate dir `rust/libsrc-classes/`, deployed to `rust/lib/libsrc-classes` (next to
  `question-queue-core.so`); `/rust/libsrc-classes/target/` has its own line in the root
  `.gitignore`.
- The equivalence oracle in `check-equivalence.el` is a frozen copy of the listing and
  parse functions as of `ddf3059`, so deleting them from the engine does not delete the
  oracle.
- Helper output is one Lisp form, `(:class-index #s(hash-table …) :unreadable (…))`, which
  the engine `read`s. GAV and simple-name rules live in the helper (Rust tests mirror the
  old ERT cases, plus case-fold corners checked against the old Elisp); `:unparsed` stays
  computed in Elisp, because `fenrir/libsrc--jar-gav` has other callers.
- The engine's old listing parsers (`--class-entry-name`, `--parse-listing`,
  `--listing-failures`, `--build-class-index`) are deleted; their ERT tests moved to
  `cargo test` or were rewritten against the helper's output form.

## 下一步

Finish slice 1 once the SPEC diff below is decided: make `check-equivalence.el` apply the
approved rule, re-run it, and commit `libsrc: list jar classes with a Rust helper`
(along with doc lines for `_doc/TAGS.md`, `_doc/BOOTSTRAP.md`, `rust/README.md`).
Moves 驗收條件 1, 2, 8 to passing.

## 卡住・待確認

- **Needs user — SPEC diff (deviation rule).** Criterion 2 fails on one key. Debian
  `unzip -Z1` (UnZip 6.00) prints the UTF-8 entry `javaslang/λ.class` in
  `kotlin-compiler-embeddable-2.0.0.jar` as `javaslang/++.class`, so the old index had
  `++`, and the helper has `λ`. Everything else matches (35,212 = 35,212 classes,
  0 unreadable, 0 unparsed). SPEC facts found wrong at the same time: kjw-web's 103 jars
  are all in the Gradle cache (none in `~/.m2`), and kjw-web is a Gradle build with no
  `pom.xml`, so criterion 7's step and side effect are wrong.
- Uncommitted slice-1 work (all tests pass except criterion 2): new
  `rust/libsrc-classes/`, `check-equivalence.el`; modified `.gitignore`, `rust/Makefile`,
  `lisp/languages/fenrir-libsrc.el`, `test/libsrc-test.el`.
- Unrelated uncommitted changes in the repo (staged rename `SPEC.md` →
  `tasks/done/20260520-dape/SPEC.md`, modified `tasks/done/README.md`, untracked
  `AGENTS.md`, `forge-database.sqlite`, `plans/`, `records/`): not this spec's; slice
  commits name only their own paths.
