# Spec: Magit — one commit timeline across every git subtree

Status: draft
Date: 2026-10-21 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)

## 目標

- In a repo built from `git subtree` (here `~/code/ig_lottery_hotfix`, 55 subtrees), one
  Emacs buffer lists the commits of every project together, newest first by commit time.
  Today `l S` shows one subtree at a time, so work that spans several projects (the
  澳洲幸運5 odds integration touches odds-server, odds-web-crawler, odds-web-ag, tg_infra
  and `repos/clawer/clawer_australian_lucky_5`) cannot be read in one place.
- Each row names the project(s) the commit touched:
  - a subtree is named by its prefix's last component (`odds-web-ag`);
  - a path under `repos/` that belongs to no subtree is named by its first directory under
    `repos/` (`clawer`);
  - any other path is named `(umbrella)`.
- One commit is one row, even when it touches several projects.
- The list can be narrowed to chosen projects, and its date range can be changed. Refreshing
  keeps both choices.
- `RET` on a row opens that commit, the way `RET` does in a Magit log.
- It is reached from the Magit log menu next to `l S`.

## 不做的事

- The `p/*` project-side refs (other developers' commits upstream) are not listed. Ownership
  there comes from the ref, and matching them against the umbrella's split copies needs
  patch-id dedup. That is a follow-up. The buffer header says that only umbrella commits are
  shown.
- No new Rust binary, and no change to `git-subtree-status`. Measured 2026-10-21, Elisp
  with per-directory memoization parses 30 days of history (578 commits) in 84 ms, against
  31 ms for `git log`. The move to Rust is a follow-up, triggered by 驗收條件 7 failing.
- The status buffer's Subtrees section and `l S` stay as they are.

## 驗收條件

Batch tests run with
`emacs -Q --batch -l test/magit-subtree-test.el -f ert-run-tests-batch-and-exit` from
`~/.emacs.d`. They use the suite's existing throwaway fixture under
`temporary-file-directory`, which has subtrees `libs/full` and `libs/sq` and a host commit
`root`. The manual criteria use the running daemon on the real repo `~/code/ig_lottery_hotfix`,
with HEAD and branches as of 2026-10-21.

1. Parse `git log --name-only --format='%x00%H%x09%ct%x09%s'` output.
   - Input: a literal string of two commits, one with two paths and one with no path.
   - Expected: two entries with hash, integer commit time, subject and paths in input order.
   - Test: `test/magit-subtree-test.el::magit-subtree-parse-log`.
   - 副作用: none.
2. Label a commit's paths.
   - Input: the suite's porcelain rows (`libs/a`, `libs/a/b`, `libs/c`).
   - Expected:
     - `("libs/a/b/x.rs" "libs/c/y")` → `"b,c"`;
     - `("repos/clawer/z/a.md")` → `"clawer"`;
     - `(".scratch/m.md" "libs/c/y")` → `"c,(umbrella)"`;
     - `()` → `"(umbrella)"`.
   - Test: `test/magit-subtree-test.el::magit-subtree-commit-labels`.
   - 副作用: none.
3. Open the timeline on the fixture after two commits, one editing `libs/full/a.txt`, then one
   editing `README`.
   - Step: `fenrir/magit-subtree-commits` with since `1 year ago`.
   - Expected:
     - The buffer lists the `README` commit (label `(umbrella)`) above the `libs/full` commit
       (label `full`).
     - `RET` on the `full` row opens a `magit-revision-mode` buffer for that hash.
     - Narrowing to `full` leaves only `full` rows.
     - `g` keeps the narrowing and the since.
   - Test: `test/magit-subtree-test.el::magit-subtree-commits-buffer`.
   - 副作用: a temp dir under `temporary-file-directory`, deleted by the test.
4. Run the timeline on the real repo in the daemon.
   - Step: `fenrir/magit-subtree-commits` in `~/code/ig_lottery_hotfix` with since
     `30 days ago`.
   - Expected:
     - The row count equals the output of
       `git -C ~/code/ig_lottery_hotfix log --branches --exclude='refs/heads/p/*' --since='30 days ago' --format=%h | wc -l`,
       run at the same moment.
     - Row times are non-increasing from top to bottom.
     - `78e0443ed` is labelled `odds-web-ag`.
     - `fdf134a7e` is labelled `clawer`.
     - `29b40f061` is labelled `clawer,(umbrella)`.
     - No row holds `c8098f07b`, which is a `p/*`-only commit.
   - Test: manual (real repo, live daemon, via `emacsclient -e`).
   - 副作用: creates buffer `*magit-subtree-commits: ig_lottery_hotfix*` in the daemon.
5. In the buffer from 4, check `RET` and narrowing.
   - Step:
     - `RET` on the `78e0443ed` row;
     - narrow to `odds-server`.
   - Expected:
     - `RET` opens that commit's revision buffer, with a `Subtree:` line naming
       `repos/lottery/odds/odds-web-ag`.
     - After narrowing, every remaining row's label contains `odds-server`.
   - Test: manual (real repo, live daemon).
   - 副作用: opens a revision buffer in the daemon.
6. Check the menu entry in the daemon.
   - Setup: reload `lisp/fenrir-magit-subtree.el` in the daemon.
   - Step: `emacsclient -e "(and (transient-get-suffix 'magit-log \"A\") t)"`.
   - Expected: `t`.
   - Test: manual (one command).
   - 副作用: reloads the module in the daemon.
7. Time a refresh of the buffer from 4.
   - Step:
     `emacsclient -e '(with-current-buffer "*magit-subtree-commits: ig_lottery_hotfix*" (car (benchmark-run 1 (magit-refresh-buffer))))'`.
   - Expected: below `0.5`.
   - Test: manual (real repo timing).
   - 副作用: refreshes that buffer.
8. Run the whole suite.
   - Step: the batch command above.
   - Expected:
     - Every test passes.
     - `fdfind --no-ignore -e elc --exclude elpa --exclude eln-cache .` prints nothing.
     - [`FEATURES.md`](../../../FEATURES.md) has an `l A` row next to `l S`.
   - Test: manual (suite run plus two checks).
   - 副作用: a temp dir under `temporary-file-directory`, deleted by the tests.

## 限制

- **Existing environment to reuse.**
  - The one Emacs 30.1 daemon and Magit from `elpa/`.
  - The existing subtree front end [`lisp/fenrir-magit-subtree.el`](../../../lisp/fenrir-magit-subtree.el)
    and its CLI [`git-subtree-status`](../../../rust/git-tools/git-subtree-status/README.md),
    already built in `rust/lib/`.
  - The existing ERT suite [`test/magit-subtree-test.el`](../../../test/magit-subtree-test.el)
    and its fixture.
  - Nothing new is created.
- The repo is read only, with one `git log` and one `git-subtree-status` call per refresh,
  and no per-commit process.
- Key routing follows [`CLAUDE.md`](../../../CLAUDE.md): the `magit-log` suffix is installed by
  the module itself, and `init-keys.el` is not touched.
- [`FEATURES.md`](../../../FEATURES.md) is updated in the same change. No `.elc` is left
  behind.

## 待決問題

- Default since when prompting? — default if unanswered: `14 days ago`.
- Which branches? — default if unanswered: all local branches except `refs/heads/p/*`.
  `C-u` asks for the revs.
