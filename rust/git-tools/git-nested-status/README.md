# git-nested-status

Lists the independent git clones nested inside a repository and their state. An umbrella
checkout such as `~/code/yeeya` keeps the product's repos as separate clones under `repos/`,
gitignored by the umbrella, so the umbrella's own `git status` says nothing about them. This
tool does. Reading is done with [gix](https://github.com/GitoxideLabs/gitoxide); it never runs
`git`, never fetches and never writes.

```
$ git nested-status
path                       branch    upstream                  staged unstaged untracked
repos/kefu                 main      origin/main +2 -0              0        0         0
repos/sms-platform         prod      origin/prod                    0        1        16
repos/sms-platform-hotfix  detached  -                              0        1         0
29 nested repo(s), 8 with a change
```

## What a clone is, and where it is looked for

A clone is a subdirectory with its own `.git` entry: a directory, or the `gitdir:` file of a
linked worktree or submodule. It is opened at that path and never found by walking upward, so a
plain subdirectory never reports the umbrella's own state. Nothing inside a clone is searched;
a clone nested in a clone belongs to the outer one.

Where to look is read from the umbrella's git config (local, global or system):

```bash
git config nested.depth <n>          # levels below the toplevel; default 2 (*/ and */*/); 0 = off
git config --add nested.path <dir>   # only the immediate children of <dir>; repeatable
```

`--depth <n>` on the command line overrides both. With `nested.path` set, `nested.depth` is
ignored unless it is 0, which always means "look nowhere". Symlinked directories are skipped.

## Columns

| column | meaning |
|---|---|
| branch | the checked-out branch; `detached` when HEAD is a commit |
| upstream | the tracking ref, with `+ahead -behind` when they are not 0; `(gone)` when its ref is missing; `-` without one |
| staged | paths that differ between HEAD and the index |
| unstaged | paths that differ between the index and the working tree |
| untracked | untracked paths, directories collapsed as `git status` does |

A clone has a **change** when it has uncommitted paths, is ahead of or behind its upstream, or
its HEAD is detached. A clone with no upstream is not a change by itself. The table lists the
changed clones (`--all` for every one); `--files` adds each uncommitted path with its kind.
Ahead/behind is as of the clone's last fetch.

## Options

```
-C <dir>  --depth <n>  --files  --all  --porcelain  --exit-code  -h  -V
```

`--porcelain` writes a `# git-nested-status v1` line, then one `R` line per clone (every clone,
not only changed ones) and, with `--files`, `F` lines under it:

```
R  path  branch  head  upstream  ahead  behind  staged  unstaged  untracked
F  kind  file                               kind = staged | unstaged | untracked
```

`branch` is `-` when detached, `head` is the abbreviated commit (`-` when unborn), `upstream`
is `-` without one, and `ahead`/`behind` are `-` without an upstream or when its ref is gone.
`git nested-status --help` has the same description. The Emacs/Magit front end,
`lisp/fenrir-magit-nested.el` (the next slice of its spec), reads this format.

## Performance

Clones are read on a small pool of worker threads (at most 6); each gix status run is limited
to one hashing thread, since gix already runs its own producer threads per repository.

Measured on 2026-10-14 (Asia/Taipei) on `~/code/yeeya` (29 clones, the largest index 3034
entries), 12 cores, warm page cache, `tests/check-repo.sh`:

| run | time |
|---|---|
| `--porcelain --files`, median of 10 warm runs | 40–45 ms (two runs of the script: 39.9 and 44.5 ms) |
| first run after a reboot or cache eviction (cold) | ~240 ms |
| `git status --porcelain` over the same 29 clones, in parallel, for comparison | 34 ms |

## Build and install

A member of the [`git-tools` cargo workspace](../README.md) in this Emacs config's
[`rust/` workspace](../../README.md).

```bash
make -C rust/git-tools                     # cargo build --release (all members), deploy to rust/lib/
make -C rust/git-tools verify              # also check each bin's porcelain header
ln -sfn ~/.emacs.d/rust/lib/git-nested-status ~/.local/bin/git-nested-status   # terminal use
```

The Emacs front end runs `rust/lib/git-nested-status` directly and does not need `PATH`. The
symlink is only for the terminal; because the binary is named `git-nested-status`, git runs it
as `git nested-status`.

## Tests

- `cargo test -p git-nested-status` (from `rust/git-tools/`): discovery (depth, `nested.path`,
  no descent into a clone, `.git` files, symlinks skipped), scope resolution, the change rule
  and the porcelain line format. Pure std, no git needed.
- [`tests/fixture.sh`](tests/fixture.sh): the spec's 驗收條件 1–3 on the fixture repo that
  [`make-fixture.sh`](../../../sliced-spec/2026-10-14/120738-magit-nested-repos/make-fixture.sh)
  builds under `/tmp`; expected values come from the fixture, not from the binary.
- [`tests/check-repo.sh <repo>`](tests/check-repo.sh): 驗收條件 6 and 7 on a real repo — the
  clone set against `find`, and the 10-run median timing.
