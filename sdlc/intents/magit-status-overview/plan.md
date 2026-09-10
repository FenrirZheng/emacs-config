# Plan: Magit status 檔案概況與檢閱動線

Author: claude (agent)
Created: 2026-09-10
Status: draft

依據 `4168a41` 已接受的 [spec](spec.md)，新增 status 專用的概況命令與入口。本計畫取代
2026-09-10 較早的草稿：對已安裝套件重新核對來源後，該草稿數項 API 敘述有誤（見
[來源核對更正](#來源核對更正)），且使用者已就 untracked 規模、驗證方式與分期做出決定。
時間背景為 2026-09-10（Asia/Taipei），目標環境為本庫 Emacs 30.1 共用 daemon 的 TTY／GUI。
本文為實作計畫；已完成部分的證據在
[`evidence/verification.md`](evidence/verification.md)，未執行者於該檔明列為未驗證。

## 分期

依使用者 2026-09-10 決定，分兩個分支：

| 分支 | 內容 | 狀態 |
|---|---|---|
| 1 | 明確命令 `fenrir/magit-status-overview`、`j o` 入口、hints、文件、測試 | 本計畫實作範圍 |
| 2 | 新 buffer 初始預設 `fenrir/magit-status-overview-default` | **阻擋中**，需先修訂 spec 並重新接受 |

分支 2 阻擋的原因：使用者要求 untracked 數量過大時先警告並讓使用者選擇是否展開，這與
R2「無條件 `untracked → show`」不符；且 D3 指定的 `magit-section-initial-visibility-alist`
機制在該時點無法得知檔案數（section 尚無 heading 與 children，取得數量必須呼叫 Git，
違反 R5），先展開再收合則會白白付出 washer 成本。改採
`magit-post-create-buffer-hook`（在第一次 `magit-refresh-buffer` 之後、buffer 首次顯示
之前執行，仍滿足 R2「首次顯示即生效」），並以「無 cache 條目且無使用者 alist 條目」定義
新鮮度。此偏離須由人工修訂 spec 後才可實作，不由本計畫逕行變更。

## 來源核對更正

對實際安裝的 magit `20260506.643`、magit-section `20260503.2051`、transient
`20260507.1521` 逐項核對，較早草稿的錯誤如下，均已在實作中改正：

| 較早草稿敘述 | 實際來源 |
|---|---|
| visibility hook 名為 `magit-section-visibility-hook` | 實為 `magit-section-set-visibility-hook`（`magit-section.el:130`），且是 `defvar` |
| cache 為獨立的優先序階段 | cache 是該 hook 的預設成員，在第一階段內被查詢（`magit-section.el:1452`）；另有更高優先序：建構時明確傳入 `:hidden` 會短路整個 `cond` |
| — | `magit-section-hide-children` 只作用一層，與 docstring 所稱遞迴不符（`magit-section.el:1013`）——正是本功能需要的語意 |
| — | `transient-append-suffix` 預設只 `message` 不 signal（`transient-error-on-insert-failure` 為 nil）；在 group LOC 追加 suffix list 會被拒為 sibling，故 `(0 2)` 必須配 group vector |
| — | `transient-get-suffix` 回傳未求值的 spec list，不是 EIEIO 物件，`oref` 會 signal `wrong-type-argument` |

已確認正確者：staged／unstaged 群組預設 show、status 中 tracked file body 預設 hide、
untracked 以 HIDE=t 建立、`[untracked status]` vector lineage 可用、`o` 在
`magit-status-jump` 未被占用、`(0 2)` 即「Jump using」欄。

## Files that change

| 檔案 | 責任 |
|---|---|
| `lisp/init-git.el` | 門檻選項、概況命令與其輔助函式、transient 入口與衝突退路、status 的 `j` hints 項目 |
| `FEATURES.md` | 概況操作、單向語意、與 `M-2` 的差異、門檻與入口衝突退路 |
| `.githooks/pre-commit` | `check-parens` 檔案清單納入 `shell/*.el` |
| `shell/test-magit-status-overview.el`（新增） | 批次 ERT 與可丟棄 Git fixtures |
| `AGENTS.md` | 補上測試指令與局部測試的規範 |
| `sdlc/intents/.../evidence/verification.md`（新增） | 三層驗證紀錄與未驗證項目 |

## Order of work

### 1. 靜態與批次基礎

- `.githooks/pre-commit` 的 `check-parens` 清單加入 `shell/*.el`；原清單只含
  `lisp/`、`lisp/languages/` 與三個根檔案，新測試檔不會被檢查。
- 新增 ERT 檔。`emacs -Q` 不載入任何使用者設定，故測試檔自行依序載入本庫 `elpa/`、
  `use-package`、`magit`，再 `load` **實際的** `lisp/init-git.el`；不複製受測函式，
  強制 `use-package-always-ensure` 為 nil 以確保不安裝任何套件，不產生 `.elc`。
  另將 Forge／Transient 的狀態檔導向暫存目錄——正式設定由 no-littering 負責，
  單獨載入 init-git.el 時 Forge 會在庫根建立資料庫。
- 先寫原生對照組：新 buffer 中 staged／unstaged 為 show、tracked file body 為 hide、
  untracked 為 hide 且**尚無任何 children**。與原生同樣會通過的斷言不算證據。

### 2. 概況命令

- 新增 `fenrir/magit-status-overview-untracked-threshold`（nil 表示沿用
  `magit-status-file-list-limit`）。
- `fenrir/magit-status-overview`，`(interactive "P")`：非 status 立即 `user-error`
  且無副作用；目標為 root 直接子節點中的 staged／unstaged／untracked，無目標時安全
  no-op 且不動 selection。
- untracked 規模守門：仍收合且數量超過門檻時先 `y-or-n-p`；數量自 heading 讀取
  （`magit-insert-files` 傳入的是截斷前的總數），不呼叫 Git。前綴引數或批次模式不詢問。
- 以 `magit-section-show` 展開群組（此時才會執行 lazy washer 並建立 children），
  再對 staged／unstaged 以 `magit-section-hide-children` 收合一層。untracked 的子節點
  沒有 body，不處理；未知節點不動。
- 操作前以 **marker** 記錄 buffer point 與 `get-buffer-window-list` 涵蓋所有 frame 的
  window-point 及其 section 身分；展開 untracked 會插入文字，整數位置會失效。
  操作後只修正被隱藏的位置：仍可見者原位保留，否則沿身分逐層上溯至可見標題，
  以 `set-window-point` 套用到每個受影響視窗，不切換 frame、不改視窗配置。
- 成功後 `deactivate-mark` 並以 `(magit-section-update-highlight t)` 清除 section
  selection，保留 mark ring。
- 以 `condition-case` 收集錯誤，先還原 point 與 selection，再回報「概況未完成」與錯誤
  摘要；保留已完成的局部摺疊，不承諾交易式回復，不包住 Magit 自己的 Git 錯誤。

### 3. 入口與 hints

- `fenrir/magit-status-overview--install-entry`：以 `ignore-errors`
  包住 `transient-get-suffix`（找不到時會 signal 一般 `error`），以
  plist 讀出既有 suffix 的 `:command`；已是本命令則不重複安裝，被他人占用則保留原動作
  並發出一次警告，其餘情況在 `transient-error-on-insert-failure` 綁為 t 之下於 `(0 2)`
  追加 `["View" ("o" "Overview (fold diffs)" …)]` group vector，失敗亦只警告一次。
  M-x 在任何分支都可用。
- hints：在 `fenrir/magit-hints--render` 的 actions 尾端，status buffer 追加
  `("j" "Jump menu" magit-status-jump)`，交由既有 live-binding 檢查驗證；置於最尾使
  `--layout` 在窄窗優先捨棄它而非 stage／unstage。不把 `j o` 當一般 keymap 序列。

### 4. 文件與驗證

- `FEATURES.md` 第 8 節；`AGENTS.md` 的指令與測試段落。
- 依 Proof 的三層執行並寫入 `evidence/verification.md`。

## Risks

- **套件 API 與 lazy body：** 版本與雜湊見 [`baseline.md`](baseline.md) 與
  `evidence/verification.md`。升級後須重查；`transient-get-suffix` 的回傳形狀與
  `transient-append-suffix` 的靜默失敗是兩個已踩過的坑。
- **手動狀態遭覆寫：** 不在 post-refresh 執行概況；cache、使用者 alist、初次定位與
  reveal 保持原生優先序。
- **共用 buffer：** 摺疊影響所有視窗，單窗成功不足以驗收；非選取視窗的 point 必須實測。
- **重載不具冪等性：** 同檔 `lisp/init-git.el:468` 的 difftastic `transient-append-suffix`
  無守衛，實測該 daemon 已累積 6 份重複 suffix。本功能的入口必須自帶守衛，並以測試
  釘住；difftastic 那段不在本變更範圍。
- **驗證環境：** TTY、GUI 與同 daemon 雙 frame 為必要條件；缺任一則記為未驗證，
  不以批次成功代替。

## Proof

本變更新增局部 ERT 測試，涵蓋可在批次模式驗證的邏輯；提交前對所有變更的 Emacs Lisp
檔案執行括號檢查。R6 各項標明採用 ERT 或互動驗證，其中 TTY／GUI 顯示、重繪與實際事件
時序由互動驗證確認。未執行的項目記為未驗證，不以批次測試通過代替。

三層：

| 層次 | 指令 | 能證明什麼 |
|---|---|---|
| 靜態 | `bash .githooks/pre-commit` | 括號與字串結構、設定仍可啟動；不證明功能 |
| 批次 ERT | `emacs -Q --batch -l shell/test-magit-status-overview.el -f ert-run-tests-batch-and-exit` | 無畫面相依的可見性、冪等、刷新保留、原生語意、入口解析、Git 狀態未變 |
| 互動 | 共用 daemon 上 TTY 80×24 與 GUI 視窗同時顯示同一 buffer | 各視窗 point、selection、窄窗 hints 階梯、可見文字與 invisible 狀態、耗時與 I/O 計數 |

R6 驗收各列對應層次：

| R6 列（節錄） | 層次 |
|---|---|
| 無快取新 buffer 的初始狀態、選項開關對照 | 分支 2，本階段未驗證 |
| 先收合三群組後執行概況，檔名可見、body 隱藏 | ERT ＋ 互動 |
| 同檔部分暫存、rename、binary | ERT |
| submodule、unmerged | **未驗證** |
| untracked 停用／超過上限的截斷提示、staged 不受此限 | ERT |
| 手動展開後刷新、重新進入、kill 後重建 | 刷新為 ERT ＋ 互動；kill/recreate 屬分支 2，未驗證 |
| 既有 alist、初次定位、`preserve-visibility` nil | 分支 2，未驗證 |
| 兩次概況後刷新；GUI／TTY 雙窗不同 hunk | 互動 |
| active region／selection 解除；入口衝突 | 互動（region）＋ ERT（衝突） |
| 無變更／單一群組／非 status | ERT |
| TTY 80×24 與 GUI 窄寬窗、hints 不裁切 | 互動 |
| 重載無重複 hook／suffix | ERT |
| 錯誤注入、未知 section | **未驗證** |
| 前後 index 與工作樹雜湊、hints 路徑零 I/O | ERT（雜湊）＋ 互動（I/O 計數） |
| 已收合 untracked 的 washer 成本、重複執行不重新 materialize | 互動（耗時與 I/O）；wash／paint 次數**未驗證** |

測試一律使用可丟棄的 fixture repository，不更動觀察案例的業務資料，且不得留下 `.elc`。
任一必要行為不符即不能宣稱實作完成。
