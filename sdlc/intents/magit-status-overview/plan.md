# Plan: Magit status 檔案概況與檢閱動線

Author: codex (agent)
Created: 2026-09-10
Status: draft

依據 `4168a41` 已接受的 [spec](spec.md)，新增 status 專用概況預設與手動入口，保留 Magit 原生快取、篩選及操作語意。本計畫先於對話的 Plan Mode 提出，再依使用者要求保存至磁碟；本文為實作計畫，不代表已完成實作或驗證。時間背景為 2026-09-10（Asia/Taipei），目標環境為本庫 Emacs 30.1 共用 daemon 的 TTY／GUI。

## Files that change

| 檔案 | 責任 |
|---|---|
| `lisp/init-git.el` | 預設選項、初始化、概況命令、transient 及 hints 整合 |
| `FEATURES.md` | 操作、停用、快取及共用視窗說明 |
| `shell/test-magit-status-overview.el`（新增） | ERT、可丟棄 Git fixtures、互動驗證輔助工具 |

SDLC home 另保存本 plan 與 `evidence/verification.md`，由既有文件索引連入。驗證紀錄包含時間與時區、版本、命令、結果、畫面或可見性證據及限制；保留既有審查快照。

## Order of work

### 1. 建立控制組與驗證工具

- 以已接受 spec 的 R6 全部案例建立驗收清單，使用臨時 repository，資料由測試生成。
- 測試載入實際 `init-git.el` 與已安裝套件，禁止測試自動安裝套件；不複製受測函式。
- 先記錄原生狀態：staged／unstaged 群組展開、tracked body 收合、untracked 群組收合。
- 現有 hints 已使用各視窗 point 的 ancestry 判斷 status 類型，列為完成基準並保留；後續只加入入口提示。
- 計畫獲批准後才建立 `intent/magit-status-overview` 分支及獨立 worktree；保留目前 checkout 與其他伙伴的變更。

### 2. 加入新 buffer 的初始規則

- 新增 boolean 選項 `fenrir/magit-status-overview-default`，預設 `t`。
- 在受 status mode guard 保護的 `magit-create-buffer-hook`，於首次刷新前記錄建立時選擇。
- 使用 permanent-local 狀態區分「未記錄／啟用／停用／初始化失敗」。Mode 重設後，`magit-status-mode-hook` 只恢復已記錄選擇。
- 啟用時在 buffer-local visibility alist 尾端加入 `([untracked status] . show)`。採用 vector lineage，讓既有匹配條目及原生 cache 優先；不加入全域 file 規則。
- Hook 與規則安裝須可重複載入，不掃描並重設既有 buffer。選項改變只影響之後建立的 buffer。
- 新初始化邏輯失敗時恢復修改前 alist，記錄本 buffer 失敗狀態並最多警告一次；不攔截 Magit refresh 的原生錯誤。

此階段須先通過「首次顯示即有差異」及 mode 重入測試，再實作命令。

### 3. 實作 `fenrir/magit-status-overview`

- 非 status 立即 `user-error`；沒有目標群組則安全 no-op，保留 selection。
- 只處理 status root 直接子節點中的 staged、unstaged、untracked。以 `magit-section-show` 展開群組，待原生 lazy body 建立後，再以 `magit-section-hide` 收合 staged／unstaged 的直接 file 子節點。
- Untracked 沿用原生清單，保留截斷 info；不遞迴列目錄、不重建 diff、不呼叫 refresh 或額外 Git 掃描。未知節點保持原生狀態。
- 操作前保存 buffer point，以及 `get-buffer-window-list` 涵蓋所有 frame 的 window-point、marker 與 section 身分。
- 操作後只修正新隱藏的位置：優先回到原 file 標題，其次目標群組標題。使用更新後 marker／`magit-get-section` 定位及 `set-window-point`，不切換 frame 或改視窗配置。
- 成功操作後解除 active region，透過原生 highlight 更新清除 section selection；保留 mark ring並刷新 hints。
- 使用原生 show/hide 更新 visibility cache，不另存可逆摺疊快照。重複執行結果相同，普通 `g` 保留新概況。
- 以清理區塊確保中途失敗仍盡力修正 point、selection；回報「概況未完成」，允許已完成的局部摺疊保留。

### 4. 整合入口與文件

- Magit 載入後，用 `transient-get-suffix` 檢查 `o` 及本命令是否存在；檢查相關 transient keymap 是否已有衝突。
- 正常結構使用 `transient-append-suffix` 在 `(0 2)` 的「Jump using」欄後加入 View 欄，提供 `o Overview (fold diffs)`；以 `keep-other` 的 `always` 防止隱式替換。
- 已有本入口則不重複插入；遇其他動作佔用或結構不相容，保留現狀、發出一次摘要警告，保留 M-x 入口。
- Status hints 在現有情境動作之後附加 `j Jump menu`，交由既有 live-binding 檢查與窄窗排序處理，不將 `j o` 當一般 keymap 序列。
- 文件說明 `j o`、M-x、原生 TAB／RET／diffstat、與作用整棵樹的 `M-2` 差異；說明停用只停止新增預設，並不清除快取或復原舊摺疊。

## Risks

- **套件 API 與 lazy body：** 目前來源為 Magit `20260506.643`、magit-section `20260503.2051`、Transient `20260507.1521`。實作開始重新核對版本與來源雜湊；必須先展開群組再取得子節點。
- **手動狀態遭覆寫：** 不在 post-refresh 執行概況；cache、使用者 alist、初次定位及 reveal 保持原生優先序。
- **共用 buffer：** 摺疊影響所有視窗，必須驗證非選取視窗 point；單窗成功不足以驗收。
- **停用與退回：** 沒有 migration；關閉預設不清 cache。`magit-zap-caches` 是使用者另行選擇，且會清除其他 Magit 快取。
- **驗證環境：** TTY、GUI 與同 daemon 雙 frame 是必要條件；缺少任一環境就記錄未完成驗證，不以 batch 成功代替。

## Proof

執行 `emacs -Q --batch -l shell/test-magit-status-overview.el -f ert-run-tests-batch-and-exit`，再依 R6 完成互動驗收與 `bash .githooks/pre-commit`。測試不得留下 `.elc`。

驗證分四組：

1. **初始與快取：** 混合狀態及 1,600 行以上 XML；選項開／關控制組；使用者 alist；refresh、mode 重入、kill/recreate、設定重載、preserve-visibility=nil、初次定位與 reveal。
2. **概況與定位：** 先收合三群組、展開部分 tracked body；驗證檔名實際可見、body 實際隱藏、兩次命令結果一致、刷新維持概況、非目標群組不變，以及 selection／所有 window-point 正確。
3. **原生邊界與入口：** 部分暫存、rename、binary、submodule、unmerged、空狀態與單一群組；停用 untracked、超過 100 個 untracked 的 info 提示、超過 100 個 staged 不受此限；篩選、`j o`、鍵位衝突、重載、非 status 與錯誤注入。
4. **畫面與成本：** 同 daemon 的 TTY 80×24、GUI 窄／寬窗及跨 frame 雙窗。保存實際畫面／可見文字、ellipsis 與 invisible 狀態；確認 hints 不截斷動作、不錯報按鍵或 Region。

概況命令與 hints 前後比較 raw index、工作樹內容雜湊；普通 `g` 另比較 `git ls-files --stage -z`，允許原生 index stat metadata 改變。分別記錄刷新及概況耗時、washer／paint 次數與 subprocess；固定 buffer 下強制 redisplay，驗證新增 hints 路徑零 Git／檔案 I/O。

驗證必須能抓到 no-op、只展開父群組、每次刷新強制摺疊、只修正選取視窗等錯誤實作。所有必要案例通過並保存證據後，才宣稱實作完成。
