# Eglot 開發工具落差任務清單

> 由 `eglot-tooling-research` workflow 產出(2026-06-10,9 個 opus agent,8 個研究維度 + 1 個綜合)。
> 研究範圍:現代 Emacs 30+ 使用 eglot 開發時的完整工具生態,並對照本 repo 既有設定([`init-languages.el`](../../lisp/init-languages.el) 等)找出落差。

## 結論摘要

這套 Emacs 30.1 設定在幾乎每個維度都已達到或超過 2025-2026 的 eglot state-of-the-art:Eglot 升級到 GNU ELPA 1.23(原生 call/type hierarchy `C-c h c/t`、semantic-tokens 切換 `C-c h s`、inlay hints 全域開)、eglot-booster + 源碼編譯的 emacs-lsp-booster、consult-eglot(`M-g s`)、breadcrumb、ripgrep+consult-xref、eldoc 側欄、完整的 ggtags-as-xref fallback(含 `M-.` 中和與 GTAGS 衛生)、treesit-auto + 三個 ABI-14 grammar pin、combobulate(`C-c o`)、treesit-fold(`C-c z`)、expreg(`C-=`)、flymake + sideline-flymake(Error-Lens 風格、TTY 安全)、apheleia format-on-save、dape、tempel、eglot-x(Rust)、vtsls override、gptel + aidermacs。

**真正的落差很窄**,集中在:Python server 選型、幾個 no-server 導航 fallback、AI inline 補全,以及少數尚未實作的機會。多數任務因此是 verify/tune 而非新增。

---

## P0 — 明確落差 / 高價值升級

### 1. Python LSP 從預設 pyright 遷移到 basedpyright + ruff server  `[新增]`
[`init-python.el`](../../lisp/languages/init-python.el) 依賴 eglot 預設 server 解析:`:python` workspace 設定是 pyright 形狀,但沒有明確的 `eglot-server-programs` 條目,所以 eglot 撿 PATH 上任何 pyright。研究指出 **basedpyright** 是成熟的 Pyright fork 預設,而 **ruff-lsp 已棄用**,改用 `ruff server` 子指令。
- 動作:加 `eglot-alternatives` 條目,優先 `(basedpyright-langserver --stdio)` 其次 `(pyright-langserver --stdio)`。
- 工具:`basedpyright`、`ruff server`、`eglot-alternatives`

---

## P1 — 值得做的改善

### 2. Python format-on-save 從 black+isort 改為 ruff format  `[已有 apheleia,調整 recipe]`
[`init-languages.el`](../../lisp/init-languages.el) 的 apheleia 註解記錄 python → black + isort。研究標示 `ruff format` + ruff-isort 為單一 binary 的新預設。
- 動作:`apheleia-mode-alist` 對 `python-ts-mode` 加一行 override,與 basedpyright 遷移配套。
- 工具:apheleia recipe

### 3. 接上 dumb-jump 作為 xref graceful fallback  `[新增]`
研究指出 xref **不會跨 backend 自動 fallback**(eglot #420):eglot 回空時直接報錯而非試下一個 backend。本 repo 有 ggtags fallback,但只在有 `GTAGS` index 的地方生效。
- 動作:`dumb-jump` 設 `dumb-jump-prefer-searcher 'rg`(符合 repo 的 rg 規範),晚序加到 `xref-backend-functions`,讓未建索引的長尾也有 no-server `M-.`。
- 工具:`dumb-jump`、ggtags

### 4. 驗證 dape 各語言 debug adapter 已裝且 config 能啟動  `[已有 dape,驗證]`
dape 已接好([`init-languages.el`](../../lisp/init-languages.el)),但研究強調 Emacs 不附帶任何 adapter,全部 out-of-band。CLAUDE.md 確認目前只有 Go 的 `dlv` 在 PATH。
- 動作:確認 Rust/C++/Python/JS 的 adapter 是否解析、dape-configs 是否能啟動。非重接 dape。
- 工具:`dlv`、`codelldb`/`lldb-dap`、`debugpy`、`vscode-js-debug`

### 5. 驗證升級後的 Eglot 1.19+ hierarchy / semantic-tokens 綁定  `[已有,週期性驗證]`
升級依賴 fresh clone 上的一次性手動 `package-install`(`elpa/` 被 gitignore、`:ensure t` 無法升級 built-in),且 eglot-booster monkey-patch `eglot--connect`/`jsonrpc--json-read`。
- 動作:每次 Emacs/eglot 升版後,確認 `C-c h c/t` hierarchy 能 render、booster advice 仍 attach(`eglot-events-buffer` 有 `emacs_lsp_booster` 訊息)。
- 工具:eglot ≥1.19、eglot-booster + emacs-lsp-booster

---

## P2 — 加分項 / 觀望項

### 6. 加 symbol-overlay 做 server-free 出現處高亮 + 區域內快速 rename  `[新增]`
lisp/ 內無此套件。研究推薦為 LSP rename 的純語法補充:高亮 point 處符號、上下跳、buffer-local scope rename,在 eglot 關閉的非專案檔也能用。填補 `eglot-rename`(`C-c r`,全專案)與「同 buffer 快速改名」之間的空缺。低風險、TTY 安全。

### 7. 評估用 java-debug bundle + dape 開啟 Java 除錯  `[新增,評估]`
CLAUDE.md 與 dape block 明確標示 Java 除錯不支援。路徑:把 `com.microsoft.java.debug.plugin` JAR 經 eglot initializationOptions `:bundles` 載入 jdtls,再由 dape 透過 executeCommand 請 jdtls 起 session。[`init-java.el`](../../lisp/languages/init-java.el) 已擁有 jdtls launcher 與 initializationOptions 管線,缺的只是 bundle 注入。標評估是因 bundle-before-dape 的時序脆弱且版本耦合。

### 8. 加 as-you-type AI inline 補全(minuet-ai.el)與 capf 並存  `[新增]`
[`init-ai.el`](../../lisp/init-ai.el) 有 gptel(對話)與 aidermacs(repo-map agentic 編輯),但無 inline ghost-text/at-point LLM 補全。研究推薦 minuet-ai.el(GNU ELPA、provider-agnostic Claude/Gemini/Ollama——正是本設定已透過 authinfo 配置的 providers)優於 copilot.el。可作 capf 跑,契合既有 `C-<tab>` / consult-completion-in-region 路由。標 niche 因 corfu popup 刻意休眠。

### 9. 為大型 monorepo 微調 eglot request-throttling  `[已有,微調]`
設定已含研究中最高價值的開關(`eglot-events-buffer-config :size 0`、`eglot-autoshutdown t`、`eglot-sync-connect 1`、`eglot-extend-to-xref t` + eglot-booster)。尚未設的 `eglot-send-changes-idle-time`、`flymake-no-changes-timeout`、`jit-lock-defer-time` 可在 coinsasia/hitok2 重型 repo 上調高以減少 didChange/diagnostic 風暴。`eglot-stay-out-of` 備用於超大檔關閉 documentSymbol/semantic-tokens。

### 10. 確認 vtsls 仍為首選 TS server,觀望 tsgo / TypeScript 7 LSP  `[已有,觀望]`
[`init-typescript.el`](../../lisp/languages/init-typescript.el) 已有 vtsls override(gated on `executable-find`)。研究警告 vtsls 自身也在倒數——微軟原生 Go 版 tsgo / TypeScript 7 LSP 將至。保留 override,觀望穩定的 tsgo eglot recipe 出現後替換。

### 11. 驗證 Vue SFC server 設 `:hybridMode :json-false` 讓 eglot 驅動內嵌 tsserver  `[新增驗證]`
研究指出裸 eglot 無法多工 Volar hybrid mode,可行的單一 server 路徑是 `@vue/language-server` 配 `:vue (:hybridMode :json-false)` 跑內嵌 tsserver。[`init-vue.el`](../../lisp/languages/init-vue.el) 目前只接了 apheleia(prettier)。確認 Vue 的 `eglot-workspace-configuration` 有設 hybridMode false。

### 12. 追蹤 rass / eglot preset 多工生態(one-server-per-buffer 限制)  `[觀望]`
研究的核心 eglot 限制:一個 buffer 一個 server,無法同時跑 ruff(lint)與 basedpyright/ty(type-check),或 eslint 與 vtsls。新興解法是 rass 外部 multiplexer(eglot 作者專案)+ eglot-python-preset/eglot-typescript-preset,仍 beta、未進 ELPA core。本設定今天靠「lint 只走 LSP、format 走 apheleia」繞過。**僅觀望,勿將 beta 工具拉進這套穩定設定**,待 rass 穩定再回顧。

### 13. 考慮把 eglot/flymake context 餵進 LLM 的 gptel tools  `[新增,探索]`
研究的跨領域 AI 落差:沒有工具自動把 eglot 的即時 LSP context 注入模型;`gptel-make-tool` 是唯一橋樑且需 DIY。本設定已配 gptel + 豐富 eglot session,手寫包住 `flymake-diagnostics`/`xref-find-references`/consult-eglot 符號搜尋的 gptel tools,能讓助手讀 eglot 回報的錯誤並迭代。高工作量但本設定的 gptel + 重度 eglot 組合獨有條件。

---

## 研究涵蓋的 8 個維度
1. 語言伺服器(各語言預設最佳選擇、被取代者、eglot 專屬設定)
2. 補全 UI(corfu / cape / consult-eglot / vertico-orderless / kind-icons)
3. 大型專案效能(eglot-booster + emacs-lsp-booster、throttling)
4. 診斷 / lint / 格式化(flymake vs flycheck、sideline、apheleia)
5. 除錯(dape vs dap-mode、各語言 adapter)
6. tree-sitter(treesit-auto、combobulate、ABI 上限與 grammar pin、folding/movement)
7. 程式碼智能 / 導航(xref、breadcrumb、inlay hints、semantic tokens、call/type hierarchy、dumb-jump/ggtags)
8. AI / agentic(gptel、aidermacs、eca、copilot、minuet 及與 LSP context 的整合落差)
