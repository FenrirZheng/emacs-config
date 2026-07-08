# Task — IDE-style Python test runner for this Emacs config

## Role & stance
You are a senior Emacs-Lisp + systems engineer extending a **personal, TTY-first Emacs 30.1
config** (daemon + `emacsclient -nw` inside tmux). You are implementing a real feature that
must load and run on the user's machine — not a sketch. Assume nothing works until you have
watched it work with pasted real output. Prefer the smallest thing that satisfies the oracle;
reuse existing repo patterns over inventing new ones.

## Inputs (delimited; fail closed)
```
EMACS_CONFIG   = /home/fenrir/.emacs.d          # the repo you edit; $HOME/.emacs.d
TARGET_REPO    = /home/fenrir/code/hitok2/sms-service
TARGET_TEST    = /home/fenrir/code/hitok2/sms-service/tests/test_crypto_vectors.py
FRAMEWORK      = pytest   (assumed; VERIFY in Phase 0 — if the repo uses unittest/nose, STOP and report)
```
- If `TARGET_TEST` does not exist or is empty, STOP and say so — do not fabricate a test file.
- If Phase 0 shows the repo is **not** pytest-based, STOP and report before writing any code.

## What "done" means (the feature)
Two IDE-grade commands in Python buffers, mirroring how Go (`C-c t t` / `C-c t d`) and Java
(`C-c t` JUnit prefix) already work in this config:
1. **Run the test at point** — cursor anywhere inside a test → run exactly that test
   (function `def test_*`, or method `Class::test_*`), streamed in a `compile` buffer.
2. **Run all tests in the current file** — run the whole `TARGET_TEST`-style file.
3. (Nice-to-have, only if cheap) run-whole-project and re-run-last-failed.

Bind under the `C-c t` prefix, **shadowed in `python-mode`/`python-ts-mode` buffers only**
(exactly as Go/Java do — do not steal `C-c t` globally). Suggested: `C-c t t` = at point,
`C-c t f` = file, `C-c t a` = project, `C-c t l` = last-failed. Update `FEATURES.md`.

---

## Procedure

### Phase 0 — Recon (READ ONLY, write nothing)
Read and quote back the load-bearing facts before deciding anything:
- `EMACS_CONFIG/lisp/languages/init-python.el` — how Python/eglot/apheleia/venv are wired now.
- `EMACS_CONFIG/lisp/languages/init-go.el` — the `C-c t t`/`C-c t d` **pure-elisp** test-runner
  precedent (how it builds the command, chooses cwd, calls `compile`).
- `EMACS_CONFIG/lisp/languages/init-java.el` + `EMACS_CONFIG/lisp/junit-runner.el` +
  `EMACS_CONFIG/cpp/junit-core/README.md` — the **native-module** test-discovery precedent
  (tree-sitter at-point discovery in C++, elisp front-end runs via `compile`).
- `EMACS_CONFIG/rust/question-queue-core/README.md` — the Rust dynamic-module precedent
  (cargo `cdylib`, `module-load`, `rust/lib/`) if you go native.
- Confirm the Python tree-sitter grammar is installed (`treesit-language-available-p 'python`)
  and whether `python-ts-mode` is the active major mode here.
- In `TARGET_REPO`: is there a `.venv/`? a `pyproject.toml` / `pytest.ini` / `conftest.py`?
  Where is the pytest rootdir? Skim `TARGET_TEST` for the test *shapes* present
  (plain functions, classes, parametrize, async).

Emit a short **Recon digest** (bullet facts + the answers above). Do not proceed to code until
this is written.

### Phase 1 — Architecture decision gate (measured, fail-closed)
The user said "效能要注意，可考慮 C++ 或 Rust." Treat that as a hypothesis to test, **not** a
mandate. Decide **pure-elisp vs native module** on a measurement, not on the mention:

- **Default = pure elisp** using built-in `treesit` (Emacs already ships tree-sitter + the
  Python grammar is installed), running via `compile`. Rationale to confirm or refute:
  at-point discovery parses **one already-open buffer** — sub-millisecond in elisp — so the
  native-module perf argument does **not** apply to the two required commands. This path also
  has zero extra build step on a fresh clone (no cargo/cmake/`module-load`).
- **Escape hatch → go native (Rust, mirroring `question-queue-core`)** ONLY if you produce a
  concrete measurement showing the elisp path is too slow for a *stated real workload*
  (e.g. project-wide collection over N files). Note first whether `pytest --collect-only -q`
  already covers that case better than any module would.
- **Fail closed**: do NOT build a native module merely because Rust/C++ was mentioned. If you
  cannot show a measured win, choose elisp and say why in one line.

Write the decision + the measurement (or the one-line "no measured win → elisp") before coding.

### Phase 2 — Plan (plan-then-execute; do not skip)
List the files you will create/modify and the acceptance criterion for each, e.g.:
`lisp/languages/init-python.el` (bindings + command builder), possibly
`lisp/python-test-runner.el` (front-end), `FEATURES.md` (§ for the keys), and — only if Phase 1
chose native — the module under `rust/<name>/` or `cpp/<name>/` + its README + build wiring.
Do not write code in this phase.

### Phase 3 — Implement against oracles (stepwise loop, PRM-style)
Implement, then after EACH step run the matching oracle and **paste the real output**. Fix only
the first real failure; repeat that step until green before moving on. The stepwise oracle stack:

1. **Discovery correctness (the core oracle).** Build a fixture table from the REAL
   `TARGET_TEST`: pick ≥1 line inside each distinct test shape found in Phase 0 and record the
   expected pytest nodeid. Assert your discovery returns exactly those nodeids.
   ```
   | cursor line (inside…)                    | expected nodeid                                   |
   |------------------------------------------|---------------------------------------------------|
   | a top-level `def test_*`                 | tests/test_crypto_vectors.py::test_foo            |
   | a method in `class TestX:`               | tests/test_crypto_vectors.py::TestX::test_bar     |
   | a `@parametrize`d test                   | tests/test_crypto_vectors.py::test_baz            |  # runs all params
   | an `async def test_*` (if present)       | tests/test_crypto_vectors.py::test_qux            |
   | a non-test line between two tests        | nearest ENCLOSING test, else clear "no test here" |
   ```
   (Fill from the actual file — if a shape is absent, drop that row and note it; do NOT invent
   a shape the file doesn't contain.)
2. **Command correctness.** For each discovered nodeid, verify with
   `pytest --collect-only -q <nodeid>` (run from the resolved rootdir, in the resolved venv)
   that it collects exactly the intended test(s) and the count matches. Paste the collect output.
3. **venv / cwd resolution.** Confirm the command uses `TARGET_REPO/.venv/bin/pytest` when a
   `.venv` exists (this config already auto-detects `.venv` for pyright — reuse that logic, do
   not hardcode a python path), falls back to `python -m pytest` otherwise, and runs **from the
   pytest rootdir** so `conftest.py`/`pyproject.toml` are picked up.
4. **Real execution.** Run "at point" and "whole file" on `TARGET_TEST` through the actual
   command; paste the real pytest pass/fail summary from the `compile` buffer.
5. **Load / regression.** Reload the module cleanly: `emacs -Q --batch` load of the edited
   files must byte-compile without error, and a daemon reload
   (`emacsclient --eval "(load-file \"…/init-python.el\")"`) must not error. Confirm the new
   `C-c t` binding is Python-buffer-local and did NOT clobber Go's/Java's `C-c t` or any global
   binding. (If Phase 1 chose native: also `module-load` the `.so` and call its `*-version`
   smoke fn.)

### Phase 4 — Adversarial edge-case verification (fear: plausible-but-wrong nodeid)
For EACH edge case below, adopt the stance **"this is broken until I prove it works"** and show
the concrete input→output that proves it. Default verdict = BROKEN; only mark ✅ with pasted
evidence (a `--collect-only` line or a real run). Uncertain ⇒ BROKEN.
- Parametrized test: does running by function name run **all** param cases? Is that the intended
  UX, or should it offer to pick a single `[param]` id? State the choice and why.
- Method inside a class → `File::Class::method` nodeid (NOT `File::method`).
- Nested class (`class Outer:` → `class Inner:`) if present.
- Cursor on a blank line / decorator / import → sensible "nearest enclosing test, else run-file
  or clear message", never a wrong test.
- File with zero tests, or a non-test `.py` buffer → refuses cleanly, no garbage command.
- Path with spaces / the nodeid quoting in the shell command.

### Phase 5 — Devil's advocate on the diff + docs
Give 2 concrete scenarios where this still breaks in the user's real workflow (e.g. tests run
from the wrong rootdir so `conftest` fixtures 404; a monorepo sub-package with its own
`pyproject.toml`; TTY `compile` buffer vs their tmux setup). Address or explicitly dismiss each.
Confirm `FEATURES.md` documents the new keys and that `CLAUDE.md`'s init-python description still
holds (update if the architecture changed).

---

## Output contract
Produce, in this order:
1. **Recon digest** (Phase 0 facts).
2. **Architecture decision** — `elisp` or `native`, with the measurement or the one-line
   "no measured win → elisp".
3. **Change set** — the final list of files created/modified, one line each.
4. **Oracle log** — for each of the 5 stepwise oracles: the command run and its **real pasted
   output** (not a paraphrase). The discovery fixture table, filled, with pass/fail per row.
5. **Edge-case table** — each Phase-4 case with ✅/❌ and its one-line evidence.
6. **Devil's-advocate** — the 2 scenarios and their resolution.
7. **How to use** — the exact keys and what each does.

## Stop condition
Stop when: every stepwise oracle in Phase 3 is green **with pasted real output**, every present
edge-case row in Phase 4 is ✅ with evidence, and `FEATURES.md` is updated. Hard cap: **6
implement→oracle rounds** per oracle; if an oracle is still red at the cap, STOP and report the
red output + your best diagnosis rather than looping or faking green.

## Prohibitions (with reasons)
- **Never claim a test "runs" without pasting the real pytest output.** Models report imagined
  passes; the whole feature is worthless if the constructed nodeid is subtly wrong.
- **Never build a native (Rust/C++) module without a pasted measurement showing an elisp win is
  insufficient.** "The user mentioned Rust" is not a measurement; a needless `module-load` adds
  fresh-clone build friction this repo is careful about.
- **Never bind `C-c t` globally or on a global hook.** It must be Python-buffer-local, or it
  clobbers Go/Java's `C-c t` and vterm — a known trap documented in this repo's CLAUDE.md.
- **Never hardcode a python/pytest path.** Resolve the venv the way pyright already does here;
  a hardcoded path breaks the moment the project's `.venv` differs.
- **Do not add `eglot-format`/format-on-save side effects or touch unrelated modules** — one
  feature, minimal diff.

## Escape hatch
If any step cannot be verified on the real machine (e.g. `TARGET_REPO` has no `.venv` and pytest
isn't importable, or a test shape from the fixture table isn't actually present in the file),
mark that row `UNVERIFIED — <reason>` and continue with the rest. An admitted gap is worth more
than a green checkmark you can't back with pasted output. If the whole feature is blocked (no
pytest, no target file), STOP and report the block — do not build against a fabricated fixture.
