# Delta review B — magit-status-overview spec v2

Reviewer `review-b` (Claude Code `f74f5bb8-6e93-4c7a-b76a-4834792e43a1`, `claude-opus-5[1m]`) · task `magit-spec-review-b-delta` / `review-b-delta-001` · produced 2026-09-10T04:43:27Z

| item | value |
|---|---|
| Reviewed | `evidence/review-20260910T1227+0800/spec-v2.snapshot` |
| v2 SHA-256 | `fa7efffcfd8733f987f66a18127ffc7a144549f2c24dee9ddea9cdd167b67421` (recomputed, matches dispatch) |
| Diff | `v1-v2.diff`, SHA-256 `121c6adee6ae896a7a38b2d966a8d14eb6c83b2fe023bd8b67d3df5e6e30a817` |
| Source | `d65ffc852c29fdb2c0c5600074f7181b6ffc0001` |
| Prior review | my own `/tmp/magit-spec-peers/review-b.md` (`f5a97a5b…88bab`) |

All evidence remains **source-derived / document-derived**. No Emacs started, no Elisp evaluated, no fixture, no timing.

## Prior finding status

| ID | v1 severity | Status | Basis in v2 |
|---|---|---|---|
| **B1** entry point unreachable | blocker | **resolved** | R3 makes `j o` the mandatory normal route with M-x as fallback and a conflict path; R4 forbids passing `j o` through the live-binding check and hints `j Jump menu` instead; D4 scopes the `magit-status-jump` `o` suffix and reload-idempotence |
| **B2** untracked `HIDE=t` | blocker | **resolved** | D1 states the per-group asymmetry and cites `magit-insert-files`; R2 makes `untracked → show` the required increment; D1 adds "觀察案例 untracked 曾為 show 不代表原生初始狀態" |
| **S1** row 1 no-op-satisfiable | should-fix | **resolved** | R6 row 1 now contrasts with the option off; new row 2 (pre-collapsed groups, partial `show` cache) states "noop 與只開父群組都必須失敗" |
| **S2** `file-list-limit` scope | should-fix | **resolved** | New R1 paragraph scopes it to `magit-insert-files` types; R6 row 4 requires >100 flat untracked plus a >100-staged control |
| **S3** command cost unobserved | should-fix | **resolved** | R5 narrows the zero-I/O claim to the hints redisplay path and permits lazy materialization; new R6 row 13 requires wash/paint counts, subprocess check, repeat-materialization check, counter-based hints I/O |
| **S4** multi-window point | should-fix | **resolved** | D2 names `get-buffer-window-list` across all frames and `set-window-point`; R3 bounds it to windows hidden by the overview; R6 row 7 asserts selected *and* non-selected `window-point` |
| **S5** wrong gate symbol | should-fix | **resolved** | D3 now names `magit-section-preserve-visibility`; R2 adds the `nil` contract ("不承諾 kill/recreate 可還原，也不偷偷將變數設回 t") |
| **N1** hints item position | nit | **still open** | R4 still says the entry "可以在窄窗被省略" without fixing its position in `fenrir/magit-hints-alist`; `--layout` (`init-git.el:117-124`) preserves only help + the **first** action |
| **N2** XML clause vacuous | nit | **resolved** | Row 1's XML fixture now carries the option-on/off contrast |
| **N3** R6 unordered | nit | **resolved** | New 驗證順序 paragraph sequences control group → command → entry/TTY/failure/I-O |

## Source verification of the resolved blockers

- `magit-status-mode-map` binds `"j" #'magit-status-jump` — `magit-status.el:391`. So R4's live-binding check (`fenrir/magit-hints--item`, `init-git.el:96-98`) genuinely passes for `j`, and R4 is right to refuse synthesising `j o` for it.
- `magit-status-jump` suffix keys are `z t n i u s`, `fu fp pu pp a w`, `j` (`magit-status.el:~405-411`). **No `o` suffix** — v2's claim confirmed; `o` is free at this revision.
- `magit-insert-files` creates the group with `HIDE=t` — the form is `magit-status.el:797`; D1 cites `:793`, the enclosing `defun` line. Same function, close enough to follow.
- `git update-index --refresh` is in the status refresh path (`magit-status.el:467`), so R6 row 12's allowance for stat-metadata change while requiring identical `git ls-files --stage -z` and file contents is well founded.

## Six-dimension triage (delta)

| Dimension | Verdict |
|---|---|
| 1 Context/alignment | **skip** — B2/S1 closed; D1 now states the real increment and disclaims the baseline observation |
| 2 Architecture/design | **discuss** — one new dependency in the cache contract (D1 below) |
| 3 Resilience/edge cases | **skip** — v2 adds the failure contract (per-buffer fallback, single `*Warnings*` summary, "概況未完成" on partial failure, no redisplay retry) and R6 row 11 exercises it |
| 4 Operability/observability | **skip** — reversibility now honest ("關閉預設…並不抹除已經由明確命令寫入的原生快取"); diagnosis via `magit-describe-section`; row 10 covers reload/suffix duplication |
| 5 Security/compliance | **skip** — unchanged surface; row 12 strengthens the no-mutation evidence |
| 6 Execution/milestones | **skip** — S1/S3/N3 closed; distinguishing tests and an explicit ordering now exist |

## New findings

### D1 — cross-buffer cache restore is not self-installing in a status-only session *(should-fix, dimension 2, source-derived)*

**Headings:** R2 ("Magit 能在 buffer 被關閉後還原同 repository 的可見性快取"), R5 ("停用預設後…原生可見性快取仍優先"), D3, R6 rows 5 and 10.

`magit-restore-section-visibility-cache` is called unconditionally on buffer setup (`magit-mode.el:917`), but the *preserve* half is installed in exactly one place — `magit-refs.el:328`, at the end of `magit-refs-refresh-buffer`:

```elisp
(add-hook 'kill-buffer-hook #'magit-preserve-section-visibility-cache)
```

No `LOCAL` argument, so it lands on the **global** `kill-buffer-hook` — which is why the coordinator's re-probe found it in `default-value` and why the earlier baseline read was a false negative. The consequence the probe does not show: it is installed **only after a refs buffer has been refreshed at least once** in the session. `magit-preserve-section-visibility-cache` gates on `(derived-mode-p 'magit-status-mode 'magit-refs-mode)` (`magit-mode.el:1549`), so it does cover status buffers — once it exists.

**Consequence:** in a session where the user only ever opens `magit-status`, killing the status buffer preserves nothing; the recreated buffer falls through to the initial alist and hardcoded defaults. R6 row 5 ("kill 後重建") and row 10 ("停用不清快取") therefore pass or fail depending on whether the tester happened to press `y` earlier — a nondeterministic acceptance row, not a wrong requirement.

**Fix:** state in R2/D3 that cross-buffer restore depends on this hook, and have R6 row 5 pin the precondition (open a refs buffer first, or assert `(memq 'magit-preserve-section-visibility-cache (default-value 'kill-buffer-hook))` before the kill). One interactive check settles it; I did not run it.

### D2 — `magit-zap-caches` clears more than visibility *(nit)*

D4 tells the user to run `M-x magit-zap-caches` to compare the native initial appearance. Without a prefix it drops the repository's whole `magit-repository-local-cache` entry and the blob cache (`magit-mode.el:~1559`), not just `magit-section-visibility-cache`. D4's own promise ("功能本身不自動清除 repository 的其他快取") is kept — but the recommended recovery does clear them. One clause naming the breadth keeps the two sentences consistent.

## Coverage and limits

- Every v1 finding given a status; six dimensions triaged; both prior blockers re-verified against source, not just against the new prose.
- Read within budget: v2 snapshot, `v1-v2.diff`, my `review-b.md`, and 4 source files (`magit-status.el`, `magit-mode.el`, `magit-refs.el`, `lisp/init-git.el` from v1) — 7 files, 6 tool calls.
- **Not read:** any other reviewer's output, and the live `spec.md`. The A1/A2 positions in the dispatch are taken as coordinator-supplied context; I neither corroborate nor dispute them beyond re-confirming the untracked `HIDE=t` fact from source.
- **Not executed:** every interactive check, including the one that settles D1 and the `o`-suffix conflict path.
- **Not re-checked:** the four magit package hashes in `evidence/baseline.md`; v2's unchanged sections (Flagged concerns, Open questions) — the diff shows no hunks there.
- **Timestamp correction:** my v1 handoff carried `04:44:00Z` while mailbox receipt was earlier. Every timestamp here comes from `date -u`.
- No spec edit, no project write, no git write, no Emacs mutation, no subagent. Sole artifact: this file.
