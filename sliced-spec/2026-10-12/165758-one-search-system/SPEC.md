# Spec: one search system — single-chord keys, no prefix

Status: implemented (rev 2), approved 2026-10-12 with the defaults (`C-t` files,
`C-z` text, full parent cycle).
Date: 2026-10-12 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)
Author: fenrir (with Claude Code)
Previous root SPEC.md (dape): [`tasks/done/20260520-dape/SPEC.md`](../../../tasks/done/20260520-dape/SPEC.md)

Rev 2 drops rev 1's `M-s` grid (`M-s f/F`, `M-s r/R`, `M-s M-s`). Its feedback
was that a prefix plus a letter, plus Shift for the folder variants, is
tiring. Every search now starts with **one Ctrl chord**.

## 目標

Every search should be easy to start without remembering a prefix, a Shift
variant, or a `C-u` trick. The motivating case: "fuzzy-find any file under a
folder I choose" works today, but only as `C-u M-s f`.

Each search is a choice on two axes:

| axis | values |
|---|---|
| **WHAT** | file name · text · (rarer: code symbol, heading, note, history) |
| **WHERE** | project · current folder · parent folders · *any folder I pick* |

**Success looks like:**

- File search and text search each start with **one chord**, and you type
  the query straight away.
- Changing WHERE or WHAT **keeps what you already typed**. No `C-u`, no Shift,
  no restarting.
- The rarer searches are in one menu, reached through the hub you already use
  (`<f5>`).
- No new search packages. Everything is consult / consult-dir / embark /
  wgrep, already installed.

## 不做的事

- No deadgrep, affe, rg.el, or `consult-ag`.
- No change to `C-s` / `consult-line`.
- No change to `M-g` jumps or `<f6>` / `<f7>` history.
- No global `C-o`.
- Not persisting the scope across restarts.

## 驗收條件

Daemon checks:

```bash
emacsclient -e '(list (key-binding (kbd "C-t")) (key-binding (kbd "C-z"))
                      (lookup-key dired-mode-map (kbd "C-t")))'
# => (fenrir/search-files fenrir/search-text <dired file-search command>)
emacsclient -e '(featurep (quote transient))'   # nil right after a fresh daemon start
```

Manual, in a TTY frame inside tmux and in a GUI frame:

1. `C-t`, type `init`, then `C-t` → the prompt folder moves from the project
   root to the current folder, and `init` is still typed.
2. `C-t`, `C-x C-d`, pick `~/code` → files under `~/code`, text kept.
3. `C-t`, type `parser`, then `C-z` → a ripgrep for `parser` in the same
   folder.
4. `C-z` in a folder that is not a project → grep of `default-directory`.
5. `C-t` in a dired buffer → file search rooted at that dired folder.
6. vterm: `C-t` / `C-z` still reach the shell.
7. `<f5> s` opens the menu, and every letter runs without `void-function` in
   a fresh daemon.
8. `C-z`, type `foo`, `C-. E`, `C-c C-p`, edit, then `C-c C-c` saves.

Startup: `emacs-init-time` within noise of the current value.

ERT: none. The `test/` suite covers libsrc only.

## 限制

- No new package, no `custom.el` change.

## 待決問題

- Should `C-t` / `C-z` be swapped (`C-z` for files)? `C-t` was picked for
  files because file search will be the more frequent one (`find-file` = 410
  presses). Accepted 2026-10-12: default (`C-t` files, `C-z` text).
- Scope cycle: is "parent, parent's parent…" useful, or should it be just
  project ⇄ current folder, with `C-x C-d` for everything else? Accepted 2026-10-12:
  default (full parent cycle: project → current → parent … → `/` → wrap).
