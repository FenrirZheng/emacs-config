# Handoff: git-nested-status — leave out the clones the umbrella gitignores, per repo

Updated: 2026-10-14 13:53 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

## 決定與原因

- Per-repo opt-in, not skip-by-default. `~/code/yeeya` ignores `/repos/` exactly as
  `~/.emacs.d` ignores `/elpa/`, so a default skip would empty yeeya (user answer,
  2026-10-14).
- The rule lives in the helper, though the user's itch is the Magit section only (user
  answer, 2026-10-14). The Lisp draws what the helper returns, so no Lisp change is needed;
  the CLI in `~/.emacs.d` goes quiet as a consequence.
- Feasibility, checked 2026-10-14 in the registry's `gix-0.89.0/Cargo.toml`: the workspace's
  `status` feature enables `dirwalk`, which enables `excludes`, so gix's exclude stack is
  available with no feature change.

## 下一步

Slice 1, the helper end to end. Read `nested.skipIgnored` and the two flags; filter the
discovered clones through gix's exclude check before any is opened; add a unit test of the
flag/config resolution; write `rust/git-tools/git-nested-status/tests/skip-ignored.sh` for
criteria 1–5; update `--help` and the crate README. Moves criteria 1–5, 9, 10 and 11, and the
`--help` and README part of 13, to passing. Commit subject:
`rust: let git-nested-status skip gitignored clones on request`.

## 卡住・待確認

- Nothing blocked.
- Untracked in the repo, but not this spec's: `AGENTS.md`, `plans/`, `records/`.
