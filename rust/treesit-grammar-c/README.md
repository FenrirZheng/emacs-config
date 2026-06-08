# rust/treesit-grammar-c — ABI-14 C tree-sitter grammar deployer

A standalone deployer that builds the **C tree-sitter grammar** pinned to an
**ABI-14** tag, because Emacs 30.1 on Debian trixie can't load the ABI-15
grammar that upstream now ships. Sibling of the original Rust deployer
([rust/treesit-grammar/](../treesit-grammar/README.md)); one subproject of the
[rust/ workspace](../README.md), driven by [`Makefile`](Makefile).

## The problem this solves

Emacs decides the maximum tree-sitter grammar ABI it will load at **compile
time**, from the `libtree-sitter` it was linked against:

```
M-: (treesit-library-abi-version)            ;; => 14   (this machine)
M-: (treesit-language-available-p 'c t)      ;; => (nil version-mismatch 15)
```

That `14` comes from Debian trixie's `libtree-sitter 0.22.6`. `tree-sitter-c`
jumped to **ABI 15** at `v0.24.0`, so a grammar built from a recent tag triggers

```
■ Warning (treesit): Cannot activate tree-sitter, because language grammar
  for c is unavailable (version-mismatch): 15
```

and `c-ts-mode` falls over. **`apt upgrade` does not help** — both `emacs-gtk`
and `libtree-sitter` are already at their newest trixie candidate, and the cap
is baked into the Emacs binary. Pinning the grammar to the newest ABI-14 tag is
the proportionate fix. **`v0.23.6`** is that tag (`v0.24.0` is the first
ABI-15 one); all of `v0.23.0`–`v0.23.6` are ABI 14.

> ABI 14 is not a downgrade in any user-visible sense — ABI 15 is an internal
> grammar-format bump for grammar authors, not a parsing-quality improvement.
> The pin is forward-compatible: a future Emacs built against a newer
> libtree-sitter (cap → 15) still loads this ABI-14 grammar.

Note: `tree-sitter-c` is **parser-only** — it ships no external scanner
(`scanner.c`), unlike rust / lua. The [Makefile](Makefile) compiles `parser.c`
alone (and links a scanner only if one ever appears).

## Layout

```
rust/treesit-grammar-c/
├── README.md          # this file (tracked)
├── Makefile           # build + deploy the grammar (tracked)
├── tree-sitter-c/     # cloned upstream grammar source (gitignored)
└── build/             # parser.o / .so (gitignored)
```

The two generated dirs are excluded in the repo-root
[.gitignore](../../.gitignore) (the `/rust/treesit-grammar-c/...` block).

## Usage

```bash
make -C ~/.emacs.d/rust/treesit-grammar-c   # fetch + build + install + verify
```

(or `make -C ~/.emacs.d/rust` from the [workspace aggregator](../Makefile),
which forwards to every subproject).

Other targets: `make install` (skip the load-check), `make clean` (drop
`build/`), `make distclean` (also drop the checkout + the deployed `.so`), and
`make GRAMMAR_TAG=v0.23.5` to override the pin for a one-off build.

If an Emacs **daemon** is already running it keeps the old grammar handle
`dlopen`'d; restart it to pick up the new `.so` (`make` prints the exact
commands, including the unsaved-buffer check).

## Keeping the pin in sync

The grammar tag is declared in **two** places that must agree:

| where | what | purpose |
|---|---|---|
| `GRAMMAR_TAG` in [Makefile](Makefile) | `v0.23.6` | this manual deployer |
| `abi14-revision` in [../../lisp/languages/init-c-cpp.el](../../lisp/languages/init-c-cpp.el) | `v0.23.6` | what `treesit-auto` auto-installs on first `.c` visit |

To bump (e.g. when a newer ABI-14 tag appears, or after Emacs gains an ABI-15
runtime): change both, re-run `make`, restart the daemon.

## Related

- [lisp/languages/init-c-cpp.el](../../lisp/languages/init-c-cpp.el) — C / C++
  mode / Eglot / clangd config and the `treesit-auto` ABI-14 pin.
- [rust/treesit-grammar/README.md](../treesit-grammar/README.md) — the original
  Rust deployer this one mirrors.
- Project notes: [../../CLAUDE.md](../../CLAUDE.md) (tree-sitter grammar handling,
  the ABI-14 pins, the `css`/`json` ABI-15 exclusions).
