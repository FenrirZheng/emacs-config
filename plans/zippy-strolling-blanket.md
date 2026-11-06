# Emacs lag with Org open: measure, fix, prove

## Context

The user reports Emacs is laggy with Org. The original wording, 「現在開org mode」, reads as
"I have Org open right now", while the English draft says "opening Org". The daemon state fits
the first reading: a GUI frame is showing `open-questions-bilingual.org` (6 KB) beside a Magit
window. So measure **both** editing/redisplay lag and file-open cost.

No root cause is established yet. Everything so far came from read-only probes. A CPU profile
has not been taken, because it changes daemon state and plan mode forbids that.

## Evidence so far

Daemon: Emacs 30.1, up 21 h, 179 buffers (145 visiting files), about 29 in `org-mode`.

| Observation | What it suggests | Status |
|---|---|---|
| The `modified-files` mod's `refreshIndex` writes the index file, then runs `indexElisp` through `emacsclient -e`: `find-file-noselect` plus `revert-buffer` | The UI thread blocks on buffers nobody is looking at | Code read; **per-call time not measured** |
| `*ig_lottery, Claude Index*`: 175 KB, display count 0, modified tick 206545 | Heavy rewriting of a never-shown Org buffer | Measured; call rate unknown |
| The reverted buffer carries `org-element--cache-after-change`, `org-indent-refresh-maybe`, `diff-hl-edit`, `jit-lock-after-change` and others on `after-change-functions` (seen on a normal Org buffer) | A whole-buffer replace may run all of them | Hypothesis |
| `*Messages*` shows runs of `Process server <N> not running: connection broken` (N reached about 2572); the mod's note calls give up after 5 s | Some clients may be leaving mid-eval | Hypothesis; the messages have no timestamps |
| 26 leaked `org-indent-initialize-agent` idle timers (repeating, agent list empty) | Org bug at `org-indent.el:213-217`: a new timer overwrites the only handle to the old one | Measured; cost looks tiny while the list is empty, so probably **not** the main cause |
| GC averages 146 ms per collection, 2313 collections, 338 s total | A pause you can feel when it lands on a keypress | Measured; my own probes trigger idle GCs too |
| Per-command and redisplay work in Org: `jinx`, `valign-region`, `org-modern--pre-redisplay`, `org-appear`, `pulsar`, `goggles`, `dimmer`, `beacon`, ligatures | Any of these could be the editing lag | Unranked; needs the profile |

Prior work read: commit `6ec949b` (2026-10-08) fixed idle redisplay churn and set the 16 MB gcmh
floor. Don't undo that floor.

Probe leftovers, not to be misread later: two `*Messages*` errors (`sequencep #<obarray>`, void
`auto-revert--buffers-by-watch-descriptor`) came from my probes, and my scratchpad `probe1.el`
was `load`ed into the daemon.

## Step 1: record the baseline (before any edit)

All of this runs against the live daemon, and nothing restarts it.

1. **Editing profile.** `profiler-start 'cpu`, the user types and moves in the Org buffer for
   about 30 s, then read the report headlessly and stop the profiler.
2. **Redisplay timing.** `benchmark-run` of 100 × `forward-line` + `(redisplay t)` in the visible
   Org window, restoring `window-point` afterwards.
3. **Open cost.** `find-file-noselect` ×3 on scratchpad copies of a 6 KB note and the 175 KB
   index, killing each buffer afterwards.
4. **Index redraw cost.** Time the exact `indexElisp` form on a scratchpad copy under a throwaway
   buffer name. Separately, sample how often the real index buffers change during a Claude session.
5. **GC.** Record `gcs-done` and `gc-elapsed` deltas over the same windows.

## Step 2: fix what the numbers rank highest

Only fixes that the baseline supports get applied.

- **If the index redraw is the cost:** stop doing the work while the buffer is hidden. Skip
  `find-file-noselect`/`revert-buffer` when no window shows the buffer and refresh it when it is
  shown; if it must stay loaded, bind `org-startup-indented` nil and turn off jinx, diff-hl and
  org-modern there. This lives in `~/code/fenrir-claude-plugin/modified-files/hooks/emacs.ts` and
  `register.ts`, **outside this config**, in a separate repo with its own tests
  (`hooks/*.test.ts`, which must stay green). If that is unwelcome, the config-side fallback is a
  light mode for files under `~/.cache/claude-modified-files/`.
- **If a per-command consumer is the cost:** narrow or disable that one package in
  `lisp/init-org.el` or its owning module, with a WHY comment, and apply it to the running daemon
  without a restart.
- **If the leaked timers show up in the profile, or as a cheap cleanup:** in `lisp/init-org.el`,
  advice that cancels stale agent timers before a new one is made, plus a one-shot cleanup.
- **GC:** don't retune unless the profile shows GC dominating. If heap size drives it, reduce
  the phantom Org buffers rather than changing thresholds.

## Constraints

- Never kill or restart the daemon. Remove all diagnostic advice and stop the profiler afterwards.
- Leave no stray `.elc` from syntax checks (see `CLAUDE.md`).
- Keep `gcmh-low-cons-threshold` at 16 MB and keep the `init-gui.el` guard.
- Update `_doc/GOTCHAS.md` if a load-bearing line is added, and `FEATURES.md` only if bindings change.
- No commits unless asked. The working tree already holds uncommitted edits to `CLAUDE.md`,
  `custom.el` and `lisp/init-appearance.el`; leave them alone.

## Verification

- Re-run probes 1–5 and report before/after numbers in one table. Done means the chosen hot path
  is measurably cheaper; report plainly if a number did not move.
- Confirm the Org features still work: indent, emphasis reveal, table alignment and `<s TAB`.
- If the mod changes: run its tests with a 10 s timeout, and confirm the Index buffer still shows
  correct content when displayed.
- `emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit` still passes.
- Confirm a clean daemon: no leftover profiler or diagnostic advice, no scratch buffers.
