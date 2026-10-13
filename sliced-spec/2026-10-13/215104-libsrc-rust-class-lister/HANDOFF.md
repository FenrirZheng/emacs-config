# Handoff: libsrc — list jar classes with a Rust helper binary

Updated: 2026-10-14 00:01 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Acceptance gate at `9570501`: criteria 1–6, 8–10 pass (verifier); 7 pass by the user
  (daemon `C-c g l`: 103 jars, 35212 classes = criterion 2's count). `Status: implemented` —
  commit `spec: mark libsrc-rust-class-lister implemented`.
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

- Stray file, not from this spec's code: `~/.cache/fenrir-libsrc/proj/e7ad2368a9224d8bdc303b4ac58430620eeb43f7.eld`
  (2.7 MB, 2026-10-13 21:45) — a copy of kjw-web's state keyed by `/tmp/x`, written by a
  timing probe of `fenrir/libsrc--write-state` in the session before this spec. Harmless
  (no root `/tmp/x` exists); delete on the user's yes.
- Untracked, not this spec's: `AGENTS.md`, `plans/`, `records/`. (The staged dape-spec
  rename and `tasks/done/README.md` were committed as `docs: archive the dape spec under
  tasks/done`, on the user's yes.)
