# Review A — delta review of spec v2

Reviewer A (Claude Code, pane %59, `claude-opus-5[1m]`, session `b443a9eb-88e2-4625-963c-514ecfb6f5f5`).
Task `magit-spec-review-a-delta` / `review-a-delta-001`. Written 2026-09-10T04:43Z (UTC from `date -u`).

| Item | Value |
|---|---|
| v2 snapshot | `evidence/review-20260910T1227+0800/spec-v2.snapshot`, SHA-256 `fa7efffcfd8733f987f66a18127ffc7a144549f2c24dee9ddea9cdd167b67421` (recomputed locally; matches dispatch) |
| Diff read | `evidence/review-20260910T1227+0800/v1-v2.diff` (113 lines, all hunks) |
| Prior review | my `/tmp/magit-spec-peers/review-a.md` (`4b3ef643…5752`) |
| Codebase | `d65ffc85…0001`; magit `20260506.643`, magit-section `20260503.2051` |

Other reviewers: not read. **[src]** = installed source; **[exec]** = none — no Emacs or `emacsclient` was run.

## Correction to my v1 review

**A2 was wrong, and the coordinator is right.** `magit-insert-files` creates its group with `(magit-insert-section section ((eval type) nil t)` — HIDE=**t** (`magit-status.el:793`, section form at `:796`) **[src]**. I asserted the untracked group was created shown without reading that argument. The untracked initial-show rule therefore has real effect, and my "native default already matches R1 uniformly" claim is refuted for untracked. It stands only for staged/unstaged (`magit-diff.el:3430`, `:3454`, no HIDE) and tracked file bodies (`magit-diff.el:2779-2785`) — which is exactly how v2's D1 now states it. D1's two citations are accurate.

**A1 is refuted as a blocker.** My claim was "the alist is a no-op in both branches". Branch (b) is false given HIDE=t above, so the alist genuinely flips untracked to show when no cache entry exists. Branch (a) — cache outranks the alist (`magit-section.el:1455-1468`, hook member `magit-section-cached-visibility` at `:130`, `:1996-2001`) — is still true as *mechanism*, but v2 R2/D3 now make that the intended contract ("Cache 優先於新預設正是 R2 的要求"), so it is a design decision, not a defect. No cache override is warranted.

## Prior-finding status

| ID | v1 severity | Status | Basis in v2 |
|---|---|---|---|
| A1 | blocker | **refuted** | R2 ¶2-3, D3 ¶1 — cache priority is the stated contract; untracked rule has effect (see correction) |
| A2 | should-fix | **refuted** | D1 ¶2 now distinguishes the three native defaults correctly; R6 rows 1-2 add anti-no-op controls |
| A3 | should-fix | **resolved** | R2 ¶3 states preserve-visibility semantics exactly as `magit-section.el:1460` does, including the `nil` → old-section branch and no kill/recreate promise; coordinator re-probe supersedes the baseline false negative |
| A4 | should-fix | **resolved** | D2 ¶2 (`get-buffer-window-list` across all frames, `set-window-point`), R3 ¶2 (only windows hidden by the overview move), R6 row 6 (selected **and** non-selected window-point) |
| A5 | should-fix | **resolved** | R5 ¶3 permits native washer/paint and materialization of not-yet-created children while forbidding extra Git scans; R6 last row tests wash/paint counts and re-materialization |
| A6 | should-fix | **resolved** | R1 new ¶ scopes `magit-status-file-list-limit` to `magit-insert-files` lists; R6 row 4 uses >100 untracked and a >100 staged control. Limit default verified = 100 (`magit-status.el:184`) **[src]** |
| A7 | should-fix | **resolved** | R2 ¶3 names `magit-status-initial-section`, `magit-status-goto-file-position` and explicit reveal as native-priority, separated from plain `g`; R6 row 5 tests them |
| A8 | nit | **resolved** | D3 ¶1 now says "只有 `magit-section-preserve-visibility` 為 nil 時"; D4 says "不改 `magit-section-cache-visibility` 變數", disambiguating variable from function |
| A9 | nit | **still open** | R4 ¶2 adds the `j`/transient rules but says nothing about `fenrir/magit-hints--diff-type` being a per-refresh buffer-local while `--render` runs per-window (`lisp/init-git.el:196-199`). R5 ¶1's "各視窗 hints 依自身寬度與 point" still overstates for diff-type |
| A10 | should-fix | **resolved** | R5 ¶2 and D4 ¶1: disable stops new intervention, does not clear the cache; `M-x magit-zap-caches` named as the explicit user step |
| A11 | should-fix | **resolved (residual)** | R6's new 驗證順序 ¶ gives an ordered validation path and the anti-no-op controls fix the satisfiable-by-no-op case. File-level sequencing is explicitly deferred to plan — acceptable for a spec, but no increment is yet declared independently shippable |
| A12 | nit | **resolved** | D4 ¶1 adds `magit-describe-section` and tells the reader to separate alist / cache / navigation effects |
| A13 | nit | **resolved** | R6 last two rows require process/file I/O counters under forced redisplay rather than screen-string checks |

## Six-dimension triage (delta)

1. **Context/alignment** — skip. D1 ¶2 now states the increment concretely (untracked initial show, scoped command, window/selection fixes); the proportionality doubt behind A2/A11 is answered.
2. **Architecture/design** — discuss (one item, A14). Changed contracts R2/D3/D2 verified against source; no defect found beyond the alist-timing question below.
3. **Resilience/edge cases** — skip. R5 ¶4 is new and good: per-buffer one-shot `*Warnings*` summary, no redisplay retry, explicit "概況未完成" on mid-command failure with no transactional-UI promise, and it does not swallow Magit's own Git errors. R6 row 10 injects those failures.
4. **Operability/observability** — skip. A10/A12/A13 resolved; the raw-index vs `update-index --refresh` stat distinction in R6's I/O row is the right bookkeeping and matches how a plain `g` behaves.
5. **Security/compliance** — skip, unchanged. Still display-only, no I/O beyond Magit's own; R6 keeps the `git ls-files --stage -z` + worktree content equality check.
6. **Execution/milestones** — skip (A11 residual noted above).

## New findings against changed text

### A14 — the alist entry must exist before the first section insertion; v2 does not say where it is installed [should-fix]

**Heading:** R2 ¶2 (`fenrir/magit-status-overview-default`), D3 ¶1.

**[src]** `magit-insert-section--create` consults `magit-section-initial-visibility-alist` *at section creation time* (`magit-section.el:1465-1467`). A buffer-local entry added after the buffer's first refresh has already inserted the untracked group therefore has no effect until the next refresh — and by then `magit-section-show`/`hide` may have cached a value that outranks it (`:949-958`, `:960-976`).

**Consequence.** "新 status buffer 預設" silently degrades to "second refresh onward" if the buffer-local lands on the wrong hook. **Fix:** name the installation point in D3, and require in R6 row 1 that untracked is shown on the buffer's *first* display, not after a `g`.

### A15 — sibling `magit-insert-files` groups also default to HIDE=t; say the rule does not widen [nit]

`magit-insert-files` serves `tracked`, `ignored`, `skip-worktree` and `assume-unchanged` as well as `untracked` (`magit-status.el:775-793`) **[src]**, all with HIDE=t. D3 mentions tracked; naming the other three (as deliberately left hidden) removes any temptation to key the lineage rule on the file-list shape rather than the `untracked` type.

### A16 — `j o` placement inside `magit-status-jump` [nit]

**[src]** `magit-status-jump` (`magit-status.el:394-411`) has suffixes `z t n i u s / fu fp pu pp a w / j`; **no `o`** — v2 R3's claim is confirmed, and `j` → `magit-status-jump` is bound at `:391`. Every existing suffix is a section *jumper*; Overview also mutates visibility. One sentence in R3/D4 on which column it joins and a label that makes the fold effect obvious would stop `j o` reading as a pure jump.

## Verified-correct in v2 (no action)

- R5 ¶3's "不另行呼叫 Git 掃描" is already guaranteed by source: `magit-insert-files` binds `files` from the Git call *outside* `magit-insert-section-body` (`magit-status.el:794-796`) **[src]**, so materializing a hidden untracked body inserts text without a new subprocess.
- The untracked heading count uses the full `(length files)` before truncation (`:797`), consistent with R1's "不宣稱完整清冊" plus a visible `(info)` notice.
- R5's "staged／unstaged 生成 diff 的成本不因此消失" remains correct (`magit-diff.el:3430-3434`, `:3454-3458`).

## Limitations

No **[exec]** evidence: no Emacs started, no Magit command run, no keymap/transient probed at runtime — A14 and A16 are source-derived predictions. Budget used: 4 source files (`magit-status.el`, `magit-section.el`, `magit-diff.el` re-checks, `lisp/init-git.el` from v1), 11 tool calls total including mailbox and hashing. Not re-checked: `FEATURES.md`, `lisp/init-keys.el`, live `spec.md`, other reviewers' output. Findings hold only for the two package versions named above. This is a spec review; no implementation exists and none was expected to be tested.
