# git-subtree-status

Shows which git subtrees in a repository have changed. It finds the subtrees on its own, so it
works in any repo that uses `git subtree`. Reading is done with
[gix](https://github.com/GitoxideLabs/gitoxide); the tool never runs `git`, never fetches and
never writes.

```
$ git subtree-status --since '7 days ago'
prefix                         uncommitted  since  import          upstream
repos/lottery/kjw-web                    3      3  changed (15)    same p/kjw-web/hg-config
repos/lottery/odds/odds-web-ag           0     24  changed (28)    same p/odds-web-ag/hg-config
55 subtree(s), 2 with a change (since: 7 days ago)
```

## How subtrees are found

`git subtree add`, `merge` and `pull` write `git-subtree-dir:` and `git-subtree-split:` trailers.
The tool walks `HEAD` once, reads those trailers, and keeps every prefix that still exists at
`HEAD`. You don't need a registry file.

- **Full-history import**: the trailers sit on a mainline commit that contains the prefix. The
  prefix tree in that commit is what was imported.
- **`--squash` import**: the trailers sit on the squash commit, and that commit's own tree is
  the imported content.

## Columns

| column | meaning |
|---|---|
| uncommitted | paths under the prefix that `git status` lists: staged, unstaged, and untracked (collapsed) |
| since | files changed under the prefix between `--since` and `HEAD`. `--since` takes a revision, or a date such as `7 days ago` (meaning the last first-parent commit before that date) |
| import | `same` or `changed (n)`: whether the prefix differs from what the newest import brought in |
| upstream | `same`, `differs (n)` or `missing`, compared against the optional ref below. `-` means none is set |

A subtree counts as "changed" if it has uncommitted paths, has any `since` changes, or has
drifted. Drift is measured against the upstream ref when one is configured, and against the last
import otherwise. Work sent upstream with `git subtree push` leaves no trailer behind, so after
a push the import difference keeps growing. The upstream ref is the one that tells you the
truth in that case.

## Upstream refs (optional)

```bash
git config subtree.<prefix>.upstream <ref>     # e.g. subtree.libs/foo.upstream foo/main
```

The value is read from local config. The tool never fetches, so the ref is only as fresh as
your last `git fetch`.

## Options

```
-C <dir>  --since <rev|date>  --filter <substr>  --all  --porcelain  --exit-code
--no-status         skip the working-tree scan (uncommitted = '-'); Magit counts it itself
--owner-of <rev>    print the subtree prefix(es) a commit belongs to
```

`--owner-of` answers from the commit's own diff when the commit is on HEAD's first-parent
chain. That chain holds umbrella commits, and their paths carry the prefix. For any other
commit, which means an imported project commit, it answers with every subtree whose own history
contains that commit: the upstream ref, or else the last import. A project commit that sits only
on another branch (UAT, say, while the mainline is hg-config) belongs to neither, so it gets no
owner.

Discovery walks HEAD's whole history once, then caches the result in
`<git-dir>/git-subtree-status.cache`, keyed by the HEAD commit. Measured on ig_lottery
(55 subtrees, 2026-10-14):

| run | time |
|---|---|
| full report | 100 ms |
| `--no-status` | 25 ms |
| `--owner-of` | 15–33 ms |

With `--porcelain` the tool writes a `# git-subtree-status v1` line, then one tab-separated line
per subtree. Run `git subtree-status --help` for the exact field list. The Emacs/Magit front end
reads this format.

## Build and install

A subproject of this Emacs config's [`rust/` workspace](../README.md). Its front end is
[`lisp/fenrir-magit-subtree.el`](../../lisp/fenrir-magit-subtree.el).

```bash
make -C rust/git-subtree-status            # cargo build --release, deploy to rust/lib/
make -C rust/git-subtree-status verify     # also check the porcelain header
ln -sfn ~/.emacs.d/rust/lib/git-subtree-status ~/.local/bin/git-subtree-status   # terminal use
```

The Emacs front end runs `rust/lib/git-subtree-status` directly and does not need `PATH`.
The symlink is only for the terminal. Because the binary is named `git-subtree-status`, git
also runs it as `git subtree-status`.

Build settings:
- `.cargo/config.toml` links with mold.
- `Cargo.toml` adds a `quick` profile (`cargo build --profile quick`) for fast optimized local
  builds.

Measured on 2026-10-14 (Asia/Taipei), 12 cores, rustc 1.98.0, real-edit rebuilds:

| build | time |
|---|---|
| `cargo build` (dev) | 0.31 s |
| `quick` profile | 0.27 s |
| release with `lto = "thin"` | 14.05 s |
| release with `lto = true` | 27.69 s |

## Tests

`cargo test`. The unit test covers prefix ownership: the longest prefix wins, and sibling
prefixes don't match. The full-history and `--squash` discovery paths were checked by hand
against a fixture repo built with `git subtree add` / `pull --squash`.
