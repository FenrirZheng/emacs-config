# Spec discussion and review record

Date: 2026-09-10, Asia/Taipei (UTC+08:00).
Repository/source baseline: `/home/fenrir/.emacs.d`, `d65ffc852c29fdb2c0c5600074f7181b6ffc0001`.
Scope: execute `sdlc next magit-status-overview`; discuss with one existing Claude Code peer, then obtain two independent Claude reviews and a Codex review; deliver a draft spec, not an implementation or human acceptance.

Current review stage: one discussion, two independent full reviews, two peer delta reviews and Codex final delta review complete. No verified spec blocker remains. The spec remains a draft for the user's acceptance.

## Inputs, outputs, and ownership

- Accepted input: [intent.md](../intent.md).
- Proposed output: [spec.md](../spec.md), still `Status: draft`.
- Runtime/source evidence and limits: [baseline.md](baseline.md).
- Exact local review inputs and raw reports: [review context](review-20260910T1227+0800/context.md).
- v1 snapshot SHA-256: `46802f5e951552106798c768f332374caa4881a8303cc092cb43dc8590229e2a`.
- v2 snapshot SHA-256: `fa7efffcfd8733f987f66a18127ffc7a144549f2c24dee9ddea9cdd167b67421`.
- Final spec SHA-256: `1e99f95ae2bbf5b391863aad72efc9e88c7b4de9f24c46981107676dd91d7e92`.

Codex owns the spec and consolidation. All peers were read-only on the repository, wrote only distinct result files under `/tmp/magit-spec-peers`, and were forbidden from staging, committing, editing live Emacs, or spawning agents. Each independently self-enrolled, ACKed the exact task, and reported running/done using the same peer-task helper/store. No sender-authored ACK is used.

| Peer | Pane | Role | Initial completion evidence |
|---|---|---|---|
| Claude discuss | `%60` | Design discussion with Codex; acknowledged two follow-ups | `discuss-001`, updates `discuss-update-002/003`, done event seq 20; artifact SHA `21bcb1b17f6f97eb98a865dad298f9ffa1fad8463dda5bb7a028a053d1eb24bf` |
| Claude review A | `%59` | Independent full v1 review, architecture/cache/API emphasis | `review-a-001`, done seq 21; artifact SHA `4b3ef643928d331eede9be0849b8c4274713cb3ea58ff7ed326c1b80cc205752` |
| Claude review B | `%56` | Independent full v1 review, requirements/acceptance/UI emphasis | `review-b-001`, done seq 22; artifact SHA `f5a97a5b3a81efd3d5311e82c012a6ca8985c34c04039be26c8486576f088bab` |
| Codex | `%57` | Independent local v1 review, source checks, author dispositions and v2 delta | [codex-v1.md](review-20260910T1227+0800/codex-v1.md); C1–C4 below |

All copied peer artifacts were hashed and matched their receiver-authored handoffs. Reviewer B's self-entered check timestamps extend past the helper's done receipt; those times are not treated as authoritative. Helper event time and local artifact digest verification establish receipt/content; the reviews do not prove runtime behavior. Raw peer statements remain historical claims, subject to the dispositions below.

## Discussion decisions

Adopted: tracked file bodies and group counts are native; avoid a new statistics subsystem; keep a one-way command; use native section APIs; visibility belongs to the buffer, not independently to each window; honor untracked filters and list-limit disclosure.

Rejected after discussion: a cache-preserving M-2 wrapper would revert the overview on ordinary refresh, and a global M-2 traversal alters non-target groups. Explicit overview is a new cached fold choice and is limited to staged/unstaged/untracked. The peer acknowledged both corrections in its addendum.

Not adopted: the discussion's claim that no status-capable kill-hook registration exists omitted `magit-section.el:521–522`. Reviewer A identified global-hook inheritance; Codex confirmed it at runtime (baseline). Leaving an already-folded untracked group untouched also fails the chosen overview, so native lazy materialization is explicitly allowed. The discussion's partial synthetic probe is not used to claim UI validation or feature completion.

## Six-dimension consolidation

| Dimension | Coverage and result |
|---|---|
| Context/alignment | All three reviewers; spec now distinguishes native controls, the required untracked default, and the scoped command |
| Architecture/design | All three; native cache priority is intentional, APIs and all-window point ownership are explicit |
| Resilience/edge cases | All three; active selection, unknown/lazy sections, partial failure, explicit navigation and custom initial rules are specified |
| Operability/observability | Codex and A discussed, B skipped with reasons; one warning/fallback, cached rollback semantics, diagnostics and I/O measurements added |
| Security/compliance | All three skipped broader security analysis after checking the local display-only boundary; C4 distinguishes native index bookkeeping from staging changes |
| Execution/milestones | All three; distinguishing initial/untracked and cached-command cases, scoped over-limit fixture, ordered acceptance groups and later plan boundary recorded |

No UI execution, timing, screenshot comparison or implementation acceptance was performed by the reviewers. The native fixture and TTY/GUI criteria remain obligations of the later build/verification stage, not missing evidence of an already-implemented feature.

## Finding dispositions against v2

| Finding | Disposition and evidence |
|---|---|
| A1 (reported blocker) | Refuted as a contradiction: R2 expressly applies initial rules only without prior cache/old state; existing cached choices must win. `magit-insert-section--create` supports this. The alist has a real uncached effect for untracked, whose native HIDE is t; no need to override the cache. D3 now states the precise increment. |
| A2 / B2 | Corrected the untracked asymmetry. B2's source observation is adopted; A2's assertion that untracked is natively shown is false at `magit-insert-files`. R2/D1/D3 require untracked show on the normal fresh path; tracked hiding remains a native control. |
| A3 | Resolved by the global-hook runtime re-probe documented in baseline; source/runtime mismatch was an incomplete hook query. |
| A4 / B-S4 | D2 explicitly owns all-frame `get-buffer-window-list` and `set-window-point` after lazy materialization; R6 distinguishes selected/non-selected windows. |
| A5 / B-S3 | R5 permits native washer/paint to create children; R6 records wash/paint counts, separate command/refresh timing and subprocess evidence. The lazy example is untracked; normal staged/unstaged diff bodies are generated eagerly. |
| A6 / B-S2 | R1/R6 distinguish file-list limits from diff groups; >100 flat untracked entries and a separate >100 staged control prevent vacuous truncation checks. |
| A7 | Clarified the triggering paths. Initial section handling/reveal can change folds during creation or explicit status entry; they are not unconditional behavior of plain g. R2/D3/R6 preserve native navigation preferences and test them separately. |
| A8 / B-S5 | Exact `magit-section-preserve-visibility` variable named; nil follows the native old-section branch and does not gain custom persistence. `magit-section-cache-visibility` variable distinguished from its function. |
| A9 | No status diff-type defect: `fenrir/magit-hints--render` branches on status and walks that window's section ancestry; the cached diff-type path is for other modes. No change to that existing code is needed. |
| A10 | R5/D4 distinguish stopping new integration from clearing original Magit cache; optional user-directed magit-zap-caches/restart documented, no automatic reset or invented restoration of prior folds. |
| A11 / B-S1 / B-N3 | R6 includes a folded-group/expanded-child command case that fails on no-op, a distinct untracked default control, and verification ordering. File-level implementation milestones remain the next plan's responsibility. |
| A12 / A13 | D4 names magit-describe-section; R6 names hints rendering, temporary I/O counters, wash/paint measurements and forced redisplay. |
| B1 / C3 | R3/D4 specify j o in the existing status-jump transient, live collision handling and M-x fallback. R4 advertises the actual j menu command, not a nonexistent direct o binding. |
| B-N1 / B-N2 | Retain existing whole-item priority/fallback and native XML-independent hiding. Plan must place any optional j reminder without displacing the primary action; no separate XML special case. |
| C1 | R3/R6 explicitly deactivate active region/section selection after successful overview, keep mark ring, and test hint scope; empty/non-status paths remain unchanged. |
| C2 | R5/R6 define bounded automatic warning/fallback and manual “overview incomplete” error with partial visibility allowed; native Git errors are not swallowed. |
| C4 | R6 uses raw index equality for the new display-only command, but staged-entry and worktree equality for native g, whose update-index --refresh may update stat metadata. No staging/worktree content mutation is authorized. |

## Independent delta reviews and final author review

Both delta reviewers read the frozen v2 snapshot and their own prior findings; neither read the other reviewer's output. Their output hashes matched the receiver-authored completion handoffs:

| Delta | Completion | Artifact SHA-256 |
|---|---|---|
| Review A | `review-a-delta-001`, done seq 32 | `eb20ae0be88b3b0171ffd50b3f9a78b62e82a3c6c7a7882f83bfe51d11743bfc` |
| Review B | `review-b-delta-001`, done seq 31 | `6d422274b73831d72175a38e0bc6dd58e75c7a90ddbeb528e864d0706f1075bd` |

A withdrew its original A1 blocker and incorrect uniform-default assertion. B marked both original blockers resolved. The final changes after v2 are recorded in `review-20260910T1227+0800/v2-final.diff` and were reviewed locally by Codex, not re-attributed to the peers:

| Residual/new item | Final disposition |
|---|---|
| A14, initial rule timing | Resolved. D3 fixes installation at guarded magit-create-buffer-hook before first refresh, with magit-status-mode-hook restoring previously recorded per-buffer policy on mode reentry; R6 requires first-display success and reentry continuity. Source: magit-setup-buffer-internal at magit-mode.el:664–697 calls mode, create hook for new buffers, then refresh. A late post-create/refresh installation is excluded. |
| A15, sibling file-list types | Resolved. D3 explicitly excludes tracked/ignored/skip-worktree/assume-unchanged initial rules. |
| A16, entry reads as a pure jump | Resolved. R3 puts `Overview (fold diffs)` in a View column of the existing jump transient. |
| A9 repeated diff-type nit | Refuted by full source check at init-git.el:146–157: status uses per-window section ancestry; only the other branch uses the cached diff-type. R4 now states this distinction. |
| B-N1, narrow-window item priority | Resolved. R4 appends the optional j reminder after existing context actions and preserves the original first action and Help priority. |
| B-D1, alleged refs-only preservation hook | Refuted. The new claim again omits magit-section-mode's hook registration at magit-section.el:521–522, inherited by magit-mode (magit-mode.el:559) and magit-status-mode (magit-status.el:413). Baseline's corrected runtime query confirms the global hook is inherited. No requirement to open a refs buffer first is added. Kill/recreate remains an implementation test, not a completed execution claim. |
| B-D2, breadth of magit-zap-caches | Resolved. D4 names repository-local, host Git-version and blob cache effects, and keeps this a user-directed optional action. |
| A11 residual, implementation increments | Deferred to plan by stage, not an unresolved spec blocker. R6 supplies verification ordering; the current authorized SDLC stage is a draft spec, not an implementation plan. |

Final six-dimension delta: context/security boundaries unchanged from reviewed v2; architecture and lifecycle checked against the setup call order; resilience reviewed for shared points, selection and partial failure; operability reviewed for hint priority and explicit cache-clearing breadth; execution reviewed for first-display and reentry controls. No substantive issue remains without a defined requirement or disposition. Future implementation must still meet R6.

## Validation and limits

The final file was compared byte-for-byte with `spec-final.snapshot`; required headers, draft status, four SDLC sections and local artifact links were checked. Source hashes still identify the installed packages used in this review. Repository pre-commit checks are run at the draft-spec commit and reported separately in the delivery result.

These checks prove document integrity and review provenance, not a working UI. No spec acceptance, plan approval, implementation, deployment or push was performed. Exact snapshots, diffs and receiver reports are intentionally retained with this SDLC deliverable to satisfy the project's artifact-preservation instruction; the reviews themselves did not stage or commit them.
