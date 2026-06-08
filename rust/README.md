# rust/ — Rust tooling workspace for this Emacs config

A multi-project workspace for Rust code that **supports this Emacs config**
(tree-sitter grammars, future Rust-based dynamic modules / helper binaries).
Each subproject lives in its own subdirectory with a self-contained
[`Makefile`](treesit-grammar/Makefile); the top-level [`Makefile`](Makefile) is
a thin **aggregator** that forwards `all` / `install` / `verify` / `clean` /
`distclean` to every subproject (recursive make). This is the Make analogue of
how [cpp/](../cpp/README.md) aggregates C++ dynamic modules via
`add_subdirectory`.

> **Scope:** only code that exists *for the Emacs config* belongs here.
> Unrelated standalone Rust apps/libraries are untracked clones under `~/code/`
> (see the parent [~/CLAUDE.md](../../CLAUDE.md) strategy) — putting them here
> would pollute the config repo. The directory name is mostly historical: it
> hosts actual Rust crates **and** the tree-sitter grammar deployers, which are
> `cc` builds of C grammar sources (not Rust). They live here as a pragmatic
> exception — the original `treesit-grammar` started in this workspace and the
> Make fan-out is a clean home for them.

## Subprojects

| dir | what | build |
|---|---|---|
| [`treesit-grammar/`](treesit-grammar/README.md) | ABI-14-pinned **Rust** tree-sitter grammar deployer (`tree-sitter-rust` @ `v0.23.3`) | `make -C treesit-grammar` |
| [`treesit-grammar-c/`](treesit-grammar-c/README.md) | ABI-14-pinned **C** tree-sitter grammar deployer (`tree-sitter-c` @ `v0.23.6`; parser-only) | `make -C treesit-grammar-c` |
| [`treesit-grammar-lua/`](treesit-grammar-lua/README.md) | ABI-14-pinned **Lua** tree-sitter grammar deployer (`tree-sitter-lua` @ `v0.3.0`; has `scanner.c`) | `make -C treesit-grammar-lua` |
| [`question-queue-core/`](question-queue-core/README.md) | Emacs **dynamic module** (raw emacs-module ABI via bindgen): assemble a region+question markdown file, atomically drop it into a question-queue `input/` dir, parse the answer back. Front-end: [`lisp/question-queue.el`](../lisp/question-queue.el) | `make -C question-queue-core` |

> Why three near-identical grammar Makefiles instead of one parameterized build:
> each subproject is self-contained per this workspace's convention, and they
> differ only in three config vars (`LANG_NAME` / `REPO_URL` / `GRAMMAR_TAG`) —
> the recipe auto-detects whether a grammar ships a `scanner.c`. Each grammar's
> tag is also mirrored in its language module's `abi14-revision` recipe pin
> (see each subproject README's "Keeping the pin in sync").

## Layout

```
rust/
├── README.md          # this file (tracked)
├── Makefile           # aggregator: forwards targets to each subproject (tracked)
├── lib/               # deployed dynamic modules, e.g. question-queue-core.so (gitignored)
├── treesit-grammar/        # Rust grammar deployer — see its own README
│   ├── Makefile / README.md
│   ├── tree-sitter-rust/   # cloned upstream grammar source (gitignored)
│   └── build/              # parser.o / scanner.o / .so (gitignored)
├── treesit-grammar-c/      # C grammar deployer (parser-only)
│   ├── Makefile / README.md
│   ├── tree-sitter-c/      # cloned upstream grammar source (gitignored)
│   └── build/              # parser.o / .so (gitignored)
├── treesit-grammar-lua/    # Lua grammar deployer
│   ├── Makefile / README.md
│   ├── tree-sitter-lua/    # cloned upstream grammar source (gitignored)
│   └── build/              # parser.o / scanner.o / .so (gitignored)
└── question-queue-core/    # cargo cdylib Emacs dynamic module — see its own README
    ├── Cargo.toml / build.rs / wrapper.h / Makefile (tracked)
    ├── src/                # lib.rs / emacs.rs / request.rs / answer.rs (tracked)
    └── target/             # cargo build dir (gitignored)
```

Cargo-built modules deploy to the workspace-wide `rust/lib/` (the Make analogue
of [cpp/lib/](../cpp/README.md)); Emacs `module-load`s them from there.
Per-subproject generated dirs are excluded in the repo-root
[.gitignore](../.gitignore) (the `/rust/...` block: `lib/`, each grammar's
checkout + `build/`, and `question-queue-core/target/`).

## Usage

```bash
make -C ~/.emacs.d/rust              # build every subproject (default goal)
make -C ~/.emacs.d/rust verify       # build + load-check each
make -C ~/.emacs.d/rust help         # list subprojects + targets
```

Command-line variables propagate to the sub-makes, e.g.
`make -C ~/.emacs.d/rust GRAMMAR_TAG=v0.23.4`. To build a single subproject
directly, `cd` into it (or `make -C ~/.emacs.d/rust/<name>`).

## Adding a subproject

1. Create `rust/<name>/` with a `Makefile` that exposes the standard phony
   targets (`all` / `install` / `verify` / `clean` / `distclean`).
2. Add `<name>` to `SUBPROJECTS` in the top-level [`Makefile`](Makefile).
3. If it generates gitignored artefacts, add a `/rust/<name>/...` block to the
   repo-root [.gitignore](../.gitignore).
4. Give it its own `README.md` and link it from the Subprojects table above.

The build is deliberately delegated, not centralised: a future cargo crate's
"build" is just `cargo build --release`, nothing like the grammar's hand-rolled
`cc` — so each subproject owns its recipe and the aggregator stays
build-agnostic.

## Related

- [cpp/README.md](../cpp/README.md) — the analogous C++ dynamic-module
  workspace this folder's structure is modeled on.
- Project notes: [../CLAUDE.md](../CLAUDE.md).
