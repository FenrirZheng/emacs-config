# Handoff: Magit — show the commit time beside every hash

Updated: 2026-10-13 23:28 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Slice 1 — `git: show commit time beside hashes in Magit status`: status buffers show the
  committer time in the right margin (16 columns); `test/magit-time-test.el` encodes
  驗收條件 1, 3, 4 (all pass); FEATURES.md §8 documents it.
- Slice 2 — `git: show commit time in Magit log buffers`: log margins show author +
  committer time instead of a relative age; `log-committer-time` encodes 驗收條件 2 (pass);
  FEATURES.md §8 updated.
- `test: keep magit-time-test's forge database out of the repo`: the suite had been
  writing `forge-database.sqlite` into the repo root (contrary to the `/tmp`-only 副作用 of
  驗收條件 1–4); it now goes to the temp dir.
- Slice 3 — `git: say refine-hunk is off under magit-delta`: `magit-diff-refine-hunk` set
  to nil with a comment saying magit-delta-mode forces it off. Batch: nil after loading
  `init-git` and inside a fixture status buffer with delta on. The daemon half of 驗收條件 7
  runs at the gate.

## 決定與原因

- The user approved SPEC.md and its 待決問題 defaults on 2026-10-13.
- Batch tests load Magit from `elpa/` via `package-initialize` and require the real
  `init-git`. Invocation:
  `TZ=Asia/Taipei emacs -Q --batch -l test/magit-time-test.el -f ert-run-tests-batch-and-exit`.
  Leave no `.elc`. Under `-Q` no-littering is absent, so the suite points
  `forge-database-file` at the temp dir itself.
- Settings live in `:custom` of `use-package magit`: `magit-log-margin-show-committer-date t`,
  `magit-status-margin '(t "%Y-%m-%d %H:%M" magit-log-margin-width nil 18)`,
  `magit-log-margin '(t "%Y-%m-%d %H:%M" magit-log-margin-width t 18)`,
  `magit-diff-refine-hunk nil`.
- `magit-delta-mode` (`elpa/magit-delta-20220125.50/magit-delta.el:99`) does a global
  `setq magit-diff-refine-hunk nil` on enable and saves the old value, which after the first
  Magit buffer is nil too. So nil is the honest setting.
- Reflog / stashes / cherry / log-select margins copy STYLE from `magit-log-margin` at load,
  so they show the absolute time too. Consistent, not a goal; no criterion covers it.
- `L L` hides the times by shrinking the window's right margin to 0; the overlays stay. The
  toggle test measures `window-margins`.
- Open Magit buffers keep their margin state from creation; acceptance 5–6 kill
  `magit: .emacs.d` first for that reason.

## 下一步

The acceptance gate. 5 and 6 are manual (real TTY / GUI frame) → `needs user`; 7 needs the
daemon (`emacsclient`) after reloading `lisp/init-git.el`.

## 卡住・待確認

- Gate step 1 needs no modified or staged tracked file. Today the tree has: the unrelated
  staged rename `SPEC.md` → `tasks/done/20260520-dape/SPEC.md` and modified
  `tasks/done/README.md` (user: leave alone), plus another session's uncommitted edits to
  `lisp/languages/fenrir-libsrc.el` and `test/libsrc-test.el` (libsrc rust class-lister
  spec). The gate cannot start until those are committed or set aside — the user's call.
- A stray `forge-database.sqlite` that this suite created at 22:57 was moved out of the repo
  to this session's scratchpad, not deleted.
