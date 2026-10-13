# Handoff: Magit — show the commit time beside every hash

Updated: 2026-10-13 21:31 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

## 決定與原因

- The interview went unanswered, so SPEC 待決問題 defaults stand until approval.
- Batch tests load Magit from `elpa/` via `package-initialize` (the existing suites load only
  `lisp/`). Invocation:
  `TZ=Asia/Taipei emacs -Q --batch -l test/magit-time-test.el -f ert-run-tests-batch-and-exit`.
  Leave no `.elc`.
- Open Magit buffers keep their margin state from creation; acceptance 5–6 kill
  `magit: .emacs.d` first for that reason.

## 下一步

Slice 1: status-buffer committer time plus `test/magit-time-test.el`, building the fixture
with [`make-fixture.sh`](make-fixture.sh). Moves 驗收條件 1, 3, 4 to passing. Commit:
`git: show commit time beside hashes in Magit status`.

## 卡住・待確認

- SPEC.md approval, and the 待決問題 defaults.
