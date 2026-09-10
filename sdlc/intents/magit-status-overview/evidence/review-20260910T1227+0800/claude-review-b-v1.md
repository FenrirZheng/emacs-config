# Independent spec review B — magit-status-overview

Reviewer: `review-b` (Claude Code, session `f74f5bb8-6e93-4c7a-b76a-4834792e43a1`, model `claude-opus-5[1m]`)
Task: `magit-spec-review-b` / message `review-b-001`, generation `2e7009c5cdac4d5a888887194ad523ae`
Produced: 2026-09-10 (Asia/Taipei)

## Input identity

| item | value |
|---|---|
| Reviewed spec (frozen) | `/home/fenrir/.emacs.d/sdlc/intents/magit-status-overview/evidence/review-20260910T1227+0800/spec-v1.snapshot` |
| Snapshot SHA-256 | `46802f5e951552106798c768f332374caa4881a8303cc092cb43dc8590229e2a` (recomputed locally; matches dispatch) |
| Source revision | `d65ffc852c29fdb2c0c5600074f7181b6ffc0001` (`git rev-parse HEAD`; matches dispatch) |
| Context read | `intent.md` (accepted), `evidence/baseline.md` |
| Live `spec.md` | not modified, not used as the review input |
| Rubric | `/home/fenrir/.agents/skills/review-plan/SKILL.md` + `references/review-dimensions.md`, `references/reviewer-protocol.md` |

## Evidence classes

All findings below are **source-derived** (reading the installed Elisp and this repo's Elisp at the pinned revision) or **document-derived** (spec/intent/baseline text). **No executed evidence**: I started no Emacs, evaluated no Elisp, drove no `emacsclient`, and made no measurement. Where a finding would be settled by an interactive check I say so. Package hashes in `evidence/baseline.md` for `lisp/init-git.el` were re-verified (`8eb0cd8930…cc48b`, matches); the magit package hashes were not recomputed.

## Checks performed

Source (installed `magit-20260506.643`, `magit-section-20260503.2051`):

- `magit-insert-section--create` visibility precedence — `magit-section.el:1441-1468`
- `magit-section-set-visibility-hook` default `(magit-section-cached-visibility)` — `magit-section.el:130-131`
- `magit-section-preserve-visibility` (defvar-local, default `t`) — `magit-section.el:337`; `magit-section-cached-visibility` — `:1996-2001`
- `magit-section-cache-visibility` (defcustom, default `t`) — `:167`; cache writes only from `magit-section-show` `:954` and `magit-section-hide` `:976`
- `magit-section-initial-visibility-alist` default `((stashes . hide))` — `:184`
- `magit-insert-section` macro HIDE semantics — `:1370-1400`
- `magit-diff-insert-file-section` hide argument — `magit-diff.el:2779-2782`
- `magit-insert-unstaged-changes` / `magit-insert-staged-changes` group sections — `magit-diff.el:3428-3430`, `3450-3454`
- `magit-insert-files` group HIDE and truncation notice — `magit-status.el:~795-815`; callers `:771,776,781,786,791`
- `magit-status-file-list-limit` (default 100) — `magit-status.el:184`, sole use `:805`
- `magit-status-show-untracked-files` `:147`, `magit-status-initial-section` `:91-112`, `magit-status-sections-hook` `:69-85`
- `magit-preserve-section-visibility-cache` / `magit-restore-section-visibility-cache` — `magit-mode.el:1548-1557`

This repo:

- `lisp/init-git.el:96-105` (`fenrir/magit-hints--item`), `:107-138` (`--layout`), `:140-199` (`--render`, `--install`), `:201-217` (mode)
- `FEATURES.md:871-894` (Git section, hints paragraph)

Every symbol the spec names exists in the installed versions — `magit-status-show-untracked-files`, `magit-status-file-list-limit`, `magit-status-initial-section`, `magit-section-initial-visibility-alist`, `magit-section-cache-visibility`, `magit-insert-section--create`, `magit-section-show-level-2-all`, `magit-preserve-section-visibility-cache`, `magit-restore-section-visibility-cache`. No invented API.

## Triage

| # | Dimension | Verdict | Reason (spec heading cited) |
|---|---|---|---|
| 1 | Context and alignment | **discuss** | R1/R2 state a uniform native baseline that the source contradicts for one of the three groups; D1 "若既有預設已滿足 R2，保留原生即可" makes the delta between native and feature the load-bearing question. → B2, S1 |
| 2 | Architecture and design | **discuss** | D3 mechanism is sound but names the wrong gate variable; D2's data flow "修正隱藏 point" is written in the singular while R5 imposes a multi-window obligation. → S4, S5 |
| 3 | Resilience and edge cases | **discuss** | R6 case 3 rests on a native limit whose scope the spec never pins; unknown-section and non-status paths are otherwise well covered. → S2 |
| 4 | Operability and observability | **skip** | Verified low surface: no service, metrics, or rollout. Reversibility is stated concretely (R5 "提供可關閉概況預設的使用者選項"; D4 "可用關閉預設與撤回本庫配置回復原行為，沒有資料 migration") and reload-idempotence is an explicit acceptance row (R6 row 8 "沒有重複 hook/advice"). D2 confirms no database, background service, index write, or persisted summary. Nothing material left unaddressed. |
| 5 | Security and compliance | **skip** | Verified low surface: single-user local Emacs config, no identity, tenancy, network, or retention surface. Data-handling obligations are named and bounded — intent.md Constraints "不將完整業務 diff 或原始測試資料複製進 Emacs 設定庫", R3 "命令不會 stage、unstage、discard、commit 或修改被檢閱 repository", R6 row 9 "index 與工作樹內容雜湊相同". `evidence/baseline.md` demonstrably follows this (hashes and section metadata only, no business file contents). |
| 6 | Execution and milestones | **discuss** | R6 row 1 — the spec's headline acceptance case — is satisfiable by a no-op for the tracked groups; the command's own cost has no observable. → S1, S3 |

Three or more dimensions warrant discussion, so a cross-dimension pre-mortem pass is included below.

## Blockers

### B1 — R3's optional binding makes R3's own discoverability requirement unreachable  *(dimension 1/2, source-derived, confirmed)*

**Spec headings:** R3 — 入口與定位; R4 — 資訊與 hints 正確性.

R3 requires both `M-x fenrir/magit-status-overview` **and** "在 status 的既有說明入口可找到", while making the key binding conditional ("若配置按鍵，必須先核對實際 keymap…"). R4 requires the entry point ride on the existing hints mode and that "Hints 只顯示目前 key-binding 真正呼叫的命令".

Source: `lisp/init-git.el:96-98`

```elisp
(defun fenrir/magit-hints--item (entry)
  "Format ENTRY only if its key actually invokes its command at point."
  (when (eq (key-binding (kbd (car entry))) (nth 2 entry))
```

An entry whose command has no live binding returns `nil` and is dropped from the toolbar entirely. So **with no binding, the hints toolbar cannot advertise the command at all** — R4's own correctness rule forbids it. The only other native "說明入口" in the status buffer is `?` → `magit-dispatch` (`init-git.el:187` uses it as the help item), an upstream transient. Adding a suffix there is nowhere in D2's ownership list ("所有概況選項、status 專用初始化、命令與 hints 整合歸 `lisp/init-git.el`") or D4's integration note ("概況入口整合目前 hints／說明流程").

**Consequence:** at plan time the implementer must either silently expand scope to patch an upstream transient, or ship an M-x-only command that fails R3 as written. Either is rework attributable to the spec.

**Fix / question (owner: spec author, then user for the binding decision):** pick one and say so in R3 — (a) the binding is **mandatory**, and R3's keymap-conflict check becomes a blocking plan item; (b) a `magit-dispatch` suffix is explicitly in scope, and D2 gains that ownership line; or (c) drop "既有說明入口" and let discoverability be `M-x` + `FEATURES.md`, which R3 already requires syncing.

### B2 — "展開三個群組" assumes a uniform native default that the source does not provide for `untracked`  *(dimension 1, source-derived, confirmed from source; one interactive check would close it)*

**Spec headings:** R1 — 可辨識的檔案概況; R2 — 初始預設與手動選擇; D1 — 已知基準與資料來源; R6 row 1.

R1 requires "展開存在的 staged、unstaged、untracked 群組". D1 then argues the increment may be near-zero ("status 的 tracked file body 原生即預設 hide…若既有預設已滿足 R2，保留原生即可，不為重複效果增加 hook"). The three groups do **not** share a hardcoded default:

- staged / unstaged groups — `magit-diff.el:3430` `(magit-insert-section (unstaged)` and `:3454` `(magit-insert-section (staged)`: HIDE omitted → **expanded** by default.
- tracked file bodies — `magit-diff.el:2781-2782`: HIDE is `(or (equal status "deleted") (derived-mode-p 'magit-status-mode))` → **hidden** in status mode, with no size or extension condition.
- untracked group — `magit-status.el` `magit-insert-files`: `(magit-insert-section section ((eval type) nil t)` → HIDE is **`t`** → **collapsed** by default. Macro arg order confirmed at `magit-section.el:1370-1400` ("When optional HIDE is non-nil collapse the section body by default").

So for a status buffer with no cached visibility, stock Magit yields exactly R1's target state for staged/unstaged — and the opposite for untracked: the untracked file heading is inside a collapsed body and is not visible. D1's "保留原生即可" therefore breaks R1, breaks R6 row 1's fixture ("1 untracked…檔名可見"), and breaks the accepted intent's hard constraint ("不得隱藏 untracked section", intent.md Constraints).

The spec never states this asymmetry, and it never reconciles it with `evidence/baseline.md` ("Untracked group: `hidden=nil`") — an observation fully explained by the cached-visibility hook (`magit-section.el:130-131`, `:1996-2001`) overriding the hardcoded `t`, i.e. a *cached* state, not the native default. Baseline itself concedes the cause was not established, and D1 repeats that ("現有群組為何收合未經查證").

**Consequence:** an implementation that follows D1's "keep native" advice ships with untracked collapsed on every fresh-cache buffer, violating an accepted constraint.

**Fix (owner: spec author):** state the per-group native defaults explicitly in D1/D3, and make the initial rule's `untracked → show` entry a required part of R2 rather than something D1 permits omitting. **Settling check:** open a status buffer in a fixture repo with `magit-section-visibility-cache` empty (fresh repo-local cache) and read the untracked group's `hidden` slot. I did not run it.

## Should-fix

### S1 — R6 row 1 cannot distinguish the feature from a no-op  *(dimension 6, source-derived, confirmed)*

**Spec heading:** R6 — 驗收邊界, row 1 ("無既有可見性快取的新 buffer：1 untracked、1 unstaged、10 staged…檔名可見，tracked body 隱藏…這個案例可區分整組收合、全部展開與正確概況").

The row is right that it separates *all-collapsed* / *all-expanded* / *overview*. It does not separate *overview implemented* from *stock Magit*: for the tracked groups, `magit-diff.el:3430/3454` (groups shown) plus `:2782` (bodies hidden) already produce the asserted observation with zero new code. Only the untracked half of the row has real discriminating power, and per **B2** that half currently fails. The review-dimensions §6 prompt — "Could a no-op implementation satisfy a proposed criterion?" — is triggered squarely here.

**Fix:** split the row. Keep the fresh-cache case as a documented *baseline* assertion labelled as native behaviour, and add a case that starts from the state `evidence/baseline.md` actually recorded (staged and unstaged groups `hidden=t`, all ten headings invisible) and asserts the explicit command restores file-level visibility. That second case is the one that fails on a no-op.

### S2 — R6 row 3's "清單超過原生上限" applies to a narrower set of sections than R1 implies  *(dimension 3, source-derived, confirmed)*

**Spec headings:** R1 ("呈現範圍沿用…`magit-status-file-list-limit`…達清單上限時保留原生未列出數量／提示"); R6 row 3.

`magit-status-file-list-limit` (default 100, `magit-status.el:184`) is read in exactly one place — `magit-status.el:805`, inside `magit-insert-files` — whose callers are `untracked` `:771`, `tracked` `:776`, `ignored` `:781`, `skip-worktree` `:786`, `assume-unchanged` `:791`. Staged and unstaged are diff sections (`magit-diff.el:3428/3450`) and are **not** subject to it. The truncation notice R1 relies on does exist, but only on that path:

```elisp
(when files
  (magit-insert-section (info)
    (insert (propertize (format "%s files not listed\n" (length files)) 'face 'warning))))
```

**Consequence:** a fixture built with, say, 150 staged files produces no truncation notice, and R6 row 3 passes vacuously while asserting "原生排除及截斷提示保留".

**Fix:** name the section the truncation fixture must use (>100 untracked files is the natural one, and it interacts with R1's default-on untracked display), and state that staged/unstaged carry no file-count limit. Secondary: the notice is an `(info)` child *inside* the untracked group, so the overview command's child walk will meet a non-`file` section there — worth naming as a concrete instance of R5's "遇無法辨識的 section，保留原生顯示".

### S3 — the explicit command's own cost has no observable; R6 row 9 measures only the redisplay path  *(dimension 6, source-derived, confirmed)*

**Spec headings:** R5 — 共用 daemon、失敗與停用 ("Redisplay 不執行 Git subprocess…與 Magit 原生延遲展開有關的計算成本要明示"); R6 row 9 ("新 redisplay 路徑零 Git／檔案 I/O；記錄概況、原生刷新各自耗時").

Two gaps. First, "新 redisplay 路徑" is close to vacuous: per D2/D3 the feature adds an initial-visibility rule and a command, not a redisplay path — the only `:eval` header path is the pre-existing `fenrir/magit-hints--render` (`init-git.el:140`, `:78-79`). Second, the cost R5 says must be "明示" lives in the command, not redisplay: `magit-section-show` calls `magit-section--opportunistic-wash` and `--opportunistic-paint` (`magit-section.el:948-949`) before recursing into children, so expanding a previously-collapsed staged group can force washing that a pure visibility flip would not. R5 correctly refuses to promise otherwise ("不承諾收合能避免原生 diff 生成"), but R6 never asks anyone to observe it.

**Fix:** in R6 row 9, keep the redisplay assertion but attach it to the existing hints path by name, and add an observable for the command run against a repo whose groups are collapsed with unwashed bodies (elapsed time and whether washing occurred), on the same fixture as the native-refresh comparison the row already requires.

### S4 — R5's multi-window point guarantee has no owner in the design  *(dimension 2, source-derived, confirmed)*

**Spec headings:** R5 ("操作後其他視窗的 point 不可卡在新隱藏的 body；需回到對應檔案／群組的可見標題"); D2 資料流 ("修正隱藏 point"); Flagged concerns #2.

`magit-section-hide` repairs point for the current buffer position only — `magit-section.el:966-969`:

```elisp
(when-let ((beg (oref section content)))
  (let ((end (oref section end)))
    (when (< beg (point) end)
      (goto-char (oref section start)))
```

`(point)` is the buffer's point, i.e. the selected window's. Other windows displaying the same buffer keep their own `window-point`, which magit does not touch; those land inside the new `invisible` + `cursor-intangible` overlay created two lines below. R5 therefore imposes an obligation that native Magit does not discharge, while D2's data-flow line describes point repair in the singular and D3 defers it ("point 調整…留給 plan"). The spec's Flagged concerns #2 raises the *right* worry but frames it as a test obligation, not a design one.

**Fix:** make D2/D3 state that the command must iterate `get-buffer-window-list` and reposition each window's `window-point` onto the corresponding visible heading, and keep R6 row 5's two-window case as its check. Cheap to write now, easy to omit at implementation time.

### S5 — D3 names the wrong symbol for the preserve-visibility gate  *(dimension 2, source-derived, confirmed)*

**Spec heading:** D3 — 初始規則與概況命令 ("已安裝 `magit-insert-section--create` 優先查 visibility hook（原生含 cached visibility）；停用 preserve-visibility 時才查相符舊 section，之後才是 initial alist 與 hardcoded default").

The described precedence is **correct** — `magit-section.el:1453-1468` orders: `magit-section-set-visibility-hook` → old matching section (gated on `(not magit-section-preserve-visibility)`) → `magit-section-initial-visibility-alist` → HIDE. But the gate is `magit-section-preserve-visibility` (`magit-section.el:337`, `defvar-local`, default `t`), a different symbol from the two `magit-mode.el:1548/1554` functions the spec names in the same paragraph, and it is the only symbol in the chain the spec leaves unnamed. It is also load-bearing twice over: `magit-section-cached-visibility` returns `nil` outright when it is `nil` (`:1999`), so setting it off disables *both* the hook path and cross-buffer restore, and R2's "刷新…保留 Magit 對相同 section 身分的既有摺疊還原" would then rest on the old-root branch within a single buffer only, with R2's cross-buffer sentence ("Magit 能在 buffer 被關閉後還原同 repository 的可見性快取") no longer holding.

**Fix:** name `magit-section-preserve-visibility` in D3, state that R2 assumes it stays non-nil (the default), and note the degraded-but-defined behaviour if a user turns it off — which also gives R5's disable story a second axis to mention.

## Nits

- **N1** — R4 ("Overview 的入口可以在窄窗被省略"): `fenrir/magit-hints--layout` (`init-git.el:117-124`) drops the *trailing* actions first and preserves help plus the **first** action. Whether the overview entry survives a narrow window is therefore a function of its position in `fenrir/magit-hints-alist`, not a free choice; worth one clause so the plan places it deliberately.
- **N2** — R1 ("千行 XML 與一般文字檔使用相同規則，不依副檔名排除變更") is already unconditional in `magit-diff.el:2781-2782`, which branches only on `"deleted"` and the major mode. Harmless to state, but it is a native invariant rather than an acceptance criterion, and R6 row 1 spends its XML fixture on it.
- **N3** — R6's nine rows carry no ordering or priority. R6's closing paragraph correctly says the spec does not claim execution, but the plan will need a sequence; a one-line note on which rows gate the others would carry that intent forward.

## Cross-dimension pre-mortem

Assume this ships as written and is judged a failure within 90 days.

1. **Untracked files quietly disappear from fresh buffers.** D1's "保留原生即可" is followed for all three groups; per **B2** untracked is the one with `HIDE=t`, so every new-cache status buffer hides it. The regression is invisible to R6 row 1 as written because the row's other assertions still pass. The spec needed the per-group defaults written down (**B2**) and a row that fails on a no-op (**S1**).
2. **The feature exists but nobody finds it.** Per **B1** the binding is optional and the hints toolbar structurally cannot list an unbound command; the plan defers the keymap conflict check; the command ends up `M-x`-only, and the user's original complaint — the review flow — is unchanged. The spec needed to resolve R3's discoverability route before plan.
3. **The two-window case bites after the fact.** Per **S4** only the selected window's point is repaired; a user running the command with the status buffer in a second window lands that window's cursor in an invisible, `cursor-intangible` region. R6 row 5 would catch it *if* someone runs it, but no design line assigns the work, so the likely outcome is a late fix rather than a prevented one.

## Coverage and limits

- All six dimensions triaged; four discussed, two skipped with the verified reasons recorded above (not "looks fine").
- All of the frozen spec was read: R1–R6, D1–D4, Flagged concerns, and the three carried open questions (102 lines).
- Reviewed locally by one reviewer; no subagents dispatched (task forbade them), no delegation.
- **Not checked:** any interactive or executed behaviour. No Emacs started, no Elisp evaluated, no `emacsclient` call, no timing, no screen capture, no TTY/GUI coexistence test, no fixture repository built. Every empirical claim above is read from source at `d65ffc8` and the installed packages named in `evidence/baseline.md`.
- **Not recomputed:** the four magit/magit-section package SHA-256 values in `evidence/baseline.md`. `lisp/init-git.el` was re-hashed and matches.
- **Deliberately not read:** other reviewers' outputs, and the live `spec.md` (only the frozen snapshot was reviewed).
- Budget: 12 files, ~22 tool calls, within the dispatched bound.
- The spec was not modified. Findings recommend changes; none were applied.
- No auxiliary snapshot written by me — the coordinator preserved the exact input at the path named above. This file is the only artifact I created.

## Open questions for the author

| ID | Question | Likely owner |
|---|---|---|
| B1 | Is the key binding mandatory, is a `magit-dispatch` suffix in scope, or does R3 drop "既有說明入口"? | spec author; user for the binding itself |
| B2 | Confirm the untracked group's fresh-cache default and make `untracked → show` a required initial rule | spec author (settling check: implementer) |
| S1 | Which R6 row is intended to fail on a no-op implementation? | spec author |
| S2 | Which section does the over-limit fixture exercise? | spec author |
| S4 | Does the command own multi-window `window-point` repair, or is R5's sentence to be weakened? | spec author |

**"Nothing to flag" is not claimed.** Dimensions 4 and 5 were skipped on verified low surface area with the cited text recorded; the four discussed dimensions produced two blockers and five should-fix items, none of which asserts that the spec is otherwise safe or accepted.
