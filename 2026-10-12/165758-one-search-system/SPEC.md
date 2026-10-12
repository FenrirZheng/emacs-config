# Spec: one search system — single-chord keys, no prefix

Status: implemented (rev 2), approved 2026-10-12 with the defaults (`C-t` files,
`C-z` text, full parent cycle). Commits: `15cc6e1` (commands + prompt keys),
`bf0f62f` (global / dired keys), `590a2a7` (`<f5> s` menu), plus the docs commit.
Deviations and evidence: [PLAN.md](PLAN.md).
Date: 2026-10-12 (Asia/Taipei)
Author: fenrir (with Claude Code)
Previous root SPEC.md (dape): [`tasks/done/20260520-dape/SPEC.md`](../../tasks/done/20260520-dape/SPEC.md)

Rev 2 drops rev 1's `M-s` grid (`M-s f/F`, `M-s r/R`, `M-s M-s`). Its feedback
was that a prefix plus a letter, plus Shift for the folder variants, is
tiring. Every search now starts with **one Ctrl chord**.

## Objective

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

## Why these keys (evidence)

keyfreq totals from [`var/keyfreq.el`](../../var/keyfreq.el), read 2026-10-12:

| command (key) | presses |
|---|---|
| `find-file` (`C-x C-f`) | 410 |
| `fenrir/back` (`<f6>`) | 272 |
| `consult-line` (`C-s`) | 170 |
| `fenrir/hub` (`<f5>`) | 113 |
| `suspend-frame` (`C-z`) | 9 — almost certainly accidental; it suspends the emacsclient TTY |
| `consult-find` (`M-s f`) | 6 |
| `transpose-chars` (`C-t`) | 2 |
| `consult-ripgrep` (`M-s r`) | 0 |

Single keys get used (`C-s`, `<f5>`, `<f6>`), and anything behind `M-s`
almost never does. CapsLock is Ctrl via keyd, so `C-<letter>` is the cheapest
chord there is. `C-t` and `C-z` are nearly unused, and they reach a TTY frame
through tmux. `C-,` and `C-'` are free but never reach a TTY frame, so they
are ruled out.

**Why not `C-o`:** it is already this config's per-mode "casual menu" key in 12
modes (dired, ibuffer, isearch, compilation, Info …), and global `C-o`
(`open-line`) is documented to stay untouched
([`init-keys.el`](../../lisp/init-keys.el), casual-suite block). A global search
binding there would give one key two unrelated meanings.

Mode-map check (`lookup-key` in the running daemon, 2026-10-12):

| map | `C-t` | `C-z` |
|---|---|---|
| global | `transpose-chars` | `suspend-frame` |
| dired-mode-map | image-dired prefix | — |
| ibuffer, magit, org, grep, compilation, occur, minibuffer, vertico | — | — |
| vterm-mode-map | (not loaded at check time; vterm sends both to the shell) | ″ |

## Design

### Tier 1 — two chords (muscle memory)

| key | does | replaces |
|---|---|---|
| `C-t` | **find file** by name: fuzzy, recursive (`consult-fd`) | `transpose-chars` (2 uses, still on `M-x`) |
| `C-z` | **search text** (`consult-ripgrep`) | `suspend-frame` (harmful under emacsclient) |
| `C-s` | search this buffer (`consult-line`) | unchanged |

Both start in the **project root**, or in `default-directory` when there is no
project. The prompt shows where you are searching, e.g. `Files [~/code/foo/]: `.

### Inside the prompt — change WHERE / WHAT, keep your text

The rule is the two-axis model mapped onto the same two keys:

| press, inside a `C-t` / `C-z` prompt | effect |
|---|---|
| the **same** key again | change **WHERE**: project root → current folder → parent → parent's parent … (wraps back to project) |
| the **other** key | change **WHAT**: file search ⇄ text search, same folder, same text |
| `C-x C-d` | change **WHERE** to any folder via consult-dir (recent / project / bookmark / quick dirs) |

Examples:

- Fuzzy-find a file under `~/code`: `C-t`, `C-x C-d`, `code`, `RET`, then
  type the name.
- Grep the folder the current file is in: `C-z`, `C-z`, then type.
- "Not a file name, it's in the contents": you typed `parser` after `C-t`;
  press `C-z` and the same `parser` is now grepped in the same folder.

Mechanism, one helper used by both commands:

1. While one of these prompts is active, a dynamic variable records
   `(kind dir)`.
2. `C-t` / `C-z` / `C-x C-d` are bound in a small minor-mode keymap that is
   active only in those prompts. That keymap takes precedence over
   `vertico-map`, so `C-x C-d` there no longer inserts a path into a ripgrep
   pattern.
3. Each key computes the next `(kind dir)`, saves `(minibuffer-contents)`,
   schedules a rerun with `run-at-time 0`, and calls
   `abort-recursive-edit`. The rerun calls `consult-fd` / `consult-ripgrep`
   with `(dir initial)`. Both accept `(&optional dir initial)`, verified.
4. Scope cycling stops at `/` and wraps back to the project root.

### Shadowing

- **dired:** `C-t` is the image-dired prefix there. Rebind
  `dired-mode-map` `C-t` → file search starting in the dired folder, because
  in dired "find under this folder" is exactly the use case. image-dired stays
  on `M-x`.
- **vterm / term:** not overridden. Global bindings only (no `bind-key*`), so
  the shell keeps `C-t` (fzf) and `C-z` (job control).
- Everywhere else checked: no shadowing.

### Tier 2 — the rarer searches: `<f5> s`

A transient, `fenrir/search-menu`, added to the hub as `s`. `<f5>` is
already the most-used menu key (113 presses), so there is nothing new to learn.

```
Files              Text                Code                 Notes              History
 f  find file       l  this buffer      i  imenu             o  outline         b  buffers
 r  recent files    L  open buffers     I  imenu (project)   h  org heading     m  global marks
 d  folder (dired)  g  ripgrep          e  LSP symbols       n  roam node       y  kill ring
                    k  keep lines       ?  references        B  bookmarks       t  TODOs (project)
                    u  focus lines                                              K  key bindings
```

- `f` / `g` call the same commands as `C-t` / `C-z`.
- `r` is `consult-recent-file`.
- `d` is `consult-dir`.
- `e` is `consult-eglot-symbols`. When eglot is off, it says so instead of
  erroring.
- Lazy: define the prefix inside `(with-eval-after-load 'transient …)`, the
  same pattern as `fenrir/hub`. Wrap any command that is not autoloaded, with
  `fenrir/hub--defwrapper`.
- `<f5> n` keeps its search entries. The hub duplicates, never replaces.

### Tier 3 — keys that work in every search prompt (document only)

| in the prompt | effect |
|---|---|
| `foo bar` | orderless: both terms, any order |
| `M-n` | insert the symbol / file name at point |
| `foo -- -g *.go` | ripgrep / fd: everything after ` -- ` goes to the tool as flags |
| `#foo#bar` | ripgrep: `foo` goes to rg, `bar` filters its results locally (perl split style) |
| `<` then a key | narrow by source (`consult-buffer`, `consult-dir`) |
| `C-.` | embark: act on the candidate (other window, copy path, …) |
| `C-. E` | export results; on a grep export, `C-c C-p` = wgrep edit-in-place |

## Implementation map

| file | change |
|---|---|
| [`lisp/init-completion.el`](../../lisp/init-completion.el) | Consult block: define `fenrir/search-files`, `fenrir/search-text` and the shared scope/rerun helper, plus the prompt-only minor-mode keymap (`C-t`, `C-z`, `C-x C-d`). Add `consult-fd` to the `consult-customize` 0.2 s debounce list. Keep `M-s f` / `M-s r` bound for old muscle memory; `M-s f` points at `consult-fd`. |
| [`lisp/init-keys.el`](../../lisp/init-keys.el) | Global `C-t` / `C-z`, the dired `C-t` override, the lazy `fenrir/search-menu` transient, and `("s" …)` in `fenrir/hub--dispatch`. This file only routes; the commands live in `init-completion.el`. |
| [`FEATURES.md`](../../FEATURES.md) | New "Search" section with Tier 1, the in-prompt table and Tier 3. Add a `<f5> s` row to the hub table. Note that `transpose-chars` / `suspend-frame` moved off their keys. |

No new package, no `custom.el` change.

## Non-goals

- No deadgrep, affe, rg.el, or `consult-ag`.
- No change to `C-s` / `consult-line`.
- No change to `M-g` jumps or `<f6>` / `<f7>` history.
- No global `C-o`.
- Not persisting the scope across restarts.

## Acceptance / verification

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

## Open questions

- Should `C-t` / `C-z` be swapped (`C-z` for files)? `C-t` was picked for
  files because file search will be the more frequent one (`find-file` = 410
  presses).
- Scope cycle: is "parent, parent's parent…" useful, or should it be just
  project ⇄ current folder, with `C-x C-d` for everything else?
