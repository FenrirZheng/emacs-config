# Handoff: one search system — single-chord keys, no prefix

Updated: 2026-10-12 23:20 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- GUI 驗收條件 2 fixed and re-run as written (`C-x C-d`, typed `~/code/`, `M-RET` →
  `Fd (~/code)`, `#init` kept) — commit
  `completion: accept a typed folder in the search C-x C-d`
- GUI run of 驗收條件 1, 3–8 in a throwaway GUI Emacs
  ([`scripts/gui-harness.el`](scripts/gui-harness.el)): all pass — commit
  `docs: record one-search GUI acceptance run`
- TTY 驗收條件 8 (wgrep round trip) and init time (HEAD median 0.447 s vs base 0.450 s,
  [`scripts/inittime.sh`](scripts/inittime.sh)) — commit
  `docs: record one-search acceptance results`
- FEATURES.md §1b "Search", `<f5> s` hub row, moved `transpose-chars` / `suspend-frame`
  — commit `docs: document one-search keys`
- `<f5> s` search menu, 21 letters, no `void-function` — commit `keys: add <f5> s search menu`
- Global `C-t` / `C-z` and dired `C-t`; TTY 驗收條件 5–6 — commit
  `keys: bind C-t / C-z to search`
- `fenrir/search-files` / `fenrir/search-text` and the in-prompt keymap; TTY 驗收條件 1–4
  — commit `completion: add fenrir/search-files and search-text`

## 決定與原因

- `C-t` = files, `C-z` = text: CapsLock is Ctrl via keyd, both keys were nearly unused
  (keyfreq 2 / 9) and reach a TTY frame through tmux; `C-,` / `C-'` never reach a TTY
  frame; `C-o` is the per-mode casual-menu key and global `open-line` stays.
- In a prompt: the same key cycles WHERE, the other key toggles WHAT, `C-x C-d` picks any
  folder; the typed text is kept. Scope cycle stops at `/` and wraps to the project root.
- `C-x C-d` accepts a typed existing folder (user's choice of fix option 1, 2026-10-12);
  anything else is `user-error` "Not an existing folder: …" and the prompt stays open.
- Commands live in `lisp/fenrir-search.el` (loadable in `emacs -Q` for ERT);
  `init-keys.el` only routes. The prompt keymap is a buffer-local minor mode in the
  minibuffer, which already beats `vertico-map`.
- Dired `C-t` → `fenrir/search-files-here` (image-dired stays on `M-x`); vterm / term keep
  `C-t` / `C-z` (global bindings only, no `bind-key*`).
- `<f5> s` menu: `e` is `fenrir/search-lsp-symbols` (reports when eglot is off), `t`
  `consult-todo-project`, `K` `embark-bindings`; `<f5> n` keeps its search entries.
- Checks for any change here: `emacs -Q --batch -l test/libsrc-test.el -f
  ert-run-tests-batch-and-exit`, the same with `test/search-test.el`, and
  `bash .githooks/pre-commit`; leave no `.elc` behind.

## 下一步

None — every slice is built. The two items below decide whether `Status: implemented`
stands.

## 卡住・待確認

- The TTY run did not use every 驗收條件's literal input: steps 1–4 started from
  `M-: (fenrir/search-files)` before the global keys existed, step 2 picked `~/cz/`
  instead of `~/code`, and step 8 used a session-only `C-c .` because tmux
  (`extended-keys off`) never delivers `C-.`. The GUI run passed all 8 as written. Re-run
  steps 1–4 in a TTY frame with the global keys, and decide whether step 8's `C-.` is
  GUI-only?
- Daemon check `(featurep 'transient)` → nil fails: combobulate's autoloads require
  transient during `package-initialize`, not this config. Amend that 驗收條件 (a SPEC
  change), or leave it failing?
