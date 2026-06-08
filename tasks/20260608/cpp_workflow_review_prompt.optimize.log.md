# Optimization log — cpp_workflow_review_prompt.md

Iterative refinement of the C++/Emacs-plugin Review Prompt via the agy expert loop.

## Iteration 1 — 2026-06-08 17:20
**Adopted:**
- File-access made explicit ("用檔案讀取工具讀取" + 禁止臆測) — prevents the AI hallucinating file contents or skipping the read.
- Converted the four Yes/No dimension questions into extraction directives (指出/列出/揪出/標示出) — Yes/No invites lazy "looks good"; directives force concrete flaw-hunting.
- Anchored subjective criteria to objective terms (deprecated/anti-pattern, UI-blocking, 邊界處理/坑洞) — "elegant"/"modern" alone yield inconsistent reviews.
- Removed tautology「異步非同步處理 Async」→ folded into「非同步處理 (Async)」.
- Enforced 1-to-1 code mapping: every flagged defect must ship a copy-pasteable Elisp block — no vague prose.
**Rejected:** none material this round (all five suggestions advanced clarity/execution; #4 adopted in augmented form, keeping the user's elegance intent rather than deleting it).
**Edits:** §intro (file-access + no-hallucination clause); §核心審查維度 1–4 (rewrote as extraction directives w/ objective anchors); §輸出要求 3 (mandatory per-defect code block).

## Iteration 2 — 2026-06-08 17:28
**Adopted:**
- Strict 3-段式 defect template (引文出處 → 具體缺陷 → 修復方案) replaces inline code-mandate — templates yield far more reliable citation-backed, actionable output.
- Resolved the contradiction between「禁止臆測/必須引用行號」and「指出文件未涵蓋的坑」: for *missing* config the AI now cites the injection point + supplies the patch, instead of citing nonexistent lines.
- Simplified file-access line — dropped the confusing「若已附在下文則以下文為準」conditional branch (real use is a file reference; executing agent has file tools).
**Rejected:**
- "指出過時套件須附替代品名稱與配置" as a standalone clause — already subsumed by the new 修復方案 row (folded in there instead of adding a separate sentence; keeps doc tight).
**Edits:** §intro (single-path file read); §維度 3 (missing-config → injection-point rule); §輸出要求 3 (rewritten as strict 3-part template).

## Iteration 3 — 2026-06-08 17:36
**Adopted:**
- Closed the strict-quote vs missing-content contradiction properly: intro now grants a global「缺失內容除外」exception; the missing-config carve-out moved out of 維度 3 into output template bullet 1 (引文／插入點). 維度 3 reverts to a clean "未涵蓋的坑" phrasing.
- Generalized 具體缺陷 → 具體缺陷／不足 (效能/過時/衝突/缺失) — no longer forces every issue into the thread-block/deprecated/conflict trio (e.g. a missing CMake flag).
- Restricted the 3-段式 template to 🔴/🟡 only; 🟢 亮點 explicitly exempt — removes "how do I format highlights" ambiguity, saves tokens.
- Removed Dim1/Dim4 "modern alternatives" overlap — Dim 4 now scoped to frontend (minibuffer/completion/UI anti-patterns), keeping dimensions mutually exclusive.
**Rejected:** none — all four were concrete contradiction/overlap fixes.
**Edits:** §intro (exception clause); §維度 3 (revert to 未涵蓋的坑); §維度 4 (scope to UI); §輸出要求 3 (🔴/🟡 scope + generalized defect + injection-point bullet).

## Iteration 4 — 2026-06-08 17:43
**Adopted:**
- Defused line-number hallucination: output template no longer *mandates*「並標明行號」— line numbers are now optional, with an explicit「讀取工具未提供行號時勿捏造」guard. Precision preserved when the reader does surface them.
- Locked the three bold heading keywords (「請精確使用以下三個粗體字詞作為區塊標題，勿自行改寫」) — prevents the AI silently renaming 引文/缺陷/修復 to 問題/解法, keeps output 100% format-consistent.
**Rejected:**
- agy's stronger form (delete line-number references entirely) — over-corrects; Claude Code's Read tool *does* return line numbers, so they stay a useful *option*, just never mandatory.
**Edits:** §輸出要求 3 (heading-keyword lock + line-number-optional / no-fabrication guard).

## Iteration 5 — 2026-06-08 17:50 (converged)
**Adopted:**
- Clarified `> [貼上原文]` is a Markdown-blockquote placeholder ("用 Markdown 引言語法（`>`）貼上文件原文") — stops a weaker model from copying the literal placeholder string verbatim.
**Rejected:** none — agy explicitly declared the prompt converged ("已達到收斂狀態，沒有會導致 AI 執行失敗或矛盾的實質問題"); this was the only remaining micro-tweak.
**Edits:** §輸出要求 3 (blockquote-syntax clarification on 引文／插入點 bullet).

---
**Loop complete — converged at round 5.** agy confirmed no substantive issues remain.
