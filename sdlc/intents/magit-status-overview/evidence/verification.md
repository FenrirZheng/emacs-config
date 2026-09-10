# Magit status overview — verification record (branch 1, the command)

Recorded: 2026-09-10, Asia/Taipei (UTC+08:00), 14:43–14:52.
Owning repository: `/home/fenrir/.emacs.d`, branch `intent/magit-status-overview`,
parent commit `27f10b2854d3cc8b4e3592e89d8c3014ea5fad6e`.
Scope: `fenrir/magit-status-overview`, its `j o` entry point and the `j Jump menu`
hint. The new-buffer default (`fenrir/magit-status-overview-default`) is **not**
implemented and **not** verified here — it is branch 2, and it is blocked on a
spec amendment (see `plan.md`).

Environment: GNU Emacs 30.1 (Debian build, GTK+ 3.24.49), one shared daemon with
three X frames and one TTY frame. Magit `20260506.643`, magit-section
`20260503.2051`, Transient `20260507.1521` — the versions pinned in
[`baseline.md`](baseline.md), re-read for this pass.

| artefact under test | SHA-256 |
|---|---|
| `lisp/init-git.el` | `674fd8044447b5edf55a517fdddbfdda03088dd7553a81473c6728bde05fb587` |
| `shell/test-magit-status-overview.el` | `181d86d5d1f8f73e18c0124ab0cfecffe8ea259d96885c5c4e8df62fab8666de` |
| `.githooks/pre-commit` | `13b7c54c8b83d048db69e7992c82f8ec51b4bf7c04c382eb33397c72c14c02a2` |

Every observation below was taken in a throwaway fixture repository built by the
run itself (`/tmp/tmv-qRh8sv/`, deleted afterwards). No observed repository, and
no business data, was read or written.

## Layer 1 — static

`bash .githooks/pre-commit`: `check-parens` over `lisp/`, `lisp/languages/`,
`shell/*.el` and the three root files, then a batch load of `init.el` with
`debug-on-error`. Passed, "pre-commit: init OK". The `shell/*.el` wildcard is
added by this change; without it the new test file would not be checked at all.
This proves paren and string structure and that the config still boots — nothing
about behaviour.

## Layer 2 — batch ERT

`emacs -Q --batch -l shell/test-magit-status-overview.el -f ert-run-tests-batch-and-exit`
→ **16 tests, 16 as expected, 0 unexpected, 2.5 s.** No `.elc` was produced
(`fdfind --no-ignore -e elc --exclude elpa --exclude eln-cache .` is empty) and
no package state was left in the repository root.

Control group first: `tmso-native-fresh-defaults` pins what stock Magit does on a
fresh buffer — `staged`/`unstaged` shown, all ten tracked file bodies hidden,
`untracked` hidden **with no children at all** until its washer runs. Any test
that would also pass against stock Magit is not evidence, and this is the row that
makes the difference visible.

The remaining tests cover: `user-error` outside a status buffer with no buffer
change; the overview reaching the file level from a fully hand-folded buffer
(a no-op implementation and a parents-only one both fail this); idempotence across
two runs, compared as a whole-tree hidden-slot map; persistence across a plain
`magit-refresh-buffer`; `stashes` keeping its visibility; clean-tree and
single-group trees as safe no-ops; a partially-staged file keeping one entry in
each group; rename and binary sections surviving; the untracked list truncating at
`magit-status-file-list-limit` with the native "not listed" `info` section intact
while a 110-file *staged* set is unaffected by that limit; the index
(`git ls-files --stage`) and a SHA-256 of every working-tree file being identical
across two runs; the `o` entry resolving to the command, reinstalling without
adding a second column **and without warning**; the conflict path leaving a
foreign `o` alone while advertising `M-x`; and the untracked count being read off
the heading as the pre-truncation total.

## Layer 3 — interactive, on the shared daemon

Driven through `emacsclient --eval` against the live daemon after
`M-x load-file lisp/init-git.el`, with the fixture buffer displayed in a GUI
window and the 80×25 TTY frame at the same time.

**Two frames, one buffer, different points.** The fixture was hand-folded to the
drifted state (all three groups collapsed), then two file bodies reopened, and
each window's point placed deep inside a *different* file body — the GUI window
inside `big.xml` (1,702 lines), the TTY window inside another staged file. The
command was invoked with the **TTY** window selected.

| observation | before | after |
|---|---|---|
| GUI window (not selected) point | `hunk` in `big.xml`, visible | `file big.xml` heading, visible |
| TTY window (selected) point | `file` heading | `file` heading, visible |
| `region-active-p` | t | nil |
| `magit-region-sections` | 3 | 0 |

The non-selected window on the other frame was corrected — this is the row a
single-window test cannot reach. No frame was selected and no window
configuration changed.

**Visibility result.** All three groups `hidden=nil`; every staged file body
`hidden=t`; every staged file heading `invisible-p` nil; the untracked group
materialised its one file. A second run produced an identical hidden-slot map, and
a following `magit-refresh-buffer` preserved both the groups and the folded bodies.

**TTY 80×24 legibility** — the point of the whole feature. Visible lines from
`window-start`, invisible text skipped:

```
Head:     main base

Untracked files (1)
untracked.txt

Unstaged changes (1)
modified   base.txt

Staged changes (10)
new file   big.xml
new file   staged-0.txt
… staged-1.txt … staged-8.txt

Recent commits
TODOs (0) (update manually)
```

Twenty lines carry the entire working-tree state; `big.xml`'s heading is visible
and its body is `invisible-p` t. Read from buffer positions and the `hidden` slot,
not inferred from GUI fringes.

**Hint toolbar across widths.** Rendered per window with `format-mode-line`:

| window body width | toolbar |
|---|---|
| 279 (GUI) | `Staged  u Unstage  k Discard  RET Diff  c Commit menu  j Jump menu … TAB Fold  ? Help` |
| 139 | same |
| 80 (TTY) | `Staged  u Unstage  k Discard  RET Diff  c Commit menu  TAB Fold  ? Help` |
| 64 | `Staged  u Unstage  k Discard  RET Diff  TAB Fold  ? Help` |
| 29 | `u Unstage  ? Help` |
| 12 | `? Help` |

`j Jump menu` is the first item shed, before any stage/unstage action, which is
what appending it last is for. No item is ever truncated mid-word, and every key
shown is one `key-binding` actually resolves to at point.

**Cost.** Advice counting `call-process`, `start-process`, `process-file`,
`insert-file-contents`, `insert-file-contents-literally` and `call-process-region`:

| operation | subprocess/file-I/O calls | wall time |
|---|---|---|
| `fenrir/magit-status-overview` from fully folded | **0** | 3 ms |
| 240 hint-toolbar renders across 5 windows | **0** | 115 ms (0.48 ms each) |
| native `magit-refresh-buffer`, for comparison | 52 | 322 ms |

The command reaches the file level two orders of magnitude cheaper than the
refresh it replaces, and neither the command nor the redisplay path touches Git.

## Not verified

Recorded as unverified rather than assumed:

- **The untracked size prompt itself.** `y-or-n-p` needs a human; the arithmetic
  around it (`--child-count`, `--threshold`) is covered by ERT, the prompt is not.
- **`magit-section-preserve-visibility` nil, `magit-status-initial-section`,
  `magit-status-goto-file-position`, kill/recreate.** These are cache and
  initial-placement rows; they belong to the branch-2 default and were not
  exercised.
- **Submodule and unmerged sections.** Rename and binary are covered by ERT;
  these two are not, in either layer.
- **Error injection** into the command's middle, and the "overview incomplete"
  report. The `condition-case` path was read, not executed.
- **Washer/paint counts.** Subprocess and file I/O were counted; wash and paint
  invocations were not instrumented separately.
- **A second, independent daemon.** Coexistence was observed on the user's own
  daemon, with a GUI window and the TTY frame showing one buffer simultaneously.

## Effect on the observed daemon, and its repair

Loading the module into the live daemon re-runs `init-git.el`'s difftastic block,
whose `transient-append-suffix` at `lisp/init-git.el:468` carries no guard. The
daemon already held **6** copies each of `difftastic-magit-diff` and
`difftastic-magit-show` in `magit-diff` before this session — a pre-existing defect
from earlier reloads, not caused by this change. The reload made it 7; two
`transient-remove-suffix` calls returned it to the 6 found. Fixture buffer killed,
fixture directory deleted, both observation frames deleted, the TTY frame's window
configuration restored to `*scratch*`.

This is the exact failure mode `fenrir/magit-status-overview--install-entry`
guards against, and the guard is verified above. The difftastic block itself is
left as it was found; fixing it is outside this change.
