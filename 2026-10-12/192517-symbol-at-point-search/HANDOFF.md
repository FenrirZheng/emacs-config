# Handoff: C-u C-t / C-u C-z — search the symbol at point

Updated: 2026-10-12 23:20 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Daemon re-run of 驗收條件 1–5 (deliberately in the daemon, to confirm the restarted
  daemon loads the keys; adds to the throwaway run, does not replace it): all pass —
  commit `docs: record the daemon run of the symbol-at-point acceptance`
- Docs + acceptance: FEATURES.md §1b rows for `C-u C-t` / `C-u C-z`; 驗收條件 1–5 run on
  their literal input in a throwaway `emacs -nw` (tmux), all pass; Status → implemented —
  commit `docs: document C-u C-t / C-u C-z symbol seeding`
- Seed helper + prefix arg, ERT 15 → 18 — commit
  `search: seed C-u C-t / C-u C-z with the symbol at point`
- Spec approved, both defaults kept — commit `spec: mark the symbol-at-point spec approved`

## 決定與原因

- Text seed is `regexp-quote`d, because consult-ripgrep reads its input as a regexp and a
  symbol such as `foo.bar` must match literally; the file seed is the symbol as is
  (both defaults accepted 2026-10-12).
- Checks for any change here: `emacs -Q --batch -l test/libsrc-test.el -f
  ert-run-tests-batch-and-exit`, the same with `test/search-test.el`, and
  `bash .githooks/pre-commit`; leave no `.elc` behind.
- Point is placed for acceptance by a preloaded helper, never a sexp typed into `M-:`
  (positioning is setup, not the input under test).

## 下一步

None — the spec is implemented and every 驗收條件 passed as written.

## 卡住・待確認

- (none)
