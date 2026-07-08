Prompt file: [emacs-python-test-runner.prompt.md](emacs-python-test-runner.prompt.md)

# Why this composition

Task: build IDE-style "run test at point / run all tests in file" for Python in the user's
Emacs config (example target `sms-service/tests/test_crypto_vectors.py`), with a nod to using
C++/Rust for performance.

## Step 1 — Diagnosis (seven axes)

| Axis | Finding | Consequence |
|---|---|---|
| **Oracle?** | **Rich.** Build compiles; module loads; discovery-at-line has a *checkable* expected nodeid; `pytest --collect-only` verifies the command collects the right tests; a real run gives pass/fail; `emacs -Q --batch` verifies clean load. | This is an oracle-anchored implement loop, not a self-eval loop → recipe R2. |
| **Solution space?** | **Narrow mechanics** (there is a *right* pytest nodeid for a given cursor) wrapped in a **small design choice** (native module vs pure elisp; Rust vs C++). Repo precedent (junit-core, question-queue-core, Go's `C-c t`) narrows it hard. | Don't run best-of-N on the whole thing; do gate the one real fork. |
| **Primary failure fear?** | **Plausible-but-wrong** — a subtly wrong nodeid (`File::method` instead of `File::Class::method`, mishandled `@parametrize`, wrong rootdir/venv) silently runs the wrong thing or nothing. Secondary: **missed shapes** (async, nested class). | → adversarial-verify on discovery + a completeness checklist of test shapes. |
| **Cost/volume?** | One-off feature dev, not high-volume. | No cascade-routing; no cost tiers. |
| **Size?** | Medium, multi-file (elisp + maybe a native module + FEATURES.md), fits one focused agent. | No map-reduce/divide-and-conquer. |
| **Interaction?** | **Must observe the environment** — build, load into Emacs, run pytest, read real output. | Implement loop is ReAct-flavored around an oracle, not plannable-blind ReWOO. |
| **Horizon & recurrence?** | A few implement→verify rounds (bounded). **Recurs as a repo pattern** — this is the 3rd native-module-or-elisp test runner in the same mold. | Cap rounds (6); explicitly mirror existing precedents rather than invent. |

Assumptions stated rather than asked (skill allows inferring): framework = **pytest** (standard
for a `test_*.py` under `tests/`), and **venv matters** (repo already auto-detects `.venv` for
pyright). The one genuinely open fork — native vs elisp — is deliberately **not** a user
question; it's built into the prompt as a measured gate (more valuable than a yes/no).

## Step 2–3 — Primitives selected & why

| Primitive | Catalog line that selected it | Where in the prompt |
|---|---|---|
| **until-oracle-passes (stepwise / PRM)** | Decision-tree #1 "objective oracle exists → until-oracle-passes; score each step, not just the end." | Phase 3: five stepwise oracles, paste real output, fix first failure, per-step green before advancing. |
| **plan-then-execute** | Catalog #10 / R2 step 1 "plan first, don't code yet" — stops skip-steps. | Phase 2. |
| **adversarial-verify (default-refute)** | Decision-tree #5 "fear plausible-but-wrong → N skeptics told to refute." | Phase 4: each edge case "BROKEN until proven," uncertain ⇒ BROKEN, evidence required. |
| **completeness-critic** | Decision-tree #6 "fear missed something → loop-until-dry + completeness-critic." | Phase 4 enumerates test *shapes* (function/method/nested/parametrize/async/no-test). |
| **devil's-advocate** | R2 step 3 "red-team the diff — 2 concrete break scenarios." | Phase 5. |
| **measured architecture gate + escape hatch** | composition-guide "cost/scope bound must fail closed" + guardrail "workflow > agent, diversity > scale" — here applied as *fail-closed on the native-module decision*. Also my global rule: surface the decoupling escape hatch before presenting a stack as forced. | Phase 1: elisp default, native only on a pasted measurement; "Rust was mentioned" ≠ measurement. |

## Step 3 — Recipe / stacking decision

Backbone = **R2 (Reliable code change)**: plan-then-execute → until-oracle-passes (stepwise) →
devil's-advocate. Adapted by inserting an upfront **architecture-decision gate** (Phase 1) — a
degenerate best-of-2 collapsed to "default + measured escape hatch," because repo precedent
already narrows the space and a full best-of-N would be theater. Layered R1's **adversarial-
verify + completeness** onto the discovery step specifically, because *nodeid correctness* is the
one place "plausible-but-wrong" bites. This matches the guide's default skeleton: (small
decompose) → implement diverse-where-it-matters → verify with the **most objective** signal
available (real pytest, not opinion) → synthesize, inside a **round-capped loop**.

Rejected: best-of-N on the whole feature (space too narrow, precedent-constrained); debate (no
asymmetry, self-consistency-style voting adds nothing to a deterministic nodeid); native module
by default (no measured win → violates fail-closed + my "surface the decoupling escape hatch"
rule).

## Step 5 — Guardrail self-check (composition-guide anti-patterns)

- **Oracle > self-eval** ✅ — every loop stops on real pytest/collect/batch-load output, never
  "looks right."
- **No naive self-refine** ✅ — no critique→revise loop lacks an external signal; discovery is
  checked against `--collect-only`, not the model's opinion.
- **Workflow > agent** ✅ — the path is a fixed 6-phase workflow; runtime observation is confined
  to the oracle loop where it's genuinely needed.
- **Diversity > scale** ✅ — Phase 4 verifiers carry *distinct lenses* (parametrize / class-nesting
  / cursor-placement / empty-file / shell-quoting), not N copies of one check.
- **Debate for its own sake** ✅ avoided.
- **Cost/scope bound fails closed** ✅ — the native-module decision aborts to elisp without a
  measurement; the round cap (6) reports red output instead of faking green; empty/missing target
  file STOPs.
- **Silent truncation** ✅ — absent test shapes are dropped *with a note*; unverifiable rows marked
  `UNVERIFIED`, not quietly passed.
- **Reasoning-effort knob considered** ✅ — a single higher-effort call can't replace this because
  the loop's value is the *external* pytest signal, not more internal thinking.
- **Context curation** — not needed; horizon is short (≤6 rounds/oracle, one context).

## Emitted-prompt smell test (prompt-quality.md)

- Every placeholder has an abort-if-missing rule ✅ (`TARGET_TEST` empty → STOP; not pytest → STOP).
- Output has a literal skeleton ✅ (7-part Output contract + the fixture/edge-case tables).
- No "be thorough/careful" vibes ✅ — each instruction ties to an observable (pasted output, a
  `--collect-only` line).
- Verifier stance stated ✅ — Phase 4 default verdict = BROKEN, tie-break "uncertain ⇒ BROKEN."
- Fan-out is real diversity ✅ (named distinct lenses).
- Stop condition is in the prompt text the model sees ✅ (Stop condition section + Phase-3 per-step).
- Escape hatch present ✅ (`UNVERIFIED — <reason>`; STOP if wholly blocked) so the output contract
  can't force a hallucinated green.
- Every prohibition carries a reason ✅.
