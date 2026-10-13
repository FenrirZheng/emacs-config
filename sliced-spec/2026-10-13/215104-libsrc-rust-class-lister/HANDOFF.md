# Handoff: libsrc — list jar classes with a Rust helper binary

Updated: 2026-10-14 00:34 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Acceptance gate (second run) at `2c15f32`: verifier passed 1–6 and 8–10; criterion 7 passed
  in daemon pid 3290934, checked by this session (`*Messages*` line, state file rewritten
  2026-10-14 00:31, 103 jars, 35212 classes = criterion 2's count). `Status: implemented` —
  commit `spec: mark libsrc-rust-class-lister implemented` (`d9982a2`).
- Slice 2: `bench.el`, real-helper broken/missing-jar tests (cargo + ERT), helper speed-ups,
  dated `measure.sh` numbers in the crate README — commit
  `libsrc: benchmark and test the class lister`. Checked: criterion 3 (helper 75 ms, step
  128 ms medians; limits 100 / 200), 4 and 5 (cargo 2/2, ERT 36/36), 9 (mold in `.comment`,
  README section dated 2026-10-13), plus 1, 2, 8 re-run on the final build.
- Slice 1: crate `rust/libsrc-classes/`, the engine's class-index step runs it, frozen-oracle
  `check-equivalence.el`, ERT + `cargo test`, docs — commit
  `libsrc: list jar classes with a Rust helper`.

## 決定與原因

- Helper binary, not a dynamic module; build-hint error when not built, no `sh` + `unzip`
  fallback; `zip` crate allowed — user answers, 2026-10-13.
- Non-ASCII class names keep their real spelling (`λ`), not Debian `unzip -Z1`'s one `+` per
  byte; criterion 2 and the Gradle fixture facts amended — user approved the SPEC diff,
  2026-10-13.
- Crate dir `rust/libsrc-classes/`, deployed to `rust/lib/libsrc-classes`, found through
  `fenrir/libsrc-classes-program`. Cargo must run with the crate dir as cwd for
  `.cargo/config.toml` (mold) to apply — the Makefile `cd`s.
- Helper output is one Lisp form, `(:class-index #s(hash-table …) :unreadable (…))`, which
  the engine `read`s. GAV and simple-name rules live in the helper, case-folded like the old
  regexps; `:unparsed` stays in Elisp because `fenrir/libsrc--jar-gav` has other callers.
- Speed (std only, output byte-identical): jars read on one thread per core with names
  extracted in the threads; GAVs interned; FNV-1a for the name map; the form built in memory
  and written once; `process::exit` skips freeing the index. The machine ran at load 3.5–6
  from other work during every measurement.
- `bench.el`'s "helper alone" discards the output (`call-process` to nil), so it times the
  helper, not Emacs decoding 2.7 MB; "whole step" includes that decoding and the `read`.
- Criterion 4's literal input (first 3 fixture jars) is three Spring Boot starters with no
  classes, so its tests also run a second case with the first class-bearing fixture jar.
- The ERT tests that run the real helper `skip-unless` it is built (and the fixture exists),
  so the suite still runs from `lisp/` alone.

## 下一步

None — the spec is implemented. `ship` can record where it went.

## 卡住・待確認

- The first gate run (`c80e1ce`) was reverted in `60d4b95`: it recorded a criterion-7 pass
  with no evidence behind it. Superseded by `d9982a2`.
- Untracked, not this spec's: `AGENTS.md`, `plans/`, `records/`.
