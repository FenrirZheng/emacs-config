;;; init-keys.el --- Keybinding routing policy: measure, hub, repeat -*- lexical-binding: t; -*-

;;; Commentary:
;; This module does NOT add features.  Every command it mentions is already
;; configured somewhere else in `lisp/'.  What it adds is a *routing policy*
;; for the scarcest resource in this config: muscle memory.
;;
;; The problem it answers (see [tasks/keybinding-strategy.md](../tasks/keybinding-strategy.md)):
;; coding here touches Eglot/xref, symbol-overlay (`C-c s'), git-extras
;; (`C-c G'), smerge (`C-c m'), devdocs (`C-c k'), the sidebar (`C-c B'),
;; tabspaces (`C-c W'), vterm (`C-c T'), docker (`C-c D'), consult (`M-s'/`M-g')
;; ... plus tmux prefix keys and keyd layers.  Recall fails exactly when focus
;; is on the code rather than on the keys.  Adding *more* discoverability
;; tooling was not the fix -- which-key, embark (`C-h B') and repeat-mode were
;; already on.  The fix is to decide, per command, WHICH OF THREE TIERS it
;; lives in, so only one tier needs memorising:
;;
;;   TIER 1 -- muscle memory, hard cap ~15 chords.  Only commands used many
;;             times per HOUR earn a direct chord.  Which 15 is decided by
;;             MEASUREMENT, not taste: `keyfreq' (below) records real usage and
;;             `fenrir/keyfreq-report' ranks it.  Nothing in this file assigns
;;             Tier 1 -- the existing chords in the other modules already are
;;             the candidates; the monthly review promotes/demotes them.
;;
;;   TIER 2 -- ONE memorised key, `<f5>', opening a `transient' hub grouped by
;;             SCENARIO ("I want to navigate / diagnose / refactor ...") rather
;;             than by package.  This is the whole point of the module: the hub
;;             DUPLICATES the existing `C-c <letter>' prefixes, it never
;;             replaces them, so a Tier-1 user bypasses it for free while a
;;             half-remembered command is still two keys away.
;;             `casual-suite' extends the same idea into the built-in modes.
;;
;;   TIER 0 -- the exception that proves the policy: when an intent is
;;             frequent AND fragmented across several mechanisms, no tier
;;             assignment helps, because the cost is the CLASSIFICATION, not
;;             the chord.  The cure is to merge the mechanisms behind one
;;             gesture.  Done once so far, for "go back where I was"
;;             (`<f6>'/`<f7>', the BACK-NAVIGATION section below).
;;
;;   TIER 3 -- no key at all.  Long-tail commands get good NAMES instead:
;;             `M-x string infl' beats recalling `C-c S' once you use it less
;;             than daily.  Nothing to configure -- Vertico + orderless +
;;             `embark-bindings' (`C-h B') already are Tier 3.
;;
;; Load position: LAST in `init.el'.  The hub and the repeat maps reference
;; command SYMBOLS from every other module; symbols need no definition at load
;; time, but loading last keeps the dependency direction honest (this module
;; reads the rest of the config, nothing reads this one).

;;; Code:

;; --------------------------------------------------------------- TIER 1 ---
;; Measurement.  The "cap 15" list is worthless if it is guessed, so record
;; what actually gets pressed and let the data pick the survivors.
;;
;; `keyfreq-mode' counts commands (not keys) per major mode in a hash table;
;; `keyfreq-autosave-mode' flushes it to `keyfreq-file' every
;; `keyfreq-autosave-timeout' seconds so a daemon restart / power cut doesn't
;; lose the window.  no-littering already redirects `keyfreq-file' to
;; `var/keyfreq.el' (verified in no-littering.el), so no path setting here.
(use-package keyfreq
  :config
  ;; Exclusions.  keyfreq matches these against the COMMAND NAME
  ;; (`keyfreq-match-p' -> `symbol-name'), and without them
  ;; `self-insert-command' alone is ~90% of every session -- which makes the
  ;; percentage column in the report useless and buries the chords the tier
  ;; policy is actually about.  Everything excluded here is a key that is
  ;; never a candidate for eviction (you are not going to forget `C-f'), so
  ;; dropping it loses no decision-relevant signal.  To measure them anyway,
  ;; `setq keyfreq-excluded-commands nil' and restart.
  (setq keyfreq-excluded-commands
        '(self-insert-command
          org-self-insert-command
          forward-char backward-char
          next-line previous-line
          forward-word backward-word
          delete-backward-char backward-delete-char-untabify
          newline newline-and-indent
          keyboard-quit
          minibuffer-keyboard-quit
          ignore))
  ;; Mouse / wheel events arrive as commands too and are pure noise here.
  (setq keyfreq-excluded-regexp
        '("\\`\\(?:mouse\\|mwheel\\|scroll\\|pixel-scroll\\)"))
  (keyfreq-mode 1)
  (keyfreq-autosave-mode 1))

(defun fenrir/keyfreq-report ()
  "Show the command-frequency report that decides the TIER 1 chord list.
The monthly ritual (see the module commentary): read the top of this
buffer, keep at most ~15 chords as muscle memory, and mentally demote
everything below that line to the `<f5>' hub (TIER 2) or to `M-x' +
`embark-bindings' (TIER 3).  Then refresh the daily card at the top of
[FEATURES.md](../FEATURES.md) from what the data actually says.

Wraps `keyfreq-show' because that command is NOT autoloaded -- calling it
from a fresh session without the `require' fails with a void function."
  (interactive)
  (require 'keyfreq)
  (keyfreq-save-now)                    ; report the current window, not the last flush
  (call-interactively #'keyfreq-show))

;; --------------------------------------------------------------- TIER 2 ---
;; One entry key, scenario menus.

;; combobulate's entry command is NOT autoloaded (only `combobulate-mode' and
;; `combobulate-query-builder' are -- checked in combobulate-autoloads.el), and
;; its menu is meaningless without a tree-sitter parser in the buffer.  So the
;; hub routes through this wrapper instead of naming `combobulate' directly.
(defun fenrir/combobulate-dwim ()
  "Open combobulate's structural-editing menu for this buffer.
Enables `combobulate-mode' first if needed, and refuses in a buffer with
no tree-sitter parser (combobulate navigates the parse tree -- without one
it has nothing to move over)."
  (interactive)
  (unless (and (fboundp 'treesit-parser-list) (treesit-parser-list))
    (user-error "No tree-sitter parser in this buffer -- combobulate needs one"))
  (require 'combobulate)
  (unless (bound-and-true-p combobulate-mode)
    (combobulate-mode 1))
  (call-interactively #'combobulate))

;; The hub itself.  `transient' is an `elpa/' package pulled in by magit /
;; gptel, but nothing loads it at STARTUP (magit is deferred behind `C-x g'),
;; so defining the prefixes at top level here would drag transient into every
;; boot for a menu that may never be opened.  Instead: the prefixes are defined
;; inside `with-eval-after-load', and `<f5>' is bound to a thin wrapper that
;; `require's transient on first press -- which runs that body, defining
;; `fenrir/hub--dispatch' before the wrapper calls it.  Same
;; "require transient only on the lazy path" trick as `fenrir/hideshow-menu'
;; in [init-editing.el](init-editing.el), just with a manual trigger because a
;; global key has no package to hang a `:config' off.
(defun fenrir/hub ()
  "Open the personal scenario hub (TIER 2 -- the one key worth memorising).
Groups every-day commands by WHAT YOU ARE TRYING TO DO (navigate /
diagnose / git / refactor / workspace / AI) rather than by which package
provides them, so a half-remembered command is `<f5>' + a letter + a
letter away instead of a recalled chord.  Everything in here is also
still on its own `C-c' chord -- the hub duplicates, never replaces."
  (interactive)
  (require 'transient)
  (call-interactively #'fenrir/hub--dispatch))

(global-set-key (kbd "<f5>") #'fenrir/hub)
;; TTY fallback: some terminal/tmux combinations swallow or remap the function
;; keys, and `<f5>' is unrecoverable when it never reaches Emacs.  `C-c ?'
;; (verified free) reaches the same hub, and reads as "help" next to the tmux
;; `prefix + ?' cheat sheet.
(global-set-key (kbd "C-c ?") #'fenrir/hub)

(with-eval-after-load 'transient

  (transient-define-prefix fenrir/hub-navigate ()
    "Get somewhere: definitions, symbols, in-buffer jumps, project search."
    [["Definitions (LSP / xref)"
      ("." "Definition"          xref-find-definitions)
      ("/" "References"          xref-find-references)
      ("," "Back"                xref-go-back)
      ("s" "LSP symbols"         consult-eglot-symbols)]
     ["In this buffer"
      ("i" "Imenu"               consult-imenu)
      ("I" "Imenu (project)"     consult-imenu-multi)
      ("l" "Line"                consult-line)
      ("j" "Avy jump menu"       casual-avy-tmenu)]
     ["Back where I was"
      ("c" "Last change"         goto-last-change)
      ("m" "Global mark ring"    pop-global-mark)
      ("b" "Breadcrumb jump"     breadcrumb-jump)]
     ["Project"
      ("r" "Ripgrep"             consult-ripgrep)
      ("f" "Find file"           project-find-file)
      ("q" "Quit"                transient-quit-one)]])

  ;; The "back" menu is worded by INTENT, never by the store's name: at the
  ;; moment of use you know "I want the other file", not "I want the global
  ;; mark ring".  Layer 1 (`<f6>'/`<f7>') is listed first and labelled with its
  ;; real keys so the menu teaches its own obsolescence; the four native
  ;; mechanisms below it are the ~10% escape hatch.  `:transient t' on the
  ;; steppers so a second press keeps walking instead of reopening the menu.
  (transient-define-prefix fenrir/hub-back ()
    "Go back where I was -- by intent, not by which ring stores it."
    [["One merged history (recommended)"
      ("<" "Back      (<f6> / M-g b)" fenrir/back    :transient t)
      (">" "Forward   (<f7> / M-g B)" fenrir/forward :transient t)]
     ["...or say which kind of back"
      ("b" "earlier position in this file"     pop-to-mark-command :transient t)
      ("f" "the file I was in before"          pop-global-mark     :transient t)
      ("d" "where I jumped from (definition)"  xref-go-back        :transient t)
      ("e" "where I last edited"               goto-last-change    :transient t)]
     ["Pick from a list"
      ("l" "this file"                         consult-mark)
      ("L" "all files"                         consult-global-mark)
      ("x" "flip between two points"           exchange-point-and-mark)
      ("q" "Quit"                              transient-quit-one)]])

  (transient-define-prefix fenrir/hub-diagnose ()
    "Find out what is wrong / what something means."
    [["Errors"
      ("e" "Flymake list"        consult-flymake)
      ("E" "Buffer diagnostics"  flymake-show-buffer-diagnostics)
      ("p" "Project diagnostics" flymake-show-project-diagnostics)]
     ["Docs for the thing at point"
      ("h" "Hover card"          fenrir/eldoc-box-dwim)
      ("d" "Eldoc buffer"        eldoc-doc-buffer)
      ("k" "DevDocs (offline)"   devdocs-lookup)]
     ["Codebase"
      ("t" "TODOs (buffer)"      consult-todo)
      ("T" "TODOs (project)"     consult-todo-all)
      ("g" "gtags index check"   fenrir/gtags-diagnose)
      ("q" "Quit"                transient-quit-one)]])

  (transient-define-prefix fenrir/hub-git ()
    "Ask git something about this file or this repo."
    [["Repo"
      ("g" "Magit status"        magit-status)
      ("d" "Magit dispatch"      magit-dispatch)
      ("f" "File dispatch"       magit-file-dispatch)]
     ["History of this file"
      ("b" "Blame"               magit-blame)
      ("B" "Inline blame toggle" blamer-mode)
      ("l" "File log"            magit-log-buffer-file)
      ("t" "Time machine"        git-timemachine)]
     ["Uncommitted hunks"
      ;; `:transient t' so n/p keep stepping without reopening the menu -- the
      ;; menu equivalent of the `C-c v n' repeat-map in init-git.el.
      ("n" "Next hunk"           diff-hl-next-hunk     :transient t)
      ("p" "Prev hunk"           diff-hl-previous-hunk :transient t)
      ("s" "Show hunk"           diff-hl-show-hunk)
      ("y" "Copy permalink"      git-link)
      ("q" "Quit"                transient-quit-one)]])

  (transient-define-prefix fenrir/hub-refactor ()
    "Change the shape of code rather than its content."
    [["LSP (eglot)"
      ("r" "Rename"              eglot-rename)
      ("a" "Code actions"        eglot-code-actions)
      ("i" "Organize imports"    eglot-code-action-organize-imports)
      ("x" "Extract"             eglot-code-action-extract)]
     ["Text"
      ("c" "Cycle case style"    string-inflection-all-cycle)
      ("f" "Format buffer"       apheleia-format-buffer)
      ("o" "Occurrences menu"    casual-symbol-overlay-tmenu)]
     ["Structure"
      ("s" "Combobulate"         fenrir/combobulate-dwim)
      ("z" "Fold toggle"         treesit-fold-toggle)
      ("e" "Edit comment block"  separedit)
      ("q" "Quit"                transient-quit-one)]])

  (transient-define-prefix fenrir/hub-workspace ()
    "Rearrange the frame: workspaces, side panels, terminals."
    [["Workspaces (tabspaces)"
      ("s" "Switch / create"     tabspaces-switch-or-create-workspace)
      ("o" "Open project"        tabspaces-open-or-create-project-and-workspace)
      ("b" "Workspace buffer"    tabspaces-switch-to-buffer)]
     ["Panels"
      ("B" "File sidebar"        dired-sidebar-toggle-sidebar)
      ("i" "Imenu sidebar"       imenu-list-smart-toggle)
      ("p" "Popup toggle"        popper-toggle)
      ("w" "Ace window"          ace-window)]
     ["Shells & display"
      ("t" "vterm toggle"        vterm-toggle)
      ("D" "Docker"              docker)
      ("G" "GUI popups toggle"   fenrir/gui-popups-toggle)
      ("q" "Quit"                transient-quit-one)]])

  (transient-define-prefix fenrir/hub-ai ()
    "Reach the AI tooling without remembering which prefix owns it."
    [["In-buffer"
      ("c" "Copilot (this buffer)" copilot-mode)]
     ["Sessions"
      ("j" "Claude jobs"         claude-jobs-view)
      ("a" "Aidermacs menu"      aidermacs-transient-menu)
      ("g" "gptel menu"          gptel-menu)]
     ["Question queue"
      ("Q" "Ask (region + text)" question-queue-ask)
      ("D" "Set queue dir"       question-queue-set-dir)
      ("q" "Quit"                transient-quit-one)]])

  (transient-define-prefix fenrir/hub--dispatch ()
    "Scenario hub -- see `fenrir/hub'."
    [["I want to..."
      ("n" "Navigate   jump, symbols, search" fenrir/hub-navigate)
      ("b" "Back       where was I?"          fenrir/hub-back)
      ("d" "Diagnose   errors, docs, TODOs"   fenrir/hub-diagnose)
      ("g" "Git        status, blame, hunks"  fenrir/hub-git)]
     [""
      ("r" "Refactor   rename, format, fold"  fenrir/hub-refactor)
      ("w" "Workspace  tabs, panels, shells"  fenrir/hub-workspace)
      ("a" "AI         copilot, claude, aider" fenrir/hub-ai)]
     ["Escape hatches"
      ;; TIER 3 lives here: when even the scenario is unclear, search the
      ;; bindings (`embark-bindings', also on `C-h B') or the edit-kit menu.
      ("e" "Edit kit (casual)"   casual-editkit-main-tmenu)
      ("p" "Project kit"         casual-editkit-project-tmenu)
      ("?" "Search all bindings" embark-bindings)
      ("k" "Key frequency report" fenrir/keyfreq-report)
      ;; Config self-audits (init-audit.el) -- rarely pressed, so they live
      ;; here rather than costing a chord.
      ("F" "FEATURES.md drift"   fenrir/features-audit)
      ("U" "Package usage audit" fenrir/package-usage-audit)
      ("q" "Quit"                transient-quit-all)]]))

;; ------------------------------------------------- BACK-NAVIGATION (L1) ---
;; ROUTING ONLY.  The merged jump history itself (the `push-mark' advice, the
;; 32-marker ring, `fenrir/back' / `fenrir/forward', `fenrir/back-forward-mode'
;; and the whole rationale for not using the `backward-forward' package) lives
;; in [`fenrir-back-forward.el'](fenrir-back-forward.el) -- this file adds no
;; features, it only loads that library and assigns the keys.  Loading it also
;; turns the mode on, gated by `fenrir/back-forward-enable' (nil = off switch).
(require 'fenrir-back-forward)

;; Keys.  `<f6>'/`<f7>' sit next to the `<f5>' hub, are single presses, and
;; were verified free.  `M-[' / `M-]' were rejected: in a TTY frame `M-['
;; arrives as `ESC [', the CSI introducer that starts every arrow-key escape
;; sequence -- unusable while this daemon still serves `emacsclient -nw'.
;; `M-g b' / `M-g B' are the terminal fallback (same doubling as `<f5>' and
;; `C-c ?'), inside the existing "goto" prefix so no namespace grows.
(global-set-key (kbd "<f6>") #'fenrir/back)
(global-set-key (kbd "<f7>") #'fenrir/forward)
(define-key goto-map (kbd "b") #'fenrir/back)
(define-key goto-map (kbd "B") #'fenrir/forward)

;; casual-suite: pre-built transient menus for the BUILT-IN modes (dired,
;; ibuffer, isearch, Info, re-builder, bookmarks, agenda, calc, ...).  Same
;; Tier-2 idea as the hub, but for the "I know this mode can do it, not which
;; letter" case -- and free, because upstream wrote the menus.
;;
;; Bound to `C-o' IN EACH MODE MAP (upstream's own convention), never globally:
;; `C-o' is `open-line' in an editing buffer and that stays untouched.  It does
;; displace two rarely-used commands -- `dired-display-file' and
;; `ibuffer-visit-buffer-other-window-noselect' -- both of which are still
;; reachable from inside the casual menu itself, so nothing is lost.
;;
;; Why `with-eval-after-load' rather than `use-package :bind (:map ...)': these
;; keymaps belong to OTHER packages (dired, ibuffer, ...), so binding into them
;; must wait for those packages, not for casual-suite.  The menu commands are
;; autoloaded, so the first `C-o' press pulls casual in.
(use-package casual-suite
  :defer t
  :init
  (dolist (entry '((dired          . (dired-mode-map          . casual-dired-tmenu))
                   (ibuffer        . (ibuffer-mode-map        . casual-ibuffer-tmenu))
                   (isearch        . (isearch-mode-map        . casual-isearch-tmenu))
                   (info           . (Info-mode-map           . casual-info-tmenu))
                   (re-builder     . (reb-mode-map            . casual-re-builder-tmenu))
                   (bookmark       . (bookmark-bmenu-mode-map . casual-bookmarks-tmenu))
                   (org-agenda     . (org-agenda-mode-map     . casual-agenda-tmenu))
                   (calc           . (calc-mode-map           . casual-calc-tmenu))
                   (compile        . (compilation-mode-map    . casual-compile-tmenu))
                   (eww            . (eww-mode-map            . casual-eww-tmenu))
                   (image-mode     . (image-mode-map          . casual-image-tmenu))
                   (man            . (Man-mode-map            . casual-man-tmenu))))
    (let ((feature (car entry))
          (map-sym (car (cdr entry)))
          (cmd     (cdr (cdr entry))))
      (with-eval-after-load feature
        (when (boundp map-sym)
          (define-key (symbol-value map-sym) (kbd "C-o") cmd))))))

;; ------------------------------------------------- repeat-mode extensions ---
;; `repeat-mode' is already on (init-defaults.el).  Each repeat map deletes N
;; chords from the recall budget for the price of one `defvar-keymap :repeat'.
;;
;; ALREADY BUILT IN -- do NOT re-add these, Emacs 30.1 ships them and they are
;; live in this config (verified via `(get COMMAND 'repeat-map)'):
;;   * `other-window-repeat-map'      -- `C-x o' then `o' `o' `o'
;;   * `resize-window-repeat-map'     -- `C-x ^' / `{' / `}' then bare repeats
;;   * `tab-bar-switch-repeat-map'    -- tab-bar next/prev
;;   * `tab-bar-move-repeat-map', `winner-repeat-map', `undo-repeat-map',
;;     `next-error-repeat-map'
;; Only the two below were genuinely missing.

;; repeat-exit-timeout: a repeat map stays armed until you press a key that is
;; NOT in it -- with no time limit by default.  That is fine for letter keys
;; (`o' after `C-x o') but a real trap for the punctuation keys the xref map
;; below wants: minutes after an `M-,' you type a literal `.' and teleport up
;; the xref stack instead.  Three seconds is long enough to walk a stack
;; deliberately and short enough that the next thing you type is just text.
;; Applies to the built-in maps too (other-window, resize-window, tab-bar,
;; winner, undo) -- intentionally, for the same reason.
(setq repeat-exit-timeout 3)

;; xref stack hopping: `M-.' into a definition, then `M-,' back -- and walking
;; several frames back up the stack meant re-typing `M-,' each time.  With this
;; map the first `M-,' (or `M-?') arms it and bare `,' / `.' walk the stack.
(defvar-keymap fenrir/xref-repeat-map
  :doc "Repeat map for walking the xref stack (see `repeat-mode')."
  :repeat t
  "," #'xref-go-back
  "." #'xref-go-forward)

;; symbol-overlay occurrence hopping: after `C-c s n' (or `p'), bare `n'/`p'
;; step through the remaining occurrences.  Exactly the diff-hl hunk pattern in
;; init-git.el, applied to the "highlight usages in file" gesture.
(defvar-keymap fenrir/symbol-overlay-repeat-map
  :doc "Repeat map for symbol-overlay occurrence navigation (see `repeat-mode')."
  :repeat t
  "n" #'symbol-overlay-jump-next
  "p" #'symbol-overlay-jump-prev)

;; Merged back/forward history: after the first `<f6>' (or `M-g b'), bare `b'
;; and `f' keep walking it.  Retracing several jumps is the common case -- one
;; press rarely lands where you meant -- and this is what makes the pair feel
;; like a browser's Back button rather than a chord.
(defvar-keymap fenrir/back-forward-repeat-map
  :doc "Repeat map for the merged jump history (see `fenrir/back')."
  :repeat t
  "b" #'fenrir/back
  "f" #'fenrir/forward)

(provide 'init-keys)
;;; init-keys.el ends here
