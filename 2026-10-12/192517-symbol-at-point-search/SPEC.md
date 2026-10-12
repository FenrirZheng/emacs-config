# Spec: C-u C-t / C-u C-z — search the symbol at point

Status: implemented
Date: 2026-10-12 (Asia/Taipei)

## Objective

- `C-u C-z` opens the text search with the symbol at point already typed, so "where else
  is this used?" is one chord plus a prefix.
- `C-u C-t` does the same for the file search: the symbol at point seeds the file-name
  query (useful on a module name such as `fenrir-search`).
- Everything else about the two prompts stays as it is: the same key still changes the
  folder, the other key still changes the kind, and the seeded text is kept like any
  typed text.
- Without `C-u`, both commands behave exactly as today.

## Design

| key | today | after |
|---|---|---|
| `C-t` / `C-z` | empty prompt | unchanged |
| `C-u C-t` | same as `C-t` (prefix ignored) | prompt seeded with the symbol at point |
| `C-u C-z` | same as `C-z` (prefix ignored) | prompt seeded with the symbol at point, regexp-quoted |

- One pure helper in [`lisp/fenrir-search.el`](../../lisp/fenrir-search.el):
  `fenrir/search--initial-from-point (kind)` → the seed string, or nil when point is on no
  symbol. `kind` `text` returns `(regexp-quote symbol)`, because consult-ripgrep reads its
  input as a regexp and a symbol such as `foo.bar` must match literally. `kind` `files`
  returns the symbol as is.
- `fenrir/search-files` and `fenrir/search-text` take the prefix through their
  `interactive` spec and pass the seed as the existing `initial` argument of
  `fenrir/search--run`. No other code path changes; `fenrir/search-files-here` (dired
  `C-t`) is untouched.
- No symbol at point with `C-u` → an empty prompt, the same as without `C-u`.

## Non-goals

- No change to dired `C-t`, `<f5> s`, or the in-prompt keys.
- No "region as seed" — only the symbol at point.
- No new key binding.

## Acceptance

Run in a throwaway `emacs -nw` inside tmux, not the daemon. Each step starts from
`~/.emacs.d/lisp/fenrir-search.el`.

1. Point on `fenrir/search--run` in the line `(defun fenrir/search--run (kind dir initial
   &optional root origin)`, press `C-u C-z` → prompt `Ripgrep (Project .emacs.d):` whose
   input contains `fenrir/search--run`, with at least 2 matches listed.
2. Point on `fenrir-search` in the line `(provide 'fenrir-search)`, press `C-u C-t` →
   prompt `Fd (Project .emacs.d):` whose input contains `fenrir-search`, and
   `lisp/fenrir-search.el` is among the candidates.
3. Point on an empty line, press `C-u C-z` → prompt `Ripgrep (Project .emacs.d):` with
   empty input (only consult's own `#` if it adds one).
4. After step 1, press `C-z` again → the folder changes to `~/.emacs.d/lisp/` and the
   input still contains `fenrir/search--run`.
5. Point on `fenrir/search--run`, press `C-z` without `C-u` → empty input, as today.

## Open questions

- Regexp-quote the text seed? — default if unanswered: yes (literal match). Accepted
  2026-10-12: default.
- File seed: symbol at point, or `thing-at-point 'filename`? — default if unanswered:
  symbol at point. Accepted 2026-10-12: default.

## Plan

Markers: `[ ]` todo · `[x]` done. The next phase is the first `[ ]`. A `[x]` carries the
commit subject (a commit cannot contain its own hash; `git log --grep` finds it).

### Gate

- [x] Spec approved; open questions answered (or defaults accepted). Approved 2026-10-12,
      both defaults kept: text seed is regexp-quoted, file seed is the symbol at point.

### Test commands (every phase; all must pass)

    emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l test/search-test.el -f ert-run-tests-batch-and-exit
    bash .githooks/pre-commit

Leave no `.elc` behind. Commit only the paths each phase lists.

### Phase 1 — seed helper and prefix arg  [x] `search: seed C-u C-t / C-u C-z with the symbol at point`

Files: `lisp/fenrir-search.el`, `test/search-test.el`
- Add `fenrir/search--initial-from-point (kind)`: `(thing-at-point 'symbol t)`; for
  `text` wrap it in `regexp-quote`; return nil when there is no symbol.
- `fenrir/search-files` / `fenrir/search-text`: signature `(&optional dir seed-p)`,
  `(interactive (list nil current-prefix-arg))`; when `seed-p`, pass
  `(fenrir/search--initial-from-point KIND)` as `initial` to `fenrir/search--run`.
  Update both docstrings to mention `C-u`.
- ERT in `test/search-test.el`, using `with-temp-buffer` + `emacs-lisp-mode`:
  - point on `foo.bar` → `text` seed is `foo\\.bar`, `files` seed is `foo.bar`;
  - point on `fenrir/search--run` → both seeds contain it;
  - point on an empty line → both nil.
- Checks: the three Test commands; search ERT count rises from 15 to at least 18.
- Commit: `search: seed C-u C-t / C-u C-z with the symbol at point`

Done 2026-10-12 (Asia/Taipei).
- Deviations: none that need asking. Recorded: the helper uses `when-let*`; the tests
  share an internal macro `search-test--at` (temp `emacs-lisp-mode` buffer, point after
  a marker).
- Evidence: libsrc ERT 34/34; search ERT 18/18 (was 15; new `search-seed-dotted-symbol`,
  `search-seed-plain-symbol`, `search-seed-empty-line`); `bash .githooks/pre-commit`
  exit 0; no `.elc` left. Full-init batch: `(interactive-form 'fenrir/search-files)` →
  `(interactive (list nil current-prefix-arg))`.
- Commits: `search: seed C-u C-t / C-u C-z with the symbol at point` (2026-10-12) —
  closes Phase 1.

### Phase 2 — docs and acceptance  [x] `docs: document C-u C-t / C-u C-z symbol seeding`

Files: `FEATURES.md`
- §1b key table: add rows for `C-u C-t` and `C-u C-z`.
- Run Acceptance steps 1–5 as written, in a throwaway `emacs -nw` via tmux; record each
  step's observed prompt and input in the Progress note. A step whose input cannot be
  used is recorded `blocked`, never passed with a substitute.
- Checks: the three Test commands.
- Commit: `docs: document C-u C-t / C-u C-z symbol seeding`

Done 2026-10-12 (Asia/Taipei).
- Deviations: none. FEATURES.md §1b gained the `C-u C-t` / `C-u C-z` rows.
- Evidence: libsrc ERT 34/34; search ERT 18/18; `bash .githooks/pre-commit` exit 0.
  Acceptance in a throwaway `emacs -nw` (tmux) on `lisp/fenrir-search.el`, every step on
  its literal input. Point was placed by an `M-:` helper, which reported the symbol at
  point before each step. A `<f9>` binding, defined in that throwaway Emacs only, logged
  the prompt state:
  1. Point on `fenrir/search--run` (line 107), `C-u C-z` → `Ripgrep (Project .emacs.d):`,
     input `#fenrir/search--run`, 17 matches. Pass.
  2. Point on `fenrir-search` in `(provide 'fenrir-search)`, `C-u C-t` →
     `Fd (Project .emacs.d):`, input `#fenrir-search`, candidates
     `("lisp/fenrir-search.el")`. Pass.
  3. Point on an empty line (line 2), `C-u C-z` → `Ripgrep (Project .emacs.d):`, input
     `#` (consult's own). Pass.
  4. After step 1, `C-z` → `Ripgrep (~/.emacs.d/lisp):`, input still
     `#fenrir/search--run`, 5 matches. Pass.
  5. Point on `fenrir/search--run`, `C-z` without `C-u` → input `#`. Pass.
- Note: the first try at steps 1, 4 and 5 never ran. Typing the positioning sexp into
  `M-:` got closing parens auto-inserted, which made it an invalid expression. The
  steps were re-run with a loaded helper (`ah-goto-run`); the inputs under test did not
  change.
- Commits: `docs: document C-u C-t / C-u C-z symbol seeding` (2026-10-12) — closes
  Phase 2 and the spec.
