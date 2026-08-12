# avy 優化建議（針對 ~/.emacs.d/lisp/init-editing.el 現況）

現況：只綁 C-: / M-g w / M-g l 三個入口，其餘 avy default。
場景：TTY-first（tmux + emacsclient -nw）、中英混用、常開 helpful/magit/eww/compile/org。

────────────────────────────────────────────────────────
完成狀態（2026-05-27 落地於 [lisp/init-editing.el](../../../lisp/init-editing.el)，commit 7340843）
────────────────────────────────────────────────────────

Tier A 全套：A1 ✓ A2 ✓ A3 ✓ A4 ✓ A5 ✓
Tier B：B1 ✓ B2 ✓ B3 ✓（綁 `M-g 2`，未用 `C-'`）／B4 知識點，無需 config
Tier C：C1 ✓ ／ C2 依建議不套
Tier D：D1/D2 依建議不套

────────────────────────────────────────────────────────
Tier A：高價值低成本（建議直接套）
────────────────────────────────────────────────────────

A1. [完成] avy-keys 改雙手 home row
    default `(a s d f g h j k l)` 偏左手；改 8 鍵雙手交替更快，且去掉 g/h
    可降低跟搜尋字元混淆。和 ace-window 既有的 aw-keys 一致，肌肉記憶共用。

A2. [完成] ace-link（GNU ELPA）
    Help / Info / EWW / Compilation / Magit / Org / Customize / Woman / Markdown
    等 buffer 按 `o` 直接 avy-跳到 link / URL / file ref。
    你 helpful + magit + 編譯輸出開很多，命中率高。

A3. [完成] avy-goto-symbol-1 綁 M-g s
    比 avy-goto-word-1 更貼程式碼：用 find-tag-default 抓 symbol 邊界，
    駝峰 / 底線不會被切斷。

A4. [完成] avy-resume 綁 M-g r
    重做上一次 avy（沿用上次輸入的字元），翻 code review / 文件時連跳超順。

A5. [完成] 把新加的命令塞進 pulsar-pulse-functions
    否則跳完不會 pulse，跟現有三個入口的行為一致。

──── diff sketch（在 init-editing.el 的 avy use-package 區塊）────

(use-package avy
  :bind (("C-:"   . avy-goto-char-timer)
         ("M-g w" . avy-goto-word-1)
         ("M-g l" . avy-goto-line)
         ("M-g s" . avy-goto-symbol-1)   ; A3
         ("M-g r" . avy-resume))         ; A4
  :custom
  (avy-keys '(?a ?s ?d ?f ?j ?k ?l ?\;)))  ; A1 — 雙手 home row，去掉 g/h

;; ace-link：在 help / info / eww / magit / org / compile / customize 按 `o` 跳 link
(use-package ace-link
  :init (ace-link-setup-default))   ; A2

;; pulsar 區塊裡擴充：
(dolist (fn '(avy-goto-char-timer
              avy-goto-line
              avy-goto-word-1
              avy-goto-symbol-1     ; A5
              avy-resume))          ; A5
  (add-to-list 'pulsar-pulse-functions fn))

────────────────────────────────────────────────────────
Tier B：中等價值（看口味）
────────────────────────────────────────────────────────

B1. [完成] (setq avy-timeout-seconds 0.3)   ; default 0.5
    avy-goto-char-timer 輸完字元後激活更貼手；輸入慢的話用 0.4 折衷。

B2. [完成] avy-zap（MELPA）：M-z 換 avy-zap-to-char-dwim
    比 native zap-to-char 強：跨大段 buffer 也能用 avy 標籤精準挑目標。
    (use-package avy-zap :bind ("M-z" . avy-zap-to-char-dwim))

B3. [完成] avy-goto-char-2 綁 C-' （或 M-g 2）  ── 實際採用 M-g 2
    兩字元輸入，候選集很小，常常一鍵就跳——比 avy-goto-char-timer
    在「我知道目標前兩個字」場景更精準少標籤。

B4. [知識點 / 無需 config] 內建 dispatch action 已有但你可能沒在用：
    選定 target 後按字母觸發動作，而不是直接跳。重點四個：
      t  teleport     ──── 把目標 word/sexp 「拉」過來你的游標位置
      m  mark         ──── 把游標跳過去並 set-mark（拉 region 神器）
      n  copy-this    ──── 複製目標 word/sexp 不移動游標
      Y  yank-line    ──── 把目標所在整行 yank 進當前位置
    不用改 config，只是值得知道——配合 avy-goto-char-timer 用最順。

────────────────────────────────────────────────────────
Tier C：依語言情境
────────────────────────────────────────────────────────

C1. [完成] ace-pinyin（MELPA）
    讓 avy-goto-char 用拼音首字母匹配漢字：跳「設計文件」按 `s` 也算候選。
    你 org-roam 在 ~/code/org-roam，中文筆記多時有感。
    (use-package ace-pinyin :init (ace-pinyin-global-mode 1))
    成本：候選集會變大；多數時候 avy-goto-char-timer 已足夠快。

C2. [未套用，依建議保持原狀] avy-style 'de-bruijn
    用 de Bruijn 序列產生標籤——可以「閉眼」連按；多數人覺得反而難用，
    不建議改 default，純記錄存在。

────────────────────────────────────────────────────────
Tier D：不建議
────────────────────────────────────────────────────────
    
D1. [未套用，依建議] (setq avy-background t)
    TTY 上會把整個 buffer 灰化，視覺壓力大、低對比反而難看標籤。保持 nil。

D2. [未套用，依建議] link-hint（vs ace-link）
    更通用，但每個 mode 要自己寫 dispatch；ace-link 內建覆蓋夠了，
    先用 ace-link，缺哪個 mode 再補。

────────────────────────────────────────────────────────
建議套用順序
────────────────────────────────────────────────────────

1. 先套 Tier A 全包（一次 commit），用一週看 avy-keys 雙手 home row 順不順。
2. 加 B2 (avy-zap) 跟 B3 (avy-goto-char-2) 試試；不順刪掉成本低。
3. 中文筆記多再考慮 C1 (ace-pinyin)。
4. B1 timeout 看打字速度自己微調。

新加套件需要 M-x my/package-refresh + 重啟（你的 init.el 不在啟動時 refresh archive）。
ace-link / avy-zap / ace-pinyin 都是 GNU ELPA 或 MELPA 純 elisp，沒有原生編譯依賴。
  * 
