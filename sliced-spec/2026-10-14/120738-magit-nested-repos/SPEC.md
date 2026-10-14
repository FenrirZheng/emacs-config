# Spec: Magit — a Nested repos section for independent clones inside a repo

Status: approved
Date: 2026-10-14 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)

## 目標

- A repo that holds independent clones — a subdirectory with its own `.git`, such as
  `~/code/yeeya`'s `repos/*` (30 clones on 2026-10-14) — gets a `Nested repos` section in its
  Magit status buffer, after the Subtrees section. Today that buffer says nothing about them,
  and the Subtrees section does not apply: yeeya has no `git subtree` trailer.
- The heading counts every clone found; the rows are the clones with something to act on:
  uncommitted paths, commits ahead of or behind the upstream, or a detached HEAD.
- A row shows the clone's path, its branch (or that HEAD is detached), how far it is ahead of
  or behind its upstream, and the number of uncommitted paths. It unfolds to the files, and
  opens the clone's own Magit status.
- The data comes from a new helper binary in the [`rust/` workspace](../../../rust/README.md),
  read-only and offline, one process per refresh, fast enough that a yeeya refresh stays
  interactive.
- Repos without nested clones, and `$HOME`, are unaffected.

## 不做的事

- No fetch; ahead/behind is as of the clone's last fetch.
- No submodule or `git subtree` handling (the Subtrees section already covers subtrees).
- No stage, unstage or commit from the section; `RET` goes to the clone's own status buffer.
- No cache file; no scan of `$HOME` (`code/*` alone holds about 100 clones).
- No new Emacs package; no change to the Subtrees section.

## 驗收條件

Fixture: [`make-fixture.sh`](make-fixture.sh) `<dir>` builds `/tmp/magit-nested-fixture`: an
umbrella repo with one commit and `/repos/` gitignored, holding `repos/dirty` (a clone of a
bare `origin`, one local commit on `main` → ahead 1, one unstaged edit, one untracked file),
`repos/clean` (a clone in sync with its origin), `repos/detached` (a clone checked out at a
commit hash), `repos/plain` (a directory with one file and no `.git`) and `deep/x/y` (a clone
at depth 3). Building it is setup. The exact values below are the fixture's.

1. `git-nested-status -C /tmp/magit-nested-fixture --porcelain` → the first line is
   `# git-nested-status v1`, then rows for exactly `repos/clean`, `repos/detached`,
   `repos/dirty`, in that order; the `repos/dirty` row says branch `main`, upstream
   `origin/main`, ahead 1, behind 0, staged 0, unstaged 1, untracked 1; the `repos/detached`
   row says detached; no row for `repos/plain` or `deep/x/y` — test:
   `rust/git-nested-status/tests/fixture.sh` — 副作用: writes `/tmp/magit-nested-fixture`
2. After `git -C /tmp/magit-nested-fixture config nested.depth 3`, the command of 1 → a
   `deep/x/y` row is added; after `git -C /tmp/magit-nested-fixture config nested.depth 0` →
   the header line only; after `git -C /tmp/magit-nested-fixture config --unset nested.depth`
   and `git -C /tmp/magit-nested-fixture config --add nested.path deep/x` → the `deep/x/y`
   row only, no `repos/*` row — test: `rust/git-nested-status/tests/fixture.sh` — 副作用:
   edits `/tmp/magit-nested-fixture/.git/config`
3. `git-nested-status -C /tmp/magit-nested-fixture --porcelain --files` → under the
   `repos/dirty` row, one file line per uncommitted path with its kind (`unstaged`,
   `untracked`); none under `repos/clean` — test: `rust/git-nested-status/tests/fixture.sh` —
   副作用: writes `/tmp/magit-nested-fixture`
4. `magit-status` on `/tmp/magit-nested-fixture` (batch Emacs with the packages in `elpa/`)
   → a section headed `Nested repos (2 changed of 3)`, placed after Staged changes (and after
   Subtrees when that section is present), with the rows `repos/detached` and `repos/dirty`
   and no `repos/clean`; the `repos/dirty` line shows `main`, ahead 1 and 2 uncommitted paths
   — test: `test/magit-nested-test.el::status-section` — 副作用: writes
   `/tmp/magit-nested-fixture`
5. In that buffer: `TAB` on the `repos/dirty` row → its two file lines appear, each marked
   `unstaged` or `untracked`; `RET` on a file line → that file is visited; `RET` on the row →
   a Magit status buffer for `/tmp/magit-nested-fixture/repos/dirty/` — test:
   `test/magit-nested-test.el::row-actions` — 副作用: writes `/tmp/magit-nested-fixture`
6. `git-nested-status -C ~/code/yeeya --porcelain` → the row paths are exactly the `repos/<d>`
   for which `~/code/yeeya/repos/<d>/.git` exists, sorted (30 on 2026-10-14), and none of
   `repos/android_yeeya_apk`, `repos/logs`, `repos/opus-rewrite` (directories without `.git`)
   — test: `rust/git-nested-status/tests/check-repo.sh ~/code/yeeya`, which compares against
   `find ~/code/yeeya -mindepth 2 -maxdepth 3 -name .git` — 副作用: none
7. `rust/git-nested-status/tests/check-repo.sh ~/code/yeeya` → prints the 10-run median of
   `git-nested-status -C ~/code/yeeya --porcelain --files`, warm, and that median is
   ≤ 100 ms — test: the same script — 副作用: none
8. The daemon with `magit: yeeya` open: one `magit-refresh-buffer`, timed as
   [`_doc/GOTCHAS.md`](../../../_doc/GOTCHAS.md) says, with the section on and then with
   `fenrir/magit-nested-show-in-status` nil → the difference is ≤ 0.15 s; both numbers go
   into the crate README — test: manual (needs the daemon) — 副作用: none
9. `C-x g` in `~` (the dotfiles repo) → no `Nested repos` section, and the helper is not run
   — test: `test/magit-nested-test.el::home-skipped` — 副作用: none
10. `magit-status` on `~/.emacs.d` (no nested clone) → no section; a second refresh does not
    run the helper again; `M-x fenrir/magit-nested-forget` and a refresh run it once more —
    test: `test/magit-nested-test.el::none-remembered` — 副作用: none
11. With `rust/lib/git-nested-status` absent, `magit-status` on `/tmp/magit-nested-fixture`
    → no section and no error in `*Messages*` — test: `test/magit-nested-test.el::unbuilt` —
    副作用: writes `/tmp/magit-nested-fixture`
12. `make -C ~/.emacs.d/rust verify` → exit 0, and its output includes the new crate;
    `cargo test` run in `rust/git-nested-status` → every test passes — test: those two
    commands — 副作用: writes `rust/lib/git-nested-status` and
    `rust/git-nested-status/target/` (both gitignored)
13. `emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit`, and the same
    for `test/search-test.el`, `test/magit-subtree-test.el`, `test/magit-time-test.el` → all
    pass; `fdfind --no-ignore -e elc --exclude elpa --exclude eln-cache .` in `~/.emacs.d`
    lists nothing — test: those commands — 副作用: none
14. `ug -n "Nested repos" FEATURES.md rust/README.md _doc/ARCHITECTURE.md rust/git-nested-status/README.md`
    in `~/.emacs.d` → a hit in each of the four files; the crate README carries the dated
    measurements of 7 and 8 — test: manual (one grep plus a read) — 副作用: none

## 限制

- **Existing environment to reuse**: the one Emacs 30.1 daemon (TTY frame in tmux plus a GUI
  frame), Magit from `elpa/`, and [`lisp/init-git.el`](../../../lisp/init-git.el), which
  already loads the Subtrees module after Magit; the [`rust/` workspace](../../../rust/README.md)
  and its rules (a self-contained Makefile per subproject with `all` / `install` / `verify` /
  `clean` / `distclean`, deployment into `rust/lib/`, the aggregator's subproject list, a
  `/rust/<name>/target/` line in the root [`.gitignore`](../../../.gitignore)); rustc 1.98 with
  mold, set up as in [`rust/git-subtree-status`](../../../rust/git-subtree-status/README.md);
  gix 0.89 from the local cargo registry; `~/code/yeeya` as the real repo. Nothing else is
  created; fixtures live under `/tmp`.
- The helper never runs `git`, never fetches and never writes into any repo.
- Discovery: a subdirectory is a nested clone iff it has a `.git` entry (directory or file).
  It is opened at that path, never found by walking upward (a plain subdirectory must not
  report the umbrella's own state). A found clone is not descended into, and `.git` itself is
  skipped. The default depth is 2; `nested.depth` and `nested.path` are read from the
  umbrella repo's git config.
- Dependencies: gix and the standard library only (threads over the clones; no rayon).
- The Lisp module follows the Subtrees module's shape: a defcustom for the program path, a
  show-in-status toggle, a per-session memory of repos with no clone plus a `-forget`
  command, section values that keep their fold state across `g`, and a build hint instead of
  an error when the helper is not built.
- A status refresh runs no Git command Magit does not already run, plus the one helper
  process.
- [`FEATURES.md`](../../../FEATURES.md) is updated in the same change as the Lisp.
- No `.elc` is left behind by any check.

## 待決問題

- Does a clone with no upstream count as changed? — default if unanswered: no; when listed
  for another reason its row says `no upstream`.
- Are `nested.path` entries scanned one level deep (their immediate children)? — default if
  unanswered: yes.
- Which directories does the Lisp skip? — default if unanswered: `~/` only, as a defcustom.
- Show the clone's HEAD subject on the row? — default if unanswered: no.

The user approved these defaults on 2026-10-14.
