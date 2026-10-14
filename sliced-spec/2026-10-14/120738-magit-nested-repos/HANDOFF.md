# Handoff: Magit — a Nested repos section for independent clones inside a repo

Updated: 2026-10-14 12:07 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

(nothing yet)

## 決定與原因

- Route: a sliced spec, not one plan-mode build — the work is a crate, a Lisp module and
  docs, three natural slices (user answer, 2026-10-14).
- Scope: scan `<top>/*/.git` and `<top>/*/*/.git` by default; per repo,
  `git config nested.depth N` (0 = off) and `git config --add nested.path <dir>` override;
  the Lisp side skips `$HOME` (user answer, 2026-10-14).
- Rows: changed clones only, the heading counts all — `Nested repos (6 changed of 30)`;
  changed = uncommitted paths, ahead or behind the upstream, or a detached HEAD (user answer,
  2026-10-14).
- One noun, `nested`: crate `rust/git-nested-status/` deployed to `rust/lib/git-nested-status`,
  module `lisp/fenrir-magit-nested.el`, heading `Nested repos`.
- Discovery tests for a `.git` entry and opens that path, never `gix::discover` from a
  subdirectory — probed 2026-10-14: `git -C` on yeeya's `repos/logs` (no `.git`) reports the
  umbrella's own branch.
- The crate emits file lines (`--files`): Magit has not drawn these clones' files, so the
  unfold list cannot be read back from the status sections the way the Subtrees module does.
- The section hook is anchored after `fenrir/magit-subtree-insert-section`, not after Staged
  changes — two hooks appended after the same anchor end up in reverse order.
- Baseline, 2026-10-14: `git status --porcelain=v2 --branch` over yeeya's 30 clones takes
  0.18 s serially and 0.034 s in parallel. gix status speed on the large Java trees is
  unmeasured.

## 下一步

Slice 1, the crate end to end: `rust/git-nested-status/` (Cargo.toml, Cargo.lock,
`.cargo/config.toml`, Makefile, README.md, `src/main.rs`) with discovery (default depth 2,
`nested.depth`, `nested.path`), per-clone branch / upstream / ahead / behind / staged /
unstaged / untracked, porcelain v1 rows and `--files` lines, clones read on parallel threads;
`make-fixture.sh` in this folder; `tests/fixture.sh` and `tests/check-repo.sh`; `cargo test`;
wiring into `rust/Makefile` `SUBPROJECTS`, `rust/README.md` and the root `.gitignore`.
Measurement gate inside the slice: if parallel gix status on yeeya is not in the band of the
0.034 s git baseline, record a 決定 here and have the helper spawn `git` instead.
Moves 驗收條件 1, 2, 3, 6, 7 and 12 to passing. Sets SPEC `Status: in progress` in the same
commit. Commit subject: `rust: add git-nested-status, a nested-clone status helper`.

## 卡住・待確認

- Nothing blocked. Untracked in the repo but not this spec's: `AGENTS.md`, `plans/`, `records/`.
