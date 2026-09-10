# Intent: 改善 Magit status 的資訊概況與檢閱動線

Author: codex (agent)
Created: 2026-09-10
Status: draft

## Problem

使用者希望改善目前 Magit status UI 的資訊呈現，讓提交前檢閱更容易掌握檔案範圍、暫存狀態與細節入口。

2026-09-10（Asia/Taipei）透過本機 emacsclient 唯讀擷取使用者選取視窗的 buffer，取得 `magit: hedge-detection-root`、`magit-status-mode`，以及 buffer 開頭最多 24,000 字元。當時文字記錄包含 main 分支、1 個 untracked 檔案、1 個 unstaged 檔案、10 個 staged 檔案；第一個 staged XML diff 標頭為新增 1,658 行，測試報告記錄 179 tests、0 failures。這是歷史快照，不代表目前 Git 狀態或本次執行過測試。

證據限制：`buffer-substring-no-properties` 不保留不可見文字屬性，可能讀到已收合的 diff；本次未記錄實際畫面、可見區域、header-line 或 section 摺疊狀態。因此先前「XML 展開佔滿版面、其他檔案難以看完」屬待驗證推論，不能當成已確認 UI 缺陷。配色與字級亦未評估。

待調查的問題包括：是否容易取得全部檔案概況、長 diff 是否妨礙導覽、同一工作涉及 staged／unstaged 時是否容易漏看，以及現有操作提示是否清楚。不同工作主題同時存在不等於應一起提交；歷史測試報告也不能證明目前工作樹通過驗證。

## Proposed outcome

- 先在實際 TTY 與 GUI 視窗確認問題，記錄可見內容、視窗尺寸、摺疊狀態及既有操作提示，建立可比較的基準。
- 使用者可快速掌握分支、各暫存狀態的檔案清單與數量，並按需進入 diff；長測試報告不妨礙返回概況或定位下一檔案。
- 評估首次開啟時收合 diff、檔案增刪摘要、以及既有 header-line 提示的改善；依實際基準選擇必要方案，保留使用者手動展開與收合的操作意圖。
- 保持 staged、unstaged、untracked 的界線清楚，方便檢查提交範圍。只呈現可證實的資料，不自動推斷工作主題或測試結果對應版本。

候選驗收情境：在可丟棄的測試 repository 建立混合暫存狀態、同檔部分暫存、多檔變更及千行 XML diff；在 TTY 與 GUI 驗證首次開啟、刷新、展開、收合、跨檔導覽與返回概況。比較改善前後畫面與操作步驟，確認 Git index／工作樹內容不因顯示操作改變。

## Affected users and systems

擁有者為 `/home/fenrir/.emacs.d`，目前 main 分支追蹤 origin/main；此 intent 改善共用 daemon 的 Emacs 30.1 TTY／GUI Git 檢閱流程。相關設定位於 `lisp/init-git.el`，其中已有 `fenrir/magit-hints-mode`；實作前需核對已安裝 Magit 的行為。涉及按鍵路由時遵守 `lisp/init-keys.el` 最後載入的規則，工作流程異動同步 `FEATURES.md`。

`hedge-detection-root` 僅為本次觀察案例；其程式、文件、測試證據與 Git 暫存內容不屬於本 intent 的修改範圍。

## Constraints

- 本次授權為記錄改善 intent；使用者隨後以「submit」授權本機提交草稿。狀態仍為 draft，尚未接受、設計或實作。
- 優先採用 Magit 既有功能與本庫設定，保留原有 stage／unstage／discard 語意；不得隱藏 untracked section。
- 顯示優化不得自動暫存、取消暫存、提交或修改被檢閱專案。
- 不能從成功 XML 推論目前版本已驗證；報告摘要與版本證據格式若需變更，另由擁有該報告的專案處理。
- TTY 與 GUI 須在同一 daemon 共存；不以 batch 啟動成功代替互動畫面驗證。
- 保留摘要證據即可，不將完整業務 diff 或原始測試資料複製進 Emacs 設定庫。

## Open questions

- 實際畫面是否已有適當收合？主要困難是在概況、導覽、操作提示，或其他尚未觀察的視覺問題？
- 初次開啟與刷新應如何兼顧預設概況及手動摺疊狀態？
- 原生檔案／diff 統計與既有 hints 是否已足夠，哪些補充資訊能實際減少檢閱步驟？

## Validation of this capture

已核對本庫指引、main 的追蹤設定與 worktree 清單；既有 SDLC home 不存在，目的路徑未被 Git 忽略。此次只新增 intent 與文件入口，未修改 Emacs 設定；互動驗收留待後續階段。
