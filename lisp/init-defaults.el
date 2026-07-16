;;; init-defaults.el --- Better built-in defaults (no external packages) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 2 of the pre-split monolithic init.el (see git log for the move).
;; Tunes built-in Emacs behaviour, sets up the OSC 52 clipboard bridge for
;; TTY frames, points `custom-file' at custom.el, and wires `which-key' and
;; `ibuffer' (both built-in).  No third-party packages here.

;;; Code:

(use-package emacs
  :ensure nil
  :init
  ;; --- chrome ---
  ;; menu/tool/scroll bars are suppressed in early-init.el via
  ;; `default-frame-alist' so the first frame is painted without them.  Only
  ;; the startup-screen toggles belong here.
  (setq inhibit-startup-screen t)        ; straight to *scratch*
  (setq initial-scratch-message nil)
  ;; --- editing ---
  (setq-default indent-tabs-mode nil)    ; spaces, not tabs
  (delete-selection-mode 1)              ; typing replaces the active region
  (electric-pair-mode 1)                 ; auto-insert matching brackets/quotes
  (global-so-long-mode 1)                ; survive opening huge minified files
  ;; show-paren-mode is on by default (Emacs 28+); when the matching OPEN paren
  ;; is scrolled off the top of the window, echo that line in an overlay at
  ;; point -- so closing a long `})]' at the bottom of a function tells you what
  ;; it closes without scrolling up.  The modern-IDE "matching-bracket peek".
  (setq show-paren-context-when-offscreen 'overlay)
  ;; --- files / backups ---
  (setq make-backup-files nil)           ; no foo~ litter next to the file
  ;; Replace classic `#foo#' recovery autosaves with `auto-save-visited-mode'.
  ;; Classic auto-save writes to a SIDECAR file (`#foo#'), useful only when
  ;; Emacs crashes; for our workflow (frequent commits via Magit, no recent
  ;; recovery use) those sidecars are pure write churn -- the no-littering
  ;; redirection in init.el shovels them into `var/auto-save/' but they
  ;; still accumulate and the recovery-via-`M-x recover-this-file' path is
  ;; never reached.
  ;;
  ;; `auto-save-visited-mode' writes through to the VISITED file every
  ;; `auto-save-visited-interval' seconds of idle, so the on-disk file
  ;; matches the buffer.  Magit then picks up the change naturally as an
  ;; unstaged edit -- exactly the state `magit-status s' expects.  30 s is
  ;; conservative (VSCode default delay is ~5 s; 60 s is the "barely
  ;; auto-saves" end).  Tune in `M-x customize-variable
  ;; auto-save-visited-interval' if 30 s is too eager.
  ;;
  ;; Side effect: `init.el's no-littering :config no longer needs the
  ;; `auto-save-file-name-transforms' form (removed in the same commit) --
  ;; with `auto-save-default nil', nothing writes `#foo#' files anywhere.
  ;; Stale ones under `var/auto-save/' can be deleted by hand later.
  (setq auto-save-default nil)
  (setq auto-save-visited-interval 30)
  (auto-save-visited-mode 1)
  (setq create-lockfiles nil)            ; no .#foo lockfiles
  (global-auto-revert-mode 1)            ; reload buffers when files change on disk
  (setq global-auto-revert-non-file-buffers t) ; ...including Dired
  ;; --- niceties ---
  (column-number-mode 1)                 ; show column in the modeline
  (setq use-short-answers t)             ; y/n instead of yes/no
  (setq ring-bell-function 'ignore)      ; no audible bell
  (setq sentence-end-double-space nil)
  ;; bookmark-save-flag = 1: persist `bookmark-set' / `bookmark-rename' /
  ;; `bookmark-delete' to the bookmarks file IMMEDIATELY, not on Emacs exit.
  ;; In daemon mode the "on exit" path effectively never fires (daemon stays
  ;; alive across `emacsclient' sessions; a SIGKILL / power cut loses
  ;; everything you set since launch).  no-littering already redirects the
  ;; on-disk bookmarks file under `var/bookmark'.
  (setq bookmark-save-flag 1)
  ;; pixel-scroll-precision-mode (Emacs 29+, GUI-only): mouse wheel /
  ;; touchpad scrolls per-pixel instead of jumping 5 lines per tick.
  ;; `fboundp' guard so a hypothetical older Emacs still loads this module;
  ;; the mode silently no-ops in TTY frames (`emacsclient -t' inside tmux).
  (when (fboundp 'pixel-scroll-precision-mode)
    (pixel-scroll-precision-mode 1))
  ;; repeat-mode (built-in, Emacs 28+): after a prefixed command like `C-x o',
  ;; pressing the LAST key (`o', `o', `o') keeps invoking it without re-typing
  ;; the `C-x' prefix.  Also works for `C-x ^' (enlarge-window) etc.  Pure
  ;; ergonomics win, no setup beyond turning it on.
  (repeat-mode 1)
  ;; set-mark-command-repeat-pop: after ONE `C-u C-SPC' (pop local mark ring)
  ;; or `C-x C-SPC' (pop-global-mark), a bare `C-SPC' keeps popping the same
  ;; ring -- so "jump back through recent positions" becomes C-SPC C-SPC C-SPC
  ;; instead of re-typing the prefix each time.  The initial keystroke still
  ;; needs the prefix; only the repeats are bare.  Kin to `repeat-mode' above.
  (setq set-mark-command-repeat-pop t)
  ;; Put `M-x customize' output in its own file rather than appending to this
  ;; one.  (The block at the bottom of this file pre-dates this and is kept
  ;; for compatibility; new customisations go to custom.el.)
  (setq custom-file (expand-file-name "custom.el" user-emacs-directory))
  (when (file-exists-p custom-file) (load custom-file)))

;; Terminal clipboard bridge: in a TTY frame Emacs' default cut path is GUI-only,
;; so `M-w' fills the internal kill-ring but nothing outside Emacs sees it.
;; Emit OSC 52 on every cut; tmux's `set-clipboard on' in
;; [.tmux.conf](../.tmux.conf) relays the escape to the outer terminal, which
;; writes the real system clipboard.  Works across SSH; no xclip/wl-copy needed.
;; The TTY check happens at cut time, not load time -- under a daemon
;; `display-graphic-p' is nil at init.el load (no frame exists yet), so a
;; load-time guard would install this for GUI clients too and `C-w' in a GUI
;; frame would crash with "Device N is not a termcap terminal device".
;;
;; GUI frames must still reach the X/Wayland clipboard, so dispatch on frame
;; type here.  Installing this as `interprogram-cut-function' unconditionally
;; would otherwise displace the default `gui-select-text' and break C-w/M-w
;; on every GUI frame served by the daemon.
(defun fenrir/osc52-copy (text)
  (if (eq (framep (selected-frame)) t)   ; t = TTY frame; x/w32/ns/pgtk = GUI
      (let ((b64 (base64-encode-string (encode-coding-string text 'utf-8) t)))
        (send-string-to-terminal (format "\e]52;c;%s\a" b64)))
    (gui-select-text text)))
(setq interprogram-cut-function #'fenrir/osc52-copy)

;; External clipboard push: callable via `emacsclient --eval' from outside.
;; Routes around two quirks of this config:
;;   (1) `kill-new' alone misses the system clipboard in GUI mode -- the
;;       OSC 52 override above displaces the default `gui-select-text' path,
;;       so we re-dispatch on frame type here.
;;   (2) Shell quoting around `emacsclient --eval' breaks on `$' / backticks /
;;       newlines / unbalanced quotes -- the `-from-file' variant routes the
;;       payload through the filesystem instead of argv.
;; Returns the character length of the pushed string so the caller can
;; verify arrival + size from the eval result.
(defun fenrir/clipboard-push (text)
  "Push TEXT onto the kill-ring AND to the system clipboard.
Designed for `emacsclient --eval' callers."
  (kill-new text)
  (cond
   ((display-graphic-p) (gui-select-text text))
   (t                   (fenrir/osc52-copy text)))
  (length text))

(defun fenrir/clipboard-push-from-file (path)
  "File-payload variant of `fenrir/clipboard-push'.
Use when payload has newlines / quotes / `$' / backticks -- those survive
the filesystem round-trip but not `emacsclient --eval' argv quoting."
  (fenrir/clipboard-push
   (with-temp-buffer
     (insert-file-contents path)
     (buffer-string))))

;; gcmh: Garbage Collector Magic Hack.  Replaces the fixed post-startup
;; `gc-cons-threshold' (16 MB floor set in `early-init.el') with an adaptive
;; scheme: raise the threshold to a high "interactive" value while you're
;; typing / scrolling / running commands, then drop it back and sweep once
;; Emacs has been idle for `gcmh-idle-delay' seconds.  Net result: zero
;; perceptible GC pauses during heavy work (`consult-ripgrep' through 100k
;; matches, `magit-refresh' on a big repo, `eglot' hover on a complex
;; struct), with memory still bounded because the idle sweep DOES run.
;;
;; `gcmh-idle-delay 'auto' lets gcmh pick the idle delay from the most-
;; recent GC time -- short for cheap GCs, longer for expensive ones --
;; instead of forcing a single fixed value.  Upstream default.
;;
;; First-run note: as with every use-package block here, the archive is not
;; refreshed at startup (see init.el §1).  After this commit lands, run
;; `M-x my/package-refresh' then restart the daemon once so gcmh installs.
(use-package gcmh
  :init (gcmh-mode 1)
  :custom (gcmh-idle-delay 'auto))

;; which-key: after a prefix key (C-x, C-c, ...) pops up a panel listing the
;; follow-up keys.  Built into Emacs 30 -- hence :ensure nil.
;;
;; TTY-first tuning (no posframe/child-frame -- those are GUI-only):
;;   * `idle-delay 0.2' makes the first popup feel near-instant without
;;     flashing when a chord is typed quickly.
;;   * `idle-secondary-delay 0.05' keeps subsequent prefixes in the same
;;     chain snappy once the panel is already up.
;;   * `show-prefix 'echo' moves the "M-g-" label to the echo area so the
;;     side-window stays a clean two-column key/command grid.
;;
;; Searchable bindings: with `prefix-help-command' set to
;; `embark-prefix-help-command' (see :config below), pressing `C-h' AFTER
;; a prefix opens a vertico minibuffer listing only that prefix's bindings
;; -- type to filter.  Acts as "search inside which-key".  `C-h B' from
;; anywhere still lists every active binding via `embark-bindings'.
(use-package which-key
  :ensure nil
  :init (which-key-mode 1)
  :custom
  (which-key-idle-delay 0.2)
  (which-key-idle-secondary-delay 0.05)
  (which-key-side-window-location 'bottom)
  (which-key-side-window-max-height 0.5)
  (which-key-side-window-max-width 0.5)
  (which-key-min-display-lines 8)
  (which-key-max-description-length 36)
  (which-key-separator " → ")
  (which-key-prefix-prefix "+")
  (which-key-show-prefix 'echo)
  (which-key-sort-order 'which-key-prefix-then-key-order)
  (which-key-add-column-padding 1)
  ;; Don't let which-key's own C-h dispatch swallow the prefix help binding --
  ;; we want C-h after a prefix to go straight to `embark-prefix-help-command'.
  (which-key-use-C-h-commands nil)
  :config
  ;; Built into Emacs 28+: when you hit a prefix then `C-h', Emacs delegates
  ;; to whatever this variable points at.  Embark's version pops a vertico
  ;; minibuffer with that prefix's bindings as candidates.
  (with-eval-after-load 'embark
    (setq prefix-help-command #'embark-prefix-help-command))
  ;; Friendly labels for the personal `C-c' prefixes, so the which-key panel
  ;; reads "g -> gtags" etc. on the FIRST `C-c' keypress instead of only
  ;; becoming legible once you continue the chord and see raw command names.
  ;; `C-c r', `C-c o' and `C-c t' are deliberately excluded: each is bound to
  ;; a genuinely different thing depending on which minor-mode keymap is
  ;; active in the current buffer (e.g. `C-c r' is eglot-rename in an
  ;; eglot-managed buffer but the org-roam prefix map elsewhere) -- a single
  ;; global label would misdescribe whichever meaning isn't showing.
  (which-key-add-key-based-replacements
    "C-c a" "aider"
    "C-c B" "dired-sidebar"
    "C-c D" "docker"
    "C-c e" '("theme" . "ef-themes light/dark toggle")
    "C-c g" '("gtags" . "GNU Global build/diagnose/nav")
    "C-c G" '("git-extras" . "git-link / timemachine / blamer")
    "C-c h" '("eglot-hier" . "call/type hierarchy, inlay hints, tokens")
    "C-c j" "claude-jobs"
    "C-c m" '("smerge" . "merge-conflict resolution")
    "C-c q" '("question-queue" . "ask / set queue dir")
    "C-c R" '("rust" . "cargo build/test/clippy/run")
    "C-c s" '("symbol-overlay" . "highlight & navigate occurrences")
    "C-c S" "string-inflection"
    "C-c v" '("git-hunk" . "diff-hl next/prev/show/revert/stage")
    "C-c W" '("workspace" . "tabspaces")
    "C-c z" '("treesit-fold" . "tree-sitter code folding")))

;; ibuffer: replace the default `switch-to-buffer' on `C-x b' with ibuffer
;; (grouping, marking, batch operations).  `C-x C-b' is avoided because tmux'
;; default prefix is `C-b' and swallows the second keystroke in a TTY frame.
(use-package ibuffer
  :ensure nil
  :bind ("C-x b" . ibuffer))

(provide 'init-defaults)
;;; init-defaults.el ends here
