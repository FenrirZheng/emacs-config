# Spec: Magit status 檔案概況與檢閱動線

Author: codex (agent)
Created: 2026-09-10
Status: draft

## Requirements

### R1 — 可辨識的檔案概況

在 `magit-status-mode` 提供「檔案概況」：保留原生分支／HEAD 資訊、群組標題及 Magit 原生數量；展開存在的 staged、unstaged、untracked 群組，讓檔案標題可見，收合 staged／unstaged 底下的檔案 body。千行 XML 與一般文字檔使用相同規則，不依副檔名排除變更。

「可見」指不因概況的摺疊設定而被隱藏，並非保證任何數量的檔案都塞進單一畫面。清單超過視窗時可正常捲動；長路徑沿用原生呈現與檔案造訪入口。同檔部分暫存時，保留 staged、unstaged 兩筆，不去重或合併。保留原生 rename、binary、submodule、unmerged 狀態資訊。

呈現範圍沿用現有 Magit／Git 篩選、`status.showUntrackedFiles`、`magit-status-show-untracked-files` 與 `magit-status-file-list-limit`；不為概況強制列出原生未載入或被使用者排除的資料。達清單上限時保留原生未列出數量／提示，群組數量不包裝成全 repository 的完整清冊。預設 fixture 應啟用 untracked 顯示，另測試使用者停用與清單超限情境。

`magit-status-file-list-limit` 只限制 `magit-insert-files` 類型的清單（本功能涉及 untracked），不限制 staged／unstaged diff 的檔案數；不可用大量 staged 檔案代替 untracked 的截斷測試。原生 `(info)` 的「N files not listed」提示須可見。

### R2 — 初始預設與手動選擇

新建立且沒有既有可見性還原資料的 status buffer 預設使用檔案概況，限目標群組及其檔案 body。Magit 能在 buffer 被關閉後還原同 repository 的可見性快取；這類重建優先保留原生還原結果，不強制覆寫為概況。既有 buffer 在載入／重載設定時，不自動重設使用者的摺疊選擇。一般刷新、重新顯示已存在的 buffer，保留 Magit 對相同 section 身分的既有摺疊還原；新出現且沒有原生快取狀態的檔案使用概況預設。

新增選項 `fenrir/magit-status-overview-default` 預設為 `t`，控制新 status buffer 的初始規則整合。規則的必要增量是無既有／快取狀態時的 `untracked → show`；staged／unstaged 原生群組 show、file body hide 作為相容性基準，不重做。使用者既有可匹配的初始可見性條目優先於新增預設；選項為 nil 時不加入新規則。既有 buffer 的 buffer-local 規則在重載時不被強制重寫。

此契約以 Magit 原生可見性配置為基礎：`magit-section-preserve-visibility` 為非 nil 時優先使用 cache；使用者設為 nil 時，保留原生同 buffer old-section 分支，不承諾 kill/recreate 可還原，也不偷偷將變數設回 t。初次定位的 `magit-status-initial-section` 特殊可見性條目，以及 `magit-status-goto-file-position`／明確 reveal 導覽仍依原生設定執行，可改變可見性；不將這些明確定位動作等同於不帶定位參數的普通 `g` 刷新。

明確執行「返回檔案概況」才重新套用目標群組的概況狀態。此命令需可重複執行，結果不隨執行次數變動；不變更其他群組的摺疊、Git diff 篩選或設定。不提供跨 Emacs 重啟的額外狀態儲存。

明確概況是一次新的手動摺疊選擇，按原生規則更新目標 section 的 visibility cache；其後普通刷新應保留概況，不自動恢復命令前展開的 diff。這是單向命令，不是暫時預覽或可恢復舊快照的 toggle。

### R3 — 入口與定位

提供 `M-x fenrir/magit-status-overview`，以及 status 的 `j` Jump menu 中 `o` Overview 入口（即 `j o`），放在新增的 View 欄，標籤為 `Overview (fold diffs)`，表明這會收合 diff 而非純粹跳轉。保留原生 `M-2`。目前已安裝 `magit-status-jump` 沒有 `o` suffix；整合時仍需檢查實際 transient／keymap，若使用者或擴充已佔用則保留原動作，提示入口衝突並保留 M-x，不無聲覆寫。此衝突退路另列驗收；正常 fixture 必須提供 `j o`。

從檔案或 hunk 執行時，point 留在該檔案的可見標題；從目標群組執行時留在群組標題；其他位置保留可見位置。只有因概況被隱藏的視窗 point 才需要移動；不變更視窗配置或選取其他 frame。成功套用目標概況時解除 active region／section selection，避免 point 改變後沿用舊選取範圍；不改 mark ring。沒有變更群組時為安全 no-op，非 status 錯誤也不改 selection。

使用者可用原生 TAB 展開／收合、section 導覽及 RET 造訪檔案，並以一次命令返回概況。命令不會 stage、unstage、discard、commit 或修改被檢閱 repository。

### R4 — 資訊與 hints 正確性

延伸既有 `fenrir/magit-hints-mode`，不新增競爭的 header 所有者。Hints 只顯示目前 key-binding 真正呼叫的命令；窄窗保留完整項目，不裁切成誤導的按鍵／標籤。Overview 的入口可以在窄窗被省略，但仍可透過 M-x 與文件找到。

Status hints 可以提示 `j Jump menu`，並用既有 live-binding 檢查確認 `j` 呼叫 `magit-status-jump`。不得把只在 transient 內生效的 `o` 當成 status 的直接快捷鍵，亦不把 `j o` 偽裝成一般 keymap 序列交給現有 hints 檢查。`FEATURES.md` 說明 `j o`／M-x、入口衝突退路與 native M-2 的範圍差異。

預設的 j 提示附加在既有情境動作之後，保留原有第一動作與 Help 的窄窗優先權；不為維持 j 提示而移除 stage／unstage 等主要動作。Status 的 diff-type 由該視窗 point 的 section ancestry 推導；其他模式既有的 buffer-local diff-type cache 不在此改動範圍。

本階段以原生檔案清單、狀態與群組數量作為概況資訊；不新增獨立 diffstat 計算器、XML 解析器、提交主題分類或測試成功標章。原生 diffstat 仍可按需使用；資料不存在時不製造零值，也不從歷史報告推論目前工作樹通過驗證。

### R5 — 共用 daemon、失敗與停用

TTY 與 GUI 可同時使用，同一 status buffer 的摺疊是 buffer 共用狀態，不承諾各視窗獨立。一次明確概況操作可影響所有顯示該 buffer 的視窗；各視窗 hints 仍依自身寬度與 point 顯示。操作後其他視窗的 point 不可卡在新隱藏的 body；需回到對應檔案／群組的可見標題。

新功能限定 status buffer。Log、revision、獨立 diff、selection buffer 的預設摺疊與 hints 既有行為維持。非 status buffer 呼叫概況命令時回報清楚的 user-error 且無副作用。停用預設後新 buffer 不加入本功能的初始規則，但原生可見性快取仍優先；不自動清除快取或還原命令前的摺疊。手動命令仍可使用。

Redisplay 中的新增 hints 邏輯不執行 Git subprocess、讀取工作樹或解析整個 diff。概況從既有 section tree 開始操作，允許 Magit 在展開群組時執行原生 washer／paint 並建立尚未 materialize 的子節點；不另行呼叫 Git 掃描或刷新 repository。Untracked 的原生 lazy body 受其清單上限約束；staged／unstaged 生成 diff 的成本不因此消失。新功能若遇無法辨識的 section，保留原生顯示；不得因概況增強失敗而使正常 status 無法開啟。原生 Git 刷新錯誤仍交由 Magit 呈現，不顯示自製「成功」摘要。

自動初始化中的新增邏輯若失敗，本 buffer 停用該次新增規則並保留原生設定，每個 buffer 最多發出一次可在 `*Warnings*` 查閱的摘要；不在 redisplay 反覆重試。明確命令若途中失敗，回報「概況未完成」與錯誤摘要，不宣稱完成；允許保留已完成的局部摺疊，不承諾 UI 交易式回復，並盡力保持 point 可見與解除已受影響的 selection。使用者仍可用原生 TAB／導覽修正。這些處理只涵蓋新增功能的錯誤，不包住或吞掉 Magit 自己的 Git 錯誤。

### R6 — 驗收邊界

| 案例 | 必須觀察的結果 |
|---|---|
| 無既有可見性快取的新 buffer：1 untracked、1 unstaged、10 staged，其中一個 XML 超過 1,600 行 | 第一次完整 status 顯示、尚未按 g 時，staged／unstaged 為原生相容性控制，untracked 必須因新增預設開啟。對照關閉新選項時原生 untracked 收合，避免 no-op 或第二次刷新才生效的實作通過 |
| 人為先收合三個變更群組，且快取中部分 tracked file 為 show，執行新概況命令 | 三群組標題下的檔名可見、tracked body 隱藏，原先隱藏的 untracked body 可載入；noop 與只開父群組都必須失敗 |
| 同檔 staged + unstaged，rename、binary、submodule、unmerged，以及 untracked 目錄 | 原生狀態與可用入口保留，部分暫存兩筆不合併；概況不聲稱目錄數量等同遞迴檔案總數 |
| Untracked 顯示停用、超過 100 個平坦 untracked 檔案（原生上限 100）、status 帶檔案篩選 | 原生排除及截斷 info 提示保留；另以超過 100 個 staged 檔確認不受此限，不宣稱完整清單、不改 Git 設定或自動載入省略內容 |
| 手動展開檔案、收合群組，再刷新、重新進入現有 buffer、kill 後重建 | Magit 可匹配／還原的 section 保留手動選擇；新檔無既有／快取狀態時套用預設 |
| 既有 visibility alist 條目、初次定位條目、goto-file-position、preserve-visibility=nil | 各自保留原生優先順序；與普通 g 分開驗證，不為強迫概況而覆寫使用者選項 |
| 未手動操作新 buffer 的 untracked 群組就重新執行 magit-status；其間改預設選項／重載模組 | 既有 buffer 保留建立時的初始規則選擇，不因 mode 重新初始化而遺失；後建 buffer 才採用新選項。載入功能前已存在且無此選擇紀錄的 buffer 不被自動套用 |
| 從 hunk 執行概況兩次後普通 g 刷新；同 buffer 在 GUI／TTY 各一窗顯示不同 hunk | 兩次摺疊結果相同且刷新後維持概況；selected 與 non-selected window-point 均在可見標題；非目標群組及篩選保持 |
| 有 active region／多 section selection 時執行概況；重映射 j 或佔用 transient o | 成功概況後 selection 解除且 hints 不再標 Region；入口無衝突時 j o 正確呼叫命令，有衝突時原動作不變、M-x 可用且有提示 |
| 無變更、只有 untracked、只有 staged、只有 unstaged、非 status 呼叫 | 前四者安全且有可理解畫面；非 status 無副作用並回報 user-error |
| TTY 80×24 與 GUI 窄／寬窗；同 daemon 並存 | 清單可導覽，hints 不裁切完整動作，按鍵與實際命令一致，沒有 frame 互斥；TTY 以可見文字／ellipsis 及 invisible 狀態驗證，不以 GUI fringe 測試代替 |
| 關閉預設、重載模組、套用功能前後的 log/revision/diff buffer | 沒有重複 hook/advice／suffix，沒有非 status 摺疊回歸；停用不清快取，使用者明確清快取後才比較原生初始外觀 |
| 在可丟棄 buffer 注入新初始化錯誤／手動命令中途錯誤，以及未知 section | 自動退回原生規則與一次警告；手動報未完成且原生操作仍可用；未知節點不被任意重設；Git 錯誤仍為原生錯誤 |
| 顯示操作前後與效能取證 | 新概況命令／hints 執行前後 raw index 與工作樹檔案內容雜湊相同；既有 `fenrir/magit-hints--render` 的新增路徑零 Git／檔案 I/O。另測普通 g，允許原生 update-index --refresh 的 stat metadata 變化，但 `git ls-files --stage -z` 與工作樹檔案內容必須相同 |
| 已收合且帶原生 washer 的 untracked 群組、長 XML、重複概況／redisplay | 分別記錄概況與原生刷新耗時、wash/paint 次數及是否新增 subprocess；確認概況沒有額外 Git 掃描，重複執行不重新 materialize 已載入 body。Hints 在固定 buffer 狀態下用暫時 process／file I/O 計數器與強制 redisplay 驗證，不只檢查畫面字串 |

上述為後續實作驗收要求，本 spec 產出不代表已執行。測試一律使用可丟棄的 fixture repository，不更動觀察案例的業務資料。比較前後使用相同 fixture、尺寸、套件版本及篩選條件；保留畫面或可見 section／header 證據與操作步驟。

驗證順序：先建立原生控制組及 untracked 初始規則差異，再測概況命令的可見性、快取、selection 與各視窗 point，最後驗證入口、TTY／GUI、失敗／停用與 I/O 成本。任一必要行為不符即不能宣稱實作完成；檔案修改順序與細分工作項目由後續 plan 記錄。

## Design

### D1 — 已知基準與資料來源

接受的 [intent](intent.md) 定義改善方向；[baseline](evidence/baseline.md) 記錄 2026-09-10（Asia/Taipei）的唯讀 runtime 與已安裝來源版本。當時 GUI staged／unstaged 群組已收合，子檔名不可見，不能把完整 buffer 文字當成畫面。

本庫 `lisp/init-git.el` 已有依 section/type 判斷的 hints，寬度不足時逐項移除；`fenrir/magit-hints--item` 核對 live binding；`--render` 走 redisplay，不能塞入新 Git 查詢。初始目標是能從「群組收合」或「長 diff 展開」直接回到檔案層級，並建立一致的新 buffer 預設。

來源與審查確認原生預設並不完全一致：`magit-diff-insert-file-section`（`magit-diff.el:2779`）在 status 預設 tracked file body hide，staged／unstaged 群組預設 show；`magit-insert-files`（`magit-status.el:793`）卻以 HIDE=t 建立 untracked 群組。原生群組已提供數量。實作增量因此明確為：status 專用的 untracked 初始 show 規則、範圍受限且可發現的概況命令，以及共用視窗／selection 的修正與驗收。其他已符合的原生預設不重做。觀察案例 untracked 曾為 show 不代表原生初始狀態；現有群組為何收合未經查證，不推定是使用者或擴充套件造成。

### D2 — 元件與所有權

所有概況選項、status 專用初始化、命令與 hints 整合歸 `lisp/init-git.el`，命名沿用 `fenrir/`；如需全域路由才在 `lisp/init-keys.el` 重複路由，不移動原功能定義。`FEATURES.md` 說明概況、手動摺疊、刷新、停用、共用 buffer 的影響與原生 diffstat 入口。

資料流：Magit 正常刷新建立 section tree → 初始可見性規則只作用於 status 的目標 section → 原生 buffer 顯示檔案概況。明確命令先保存所有顯示本 buffer 的視窗及其 point/section 身分（`get-buffer-window-list` 涵蓋所有 frame），再找 staged／unstaged／untracked 群組，執行原生 show/hide 與必要 lazy materialization，最後依更新後 marker／section 修正每個受影響視窗的 `window-point`（使用 `set-window-point`）及 selection，不只修正 selected window。沒有額外資料庫、背景服務、概況命令的 Git index 寫入或持久化摘要；原生 refresh 的 index stat-cache bookkeeping 見 R6。

### D3 — 初始規則與概況命令

使用 status buffer-local `magit-section-initial-visibility-alist` 加入 untracked show 預設，保留並優先尊重其他既有可匹配條目；不添加全域 `(file . hide)` 或重做 tracked 預設。已安裝 `magit-insert-section--create` 優先查 visibility hook（原生含 cached visibility）；只有 `magit-section-preserve-visibility` 為 nil 時才查相符舊 section，之後才是 initial alist 與 hardcoded default。Cache 優先於新預設正是 R2 的要求，不把未改變既有快取誤認為失敗。`magit-mode.el` 的 `magit-preserve-section-visibility-cache`／`magit-restore-section-visibility-cache` 可在同 repository 關閉再建 buffer 時還原狀態。因此不能在每次 refresh 結束無條件執行 overview，亦不應以更高優先的 visibility hook 強迫重設手動選擇。初次定位／reveal 的原生後處理依 R2 保留。

初始化時機固定在 status 專用、受 mode guard 保護的 `magit-create-buffer-hook`：此 hook 在 `magit-setup-buffer-internal` 呼叫 mode 後、第一次 `magit-refresh-buffer` 前執行（`magit-mode.el:664–697`）。在此記錄該 buffer 建立時的預設選擇並加入規則，不能等 `magit-post-create-buffer-hook` 或 refresh 結束才加入。該選擇是可跨 major-mode 重設保留的 buffer-local 狀態；既有 buffer 重新執行 mode 時，由 `magit-status-mode-hook` 只恢復已記錄的選擇，不重新讀取全域預設，也不替載入前已存在的 buffer 建立新選擇。此記憶只存於 buffer，非另一套摺疊 cache。對 `tracked`、`ignored`、`skip-worktree`、`assume-unchanged` 清單群組不增加 show 規則。

明確命令只處理變更群組，透過 Magit section API 展開父群組並收合 tracked file body。Untracked 保留原生清單／目錄表達，不強制遞迴載入。保留既有身分與 body，不自行重建 diff 或替換原生 section keymap。

原生 `M-2` (`magit-section-show-level-2-all`) 是重要比較方案，但作用於整個 root tree，可能改變 stash、commit 或其他非變更群組；本 spec 保留 `M-2` 並採用範圍受限的命令以滿足 R2。只對目標群組使用原生 section API，不呼叫全 root 的 M-2 再事後猜測還原其他群組。精確 lineage、point 調整與 lazy section 順序留給 plan 依已安裝 API 固定並驗證。

### D4 — 整合、恢復與成本

使用 buffer-local 設定與可撤銷的 hook；重載不重複安裝，不強制折疊已開啟的 buffer。保留停用前的其他初始可見性條目；不改 `magit-section-cache-visibility` 變數或模組 load order。關閉預設／撤回配置會停止新增介入，並不抹除已經由明確命令寫入的原生快取。使用者若要重新比較原生初始外觀，可另外明確執行 `M-x magit-zap-caches` 或重新啟動 Emacs；功能本身不自動清除 repository 的其他快取，也不承諾恢復命令前的個別摺疊。沒有資料 migration。診斷可用 `magit-describe-section` 查 lineage，並區分初始 alist、原生 cache 與明確導覽的影響。

`magit-zap-caches` 也會清理 repository-local、host Git-version 與 blob 快取，並非只清可見性；這是使用者另外選擇的原生命令，不是停用本功能的自動步驟。

概況入口整合 `magit-status-jump` 的 `o` suffix 與現有 hints；用 status 上的 `j` 提示選單入口，M-x 作為必要且穩定的退路。整合必須可重載且不重複插入 suffix。具體 transient API 與衝突偵測在 plan 中固定。採用原生數量與按需 diffstat，比在每次 redisplay 計算數量或解析 XML 更容易維持語意與反應速度。

## Flagged concerns

- **實際互動仍待驗證（實作者）**：已取得 hidden／invisible 狀態，但沒有前後畫面、按鍵實測與延遲資料。Baseline 不足以宣稱已證實所有可用性缺陷或已改善。
- **共用 buffer 的視窗影響（實作者）**：摺疊共用而 point／header 依視窗；必須測試兩窗均在不同 hunk 的情境，不把 per-window rendering 誤當 per-window visibility。
- **套件版本與擴充（實作者）**：本地 Magit／magit-section 版本與 SHA 見 baseline。升級、Forge 或延遲 section 可能改變 tree；採用 API 前重查，遇未知節點保留原行為。
- **需求取捨（使用者）**：本草稿提議新 buffer 預設檔案概況；若使用者偏好原生初始展開，可停用預設並使用手動入口。Spec 尚未由使用者接受。

## Open questions carried from intent.md

1. **目前是否已有收合、主要困難何在？** 已確認群組收合使檔名隱藏；未取得主觀操作評分或實際截圖。設計針對可直接切到檔案層級的需求；實作驗收需比較原生與改善動線，不再聲稱 XML 已佔滿畫面。
2. **首次開啟與刷新如何兼顧手動狀態？** 提議新 buffer／新且無還原狀態的 section 使用初始規則，刷新交由 Magit 身分還原，手動命令才重設目標群組。依據是本地 section 建立與 visibility cache 的宣告，最終需 R6 驗證。
3. **原生統計與 hints 是否足夠？** 本草稿採用原生清單／群組數量與按需 diffstat，延伸既有 hints；不新增統計管線。以 R6 的可見資訊及返回概況操作驗收，若仍無法判斷提交範圍，再提出具體證據與獨立需求。
