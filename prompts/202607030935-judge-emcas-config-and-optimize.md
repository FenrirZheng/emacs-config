# Emacs Config Improvement Hunt → Implement → Verify

Target: /home/fenrir/.emacs.d (Emacs 30.1, TTY-first daemon + emacsclient -nw in tmux,
simultaneously serving a GUI frame). CLAUDE.md in that repo is the constraint bible —
every finder and skeptic MUST read it first.

## Phase 1 — DISCOVER (map fan-out + loop-until-dry)

Fan out finders in parallel, each with a DIFFERENT lens (diversity > scale):

  F1 startup-perf     : early-init.el / init.el / eager `:demand` blocks — anything
                        loading eagerly that could be `:defer`/`:hook`/`:commands`;
                        GC & file-name-handler discipline; autoload opportunities.
  F2 runtime-perf     : hooks that run per-keystroke/per-save (ws-butler, sideline,
                        symbol-overlay, eldoc routing, flymake timers); jit-lock /
                        font-lock cost; process-heavy minor modes on TTY.
  F3 ux-keybindings   : lisp/*.el + lisp/languages/*.el — C-c prefix collisions,
                        unbound-but-useful commands, repeat-map gaps, missing
                        which-key labels, TTY-unreachable keys (e.g. C-; on some terms).
  F4 ux-workflow      : friction in daily flows (buffer switch, project switch, search,
                        completion styles, dired, org) vs what's already installed but
                        under-wired; redundant/overlapping packages.
  F5 hygiene          : dead code, duplicate hooks, stale `:after` edges, modules whose
                        load order could be flattened, custom.el drift.

Rules per finder:
  - Return findings as: {id, file:line, lens, claim, expected-benefit, risk, evidence}.
  - Maintain a shared SEEN set keyed by file:line:claim — report only NEW findings.
  - LOOP: after all finders return, run another round with fresh angle hints;
    STOP when 2 consecutive rounds add nothing new (loop-until-dry), hard cap 4 rounds.

## Phase 2 — ADVERSARIAL-VERIFY each finding (kill plausible-but-wrong)

For every NEW finding, 3 independent skeptics, each defaulting to "REFUTE unless proven":
  S1 claude-md-trap   : read .emacs.d/CLAUDE.md end-to-end. Does this "improvement"
                        revert a documented deliberate decision? (global-corfu-mode,
                        Tier-C posframe auto-enable, ggtags M-. neutralization,
                        eglot-format in save-hook, load-order reshuffle, globalizing
                        semantic-tokens…) If yes → REFUTE, cite the CLAUDE.md line.
  S2 tty-daemon       : does it survive the TTY frame AND the coexisting GUI frame on
                        one daemon? Child-frame/fringe/stipple-only features → REFUTE.
  S3 evidence         : is the claimed cost/benefit real? Demand a measurement path or
                        concrete repro; "feels faster" with no measurable path → REFUTE.
Drop the finding if ≥2 skeptics refute. Survivors keep skeptic notes attached.

## Phase 3 — RANK (rubric judge; no oracle exists for "is this good UX")

Score each survivor 0–5 on: impact, risk-inverse, effort-inverse, measurability.
Anchors: impact 5 = felt every session / >100ms startup; 1 = cosmetic.
Output a ranked list; take the top items whose risk ≤ medium, cap at 6 changes
per batch (fail-closed: if ranking is ambiguous, take fewer, not more).

## Phase 4 — IMPLEMENT (plan-then-execute + until-oracle-passes, per change)

For EACH selected change, independently (one change = one commit-sized unit):
  1. PLAN: files to touch + acceptance criteria BEFORE editing.
  2. EDIT, then run the oracle chain; paste REAL output each time:
       O1 load-health : emacs --batch --eval '(setq debug-on-error t)' -l init.el
                        → must exit 0, no new warnings vs baseline.
       O2 byte-compile: byte-compile touched lisp/*.el → no NEW warnings.
       O3 perf changes: hyperfine-style 3× median of
                        `time emacs --batch -l init.el` before vs after —
                        record both numbers; a perf claim with no delta = revert.
       O4 ux changes  : eval the new binding/feature via emacsclient on the live
                        daemon (TTY frame) and confirm behavior; scan for C-c
                        collisions introduced.
  3. Fix only the first real failure; repeat until green. Max 3 fix attempts per
     change → REVERT that change and log why (fail-closed, never leave half-applied).
  4. Baseline capture BEFORE any edit: O1 output + O3 timing 3× median. Abort the
     whole phase if baseline itself fails (don't build on a broken base).

## Phase 5 — FINAL GATE (devil's-advocate on the accumulated diff)

Red-team the full diff: "give 2 concrete scenarios where this breaks the daemon,
the TTY frame, or a documented CLAUDE.md invariant." Address or explicitly dismiss
each with evidence. Then report: per-change before/after numbers, reverted items
with reasons, and keep FEATURES.md in sync for any keybinding change.

Never claim done without pasted green oracle output. Do not git push.

---

## Why this composition (primitive ← diagnosis)

- map fan-out (5 heterogeneous lenses)      ← wide solution space + 20+ modules to cover; diversity > scale
- loop-until-dry (2 dry rounds, cap 4)      ← fear "missed something"; `find N` misses the long tail
- adversarial-verify (3 skeptics, ≥2 kill)  ← fear "plausible-but-wrong"; S1 is custom-built for this
                                              config's documented deliberate traps
- rubric judge                              ← "is this good UX" has no oracle → anchored rubric, not self-opinion
- plan-then-execute + until-oracle-passes   ← implementation HAS real oracles (batch load / byte-compile /
                                              timing); every refine loop is oracle-grounded, no naive self-refine
- devil's-advocate                          ← catches "all green but wrong design"
- fail-closed bounds                        ← ≤6 changes/batch, ≤3 fix attempts then revert, abort on broken baseline
