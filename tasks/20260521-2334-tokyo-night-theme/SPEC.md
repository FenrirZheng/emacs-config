# 修改規格書 (Spec)：Emacs 外觀調整 — Tokyo Night 主題、透明背景、isearch-fail 配色

## 1. 目的與概述 (Objective)

將 Emacs 的視覺外觀統一為 Tokyo Night 色調,共三項變更:

1. 佈景主題由 `doom-one` 切換為 `doom-tokyo-night`。
2. 視窗背景改為透明 — TTY 與 GUI 各自處理。
3. 增量搜尋失配時的 `isearch-fail` face,由 doom-themes 預設的紅色改為 Tokyo Night 橘色。

涉及檔案:[`lisp/init-appearance.el`](../../lisp/init-appearance.el)、[`custom.el`](../../custom.el)。

## 2. 功能需求 (Functional Requirements)

### 2.1 佈景主題切換

* 檔案:[`lisp/init-appearance.el`](../../lisp/init-appearance.el)
* 變更:`use-package doom-themes` 的 `:config` 中,`(load-theme 'doom-one t)` → `(load-theme 'doom-tokyo-night t)`。
* `doom-tokyo-night` 已隨 `doom-themes` 套件附帶,無需額外安裝。

### 2.2 透明背景

* 檔案:[`lisp/init-appearance.el`](../../lisp/init-appearance.el)
* 透明背景屬「逐 frame」設定 — daemon 每開一個 `emacsclient` frame 都必須重跑,因此實作於既有的 `fenrir/setup-frame`(掛在 `server-after-make-frame-hook`)。
* 行為依 frame 類型分流:
  * **TTY**:將 `default` face 的背景設為魔術值 `"unspecified-bg"`,使 Emacs 不再自行塗背景,讓終端機 / compositor 的透明透出。
  * **GUI**:設定 frame 參數 `alpha-background`(Emacs 29+),僅背景半透明、文字與 face 維持不透明。
* 新增 `defvar fenrir/gui-alpha-background`(預設 `90`)作為 GUI 透明度的可調旋鈕。

### 2.3 isearch-fail 配色

* 檔案:[`custom.el`](../../custom.el)
* 於 `custom-set-faces` 區塊新增 `isearch-fail` override:
  * 背景:`#ff9e64`(Tokyo Night 橘)
  * 前景:`#414868`(Tokyo Night `base0`,深色,確保橘底上對比足夠)
  * 字重:`bold`(沿用 doom-themes 原設計)
* 寫入的是 `user` theme,優先序高於任何已載入的 doom 主題,故覆寫不受載入順序影響。

## 3. 技術實作細節 (Implementation Notes)

* **為何透明背景放在 `fenrir/setup-frame`**:`load-theme` 在 daemon 啟動時只跑一次(主題是全域的,正確);但 frame 專屬設定(font / face / `alpha-background`)必須對每個新 frame 重跑,否則新 frame 會繼承 daemon 的 pre-init 預設值。`fenrir/setup-frame` 已透過 `server-after-make-frame-hook` 處理此情境。
* **`"unspecified-bg"` 的原理**:終端機 face 系統將此字串視為特殊值,代表「不指定背景色」,Emacs 因而略過背景繪製,露出底層終端的像素 — 這正是 TTY 透明的標準作法。
* **`alpha-background` vs `alpha`**:`alpha-background` 只讓背景半透明,文字保持清晰;`alpha` 會讓整個 frame(含文字)淡化。此處選用前者。
* **isearch-fail 紅色來源**:`doom-themes-base.el` 將 `isearch-fail` 定義為 `:background error`(主題的紅色變數)。所有 doom 主題皆繼承此 base 定義,故需以 `user` theme 覆寫,而非修改套件檔(`elpa/` 被 gitignore,套件更新會被覆寫)。

## 4. 邊界情況與注意事項 (Edge Cases)

* **TTY 透明的前提**:`"unspecified-bg"` 只是「不繪製背景」,真正的透明效果需終端機模擬器本身已開啟透明背景,或有 compositor 支援;否則僅顯示終端預設背景色。在 tmux 中需確認未設定 `window-style` / `pane-style` 背景色。
* **目前 frame 不會自動套用透明**:`fenrir/setup-frame` 僅掛於「新 frame」hook;對 reload 當下既有的 frame,需手動 `M-: (fenrir/setup-frame)` 或重開 frame。
* **`custom.el` 註解可能被覆寫**:日後若執行 `M-x customize` 並存檔,customize 會重寫整個 `custom-set-faces` 區塊 — face 設定本身保留,但手寫的說明註解會被清除。

## 5. 套用方式 (Apply)

無需重啟 daemon:

* 主題 + 透明背景:`M-x load-file RET lisp/init-appearance.el RET`,當下 frame 再補 `M-: (fenrir/setup-frame)`。
* isearch-fail 配色:`M-x load-file RET custom.el RET`,即時生效於所有 frame。
