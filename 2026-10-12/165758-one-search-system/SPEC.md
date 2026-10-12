# Spec: one search system — single-chord keys, no prefix

Status: implemented (rev 2), approved 2026-10-12 with the defaults (`C-t` files,
`C-z` text, full parent cycle). Commits: `15cc6e1` (commands + prompt keys),
`bf0f62f` (global / dired keys), `590a2a7` (`<f5> s` menu), plus the docs commit.
Deviations and evidence: [Plan](#plan) below (merged in from the former PLAN.md).
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

## Plan

Progress markers: `[ ]` todo · `[x]` done (commit subject appended; a commit
cannot carry its own hash — `git log --grep` finds it). The next phase is the
first `[ ]`.

### Gate (before Phase 1)

- [x] SPEC approved 2026-10-12, defaults kept: `C-t` = files, `C-z` = text; full
      parent cycle (project → current → parent … → `/` → wrap).

### Test commands (every phase; all must pass)

    emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l test/search-test.el -f ert-run-tests-batch-and-exit   # from Phase 1
    bash .githooks/pre-commit        # paren check + whole-init smoke load

Leave no `.elc` behind. Commit only the paths each phase lists.

### Phase 1 — core commands + in-prompt keymap  [x] `completion: add fenrir/search-files and search-text`

Files: `lisp/init-completion.el`, new `test/search-test.el`.
- Pure helper `fenrir/search--next-scope (dir root)` → next dir (current → parent
  … stops at `/`, wraps to root). Pure helper for the WHAT toggle.
- `fenrir/search-files` (`consult-fd`) and `fenrir/search-text` (`consult-ripgrep`).
  Both start at the project root, or at `default-directory` when there is no project.
  Shared `fenrir/search--run (kind dir initial)`.
- A minor mode `fenrir/search-prompt-mode` with a keymap for `C-t`, `C-z` and
  `C-x C-d`. The keymap goes on `minor-mode-overriding-map-alist` or
  `emulation-mode-map-alists` in the minibuffer, so it beats `vertico-map`'s
  `C-x C-d` from `init-dired.el:127`. Each key saves `(minibuffer-contents)`,
  sets up `run-at-time 0` to rerun, and calls `abort-recursive-edit`.
- `consult-fd-args` uses `fdfind` (the binary name on Debian).
- Add `consult-fd` to the `consult-customize` debounce list (`init-completion.el:145`).
- Rebind `M-s f` to `consult-fd` (line 118). Leave `M-s r` as is.
- ERT tests the pure helpers: the scope cycle, the wrap at `/`, and the no-project root.
- Extra check: in the daemon, `M-x fenrir/search-files` / `fenrir/search-text` work
  and the in-prompt keys cycle (manual SPEC steps 1–4, reached via `M-x`).
- Commit: `completion: add fenrir/search-files and search-text`.

Done 2026-10-12 (Asia/Taipei). Deviations from the bullets above:
- The commands live in a new [`lisp/fenrir-search.el`](../../lisp/fenrir-search.el),
  which `init-completion.el` requires (the `fenrir-back-forward.el` pattern), because
  `test/search-test.el` must load them in `emacs -Q` and `init-completion.el` is all
  `use-package`.
- The scope helper is `fenrir/search--next-scope (dir root origin)` over
  `fenrir/search--scopes`; the WHAT toggle is `fenrir/search--next-state`.
- The keymap is a plain buffer-local minor mode in the minibuffer. Minor-mode maps
  already beat Vertico's local map, so neither overriding alist was needed.
- `consult-fd-args` is unchanged: consult's default already picks `fdfind` when it
  exists.

Evidence: libsrc ERT 34/34, search ERT 11/11, `bash .githooks/pre-commit` exit 0.
A throwaway `emacs -nw` driven via tmux, starting from `M-: (fenrir/search-files)`
(global keys come in Phase 2):
- `C-t` cycles WHERE: root → `lisp/` → `~` (`.emacs.d/` is skipped as the root).
- `C-z` / `C-t` switch WHAT in the same folder.
- `C-x C-d` → `~/cz/` reruns there.
- The typed text survives every switch, with no doubled `#`.
- A non-project `default-directory` starts there.
- `M-s f` → `consult-fd`.

### Phase 2 — global and dired keys  [x] `keys: bind C-t / C-z to search`

File: `lisp/init-keys.el` (routing only).
- Global `C-t` → `fenrir/search-files`, `C-z` → `fenrir/search-text`, both
  `global-set-key`/`keymap-global-set`, not `bind-key*`, so vterm keeps them.
- `dired-mode-map` `C-t` → file search rooted at the dired dir (via
  `with-eval-after-load 'dired`).
- Check: the SPEC's `emacsclient -e '(list (key-binding …))'`; SPEC steps 5–6.
- Commit: `keys: bind C-t / C-z to search`.

Done 2026-10-12 (Asia/Taipei). Deviation: the dired key needs a command that
starts in the dired folder rather than the project root. `fenrir/search-files-here`
was added to `lisp/fenrir-search.el`, because `init-keys.el` only routes keys.

Evidence: libsrc ERT 34/34, search ERT 11/11, `bash .githooks/pre-commit` exit 0.
A throwaway `emacs -nw` was driven via tmux, without the daemon:
- `(key-binding "C-t"/"C-z")` → `fenrir/search-files` / `fenrir/search-text`, and
  `dired-mode-map` `C-t` → `fenrir/search-files-here`.
- `C-t` in dired on `lisp/languages/` → `Fd (…/lisp/languages)`, and `init-go`
  finds `init-go.el`.
- vterm: `sleep 30` + `C-z` → `Stopped`, and `abc` + `C-t` → `acb`.
- Note: nothing searches before 3 characters, because consult's
  `consult-async-min-input` is 3. This is consult behaviour, not this config.
- Note: `C-t` / `C-z` are now global inside minibuffers too, where they used to
  run `transpose-chars` / `suspend-frame`. Only the one-search prompts rebind them.

### Phase 3 — `<f5> s` search menu  [x] `keys: add <f5> s search menu`

File: `lisp/init-keys.el`.
- Define `fenrir/search-menu` inside the existing `with-eval-after-load 'transient`
  block (starts at around line 183), using the SPEC layout. Add `("s" …)` to
  `fenrir/hub--dispatch` (line 400 onwards). Leave `<f5> n` unchanged.
- Use `fenrir/hub--defwrapper` (line 134) for any non-autoloaded command. The
  `e` entry checks for eglot and reports it when eglot is off.
- Check: `(featurep 'transient)` is nil in a fresh daemon; every letter of
  `<f5> s` runs without `void-function` (SPEC step 7).
- Commit: `keys: add <f5> s search menu`.

Done 2026-10-12 (Asia/Taipei).
- Deviation: the `e` eglot check is a command, `fenrir/search-lsp-symbols` in
  `lisp/fenrir-search.el`, because it is more than a require-and-call wrapper.
- `t` is `consult-todo-project`.
- `K` is `embark-bindings`.
- No `fenrir/hub--defwrapper` was needed: every other menu command is in its
  package's `*-autoloads.el`.

Evidence: libsrc ERT 34/34, search ERT 11/11, `bash .githooks/pre-commit` exit 0.
- Batch `emacs -Q -l init.el`: every `fenrir/search-menu` suffix is `commandp`, and
  hub `s` → `fenrir/search-menu`.
- In a throwaway `emacs -nw` (tmux), `<f5> s` shows the SPEC layout. All 21 letters
  were pressed, and `*Messages*` has no `void-function`. `e` without eglot prints
  its notice. `h` outside org gives consult's own "Must be called from an Org
  buffer".
- **Check not met, and the cause is not this phase:** `(featurep 'transient)` is
  already `t` right after init. combobulate's autoloads file requires
  `combobulate-ui`, which requires transient during `package-initialize`; the
  backtrace shows `combobulate-autoloads` → `combobulate-ui` → `transient`. This
  config's lazy hub does not load it. The SPEC's "nil after a fresh start"
  expectation is stale until combobulate changes.

### Phase 4 — docs + acceptance  [x] `completion: accept a typed folder in the search C-x C-d`

Commits: `docs: document one-search keys` (2026-10-12) — docs; `docs: record one-search
acceptance results` (2026-10-12) — TTY step 8 + init time; `docs: record one-search GUI
acceptance run` (2026-10-12) — GUI steps 1–8, reopened on step 2; `completion: accept a
typed folder in the search C-x C-d` (2026-10-12) — step 2 fix, closes the phase.

Files: `FEATURES.md`, `SPEC.md` (status → implemented).
- New "Search" section: Tier 1, the in-prompt table, Tier 3. Add a `<f5> s` row to
  the hub table (around line 40). Note that `transpose-chars` and `suspend-frame`
  moved off their keys.
- Run the full SPEC acceptance list (steps 1–8, TTY and GUI) and compare
  `emacs-init-time` with the current value.
- Commit: `docs: document one-search keys`.

Progress 2026-10-12 (Asia/Taipei). Closed after the step 8 and init-time runs
below. The GUI-frame run was not done (see the end of this note).
- [x] Docs, in `docs: document one-search keys`.
  - `FEATURES.md`: a new §1b "Search" section (Tier 1, the in-prompt table,
    examples, the moved `transpose-chars` / `suspend-frame`, vterm, Tier 3).
  - `FEATURES.md`: a `<f5> s` hub row, and the daily-card `C-t` / `C-z` row in
    place of `M-s r`.
  - `FEATURES.md`: §1 `M-s f` → `consult-fd`, plus the debounce list.
  - `FEATURES.md`: §2's combo starts from `C-z`, and §12 has a dired `C-t` row.
  - `SPEC.md`: the status is implemented, with the commit list.
  - `fenrir/features-audit`: no search command shows up as drift.
- Acceptance coverage so far (TTY only, throwaway `emacs -nw`):
  - [x] Steps 1–4 (Phase 1).
  - [x] Steps 5–6 (Phase 2).
  - [x] Step 7: no `void-function` (Phase 3). Its `(featurep 'transient)` = nil
        part fails for the pre-existing combobulate reason recorded in Phase 3.
  - [x] Step 8: wgrep round trip, on two scratch files (`a.txt`, `b.txt`, each with
        one `foo`) in a temp dir outside any project.
    - `C-z` + `foo` → `Ripgrep (…/scratchpad/wg)` with 2 matches.
    - `embark-act` → `E` → `*Embark Export: consult-ripgrep - #foo*`.
    - `C-c C-p`, `M-%` foo→bar `!`, `C-c C-c` → `Successfully finished. (2 changed)`.
    - On disk: `alpha bar one` and `bar two`.
    - **TTY caveat:** the `C-.` key itself never reaches a TTY Emacs here. tmux has
      `extended-keys off`, so tmux delivers it as a plain `.`. The test therefore
      bound `embark-act` to `C-c .` in the throwaway session only. This is
      pre-existing (embark's binding, same class as `C-,` / `C-'` in the SPEC), not
      a search regression. In a TTY frame, FEATURES.md §1b's `C-. E` works only if
      tmux passes extended keys.
  - [x] `emacs-init-time`: within noise. HEAD median 0.447 s (0.438–0.497, one
        outlier). Base median 0.450 s (0.442–0.453).
    - Method: [`scripts/inittime.sh`](scripts/inittime.sh). The real `emacs -nw` in
      tmux, `--eval` logs `(emacs-init-time "%f")`, then exits with
      `kill-emacs-hook` nil.
    - Base means the `15cc6e1^` versions of `init-completion.el` and `init-keys.el`,
      written in place, so paths and `.eln` stay comparable; a worktree would
      change every path and force a native recompile. HEAD's files are restored by
      `git checkout HEAD --` on exit, and `git status lisp/` was clean afterwards.
    - 2 warm-up runs per variant, then 6 alternating runs each.
  - GUI frame run, 2026-10-12:
    - Setup: a throwaway `emacs` (X11/GTK3 build on Xwayland `:0`), never the
      daemon. It ran with [`scripts/gui-harness.el`](scripts/gui-harness.el),
      which starts a private server `srchgui`. It exited with `kill-emacs-hook`
      nil, and its socket was removed.
    - Input method: `emacsclient -s srchgui` queued real key events into that
      process's `unread-command-events`. `C-.` is the GUI event 67108910, which a
      TTY cannot represent. The window system did not deliver the keys: the
      session is Wayland, no xdotool/ydotool is installed, and XTEST could reach
      the daemon's X frame. Evidence was read from a `minibuffer-setup-hook` log
      and from `*Messages*`.
    - Key check: `C-t` → `fenrir/search-files`, `C-z` → `fenrir/search-text`,
      dired `C-t` → `fenrir/search-files-here`, `C-.` → `embark-act`, and
      `display-graphic-p` = t.
  - [x] GUI step 1: `C-t`, `init`, `C-t` went from `Fd (Project .emacs.d)` with
        39 candidates to `Fd (~/.emacs.d/lisp)` with 36, and the input stayed `#init`.
  - [ ] GUI step 2 **fails as written**. "`C-x C-d`, pick `~/code`" cannot pick
        `~/code` itself.
    - `~/code/` is not among consult-dir's 129 candidates.
    - `code` + `RET` picks the first match, `~/code/agent-workflow/`.
    - Typing `~/code/` + `M-RET` errors with `bookmark-get-bookmark: Invalid
      bookmark ~/code/`, because `consult-dir--pick` gives free input the
      bookmark category.
    - The mechanism itself passes: the rerun happens in the picked folder, and
      `#init` is kept.
    - The same limit applies in a TTY frame. The earlier TTY run used `~/cz/`,
      which is a candidate.
    - Fix options, not done:
      1. Accept a typed existing directory in `fenrir/search-prompt-pick-dir`.
      2. Add `~/code` to the consult-dir quick list.
      3. Reword SPEC step 2.
    - **Fixed with option 1** (user's choice, 2026-10-12), in
      `completion: accept a typed folder in the search C-x C-d`:
      - `fenrir/search-prompt-pick-dir` no longer calls `consult-dir--pick`.
      - Instead it makes the same `consult--multi` call, over `consult-dir-sources`
        with `consult-dir-sort-candidates`.
      - It resolves the result with the new pure helper `fenrir/search--picked-dir`.
        A listed candidate resolves by category: `bookmark` through
        `bookmark-get-filename`, `file` as itself.
      - Typed input (`:match nil`) is accepted when it names an existing folder.
        Anything else gives a `user-error` "Not an existing folder: …", and the
        search prompt stays open.
      - ERT `search-picked-dir-*` (4 tests) covers: a typed existing folder (with
        and without the trailing slash; the bookmark resolver is never called),
        `~/`, a missing path or a file, and listed `file` / `bookmark` candidates.
    - [x] GUI step 2, rerun after the fix (same harness, a throwaway GUI Emacs):
      - `C-t`, `init`, `C-x C-d`, `~/code/`, `M-RET` → `Fd (~/code)`, input
        `#init`, 3152 candidates.
      - A listed candidate still works: `cz` + `RET` → `Fd (Project cz)`, `#init`
        kept.
      - `/no/such/dir/` + `M-RET` → `Not an existing folder: /no/such/dir/`, and
        the `Fd (Project cz)` prompt is still active.
  - [x] GUI step 3: `C-t`, `parser`, `C-z` → `Ripgrep (Project .emacs.d)` with
        input `#parser` and 466 matches, in the same folder.
  - [x] GUI step 4: `C-z` from `/usr/share/doc/bash/README`, which is in no
        project → `Ripgrep (…/doc/bash)`.
  - [x] GUI step 5: `C-t` in dired on `lisp/languages/` → `Fd (…/lisp/languages)`,
        and `init-go` finds 1 file.
  - [x] GUI step 6: in vterm, `C-t` / `C-z` are `vterm--self-insert`. `sleep 30` +
        `C-z` → `Stopped`, and `abc` + `C-t` → `acb`.
  - [x] GUI step 7: `<f5> s` → `fenrir/search-menu`. All 21 letters opened their
        commands' prompts. The exceptions are `e` (eglot notice), `h` ("Must be
        called from an Org buffer") and `m` ("No global marks"). There is no
        `void-function`.
  - [x] GUI step 8: **`C-. E` works in a GUI frame.**
    - `C-z` + `foo` → `C-.` → `E` gave `*Embark Export: consult-ripgrep - #foo*`
      with both matches.
    - `C-c C-p`, `M-%` foo→bar `!`, `C-c C-c` → `Successfully finished.
      (2 changed)`.
    - Both scratch files contain `bar` on disk.
