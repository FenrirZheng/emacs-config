// cpp-workflow — multi-agent conversion of [cpp_workflow.md](cpp_workflow.md).
//
// The original is a single-agent prompt for "C++ work inside this Emacs 30.1
// config". This rewrites it as a deterministic Workflow: each section of the doc
// becomes a phase or an agent prompt, so the steps run as separate sub-agents
// with structured hand-offs instead of one long instruction blob.
//
//   doc §1 Role/objective        -> Triage phase (classify track A vs B)
//   doc §2 Ground truth          -> embedded into prompts + read-the-files step
//   doc §3 Prerequisites         -> Prereqs phase (parallel checks)
//   doc §4 In-editor workflow    -> Execute phase guidance (track A)
//   doc §5 Native module track   -> Execute phase guidance (track B)
//   doc §6 Conventions           -> CONVENTIONS, injected into every actor
//   doc §7 Acceptance checklist  -> Verify phase
//   doc §8 Constraints           -> doc-posture guard, threaded through
//
// Invoke with args:
//   { task: "<what the user wants>", track?: "A"|"B", configChange?: true }
// or just a bare string (treated as args.task). With no task, it runs in pure
// diagnostic posture: Prereqs + Verify audit only, no edits.

export const meta = {
  name: 'cpp-workflow',
  description: 'Assist with C++ work in this Emacs 30.1 config: triage app-C++ vs native-module track, verify clangd/compile_commands prerequisites, execute under the config conventions, then run the acceptance checklist',
  whenToUse: 'C++ development inside this Emacs config (clangd + eglot + tree-sitter), or authoring native Emacs C++ modules under cpp/. Faithful conversion of cpp_workflow.md.',
  phases: [
    { title: 'Triage', detail: 'classify track A (app C++) vs B (native module); detect config-change intent' },
    { title: 'Prereqs', detail: 'parallel ground-truth + prerequisite checks (clangd, compile_commands.json, build setup)' },
    { title: 'Execute', detail: 'do the work under the config conventions, or diagnose in doc posture' },
    { title: 'Verify', detail: 'run the acceptance checklist for the resolved track' },
  ],
}

// ---------------------------------------------------------------------------
// Shared ground truth — doc §2 + §6. Injected verbatim into every actor so no
// sub-agent re-adds existing config or violates a convention.
// ---------------------------------------------------------------------------

const GROUND_TRUTH = `
GROUND TRUTH — C++ LSP is ALREADY fully wired in this Emacs 30.1 config. Do NOT
install lsp-mode / ccls / irony / company-clang, and do NOT add a second clangd
hook. (doc cpp_workflow.md §2)
- LSP client: eglot (GNU ELPA, upgraded off the bundled copy), auto-starts on
  C/C++ buffers. Core in lisp/init-languages.el.
- Server launch: ("clangd" "--inlay-hints") registered in
  lisp/languages/init-c-cpp.el.
- Major modes: c-ts-mode / c++-ts-mode (treesit-auto remaps .c/.cc/.cpp/.h).
- Dead-branch dimming: eglot-inactive-regions (shadow-face).
- Inlay hints: eglot-inlay-hints-mode (global-on via eglot-managed-mode).
- No-server fallback nav: ggtags-mode (GNU Global GTAGS).
- Diagnostics: flymake <- eglot <- clangd. Hover: eldoc, side window on C-c d.
- Completion UI: Vertico + consult (NOT corfu; global-corfu-mode is OFF on purpose).
- Format-on-save: apheleia owns it. Debugging: dape (needs external C++ adapter).
- combobulate is intentionally NOT hooked for C/C++ — do not add it.`

const CONVENTIONS = `
CONVENTIONS YOU MUST HONOUR (doc cpp_workflow.md §6 + repo CLAUDE.md):
- apheleia owns format-on-save. NEVER add eglot-format/eglot-format-buffer to
  before-save-hook. C-c f is the manual-only escape hatch.
- To change C++ indent/style, edit a .clang-format at the project root — never
  tweak c-ts-mode-indent-offset / c-basic-offset in Elisp.
- Never globalize ggtags-mode; the M-./C-M-. neutralization in
  lisp/init-languages.el is load-bearing (else gtags shadows clangd on M-.).
- TTY-correct faces only (every frame is emacsclient -nw): theme-relative
  styling (shadow), never truecolour-only effects.
- Package hygiene: built-ins get :ensure nil; a brand-new package needs
  M-x my/package-refresh + restart (archive is never refreshed at boot).
- Per-language change goes in lisp/languages/init-c-cpp.el; shared infra in
  lisp/init-languages.el stays untouched.
- Docs in English; cross-references as markdown links with repo-relative paths.`

const DOC_POSTURE = `
POSTURE (doc cpp_workflow.md §8): doc/guidance by default. Do NOT edit Elisp
unless the user explicitly asked for a config change. If you believe a real gap
exists, state it and ask — do not "helpfully" add a second LSP client, globalize
a minor mode, or wire format-on-save. Prefer fixing the prerequisites (clangd,
compile_commands.json) over changing the config.`

// Hard guard for any agent that touches the live Emacs daemon via emacsclient.
// A prior Verify run wedged the daemon by calling (call-interactively #'eglot),
// which opened a minibuffer prompt that blocked the single command loop and made
// every later emacsclient --eval time out. Never let a checker do that.
const DAEMON_SAFETY = `
DAEMON SAFETY — when checking state through the live Emacs daemon (emacsclient):
- ONLY run non-interactive, side-effect-free evals. NEVER use call-interactively,
  M-x equivalents, or any command that can open a minibuffer prompt
  (eglot, eglot-rename, read-from-minibuffer, completing-read, y-or-n-p, etc.) —
  a blocking prompt wedges the daemon's single command loop and every later eval
  times out.
- To start a server for a check use (eglot-ensure) (non-interactive), never
  (call-interactively #'eglot) / (eglot ...) interactively.
- Wrap evals defensively: (ignore-errors ...) with a short timeout; treat a
  timeout/error as pass=false "could not confirm", do NOT escalate to interactive
  commands to "make it work".
- Prefer read-only inspection: (executable-find ...), (eglot-current-server),
  eglot--servers-by-project, buffer-local major-mode — not actions that mutate UI.
- If a check genuinely needs interaction, mark it pass=false with a note saying
  it requires manual verification; do not attempt it against the daemon.`

// ---------------------------------------------------------------------------
// Input parsing
// ---------------------------------------------------------------------------

const TASK = typeof args === 'string' ? args : (args && args.task) || ''
const FORCED_TRACK = (args && args.track) || null
const CONFIG_CHANGE = !!(args && args.configChange)

if (!TASK) {
  log('No task supplied — running in diagnostic posture: Prereqs + Verify audit only, no edits.')
}

// ===========================================================================
// Phase 1 — Triage (doc §1). Classify track A vs B; detect config-change intent.
// ===========================================================================

phase('Triage')

const TRIAGE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['track', 'rationale', 'isConfigChange'],
  properties: {
    track: { type: 'string', enum: ['A', 'B'], description: 'A = ordinary C/C++ application/library code (clangd over eglot). B = native Emacs C++ module under cpp/ wrapping emacs-module.h.' },
    rationale: { type: 'string', description: 'one sentence on why this track' },
    isConfigChange: { type: 'boolean', description: 'true ONLY if the user explicitly asked to change the Emacs Elisp config' },
  },
}

let triage
if (FORCED_TRACK) {
  triage = { track: FORCED_TRACK, rationale: 'forced via args.track', isConfigChange: CONFIG_CHANGE }
  log(`Track forced to ${FORCED_TRACK} via args.`)
} else if (!TASK) {
  triage = { track: 'A', rationale: 'no task — defaulting to app-C++ audit', isConfigChange: false }
} else {
  triage = await agent(
    `You are triaging a C++ task for this Emacs config. Decide the track.
${GROUND_TRUTH}

TASK: ${TASK}

Track A = editing ordinary C/C++ app/library code anywhere on disk (the editor
support is already wired; your later job is to USE/troubleshoot it).
Track B = writing a native Emacs C++ .so under the cpp/ workspace (see
cpp/README.md, junit-core is the worked example).

Also decide isConfigChange: true ONLY if the task explicitly asks to modify the
Emacs Elisp config (e.g. "add a keybinding", "register a new server option").`,
    { phase: 'Triage', schema: TRIAGE_SCHEMA },
  )
}

log(`Track ${triage.track}: ${triage.rationale}${triage.isConfigChange ? ' [config-change requested]' : ''}`)

// ===========================================================================
// Phase 2 — Prereqs / ground truth (doc §2 + §3). Parallel independent checks.
// A barrier is correct here: Execute needs the full prereq picture at once.
// ===========================================================================

phase('Prereqs')

const CHECK_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['name', 'status', 'evidence', 'fix'],
  properties: {
    name: { type: 'string' },
    status: { type: 'string', enum: ['ok', 'missing', 'unknown'] },
    evidence: { type: 'string', description: 'what you ran/read and what it showed' },
    fix: { type: 'string', description: 'exact command(s) or doc reference to remediate; empty if status ok' },
  },
}

const trackAChecks = [
  {
    label: 'clangd-on-path',
    prompt: `Verify clangd is reachable for Emacs (doc cpp_workflow.md §3.1).
Run: which clangd; clangd --version. Note the daemon-PATH gotcha — Emacs may have
a narrower PATH than the shell; the in-Emacs check is M-: (executable-find "clangd").
If absent: sudo apt install clangd (or versioned clangd-NN + symlink), and
M-x exec-path-from-shell-initialize for the daemon-PATH case.`,
  },
  {
    label: 'compile-commands',
    prompt: `Check whether the relevant project has a compile_commands.json (or
compile_flags.txt / a .clangd pointing at build/) that clangd will resolve — the
single biggest correctness lever (doc cpp_workflow.md §3.2). Look for it at the
project root or a build/ dir. If missing, report the generation path that fits the
build system: CMake (cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON +
symlink or a .clangd CompilationDatabase: build/), Make (bear -- make), or a tiny
compile_flags.txt. Do NOT assume CMake.`,
  },
  {
    label: 'clangd-config',
    prompt: `Optional: report whether ~/.config/clangd/config.yaml exists and what
it tunes (per-hint InlayHints, extra diagnostics, CompileFlags: Add). The Emacs
side only flips the master switch; hint/diagnostic DETAIL belongs here (doc
cpp_workflow.md §3.3). status=ok if present or legitimately absent (it's optional).`,
  },
]

const trackBChecks = [
  {
    label: 'cpp-workspace',
    prompt: `Verify the native-module workspace (doc cpp_workflow.md §5). Read
cpp/README.md and cpp/CMakeLists.txt (the aggregator). Confirm it is a multi-project
CMake tree (NOT a submodule), that junit-core is the worked example, and that
cpp/build.sh exists. Report the add-a-module steps as evidence.`,
  },
  {
    label: 'build-toolchain',
    prompt: `Check the native build prerequisites: a C++ toolchain + cmake, and
that cpp/build.sh runs. For junit-core specifically, libtree-sitter-dev is the only
apt dep (the java grammar is vendored). Report status + the build command
(~/.emacs.d/cpp/build.sh, or M-x <front-end>-build).`,
  },
]

const checks = triage.track === 'B' ? trackBChecks : trackAChecks
const prereqs = (await parallel(
  checks.map(c => () =>
    agent(`${c.prompt}\n${DOC_POSTURE}\n${DAEMON_SAFETY}`, { label: `check:${c.label}`, phase: 'Prereqs', schema: CHECK_SCHEMA }),
  ),
)).filter(Boolean)

const blocking = prereqs.filter(p => p.status === 'missing')
for (const p of prereqs) log(`prereq ${p.name}: ${p.status}`)
if (blocking.length) {
  log(`${blocking.length} blocking prerequisite(s) missing — Execute will fix these before touching config.`)
}

// ===========================================================================
// Phase 3 — Execute (doc §4 track A / §5 track B). Honours posture: in pure
// diagnostic mode (no task) this is skipped.
// ===========================================================================

phase('Execute')

const EXEC_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'actionsTaken', 'openQuestions'],
  properties: {
    summary: { type: 'string' },
    actionsTaken: { type: 'array', items: { type: 'string' } },
    openQuestions: { type: 'array', items: { type: 'string' }, description: 'anything that needs the user to decide before proceeding (e.g. header/source switching key, eglot-x)' },
  },
}

let execution = null
if (TASK) {
  const trackGuidance = triage.track === 'B'
    ? `TRACK B — native Emacs C++ module (doc cpp_workflow.md §5). Keep the
compute-only discipline: parse/transform/local-file-I/O in C++, NEVER launch a
process or watch directories from C++ — that belongs to the elisp front-end (the
junit-core <-> lisp/junit-runner.el split is the template). To add a module:
cpp/<name>/CMakeLists.txt (add_library MODULE, PREFIX "", SUFFIX ".so"), sources
under cpp/<name>/src/, one add_subdirectory line in cpp/CMakeLists.txt, build via
cpp/build.sh, load via (module-load (expand-file-name "cpp/lib/<name>.so" ...)).`
    : `TRACK A — ordinary C/C++ via clangd/eglot (doc cpp_workflow.md §4). Use and
troubleshoot the EXISTING support; do not re-add an LSP client. Key flows: M-. /
M-? navigation (crosses files via eglot-extend-to-xref), M-g s consult-eglot-symbols,
C-c . eglot-code-actions (the primary way to add a missing #include), C-c r rename,
C-c f manual format only. Header/source switching is NOT bound — use M-x
ff-find-other-file ad hoc; a real key needs eglot-x (NOT installed) — surface that
and ask before adding. Debugging via dape needs an external adapter (codelldb/
lldb-dap/gdb); set the target in the project .dir-locals.el, never the global. No
C++ test-runner key — run tests via M-x compile (ctest / make test).`

  const allowEdits = triage.isConfigChange || CONFIG_CHANGE
  execution = await agent(
    `Execute this C++ task for the Emacs config.
TASK: ${TASK}

${GROUND_TRUTH}
${trackGuidance}
${CONVENTIONS}
${DOC_POSTURE}

Resolved prerequisite state (fix any 'missing' BEFORE changing config — that
resolves the overwhelming majority of "LSP isn't working" reports):
${JSON.stringify(prereqs, null, 2)}

Elisp edits are ${allowEdits ? 'PERMITTED (the user explicitly requested a config change) — but keep changes in lisp/languages/init-c-cpp.el per the per-language convention' : 'NOT permitted (no config change was requested) — stay in guidance posture; if a config gap is real, put it in openQuestions and ask'}.`,
    { phase: 'Execute', schema: EXEC_SCHEMA },
  )
  log(`Execute: ${execution.summary}`)
} else {
  log('Execute skipped (diagnostic posture).')
}

// ===========================================================================
// Phase 4 — Verify (doc §7). Run the acceptance checklist for the track.
// ===========================================================================

phase('Verify')

const VERIFY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['allPass', 'items'],
  properties: {
    allPass: { type: 'boolean' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['check', 'pass', 'note'],
        properties: {
          check: { type: 'string' },
          pass: { type: 'boolean' },
          note: { type: 'string' },
        },
      },
    },
  },
}

const checklist = triage.track === 'B'
  ? `Native-module acceptance (doc cpp_workflow.md §7):
- cpp/build.sh exits 0 and produces cpp/lib/<name>.so
- (module-load ...) succeeds and the exported functions are callable`
  : `C++ editing acceptance (doc cpp_workflow.md §7), in a C/C++ buffer:
- clangd reachable: M-: (executable-find "clangd") is non-nil
- project has a compile_commands.json (or compile_flags.txt) clangd resolves
- modeline shows Eglot(c++-ts/...) / Eglot(c-ts/...) — server attached
- M-. jumps to a definition (including across files)
- M-? lists references; M-n / M-p walk diagnostics
- inlay hints render (C-c h i); a false #if 0 / #ifdef branch is dimmed`

const verdict = await agent(
  `Run this acceptance checklist and report each item honestly (pass=false if you
can't confirm it — never assume).
${checklist}
${DAEMON_SAFETY}

Context from earlier phases:
prereqs=${JSON.stringify(prereqs)}
execution=${execution ? JSON.stringify(execution) : 'none (diagnostic posture)'}`,
  { phase: 'Verify', schema: VERIFY_SCHEMA },
)

log(`Verify: ${verdict.allPass ? 'ALL PASS' : 'gaps remain — see items'}`)

return {
  track: triage.track,
  triage,
  prerequisites: prereqs,
  blockingPrereqs: blocking,
  execution,
  acceptance: verdict,
}
