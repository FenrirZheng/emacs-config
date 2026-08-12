# TASKS — Emacs ↔ VSCode parity, Tier 1

> 補齊 VSCode 五個最有感的特性到 TTY-daemon Emacs 30 config。
> 全部選項都驗證過 TTY 友善（不依賴 child-frame / fringe）。
> Status: ☐ todo · ⧗ in-progress · ☑ done.

## Scope

只做 Tier 1。Tier 2/3 留作後續，不在此 task 範圍內：

| # | VSCode 對應 | 套件 | 目標模組 |
|---|---|---|---|
| 1 | Error Lens (inline diagnostic) | `sideline` + `sideline-flymake` | [`lisp/init-languages.el`](../../../lisp/init-languages.el) |
| 2 | Inlay hints | 內建 `eglot-inlay-hints-mode` | [`lisp/init-languages.el`](../../../lisp/init-languages.el) |
| 3 | Quick Fix 燈泡 (Ctrl+.) | 內建 `eglot-code-actions` 綁鍵 | [`lisp/init-languages.el`](../../../lisp/init-languages.el) |
| 4 | GitHub PR Reviewer | `forge` | [`lisp/init-git.el`](../../../lisp/init-git.el) |

> T5（常駐左側檔案樹 / dirvish-side）已於 2026-05-25 從 Tier 1 移除，理由：daemon 啟動就跳 sidebar 在 TTY 多 frame 場景會搶版面、手動 toggle 又跟既有 `C-x C-d` / dired 重複。

## Implementation

- ☑ **T1** Error Lens via sideline
  - 在 [`init-languages.el`](../../../lisp/init-languages.el) `flymake` block 後新增
    `use-package sideline` + `use-package sideline-flymake`。
  - `:hook (flymake-mode . sideline-mode)`；`sideline-backends-right '(sideline-flymake)`。
  - `sideline-flymake-display-mode 'point`（只顯示當前行，避免整 buffer 雜訊）。
  - 兩個套件都不在 elpa/，先跑 `M-x my/package-refresh` 再重啟一次 daemon。
  - 驗收：故意打錯一個 TS 型別，當前行右側 inline 顯示紅色 diagnostic 文字；
    `M-n` / `M-p` 跳到下個錯誤時 sideline 跟著移動。

- ☑ **T2** Inlay hints 開關
  - 在 [`init-languages.el`](../../../lisp/init-languages.el) `(use-package eglot)`
    的 `:hook` 裡加一行 `(eglot-managed-mode . eglot-inlay-hints-mode)`。
  - 不需要新套件 — Emacs 30 內建。
  - 驗收：開一個 Go 檔案，呼叫帶多參數的 function，參數名稱以 dim face inline
    出現在實參前；Rust `let x = vec![…]` 顯示 `: Vec<i32>` hint。
  - 若覺得太吵：`(setq eglot-inlay-hints-mode-map ...)` 可綁 `C-c C-i` 來 toggle。

- ☑ **T3** Code Actions keybinding（VSCode `Ctrl+.` 等價）
  - 在 [`init-languages.el`](../../../lisp/init-languages.el) `(use-package eglot)`
    末尾加 `:bind (:map eglot-mode-map ("C-c ." . eglot-code-actions))`。
  - 為什麼是 `C-c .`：呼應 VSCode 的 `Ctrl+.`，且不與既有任何 binding 衝突
    （`C-.` 已給 embark-act，所以走 `C-c` prefix）。
  - 驗收：在 TS 檔光標停在未 import 的 symbol，按 `C-c .` 出現 transient 列表，
    其中含 "Add missing import"；選下去自動補 import 在檔首。
  - 注意 `eglot-code-action-fix-all` / `eglot-code-action-organize-imports`
    也可以另外綁鍵，但先不加 — 先看 `C-c .` 列表夠不夠用。

- ☑ **T4** Forge — Magit 內 GitHub PR / issue
  - 在 [`init-git.el`](../../../lisp/init-git.el) `(use-package magit-todos)` 之前
    加 `(use-package forge :after magit)`。
  - 不在 elpa/，先 `M-x my/package-refresh` 再重啟。
  - 首次使用：`M-x forge-add-repository` 在當前 repo 啟用；token 走 `auth-source`
    （`~/.authinfo.gpg`，machine `api.github.com` login `<user>^forge`
    password `<gh PAT>`）。
  - PAT scope：`repo`, `read:org`。建 token 從 `gh auth token` 取得也可（已有 `gh`）。
  - 驗收：在一個 GitHub remote 的 repo 跑 `magit-status`，header 多 Pull requests / Issues
    section；`'@ p l'` fetch PRs；游標在 PR 上按 `RET` 看 PR detail buffer。
  - 不做：不啟用 `forge-pull-notifications`（會在 minibuffer 噴通知，干擾 TTY 工作流）。

## Verification

- ☑ **V1** 四項各別獨立驗收完成（見每個 T*N* 的驗收條目）。Depends on T1–T4。

- ☑ **V2** 全部 byte-compile 乾淨重啟：
  - `fdfind -e elc lisp/ -X rm` → 重啟 daemon → `*Messages*` 無 warning/error。
  - `M-x eglot-stats` 在 TS / Go / Rust 三個 buffer 顯示 server 仍正常。

- ☑ **V3** 不破壞既有設定的負面測試：
  - `C-x g`（magit-status）開啟時間沒明顯變慢（forge 不會阻塞）。
  - `M-.` / `M-?` xref 行為不變（sideline 不應影響 xref）。
  - hideshow transient（`C-c @`）仍正常。
  - Vertico-driven completion-at-point（`M-TAB`）仍走 minibuffer 而非 corfu popup。

## Checkpoints

- ☑ After T1 — sideline 套件已裝、`flymake-mode` buffer 右側顯示 diagnostic。
- ☑ After T2 — Go/Rust buffer 看到 inline inlay hint。
- ☑ After T3 — `C-c .` 在 eglot buffer 觸發 code-actions transient。
- ☑ After T4 — `magit-status` 多 Pull requests / Issues section。
- ☑ After V1/V2/V3 — 一次完整 daemon 重啟通過。

## Out of scope（明確不做）

- ❌ 重新啟用 `global-corfu-mode`（user 已刻意關掉，需獨立決策 — 見 [`init-corfu.el`](../../../lisp/init-corfu.el) 頭部註解）。
- ❌ 換 `lsp-mode`（為了 code lens）。Eglot 投入過深，遷移成本大於收益。
- ❌ `eldoc-box` / `lsp-ui` / 任何 child-frame 套件 — TTY-only 環境直接消失。
- ❌ T5 / 常駐左側檔案樹（dirvish-side）— 拆出 Tier 1，理由如 Scope 註解。
- ❌ Tier 2/3 全部項目（indent-bars / blamer / tab-bar / consult-yasnippet / 等）— 另開 task。

## References

| doc | why |
|-----|-----|
| [`init-languages.el`](../../../lisp/init-languages.el) | T1–T3 改動點：Eglot、Flymake、sideline |
| [`init-git.el`](../../../lisp/init-git.el) | T4 改動點：Forge 嵌進 magit block 之間 |
| [`init-corfu.el`](../../../lisp/init-corfu.el) | 為什麼 Out of scope 不重啟 corfu popup（同一決策的歷史） |
| [`FEATURES.md`](../../../FEATURES.md) | 完成後同步：新 keybinding (`C-c .`) 與 forge prefix (`'@'`) |
