# Handoff: Magit — a Nested repos section for independent clones inside a repo

Updated: 2026-10-14 12:51 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- Slice 2, the Magit section:
  - `lisp/fenrir-magit-nested.el` adds the `Nested repos (N changed of M)` section after
    Subtrees.
  - It is required after the subtree module in `lisp/init-git.el`.
  - `test/magit-nested-test.el` has 11 tests.
  - The FEATURES.md Magit paragraph and the `_doc/ARCHITECTURE.md` init-git row are written.
  - The rust READMEs now link the module instead of saying "next slice".
  - Commits: `git: show the nested clones of a repo in Magit` (`e437ed1`), then the test
    fix from the advisor review, `git: test the Nested repos section on the spec's literal
    inputs` (`6579a21`).
  - Checked:
    - criteria 4, 5, 9, 10 and 11 pass via the ERT suite (11/11);
    - criterion 13: libsrc 36/36, search 18/18, magit-subtree 13/13, magit-time 4/4, and the
      `fdfind` `.elc` check prints nothing.
  - Mutation checks:
    - `show-in-status nil` → 5 integration tests fail;
    - `skip-directories nil` → both home tests fail (the `~` scan then takes 3.4 s).
- Slice 1, the helper binary end to end:
  - crate `rust/git-tools/git-nested-status/`, plus `make-fixture.sh`, `tests/fixture.sh`,
    `tests/check-repo.sh` and the READMEs;
  - commit `rust: add git-nested-status, a nested-clone status helper` (`ddd40cd`), then
    `rust: let git-nested-status honour the global ignore file` (`ab73c73`);
  - criteria 1–3, 6, 7 and 12 were checked then;
  - yeeya warm medians were 39.9, 44.5 and 39.5 ms (all three runs on 2026-10-14);
  - preceded by `rust: move git-subtree-status into the git-tools cargo workspace`
    (`08c766e`).

## 決定與原因

- Route: a sliced spec. The work is three natural slices: a crate, a Lisp module, and docs
  with the live timing (user answer, 2026-10-14).
- Scope:
  - The default scan is `<top>/*/.git` and `<top>/*/*/.git`.
  - `git config nested.depth N` (0 = off) and `git config --add nested.path <dir>`
    override it.
  - The Lisp skips `fenrir/magit-nested-skip-directories`, default `("~/")` (user answer +
    approved default).
  - In the helper, `--depth` wins, and depth 0 means nowhere, even with paths. Paths scan
    their immediate children only.
- Rows:
  - Only changed clones get a row; the heading counts all of them.
  - Changed means uncommitted paths, ahead/behind > 0, or a detached HEAD. No upstream
    alone is not a change, and such a row says `no upstream`.
  - When no clone changed, no section is drawn, as in Subtrees.
  - `U:n` counts distinct paths, so a file both staged and unstaged counts once.
- The git crates share one cargo workspace, `rust/git-tools/` (user direction, 2026-10-14).
- SPEC corrections approved with the slice-1 plan:
  - yeeya has 29 clones;
  - criterion 10 runs on `/tmp/magit-nested-fixture/repos/clean`, because `~/.emacs.d` has
    3 `package-vc` clones under `elpa/`.
- One noun, `nested`: the crate `git-nested-status`, the module `fenrir-magit-nested.el`, the
  heading `Nested repos`, and the section types `fenrir-nested-repos` / `fenrir-nested` /
  `fenrir-nested-file`.
- The Lisp runs `--porcelain --files` once per refresh. It takes the file list from the
  helper, because Magit has not drawn these clones' files. The section hook runs no Git
  command.
- The section hook is anchored after `fenrir/magit-subtree-insert-section`, or after
  `magit-insert-staged-changes` when that hook is absent. Two hooks appended after the same
  anchor end up in reverse order. `magit-nested-hook-after-subtrees` checks the hook order.
- A missing binary gives one `message` per session (`Nested repos: … is not built -- run:
  make -C …/rust/git-tools`), never an error.
- Test inputs:
  - The integration tests rebuild `/tmp/magit-nested-fixture` with `make-fixture.sh`.
  - They count helper runs through a logging wrapper bound as `fenrir/magit-nested-program`.
  - `::unbuilt` renames the real `rust/lib/git-nested-status` aside and restores it in
    `unwind-protect`. That is the spec's literal input "absent".
- The helper and discovery decisions from slice 1 still hold:
  - each clone is opened with `gix::open` at its `.git` path, never with discover;
  - errors go to stderr, and the clone is left out;
  - symlinked dirs are skipped.

## 下一步

Slice 3, the live timing and the docs (criteria 8 and 14):

1. Make the running daemon load the module, because it predates `e437ed1`. Either restart it
   or run `emacsclient -e '(require (quote fenrir-magit-nested))'`.
2. Confirm that `fenrir/magit-nested-insert-section` sits after the subtree hook in
   `magit-status-sections-hook`. Otherwise both timings are equal and look like a pass.
3. With `magit: yeeya` open, time one `magit-refresh-buffer` as
   [`_doc/GOTCHAS.md`](../../../_doc/GOTCHAS.md) says. Time it with the section on, then with
   `fenrir/magit-nested-show-in-status` nil. The difference must be ≤ 0.15 s.
4. Write both numbers, dated, into the crate README, beside the slice-1 helper medians that
   criterion 7 needs. Add the phrase `Nested repos` there: the crate README is the one file
   of criterion 14's four that lacks it today. FEATURES.md, `rust/README.md` and
   `_doc/ARCHITECTURE.md` already hit.
5. Add a cost line to the FEATURES.md Nested repos paragraph.

Commit subject: `docs: record the Nested repos section's cost on yeeya`.
After that slice, 下一步 is the acceptance gate.

## 卡住・待確認

- Nothing blocked. Criterion 11's test moves the real `rust/lib/git-nested-status` aside for
  about 0.3 s. That path is gitignored and is restored by `unwind-protect`. SPEC's `副作用`
  for 11 names only `/tmp/magit-nested-fixture`. Whether to add the binary rename there is a
  SPEC change for the user's approval before the gate.
- Untracked in the repo, but not this spec's: `AGENTS.md`, `plans/`, `records/`.
- The scripts leave `/tmp/magit-nested-fixture` in place (the criteria's declared 副作用).
