Prompt file: [emacs-venv-lib-not-found.prompt.md](emacs-venv-lib-not-found.prompt.md)

# Diagnosis (eight axes)

- **Oracle?** Yes, several: file existence, `getenv`/`python-shell-virtualenv-root`
  buffer-local values, `project-current` resolution, `eglot-events-buffer`
  content, and a direct Python import test. Confirmed by hand before
  drafting the prompt (see "Pre-composition grounding" below) — the
  venv/build/interpreter layer is objectively healthy at the OS level, so
  whatever "lib not found" refers to lives entirely on the Emacs side.
- **Solution space?** Narrow. A small, enumerable set of candidate
  mechanisms: venv-hook didn't fire / found wrong root, `VIRTUAL_ENV`
  pre-set by envrc or an inherited shell (hook defers and no-ops), a stale
  Eglot/pyright server process holding an old env, wrong project-root
  resolution, or the message isn't even a pyright diagnostic (rust-analyzer,
  Eglot server-start failure, plain runtime `ModuleNotFoundError`).
- **Primary failure fear?** Plausible-but-wrong. "It's probably the venv
  hook" is the easy, likely-first guess and matches the user's own framing
  of the question — exactly the case where a diagnosis needs to resist
  concluding on vibes. Secondary fear: missed-something, since several
  independent mechanisms in `fenrir/python-activate-project-venv` /
  Eglot's server lifecycle could each produce the same symptom.
- **Cost / volume?** One-off, cheap, local — no batching or cost-tiering
  needed.
- **Size?** Small — one project directory, one Elisp module, fits in a
  single context. No map-reduce/divide-and-conquer.
- **Interaction?** Must observe the live environment mid-task — buffer-local
  variable values, the running Eglot server's state, and the exact
  diagnostic text can't be predicted or planned up front; they have to be
  read from a live (or freshly reproduced) Emacs session. This rules out
  ReWOO/plan-and-solve in favor of ReAct.
- **Horizon & recurrence?** Short — capped at 8 investigative actions, well
  under the >5-round threshold that would require context-curation
  machinery. The venv-detection *mechanism* could recur as a debugging
  pattern for other projects, but a one-off diagnosis doesn't warrant a
  skill-library entry by itself.
- **Edges?**
  - *Ambiguity*: "lib not found" is the user's paraphrase, not a literal
    error string, and at least four distinct Emacs subsystems could produce
    something a user would describe that way (pyright import diagnostic,
    Eglot server-start failure, rust-analyzer diagnostic on the adjacent
    Cargo.toml, or a runtime import error from executing Python inside
    Emacs). Resolved via **observation, not a user-facing question**: step 1
    of the procedure captures the verbatim text and classifies its source
    before any hypothesis is allowed, since the agent has direct tool/Emacs
    access to just go look — asking the user to paraphrase further would be
    lower-fidelity than reading the actual diagnostic.
  - *Irreversible actions*: none — this is read-only diagnosis. The prompt
    explicitly forbids editing `init-python.el` as part of this task, so no
    dry-run/sandbox-verify-commit machinery is needed.
  - *Untrusted content + tools*: none — the agent is reading the user's own
    project and config, no injection surface.
  - *Abstain vs. wrong*: yes — if the live state can't be reproduced (daemon
    down, error not reproducible) or evidence splits between two
    hypotheses, an `INCONCLUSIVE` verdict is explicitly preferred over a
    forced guess.

# Pre-composition grounding (done before drafting, to write a specific rather than generic prompt)

Per `Grounding in real data` in the global CLAUDE.md ("surface data-reality
mismatches early", "don't hardcode a value whose real value is available
upstream"), I checked the actual project and Elisp before writing the prompt
rather than describing the mechanism from memory:

- `{{PROJECT_DIR}}/.venv` exists, has a working Python 3.13 interpreter.
- The Rust extension IS built and installed: site-packages has
  `python_rust_ffi_example/__init__.py` +
  `python_rust_ffi_example.cpython-313-x86_64-linux-gnu.so`.
- `.venv/bin/python -c "import python_rust_ffi_example"` and
  `.venv/bin/python example.py` both succeed cleanly.
- Read `lisp/languages/init-python.el`'s `fenrir/python-activate-project-venv`
  to get the real mechanism (buffer-local `VIRTUAL_ENV`/`PATH` injection via
  `locate-dominating-file`, deferring to envrc, hooked at priority 90 on
  `after-change-major-mode-hook`) rather than assuming a generic "Emacs venv
  detection" story.

This closed off the "maybe the venv/build is just broken" branch entirely
before the prompt was written, so the emitted prompt's `<known_baseline>`
block tells the executing agent not to re-derive it — it can spend its
8-action budget entirely on the actually-unknown Emacs-side state.

# Primitives selected

| Primitive | Diagnosis line that selected it |
|---|---|
| **ReAct** (backbone) | "Must observe environment mid-task" — buffer-local env values and the live Eglot server state can only be read live, not planned; catalog rule 12. |
| **Oracle-grounded hypothesis checks** (until-oracle-passes discipline, not a full loop) | "Oracle exists" — every step in the procedure names a concrete command/read whose result confirms or refutes, not a self-opinion check (composition-guide rule 1, "oracle > self-eval"). |
| **Default-refute self-check** (lightweight adversarial-verify, single-agent) | "Fear plausible-but-wrong" — step 6 forces the agent to try to disqualify its own leading hypothesis and rule out ≥1 alternative before concluding, mirroring adversarial-verify's default-refute stance without the multi-skeptic fan-out (see trade-off below). |
| **Escape hatch / abstention** | "Abstain vs. wrong: abstaining beats a wrong answer" — `INCONCLUSIVE` is a first-class, explicitly-preferred output, not a failure mode. |
| **Observation-first ambiguity resolution** (in place of clarify-before-act) | "Ambiguity" edge, resolved by step 1 (reproduce + classify the exact error) instead of a user-facing question, since the agent holds the tools needed to resolve it itself and Auto Mode biases toward proceeding rather than stopping. |

# Why a single-agent ReAct, not a multi-agent fan-out (self-grill)

The catalog's R1 recipe (fan-out finders → loop-until-dry → N-skeptic
adversarial-verify → judge-panel) was the first template considered, since
this is nominally a "find the bug" task. Rejected in favor of a lean
single-agent ReAct with a built-in default-refute step. Two counter-questions,
answered:

1. **"Doesn't 'fear plausible-but-wrong' always mean N independent
   skeptics?"** No — adversarial-verify earns its cost when the *check
   itself* is a judgment call multiple reviewers could disagree on (e.g. "is
   this a real security bug"). Here every check is a mechanical, objective
   read (a variable's value, a file's existence, whether a diagnostic clears
   after a server restart) — three skeptics reading the same `getenv` output
   would agree trivially. Composition-guide's "workflow > agent" and
   "don't multiply agents for their own sake" defaults apply: a single
   careful pass with a structured self-refute step gets the same rigor at a
   fraction of the cost.
2. **"Could the solution space actually be wide enough to need best-of-N
   generation instead of ReAct?"** No — the candidate causes are a small,
   enumerable, mutually-exclusive set (five listed in
   `<venv_detection_mechanism>`), not an open design space; this is
   classification/diagnosis with a unique right answer, which the catalog
   maps to self-consistency/ReAct-style investigation, not best-of-N
   generation (that's for wide, subjective solution spaces like design or
   naming).

# Guardrail self-check (composition-guide.md)

- Every loop has an explicit, externally-checkable stop condition? Yes — 8
  investigative actions is the hard cap, and it can end earlier once
  for/against evidence exists (composition-guide rule 3, oracle-green-style
  stop preferred over open-ended "keep investigating").
- Refine loop grounded in an external signal? N/A — this isn't a
  generate-then-critique-then-revise loop; it's an evidence-gathering loop
  where each step's "signal" is a real command output, not model opinion.
- Fan-out genuinely diverse? N/A — no fan-out; single-agent by design (see
  self-grill above).
- Workflow instead of agent? The procedure IS effectively a fixed decision
  tree (steps 2–5 branch on the step-1 classification) — about as
  workflow-shaped as a live-environment investigation can be, while still
  needing ReAct's observe-then-branch loop for the live reads.
- Reasoning-effort knob instead of hand-rolled loop? Considered; not
  applicable — the loop's value is in *which live facts to check*, not in
  more reasoning depth per call.
- Context curation needed? No — well under 5 rounds (8-action cap on a
  narrow, closed investigation).
- Cost bounds fail-closed? Yes — the 8-action cap is a hard stop that
  produces `INCONCLUSIVE`, not a silent full re-scan of everything.
- Every stage boundary contracted? Single-agent single-stage artifact; the
  output contract is the one boundary and it's a literal skeleton.
- Passes the prompt-quality smell test? Yes — runner manifest lists all four
  placeholders with fail-closed guidance, `<known_baseline>` /
  `<venv_detection_mechanism>` are marked as data, output has a literal
  fenced skeleton, every `Never` has a reason, default-refute + tie-break are
  stated (step 6), stop condition is echoed both mid-procedure and in the
  closing "before you answer" block.
- Dry-run walkthrough: given the four placeholders filled with their
  defaults, step 1 either finds a live daemon and captures the error, or
  reports UNVERIFIED and proceeds static-only; steps 2–5 each produce one
  concrete fact; step 6 requires ≥1 for + ≥1 against before the output
  contract can be filled in — the skeleton has a slot for every field the
  procedure produces, so it's parseable by a human (or a downstream stage)
  reading the result.
