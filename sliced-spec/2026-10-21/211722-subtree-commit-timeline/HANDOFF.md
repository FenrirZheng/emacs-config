# Handoff: Magit — one commit timeline across every git subtree

Updated: 2026-10-21 21:17 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

(none yet)

## 決定與原因

- Elisp in `lisp/fenrir-magit-subtree.el`, not Rust. Per-directory owner memoization brings
  30 days of history to 84 ms against 31 ms for `git log` (measured 2026-10-21 in the
  daemon). The Rust path, a `--log` mode in `git-subtree-status`, is taken only if 驗收條件 7
  fails.
- A `magit-mode`-derived buffer whose rows are `commit` sections, so `RET`, `g` and the
  `Subtree:` line in the revision buffer come from Magit.
- The `repos/` fallback root is a defcustom (`'("repos")`), not hard-coded, because the
  module serves any subtree repo.
- Tests extend `test/magit-subtree-test.el`, which already loads Magit from `elpa/`. The
  plan file's "no ERT" was wrong.

## 下一步

Build the whole feature in one slice: the parser, the labeller, the mode and command, `l A`,
the tests and FEATURES.md. It moves 驗收條件 1–8 toward passing. Commit subject:
`magit-subtree: add a cross-subtree commit timeline (l A)`.

## 卡住・待確認

- SPEC.md is `draft` and waits for the user's approval.
