# Spec: libsrc — list jar classes with a Rust helper binary

Status: implemented
Date: 2026-10-13 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)

## 目標

- The libsrc engine's class-index step (simple class name → the `g:a:v` artifacts defining
  it, in [`lisp/languages/fenrir-libsrc.el`](../../../lisp/languages/fenrir-libsrc.el)) gets
  its class → `g:a:v` data straight from one Rust helper binary under [`rust/`](../../../rust/),
  instead of `sh` + `unzip -Z1` per jar plus line-by-line Elisp parsing.
- The stored per-project state is the same as today's for the same jars: same class index,
  same `:unreadable` jars, same `:unparsed` jars. Existing state files stay readable; no
  forced re-sync.
- The step gets faster. Baseline measured 2026-10-13 on kjw-web's 103 jars (69,614 listing
  lines, 35,212 classes): `unzip` loop 0.39 s + Elisp parse 0.40 s (0.35 s native-compiled).
- The crate is scaffolded per the
  [`rust-build-speed`](../../../../.claude/skills/rust-build-speed/SKILL.md) new-workspace
  defaults, and its edit→build loop is measured, not assumed.
- A fresh clone that has not built the helper gets a clear build hint, not a silent empty
  index — the convention the repo's other native parts already follow.

## 不做的事

- No Emacs dynamic module: the helper is a standalone binary run as a subprocess.
- `unzip` is still used to extract `-sources.jar` files; only the class listing moves.
- No fallback to the old `sh` + `unzip -Z1` listing when the helper is missing.
- No change to classpath resolution (Maven / Gradle), artifact fetch/extract, gtags builds,
  or `M-.` lookup.
- No change to the state file format.

## 驗收條件

Fixture input, used by 2, 3 and 7: the `:jars` list stored in kjw-web's state file
`~/.cache/fenrir-libsrc/proj/0c3182fdef74a5edb107922b61083d9364653696.eld` (root
`/home/fenrir/code/ig_lottery/repos/lottery/kjw-web/`, 103 jars, all in the Gradle cache
`~/.gradle/caches/modules-2/files-2.1/`, as of 2026-10-13). Batch runs use `emacs -Q --batch`; no `.elc` is left behind.

1. `make -C rust/libsrc-classes distclean`, then `make -C rust/libsrc-classes verify` → exits
   0, and `rust/lib/libsrc-classes` exists and is executable — test: the crate Makefile's
   `verify` target — 副作用: deletes and rewrites `rust/libsrc-classes/target/` and
   `rust/lib/libsrc-classes` (both gitignored)
2. Fixture input → the class index, `:unreadable` and `:unparsed` produced by the new step
   are `equal` to those produced by a frozen copy of today's `sh` + `unzip -Z1` + Elisp parse
   pipeline (same keys, same `g:a:v` lists in the same order) — except a class whose entry
   name `unzip -Z1` cannot print (non-ASCII, shown as one `+` per byte): it appears under its
   real name, and the script lists each such pair — test:
   `sliced-spec/2026-10-13/215104-libsrc-rust-class-lister/check-equivalence.el` — 副作用:
   none
3. Fixture input, 5 runs after one warm-up → median wall time of the whole new step (process
   start to the class index ready in Elisp) ≤ 200 ms, and of the helper alone ≤ 100 ms;
   the script prints both medians and the 0.79 s baseline — test:
   `sliced-spec/2026-10-13/215104-libsrc-rust-class-lister/bench.el` — 副作用: none
4. Jars `/tmp/libsrc-classes-fixture/broken.jar` (a file holding the text `not a zip`),
   `/tmp/libsrc-classes-fixture/missing.jar` (absent) and the first 3 fixture jars → the
   index holds the 3 good jars' classes; `:unreadable` is exactly the two `/tmp` paths;
   the `*libsrc*` log names both — test: `rust/libsrc-classes` `cargo test` plus
   `test/libsrc-test.el` — 副作用: writes `/tmp/libsrc-classes-fixture/`
5. Only `/tmp/libsrc-classes-fixture/broken.jar` and `/tmp/libsrc-classes-fixture/missing.jar`
   → no state is stored, the resolving entry is released, and the message says no jar
   could be listed — test: `test/libsrc-test.el` — 副作用: writes
   `/tmp/libsrc-classes-fixture/`
6. Helper program path set to `/nonexistent/libsrc-classes` → the index step stores no
   state, releases the resolving entry, and the message names `make -C rust/libsrc-classes`
   — test: `test/libsrc-test.el` — 副作用: none
7. Daemon: reload `lisp/languages/fenrir-libsrc.el`, open
   `/home/fenrir/code/ig_lottery/repos/lottery/kjw-web/build.gradle.kts`, `C-c g l` → `*Messages*`
   shows `libsrc: 103 jars, <N> classes indexed`, with `<N>` equal to the class count
   criterion 2 printed — test: manual (needs the live daemon and an offline-capable Gradle) —
   副作用: runs kjw-web's `gradlew` with the libsrc init script (may write kjw-web's
   `.gradle/` and `build/`), rewrites
   `~/.cache/fenrir-libsrc/proj/0c3182fdef74a5edb107922b61083d9364653696.eld`
8. `emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit` → 0 unexpected
   results; `cargo test --manifest-path rust/libsrc-classes/Cargo.toml` → all pass — test:
   those two commands — 副作用: writes `rust/libsrc-classes/target/` (gitignored) and temp
   dirs under `/tmp`
9. `readelf -p .comment rust/lib/libsrc-classes` → names mold; `rust/libsrc-classes/README.md`
   has a dated section with the numbers `bash
   ~/.claude/skills/rust-build-speed/scripts/measure.sh` printed for the crate (no-op build,
   edit→check, edit→build) — test: manual (one command, one read) — 副作用: none
10. `ug -n 'libsrc-classes' rust/README.md rust/Makefile _doc/BOOTSTRAP.md _doc/TAGS.md` →
    each file has at least one hit: the subproject table, `SUBPROJECTS`, the fresh-clone
    build step, the class-index description — test: manual (one grep) — 副作用: none

## 限制

- **Existing environment to reuse** (user confirmed 2026-10-13):
  - the [`rust/`](../../../rust/README.md) workspace: one self-contained Makefile per
    subproject exposing `all` / `install` / `verify` / `clean` / `distclean`, listed in
    [`rust/Makefile`](../../../rust/Makefile)'s `SUBPROJECTS`; build output gitignored;
  - rustup `rustc 1.98.0` and `/usr/bin/mold`, already installed;
  - the Emacs 30.1 daemon, and kjw-web with its jars in the Gradle module cache as the
    literal acceptance input.
  Nothing else is created.
- One crates.io dependency is allowed: `zip`, default features off (user approved
  2026-10-13). Any other crate is a SPEC change.
- Simple-name and GAV rules stay those of today's engine and its tests: package and
  `$Inner` stripped, `module-info` / `package-info` skipped, `~/.m2` (slashed groupId) and
  Gradle `files-2.1` (dotted groupId) layouts, classifier jars have no GAV.
- The ERT suite runs without the helper built (the pure layer stays testable from `lisp/`
  alone).
- Build profiles follow the `rust-build-speed` new-workspace scaffold; they are labelled
  unmeasured until criterion 9's numbers exist.

## 待決問題

- kjw-web's jars are all Gradle-cache jars, so the `~/.m2` layout is covered only by unit
  tests — default if unanswered: unit-test coverage is enough.
