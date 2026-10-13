# Handoff: Magit — show the commit time beside every hash

Updated: 2026-10-13 23:23 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Slice 1 — `git: show commit time beside hashes in Magit status`: status buffers show the
  committer time in the right margin (16 columns); `test/magit-time-test.el` encodes
  驗收條件 1, 3, 4 (all pass); FEATURES.md §8 documents it.
- Slice 2 — `git: show commit time in Magit log buffers`: log margins show author +
  committer time instead of a relative age; `log-committer-time` encodes 驗收條件 2 (pass);
  FEATURES.md §8 updated.

## 決定與原因

- The user approved SPEC.md and its 待決問題 defaults on 2026-10-13.
- Batch tests load Magit from `elpa/` via `package-initialize` and require the real
  `init-git` (it loads cleanly in batch). Invocation:
  `TZ=Asia/Taipei emacs -Q --batch -l test/magit-time-test.el -f ert-run-tests-batch-and-exit`.
  Leave no `.elc`.
- Settings live in `:custom` of `use-package magit`: `magit-log-margin-show-committer-date t`,
  `magit-status-margin '(t "%Y-%m-%d %H:%M" magit-log-margin-width nil 18)`,
  `magit-log-margin '(t "%Y-%m-%d %H:%M" magit-log-margin-width t 18)`.
- `:custom` runs before magit loads, and the reflog / stashes / cherry / log-select margin
  defcustoms copy STYLE from `magit-log-margin` at load, so those buffers show the absolute
  time too. Consistent, not a goal; no criterion covers it.
- The log test runs `magit-log-current` via `call-interactively` (its positional args are
  revs, args, files — passing args directly errored).
- `L L` (status map `L` → `magit-log-refresh`, suffix `L` → `magit-toggle-margin`) hides
  the times by shrinking the window's right margin to 0; the overlays stay. The toggle test
  measures `window-margins`, not overlays.
- Open Magit buffers keep their margin state from creation; acceptance 5–6 kill
  `magit: .emacs.d` first for that reason.

## 下一步

Slice 3: make the in-hunk refinement line in `lisp/init-git.el` state what happens while
magit-delta is on (目標 bullet 5) — `magit-diff-refine-hunk` is overridden to nil by
magit-delta-mode, so the `t` setting and its comment are misleading. Read magit-delta's
source in `elpa/` for the override first. Moves 驗收條件 7 toward passing (its daemon half
runs at the gate). Commit: `git: say refine-hunk is off under magit-delta`.

## 卡住・待確認

- Unrelated uncommitted changes in the repo (staged rename `SPEC.md` →
  `tasks/done/20260520-dape/SPEC.md`, modified `tasks/done/README.md`): the user said leave
  them alone. Slice commits name only their own paths.
- The running daemon has not reloaded `lisp/init-git.el`; that happens in the setup of
  驗收條件 5 at the gate.
