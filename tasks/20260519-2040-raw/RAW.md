# 幫我看emacs還有哪些配置能加入

## 環境

- Emacs 30.1
- 平台：Debian 13 / Linux 6.12（無頭 daemon + tmux TTY frame 為主，偶爾 GUI）
- 設定倉庫：`~/.emacs.d`（thin loader `init.el` + `lisp/init-<area>.el` × 15）
- `use-package-always-ensure t`、`no-littering`、`exec-path-from-shell`
- 啟動時**不**自動 refresh 套件庫（網路無感啟動）
- `M-x customize` 寫入 `custom.el`（init 不再有 `custom-set-variables`）
- GitHub-only 套件用 Emacs 30 native `:vc`（無 straight.el、無 quelpa）

## 已安裝套件（依模組分組）

### init-defaults — 內建預設值微調 + 一些 quality-of-life
- 內建：`delete-selection-mode`、`electric-pair-mode`、`global-so-long-mode`、`auto-save-visited-mode`（取代 `#autosave#`）、`global-auto-revert-mode`、`column-number-mode`、`pixel-scroll-precision-mode`、`repeat-mode`、`bookmark-save-flag=1`
- `gcmh`（自適應 GC，搭配 early-init 的 16MB floor）
- `which-key`（built-in，prefix 提示）
- `ibuffer`（綁 `C-x b`，因 tmux prefix 吃掉 `C-x C-b`）
- TTY OSC 52 clipboard bridge（`interprogram-cut-function`）

### init-system-packages
- `system-packages`（apt/brew 薄封裝，`M-x system-packages-*`）

### init-completion — Vertico ecosystem（minibuffer 主導 in-buffer completion）
- `vertico` + `vertico-directory`
- `orderless`
- `marginalia`
- `consult`（`C-x B`、`C-s`→`consult-line`、`M-y`、`M-g g/i/I/o/m/k/f`、`M-s r/f/L/k/u`）
- `embark` + `embark-consult`
- `wgrep`（可寫 grep buffer）
- `savehist`、`recentf`、`saveplace`（內建，已排除 var/etc/sudo/COMMIT_EDITMSG）

### init-corfu — 安裝但 dormant（in-buffer completion 走 Vertico）
- `corfu` + `corfu-popupinfo` + `corfu-terminal`（`global-corfu-mode` **沒開**）
- `cape`（`cape-dabbrev` / `cape-file` / `cape-elisp-block` 已掛 `completion-at-point-functions`）
- `completion-in-region-function = consult-completion-in-region`

### init-snippets
- `yasnippet`（`yas-global-mode`）
- `yasnippet-snippets`

### init-editing — 編輯體驗
- `avy`（`C-:` / `M-g w` / `M-g l`）
- `expand-region`（`C-=`）
- `multiple-cursors`（`C->` / `C-<` / `C-c C-<`）
- `rainbow-delimiters`
- `helpful`（`C-h f/v/k/x/o` 全換掉）
- `vundo`（`C-x u`，Unicode glyph）
- `hl-todo`
- `pulsar`（global，pulse on big motion；掛 consult/avy）
- `ace-window`（`M-o`，home-row keys）
- `popper`（`C-`` / `M-`` / `C-M-``；vterm/help/compile/magit-process/flymake-diagnostics 都歸 popup）
- `winner`（內建，`C-c <left>/<right>`）
- `breadcrumb`（header-line：project / file / class / function）
- `jinx`（`enchant-2`-backed 拼字，`M-$` / `C-M-$`，`global-jinx-mode` on after-init）

### init-languages — project / LSP / tree-sitter / 各語言
- `project`（內建，advice 避開 `$HOME` 當 project root；`project-vc-extra-root-markers` 含 `.project`、`Cargo.toml`、`go.mod`、`pyproject.toml`、`CLAUDE.md`、`package.json`、`Makefile`）
- `envrc`（direnv buffer-local 注入，`envrc-global-mode` on after-init）
- `eglot`（內建，hook：python / go / rust / js / typescript / tsx / css / html / json / c / c++）
- `eglot-booster`（`:vc`，jdtsmith/eglot-booster；`cargo install` 的 `emacs-lsp-booster` 後端）
- `consult-eglot`（`M-g s` workspace symbol，scoped to `eglot-mode-map`）
- `vue-mode`（不掛 Volar Eglot，配 tree-sitter modes）
- `ggtags`（GNU Global xref backend；hook：c / c++ / java / python；防呆 `tags-file-name nil`）
- `treesit-auto`（`treesit-auto-install t`，排除 `css` / `json` / `lua`，ABI 14 cap）
- `lua-mode`（regex-based，因 tree-sitter-lua ABI 15）
- `combobulate`（`:vc`，mickeynp/combobulate；hook：python / go / js / typescript / tsx；`C-c o` prefix）
- `flymake`（內建，`M-n` / `M-p`）
- `flymake-eslint`（hook：js / ts / tsx / vue；defer binary check）
- `apheleia`（async format-on-save；global mode；vue→prettier）
- `markdown-mode`（README → gfm-mode；`markdown-command "pandoc"`）
- eldoc：echo area + `display-buffer-alist` 把 `*eldoc for ...*` 釘到右側 60-col side window；`C-c d` 召喚

### init-git
- `magit`（`C-x g`，refine hunk on，`vc-handled-backends nil`，移除 untracked-files section）
- `diff-hl`（fringe，`prog-mode` + `magit-post-refresh`；**沒**用 `diff-hl-dired-mode`）
- `magit-todos`（`magit-todos-update nil`，手動 `j T` 重掃）
- `magit-delta`（git-delta 美化 magit diff，CLI 不受影響）
- `difftastic`（AST diff，append 到 magit-diff transient：`d D` / `d S`）

### init-terminal
- `vterm`（`C-c t`，scrollback 10000，`vterm-always-compile-module t`）

### init-appearance
- `doom-themes`（`doom-one`，bold + italic + org-config）
- `doom-modeline`（`doom-modeline-height 25`）
- `nerd-icons`（`:defer`，daemon-aware `server-after-make-frame-hook` 已 scaffold）

### init-dirvish
- `dirvish`（`dirvish-override-dired-mode`；`C-c f` / `C-c s`）
- `dired`（內建，`--almost-all --human-readable --group-directories-first`）
- attributes：`subtree-state` / `nerd-icons` / `collapse` / `file-time` / `file-size`（刻意**不**含 `vc-state` / `git-msg`）
- quick-access：`~/`、`~/.emacs.d/`、`~/.claude/`、`~/code/obsidian/`、`~/code/org-roam/`、`~/fenrir-tools/`
- `fdfind` 處理 >20k entries 的 dir

### init-org
- `org`（內建，`org-startup-indented`、`org-hide-emphasis-markers`、`org-src-fontify-natively`）
- `org-modern`（不改 table）
- `org-appear`（暫時露出 markup）

### init-obsidian
- `obsidian`（vault：`~/code/obsidian/`；`C-c n n/c/s`；in-vault `C-c C-o` / `C-c C-l`；`global-obsidian-mode` on after-init）

### init-org-roam
- `org-roam`（vault：`~/code/org-roam/`；`C-c r f/i/b/c/d`；capture template 含 tag prompt；dailies 在 root；`db-autosync-mode` on after-init）
- `org-roam-ui`（D3 browser graph + websocket + simple-httpd；`C-c r g`）

### init-ai
- `claude-jobs-view`（本地 elisp，`lisp/claude-jobs-view.el`，tabulated-list UI 包 `jobctl`；lazy autoload）
- `gptel`（backend：Claude / Gemini / OpenAI；預設 Gemini 2.5 Pro；`~/.authinfo` 存 key；`fenrir/gptel-set-api-key` helper）
- `eca`（Editor Code Assistant client，customize 安裝，尚未 wire 配置）
- `acp`（Agent Client Protocol library，customize 安裝）
- `shell-maker`（被 eca / acp 拉進來）

### 跨模組依賴 / transitive（看得到的）
- `transient`（magit + gptel 共用）
- `magit-section`
- `with-editor`
- `emacsql`（org-roam）
- `websocket`、`simple-httpd`（org-roam-ui）
- `compat`、`dash`、`s`、`f`、`ht`、`async`、`llama`、`cond-let`、`pcre2el`、`inheritenv`、`elgrep`、`elisp-refs`、`eldoc-box`（未啟用）、`edit-indirect`、`mmm-mode`、`ssass-mode`、`vue-html-mode`、`shrink-path`、`xterm-color`、`yaml`、`popon`

## 沒裝 / 沒啟用的東西（已知留白）

- 沒 `lsp-mode`（用 `eglot`）
- 沒 `company`（用 Vertico minibuffer 路徑，corfu 安裝但 dormant）
- 沒 `evil` / vim 模擬層
- 沒 `org-agenda` / `org-capture` 的設定（org 本身只開了基本三項）
- 沒 `flyspell`（被 `jinx` 取代）
- 沒 `undo-tree`（用 `vundo`）
- 沒 `treemacs` / `neotree`（用 `dirvish-side`）
- 沒 `projectile`（用內建 `project.el`）
- 沒 `eldoc-box`（雖然安裝在 elpa，但 TTY 為主，刻意走 side-window）
- 沒 `dap-mode` / `realgud` debugger 整合
- 沒 `verb` / `restclient`（HTTP client）
- 沒 `eat`（terminal，用 `vterm`）
- 沒 `denote`（用 `org-roam` + `obsidian.el`）
- 沒 `tempel`（snippet 走 `yasnippet`）
- 沒 `vterm-toggle` / popper-managed 但沒 toggle helper
- 沒 `pdf-tools` / `nov.el`（PDF / epub）
- 沒 `mu4e` / `notmuch` / `gnus`（mail）
- 沒 `elfeed`（feed reader）
- 沒 `erc` / `circe`（IRC）
- 沒 `telega` / `slack` / matrix client
- 沒 `crdt` / `zerolfs`（real-time collab）
- 沒 `eshell` 客製（vterm 為主）
- AI tooling：`eca` / `acp` 雖然裝了但**還沒有 use-package config**（無 keybinding，僅靠 `M-x`）
- 沒 `aider.el`（claude / gemini coding agent emacs UI）
- 沒 `copilot.el` / `codeium.el`

## 重點限制 / 顧慮（提建議時請納入）

- `$HOME` 本身是 git repo，且 `status.showUntrackedFiles=no` 隱藏 ~1M item，~1500 tracked file
  - 凡是會掃 `$HOME` 的東西（recursive find / vc walk / dired full-git-status）都要小心
  - 已關 `diff-hl-dired-mode`、`magit-todos-update`、移除 magit untracked section
- tmux TTY frame 為主場，**GUI-only**（child-frame、`posframe`）的功能很可能用不到（例如 `eldoc-box`、`vertico-posframe`、`corfu` popup）
- Emacs 30.1 的 tree-sitter ABI cap = 14，css/json/lua grammar 已是 ABI 15，自動排除
- 啟動時不 refresh archive — 加新套件要 `M-x my/package-refresh` + restart
- 倚賴一些外部 CLI：`gtags` / `global`、`enchant-2`、`direnv`、`fdfind`、`rg`、`delta`、`difft`、`pandoc`、`graphviz`、`prettier`、`eslint`、`gopls` / `pyright` / `rust-analyzer` / `typescript-language-server` / `vscode-langservers-extracted` / `clangd`、`emacs-lsp-booster`、`cmake` / `libvterm-dev`
- 私有 elisp：`lisp/claude-jobs-view.el`（`jobctl` 的 tabulated UI），未來想塞同質工具就走 `lisp/` + `:ensure nil`

請根據上面盤點，建議「合理的下一步補強」——優先順序大概是：
1. 已裝但**沒 wire**的（`eca` / `acp` 該怎麼配？）
2. 我目前真正在做的事（`org-roam` Zettelkasten、Claude/Gemini agent 開發、Go/TS/Rust/Python coding、`~/.emacs.d` daemon TTY-in-tmux）會明顯受益的補強
3. 不要建議跟我「已知留白」清單衝突的（例如不要叫我裝 `lsp-mode` / `projectile` / `flyspell` / `undo-tree`）
4. GUI-only / child-frame 路線盡量避開，或註明「TTY 用不到」
5. AI / agent 相關的 emacs 客戶端有沒有比 `gptel` 更值得加的（保留 `gptel` 不換）
6. 工具鏈外接 CLI 若需要請列出 apt / cargo / npm 安裝指令

<!-- Local Variables: -->
<!-- gptel-model: gemini-2.5-pro -->
<!-- gptel--backend-name: "Gemini" -->
<!-- gptel--system-message: "You are a large language model living in Emacs and a helpful assistant. Respond concisely." -->
<!-- gptel--tool-names: nil -->
<!-- gptel--bounds: nil -->
<!-- End: -->



``` reasoning
**Analyzing the User's Query**

I'm currently dissecting the user's Emacs configuration request. My initial step involves interpreting the core intent behind "幫我看emacs還有哪些配置 能加入." I need to understand what specific aspects of their Emacs setup they're open to enhancing. The goal is to provide targeted configuration suggestions.


**Prioritizing ECA/ACP Configuration**

I've identified the user's primary concern: configuring `eca` and `acp`, which now becomes my top priority. My analysis indicates a strong preference for enhancing existing workflows, particularly within Org-roam, AI development, and Go/TS/Rust/Python coding. The user's daemon/TTY environment also needs consideration. It's crucial to offer suggestions that complement the existing setup, avoiding conflicts with their established tools like `lsp-mode`.


**Focusing on ECA and ACP**

I'm deep-diving into configuring `eca` and `acp`. My research reveals that `eca-mode` should be activated within programming modes, providing commands for code assistance. I'm building a sample `use-package` block for this. Given the user's TTY focus, I'll prioritize command-line interactions for `eca` and `acp`. Next, I will think about how to bind the commands and suggest keybindings that align with their style, and not conflicting with the already defined keybindings.


**Refining Configuration and Keybindings**

I've crafted a sample `use-package` block with hooks to activate `eca-mode` in programming modes, which seems logical. My current focus is on keybindings for `eca` and `acp`. I'm leaning toward a `C-c a` prefix, avoiding conflicts, and mapping common actions like fixing, chatting, and explaining code. I'm also considering `C-c a f`, `C-c a c` and `C-c a e` for the corresponding commands. I'm also including information on external dependencies, such as `aider-chat` installation and running the server, and the connection setup using `eca-connect`.


**Refining Code Enhancements**

I'm now focusing on specific coding enhancements. The user's reliance on `vterm` suggests prioritizing REPL integration. I'll recommend `run-python` for seamless `ipython` integration, maintaining the TTY-first principle. Furthermore, I'll suggest mapping `eglot-code-actions`, potentially to `C-c .` or `C-c a a`, which offers refactoring capabilities through LSP integration, complementing existing tooling like `combobulate` and the active `flymake-eslint`. I also consider how to make snippets easily accessible.


**Enhancing Emacs for AI Dev**

I've been solidifying the `eca`/`acp` configuration, focusing on keybindings for common actions within programming modes. I'm now crafting a `use-package` block with hooks to activate `eca-mode`, and I am considering `C-c a` as the prefix. I will suggest `C-c a f`, `C-c a c` and `C-c a e` for fix, chat, and explain, alongside external dependency instructions. I'll include `aider-chat` installation.



**Refining Coding and AI Tools**

I'm solidifying the configuration of AI tools in Emacs. I have decided to recommend a `vterm` toggle function to improve the TTY integration. The `rg.el` package offers a convenient persistent results buffer, similar to `wgrep`, for improved integration with `consult`. I will include installation steps for `aider-chat` and the configuration for `eca-mode`.


**Enhancing Emacs for AI Dev**

I've been consolidating AI tool integration, emphasizing `copilot.el` alongside the `eca`/`acp` enhancements. I'm focusing on crafting a `use-package` block for `copilot.el` with hooks, keeping it TTY-friendly. I'll include setup instructions for Node.js, and how to connect to aider-chat. I'm also suggesting `vterm-toggle` for enhanced TTY integration.



**Refining Keybinding Configurations**

I've made progress in crafting a solid Emacs setup. Recent efforts have centered on finalizing the keybinding configuration for both `eca` and `acp`. I've chosen `C-c a` as the prefix, mapping frequently used actions like "fix", "chat," and "explain" to `C-c a f`, `C-c a c` and `C-c a e` respectively. I will need to consider keybindings in other modes, as well.



```

好的，你的配置相當現代且扎實，完全是 TTY-first power user 的風格。以下針對你的需求提出幾項補強建議，依優先序排列。

### 1. 啟用 ECA (Editor Code Assistant)

你已經安裝了 `eca` / `acp`，這是整合本地或遠端 AI agent 的標準協議。將它啟用能讓你直接在 buffer 內進行更複雜的 code-agent 互動。

- **用途**：對選定區域進行修復、重構、解釋、產生測試，或開啟一段對話。
- **後端 CLI**：需要一個 `acp` 相容的 agent server。`aider-chat` 是個好選擇。

```bash
# 安裝 aider-chat
pip install aider-chat

# 在一個獨立的 terminal 啟動 agent server
aider --acp-server --model gemini/gemini-1.5-pro-latest
```

- **Emacs 配置 (`lisp/init-ai.el`)**：

```elisp
(use-package eca
  :ensure nil ; already installed as a dependency
  :hook (prog-mode . eca-mode)
  :bind (:map eca-mode-map
              ("C-c a a" . eca-code-actions) ; Agent 提供的 Code Actions
              ("C-c a f" . eca-fix)          ; 修復選區
              ("C-c a e" . eca-explain)      ; 解釋選區
              ("C-c a t" . eca-generate-test); 產生測試
              ("C-c a c" . eca-chat)))       ; 開啟對話

;; 初次使用時，執行 M-x eca-connect 連接到 localhost:8000 的 agent server
```





好的，你的配置已經非常現代且精煉，完全符合 TTY-first power user 的風格。針對你的需求限制與工作流，以下是「合理且高回報」的下一步補強建議，依優先順序排列：

### 1. 啟用與配置 ECA / ACP (Editor Code Assistant)

既然已經安裝了 `eca` / `acp`，這是為了與外部 Agent（如 Aider）透過 Agent Client Protocol 溝通的套件。你需要將它綁定起來並啟動背景服務。

**外部依賴 (Agent Server)**
你需要跑一個支援 ACP 的 Server。最成熟的是 Aider：
```bash
pipx install aider-chat
# 在你的專案目錄或背景啟動 (預設監聽 localhost:8000)
aider --acp-server --model gemini/gemini-2.5-pro
```

**Emacs 配置 (`lisp/init-ai.el`)**
將 ECA 掛載到編程模式，並給它一個專屬的 prefix key（例如 `C-c a`）：

```elisp
(use-package eca
  :defer t
  :hook (prog-mode . eca-mode)
  :bind (:map eca-mode-map
              ("C-c a c" . eca-chat)       ; 開啟對話面板
              ("C-c a e" . eca-explain)    ; 解釋當前 function/region
              ("C-c a f" . eca-fix)        ; 讓 Agent 修復錯誤
              ("C-c a r" . eca-refactor)   ; 重構
              ("C-c a a" . eca-code-actions))
  :config
  ;; 如果 server 不在預設的 localhost:8000，可在此調整
  ;; (setq acp-server-host "127.0.0.1" acp-server-port 8000)
  )
```
*(注意：啟動 Emacs 後，若 Server 已在跑，執行 `M-x eca-connect` 即可連線。)*

### 2. 開發體驗 (Go/TS/Rust/Python) 補強

你在這幾個語言都有 Eglot 支援，但缺乏一些進階整合。

*   **`consult-flymake`**: 既然你用了 `consult` 和 `flymake`，這個指令能讓你用 Vertico 介面搜尋與跳轉當前 buffer/專案的 diagnostics，比 `M-n`/`M-p` 慢慢跳有效率得多。
    ```elisp
    ;; 在 init-completion.el 補上
    (keymap-global-set "M-g f" 'consult-flymake) ;; 搭配你的 M-g prefix
    ```
*   **`envrc` 整合 Eglot**: Eglot 有時會在 `direnv` 載入前就啟動，導致找不到 Lsp Server 或環境變數錯亂。
    ```elisp
    ;; 在 init-languages.el 的 envrc 配置加入
    (use-package envrc
      :hook (after-init . envrc-global-mode)
      :config
      ;; 確保 eglot 在 envrc 更新環境變數後才啟動/重啟
      (with-eval-after-load 'eglot
        (add-hook 'envrc-mode-hook #'eglot--envrc-reconnect)))
    ;; (需手動寫個 eglot--envrc-reconnect 函式，或簡單點：確保開啟檔案時先觸發 envrc)
    ```

### 3. Org-Roam Zettelkasten 補強

你主要使用 `org-roam` 搭配 `obsidian`。

*   **`consult-org-roam`**: 強烈建議加入！它將 Vertico 的強大過濾能力帶入 Org-Roam。它提供 `consult-org-roam-file-find` (支援即時預覽)、`consult-org-roam-search` (全文搜尋筆記內容，支援 `orderless`)。
    ```elisp
    (use-package consult-org-roam
      :ensure t
      :after org-roam
      :init
      (require 'consult-org-roam)
      (consult-org-roam-mode 1)
      :bind (:map org-roam-mode-map
                  ("C-c r s" . consult-org-roam-search)
                  ("C-c r f" . consult-org-roam-file-find)))
    ```

### 4. 工作區管理與終端機 (Daemon/TTY 友善)

*   **自製 `vterm-toggle` helper**: 你沒有用 `vterm-toggle`，但 `popper` 可以管理它。你可以寫一個簡單的 command 綁到 `C-``，如果沒有 vterm 就開一個，有的話就用 popper 彈出來。這對 TTY 非常實用。
    ```elisp
    ;; 在 init-terminal.el
    (defun my/toggle-vterm ()
      "Toggle vterm using popper."
      (interactive)
      (if (get-buffer "*vterm*")
          (popper-toggle-type (get-buffer "*vterm*"))
        (vterm)))
    (keymap-global-set "C-`" 'my/toggle-vterm)
    ```
*   **`rg` (rg.el)**: 你有用 `consult-line` 和 `wgrep`，但如果要做跨專案的大型搜尋與替換，`rg.el` 提供的結果 buffer (類似 compile buffer) 配合 `wgrep` 體驗比 `consult-ripgrep` 更好管理。
    *   *CLI: `apt install ripgrep` 或 `cargo install ripgrep`*

### 5. AI 工具選項評估 (Gptel vs. Aider vs. 其他)

*   **維持現狀為主**: `gptel` 是目前最好的「純文字互動/寫作」客戶端，而 `eca` + `aider` (如上述第1點) 是最好的「自動改 Code」組合。這兩者搭配已經是 Emacs 上頂級的 AI 工作流。
*   **可以考慮 `kagi.el` 或 `chatgpt-shell` (如果需要獨立 session)**：但既然你已經用了 `gptel` 和 `eca`，其實不需要再加其他大型 AI 套件。
*   如果你需要在程式碼中自動補全 (像 GitHub Copilot 那種 "ghost text")，在 TTY 環境下目前只有 **`copilot.el`** (非官方) 支援得比較好，但它需要 Node.js。如果你不需要自動補全，就保持留白。

### 總結建議動作清單：
1. `apt install ripgrep` (或 brew/cargo)
2. `pipx install aider-chat`
3. 加入 `eca` 的 keybindings 配置。
4. 加入 `consult-org-roam` 增強筆記搜尋。
5. 補上一個自製的 `vterm` toggle 函式配合你的 `popper`。

### 

<!-- Local Variables: -->
<!-- gptel-model: gemini-pro-latest -->
<!-- gptel--backend-name: "Gemini" -->
<!-- gptel--system-message: "You are a large language model living in Emacs and a helpful assistant. Respond concisely." -->
<!-- gptel--tool-names: nil -->
<!-- gptel--bounds: ((response (13603 17187))) -->
<!-- End: -->
