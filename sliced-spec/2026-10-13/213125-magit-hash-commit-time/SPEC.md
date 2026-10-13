# Spec: Magit — show the commit time beside every hash

Status: draft
Date: 2026-10-13 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)

## 目標

- Every commit line in a Magit status buffer (Unmerged / Unpushed / Unpulled / Recent
  commits) shows when the commit was made, beside its hash. Today it shows hash and subject
  only (observed 2026-10-13 in `magit: .emacs.d`: `9932ee0 main docs: move specs under
  sliced-spec/`).
- Log buffers show the same exact time instead of a relative age ("3 days").
- The time is the committer time, `YYYY-MM-DD HH:MM` in local time, and looks the same in
  status and log buffers.
- In the 103-column status window measured 2026-10-13, the time takes at most 17 columns.
- The in-hunk refinement line in [`lisp/init-git.el`](../../../lisp/init-git.el) states what
  actually happens while delta is on. Today it sets a value that magit-delta overrides to off
  (the daemon reports off, globally and inside `magit: .emacs.d`).
- The result is the same in the daemon's TTY frame and its GUI frame.

## 不做的事

- No new package. No change to how delta or difftastic render diffs.
- The refs buffer (`y`), the `Head:`/`Merge:` header hash and the `TODOs (0)` line stay as
  they are (see 待決問題).
- No change to the hint toolbar's logic. If the margin makes it drop items sooner, that is
  reported, not fixed here.
- Blame and revision buffers stay as they are; the revision buffer already prints AuthorDate
  and CommitDate.

## 驗收條件

Fixture: [`make-fixture.sh`](make-fixture.sh) `/tmp/magit-time-fixture` builds a repo with two
commits, `fixture one` and `fixture two`, author `Fixture Author`, author date 2026-01-02
03:04 +0800, committer date 2026-02-03 04:05 +0800, no upstream (so status shows "Recent
commits"). Building it is setup. Batch tests run with `TZ=Asia/Taipei`.

1. `magit-status` on `/tmp/magit-time-fixture` → both Recent-commits lines show their hash
   and `2026-02-03 04:05` on the same screen line; `2026-01-02` appears on neither line —
   test: `test/magit-time-test.el::status-committer-time` — 副作用: writes
   `/tmp/magit-time-fixture` (outside the repo)
2. `magit-log-current` on `/tmp/magit-time-fixture` → each commit line shows
   `2026-02-03 04:05` and `Fixture Author`, and no relative age — test:
   `test/magit-time-test.el::log-committer-time` — 副作用: writes `/tmp/magit-time-fixture`
3. The status buffer of `/tmp/magit-time-fixture` → the time column is ≤ 17 columns wide —
   test: `test/magit-time-test.el::status-margin-width` — 副作用: writes
   `/tmp/magit-time-fixture`
4. In the status buffer of `/tmp/magit-time-fixture`, press `L L` → the times are hidden;
   press `L L` again → they are shown — test: `test/magit-time-test.el::margin-toggle` —
   副作用: writes `/tmp/magit-time-fixture`
5. Daemon, TTY frame. Setup: reload `lisp/init-git.el`, kill the buffer `magit: .emacs.d`.
   `C-x g` in `~/.emacs.d` → every commit line shows the time that
   `git -C ~/.emacs.d log -1 --format=%cd --date=format-local:'%Y-%m-%d %H:%M' <hash>`
   prints for its hash — test: manual (needs a real TTY frame) — 副作用: none
6. Same input and step as 5, in the daemon's GUI frame → same result — test: manual (needs
   a real GUI frame) — 副作用: none
7. `emacsclient -e '(with-current-buffer "magit: .emacs.d" magit-diff-refine-hunk)'` →
   `nil`, and `ug -n refine lisp/init-git.el` shows no line that sets or claims another
   value — test: manual (one command plus a grep) — 副作用: none

## 限制

- **Existing environment to reuse**: the one Emacs 30.1 daemon (TTY `emacsclient -nw` in
  tmux plus a GUI frame), Magit 20260506.643 and magit-delta from `elpa/`, configured in
  [`lisp/init-git.el`](../../../lisp/init-git.el) — documented in
  [`CLAUDE.md`](../../../CLAUDE.md) and [FEATURES.md §8](../../../FEATURES.md). Nothing else is
  created; the fixture is a throwaway repo under `/tmp`.
- Status refresh runs no Git command Magit does not already run — the `$HOME` refresh budget
  ([`_doc/GOTCHAS.md`](../../../_doc/GOTCHAS.md)).
- FEATURES.md §8 is updated in the same change.
- `test/libsrc-test.el` and `test/search-test.el` still pass; no `.elc` is left behind.

## 待決問題

The interview (2026-10-13) got no answer; these are defaults until approval.

- Committer time or author time? — default if unanswered: committer.
- Absolute `YYYY-MM-DD HH:MM` or relative age? — default if unanswered: absolute.
- Author name in the status margin too? — default if unanswered: no (width); log buffers
  keep it.
- Times in the refs buffer (`y`) too? — default if unanswered: no.
- Hash in the `Head:`/`Merge:` header lines? — default if unanswered: no.
- Hide `TODOs (0) (update manually)` until a scan finds something? — default if
  unanswered: no.
