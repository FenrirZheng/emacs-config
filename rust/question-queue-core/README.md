# question-queue-core — Emacs dynamic module (Rust)

The native half of the **question-queue** workflow: capture a highlighted Emacs
region + a typed question, assemble a markdown request, and drop it atomically
into an external file-queue's `input/` directory; later, clean the answer that
the queue writes to `output/`. The Elisp front-end that drives it (region
capture, the `output/` `file-notify` watch, display) is
[`lisp/question-queue.el`](../../lisp/question-queue.el).

This mirrors the C++ [`cpp/junit-core`](../../cpp/junit-core/README.md) split —
**native = pure compute + local file I/O, never launches a process or watches a
directory** — but is written in Rust against the raw emacs-module ABI.

## Build

```bash
make            # cargo build --release + deploy to ../lib/question-queue-core.so
make verify     # build + dlopen in a throwaway `emacs -Q --batch`, call qq-core-version
make clean      # cargo clean + remove the deployed .so
make distclean  # also remove target/
```

Output: `rust/lib/question-queue-core.so` (the `lib` prefix is dropped because
Emacs `module-load` wants the bare FEATURE name). From Emacs the front-end loads
it on first use, or `M-x question-queue-build`.

Requirements: a Rust toolchain (`cargo`), `libclang` (bindgen), and the Emacs
module header at `/usr/include/emacs-module.h` (present on Debian trixie — the
same header `cpp/junit-core` compiles against).

## How the bindings are generated ("codegen")

[`build.rs`](build.rs) runs **bindgen** over [`wrapper.h`](wrapper.h) (which
`#include`s the system `<emacs-module.h>`) to emit raw FFI struct layouts plus
the opaque `emacs_value` into `$OUT_DIR/bindings.rs`. We hand-write the unsafe
marshalling on top of those in [`src/emacs.rs`](src/emacs.rs).

One subtlety worth knowing: the env's function pointers mention `ptrdiff_t`,
which different bindgen versions spell as `isize` or `c_long`. To stay version-
independent, `emacs.rs` `transmute`s each env fn-pointer to a locally-declared,
ABI-stable `fn` type before calling it (fn-pointer transmute is size/ABI-safe).

## Native API (registered by `emacs_module_init`)

| function | args | returns | effect |
|---|---|---|---|
| `qq-core-submit` | `REGION QUESTION LANG SOURCE-FILE INPUT-DIR` | basename string | build the markdown, generate a unique `YYYYMMDD-HHMMSS-<6hex>.md` name, **atomically** write (temp + `rename`, firing the monitor's `moved_to`) into `INPUT-DIR`. `SOURCE-FILE` may be nil. Signals an Elisp `error` on bad input / I/O failure. |
| `qq-core-parse-answer` | `OUTPUT-TEXT` | answer body string | trim; unwrap a single enclosing code fence; strip an echoed YAML front-matter block. |
| `qq-core-version` | – | version string | sanity probe used by `make verify`. |

Every trampoline wraps its body in `catch_unwind` so a Rust panic becomes an
Elisp `error` rather than unwinding across the FFI boundary and killing Emacs.

## Source layout

| file | role |
|---|---|
| [`build.rs`](build.rs) | bindgen codegen of the emacs-module ABI |
| [`src/lib.rs`](src/lib.rs) | `emacs_module_init`, `plugin_is_GPL_compatible`, fn registration, trampolines |
| [`src/emacs.rs`](src/emacs.rs) | safe-ish `Env` wrapper over the raw `emacs_env` fn-pointers |
| [`src/request.rs`](src/request.rs) | markdown assembly + unique filename + atomic write |
| [`src/answer.rs`](src/answer.rs) | answer-text normalisation (+ unit tests: `cargo test`) |

## Related

- [`lisp/question-queue.el`](../../lisp/question-queue.el) — the Elisp front-end.
- [`cpp/junit-core/README.md`](../../cpp/junit-core/README.md) — the analogous
  C++ dynamic module this one's structure follows.
- Workspace overview: [`rust/README.md`](../README.md).
