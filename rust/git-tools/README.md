# git-tools — the git helper binaries, one cargo workspace

The git-related helpers of this Emacs config live here as members of one cargo workspace.
Each member is a bin run by a `lisp/` module, and also a plain CLI: because a binary is named
`git-<name>`, a symlink in `~/.local/bin` makes it a `git <name>` subcommand.

| member | front end | what |
|---|---|---|
| [`git-subtree-status/`](git-subtree-status/README.md) | [`lisp/fenrir-magit-subtree.el`](../../lisp/fenrir-magit-subtree.el) | which `git subtree` prefixes changed: uncommitted, since a revision, against an upstream ref |
| [`git-nested-status/`](git-nested-status/README.md) | `lisp/fenrir-magit-nested.el` (next slice of its spec) | the independent clones nested inside a repo (`repos/*` with their own `.git`): branch, ahead/behind, staged/unstaged/untracked |

## Why one workspace

Every member reads repositories with [gix](https://github.com/GitoxideLabs/gitoxide) and
never runs `git`. gix is the whole build cost (a release link is ~14 s with `lto = "thin"`;
a cold build is minutes), so the members share it: one `Cargo.lock`, one `target/`, the
`[profile.*]` blocks and the mold linker config (`.cargo/config.toml`) are workspace-level.
A member's `Cargo.toml` says only `gix = { workspace = true }`.

## Build and install

A subproject of the [`rust/` workspace](../README.md); the aggregator forwards the standard
targets here.

```bash
make -C ~/.emacs.d/rust/git-tools            # cargo build --release, deploy every bin to rust/lib/
make -C ~/.emacs.d/rust/git-tools verify     # also check each bin's porcelain header
```

cargo runs with this directory as cwd so `.cargo/config.toml` applies; `cargo build` from a
member directory works too (cargo finds the workspace root). `cargo build --profile quick`
is the fast optimized build for local runs.

## Adding a member

1. `cargo new --bin git-<name>` here; in its `Cargo.toml` use `gix = { workspace = true }`
   and drop the `[profile.*]` blocks (cargo ignores member profiles).
2. Add it to `members` in [`Cargo.toml`](Cargo.toml) and to `BINS` in the
   [`Makefile`](Makefile). Its `--porcelain` output must start with `# git-<name> v1` for
   `make verify`.
3. Give it a `README.md`, link it from the table above and from the
   [`rust/README.md`](../README.md) subprojects table.
