# Plan: one search system

Spec: [SPEC.md](SPEC.md)
Progress markers: `[ ]` todo · `[x]` done (commit hash appended). The next phase
is the first `[ ]`.

## Gate (before Phase 1)

- [ ] SPEC approved. Open questions settled. Defaults if unanswered: `C-t` = files,
      `C-z` = text; full parent cycle (project → current → parent … → wrap).

## Test commands (every phase; all must pass)

    emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l test/search-test.el -f ert-run-tests-batch-and-exit   # from Phase 1
    bash .githooks/pre-commit        # paren check + whole-init smoke load

Leave no `.elc` behind. Commit only the paths each phase lists.

## Phase 1 — core commands + in-prompt keymap  [ ]

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

## Phase 2 — global and dired keys  [ ]

File: `lisp/init-keys.el` (routing only).
- Global `C-t` → `fenrir/search-files`, `C-z` → `fenrir/search-text`, both
  `global-set-key`/`keymap-global-set`, not `bind-key*`, so vterm keeps them.
- `dired-mode-map` `C-t` → file search rooted at the dired dir (via
  `with-eval-after-load 'dired`).
- Check: the SPEC's `emacsclient -e '(list (key-binding …))'`; SPEC steps 5–6.
- Commit: `keys: bind C-t / C-z to search`.

## Phase 3 — `<f5> s` search menu  [ ]

File: `lisp/init-keys.el`.
- Define `fenrir/search-menu` inside the existing `with-eval-after-load 'transient`
  block (starts at around line 183), using the SPEC layout. Add `("s" …)` to
  `fenrir/hub--dispatch` (line 400 onwards). Leave `<f5> n` unchanged.
- Use `fenrir/hub--defwrapper` (line 134) for any non-autoloaded command. The
  `e` entry checks for eglot and reports it when eglot is off.
- Check: `(featurep 'transient)` is nil in a fresh daemon; every letter of
  `<f5> s` runs without `void-function` (SPEC step 7).
- Commit: `keys: add <f5> s search menu`.

## Phase 4 — docs + acceptance  [ ]

Files: `FEATURES.md`, `SPEC.md` (status → implemented).
- New "Search" section: Tier 1, the in-prompt table, Tier 3. Add a `<f5> s` row to
  the hub table (around line 40). Note that `transpose-chars` and `suspend-frame`
  moved off their keys.
- Run the full SPEC acceptance list (steps 1–8, TTY and GUI) and compare
  `emacs-init-time` with the current value.
- Commit: `docs: document one-search keys`.
