# Why this composition — Emacs GUI UX backlog implementation

Companion rationale for
[`emacs-gui-ux-implementation.prompt.md`](emacs-gui-ux-implementation.prompt.md).

## Diagnosis

- **Oracle?** Hybrid, not a clean yes. There's no test suite or compiler for Elisp
  config. Two different sub-problems have two different oracle qualities:
  - "Does the edit even load?" → a cheap, fully objective, scriptable oracle
    (batch-mode `emacs --batch -l file`).
  - "Does this actually preserve TTY safety?" → **no automated oracle exists.** The only
    ground truth is (a) reading the real package source to check the claimed mechanism,
    and (b) a human reloading the live daemon and observing the TTY frame. Both are
    irreducibly manual here.
- **Solution space:** narrow. Each backlog item has one correct implementation (a
  specific snippet in a specific file) — this is not a design/naming/writing task.
- **Primary failure fear:** "plausible but wrong," decisively, not "missed something."
  The backlog itself is the surviving 8/34 items from a prior adversarial-verification
  pass; the 26 rejected ideas are documented, and several failed only because a
  TTY-safety claim that *sounded* right (e.g. "tmux eats mouse-3, so `context-menu-mode`
  can't reach the TTY frame") was factually wrong once someone read the actual source
  (`context-menu-mode` is `:global t`, independent of tmux's input handling). This one
  failure mode dominates the whole design.
- **Cost/volume:** low, one-off — 8 items, not a high-volume pipeline.
- **Size:** each item trivially fits in one context; the backlog as a whole is small.
- **Interaction:** genuinely needs to observe the environment (read real package source,
  not recall it) and cannot complete end-to-end without human observation of a live TTY
  session — this rules out a fully autonomous "just do all 8 and report back" design.
- **Horizon:** 8 sequential items, each paused on a human checkpoint — long enough
  (> 5 rounds across items 1-8) that state needs to survive checkpoint pauses without
  re-deriving context each time.
- **Edges:**
  - *Ambiguity*: item 4 is pre-flagged as possibly infeasible. Resolved by making the
    ground-verify step itself the arbiter (with an explicit skip path), not by asking
    the human to adjudicate up front — the whole point is that the agent must check,
    not guess or ask.
  - *Blast radius*: breaking the TTY frame is disruptive to a live daily-driver session,
    though git-revertible — not "irreversible" in the strict delete/deploy/spend sense,
    but high enough cost to warrant dry-run discipline before the risky action (enabling
    a mode) rather than after.
  - *Human-only prerequisites*: `M-x my/package-refresh` + restart for new packages
    (items 5/7/8) is a step the agent cannot itself perform — modeled explicitly as a
    `BLOCKED` outcome, not glossed over.
  - No untrusted content is processed, so dual-LLM quarantine doesn't apply. No
    subjective judge is used, so judge-debias hygiene isn't the relevant lens (see
    "why not adversarial-verify's N-skeptic panel" below).

## Primitives selected

| Primitive | Where it shows up | Why |
|---|---|---|
| **Workflow, not agent** | The whole thing is a fixed, ordered, 8-item loop — no branching path to discover at runtime beyond per-item verify/skip. | The path is fully knowable in advance (composition-guide's "prefer a workflow" default); an open-ended agent would add unpredictability for zero benefit. |
| **Dry-run + pre-mortem** (§50) | Step 3.1, mandatory before every edit. | The dominant failure fear is a claim that sounds safe and isn't — this is exactly the "would this fail, and why, before you commit to it" pattern, grounded in reading real source rather than opinion. |
| **Adversarial-verify's evidence discipline**, applied narrowly | Step 3.1's "cite the exact file/symbol you checked" + default-refute framing ("wrong until proven right"). | Borrowed the *stance and evidence-demand* from adversarial-verify without the N-skeptic panel — see below for why a panel isn't warranted here. |
| **Sandbox-verify-commit** (§51) shape | Steps 3.2→3.3→3.4: edit is inherently sandboxed (a local, git-revertible diff); "commit" = advancing to the next item, gated on a human-confirmed oracle, never on the model's own opinion that "this should be fine." | The risky action (enabling a mode that could break a live session) needs isolate→verify→merge-or-discard discipline even without a literal sandbox environment — the git working tree plus a human checkpoint stands in for the sandbox. |
| **Stepwise oracle loop** (until-oracle-passes flavor) | Step 3.3: batch-load check must pass before the human is even asked to look. | Applies the "oracle over self-eval" rule to the *part* of this task that does have a real oracle (syntax/load correctness), instead of skipping straight to human review for something a script can catch for free. |
| **Human-in-the-loop checkpoint gate** | Step 3.4, explicitly required before any item is marked done. | No automated oracle exists for "is the TTY frame still fine" — the composition-guide rule "attach an oracle to any refine loop, or cap it" is satisfied here by substituting the one oracle that does exist (human observation) rather than pretending the automated check covers it. |
| **Lightweight context curation** | Step 3.5's running STATUS list, carried forward rather than re-derived. | 8 sequential items with pauses between them is past the "> ~5 rounds" threshold where the composition-guide makes per-round state externalization mandatory, not optional. |
| **Fixed, fail-closed stop condition + no-silent-scope-creep constraint** | §5 negative constraints; §7 stop condition. | All 8 items reaching a terminal state is the only acceptable stop — never "keep going" or "helpfully" adding/reordering items, matching the anti-pattern list's "cost/scope bound that fails open" and "silent truncation" warnings. |

## Why NOT a few tempting alternatives

- **Why not full `adversarial-verify` with 3 independent skeptics per item?** The
  underlying claim ("does package X have a per-frame TTY fallback") is a *fact*
  resolvable by reading one source file correctly — it's not a matter of subjective
  judgment where sampling diversity reduces noise. Spending 3x the verification compute
  on a question with a single objectively-checkable answer doesn't reduce the actual
  uncertainty; reading the right file once, carefully, does. This matches the
  reasoning-effort-knob guidance: prefer one well-grounded check over hand-rolled
  ensemble voting when the thing being checked is a fact, not an opinion.
- **Why not `plan-then-execute` with the whole 8-item plan written up front (R2 exactly
  as catalogued)?** R2 assumes a real test/build oracle exists throughout. Here the
  oracle for the one property that matters (TTY safety) is *per-item and human-gated*,
  so batching the plan doesn't save anything — each item still needs its own
  ground-verify → implement → checkpoint cycle before the next can safely start. The
  procedure keeps R2's "plan stops skip-steps" spirit (ground-verify is itself a forced
  planning step per item) without pretending the whole backlog can be executed in one
  oracle-checked pass.
- **Why not let the agent just implement all 8 and report at the end?** That collapses
  steps 3.4's role entirely — the human explicitly asked for a manual verify checkpoint
  between items so they can reload and bisect if something breaks the TTY frame. Batch
  execution also directly reproduces the anti-pattern "self-eval where an oracle
  exists": the model would be certifying TTY-safety on its own opinion when a real
  (human) oracle is available and was explicitly requested.
- **Why not a `clarify-before-act` pass asking the human up front whether item 4 is
  feasible?** The backlog already states the test for feasibility (a genuinely
  per-frame-safe wrapper); that's a technical question the agent should answer by
  reading source and reasoning about the `display-graphic-p`/frame-focus-hook mechanics,
  not a preference question only the human could answer. Asking would just defer work
  the agent is equipped to do.

## Sanity self-check (composition-guide checklist)

- Every loop has an explicit, externally-checkable stop condition (per-item: ground-verify
  verdict + human confirmation; overall: all 8 items terminal) — not open-ended.
- The one refine-shaped step (ground-verify) is grounded in an external signal (real
  package source), not self-opinion.
- No fan-out here, so the diversity question doesn't apply — correctly not forced in.
- Workflow chosen over agent because the path is fully predefined.
- Considered reasoning-effort/ensemble alternatives and rejected them for the stated
  reason (fact-checkable claim, not a judgment call).
- Context curation (STATUS list) included because the loop exceeds ~5 rounds across
  items with human pauses between them.
- Cost/scope bound is fail-closed: the backlog is fixed at 8 items, reordering/expansion
  is explicitly prohibited, and `BLOCKED`/`SKIPPED` outcomes are surfaced, never hidden.
- Every stage boundary (ground-verify → implement → automated check → human checkpoint →
  record) names its passed artifact and what happens if it fails (skip, fix-and-retry,
  block, or halt for human input) — no happy-path-only joints.
- Prompt text passes the smell test: role+stance, runner manifest with fail-closed
  guard, numbered procedure, literal output skeletons (per-item and final), reasoned
  negative constraints, an explicit escape hatch, and the stop condition echoed at the
  end.
