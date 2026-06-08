# rust/treesit-grammar-lua — ABI-14 Lua tree-sitter grammar deployer

A standalone deployer that builds the **Lua tree-sitter grammar** pinned to an
**ABI-14** tag, because Emacs 30.1 on Debian trixie can't load the ABI-15
grammar that upstream now ships. Sibling of the original Rust deployer
([rust/treesit-grammar/](../treesit-grammar/README.md)); one subproject of the
[rust/ workspace](../README.md), driven by [`Makefile`](Makefile).

## The problem this solves

Emacs decides the maximum tree-sitter grammar ABI it will load at **compile
time**, from the `libtree-sitter` it was linked against:

```
M-: (treesit-library-abi-version)            ;; => 14   (this machine)
M-: (treesit-language-available-p 'lua t)    ;; => (nil version-mismatch 15)
```

That `14` comes from Debian trixie's `libtree-sitter 0.22.6`.
`tree-sitter-grammars/tree-sitter-lua` jumped to **ABI 15** at `v0.4.0`, so a
grammar built from a recent tag / HEAD loads as `(nil version-mismatch 15)` and
`lua-ts-mode` can't start.

**History worth knowing:** an earlier pass (2026-05-19) concluded *"no
ABI-14-compatible tag exists upstream"* and fell back to the regex-based MELPA
`lua-mode`. That was wrong — re-verified **2026-06-08**: `v0.3.0` IS the newest
ABI-14 tag (`v0.4.0` is the first ABI-15 one; `v0.0.16`–`v0.3.0` are ABI 14,
older tags ABI 13). So Lua now follows the same pin-and-rebuild path as rust /
c, and `lua-ts-mode` is promoted back over `lua-mode`.

> ABI 14 is not a downgrade in any user-visible sense — ABI 15 is an internal
> grammar-format bump for grammar authors, not a parsing-quality improvement.
> The pin is forward-compatible: a future Emacs built against a newer
> libtree-sitter (cap → 15) still loads this ABI-14 grammar.

Note: `tree-sitter-lua` ships `parser.c` **and** `scanner.c` (an external
scanner for long strings / long comments); the [Makefile](Makefile) compiles and
links both.

## Layout

```
rust/treesit-grammar-lua/
├── README.md          # this file (tracked)
├── Makefile           # build + deploy the grammar (tracked)
├── tree-sitter-lua/   # cloned upstream grammar source (gitignored)
└── build/             # parser.o / scanner.o / .so (gitignored)
```

The two generated dirs are excluded in the repo-root
[.gitignore](../../.gitignore) (the `/rust/treesit-grammar-lua/...` block).

## Usage

```bash
make -C ~/.emacs.d/rust/treesit-grammar-lua   # fetch + build + install + verify
```

(or `make -C ~/.emacs.d/rust` from the [workspace aggregator](../Makefile),
which forwards to every subproject).

Other targets: `make install` (skip the load-check), `make clean` (drop
`build/`), `make distclean` (also drop the checkout + the deployed `.so`), and
`make GRAMMAR_TAG=v0.2.0` to override the pin for a one-off build.

If an Emacs **daemon** is already running it keeps the old grammar handle
`dlopen`'d; restart it to pick up the new `.so` (`make` prints the exact
commands, including the unsaved-buffer check).

## Keeping the pin in sync

The grammar tag is declared in **two** places that must agree:

| where | what | purpose |
|---|---|---|
| `GRAMMAR_TAG` in [Makefile](Makefile) | `v0.3.0` | this manual deployer |
| `abi14-revision` in [../../lisp/languages/init-lua.el](../../lisp/languages/init-lua.el) | `v0.3.0` | what `treesit-auto` auto-installs on first `.lua` visit |

To bump (e.g. when a newer ABI-14 tag appears, or after Emacs gains an ABI-15
runtime): change both, re-run `make`, restart the daemon.

## Related

- [lisp/languages/init-lua.el](../../lisp/languages/init-lua.el) — Lua mode /
  Eglot / lua-language-server config and the `treesit-auto` ABI-14 pin.
- [rust/treesit-grammar/README.md](../treesit-grammar/README.md) — the original
  Rust deployer this one mirrors.
- Project notes: [../../CLAUDE.md](../../CLAUDE.md) (tree-sitter grammar handling,
  the ABI-14 pins, the `css`/`json` ABI-15 exclusions).
