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
