# Handoff: libsrc — list jar classes with a Rust helper binary

Updated: 2026-10-14 00:12 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

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

The acceptance gate, as a whole new run. Criterion 7 (daemon `C-c g l` on kjw-web's
`build.gradle.kts`) is manual and runs kjw-web's `gradlew`; the daemon must first
`load-file` `lisp/languages/fenrir-libsrc.el`. A real pass rewrites
`~/.cache/fenrir-libsrc/proj/0c3182fd….eld` with a fresh mtime and `:resolved-at` —
check that alongside the `*Messages*` line.

## 卡住・待確認

- First gate run, 2026-10-14 at `9570501`: verifier passed 1–6 and 8–10 (criterion 2 printed
  35212 classes; helper 68 ms, step 124 ms). It wrote `Status: implemented` (`c80e1ce`) on a
  reported criterion-7 pass that the evidence contradicted — the daemon had never loaded the
  new `fenrir-libsrc.el` (`fenrir/libsrc-classes-program` unbound), `*Messages*` had no
  `classes indexed` line, and the state file still held its 2026-10-07 `:resolved-at`.
  Reverted on the user's yes (`60d4b95`, `687926d`). Those passes do not carry: the next gate
  is a whole run.
- 驗收條件 and 限制 differ from the approval commit `ddf3059` (amended in `b9c58cd`); the user
  accepted them in the first run, but the next gate's step 2 asks again.
- Untracked, not this spec's: `AGENTS.md`, `plans/`, `records/`.
