# libsrc-classes — jar class lister for fenrir-libsrc

A standalone helper binary (not an Emacs module) that the libsrc engine,
[`lisp/languages/fenrir-libsrc.el`](../../lisp/languages/fenrir-libsrc.el), runs on
`C-c g l` to build a project's class index. It replaced `sh` + `unzip -Z1` per jar
plus line-by-line Elisp parsing (spec:
[`sliced-spec/2026-10-13/215104-libsrc-rust-class-lister`](../../sliced-spec/2026-10-13/215104-libsrc-rust-class-lister/SPEC.md)).

```
libsrc-classes JAR...
```

It reads each jar's zip central directory (entry names only, no decompression) and
prints **one Lisp form** on stdout, which the engine `read`s:

```elisp
(:class-index #s(hash-table test equal data ("Foo" ("org.x:a:1.0" "org.y:b:2.0") ...))
 :unreadable ("/path/broken.jar" ...))
```

- **Keys** are simple class names: package and `$Inner` stripped, `module-info` /
  `package-info` skipped. **Values** are `g:a:v` lists in jar order, without duplicates.
- **GAV** comes from the jar path: `~/.m2/repository/<g/slashed>/<a>/<v>/<a>-<v>.jar` or
  the Gradle cache `files-2.1/<g.dotted>/<a>/<v>/<hash>/<a>-<v>.jar`. Classifier jars
  and project build output have no GAV, so they are opened but not indexed.
- The rules reproduce the Elisp regexps they replaced, including Emacs's default
  `case-fold-search` (`Foo.CLASS`, `/Repository/` match). The one known deliberate
  difference: a non-ASCII class name keeps its real spelling (`λ`), where Debian
  `unzip -Z1` printed one `+` per byte (`++`).
- Exit 0 whenever the form was written, even if every jar was unreadable; the engine
  decides what to store.

## Build

```bash
make -C ~/.emacs.d/rust/libsrc-classes          # -> ~/.emacs.d/rust/lib/libsrc-classes
make -C ~/.emacs.d/rust/libsrc-classes verify   # + check its output parses in Emacs
cd ~/.emacs.d/rust/libsrc-classes && cargo test
```

Until it is built, `C-c g l` refuses and names the `make` command. The engine finds the
binary through `fenrir/libsrc-classes-program`.

The one dependency is `zip` with default features off. `.cargo/config.toml` links with
mold. It is read only when cargo runs with this directory as cwd, which the Makefile
does; check with `readelf -p .comment ../lib/libsrc-classes`.

## Speed

Measured 2026-10-13 23:4x (Asia/Taipei) on kjw-web's 103 jars (35,212 classes), 12 cores,
machine load average 3.5–6 from other work, so treat these as upper bounds:

- `sliced-spec/…/bench.el`, medians of 5 runs after one warm-up: the helper alone 73–90 ms,
  the whole step (process start to the index parsed in Elisp) 130–151 ms, against the
  0.79 s of `sh` + `unzip -Z1` + Elisp parse it replaced.
- Inside the helper, medians of 10: reading the jars 36 ms (parallel, one thread per core;
  the 57 MB `kotlin-compiler-embeddable` jar alone sets the floor), indexing 21 ms, writing
  the form 11 ms — measured before the FNV hasher and the single write, which cut the
  shell-timed median from 77 to 70 ms.

## Build profiles

From the `rust-build-speed` new-workspace scaffold: `release` uses thin LTO, `dev` uses
`debug = "line-tables-only"`, and `quick` is an incremental, non-LTO release.

`bash ~/.claude/skills/rust-build-speed/scripts/measure.sh --lto --real-edit .`, run
2026-10-13 23:49 (Asia/Taipei), rustc 1.98.0, mold 2.37.1, 12 cores, load average 6.0, real
edits (probe functions appended, sources restored byte-identically and checked with
`diff` against a backup):

| step | time |
|---|---|
| no-op build | 0.05 s |
| edit `main.rs` → `cargo check` | 0.14 s |
| edit `main.rs` → `cargo build` | 0.34 s |
| edit `lib.rs` → `cargo build` | 0.67 s |
| edit `lib.rs` → `cargo build --release` (thin LTO) | 5.63 s |
| same, `lto = false` / `thin` / `true` | 1.66 s / 5.52 s / 7.10 s |
| same, `--profile quick` | 0.61 s |

The dev loop is under a second, so there is nothing to tune there. For an optimized build
while iterating, use `cargo build --profile quick` (9× faster than the thin-LTO release).
`make` keeps building the thin-LTO `release` that it deploys.
