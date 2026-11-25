# Plan: apply the verified Emacs performance findings (booster verdict, Magit timing, wrong docs)

Source note: `/home/fenrir/code/org-roam/codeVault/emacs/Emacs_Performance_Verified_Findings.org` ("findings" below, cited as `F:<line>`).
Status: nothing here has been executed. Commands that do not exist yet are labelled.

**Execution (user decision):** a spawned `general-purpose` subagent runs P1-P5, using the `/orchestrate` subagent variant. The orchestrating session does not edit project code. It reviews the worker's phase 1 plan against the four checks in `~/.claude/skills/advisor-orchestrator-worker/references/worker-brief.md`, replies by `SendMessage`, verifies the checks in sections A and E with its own runs, and relays the `no-win` removal question to the user. Worker limits: no push, no commit unless the user asks, no daemon restart, `early-init.el` and `lisp/init-org.el` untouched, no removal without the user's yes.

## A. Goal, success criteria, non-goals

**Underlying goal.** Make the performance decisions in this config rest on measurement, as the findings ask (`F:28`, `F:73`). This does not mean applying more tweaks: `tasks/emacs-perf-followups.org` (commit `07bec51`) already compared the note with the config and found nothing new to switch on. This plan executes that file's three TODOs and fixes docs that contradict the code or the findings.

The "Now" column was run during planning, except S6's hash, which is recorded when implementation starts.

| # | Success criterion | Command or observation | Now | Done |
|---|---|---|---|---|
| S1 | The booster has a measured verdict from a pre-committed rule | `ug -n 'Verdict: (no-win\|io-only\|bytecode\|inconclusive)' tasks/emacs-perf-followups.org`; `ug -n '^\| *(off\|io-only\|bytecode) *\|' tasks/emacs-perf-followups.org` | no match for either | one verdict line; at least one row for each mode |
| S2 | Live config matches the verdict | `emacsclient -e "(list (bound-and-true-p eglot-booster-mode) (bound-and-true-p eglot-booster-io-only) (and (advice-member-p 'eglot-booster--jsonrpc--json-read 'jsonrpc--json-read) t))"` | `(t nil t)` | `(t nil t)` for bytecode, inconclusive, or no-win with removal declined; `(t t nil)` for io-only; `(nil nil nil)` for removal |
| S2b | The verdict persists across a restart | Fresh-init row in section F. For io-only, also `ug -n 'eglot-booster-io-only t' lisp/init-languages.el` | no match | fresh init prints the S2 values; io-only line present only in that branch |
| S3 | The wrong option name and unmeasured speed claims are gone | `ug -n 'eglot-booster-program-args\|Win regardless of message size\|still meaningful for large payloads' lisp/init-languages.el`; `ug -n 'meaningfully faster' FEATURES.md` | hits at `:316`, `:319`, `:324`; `FEATURES.md:667` | no hits |
| S4 | Magit has been timed once, including `diff-hl-magit-post-refresh` under open buffers | `ug -n 'diff-hl-magit-post-refresh.*[0-9]+\.[0-9]+ ?s' tasks/emacs-perf-followups.org` | no match | line with seconds and the buffer count |
| S5 | The follow-up TODOs are closed | `ug -n '^\*\* TODO' tasks/emacs-perf-followups.org` | lines 9, 16, 22 | no lines |
| S6 | The user's unrelated edits are untouched | `git diff -- early-init.el lisp/init-org.el \| sha256sum`, compared with the hash saved at the start of implementation | recorded at start | same hash, unless the user edited those files during the work |

**Non-goals.** No new tuning knobs on unverified evidence (`F:17-26`). No fixes to anything the Magit run finds; those become tickets. No daemon restart by the implementer.

## B. Current state and evidence

**Confirmed: already matches the findings, no change** (`tasks/emacs-perf-followups.org:36-41`; re-read today):
- `global-so-long-mode`: `lisp/init-defaults.el:24`. Live: `so-long-threshold` 10000, targets exclude `text-mode`.
- `long-line-threshold` 50000 and `large-hscroll-threshold` 10000 are defaults (`F:56`).
- Startup GC and gcmh: `early-init.el:33-39`, `lisp/init-defaults.el:163-167`. The findings rate this low confidence (`F:86-89`). The vault notes `GCMH_Adaptive_GC.org` and `gcmh_Low_Threshold_Overrides_early-init_GC_Floor.org` record why the 16 MB floor exists.
- Timers (`F:38`): live list has one `org-indent-initialize-agent`, so no leak after `f4286dd`. `diff-hl-dired-mode` stays unhooked (`lisp/init-git.el:605`).
- `magit-refresh-status-buffer` is unset (`F:82`); the grep found no use.

**Confirmed: defects and gaps.**
- `lisp/init-languages.el:322-325` says to use `eglot-booster-no-remote-boost` / `eglot-booster-program-args`. The second does not exist and the first is unrelated. The real switch is `eglot-booster-io-only` (`elpa/eglot-booster/eglot-booster.el`, defcustoms after `;;; Code:`).
- `FEATURES.md:664-668` claims "meaningfully faster even on Emacs 30's already-quick native JSON parser" with no measurement. `F:73` says no controlled benchmark was found. `lisp/init-languages.el:315-321` makes softer versions of the same claim.
- `lisp/init-languages.el:337`, `_doc/GOTCHAS.md:47-50`, `CLAUDE.md:158-159` and `FEATURES.md:673` say `M-x eglot-booster-mode` recovers at runtime. The package commentary says boosted servers must be restarted. Inference from source: with the read advice removed, a still-running bytecode server's `#[...` messages reach the plain JSON parser and fail.
- The installed booster is `cab7803` (2025-07-16), so its local README has no archive notice. The notice is known from `F:71`, not from the local copy.

**Confirmed: the mechanism being measured.**
- `jsonrpc--process-filter` (`elpa/jsonrpc-1.0.28/jsonrpc.el:777`) calls `jsonrpc--json-read` (`:691`, native `json-parse-buffer`) and copies each message with `buffer-string` into `:jsonrpc-json` (`:846-847`). The copy happens in every mode.
- `eglot-booster--wrap-contact` reads `eglot-booster-io-only` at connect time. The read advice is added only when the mode is *enabled* with io-only nil. **A bare `setq` on a running daemon is not a mode switch.**
- Booster args: bytecode `--json-false-value :json-false --`; io-only `--disable-bytecode --`.
- `eglot--connect` signature: `(managed-modes project class contact language-ids)` (`elpa/eglot-1.23/eglot.el:1758`). The booster's advice wraps `(nth 3 args)`.
- Live: Emacs 30.1, native comp on, Eglot 1.23, jsonrpc 1.0.28, `read-process-output-max` 65536, `gcmh-high-cons-threshold` 1073741824, 0 connected servers at planning time, 15 GB RAM with 10 GB used.

**Confirmed: batch constraints on managing a buffer.**
- A server is registered under the project passed to `eglot--connect` (`eglot.el:1875`), but a buffer looks it up through `project-current` (`eglot.el:1592-1601`, `:2454`). The benchmark repo's Git root is its parent, `~/code/coinsasia`, so a bare transient project would never match.
- `eglot-current-server` returns nil in `fundamental-mode` (`eglot.el:2451`). Under `-Q`, `.go` has no `auto-mode-alist` entry (probe returned nil). `go-ts-mode` is loadable, and the grammar is at `tree-sitter/libtree-sitter-go.so`.

**Confirmed: Magit timing.**
- `magit-refresh` (`elpa/magit-20260506.643/magit-mode.el:1050-1076`) times each function on the pre- and post-refresh hooks through `magit-run-hook-with-benchmark` (`:1604-1614`).
- `magit-refresh-buffer-hook` runs through plain `run-hooks` (`:1125`). It counts in the refresh total but gets no per-function time.
- `diff-hl-magit-post-refresh` does per-buffer work only for unmodified file-visiting `diff-hl-mode` buffers (`elpa/diff-hl-20260427.2329/diff-hl.el:1427-1447`), so timing it with only status buffers open says little.
- `test/magit-time-test.el:13-20` is a working batch loader for real `init-git`. `_doc/GOTCHAS.md:142-144` warns against double refreshes.

**Assumption.** Eglot connects in `-Q --batch`; Eglot's own test suite works this way, but it has not been run here. P1's check settles it.

**Not checked.** Which Emacs release merged the bug#69385 fix (`F:103`); this plan does not depend on it.

## C. Key questions, by impact

1. **Does the booster help on this Emacs at all?** It is a kept dependency that advises two internals of an archived upstream, and any decision without a number is a guess (`F:73`, `F:102`). The answer picks the P3 branch. `tasks/emacs-perf-followups.org:20` says to benchmark "only if LSP feels slow"; this plan runs it anyway because the findings say to measure before *keeping*. **Handled:** P1 and P2.
2. **What metric decides it?** Round-trip time is dominated by the server and hides Emacs's cost, so the harness records blocked time inside `jsonrpc--process-filter`. Decision metric: median blocked ms. Context only: parse ms, round trip, bytes consed, `gc-elapsed`. **Limit:** batch has no redisplay, so a verdict covers process-side blocking, not perceived latency. The verdict line says so.
3. **Does a realistic workload produce large payloads?** The examples at `lisp/init-languages.el:320-321` are claims, and `workspace/symbol` may be capped by the server (not verified). A 100 KiB payload might never occur on gopls. **Handled:** P2 classifies actions by off-mode response size; no action over 100 KiB gives `inconclusive`, not `no-win`.
4. **Which server?** Go with gopls on the largest local Go service (1120 files, 232k lines, `~/code/coinsasia/backend/backend-api-golang`). One server limits how far the result generalizes. The verdict is labelled gopls-only. `~/code/helix` (103k lines of Rust) has no `target/`, so rust-analyzer would start cold and build. **Deferred;** the harness takes server and directory as arguments, so it is one more command.
5. **Felt slowness (question timed out, provisional).** Default: none assumed, no extra profiling tracks. If the user names a symptom, add the matching track from "Can defer".
6. **Removal on no-win (question timed out, provisional).** Recommended default is removal, but it needs the user's confirmation *after* seeing the numbers. Without that, P3 takes the docs-only path.
7. **Does the Magit run belong in a live daemon?** No. `magit-pre-refresh-hook` is `magit-maybe-save-repository-buffers` and `magit-status-setup-buffer` changes windows. A batch process avoids saving or moving anything in the user's session.

## D. Approach and alternatives

**Recommended:** an opt-in harness that runs real Eglot in a separate `emacs -Q --batch` process per mode (off, io-only, bytecode), with rotated order and a verdict computed by a pure function fixed in advance.

| Alternative | Why not |
|---|---|
| Apply `eglot-booster-io-only` now, or remove the booster now | Exactly the unmeasured guess `tasks/emacs-perf-followups.org:13` warns about |
| Time in the live daemon | Mode switching needs server restarts, it disturbs the session, and shared state skews runs |
| Parse-only micro-benchmark on a captured payload | Misses the chunked filter, the `buffer-string` copy and any I/O-buffering effect; it can only ever favour bytecode. Parse ms is still recorded |
| Bare `jsonrpc-process-connection` without Eglot | Must then answer `workspace/configuration` etc. by hand, and skips the real `eglot--connect` advice path |

Tradeoff accepted: real Eglot in batch is more fragile than a bare connection. P1 proves it works before any measuring.

**Pre-committed rule.** L = action with off-mode response of at least 100 KiB. S = action under 20 KiB. A mode *qualifies* if, in each of 3 rotations:
- median blocked ms on L is at least 25% **and** at least 5 ms below off, and
- median blocked ms on S is not worse than off by both more than 25% and more than 1 ms.

Verdict, first match wins:
1. No L action found: `inconclusive`.
2. Neither mode qualifies: `no-win`.
3. Only one mode qualifies: that mode.
4. Both qualify: `bytecode` if it is at least 25% better than io-only on L in every rotation, otherwise `io-only` (less patching).

The thresholds are provisional and can be changed at plan approval; they must not be changed after seeing results.

**Pre-mortem.**
- *Noise from the user's concurrent work:* three rotations, medians, and a win must hold in all three.
- *A mode silently not active:* each run asserts the process command, that the buffer is managed, and how the probe reply was encoded (P1 check).
- *Different results between modes:* assert result count equals off-mode for each action; a mismatch aborts.
- *Out of memory:* one server at a time, and abort if available RAM is under 3 GB at start.
- *Indexing still running:* poll one fixed `textDocument/references` request until its response size is stable for 3 polls, with a 10 min limit, then exit non-zero. Polls are excluded from samples.
- *A wrong verdict leads to removal:* the user confirms with numbers in hand, and rollback is `git revert` plus `package-vc-install`.

## E. Phases

Must address: P1-P5. Commit only when the user asks. Before the first edit, save the S6 hash and run the fresh-init row (section F) once to record its baseline.

### P1: Harness (`test/booster-bench.el`, new)
- **Purpose.** Opt-in benchmark, not part of any suite, same status as `test/libsrc-e2e.el`. Loading it starts nothing. Runner functions use the package loader from `test/magit-time-test.el:13-14`.
- **Per-process setup.** Mode from argument. Set `eglot-booster-io-only` before `(eglot-booster-mode 1)`; off mode never enables it. Add timing advice *after* the mode so it is outermost. `gc-cons-threshold` = 1 GiB, mirroring live `gcmh-high-cons-threshold`; `(garbage-collect)` before each action block. Eglot events `:size 0`, matching `lisp/init-languages.el:165`.
- **Connect.**
  - Expand `DIR` once, with a trailing slash, and use that same string everywhere below. `eglot--servers-by-project` matches on the project value, so a differently spelled `DIR` gives the same unmanaged buffer.
  - Set `project-find-functions` to return `(cons 'transient DIR)`, so the buffer's lookup matches the registered project (`eglot.el:1592-1601`, `:1875`).
  - Add `~/.emacs.d/tree-sitter` to `treesit-extra-load-path`, `(require 'go-ts-mode)`, visit one source file and call `(go-ts-mode)`.
  - Then `(eglot--connect '(go-ts-mode) (cons 'transient DIR) 'eglot-lsp-server '("gopls") '("go"))`.
  - Never `didSave`, never apply edits, so the repo is not written.
- **Actions.** At minimum `textDocument/references`, `textDocument/hover`, `textDocument/completion`, `workspace/symbol`, plus one large `didChange` timed in `jsonrpc-connection-send` (report only). N = 30 after readiness.
- **Output.** CSV to `var/booster-bench/` (gitignored). Metadata row: versions, `(symbol-file 'eglot--connect)`, native-comp state of the filter.
- **Verdict.** Pure function `booster-bench-verdict`, with ERT tests on synthetic data: each of the four rule steps, "wins 2 of 3 rotations" does not qualify, and "io-only qualifies while bytecode is better on L but fails on S" gives `io-only`.
- **Depends on:** none.
- **Check 1** (new command, 10 s timeout): `emacs -Q --batch -l test/booster-bench.el -f ert-run-tests-batch-and-exit` reports all passing. Before: fails, file does not exist.
- **Check 2** (new command, run in background): `emacs -Q --batch -l test/booster-bench.el -f booster-bench-smoke` sends one `textDocument/hover` per mode and prints three lines. Every line must show `managed=t` from `(eglot-managed-p)` in the test buffer and a non-nil reply. off: no `emacs-lsp-booster` in the command, probe reply starts with `{`. io-only: `--disable-bytecode` present, probe reply starts with `{`. bytecode: `--json-false-value` present, probe reply starts with `#`. Any other result means the path under test never ran, and P2 must not start.

### P2: Measure
- **Purpose.** Run 3 rotations of off, io-only, bytecode on gopls in background, one child Emacs per mode and rotation. Estimated 15-30 min (unverified). No API cost. Writes `var/booster-bench/` and gopls's own cache. gopls may also run `go list` or `go mod download` if the module cache is incomplete, which can mean network access and writes to `GOMODCACHE`, but not to the repo.
- **Depends on:** P1.
- **Check** (new command): `emacs -Q --batch -l test/booster-bench.el --eval '(booster-bench-run "gopls" "~/code/coinsasia/backend/backend-api-golang/")'` exits 0 and prints `Verdict: <value>` with one median table per rotation. Before: no CSV or verdict exists.

### P3: Apply verdict and correct docs
- **Always:**
  - Fix `lisp/init-languages.el:315-325` to name `eglot-booster-io-only` and cite the measured result.
  - Note at `:337` and `CLAUDE.md:158-159` that servers must be shut down before toggling. Read that bullet's history with `git log -S` first.
  - Replace the claims at `FEATURES.md:664-674` with the measured result, the restart requirement and the upstream archive status (`F:71`).
  - Add measurement summary and the toggle order to `_doc/GOTCHAS.md:45-50`, through `record-convention`. Describe the repo by size, not by client name.
- **`bytecode` or `inconclusive`:** no config change.
- **`io-only`:** add `:custom (eglot-booster-io-only t)` to the block at `lisp/init-languages.el:345-348`. Live order: shut down servers, `(setq eglot-booster-io-only t)`, `(eglot-booster-mode -1)`, `(eglot-booster-mode 1)`, reconnect.
- **`no-win`:** ask the user, showing the numbers. On yes, remove:
  - `lisp/init-languages.el:12,143-145,312-348`; `custom.el:23,44`.
  - `lisp/languages/init-toml.el:41-43` (would falsely say the booster wraps the connection); the comparison at `lisp/languages/init-rust.el:58`.
  - `shell/install-user.sh:8,59-60,68` and `README.md:27`, so a fresh clone stops installing the binary.
  - `FEATURES.md:664-674`; `_doc/ARCHITECTURE.md:97`; `_doc/BOOTSTRAP.md:62,95`; `_doc/README.md:11`; `_doc/GOTCHAS.md:45-50`.
  - The `eglot-booster` bullet at `CLAUDE.md:158-159`.
  - `tasks/20260610/eglot-tooling-tasks.md:8,41-43,59,78`.
  - The harness (git keeps it; cite its SHA).
  - Live: shut down servers, `(eglot-booster-mode -1)`, `(setq eglot-booster-io-only nil)`, `(package-delete (cadr (assq 'eglot-booster package-alist)) t t)`, drop it from `package-selected-packages`, then check `git diff custom.el`.
  - Keep `~/.cargo/bin/emacs-lsp-booster`, the factual author mentions at `lisp/init-ide.el:68` and `FEATURES.md:695`, and the historical `prompts/fix-emacs-daemon-path-harvest*.md`.
  - On no: docs only, config unchanged.
- **Depends on:** P2. If P2 cannot complete, apply "Always" with "not measured" wording.
- **Check:** S2, S2b, S3. Before: S3 prints the hits listed in section A, and S2 prints `(t nil t)`. In the removal branch, also `ug -rn 'use-package eglot-booster' lisp/`: hit at `lisp/init-languages.el:345` before, none after.

### P4: One Magit timing run
- **Purpose.** Run a scratchpad script (not in the repo) using the loader at `test/magit-time-test.el:13-20`.
  - For `~/.emacs.d/`: visit 30 tracked `.el` files read-only with `diff-hl-mode` on, so `diff-hl-magit-post-refresh` has buffers to scan. Never save them.
  - For `~/`: no extra buffers.
  - For each repo: `magit-status-setup-buffer`, discard that output, then one `(let ((magit-refresh-verbose t)) (magit-refresh))`, capturing messages.
  - Record total, slowest sections, per-function times on the pre- and post-refresh hooks, and the buffer count. `magit-refresh-buffer-hook` has no per-function time (`magit-mode.el:1125`); say so in the record.
  - Any item over 200 ms (provisional) gets one ticket under `.scratch/`; it is not fixed here.
- **Depends on:** none.
- **Check:** S4. Before: no match. The raw output must contain `Refreshing magit...done` for each repo.

### P5: Close the follow-ups
- **Purpose.** Update `tasks/emacs-perf-followups.org`: mark the three TODOs DONE (or CANCELLED for io-only if the verdict rules it out), add the `Verdict:` line, the per-mode median table and repo size, and fill in the "Not measured" remark at `:34`. Offer one org-roam note on the answer to `F:102`, without writing it unasked.
- **Depends on:** P3, P4.
- **Check:** S1, S5, S6.

### Can defer
- rust-analyzer run (C4).
- `read-process-output-max` as a fourth harness mode (`F:21`, `F:104`).
- Extra profiling tracks if the user names a symptom:
  - LSP editing profile (inlay hints, flymake, eldoc).
  - Key-injected redisplay and Org profile using the `unread-command-events` method in `_doc/GOTCHAS.md`, since `emacsclient -e` never ends idle (doom-modeline, font-lock, timers).
  - Magit runs on repos the user names.
- `so-long` coverage of `text-mode`/`org-mode` (live targets exclude them, and the findings do not ask for it).
- A profiler key binding.

### Out of scope
- GC or gcmh changes (`B` and `F:86-89`: already matches, low confidence).
- Lowering `long-line-threshold` (`F:56`).
- Setting `magit-refresh-status-buffer` nil (`F:82`).
- Native comp, bidi, jit-lock, tree-sitter font-lock tuning (`F:17-26`).
- bug#69385 (`F:64`).
- Editing anything under `elpa/`, or the findings note itself.
- `early-init.el` and `lisp/init-org.el` (in-progress user edits).

## F. Validation

| Case | How | Expected |
|---|---|---|
| Normal | P2 command | `Verdict:` line and three rotation tables |
| Boundary | ERT on `booster-bench-verdict` (P1) | A win in 2 of 3 rotations does not qualify; no L action gives `inconclusive`; every input yields exactly one verdict |
| Failure | P1 smoke; result-count assertion; readiness limit | Unmanaged buffer, inactive mode, mismatched results or a server that never settles exits non-zero with no verdict |
| Regression, fresh init (the real load guard) | `emacs --batch -l ~/.emacs.d/early-init.el -l ~/.emacs.d/init.el --eval "(progn (require 'eglot) (princ (list (bound-and-true-p eglot-booster-mode) (bound-and-true-p eglot-booster-io-only) (and (advice-member-p 'eglot-booster--jsonrpc--json-read 'jsonrpc--json-read) t))))"` (**unverified, requires confirmation**: may touch `var/` state) | Before edits: `(t nil t)`. If that baseline fails, fix the command first. After P3: the S2 values |
| Regression, live | After P3 in a repo with `eglot-ensure`: `M-.` and completion work | No `Invalid JSON` warning in `*Messages*`; `jsonrpc--warn` emits this text at `jsonrpc.el:841` |

The existing ERT suites are not used as a guard: `test/python-root-test.el` and `test/libsrc-test.el` load only their own engine modules, not `lisp/init-languages.el` or `custom.el`.

No test here has been run. Test Bash calls use a 10 s timeout; the benchmark and smoke run in background.

## G. Deployment, compatibility, rollback

- **Deploy:** edit files, then apply live in the order in P3. A daemon restart is the user's choice.
- **Fresh clone:** in the removal branch, `_doc/BOOTSTRAP.md`, `README.md` and `shell/install-user.sh` no longer mention or install the booster. In the other branches nothing changes.
- **Rollback:** `git revert`. For io-only, use the P3 order with nil. For removal, `git revert` plus `M-x package-vc-install`; the binary is kept on this machine.
- **Working tree:** `early-init.el` and `lisp/init-org.el` carry unrelated user edits, and `plans/` has two untracked files. Stage with `git add <path>` per file, never `-a` or `-A`.
- **Compatibility:** the harness assumes Eglot 1.23 and jsonrpc 1.0.28 internals, and records versions in its metadata row. It is opt-in, so a later upgrade cannot break any suite.

## H. Open items and decisions

**Provisional, because the question timed out. Override at approval:**
1. Felt slowness: none assumed, no extra profiling tracks.
2. On `no-win`: recommended removal, and the implementer still stops to ask with numbers before removing.

**Provisional defaults:** thresholds in the verdict rule (25% / 5 ms / 1 ms, 100 KiB / 20 KiB); 200 ms Magit ticket line; 30 open buffers in the Magit run; gopls as the only server; benchmark repo.

**Unknowns:** benchmark duration; whether `workspace/symbol` yields a large payload on gopls; whether batch Eglot works here (P1 settles it; if it does not, stop and report instead of switching method silently); whether `diff-hl-mode` behaves normally in batch (P4 records the result either way).

**Plan review** (one fresh `plan-reviewer` pass; each finding checked against the code):

| Finding                                                                                                          | Outcome                                                                                                                |
|------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| Transient project never matches the buffer's `project-current`; `fundamental-mode` blocks `eglot-current-server` | Confirmed, fixed (P1 Connect)                                                                                          |
| Smoke check could pass with an unmanaged buffer, so "P1 settles it" was false                                    | Confirmed, fixed (`managed=t`, per-request reply check)                                                                |
| Citations `F:320` and `F:22` wrong                                                                               | Confirmed, fixed (`lisp/init-languages.el:320-321`, `F:21`)                                                            |
| "`magit-refresh-buffer` alone does not run the hooks" partly wrong                                               | Confirmed, fixed in B and P4                                                                                           |
| "Recover at runtime" also at `CLAUDE.md:159`, `FEATURES.md:673`                                                  | Confirmed, fixed (P3 Always)                                                                                           |
| Removal list incomplete                                                                                          | Confirmed, fixed. `tasks/20260610` lines added; `prompts/` deliberately kept as history                                |
| Verdict rule has no result when io-only qualifies and bytecode is better on L but fails S                        | Confirmed, fixed (first-match rule, ERT case)                                                                          |
| Readiness polled an L action that may not exist                                                                  | Confirmed, fixed (fixed `references` request)                                                                          |
| S2 had no value for `no-win` with removal declined                                                               | Confirmed, fixed                                                                                                       |
| `ug -n PAT lisp/` without `-r` is a silent no-op                                                                 | **Rejected:** run here, it printed `lisp/init-languages.el:345` and exited 0. `-r` added anyway since it costs nothing |
| Existing ERT suites do not guard the edited files                                                                | Confirmed, fixed (row removed, fresh init is the guard, baseline required)                                             |
| S4 regex false pass and false fail                                                                               | Confirmed, fixed (needs a number and `s`; "Now" confirmed no match)                                                    |
| Magit run opens no `diff-hl-mode` buffers, so it cannot answer the question                                      | Confirmed, fixed (30 buffers in P4)                                                                                    |
| S2 passes after a bare `setq`; a missing `:custom` passes too                                                    | Confirmed, fixed (advice term in S2, new S2b)                                                                          |
| S3 covered one phrase in one file                                                                                | Confirmed, fixed (three more phrases; edit range widened to `:315`)                                                    |
| S6 `--stat` does not prove byte identity, no baseline recorded                                                   | Confirmed, fixed (hash saved at start)                                                                                 |
| S1 passed on any value and no numbers                                                                            | Confirmed, fixed (value alternation, table row check)                                                                  |
| P2 had no named command                                                                                          | Confirmed, fixed                                                                                                       |
