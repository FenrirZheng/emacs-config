# rust/ — Rust tree-sitter grammar workspace

Root for Rust-related repos and build tooling used by this Emacs config. Right
now it holds one thing: a standalone deployer that builds the **Rust
tree-sitter grammar** pinned to an **ABI-14** tag, because Emacs 30.1 on Debian
trixie can't load the ABI-15 grammar that upstream now ships by default.

## The problem this solves

Emacs decides the maximum tree-sitter grammar ABI it will load at **compile
time**, from the `libtree-sitter` it was linked against:

```
M-: (treesit-library-abi-version)   ;; => 14   (this machine)
```

That `14` comes from Debian trixie's `libtree-sitter 0.22.6` — the newest the
distro ships. `tree-sitter-rust` master has been **ABI 15** since `v0.24.0`, so
a grammar built from master loads as:

```
M-: (treesit-language-available-p 'rust t)   ;; => (nil version-mismatch 15)
```

and `rust-ts-mode` can't start. **`apt upgrade` does not help** — both
`emacs-gtk` and `libtree-sitter` are already at their newest trixie candidate,
and the cap is baked into the Emacs binary anyway (swapping the runtime `.so`
wouldn't change it; only a recompile against `libtree-sitter >= 0.24` would).
Pinning the grammar to the newest ABI-14 tag is the proportionate fix.

> ABI 14 is not a downgrade in any user-visible sense — ABI 15 is an internal
> grammar-format bump for grammar authors, not a parsing-quality improvement.
> The pins are also forward-compatible: a future Emacs built against a newer
> libtree-sitter (cap → 15) still loads these ABI-14 grammars.

## Layout

```
rust/
├── README.md                    # this file (tracked)
├── install-treesit-grammar.sh   # build + deploy the grammar (tracked)
├── tree-sitter-rust/            # cloned upstream grammar source (gitignored)
└── build/                       # parser.o / scanner.o / .so (gitignored)
```

The two generated dirs are excluded in the repo-root
[.gitignore](../.gitignore) (the `/rust/...` block), mirroring how
[cpp/](../cpp/README.md) keeps its `build/` and `lib/` out of git.

## Usage

```bash
~/.emacs.d/rust/install-treesit-grammar.sh
```

It clones (or updates) `tree-sitter-rust` at the pinned tag, compiles
`parser.c` + `scanner.c` with `cc`, installs
`libtree-sitter-rust.so` into [../tree-sitter/](../tree-sitter/) (where
`treesit-extra-load-path` points), and verifies the result in a throwaway
`emacs -Q --batch` so a bad build fails here rather than at first `.rs` visit.

If an Emacs **daemon** is already running it keeps the old grammar handle
`dlopen`'d; restart it to pick up the new `.so` (the script prints the exact
commands, including the unsaved-buffer check).

## Keeping the pin in sync

The grammar tag is declared in **two** places that must agree:

| where | what | purpose |
|---|---|---|
| `GRAMMAR_TAG` in [install-treesit-grammar.sh](install-treesit-grammar.sh) | `v0.23.3` | this manual deployer |
| `abi14-revision` in [../lisp/languages/init-rust.el](../lisp/languages/init-rust.el) | `v0.23.3` | what `treesit-auto` auto-installs on first `.rs` visit |

To bump (e.g. when a newer ABI-14 tag appears, or after Emacs gains an ABI-15
runtime): change both, re-run the script, restart the daemon.

## Related

- [lisp/languages/init-rust.el](../lisp/languages/init-rust.el) — Rust mode /
  Eglot / rust-analyzer config and the `treesit-auto` ABI-14 pin.
- [cpp/README.md](../cpp/README.md) — the analogous C++ dynamic-module
  workspace this folder's tracked/ignored split is modeled on.
- Project notes: [../CLAUDE.md](../CLAUDE.md) (tree-sitter grammar handling,
  the `css`/`json`/`lua` ABI-15 exclusions).
