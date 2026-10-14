# Handoff: Magit — a Nested repos section for independent clones inside a repo

Updated: 2026-10-14 12:40 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Slice 1: the helper binary end to end — crate `rust/git-tools/git-nested-status/`
  (discovery with `nested.depth` / `nested.path` / `--depth`, per-clone branch / head /
  upstream / ahead / behind / staged / unstaged / untracked, porcelain v1 `R` rows and `--files`
  `F` lines, 6-thread worker pool), `make-fixture.sh` in this folder, `tests/fixture.sh`,
  `tests/check-repo.sh`, crate README, `rust/README.md` and `rust/git-tools/README.md` rows;
  SPEC `Status: in progress` plus the corrections below — commit
  `rust: add git-nested-status, a nested-clone status helper` (`ddd40cd`).
  Checked: `cargo test` 8/8; criteria 1–3 via `tests/fixture.sh` all ok; criteria 6–7 via
  `tests/check-repo.sh ~/code/yeeya`: 29 clones = find's set, warm 10-run medians 39.9 ms and
  44.5 ms (bound 100 ms; the cold first run was 242 ms); criterion 12: `make -C rust verify`
  green with both bins. The fixture script's FAIL path was exercised once with a wrapper that
  dropped a row (3 FAILs, exit 1).
- Fix after the slice's advisor review: clones are opened with gix's default options, not
  `isolated()`, so `~/.config/git/ignore` applies; yeeya's three dirty clones now list the
  same paths as their own `git status` (before, `.claude` showed as untracked in two of them);
  warm median 39.5 ms — commit `rust: let git-nested-status honour the global ignore file`
  (`ab73c73`).
- Workspace move, before the slice: `rust/git-subtree-status/` became a member of the new cargo
  workspace `rust/git-tools/` (one `Cargo.lock`, one `target/`, workspace-level profiles and
  mold config, one Makefile deploying every bin to `rust/lib/`); deployed paths unchanged,
  output checksum identical, `test/magit-subtree-test.el` 13/13 — commit
  `rust: move git-subtree-status into the git-tools cargo workspace` (`08c766e`).

## 決定與原因

- Route: a sliced spec, not one plan-mode build — the work is a crate, a Lisp module and
  docs, three natural slices (user answer, 2026-10-14).
- Scope: scan `<top>/*/.git` and `<top>/*/*/.git` by default; per repo,
  `git config nested.depth N` (0 = off) and `git config --add nested.path <dir>` override;
  the Lisp side skips `$HOME` (user answer, 2026-10-14). Resolution in code: `--depth` wins;
  depth 0 from either source means nowhere even with paths; paths scan their immediate
  children only (approved default); else depth, default 2.
- Rows: changed clones only, the heading counts all — `Nested repos (6 changed of 30)`;
  changed = uncommitted paths, ahead or behind the upstream, or a detached HEAD; no upstream
  alone is not a change (user answer + approved default, 2026-10-14).
- The git crates share one cargo workspace, `rust/git-tools/` — user direction 2026-10-14
  ("why not group the git-related crates"); gix compiles once, one lockfile. Adding a member:
  `rust/git-tools/README.md`. The aggregator's subproject is `git-tools`, not the crates.
- SPEC corrections approved with the slice-1 plan (2026-10-14): yeeya has 29 clones with their
  own `.git`, not 30 (one of them, `sms-platform-hotfix/.git`, is a worktree `gitdir:` file);
  criterion 10 runs on `/tmp/magit-nested-fixture/repos/clean`, because `~/.emacs.d` has three
  `package-vc` clones under `elpa/` (combobulate, eglot-booster, eglot-x) that a depth-2 scan
  finds — they are left visible there, no `nested.depth 0` for the config repo; test paths
  follow the workspace layout.
- `--porcelain` lists every clone (the Magit heading needs the total; a script can tell a
  changed row from its columns); `--all` only widens the table. Criterion 1 reads that way.
- One noun, `nested`: crate `rust/git-tools/git-nested-status/` deployed to
  `rust/lib/git-nested-status`, module `lisp/fenrir-magit-nested.el`, heading `Nested repos`.
- Discovery tests for a `.git` entry and opens that path with `gix::open` (default options,
  so the global config and `~/.config/git/ignore` apply), never `gix::discover` from a
  subdirectory — probed 2026-10-14: `git -C`
  on yeeya's `repos/logs` (no `.git`) reports the umbrella's own branch. The umbrella itself is
  opened with `gix::discover`, so `-C` may name a subdirectory and global config applies.
- Ahead/behind: two `rev_walk(..).with_hidden(..)` counts (exact `^tip` semantics), skipped
  when head == upstream. Status: gix status iterator, untracked collapsed, rename tracking off,
  one hashing thread per clone; `summary()` None (stat-only) is skipped, `Added` = untracked.
- The crate emits file lines (`--files`): Magit has not drawn these clones' files, so the
  unfold list cannot be read back from the status sections the way the Subtrees module does.
- The section hook (slice 2) is anchored after `fenrir/magit-subtree-insert-section`, not after
  Staged changes — two hooks appended after the same anchor end up in reverse order.
- A clone that fails to open or read is reported on stderr and left out of the rows; the exit
  code is unaffected. Symlinked directories are skipped during discovery.
- Baseline, 2026-10-14: `git status --porcelain=v2 --branch` over yeeya's 29 clones takes
  0.18 s serially and 0.034 s in parallel; the helper's warm median is 40–45 ms, so no git
  fallback was needed (and SPEC 限制 forbids running `git`).

## 下一步

Slice 2, the Magit section: `lisp/fenrir-magit-nested.el` (defcustoms for the program path, a
show-in-status toggle and the skipped directories, default `("~/")`; porcelain parser for `R`/`F`
lines; a `Nested repos (N changed of M)` section after Subtrees with one row per changed clone
showing path, branch or detached, `↑a ↓b` and the uncommitted count, folded file lines
underneath, `RET` on a row → `magit-status` of the clone, `RET` on a file → visit it; a
per-session "no clone here" memory with `fenrir/magit-nested-forget`; a build hint, no error,
when the binary is absent), `(require 'fenrir-magit-nested)` next to the subtree require in
`lisp/init-git.el`, `test/magit-nested-test.el` (status-section, row-actions, home-skipped,
none-remembered, unbuilt — modelled on `test/magit-subtree-test.el`, fixture via
`make-fixture.sh`), and the FEATURES.md Magit section. Moves 驗收條件 4, 5, 9, 10, 11 and 13.
Commit subject: `git: show the nested clones of a repo in Magit`.

## 卡住・待確認

- Nothing blocked. Untracked in the repo but not this spec's: `AGENTS.md`, `plans/`, `records/`.
- `/tmp/magit-nested-fixture` is left in place by the scripts (criteria' declared 副作用).
