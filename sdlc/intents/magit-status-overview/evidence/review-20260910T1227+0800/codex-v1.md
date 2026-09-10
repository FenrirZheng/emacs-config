# Codex independent review — spec v1

Reviewed: 2026-09-10, Asia/Taipei (UTC+08:00), approximately 12:29.
Source: `spec-v1.snapshot`, SHA-256 `46802f5e951552106798c768f332374caa4881a8303cc092cb43dc8590229e2a`.
Code baseline: `d65ffc852c29fdb2c0c5600074f7181b6ffc0001`; source versions/hashes in `../baseline.md`.
Coverage: entire frozen spec, accepted intent, baseline, local hints and installed Magit section/status/mode/apply source. This is a local review, separate from two Claude reviews; no Claude review result was read before this record.

## Triage

| Dimension | Disposition | Basis |
|---|---|---|
| Context and alignment | discuss | R1/R2 and D1 correctly distinguish observed folds from full buffer text; native behavior is explicitly credited |
| Architecture and design | discuss | D2/D3 scope mutation to change groups and preserve native cache; no replacement section model |
| Resilience and edge cases | discuss | R3/R5 specify multi-window point movement but leave active selection and fallback behavior incomplete |
| Operability and observability | discuss | R5/D4 provide disable path; automatic failure reporting and manual partial completion need definition |
| Security and compliance | skip | R3/R6 exclude Git writes and use disposable fixtures; no new remote/auth/data-export surface; source snapshot contains no business payload |
| Execution and milestones | discuss | R6 has distinguishing fixtures, but R3's help entry is not yet a concrete discoverable route |

## Findings

- **C1 — should-fix; R3/R5/R6; selection after point relocation.** The command relocates point after collapsing hunk bodies, but says nothing about active region/section selection. `magit-region-sections` and Magit's apply path (`magit-apply.el`, `magit-apply--get-selection`) use the active selection to choose action scope; hints explicitly use `use-region-p` (`init-git.el`, `fenrir/magit-hints--render`). Leaving mark active can make a later action operate over an unexpected range after point moves. Specify deactivating the active region when overview successfully changes visibility/position, without replacing the mark ring, and test that hints no longer claim Region. This is a requirement gap, not an observed incident. Owner: spec author.
- **C2 — should-fix; R5/D4; recoverable failure needs an observable contract.** “Do not prevent normal status” and “keep native display for unknown sections” do not settle whether initialization failures are suppressed silently or endlessly recur on redisplay, nor whether a manual command can report success after partial folding. Require bounded warning/fallback for automatic integration and a clear manual error without claiming full overview; keep original Git errors intact. Owner: spec author.
- **C3 — should-fix; R3/D4; discoverability is underspecified.** M-x is definite, but “existing help entry” plus an optional key leaves the user-visible second route and its acceptance test unresolved. The installed `magit-status-jump` (magit-status.el:394) is already reached by `j`, has no `o` suffix in the inspected definition, and is status-specific. Specify an Overview suffix there (subject to live collision handling) or choose another explicit route; do not shadow native M-2. Owner: spec author.
- **C4 — should-fix; R6; distinguish display-only command from native refresh index bookkeeping.** Follow-up source check around 12:35: `magit-status-refresh-buffer` calls `git update-index --refresh` (magit-status.el:464–466). Raw index bytes may change due to stat-cache metadata even when staged content is unchanged. Require raw index equality for the new explicit overview/redisplay path, but compare staged entries and worktree file bytes for native refresh integration tests; record native index metadata differences separately. Otherwise an unchanged, correct native refresh can fail the acceptance criterion. This does not authorize staging changes or worktree writes. Owner: spec author.

No verified blockers. Native cache restore and default file hiding claims were checked against source, not by changing live Emacs. R6 implementation checks remain unexecuted; a source review is not UI acceptance.

## Pre-mortem

1. An overview works visually, but an active region survives point movement and changes a later stage action's scope (C1).
2. An extension supplies an unfamiliar section and initialization fails silently every time the buffer opens (C2).
3. Users still fold whole groups because the new command has no obvious route from status (C3).

Snapshot retained locally at this directory's `spec-v1.snapshot`; this review does not modify the reviewed input or record user acceptance.
