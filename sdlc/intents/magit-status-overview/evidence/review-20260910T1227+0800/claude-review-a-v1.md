# Review A — spec: Magit status 檔案概況與檢閱動線

Reviewer: independent spec reviewer A (Claude Code, pane %59, model `claude-opus-5[1m]`, session `b443a9eb-88e2-4625-963c-514ecfb6f5f5`).
Task: `magit-spec-review-a` / `review-a-001`. Date: 2026-09-10 (Asia/Taipei).

## Identity of the reviewed input

| Item | Value |
|---|---|
| Frozen spec | `/home/fenrir/.emacs.d/sdlc/intents/magit-status-overview/evidence/review-20260910T1227+0800/spec-v1.snapshot` |
| Spec SHA-256 | `46802f5e951552106798c768f332374caa4881a8303cc092cb43dc8590229e2a` (recomputed locally; matches the dispatched baseline) |
| Codebase | `/home/fenrir/.emacs.d` at `d65ffc852c29fdb2c0c5600074f7181b6ffc0001` (recomputed locally with `git rev-parse HEAD`) |
| Context read | `intent.md` (accepted), `evidence/baseline.md` |
| Live spec | `sdlc/intents/magit-status-overview/spec.md` — **not read, not modified** |
| Other reviewers | not read |

Installed packages inspected (paths, not tracked artifacts): `elpa/magit-20260506.643/{magit-status.el,magit-diff.el,magit-mode.el}`, `elpa/magit-section-20260503.2051/magit-section.el`, plus `lisp/init-git.el`.

### Evidence classes used here

- **[src]** = read directly from the installed source at the paths above. All findings below are [src] unless marked otherwise.
- **[base]** = a runtime observation recorded by the coordinator in `evidence/baseline.md`. I did not re-run it.
- **[exec]** = executed by me in a live Emacs. **There is none.** I ran no `emacsclient`, no Emacs, and no Magit command; the task forbade live mutation and I did not attempt read-only runtime probes either.

Note: `evidence/baseline.md` gained a "Follow-up on the cache disagreement" section (recorded ~12:31) while this review was in progress. Findings A1/A3 below account for that follow-up and correct one of its conclusions.

## Coverage and limits

- Whole frozen spec read: R1–R6, D1–D4, Flagged concerns, Open questions (102 lines).
- All six review dimensions triaged; deeper passes on architecture / API correctness / visibility-cache lifecycle / lazy sections / compatibility & rollback, per the task focus.
- Cross-dimension pre-mortem performed (≥3 dimensions warranted discussion). Local pass, no subagents (none used, per task).
- Budget: 11 files, 21 tool calls — within the ~12 file / ~25 call bound.
- **Not checked:** any runtime behaviour, timings, screen rendering, TTY/GUI interaction, key conflicts against the live keymap, or `FEATURES.md` content. Magit `20260506.643` / magit-section `20260503.2051` only; a package upgrade invalidates every [src] claim.
- Reviewing a spec, not code: no implementation exists to test.

## Triage

| # | Dimension | Verdict | Reason (spec heading cited) |
|---|---|---|---|
| 1 | Context and alignment | discuss (brief) | Intent accepted and honest about unverified UI claims; but D1 itself concedes the native default may already satisfy R1/R2 — proportionality is the live question → A2, A11 |
| 2 | Architecture and design | **discuss (deep)** | The mechanism chosen in D3 is outranked by the native visibility cache and cannot deliver R2 → A1, A2, A5, A7, A8 |
| 3 | Resilience and edge cases | discuss | Shared-buffer/multi-window point and lazy-washed sections are real failure paths R5/D2 under-specify → A4, A5 |
| 4 | Operability and observability | discuss (brief) | Rollback is genuinely clean (verified), but the disable path does not undo folds already written to the repo-local cache → A10, A12 |
| 5 | Security and compliance | **skip** | Verified low surface: display-only change to a local Emacs config. R5 (line 43) forbids Git subprocesses in redisplay, R3 (line 29) forbids stage/unstage/discard/commit, R6 (line 57) requires index+worktree hash equality before/after. No network, no credentials, no data retention, no tenancy. Re-read those three lines before asserting this skip; nothing in D1–D4 introduces I/O beyond Magit's own. |
| 6 | Execution and milestones | discuss (brief) | R6 is a strong acceptance table but there is no sequencing, no independently deliverable increment, and case 1 is satisfiable by a no-op → A11, A13 |

## Blockers

### A1 — `magit-section-initial-visibility-alist` is outranked by the visibility cache, so D3's mechanism cannot deliver R2 [blocker]

**Spec headings:** R2 (line 19, "新建立且沒有既有可見性還原資料的 status buffer 預設使用檔案概況"), D3 (line 79, "優先使用 status buffer-local `magit-section-initial-visibility-alist` 的 lineage 規則").

**Evidence [src]** — `magit-insert-section--create`, `magit-section.el:1453-1468`, the precedence for an unbound `hidden` slot is, in order:

1. `magit-section-set-visibility-hook` (first non-nil wins),
2. the matching old section, **only when `magit-section-preserve-visibility` is nil** — and it is a `defvar-local` defaulting to `t` (`magit-section.el:337`),
3. `magit-section-initial-visibility-alist`,
4. the hardcoded HIDE argument.

The hook's default value is `(list #'magit-section-cached-visibility)` (`magit-section.el:130-131`), and that function returns the entry stored for the section ident in `magit-section-visibility-cache` (`magit-section.el:1996-2001`). Both `magit-section-show` (`:949-958`) and `magit-section-hide` (`:960-976`) end by calling `magit-section-maybe-cache-visibility`, which caches unconditionally while `magit-section-cache-visibility` is `t` (`magit-section.el:167-181`; baseline records the live value as `t` **[base]**).

**Consequence.** The alist fires only for a section ident that has *no* cache entry. In the branch where the cache is populated, the alist is dead code; in the branch where it is empty, the native defaults already produce R1's target state (see A2). D3's primary mechanism is therefore a no-op in **both** branches — the spec's central default is unimplementable as written. Corroboration **[base]**: the observed live buffer reported `:cache-size 56`.

The only construct that outranks the cache is a function pushed onto `magit-section-set-visibility-hook` ahead of `magit-section-cached-visibility` — which D3 (line 79) explicitly rules out ("不應以更高優先的 visibility hook 強迫重設手動選擇"). R2 and D3 are internally contradictory.

**Fix / question (owner: spec author).** Choose one and say so: (a) drop the initial-default requirement, make R2 purely about the explicit command, and demote the alist to "verify native default already matches, add nothing"; or (b) accept a visibility-hook entry with a precisely bounded predicate (status buffer + target lineage + first refresh of a freshly generated buffer only) and rewrite line 79, stating what it costs in overridden manual choices. Option (a) matches D1's own admission at line 69.

## Should-fix

### A2 — R1's target initial state is the native default on an empty cache; the spec does not state the actual increment [should-fix]

**Spec headings:** R1 (line 11), R2 (line 19), D1 (line 69).

**Evidence [src].** `magit-diff-insert-file-section` (`magit-diff.el:2779-2785`) passes HIDE = `(or (equal status "deleted") (derived-mode-p 'magit-status-mode))` — in `magit-status-mode` every tracked file body is created hidden. `magit-insert-unstaged-changes` (`magit-diff.el:3428-3430`) and `magit-insert-staged-changes` (`magit-diff.el:3450-3454`) create their group sections with no HIDE argument, i.e. shown. The untracked group is likewise created shown (`magit-status.el:763-772` → `magit-insert-files`).

So "groups expanded, tracked file bodies collapsed" **is** stock Magit whenever the cache is empty. D1 line 69 concedes this, but R1/R2/R6-case-1 are still written as behaviour to build, and R6 case 1 would pass against unmodified Magit.

**Fix.** State the increment explicitly in R1/R2: the deliverable is the **explicit `fenrir/magit-status-overview` command** (R2 line 21) plus its option and hints entry; the initial default is a *verification* item ("confirm native default already satisfies this; add no hook if so"), not a feature. Mark R6 case 1 as a native-behaviour control, and add a case that only the new command can pass.

### A3 — baseline's `:kill-hook-installed nil` is a false negative; kill/recreate restore is the norm, not the exception [should-fix]

**Spec heading:** R2 (line 19, "Magit 能在 buffer 被關閉後還原同 repository 的可見性快取"). Also corrects `evidence/baseline.md` §"Follow-up on the cache disagreement", which states the source/runtime difference "was not investigated".

**Evidence [src].** `magit-section.el:521-522`, inside the mode body:

```elisp
(when (fboundp 'magit-preserve-section-visibility-cache)
  (add-hook 'kill-buffer-hook #'magit-preserve-section-visibility-cache))
```

There is **no LOCAL argument**, so this registers on the *global* value of `kill-buffer-hook`. The baseline's probe was `(and (memq 'magit-preserve-section-visibility-cache kill-buffer-hook) t)` **[base]**; in a buffer that has any buffer-local `kill-buffer-hook` value, that variable evaluates to the local list, which carries the `t` marker instead of the global members — so `memq` misses a hook that `run-hooks` will nonetheless run. The negative result is an artefact of the probe, not evidence of absence.

The rest of the path is intact: `magit-preserve-section-visibility-cache` stores the cache repository-locally for status/refs buffers (`magit-mode.el:1548-1552`), `magit-generate-new-buffer` calls `magit-restore-section-visibility-cache` for **every** newly generated Magit buffer (`magit-mode.el:917`), and `magit-repository-local-cache` is a plain in-memory defvar (`magit-mode.el:1468`).

**Consequence.** R2's "沒有既有可見性還原資料" condition is essentially only *the first `magit-status` for that repository since the daemon started*. The spec's sentence at line 19 is correct; the surrounding framing (overview as the normal new-buffer default) is not. This compounds A1.

**Fix.** Re-probe with `(memq 'magit-preserve-section-visibility-cache (default-value 'kill-buffer-hook))` and record the corrected result in the baseline; then rewrite R2's freshness definition around "first status buffer for this repo in this Emacs session". Keep R6 case 4's kill/recreate check — it is now the important case, not a corner.

### A4 — R5's per-window point requirement is not met by the native API and D2 does not plan for it [should-fix]

**Spec headings:** R5 (line 39, "操作後其他視窗的 point 不可卡在新隱藏的 body"), D2 (line 75, "修正隱藏 point").

**Evidence [src].** `magit-section-hide` (`magit-section.el:960-976`) rescues point with `(when (< beg (point) end) (goto-char (oref section start)))` — that is the current buffer's point, i.e. only the selected window. It then places an overlay with `'cursor-intangible t` (`:973`), which has no effect unless `cursor-intangible-mode` is active in the buffer. Nothing in the native path touches `window-point` of the buffer's other windows.

**Consequence.** Exactly the scenario R5 forbids: run the overview from one window while a second window shows the same buffer inside a now-hidden hunk, and that window's point stays in invisible text — subsequent section commands in it act on a hidden section.

**Fix.** D2's dataflow step should read "fix point in *every* window showing the buffer" — iterate `get-buffer-window-list` and `set-window-point` after the fold pass. Add the non-selected window's point to R6 case 5's must-observe column (it currently says only "point 均在可見標題", with no statement of which window).

### A5 — lazily-washed sections mean the command does not merely "operate on existing sections" [should-fix]

**Spec headings:** R5 (line 43, "概況只操作現有 section"), R1 (line 11, "展開存在的…untracked 群組"), D3 (line 83, "lazy section 順序留給 plan").

**Evidence [src].** `magit-insert-section-body` (`magit-section.el:1590-1600`): when the enclosing section is hidden at creation time, BODY is **not** run; it is stored in the section's `washer` slot. `magit-section-show` calls `magit-section--opportunistic-wash` first (`:949`, defined `:1699-1710`), which runs the washer, inserts the body and resets the `content`/`end` markers. `magit-insert-files` — the untracked/tracked file lister — uses `magit-insert-section-body` (`magit-status.el:~804`).

**Consequence.** If the untracked group is restored hidden, its child `file` sections **do not exist** until the overview expands it; they are created at that instant and run through `magit-insert-section--create`, i.e. through the cached-visibility path of A1. Two spec statements need correcting: R5's "only operates on existing sections", and R2's "新出現且沒有原生快取狀態的檔案使用概況預設" (which now also covers files materialised by the command itself). Ordering also matters — point fixup must follow the wash, because markers move.

**Positive verification, same area:** `magit-insert-staged-changes` / `magit-insert-unstaged-changes` call `magit--insert-diff` directly with no `magit-insert-section-body` (`magit-diff.el:3430-3434`, `3454-3458`), so their diffs are generated whether folded or not. R5's "不承諾收合能避免原生 diff 生成" is **confirmed correct** — keep that sentence.

### A6 — `magit-status-file-list-limit` bounds only the file-list sections, not staged/unstaged [should-fix]

**Spec headings:** R1 (line 15), R6 case 3 (line 51).

**Evidence [src].** The limit is consumed inside `magit-insert-files` (`magit-status.el:~800-815`, `(limit magit-status-file-list-limit)` guarding the `while`, with the overflow `info` section after it), reached from `magit-insert-untracked-files` / `magit-insert-tracked-files` (`magit-status.el:748-770`). `magit-insert-staged-changes` and `magit-insert-unstaged-changes` pass no limit — their file sections come from washing the diff.

**Consequence.** R1's "沿用…`magit-status-file-list-limit`" and R6 case 3's "清單超過原生上限" read as though truncation applies to the overview as a whole. It applies to untracked/tracked listings only; a 400-file staged diff is not truncated.

**Fix.** Say which sections the limit governs; keep the "don't claim a complete inventory" rule, which remains right for the untracked list.

### A7 — two native paths can re-expand sections right after a refresh, contradicting R2's "刷新保留概況" [should-fix]

**Spec headings:** R2 (lines 19, 23), D3 (line 79, "保留其他既有條目").

**Evidence [src].**
1. `magit-section-initial-visibility-alist`'s docstring (`magit-section.el:184-206`): an entry keyed `magit-status-initial-section` "does not only override defaults, but also other entries of this alist". It is consumed by `magit-status-goto-initial-section` (`magit-status.el:492-507`), which calls `magit-section-show`/`magit-section-hide` on the initial section **after** the refresh — and, per A1, that write lands in the visibility cache.
2. `magit-status--goto-file-position` (`magit-status.el:~478-490`) ends with `(magit-section-reveal (magit-current-section))`, and `magit-section-reveal` (`magit-section.el:2139-2143`) shows every hidden ancestor. It is gated on `magit-status-goto-file-position` (`magit-status.el:118`, default nil; forced non-nil by the wrapper at `:351-357`).

**Consequence.** A user who sets `magit-status-goto-file-position`, or who has an `magit-status-initial-section` entry in the alist, gets the overview partially undone by the next refresh — and the undo is then cached.

**Fix.** Name both paths in D3 as constraints on the initial rule, and add to R6 case 5: refresh with `magit-status-goto-file-position` non-nil, and refresh with an `magit-status-initial-section` alist entry present.

### A10 — disabling the feature does not undo folds already written to the repository-local cache [should-fix]

**Spec headings:** R5 (line 41, "停用後新 buffer 使用原生初始規則，既有摺疊不被強制重設"), D4 (line 87, "可用關閉預設與撤回本庫配置回復原行為，沒有資料 migration").

**Evidence [src].** Every overview fold goes through `magit-section-show`/`hide` → `magit-section-maybe-cache-visibility` (A1) → `magit-section-visibility-cache` → preserved into `magit-repository-local-cache` on kill (A3) → restored into each new buffer (`magit-mode.el:917`). The escape hatch is `magit-zap-caches` (`magit-mode.el:1558-1566`), which clears the repository entry and nils the cache in the repo's Magit buffers.

**Consequence.** D4's rollback claim is true for *code and configuration* and false for *observed behaviour*: after disabling the option, already-created folds keep coming back for the rest of the Emacs session. On this user's setup that is a long-running shared daemon — the session is measured in days.

**Fix.** State the rollback as two steps (disable the option; `M-x magit-zap-caches` or restart to drop already-cached folds) and add it to R6 case 8's must-observe column.

**Positive verification, same dimension:** rollback is otherwise genuinely clean. `magit-repository-local-cache` is an in-memory defvar (`magit-mode.el:1468`) with no on-disk persistence, and D4's "沒有資料 migration" is correct — nothing this spec proposes writes to disk or to Git.

### A11 — R6's acceptance table has no milestones, and its first case is satisfiable by a no-op [should-fix]

**Spec headings:** R6 (lines 47-59).

**Evidence.** The table is a flat list of nine cases with no sequencing, no statement of which is independently deliverable, and no critical path. Per A2 **[src]**, case 1 (line 49: "檔名可見，tracked body 隱藏") passes against unmodified Magit on an empty cache — a no-op implementation satisfies the stated criterion, which is precisely the failure the review rubric warns about.

**Fix.** Split into at least two increments — (i) command + `user-error` + point handling + hints entry, (ii) initial-default rule *if* A1 is resolved in favour of keeping it — each with its own subset of the table. Rewrite case 1 so it can only pass with the command applied to a buffer whose cache says otherwise.

## Nits

- **A8** — Naming precision, D3 line 79. "停用 preserve-visibility" reads as a user option; the gate is `magit-section-preserve-visibility`, a `defvar-local` with no `defcustom` (`magit-section.el:337`), distinct from the *function* `magit-preserve-section-visibility-cache` (`magit-mode.el:1548`). Separately, `magit-section-cache-visibility` is both a defcustom (`:167`) and a function (`:2003`) — cite which one is meant. Baseline's table has the same conflation.
- **A9** — R4/R5 hints, line 33/39. `fenrir/magit-hints--diff-type` is computed once per refresh into a buffer-local (`lisp/init-git.el:196-198`) while `--render` runs per-window through the header-line `:eval` (`:78-79`, `:199`). R5's "各視窗 hints 仍依自身寬度與 point 顯示" holds for width and point but not for diff-type; either narrow the claim or note the exception.
- **A12** — Observability, D-section. Nothing tells a future debugger *which* precedence branch set a section's state. One sentence pointing at `magit-describe-section` (also the documented way to obtain the lineage the alist needs, `magit-section.el:193-196`) would pay for itself.
- **A13** — R6 line 57 requires "新 redisplay 路徑零 Git／檔案 I/O" but names no method. `fenrir/magit-hints--render` already runs in redisplay; suggest naming the check (e.g. instrument `magit-git-insert` / `process-file` during a forced redisplay) so the criterion is falsifiable.

## Cross-dimension pre-mortem

Assume the spec ships as written and the result is judged a failure within 90 days.

1. **"It does nothing."** The initial-default rule is implemented as D3 describes, and on the user's long-lived daemon the visibility cache wins every time (A1 + A3). The feature appears to work in a fresh fixture repo and never fires in the repos the user actually reviews. Spec needed: the precedence table from A1 written into D3, and R2's freshness condition restated per A3.
2. **"It reverted my folds and I can't get them back."** The command writes `hide` into the repository-local cache for every tracked file (A1), the user dislikes it, disables the option — and the folds persist for the rest of the session because nothing clears the cache (A10). Spec needed: the two-step rollback, and an explicit statement that the command is cache-writing and one-way (R2 line 23 already says one-way; it does not say the cache is what makes it stick).
3. **"It broke the second window."** Point in a non-selected window stays inside a newly hidden body (A4); the next `TAB` or stage command there acts on a section the user cannot see. On this setup TTY and GUI frames share the daemon and routinely show the same status buffer — R5 line 39 anticipates the risk but D2 plans only a single point fixup. Spec needed: the per-window fixup in D2 and in R6 case 5.

## Open questions for the author

| # | Question | Likely owner |
|---|---|---|
| Q1 | Given A1, is R2's initial default dropped, or is a bounded `magit-section-set-visibility-hook` entry accepted despite line 79? | spec author (codex) |
| Q2 | After A2, what is the non-native increment this spec actually buys — is it the command alone? | spec author + user |
| Q3 | Is the two-step rollback of A10 acceptable, or must the feature restore pre-overview folds (which would need a separate saved snapshot, contradicting R2 line 23's "不是可恢復舊快照的 toggle")? | user |
| Q4 | Should the corrected kill-hook probe (A3) be re-run and written back into `evidence/baseline.md` before the spec is accepted? | coordinator |

## Not verified / not covered

- No **[exec]** evidence of any kind: no Emacs was started or queried by me, so every behavioural claim above is source-derived and could be altered at runtime by other config, advice, or a package upgrade. The Magit/magit-section versions in the header are the only ones these findings apply to.
- `lisp/init-git.el` was read by grep for the hints contract only (A9); its full logic, and any key-binding conflict for R3, were not checked.
- `FEATURES.md`, `lisp/init-keys.el` and the live `spec.md` were not read.
- Rendering, timing, TTY/GUI coexistence, narrow-window hint truncation (R4) and the R6 performance criteria are untestable from source and remain open for implementation acceptance.
- This is a review of a draft spec. It is not an acceptance, and "no further findings" in the skipped dimension (security) means the cited lines were checked, not that the design is guaranteed safe.
