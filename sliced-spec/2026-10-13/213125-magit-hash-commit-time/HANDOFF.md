# Handoff: Magit — show the commit time beside every hash

Updated: 2026-10-13 22:57 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Slice 1 — `git: show commit time beside hashes in Magit status`: status buffers show the
  committer time in the right margin (16 columns); `test/magit-time-test.el` encodes
  驗收條件 1, 3, 4 (all pass); FEATURES.md §8 documents it.

## 決定與原因

- The user approved SPEC.md and its 待決問題 defaults on 2026-10-13.
- Batch tests load Magit from `elpa/` via `package-initialize` and require the real
  `init-git` (it loads cleanly in batch). Invocation:
  `TZ=Asia/Taipei emacs -Q --batch -l test/magit-time-test.el -f ert-run-tests-batch-and-exit`.
  Leave no `.elc`.
- Status margin is `magit-status-margin` = `(t "%Y-%m-%d %H:%M" magit-log-margin-width nil 18)`
  plus `magit-log-margin-show-committer-date t` in `:custom` of `use-package magit`. The
  committer-date option is global, so log-buffer ages already follow committer time.
- `L L` (status map `L` → `magit-log-refresh`, suffix `L` → `magit-toggle-margin`) hides
  the times by shrinking the window's right margin to 0; the overlays stay. The toggle test
  measures `window-margins`, not overlays.
- Open Magit buffers keep their margin state from creation; acceptance 5–6 kill
  `magit: .emacs.d` first for that reason.

## 下一步

Slice 2: log buffers show the same `YYYY-MM-DD HH:MM` committer time plus the author, with
no relative age (`magit-log-margin`). Add `log-committer-time` to
`test/magit-time-test.el`. Moves 驗收條件 2 to passing. Commit:
`git: show commit time in Magit log buffers`.

## 卡住・待確認

- Unrelated uncommitted changes in the repo (staged rename `SPEC.md` →
  `tasks/done/20260520-dape/SPEC.md`, modified `tasks/done/README.md`): the user said leave
  them alone. Slice commits name only their own paths.
