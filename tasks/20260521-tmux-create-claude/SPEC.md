這是一份為您重新梳理並專業化的規格書 (Spec)。我幫您修正了原本的錯字（如 `pan`/`plan` 應為 `pane`），並將需求轉換為更精確的技術描述，方便您或開發者後續實作。

---

# 系統規格書 (Spec)：Emacs Lisp 整合 Tmux 與 Claude CLI

## 1. 目的與概述 (Objective)

開發一個 Emacs Lisp 指令 (Command)，允許使用者在 Emacs 內部觸發外部的 Tmux 操作。該指令將在當前的 Tmux 會話中建立一個垂直分割的窗格 (Vertical Split Pane)，為其動態命名，並自動於該窗格內啟動 `claude` 指令列工具。

## 2. 功能需求 (Functional Requirements)

1. **垂直分割窗格 (Vertical Split)**
* 指令觸發後，需呼叫 Tmux 執行垂直分割畫面。
* 預期行為應與 Tmux 預設快捷鍵 `Prefix + %`（通常為 `Ctrl+b %`）完全一致，將當前視窗左右對半切分。


2. **動態命名窗格 (Pane Naming)**
* 必須擷取新建立的 Tmux Pane ID。
* 將新建的窗格標題 (Pane Title) 或名稱動態設定為 `claude-{pane_id}`（例如：`claude-%2`）。


3. **自動執行指令 (Auto-execute Command)**
* 在成功建立並命名新窗格後，必須於該窗格內自動啟動並執行 `claude` CLI 應用程式。



## 3. 技術實作細節 (Implementation Notes)

* **Emacs Lisp 系統呼叫：** 將使用 Emacs Lisp 的 `shell-command` 或 `call-process` 函數來呼叫系統中的 `tmux` 執行檔。
* **Tmux CLI 參數建議：**
* 可使用 `tmux split-window -h` 來達到垂直分割的效果。
* 可搭配 `-P -F "#{pane_id}"` 參數讓 Tmux 回傳新建立的 Pane ID，以便 Emacs Lisp 擷取並組合字串。
* 可使用 `tmux select-pane -T "claude-{pane_id}"` 來設定窗格標題（需確保 tmux.conf 有開啟 `pane-border-status` 才看得到標題）。
* 執行指令可以直接接在 split-window 後面，例如：`tmux split-window -h "claude"`。



## 4. 邊界情況與錯誤處理 (Edge Cases)

* **非 Tmux 環境防呆：** 若使用者在未啟動 Tmux 的終端機環境或 GUI Emacs 中執行此指令，系統應跳出 `message` 提示使用者：「目前不在 Tmux 環境中，無法執行此指令」。
* **Claude 指令不存在：** 若系統環境變數 `$PATH` 中找不到 `claude`，Tmux 窗格可能會閃退，應確保 Emacs Lisp 執行前或 Tmux 執行時有相應的錯誤捕捉。

---

<!-- Local Variables: -->
<!-- gptel-model: gemini-pro-latest -->
<!-- gptel--backend-name: "Gemini" -->
<!-- gptel--system-message: "You are a large language model living in Emacs and a helpful assistant. Respond concisely." -->
<!-- gptel--tool-names: nil -->
<!-- gptel--bounds: nil -->
<!-- End: -->
