# Plan: one search system

Spec: [SPEC.md](SPEC.md)
Progress markers: `[ ]` todo · `[x]` done (commit subject appended; a commit
cannot carry its own hash — `git log --grep` finds it). The next phase is the
first `[ ]`.

## Gate (before Phase 1)

- [x] SPEC approved 2026-10-12, defaults kept: `C-t` = files, `C-z` = text; full
      parent cycle (project → current → parent … → `/` → wrap).

## Test commands (every phase; all must pass)

    emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l test/search-test.el -f ert-run-tests-batch-and-exit   # from Phase 1
    bash .githooks/pre-commit        # paren check + whole-init smoke load

Leave no `.elc` behind. Commit only the paths each phase lists.

## Phase 1 — core commands + in-prompt keymap  [x] `completion: add fenrir/search-files and search-text`

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

## Phase 2 — global and dired keys  [x] `keys: bind C-t / C-z to search`

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

## Phase 3 — `<f5> s` search menu  [x] `keys: add <f5> s search menu`

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

## Phase 4 — docs + acceptance  [x] `docs: document one-search keys` + `docs: record one-search acceptance results` + `docs: record one-search GUI acceptance run` + `completion: accept a typed folder in the search C-x C-d`

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
