# Features & cheat sheet

What this Emacs 30.1 config actually gives you, grouped by workflow. Each section
points to the module file under [`lisp/`](lisp/) where the relevant config lives.
For the package list and *why* each choice was made, read the comments in those
modules (and in [`init.el`](init.el)'s bootstrap block) — this file is the "what
keys do I press" companion.

Language-specific guides (architecture, workflows, troubleshooting):

- [Go development](_doc/GO.md) — `go-ts-mode` + Eglot + gopls + Vertico-driven completion

> Conventions in the tables: `C-x` = Ctrl+x, `M-x` = Alt/Meta+x, `C-S-x` = Ctrl+Shift+x,
> `SPC` = space, `RET` = Enter. Built-in packages are marked **(built-in)** — they ship
> with Emacs 30 and the config only enables/configures them.

---

## 0. Keybinding policy — three tiers and the `<f5>` hub ([`init-keys.el`](lisp/init-keys.el))

**Read this before memorising anything below.** The rest of this file is ~1000 lines of
bindings; nobody holds that. The policy, implemented in
[`init-keys.el`](lisp/init-keys.el) (rationale:
[`tasks/keybinding-strategy.md`](tasks/keybinding-strategy.md)), is to decide per command
which of three tiers it lives in, so only one tier needs memory:

| tier | what earns it | how you reach it |
|---|---|---|
| **1 — muscle memory** | used many times per *hour*. Hard cap ~15 chords, chosen from measured usage | the chord itself |
| **2 — one key** | everything you use but don't press constantly | **`<f5>`** (or `C-c ?`) → scenario menu; `C-o` inside built-in modes |
| **3 — no key** | fires less than once a day | `M-x <part of the name>`, or `C-h B` to search every live binding |

### The `<f5>` scenario hub (Tier 2)

One key, then a letter, then a letter. Grouped by *what you're trying to do*, not by
which package provides it. Every command in the hub is **also** still on its own `C-c`
chord — the hub duplicates, it never replaces, so Tier-1 habits keep working.

| key | scenario | contains |
|---|---|---|
| `<f5> n` | **Navigate** | definition / references / xref back, LSP symbols, imenu (buffer + project), consult-line, avy menu, last change, global mark ring, breadcrumb jump, ripgrep, project find-file |
| `<f5> b` | **Back** | the merged history (`<f6>`/`<f7>`), plus the four native "backs" listed *by intent* — this file / the file before / where I jumped from / where I last edited — and the two list pickers (see [below](#going-back-where-you-were)) |
| `<f5> d` | **Diagnose** | flymake list (buffer + project), hover card, eldoc buffer, DevDocs, TODOs (buffer + project), gtags index check |
| `<f5> g` | **Git** | magit status / dispatch / file-dispatch, blame, inline blame, file log, time machine, hunk next/prev/show (repeats in place), copy permalink |
| `<f5> r` | **Refactor** | eglot rename / code actions / organize-imports / extract, case-style cycle, format buffer, occurrences menu, combobulate, fold toggle, edit comment block |
| `<f5> w` | **Workspace** | tabspaces switch/open/buffer, file sidebar, imenu sidebar, popup toggle, ace-window, vterm toggle, docker, GUI popup toggle |
| `<f5> a` | **AI** | copilot (this buffer), claude jobs, aidermacs, gptel, question queue ask / set dir |
| `<f5> e` / `p` | Edit kit / Project kit | `casual-editkit` menus — the generic "what can I do here" fallbacks |
| `<f5> ?` | Search all bindings | `embark-bindings` (same as `C-h B`) |
| `<f5> k` | Key frequency report | `fenrir/keyfreq-report` — the Tier-1 review (below) |

`C-c ?` is the same hub, for terminals that swallow function keys. `q` closes any of the
menus; `C-g` also works.

### `C-o` — casual menus inside built-in modes (Tier 2)

`casual-suite` supplies ready-made transient menus for modes whose native keys are
unmemorable. Bound to **`C-o` in the mode's own map only** (`open-line` in a normal
buffer is untouched): `dired`, `ibuffer`, `isearch`, `Info`, `re-builder`,
`bookmark-bmenu`, `org-agenda`, `calc`, `compilation`, `eww`, `image-mode`, `Man`.
It displaces `dired-display-file` and `ibuffer-visit-buffer-other-window-noselect`, both
still reachable from inside the menu.

### Going back where you were

**One gesture: `<f6>` back, `<f7>` forward** (`M-g b` / `M-g B` in a terminal that eats
function keys). Then bare `b` / `f` keep walking (repeat map). It is a browser Back button:
one merged history of every far jump — searches, `M-.`, `M-<`/`M->`, the `consult-*`
family, buffer switches that push a mark — with no ring-vs-stack decision to make first.
A new jump truncates the forward branch, as in every IDE.

The reason it exists: Emacs ships **four** unrelated back-histories, and the cost was never
the chord, it was having to classify *which kind of back you meant* before any key was
correct. The distinction is still worth knowing for the ~10% of presses where `<f6>` lands
somewhere you didn't mean — that's what `<f5> b` is for, worded by intent:

| what you want | native key | `<f5> b` | store | ring or stack? |
|---|---|---|---|---|
| earlier position in **this** buffer | `C-u C-SPC`, then bare `C-SPC` | `b` | buffer-local `mark-ring` (max 16) | **ring** — cycles, never empties |
| the **file** I was in before | `C-x C-SPC` | `f` | `global-mark-ring`, one slot per *buffer* | **ring** (max 16) |
| where I jumped **from** (`M-.`) | `M-,` (forward: `C-M-,`) | `d` | xref marker stack | **stack** — does empty |
| where I last **edited** | `C-c ;` (reverse: `C-c '`) | `e` | undo records | linear, edit-only |
| pick from a list, this file / all files | `M-g m` / `M-g k` | `l` / `L` | `consult-mark` / `consult-global-mark`, with preview | — |
| **delete** a mark from those lists | `C-. d` on the candidate | — | embark action `fenrir/mark-ring-delete` ([`init-completion.el`](lisp/init-completion.el)) — drops it from both rings; reopen the list to see the result | — |
| flip between two points | `C-x C-x` | `x` | point ↔ mark | not a history |

Implementation: [`init-keys.el`](lisp/init-keys.el) advises `push-mark` once (every far jump
funnels through it) and keeps a 32-entry marker ring. `fenrir/back-forward-enable` → nil is
the one-line off switch; strategy and the rejected alternatives are in
[`tasks/back-navigation-strategy.md`](tasks/back-navigation-strategy.md).

### Tier 1 is measured, not chosen

`keyfreq` records every command (per major mode) from startup and flushes to
`var/keyfreq.el`. `M-x fenrir/keyfreq-report` (or `<f5> k`) saves the current window and
shows the ranking.

- `self-insert-command`, single-char motion, mouse/wheel events are **excluded** — they'd
  be ~90% of the table and they're never eviction candidates anyway.
- **Monthly ritual**: read the top of the report, keep ≤15 chords as muscle memory,
  mentally demote the rest to Tier 2/3, then refresh the card below.

### Daily card — top keys

> **Status: not yet measured.** `keyfreq` was enabled 2026-07-30; this list is the
> *provisional* Tier-1 candidate set from the strategy doc, **not** frequency data.
> Replace it with the real top-15 after ~2 weeks of collection (`<f5> k`).

| key | command |
|---|---|
| `M-.` / `M-?` / `M-,` | definition / references / back (then bare `,` `.` keep walking the stack) |
| `<f6>` / `<f7>` | back / forward across **all** jump histories (then bare `b` `f`); `M-g b` / `M-g B` on a terminal |
| `M-x` | run anything by name (Tier 3's entire mechanism) |
| `C-.` | embark act on the thing at point |
| `C-s` | `consult-line` search this buffer |
| `M-s r` | `consult-ripgrep` search the project |
| `C-x B` | fuzzy buffer switcher (`C-x b` is ibuffer) |
| `C-x g` | magit status |
| `M-o` | ace-window |
| `C-x C-s` | save |
| `<f5>` | the hub — everything else |
| `C-b` (tmux) | tmux prefix; `prefix + ?` is the tmux cheat sheet |

### Repeat maps — chords you don't need to re-type

`repeat-mode` is on globally. After the first invocation, the **bare** last key repeats
until you press something else or 3 s pass (`repeat-exit-timeout`, set in
[`init-keys.el`](lisp/init-keys.el) so punctuation repeat keys can't ambush you later).

| after | bare repeat keys | where |
|---|---|---|
| `<f6>` / `<f7>` (merged jump history) | `b` back, `f` forward | [`init-keys.el`](lisp/init-keys.el) |
| `M-,` / `M-?` (xref) | `,` back, `.` forward | [`init-keys.el`](lisp/init-keys.el) |
| `C-c s n` / `p` (symbol-overlay) | `n` / `p` | [`init-keys.el`](lisp/init-keys.el) |
| `C-c v n` (diff-hl hunks) | `n` `p` `s` `r` | [`init-git.el`](lisp/init-git.el) |
| `C-c m n` / `p` (smerge conflicts) | `n` / `p` | [`init-git.el`](lisp/init-git.el) |
| `M-n` / `M-p` (flymake errors) | `n` / `p` | [`init-languages.el`](lisp/init-languages.el) |
| `C-x o`, `C-x ^`/`{`/`}`, tab-bar switch/move, `winner-undo`, `undo`, `next-error` | Emacs 30 built-ins, already live — nothing added here | built-in |

### One prefix per layer (cross-tool)

keyd does **physical remapping only** (no leader layer), tmux owns `C-b`, Emacs owns
`C-c` plus `<f5>`. A fourth namespace is the disease, not the cure. The tmux layer has
its own curated sheet on **`prefix + ?`** (`~/.tmux/cheat.txt`; the full `list-keys` dump
moved to `prefix + M-?`).

---

## 1. Minibuffer: finding things (Vertico ecosystem — [`init-completion.el`](lisp/init-completion.el))

Five small orthogonal packages replace Helm/Ivy/ido: **vertico** (vertical candidate
list), **orderless** (space-separated, any-order fuzzy match), **marginalia** (docstrings
/ file sizes / perms beside candidates), **consult** (richer commands), **embark** (act on
a candidate).

| Key | Command | What it does |
|---|---|---|
| `C-x b` | `ibuffer` **(built-in)** | Buffer list with grouping, marking, batch ops. `RET` opens, `o` opens in another window, `D` kills, `m` mark + `S`/`D`/`Q` save/kill/query-replace marked, `/` filter, `q` quit. Bound here instead of the default `C-x C-b` because tmux's `C-b` prefix swallows the second keystroke in a TTY frame |
| `C-x B` | `consult-buffer` | Switch buffer **with live preview**; also lists recent files, bookmarks. Shifted off the default `C-x b` to make room for ibuffer above |
| `C-x 4 b` | `consult-buffer-other-window` | …opening the pick in another window |
| `C-x p b` | `consult-project-buffer` | Buffer switch scoped to the current project |
| `C-x r b` | `consult-bookmark` | Jump to a bookmark with preview |
| `C-s` | `consult-line` | Search lines in this buffer (incremental, jumps live) |
| `M-s L` | `consult-line-multi` | Same, but across every open buffer at once |
| `M-s r` | `consult-ripgrep` | **ripgrep across the whole project** |
| `M-s f` | `consult-find` | Find files by name |
| `M-s k` | `consult-keep-lines` | Filter the current buffer down to lines matching a pattern (destructive — undoable with `C-/`) |
| `M-s u` | `consult-focus-lines` | Hide non-matching lines via overlays (non-destructive toggle — call again to reveal) |
| `M-g g` | `consult-goto-line` | Go to line number |
| `M-g i` | `consult-imenu` | Jump to a definition in this file (functions / classes …) |
| `M-g I` | `consult-imenu-multi` | Same, but across every open buffer with the same major mode |
| `M-g o` | `consult-outline` | Jump to a heading in outline-minor-mode / Org / Markdown |
| `M-g m` | `consult-mark` | Jump to a recent mark in this buffer — beats hammering `C-u C-SPC` |
| `M-g k` | `consult-global-mark` | Same, but across **all** buffers — recover "where was I before that detour?" |
| `M-g f` | `consult-flymake` | List diagnostics with consult preview (`C-u` for project-wide); pairs with the LSP/flymake stack in §7 |
| `M-g e` | `consult-eglot-symbols` | **Project-wide LSP symbol jump** (LSP buffers only — bound in `eglot-mode-map`). Unlike `M-g I` (open buffers, same major mode), this hits the LSP's `workspace/symbol` index so unopened files are found too. Not `M-g s` — avy already owns that globally for `avy-goto-symbol-1`. See §7 |
| `M-y` | `consult-yank-pop` | Browse the whole kill-ring (not just paste the last entry) |
| `<` | — | Inside the above commands, `<` *narrows* to one source (e.g. only buffers, not recents) |

- **Fuzzy matching**: `orderless` lets `foo bar` match candidates containing both tokens
  in any order. The built-in file-name style is kept so partial paths still work
  (`/u/s/b` → `/usr/share/bin`).
- **Path editing in the minibuffer** (`vertico-directory`, **built-in** extension): while
  editing a filename, `RET` descends into the directory under point, `DEL` deletes back to
  the previous `/`, `M-DEL` deletes a whole path component. `//` and `~/` shadows collapse
  automatically.
- **History**: `savehist` **(built-in)** persists minibuffer history across sessions and
  floats recent picks to the top.
- **Cursor back-navigation (mark ring, built-in)** — for the everyday "just go back" case
  use `<f6>` / `<f7>`, which merge all four histories into one gesture
  ([§0](#going-back-where-you-were)). The `M-g m` / `M-g k` pickers above are the nice
  preview front-end; the raw keys below are worth knowing for quick "flip back and forth"
  reading and for the times you specifically want *this* ring:
  - Drop a manual anchor at point with `C-SPC C-SPC` (set mark, then deactivate the region).
  - Step back through *this buffer's* recent positions with `C-u C-SPC`; step back *across
    buffers* with `C-x C-SPC` (`pop-global-mark`).
  - `set-mark-command-repeat-pop t` (set in [`init-defaults.el`](lisp/init-defaults.el))
    means only that **first** keystroke needs the prefix — a bare `C-SPC C-SPC …` then keeps
    popping the same ring, so back-nav is as light as `repeat-mode`.
  - Many "far jump" commands (`C-s`, `M-.`, `M-<` / `M->`, `consult-*`) auto-push a mark, so
    the ring fills as you move — no manual anchoring needed for those. The **global** ring
    keeps just one slot per buffer (a cross-file trail, so `M-g k` shows ~one row per file),
    capped at 16 (`global-mark-ring-max`). For fixed anchors that never get pushed out, use a
    register (`C-x r SPC a` / `C-x r j a`) or a bookmark (`C-x r b`).
- **Preview debounce**: expensive previewers (`consult-ripgrep`, `consult-grep`,
  `consult-find`, `consult-bookmark`, `consult-recent-file`) wait 200 ms of input idle
  before re-rendering — keeps typing in a large project from queueing a ripgrep per
  keystroke. Tune via `consult-customize` in [`init-completion.el`](lisp/init-completion.el).

---

## 2. ⭐ Combo — project-wide search-and-replace with undo ([`init-completion.el`](lisp/init-completion.el))

The payoff of consult + embark + wgrep wired together:

```
M-s r          ; consult-ripgrep — search the project
C-.            ; embark-act → choose  E  (embark-export) → matches become a grep buffer
C-c C-p        ; wgrep — make that buffer editable
               ; …edit freely, across as many files as the matches span
C-c C-c        ; write the edits back to every file at once (each file keeps its own undo)
```

`wgrep-auto-save-buffer t` means edited files are saved to disk immediately on `C-c C-c`.

---

## 3. Embark — a context menu for "the thing at point" ([`init-completion.el`](lisp/init-completion.el))

| Key | Command | What it does |
|---|---|---|
| `C-.` | `embark-act` | Act on point / the current minibuffer candidate — the offered actions change with the object type (file → open/rename/grep; symbol → describe/find-def; …) |
| `C-;` | `embark-dwim` | "Do What I Mean" — run the single most sensible default action |
| `C-h B` | `embark-bindings` | Browse every active key binding via `completing-read` |

`embark-consult` glue: exporting from a consult command formats the export buffer nicely
and previews entries at point.

---

## 4. In-buffer code completion — Corfu + Cape ([`init-corfu.el`](lisp/init-corfu.el))

- Popup appears automatically after **2 characters**, **0.2 s** delay (`corfu-auto`,
  `corfu-auto-prefix 2`, `corfu-auto-delay 0.2`); `corfu-cycle` wraps the list.
- `corfu-popupinfo` **(built-in extension)**: a second popup beside the list shows the
  selected candidate's docstring / signature (0.5 s to first appear, 0.2 s when stepping
  between candidates).
- `cape` adds generic completion backends usable in any buffer: **dabbrev** (words from
  open buffers), **file paths**, **elisp symbols / elisp code blocks**. Eglot layers
  language-aware completions on top in programming buffers.

---

## 5. Motion & editing power tools ([`init-editing.el`](lisp/init-editing.el))

| Key | Command | What it does |
|---|---|---|
| `C-:` | `avy-goto-char-timer` | Type a few chars → every match gets a letter label → press it to jump there (the Emacs analogue of ace-jump / tmux-jump) |
| `M-g w` | `avy-goto-word-1` | Jump to a word |
| `M-g l` | `avy-goto-line` | Jump to a line |
| `C-=` | `expreg-expand` | Grow the region along the **tree-sitter parse tree**: word → string → node → enclosing node → … `C-+` (= `C-S-=`) shrinks it. Exact if-statement / parameter-list / JSX-element boundaries in every grammar-backed language |
| `C-M-=` | `er/expand-region` | The **no-grammar fallback** for `C-=` — grows by Lisp sexps (word → sexp → string → defun → …). For css / json, which have no tree-sitter parser (excluded from `treesit-auto`), where expreg has nothing to climb |
| `C->` | `mc/mark-next-like-this` | Multiple cursors: mark the next occurrence of the region/word |
| `C-<` | `mc/mark-previous-like-this` | …the previous occurrence |
| `C-c C-<` | `mc/mark-all-like-this` | Mark *all* occurrences |
| `C-S-<mouse-1>` | `mc/add-cursor-on-click` | Click to drop an extra cursor |
| `C-x u` | `vundo` | Draw the undo history as a tree in a transient side buffer; walk it with the arrow keys. Stores nothing on disk, doesn't replace native undo — plain `C-/` and `C-_` still undo |
| `M-o` | `ace-window` | Overlay every window in the frame with a one-character label (`a s d f j k l ;`) — press the letter to jump there. Far faster than `C-x o` cycling once you have 3+ windows. `C-x o` itself is unchanged |
| `` C-` `` | `popper-toggle` | Show/hide the latest "popup" buffer (compile, help, vterm, magit-process, *Warnings*, *Async Shell Command*, flymake diagnostics, …) — popups form a stack so they don't permanently fragment your layout |
| `` M-` `` | `popper-cycle` | Cycle through visible-able popup buffers in the stack |
| `` C-M-` `` | `popper-toggle-type` | Toggle whether the current buffer is treated as a popup (one-off opt in/out for buffers `popper-reference-buffers` doesn't match) |
| `C-c ←` | `winner-undo` | Undo the last window-layout change (`winner-mode`, built-in). Concrete save: you `C-x 1`-ed expecting to keep the other window — this brings it back. Magit / Org / Help re-arrange windows aggressively; this is the universal undo for that |
| `C-c →` | `winner-redo` | Redo a window-layout change you just undid with `C-c ←` |

Always-on editing defaults (mostly [`init-defaults.el`](lisp/init-defaults.el); `save-place-mode`
lives in [`init-completion.el`](lisp/init-completion.el), `rainbow-delimiters` in
[`init-editing.el`](lisp/init-editing.el)): `electric-pair-mode` (auto-insert matching brackets
/ quotes), `delete-selection-mode` (typing replaces the active region),
`rainbow-delimiters` (colour nested parens by depth in `prog-mode`), `column-number-mode`,
`y/n` instead of `yes/no`, no audible bell, `global-auto-revert-mode` (reload buffers —
and Dired — when files change on disk), `save-place-mode` (cursor position per file
persists across sessions — reopen a file, point lands where you left off), no `foo~`
backups / `.#foo` lockfiles (autosaves `#foo#` are kept for recovery, redirected under
`var/auto-save/` by no-littering).

**Visual feedback** — `pulsar` briefly pulses the current line after a big motion: an avy
jump, a window switch, `consult-line` / `consult-imenu` / `consult-ripgrep`,
`recenter-top-bottom`, … so your eye re-acquires the cursor.

**Code folding (HideShow)** — `hs-minor-mode` **(built-in)** is auto-enabled in every
`prog-mode` buffer. `C-c @` (hideshow's own prefix, rebound here) opens a `transient`
menu — the same menu style as `C-c a` for aidermacs (§15). hideshow's native sub-keys
are unmemorable multi-modifier chords; this replaces the whole prefix with one
discoverable, bottom-popup menu that **stays open** so you can navigate and fold
repeatedly. `which-key` still routes you in: press `C-c`, pause, and the panel shows
`@`.

| Key | Command | What it does |
|---|---|---|
| `C-c @` | `fenrir/hideshow-menu` | Open the folding menu (bottom-popup transient) |
| `t` | `hs-toggle-hiding` | Fold / unfold the block at point |
| `h` | `hs-hide-block` | Fold the block at point |
| `s` | `hs-show-block` | Unfold the block at point |
| `H` | `hs-hide-all` | Fold every block in the buffer |
| `S` | `hs-show-all` | Unfold everything |
| `l` | `hs-hide-level` | Fold all blocks one nesting level deep (`C-u N` then `l` for N levels) |
| `n` / `p` | `next-line` / `previous-line` | Move point down / up *without leaving the menu*. **Bound and working but hidden** from the popup — `?` lists them |
| `C-v` / `M-v` | `scroll-up-command` / `scroll-down-command` | Page down / up. **Bound and working but hidden** from the popup — `?` lists them |
| `C-s` | `consult-line` | Search the buffer (the config's usual `C-s`); jump to a match, then the menu re-appears so you can fold there. **Hidden by default** — `?` lists it |
| `?` | — | Show (or re-hide) the navigation keys above — they work either way, `?` only controls whether the popup *shows* them |
| `q` | — | Quit the menu (`C-g` also works) |

`t` / `h` / `s` / `H` / `S` / `l` / `?` are shown in the popup; the navigation keys
`n` / `p` / `C-v` / `M-v` / `C-s` work but are hidden until `?`. All are pressed
*inside* the menu after `C-c @`.
hideshow folds by sexp / braces — strong for C-like, Lisp and JSON, weaker for
indentation-structured languages like Python.

**Code folding (tree-sitter)** — `treesit-fold` complements HideShow above by folding on
the **parse tree** instead of braces / indentation, so it folds Python (and every other
grammar-backed language) accurately exactly where hideshow is weak. `global-treesit-fold-mode`
is on; in a buffer with no tree-sitter parser (css / json) it no-ops and hideshow
stays in charge — the two coexist. Folds render as an overlay ellipsis (no fringe — TTY-safe).
Its own `C-c z` prefix is kept off hideshow's `C-c @` and combobulate's `C-c o` (§7) so all
three can be live in one buffer. Config lives with the tree-sitter stack in
[`init-languages.el`](lisp/init-languages.el), not this section's `init-editing.el`.

| Key | Command | What it does |
|---|---|---|
| `C-c z t` | `treesit-fold-toggle` | Fold / unfold the node at point |
| `C-c z h` | `treesit-fold-close` | Fold the node at point |
| `C-c z s` | `treesit-fold-open` | Unfold the node at point |
| `C-c z H` | `treesit-fold-close-all` | Fold every foldable node in the buffer |
| `C-c z S` | `treesit-fold-open-all` | Unfold everything |
| `C-c z r` | `treesit-fold-open-recursively` | Unfold the node at point and all its descendants |

---

## 5b. Modern-IDE layer ([`init-ide.el`](lisp/init-ide.el))

The VSCode / JetBrains conveniences the rest of the config didn't already cover,
gathered into one module. Works on **both TTY and GUI** Emacs (everything is
TTY-safe, the stricter case — a GUI frame runs the same layer unchanged, just
rendering a few pieces richer). The heavy IDE machinery lives elsewhere
(LSP/refactor/hierarchy + tree-sitter + debugger in §7, git porcelain in §8,
project search in §1–2, completion in §1/§4) — this section is the rest.

**Always-on (no keys to press):**

| Feature | Where active | What you get |
|---|---|---|
| `hl-line` **(built-in)** | prog + dired/ibuffer/grep/occur/package-menu | Current line highlighted (not global — keeps vterm/org/minibuffer clean) |
| `subword-mode` **(built-in)** | everywhere (`global-subword-mode`) | `M-f`/`M-b`/`M-d` stop at camelCase boundaries (`get`\|`User`\|`Name`) |
| `indent-bars` | prog + `yaml-ts-mode` | Vertical indentation guides (char backend — renders on TTY) |
| `colorful-mode` | prog + css/web/html/conf | Inline colour swatch behind every `#rrggbb` / `rgb(...)` / CSS name |
| `ws-butler` | prog | Trims trailing whitespace **only on lines you edited** (diff-safe on-save trim) |
| `dumb-jump` | xref fallback (last backend) | `M-.` still jumps via ripgrep when no LSP/GTAGS exists — never shadows Eglot |

**Keys:**

| Key | Command | What it does |
|---|---|---|
| `C-c s s` | `symbol-overlay-put` | Highlight every occurrence of the symbol at point (toggle) — "highlight usages" |
| `C-c s n` / `C-c s p` | `symbol-overlay-jump-next` / `-prev` | Jump between the highlighted occurrences |
| `C-c s r` | `symbol-overlay-rename` | Rename all occurrences **in this buffer** (lexical, no LSP needed) |
| `C-c s a` | `symbol-overlay-remove-all` | Clear all symbol highlights |
| `M-<up>` / `M-<down>` | `move-text-up` / `-down` | Drag the line / region up or down (VSCode `Alt+↑/↓`); org keeps its own |
| `C-c S` | `string-inflection-all-cycle` | Cycle the identifier: `snake` → `SCREAMING` → `Camel` → `camel` → `kebab` |
| `C-c ;` / `C-c '` | `goto-last-change` / `-reverse` | Jump to where you last edited, then the edit before that |
| `C-c k` / `C-c K` | `devdocs-lookup` / `devdocs-peruse` | Offline devdocs.io API docs (run `M-x devdocs-install LANG` once per language) |
| `C-c B` | `dired-sidebar-toggle-sidebar` | File-tree sidebar (reuses dired + its nerd-icons/subtree enhancers) |
| `C-c O` | `imenu-list-smart-toggle` | Outline / Structure pane: a persistent side window of the buffer's imenu tree |
| `C-c E` | `separedit` | Edit the comment / string / code-block at point in a dedicated buffer with the embedded language's own mode (`C-c C-c` writes back) |

**Git extras (`C-c G` prefix — GitLens-style; Magit owns the porcelain in §8):**

| Key | Command | What it does |
|---|---|---|
| `C-c G l` | `git-link` | Copy the forge permalink (pinned to commit SHA) for the current line / region |
| `C-c G h` | `git-link-homepage` | Copy the repo's homepage URL |
| `C-c G t` | `git-timemachine` | Step through this file's history in place (`p`/`n` = older/newer, `q` quit) |
| `C-c G b` | `blamer-mode` | Toggle inline end-of-line blame (author · when · summary) for the buffer |

**Workspaces (`C-c W` prefix — `tabspaces`, project-scoped on top of the §11 tab-bar):**

| Key | Command | What it does |
|---|---|---|
| `C-c W s` | `tabspaces-switch-or-create-workspace` | Switch to (or create) a named workspace tab |
| `C-c W o` | `tabspaces-open-or-create-project-and-workspace` | Open a project as its own workspace |
| `C-c W b` | `tabspaces-switch-to-buffer` | Switch buffer **within** this workspace (filtered list) |
| `C-c W d` / `C-c W k` | `tabspaces-close-workspace` / `tabspaces-kill-buffers-close-workspace` | Close the workspace (keep / kill its buffers) |
| `C-c W r` | `tabspaces-remove-current-buffer` | Drop the current buffer from this workspace |
| `C-c W w` | `tabspaces-show-workspaces` | List all workspaces |

Each workspace tab has its **own buffer list**, so `C-x b` / `consult-buffer` show only
that project's buffers (`tabspaces-use-filtered-buffers-as-default` is on).

**REST client:** open any `.http` / `.rest` file → `restclient-mode`; write a request and
press `C-c C-c` to fire it and pretty-print the response (the in-editor Postman / VSCode
REST Client).

**More IDE conveniences, layered into their home modules** (same initiative, but the code
lives where it thematically belongs):

| Key | Command | Lives in | What it does |
|---|---|---|---|
| `C-c T` | `vterm-toggle` | [`init-terminal.el`](lisp/init-terminal.el) | Integrated-terminal toggle (VSCode `Ctrl+\``): show/hide a project-scoped vterm, `cd`'d to the current dir |
| _(automatic)_ | `undo-fu-session-global-mode` | [`init-editing.el`](lisp/init-editing.el) | Persists native undo history to disk, so undo survives reopening a file / daemon restart |
| `C-c m …` | `smerge-mode` **(built-in)** | [`init-git.el`](lisp/init-git.el) | Merge-conflict resolver, auto-enabled on conflict markers. `C-c m n`/`p` next/prev, `RET` keep-current, `a` keep-all, `u`/`l` keep-upper/lower, `E` ediff |
| `M-g t` / `M-g T` | `consult-todo` / `consult-todo-all` | [`init-git.el`](lisp/init-git.el) | Jump to a TODO/FIXME/HACK with preview — this buffer / every open buffer |
| `C-c v n` / `C-c v p` | `diff-hl-next-hunk` / `-previous` | [`init-git.el`](lisp/init-git.el) | Jump between changed hunks (the gutter marks); **repeatable** — bare `n`/`p`/`s`/`r` continue (repeat-mode) |
| `C-c v s` / `C-c v r` / `C-c v S` | `diff-hl-show-hunk` / `-revert-hunk` / `-stage-current-hunk` | [`init-git.el`](lisp/init-git.el) | Preview / revert / stage just the hunk at point, without opening Magit |
| `C-c D` | `docker` | [`init-docker.el`](lisp/init-docker.el) | Manage containers/images/volumes/networks (start/stop/logs/exec/inspect) — needs the `docker` CLI |
| `C-c M-c` | `copilot-mode` | [`init-ai.el`](lisp/init-ai.el) | Toggle GitHub Copilot AI inline ("ghost text") completion in this buffer — `TAB` accepts, `C-TAB` accepts a word, `C-c M-n`/`M-p` cycle |

`.dockerfile` / `Dockerfile*` files open in `dockerfile-mode` (`C-c C-b` builds the image).

**Copilot one-time setup:** `M-x copilot-install-server` (downloads the Node server) then
`M-x copilot-login` (device-code auth, needs a Copilot subscription). It's opt-in per buffer
on purpose — to make it always-on in code, add `(add-hook 'prog-mode-hook #'copilot-mode)`.

**Bracket peek (built-in):** when the matching open-bracket is scrolled off-screen, the line
that opens it is shown in an overlay at point (`show-paren-context-when-offscreen`,
[`init-defaults.el`](lisp/init-defaults.el)) — so a closing `})]` at the bottom of a long
function tells you what it closes without scrolling up.

---

## 5c. GUI-frame eye-candy + diagrams ([`init-gui.el`](lisp/init-gui.el), [`init-diagrams.el`](lisp/init-diagrams.el))

This daemon serves **both** TTY (`emacsclient -nw`) and GUI (`emacsclient -c`)
frames — sometimes at the same time — so GUI-only packages are gated by how they
behave on a terminal frame:

**Tier A — on automatically, safe on both TTY and GUI** (each self-falls-back or its effect is a pure overlay/face that just renders plainer on a terminal):

| Feature | GUI frame | TTY frame |
|---|---|---|
| `vertico-posframe` | Minibuffer floats as a centred child frame | Falls back to the normal bottom Vertico (per-display `posframe-workable-p` check) |
| `ligature` | Programming ligatures (`-> => != >=` …) with a capable font | OpenType features ignored — harmless no-op |
| `beacon` | Coloured beam flashes the line when point teleports (window switch, big scroll, avy/consult jump) | Plainer overlay flash — still works |
| `dimmer` | Inactive windows dimmed so the focused buffer pops (which-key/magit/org kept bright) | Foreground dimmed; degrades on low-colour, never breaks |
| `solaire-mode` | "Real" file buffers get a subtly different background from UI buffers | Face remap — harmless |
| `highlight-numbers` | Numeric literals in their own face (prog-mode) | Same (font-lock keyword) |
| `goggles` | Soft pulse over the just-edited region (yank/delete/kill) | Plainer overlay |
| `volatile-highlights` | Transient highlight of yank/undo regions | Same (overlay) |
| `nerd-icons-corfu` | Kind glyph (fn/var/keyword…) in each corfu candidate's margin | Glyphs if the terminal font is a Nerd Font, else text |
| `lin` | Stylish mode-aware `hl-line` for list/selection buffers (dired/ibuffer/grep/occur…) | Same (face) |
| `pulsing-cursor` | Cursor gently pulses instead of a hard blink | Harmless (drives the same blink machinery) |

**Tier B — on demand, the command adapts per display (GUI feature ↔ TTY fallback / no-op):**

| Key | Command | What it does |
|---|---|---|
| `C-c H` | `fenrir/eldoc-box-dwim` | Hover docs: an `eldoc-box` child frame on GUI; falls back to the eldoc **doc buffer** on TTY |
| `C-c J` | `fenrir/jump-buffer-dwim` | Buffer switcher: a `frog-jump-buffer` posframe grid on GUI; falls back to `consult-buffer` on TTY |
| `C-c M-v` | `fenrir/mixed-pitch-dwim` | Toggle variable-pitch prose (`mixed-pitch`) in this buffer; reports a no-op on TTY (no variable-pitch fonts there) |
| `C-c M-o` | `olivetti-mode` | Centered prose margins (`olivetti`) for long-form reading/writing — works on TTY too (window margins + fill-column, no fonts involved); on-demand purely by light-touch philosophy |
| `C-c M-f` | `fenrir/fontaine-set-preset-dwim` | Pick a `fontaine` font-size preset (small/regular/large/huge); refuses on TTY |
| `C-c M-r` | `fenrir/prism-toggle` | Toggle `prism` depth-based ("rainbow") code colouring in this buffer — opt-in per buffer (striking on a truecolor GUI, noisy on an 8-colour TTY) |
| `C-c M-d` | `dashboard-open` | Open the graphical startup dashboard (logo banner + recents/projects/bookmarks) |

**Tier C — GUI-only global display-replacing modes (no TTY fallback):**

The two **posframe popups** (`which-key-posframe`, `transient-posframe`) are now enabled
**automatically** while this daemon serves graphical frames *only* — that's what makes
which-key and the `<f5>` hub (§0) render as centred popups instead of a bottom strip. The instant an `emacsclient -nw`
frame connects they switch straight back off (together with anything `C-c M-g` had
turned on), because they are process-global modes and would otherwise leave the terminal
frame showing nothing. Driven by `fenrir/gui-popups-auto` on
`server-after-make-frame-hook` / `after-delete-frame-functions`; set
`fenrir/gui-popups-auto-enable` to nil for purely manual control.

| Key | Command | What it does |
|---|---|---|
| `C-c M-g` | `fenrir/gui-popups-toggle` | Manual override / the rest of the batch: the posframe popups **plus** `good-scroll` (animated smooth scroll), `mlscroll` (graphical mode-line scrollbar), `spacious-padding` (frame borders/padding), `nyan-mode` (mode-line image). Those four are never automatic — a nyan cat appearing by itself is a surprise, not a feature. ⚠️ Turn them **off** before using a TTY frame of the same daemon; the frame hook also does it for you. (`pixel-scroll-precision-mode` is *not* part of this toggle — [`init-defaults.el`](lisp/init-defaults.el) enables it globally and it no-ops on TTY) |
| `C-c M-m` | `fenrir/minimap-toggle-dwim` | Toggle the `minimap` code-overview side window; refuses on TTY |
| `C-c M-t` | `centaur-tabs-mode` | Toggle the `centaur-tabs` graphical buffer tab bar (VSCode-style file tabs; distinct from the `C-c W` tab-bar/tabspaces workspaces) |

> New in this layer: 20 packages. They aren't in `elpa/` on a fresh add — run `M-x my/package-refresh` then restart Emacs once so `use-package` installs them (the archive is never refreshed at startup; see [CLAUDE.md](CLAUDE.md#package-install-discipline-load-bearing-quirks)).

**Diagrams-as-code** ([`init-diagrams.el`](lisp/init-diagrams.el)):

| File / mode | Render | Notes |
|---|---|---|
| `.puml` / `.plantuml` → `plantuml-mode` | `C-c C-c` (or `C-c C-p` preview) | Local `java -jar` mode; jar at `var/plantuml/plantuml.jar`. PNG renders in a GUI frame — for TTY set `(setq plantuml-output-type "txt")` for ASCII art |
| `.mmd` / `.mermaid` → `mermaid-mode` | `C-c C-c` compile, `C-c C-o` open | Uses the `mmdc` CLI |
| org `#+begin_src plantuml` / `mermaid` | `C-c C-c` | Wired into `org-babel` (both languages) |

**One-time renderer setup** (both already done on this machine; needed again on a fresh clone):
- PlantUML jar: `M-x plantuml-download-jar` (or re-curl into `var/plantuml/`, see the module header). Needs `java` (+ `dot` for class/state diagrams).
- Mermaid CLI: `npm install -g @mermaid-js/mermaid-cli` (provides `mmdc`).

---

## 6. Help system, upgraded (`which-key` in [`init-defaults.el`](lisp/init-defaults.el), `helpful` in [`init-editing.el`](lisp/init-editing.el))

| Key | Command | What it does |
|---|---|---|
| `C-h f` | `helpful-callable` | Functions + macros — `*Help*` with source, callers, edebug entry |
| `C-h v` | `helpful-variable` | Variables |
| `C-h k` | `helpful-key` | Describe a key |
| `C-h x` | `helpful-command` | Commands |
| `C-h o` | `helpful-symbol` | Any symbol |

`which-key` **(built-in)**: after a prefix key (`C-x`, `C-c`, …) wait 0.5 s and a panel
lists the follow-up keys — no need to memorise prefixes.

**Too many candidates in the panel? Search it**: press the prefix, then `C-h` — this
routes through `embark-prefix-help-command` (wired in [`init-defaults.el`](lisp/init-defaults.el))
into a Vertico minibuffer listing just that prefix's bindings, filterable by typing.
`which-key` itself has no built-in text filter; this is what stands in for one.

---

## 7. Project, LSP & languages ([`init-languages.el`](lisp/init-languages.el) + per-language [`lisp/languages/`](lisp/languages/))

> Shared Eglot / tree-sitter / project / debugger infra lives in [`init-languages.el`](lisp/init-languages.el); each language's hooks + server config live in [`lisp/languages/init-<lang>.el`](lisp/languages/) (`init-java`, `init-go`, `init-python`, `init-rust`, `init-typescript`, `init-c-cpp`, `init-lua`, `init-vue`, `init-web`, `init-markdown`).

- `project.el` **(built-in)**: project-aware file/buffer/command commands under `C-x p`.
- **envrc**: direnv integration. When you visit a file under a directory with an
  `.envrc`, envrc runs `direnv export json` and applies the result **buffer-locally**
  (`process-environment` + `exec-path`). Two concrete wins: Eglot picks the right server
  binary per project (e.g. a Go monorepo's pinned `gopls` in `./bin/`), and Node tooling
  follows whatever `nvm`/`volta`/`asdf` declared. Complements `exec-path-from-shell` in
  [`init.el`](init.el)'s bootstrap (one-shot global harvest at daemon launch) — neither replaces the other.
  Per-project setup: drop an `.envrc`, then `direnv allow` once. Needs the `direnv`
  binary (`apt install direnv`); without it the mode silently no-ops.
- **Eglot** **(GNU ELPA — upgraded from the bundled copy)**: a zero-config LSP client.
  Upgraded off the version bundled with Emacs 30.1 to the ELPA release (≥1.19) so that
  **native call / type hierarchy** is available (`C-c h c` / `C-c h t`, below) — the
  bundled copy had no client code for `callHierarchy/*`. Auto-starts when you open a file
  in a hooked mode **and** the language server binary is on `PATH`. Hooked modes:
  `python-ts-mode`, `go-ts-mode`, `rust-ts-mode`, `js-ts-mode`, `typescript-ts-mode`,
  `c-ts-mode`, `c++-ts-mode` (so: pyright/pylsp, gopls, rust-analyzer,
  typescript-language-server, clangd). **`java-ts-mode` is deliberately absent** — Java
  runs with no language server at all ([why](_doc/JAVA.md#there-is-no-language-server)).
  `eglot-autoshutdown t` kills the server when
  its last buffer closes; the JSON-RPC events log is disabled.
- **consult-eglot**: `M-g e` → `consult-eglot-symbols` (bound only in
  `eglot-mode-map`). Asks the language server's `workspace/symbol` index for **every**
  symbol in the project, not just open buffers — fills the gap between `consult-imenu`
  (this file) and `consult-imenu-multi` (open buffers of the same major mode). Same
  vertico + orderless + marginalia UI as the rest of §1.
- **gtags / GNU Global — the non-LSP xref fallback** ([`lisp/init-tags.el`](lisp/init-tags.el),
  rebuilt 2026-07-30 around the maintained GNU-ELPA **`gtags-mode`**; full story in
  [_doc/TAGS.md](_doc/TAGS.md)): one *global* minor mode contributes a gtags xref backend
  that answers only in buffers under an indexed root and declines silently elsewhere — no
  per-language hooks, no keymap grabs. When no language server is attached (a failed
  server, or a repo with no `go.mod` / `package.json` at the resolved root — e.g.
  `~/code/coinsasia/` with a prebuilt `GTAGS`), `M-.` / `M-?` / `M-,` work off the index;
  when Eglot is attached it registers its backend buffer-locally ahead of gtags and **wins
  automatically**. **The index stays fresh by itself**: every save runs an async
  `global --single-update <file>` (per-file, no re-traversal). `GTAGSCONF` (the tracked
  [`gtags.conf`](gtags.conf) with the extended skip list) and `GTAGSLABEL=java-pygments`
  (built-in parser for C/C++, pygments for Go/Python/TS **and Java** — the built-in Java
  parser indexes no fields) are exported **daemon-wide**, so create, update,
  on-save refresh and every query all inherit them — no per-call env plumbing to forget.
  The label is re-read on *every* invocation, so an update run under the wrong label
  silently rots the index; see [TAGS.md](_doc/TAGS.md#env--one-setenv-every-subprocess). In an un-indexed
  buffer with no LSP, `M-.` gives a one-line `No tags here -- C-c g g builds a gtags index`
  instead of etags' 1990s `Visit tags table` prompt. Needs `global` + `universal-ctags` +
  `python3-pygments` (installed by [`shell/install-root.sh`](shell/install-root.sh)).
- **`C-c g` — index management** (navigation itself has no keys here; it's plain xref):
  **`C-c g g`** (`fenrir/gtags-build`) builds the index async — default root is the
  **covering index root** (`global --print-dbpath`, upward walk), else the project root,
  so a rebuild from inside a sub-crate lands on the repo-top index instead of creating a
  nested shadow — refuses `$HOME` / filesystem roots, wipes a pre-existing 0-byte stub, and **validates
  the result** (a failed or corrupt build is deleted, never left as the stub every later
  `global -u` rejects with `seems corrupted`). **`C-c g u`** (`gtags-mode-update`) is the
  bulk async `global -u` for after a branch switch / pull. **`C-c g d`**
  (`fenrir/gtags-diagnose`) lists every `GTAGS` in the subtree (`[root]`/`[nested]`) and
  offers to delete the nested ones — GNU Global resolves to the *nearest ancestor* index,
  so `backend/GTAGS` silently shadows the root index for everything beneath it.
- **eglot-booster**: routes LSP traffic through the `emacs-lsp-booster` Rust binary
  for threaded I/O (Emacs no longer blocks waiting on the server) and JSON →
  Elisp-bytecode pre-parse (large payloads like `consult-eglot-symbols`, gopls
  hover on heavy structs, rust-analyzer type info — meaningfully faster even on
  Emacs 30's already-quick native JSON parser; per-keystroke completion deltas
  may go marginally slower). Binary built from source via
  `cargo install --locked --version 0.2.1 emacs-lsp-booster` (lands in
  `~/.cargo/bin/`); `--locked` pins transitive deps to the upstream `Cargo.lock`
  so there's no compiler-supply-chain gap relative to the pre-built release.
  Toggle at runtime via `M-x eglot-booster-mode` if anything misbehaves; package
  itself installed via `:vc` from [jdtsmith/eglot-booster](https://github.com/jdtsmith/eglot-booster).
- **tree-sitter** **(built-in)** via `treesit-auto`: faster, more accurate syntax through
  `*-ts-mode`. Grammars are installed on demand (`treesit-auto-install 'prompt` — it asks
  first); classic modes are remapped to their tree-sitter equivalents.
- **combobulate**: structural editing driven by the tree-sitter parse tree. Active in
  `python-ts-mode`, `go-ts-mode`, `js-ts-mode`, `typescript-ts-mode`, `tsx-ts-mode`.
  Where `expreg` (`C-=`, §5) only *grows the region* along the parse tree, combobulate
  *navigates and transforms* the nodes themselves — if-statement, parameter list, JSX
  element. Key motions: `M-a` / `M-e` jump between siblings (cases of a switch, list
  items, JSX children); `M-<` / `M->` swap siblings (reorder args / list items / JSX
  attributes); `M-h` mark current node (repeat to climb to the enclosing node, composes
  with `delete-selection-mode`); `C-c o n` rename identifier across its lexical scope
  (no LSP required — works on JSON keys, YAML, etc.). Installed from GitHub via Emacs
  30's `use-package :vc`; update later with `M-x package-vc-upgrade RET combobulate`.
- **breadcrumb**: header-line shows `project / file / class / function` path of point,
  powered by `project.el` + `imenu` + (when active) Eglot's symbol info. Concrete use:
  deep inside a long file, the header tells you which function / class you're inside
  without scrolling up; the project segment disambiguates when several repos are open.
  Enabled in `prog-mode` buffers only — org/markdown have their own outline-navigation
  surfaces and a redundant breadcrumb would clash visually in long org buffers; toggle
  per buffer with `M-x breadcrumb-local-mode`. From GNU ELPA (same author as
  eglot-booster and `indent-bars`).
- **flymake** **(built-in)**: on-the-fly diagnostics, fed by Eglot from the LSP. `M-n` /
  `M-p` jump to the next / previous error; the `C-c !` cluster opens the list views —
  `C-c ! l` this buffer's diagnostics (`flymake-show-buffer-diagnostics`), `C-c ! p` the
  **project-wide** list (`flymake-show-project-diagnostics` — the cross-file error surface,
  pairs with Eglot's workspace `diagnosticMode`), `C-c ! c` the full diagnostic at point
  (`flymake-show-diagnostic`). (`M-g f` in §1 lists this buffer's diagnostics through
  consult with preview; `C-u M-g f` goes project-wide.)
- **sideline** + **sideline-flymake**: VSCode "Error Lens"-style inline diagnostics.
  The diagnostic for the line containing point is rendered to the **right of that
  line** via overlay `after-string` — works identically in TTY and GUI, no fringe /
  child-frame dependency. `sideline-flymake-display-mode` is set to `'point` (the
  package default, spelled out at the call site) so only the current line's
  diagnostic shows; the alternative `'line` decorates every diagnostic line at once
  and is unbearable in any non-toy buffer. Walking errors with `M-n` / `M-p` above
  drags the inline message along to wherever point lands.
- **Code actions** — `C-c .` (in `eglot-mode-map`): VSCode `Ctrl+.` equivalent.
  Opens Eglot's `eglot-code-actions` transient — the LSP-driven quick-fix list
  ("Add missing import", "Organize imports", "Quickfix this diagnostic", …). The
  user-prefix variant is used because `C-.` is already `embark-act` (§3); scoped
  to `eglot-mode-map` so it doesn't shadow `C-c .` in non-LSP buffers.
- **Refactor / format keys** — the most-used code actions are lifted out of the
  `C-c .` transient onto dedicated keys (all in `eglot-mode-map`, all avoiding
  the combobulate `C-c o` prefix — see §3):
  - `C-c r` — `eglot-rename`: project-wide rename (VSCode F2 / IntelliJ Shift-F6),
    multi-file (`eglot-confirm-server-initiated-edits` is `nil`, so it applies in
    one go; review the aggregate in `git diff`).
  - `C-c i` — `eglot-code-action-organize-imports` (VSCode Shift-Alt-O).
  - `C-c x` — `eglot-code-action-extract`: extract method / variable (server-dependent —
    rich in rust-analyzer, sparse in gopls).
  - `C-c f` — `eglot-format`: format region (if active) else buffer, **on demand only**.
    apheleia owns format-on-save (§7's formatting notes); this is the manual escape
    hatch for buffers with no apheleia formatter and is deliberately never added to
    `before-save-hook` (would double-format).
- **Call / type hierarchy** — `C-c h c` (`eglot-show-call-hierarchy`) and `C-c h t`
  (`eglot-show-type-hierarchy`), both in `eglot-mode-map`. Native to Eglot ≥1.19 (the
  reason this config upgrades Eglot off the bundled 30.1 copy — see the Eglot bullet
  above). `C-c h c` opens an interactive tree of **callers / callees** of the symbol at
  point; `C-c h t` opens **super- / sub-types** — trace who calls a function, or walk a
  trait's implementors. Served by rust-analyzer, gopls and clangd. **Not available in
  Java**, which has no server ([why](_doc/JAVA.md#there-is-no-language-server)). The tree
  buffer is navigable — `RET` jumps to a node's definition.
- **Inlay hints**: parameter names, inferred types, `&` reference markers etc.
  rendered inline by the LSP. Built-in in Emacs 30 — no external package. Enabled
  via `(eglot-managed-mode . eglot-inlay-hints-mode)` so it lights up on every
  Eglot-attached buffer (Go parameter names before each arg, Rust `: Vec<i32>`
  after `let x = vec![…]`, …). Toggle per-buffer at runtime with `C-c h i`
  (`eglot-inlay-hints-mode`); disable for a noisy language by removing its
  hook in that language's [`lisp/languages/init-<lang>.el`](lisp/languages/) module
  rather than touching the global setting. C/C++ (clangd) emit hints by default. Java
  gets none — no server ([why](_doc/JAVA.md#there-is-no-language-server)).
- **Semantic-tokens highlighting** — `C-c h s` (`eglot-semantic-tokens-mode`, native
  Eglot ≥1.20). Server-driven highlighting that knows local vs. captured variable,
  type vs. value, etc., beyond what tree-sitter font-lock infers. **Per-buffer opt-in,
  not a global hook** — it can fight tree-sitter font-lock and, on an 8/16-colour TTY,
  the extra face distinctions collapse into the same colour, so the payoff is real only
  on a truecolour terminal.
- **eglot-x — rust-analyzer protocol extensions** (Rust only, prefix `C-c R`): plain
  Eglot speaks standard LSP and ignores rust-analyzer's custom requests; `eglot-x`
  ([`init-rust.el`](lisp/languages/init-rust.el), `:vc` from GitHub) wires them in via
  `(eglot-x-setup)`. The cockpit is bound into `rust-ts-mode-map` so it never collides
  with the core's `C-c r` (rename) / `C-c h …` / combobulate's `C-c o`. Capital `R`:
  - `C-c R e` — `eglot-x-expand-macro`: expand the macro call at point.
  - `C-c R r` — `eglot-x-ask-runnables`: pick a cargo run / test / bench target.
  - `C-c R t` — `eglot-x-ask-related-tests`: tests touching the function at point.
  - `C-c R d` — `eglot-x-open-external-documentation`: open the symbol's docs.rs page.
  - `C-c R w` — `eglot-x-reload-workspace`: re-scan `Cargo.toml` after editing deps.
  - `C-c R p` — `eglot-x-rebuild-proc-macros`.
  - `C-c R s` — `eglot-x-structural-search-replace`: syntax-tree-aware search/replace.
  - `C-c R g` — `eglot-x-view-crate-graph` (needs graphviz `dot`).
  - `C-c R m` — `eglot-x-view-recursive-memory-layout`: byte layout of the type at point.
  - `C-c R a` — `eglot-x-analyzer-status`: rust-analyzer server status / indexing state.
  - `C-c R <up>` / `C-c R <down>` — `eglot-x-move-item-up/down`: move fn/struct/variant.
  `eglot-x-setup` is global (its file-handling advice is live for every Eglot server);
  it lives in the Rust module because that's where the payoff and every binding are.
- **eglot-inactive-regions** (C / C++): dims the `#if` / `#ifdef` branches clangd (≥17)
  reports as inactive via its `inactiveRegions` extension, so code the preprocessor
  discards reads as dimmed rather than live. Style is `'shadow-face` (theme-relative
  dimming, the same channel as the diagnostic-tag faces) so it survives an 8 / 16-colour
  TTY where the truecolour styles (`darken-foreground` / `shade-background`) collapse.
  No keybinding — automatic in eglot-managed buffers; config in
  [`init-c-cpp.el`](lisp/languages/init-c-cpp.el).
- **`C-c %` — brace-hop dwim** (C / C++ only): vim `%`-style one-key jump between
  matching brackets (`fenrir/c-sexp-dwim` in [`init-c-cpp.el`](lisp/languages/init-c-cpp.el)).
  On an opening `([{` it `forward-sexp`s to just past the match; right after a closing
  `)]}` it `backward-sexp`s to the opener; elsewhere it scans to the next opener on the
  line and hops to its match (else plain `forward-sexp`). combobulate has no C / C++
  support, so this wraps the built-in sexp motion instead — it uses `char-syntax`, so
  C++ template `<>` (not paren-syntax) are correctly skipped. Bound in
  `c-ts-mode-map` / `c++-ts-mode-map` only; bare `%` still self-inserts.
- **cmake-mode** (C / C++): `CMakeLists.txt` and `*.cmake` open in `cmake-mode`
  (font-lock + indent) instead of plain `text-mode` — the [`cpp/`](cpp/README.md) native-module
  workspace is a CMake tree. Deliberately the **regex** mode, not the built-in
  `cmake-ts-mode`: the tree-sitter-cmake grammar isn't installed and its treesit-auto recipe
  is unpinned (would risk the same ABI-15 `version-mismatch` trap the c/rust/lua grammars pin
  around), whereas cmake-mode is pure Elisp — zero grammar, TTY-identical. Config in
  [`init-c-cpp.el`](lisp/languages/init-c-cpp.el).
- **markdown-mode**: `README.md` opens in GitHub-flavoured Markdown mode (`gfm-mode`);
  `markdown-command` is `pandoc`.
- **TOML** ([`init-toml.el`](lisp/languages/init-toml.el)): `.toml` opens in the built-in
  `toml-ts-mode`; Eglot attaches the **taplo** language server (`taplo lsp stdio`) for
  schema-aware completion / hover / diagnostics in `Cargo.toml`, `pyproject.toml`, etc.
  (taplo bundles a schema store keyed by filename). Format-on-save is free — apheleia already
  ships a `taplo` formatter mapped to `toml-ts-mode`. All the standard Eglot keys apply
  (`C-c .`/`r`/`f`/hover). Needs `cargo install taplo-cli --locked --features lsp` (the `lsp`
  feature; installed by [`shell/install-user.sh`](shell/install-user.sh)); without the binary
  the mode still edits + formats, only the LSP is absent.
- **jinx**: fast spell checker for every text-mode buffer (org, markdown, gfm, ...).
  Backed by the `enchant-2` C binary — orders of magnitude faster than `flyspell`.
  `M-$` (was `ispell-word`) opens a vertico-driven correction menu for the word at point;
  `C-M-$` switches languages mid-buffer. Pinned to `en_US` by default; first load
  compiles a small C module (~2 s, one-off). Requires `apt install enchant-2
  libenchant-2-dev`.
- **lua-ts-mode** (built-in) + **lua-mode** (MELPA) fallback: `.lua` files open in
  the tree-sitter `lua-ts-mode` when the grammar is present, and fall back to
  regex-based `lua-mode` when it isn't (the same "hook both modes" pattern as
  C/C++). The upstream `tree-sitter-grammars/tree-sitter-lua` grammar is ABI 15
  at HEAD and Emacs 30.1 caps at ABI 14, so the grammar is **pinned to `v0.3.0`**
  (its newest ABI-14 tag) via the `abi14-revision` recipe slot in
  [`init-lua.el`](lisp/languages/init-lua.el) and rebuilt by
  [`rust/treesit-grammar-lua/`](rust/treesit-grammar-lua/README.md) — same fix as
  `rust` (`v0.23.3`) and `c` (`v0.23.6`); `css` / `json` instead just drop out of
  `treesit-auto` since the built-in modes suffice. (Lua used `lua-mode` only until
  2026-06-08, when `v0.3.0` was found to be a valid ABI-14 tag.) **LSP**: Eglot
  attaches `lua-language-server` (LuaLS) on both modes — go-to-def, hover,
  `consult-eglot-symbols`, Flymake diagnostics. The server isn't on apt;
  [`shell/install-user.sh`](shell/install-user.sh) installs it from upstream
  GitHub releases into `~/.local/share/lua-language-server/` with a
  `~/.local/bin/` symlink. If the binary is missing, Eglot just declines to
  start — highlighting still works. No formatter / REPL wired.
- **dape**: Debug Adapter Protocol client — an in-editor step debugger, the
  Eglot-spirit counterpart to `dap-mode`. Core-only deps (`jsonrpc`), no
  `lsp-mode`, no child frames; breakpoints render in the buffer **margin**
  (a `B` glyph) so they stay visible on TTY frames (this config runs daemon +
  `emacsclient -nw`). `M-x dape` starts a session and prompts for a built-in
  config (`dlv`, `debugpy`, `codelldb`, `gdb`, `js-debug`, …) — you install the
  adapter **binary**, not write configs; only Go's `dlv` is on `PATH` today.

  **Single Go test at point** (the IDE "gutter Run/Debug" equivalent, in any
  `go-ts-mode` buffer — [`init-go.el`](lisp/languages/init-go.el)): put the cursor
  anywhere inside a `func TestXxx` and press **`C-c t t`** to run it or **`C-c t d`**
  to debug it under delve — zero further prompts. Both auto-detect the enclosing
  test name (treesit, with a regex fallback) and scope to `-run '^TestXxx$'` in
  that file's **package** directory; `C-c t t` runs `go test … -v` in a `compile`
  buffer, `C-c t d` launches a fully-specified dape session (no menu pick).
  A matching `go-test` config is still registered so `M-x dape` offers the same
  as a manual menu pick. (Both fix the old recipe's two bugs: `dape-cwd` =
  module root broke subpackage tests, and a hard-coded port blocked concurrent
  sessions.)
  Per-project overrides live in `.dir-locals.el`. Breakpoints persist across
  Emacs sessions (`dape-breakpoint-save` on quit, `dape-breakpoint-load` on
  startup). Modified buffers are saved before each run. Keymap below.

  **Single JUnit test at point / whole file** (the Java analogue, in any
  `java-ts-mode` / `java-mode` buffer — [`init-java.el`](lisp/languages/init-java.el),
  mirrors Go's `C-c t` test prefix above):

  | key | command | action |
  |---|---|---|
  | `C-c t t` | `junit-run-dwim` | run the `@Test` method at point; if point isn't in a test, run the whole file |
  | `C-c t m` | `junit-run-method-at-point` | run the `@Test` method enclosing point |
  | `C-c t f` | `junit-run-file` | run every test in the file |
  | `C-c t b` | `junit-runner-build` | (re)build the `junit-core` module |

  The parsing + command construction is a **C++ Emacs dynamic module**,
  `junit-core` (in the [cpp/ workspace](cpp/README.md),
  [`cpp/junit-core/`](cpp/junit-core/)), driven by the elisp front-end
  [`junit-runner.el`](lisp/junit-runner.el). The module uses tree-sitter to find
  the test method at a line (JUnit 4 + 5 annotations, nested `@Nested` classes
  via `Outer$Nested`), walks up to detect Maven vs Gradle, and returns the exact
  `mvn test -Dtest=…` / `./gradlew test --tests …` command; elisp runs it through
  `compile` (so `*junit*` is a compilation buffer with error jumps + `g`
  recompile). Build once with `M-x junit-runner-build` (or `cpp/build.sh`);
  needs `libtree-sitter-dev`. Like Go's keys, `C-c t` becomes a test prefix
  **inside Java buffers only** — it shadows vterm (§9) there; `C-c t` stays vterm
  everywhere else.

  **pytest test at point / file / project / last-failed** (the Python analogue,
  in any `python-ts-mode` / `python-mode` buffer —
  [`init-python.el`](lisp/languages/init-python.el), mirrors Go's & Java's
  `C-c t` test prefix above):

  | key | command | action |
  |---|---|---|
  | `C-c t t` | `fenrir/python-test-at-point` | run the test enclosing point; if point isn't in a test, run the whole file |
  | `C-c t f` | `fenrir/python-test-file` | run every test in the current file |
  | `C-c t a` | `fenrir/python-test-project` | run the whole suite from the project rootdir |
  | `C-c t l` | `fenrir/python-test-last-failed` | re-run only last run's failures (`pytest --lf`) |

  **Pure elisp** (no native module, unlike Java): the enclosing-test discovery
  parses the one already-open buffer via built-in `treesit`, so it's
  sub-millisecond and needs zero build step on a fresh clone. It maps the cursor
  to the exact pytest nodeid — `FILE::test_x` for a top-level `def`,
  `FILE::TestClass::test_x` for a method, `FILE::Outer::Inner::test_x` for a
  nested class (every enclosing class is included), and `async def` is handled
  transparently; a cursor on a test's decorator line (`@pytest.mark.parametrize`)
  resolves to that test, and running a parametrized test by name runs **all** its
  param cases. The `pytest` binary is the project's `.venv/bin/pytest` when a
  `.venv/` exists (same walk-up the pyright venv detector uses — never a
  hardcoded path), else `python -m pytest`; it runs from the pytest **rootdir**
  (nearest `pyproject.toml`/`pytest.ini`/`tox.ini`/`setup.cfg`/`setup.py`) so
  `conftest.py` fixtures resolve, through `compile` (so `*pytest*` is a
  compilation buffer with error jumps + `g` recompile). Modified buffers are
  saved first (pytest reads disk). Like Go's/Java's keys, `C-c t` is a test
  prefix **inside Python buffers only** — it shadows vterm (§9) there.

All dape commands live in `dape-global-map` under the **`C-x C-a`** prefix:

| Key | Command | What it does |
|---|---|---|
| `C-x C-a d` | `dape` | Start a debug session — prompts for an adapter config |
| `C-x C-a c` | `dape-continue` | Continue / resume execution |
| `C-x C-a n` | `dape-next` | Step over |
| `C-x C-a s` | `dape-step-in` | Step into |
| `C-x C-a o` | `dape-step-out` | Step out |
| `C-x C-a u` | `dape-until` | Run to the line at point |
| `C-x C-a p` | `dape-pause` | Pause a running session |
| `C-x C-a r` | `dape-restart` | Restart the session |
| `C-x C-a f` | `dape-restart-frame` | Restart the current stack frame |
| `C-x C-a b` | `dape-breakpoint-toggle` | Toggle a breakpoint (the `B` margin glyph) |
| `C-x C-a e` | `dape-breakpoint-expression` | Conditional breakpoint — stop when an expression is true |
| `C-x C-a h` | `dape-breakpoint-hits` | Hit-count breakpoint — stop on the Nth hit |
| `C-x C-a l` | `dape-breakpoint-log` | Logpoint — print a message instead of stopping |
| `C-x C-a F` | `dape-breakpoint-function` | Break on entry to a named function |
| `C-x C-a B` | `dape-breakpoint-remove-all` | Remove every breakpoint |
| `C-x C-a i` | `dape-info` | Open / refresh the info windows (scope, stack, breakpoints, threads) |
| `C-x C-a R` | `dape-repl` | Open the debug REPL |
| `C-x C-a x` | `dape-evaluate-expression` | Evaluate an expression in the stopped frame |
| `C-x C-a w` | `dape-watch-dwim` | Add the symbol/expression at point to the watch list |
| `C-x C-a m` | `dape-memory` | Open a hex memory view |
| `C-x C-a M` | `dape-disassemble` | Disassemble the current function |
| `C-x C-a t` | `dape-select-thread` | Switch thread |
| `C-x C-a S` | `dape-select-stack` | Pick a stack frame |
| `C-x C-a <` | `dape-stack-select-up` | Move up the call stack |
| `C-x C-a >` | `dape-stack-select-down` | Move down the call stack |
| `C-x C-a T` | `dape-select-session` | Switch between concurrent debug sessions |
| `C-x C-a K` | `dape-kill` | Kill the debuggee |
| `C-x C-a D` | `dape-disconnect-quit` | Detach from the debuggee and quit |
| `C-x C-a q` | `dape-quit` | Quit dape and tear down its windows |

**repeat-mode** (enabled in [`init-defaults.el`](lisp/init-defaults.el)): after one
`C-x C-a`-prefixed command the prefix stays live — bare `n` / `s` / `o` / `c` / `u`
keep stepping, `<` / `>` keep walking the stack, until you press any other key.

**Logpoints** (`C-x C-a l`): the message is plain text with `{expression}`
interpolation — e.g. `i={i} sum={sum}` re-evaluates `i` and `sum` in the stopped
frame and prints to the `dape-repl` every time the line is reached, **without
halting**: a `printf` you didn't have to edit into the source. The `{}` is expanded
by the adapter (`dlv` / `debugpy` / `codelldb` / `js-debug` all support it), so the
expression syntax is the debuggee's language. An empty message removes the logpoint.

---

## 8. Git — Magit + diff-hl ([`init-git.el`](lisp/init-git.el))

| Key | Command | What it does |
|---|---|---|
| `C-x g` | `magit-status` | The full Git porcelain — stage hunks, commit, rebase, log, … |
| `C-x M-g` | `magit-dispatch` | Menu of all Magit commands |

**`C-x v …` — Magit on the retired `vc.el` prefix.** `vc-handled-backends` is
`nil` (vc.el disabled), so its stock `C-x v` prefix map is repurposed wholesale:
each key keeps the slot vc.el used, so vc muscle memory carries over. Keys marked
*(menu)* open a Magit transient rather than acting immediately.

| Key | Command | Was (vc) |
|---|---|---|
| `C-x v e` | `magit-ediff-dwim` | `vc-ediff` |
| `C-x v =` | `magit-diff-buffer-file` | `vc-diff` |
| `C-x v D` | `magit-diff` *(menu)* | `vc-root-diff` |
| `C-x v l` | `magit-log-buffer-file` | `vc-print-log` |
| `C-x v L` | `magit-log-current` | `vc-print-root-log` |
| `C-x v g` | `magit-blame` *(menu)* | `vc-annotate` |
| `C-x v d` | `magit-status` | `vc-dir` |
| `C-x v v` | `magit-stage-buffer-file` | `vc-next-action` |
| `C-x v u` | `magit-file-checkout` | `vc-revert` |
| `C-x v +` | `magit-pull` *(menu)* | `vc-update` |
| `C-x v P` | `magit-push` *(menu)* | `vc-push` |
| `C-x v m` | `magit-merge` *(menu)* | `vc-merge` |
| `C-x v s` | `magit-tag` *(menu)* | `vc-create-tag` |
| `C-x v r` | `magit-branch-checkout` | `vc-retrieve-tag` |
| `C-x v G` | `magit-gitignore` | `vc-ignore` |
| `C-x v ~` | `magit-find-file` | `vc-revision-other-window` |
| `C-x v x` | `magit-file-delete` | `vc-delete-file` |

`vc-register`, `vc-log-incoming`/`vc-log-outgoing`, `vc-region-history`,
`vc-edit-next-command`, and `vc-update-change-log` had no crisp Magit
counterpart — those `C-x v` slots (`i`, `I`, `O`, `h`, `!`, `a`) are now undefined.

- **diff-hl**: live added/changed/removed markers in the fringe (in `prog-mode` and
  Dired); refreshes right after a Magit commit/stage via `magit-post-refresh`.
- **forge**: GitHub PR / Issue browsing inside Magit. Adds "Pull requests" and
  "Issues" sections to the `magit-status` buffer plus a `@` transient (e.g. `@ p l`
  fetch PRs, `@ p p` act on the PR at point, `@ a` add the repo). First-time
  per-machine setup:
  1. Mint a GitHub PAT with scopes `repo` + `read:org` (`gh auth token` reuses the
     existing `gh` token; otherwise <https://github.com/settings/tokens>).
  2. Add to `~/.authinfo.gpg`:
     `machine api.github.com login <user>^forge password <token>` — the `^forge`
     suffix namespaces the credential apart from any other `api.github.com` entry.
  3. In the target repo: `M-x forge-add-repository` (or `@ a`). Forge clones the
     issue/PR metadata into a local sqlite DB under `forge-database-file`
     (no-littering parks it in `var/`); the first add triggers a schema migration.

  Intentionally NOT enabled: `forge-pull-notifications` — it polls api.github.com
  periodically and dirties the minibuffer via `message`, which is precious real
  estate in a TTY workflow. Reach for `M-x forge-pull` on demand instead.
- **magit-todos**: adds a "TODOs" section to the Magit status buffer listing
  `TODO`/`FIXME`/`HACK`/`NOTE`/`BUG` keywords found across the repo (uses `rg` if present,
  else `git grep`); jump to them like any other section.
- **hl-todo**: colours those same keywords in code comments (`prog-mode`).

---

## 9. Terminal — vterm ([`init-terminal.el`](lisp/init-terminal.el))

| Key | Command | What it does |
|---|---|---|
| `C-c t` | `vterm` | A real libvterm-backed terminal emulator — far more capable than `term` / `eshell` |

`vterm-max-scrollback` 10000 lines. `vterm-always-compile-module t` compiles the C module
when `vterm.el` loads, so a missing `cmake` / `libvterm-dev` shows up as a loud startup
error rather than on first `M-x vterm`. (Prefer no C toolchain? Comment the block out and
use `M-x eshell`.)

---

## 10. Snippets / templates — TempEl + YASnippet ([`init-snippets.el`](lisp/init-snippets.el))

Two engines, split by job (decided 2026-06-01 — TempEl is GNU-ELPA, actively maintained by
minad, and reuses the built-in `tempo.el` syntax; YASnippet's upkeep has slowed but Eglot
still needs it for LSP snippet expansion):

- **TempEl** — your hand-written templates. Definitions live in the [`templates`](templates)
  file at the repo root (one section per major mode; `fundamental-mode` templates are global).
  Ways to use them:
  - Type a trigger name (e.g. `iferr`, `def`, `func`) then `C-<tab>` / `C-M-i` — `tempel-expand`
    completes and expands it inline (rides the same Vertico in-region UI as all completion).
    (`C-<tab>` replaces the Emacs default `M-TAB`, which GNOME swallows as Alt+Tab.)
  - `M-+` (`tempel-complete`) — list every template for the current mode and expand the pick.
  - `M-*` (`tempel-insert`) — browse/insert a template by name via the minibuffer.
  - While a template is active: `TAB` / `S-TAB` jump to the next / previous field; `C-g` exits.
  - [`tempel-collection`](https://github.com/Crandel/tempel-collection) (a large community
    template library) is available but **off by default** — opt in by uncommenting its block
    in [`init-snippets.el`](lisp/init-snippets.el).
- **YASnippet** — enabled only on `eglot-managed-mode` as Eglot's LSP snippet backend (so a
  language server's parameter-placeholder completions expand). Not used for hand-written
  snippets; no `yas-global-mode`, no `yasnippet-snippets`.

First install: `tempel` isn't bundled — `M-x my/package-refresh` then restart once.

---

## 11. Appearance ([`init-appearance.el`](lisp/init-appearance.el))

- **ef-themes** — `ef-melissa-dark` loaded by default (warm, sunlit dark palette; replaced
  the cold doom-tokyo-night). `C-c e t` = `ef-themes-toggle` (flip `ef-melissa-dark` ↔
  `ef-melissa-light`, night/day).
- **doom-themes** — kept installed for its extras: `doom-themes-org-config` (re-run after
  the ef theme loads, harmonizing Org faces) and as an alternative palette family (bold +
  italic apply when a `doom-*` theme is selected).
- **doom-modeline** — `doom-modeline-mode`, height 25. Tuned for narrow tmux panes so the
  right-side segments don't silently truncate: compact checker counter
  (`doom-modeline-check 'simple`), no buffer-encoding segment, `truncate-upto-project` file
  names, `vcs-max-length 18`. The **LSP/Eglot segment** is on (`doom-modeline-lsp`) — it
  renders only once an Eglot server manages the buffer, making it the load-bearing "did the
  server connect?" signal (e.g. when gopls or clangd silently fails to start, the missing
  segment is the tell). It stays blank in Java buffers by design — no server there.
- **nerd-icons** — glyph set used by doom-modeline, `nerd-icons-dired` (§12) and Corfu.
  Run `M-x nerd-icons-install-fonts` **once** after install to fetch the font. On a TTY the
  glyphs **display** only when the terminal emulator's own font is a Nerd Font (or has
  "Symbols Nerd Font Mono" in its fallback chain) — a tofu modeline is a terminal-font
  config issue, not an Emacs bug.
- **nerd-icons-completion** — icons in the minibuffer / marginalia column (Vertico-driven
  completion). `marginalia-mode` is already on at startup, so the mode is enabled explicitly
  *and* hooked to `marginalia-mode-hook` for later re-wiring.
- **nerd-icons-ibuffer** — a glyph per row in ibuffer (this config's `C-x b`).
- **consult-theme** — `C-c e T`: live-preview pick any installed theme (e.g. the punchier
  runner-up `doom-snazzy`, or back to `doom-tokyo-night`).
- **tab-bar** **(built-in)** — TTY-native text workspace row. `tab-bar-show 1` auto-hides the
  row at a single tab (invisible until you open a second tab). Numeric hints on, mouse close
  / new buttons off for a clean TTY row. Tab commands stay on the native `C-x t` map
  (`C-x t 2` new, `C-x t 0` close, `C-x t o` next, `C-x t RET` switch, `C-x t r` rename).

---

## 12. File manager — Dired + small enhancers + consult-dir ([`init-dired.el`](lisp/init-dired.el))

Plain `dired` **(built-in)** with small orthogonal enhancers layered on top — replaces
the previous Dirvish stack. Same UX wins as §1 (Vertico/Consult/Marginalia for the
minibuffer): each piece is independently swappable, and the directory picker
(`consult-dir`) plugs into the same completion frontend.

| Key | Command | What it does |
|---|---|---|
| `C-x d` | `dired` **(built-in)** | Open a Dired buffer for a directory |
| `C-x C-j` | `dired-jump` **(built-in,** `dired-x`**)** | From any buffer, open Dired on the directory containing this file with point already on the file. From a Dired buffer it lands in the **parent** (the dir "containing" this dir), with point on the original subdir — the easy "up one" entry point. `C-u C-x C-j` prompts for a directory instead |
| `C-x C-d` | `consult-dir` | Pick a directory from **recent files' parents / project roots / bookmarks / a curated "Quick" list** (`~`, `~/.emacs.d`, `~/.claude`, `~/code/obsidian`, `~/code/org-roam`, `~/fenrir-tools`) — Vertico drives the prompt, `<` then `r`/`p`/`b`/`q` narrows to one source. Replaces `list-directory` (the stock binding nobody uses) |
| `C-x C-d` *(in minibuffer)* | `consult-dir` | Same picker, but inserts the chosen dir into the current `find-file` prompt — keeps the partial filename you've already typed |
| `C-x C-j` *(in minibuffer)* | `consult-dir-jump-file` | Pick a dir, then immediately drop into a file-search prompt scoped to it. Distinct from the global `C-x C-j` above — this one only fires inside an active minibuffer prompt (`vertico-map`) |

Inside a Dired buffer:

| Key | Command | What it does |
|---|---|---|
| `TAB` | `dired-subtree-toggle` | Expand / collapse the directory at point inline (no new buffer) |
| `S-TAB` | `dired-subtree-cycle` | Cycle fold depth |
| `N` | `dired-narrow` | Live minibuffer filter over the current Dired listing — `RET` commits the filtered view, `g` (`revert-buffer`) returns to full |
| `w` | `dired-copy-filename-as-kill` **(built-in)** | Copy file **basename(s)** to kill ring |
| `C-c w` | `fenrir/dired-copy-absolute-path` | Copy **absolute path(s)** of marked files (one per line) — paired with `w` above so both forms are one keystroke apart |
| `a` | `dired-find-alternate-file` **(built-in)** | Open the entry under point, **reusing the current Dired buffer** instead of stacking a new one (this command is disabled by default; the module turns it on) |
| `C-x C-q` | `wdired-change-to-wdired-mode` **(built-in)** | Make the Dired buffer **editable as plain text** — rename files by editing their names, then `C-c C-c` writes the renames back (or `C-c ESC` cancels). With `wdired-allow-to-change-permissions 'advanced` (set in this module) the `rwxr-xr-x` columns are editable too — edit them and the save fires `chmod` |

Always-on enhancers:

- **diredfl** — distinct font-lock face per column (permissions / size / timestamp /
  owner / executable flag). Without it Dired is one foreground colour for everything;
  with it sizes pop in green, dates in cyan, symlinks in pink, etc. — same role
  Dirvish's `file-time` / `file-size` attributes used to play.
- **nerd-icons-dired** — inline file-type glyph at the start of each line, reuses the
  same nerd-icons font stack doom-modeline depends on (§11).
- **dired-collapse** — auto-collapses single-child directory chains onto one line.
  `foo/bar/baz/file.txt` displays as a single entry whenever each of `foo/`, `bar/`,
  `baz/` contains only its next child. Huge readability win in deeply nested project
  trees (Rust `target/`, Go `vendor/`, Java package paths). Auto-expands the moment a
  collapsed dir gains a second entry.
- **dired-async** — `C` (copy), `R` (rename / move), `D` (delete) and other file
  operations run in a child Emacs so the main session doesn't block. Pulls in the
  `async` package. No per-command setup: the mode hooks into Dired's dispatch table
  so the same keystrokes you'd already use just don't freeze on big trees.
- **`dired-kill-when-opening-new-dired-buffer t`** — descending into a directory
  reuses the current Dired buffer instead of leaving a trail.
- **`dired-listing-switches`** pinned to
  `-l --almost-all --human-readable --group-directories-first --no-group`. Directories
  sort first; human-readable sizes; the noisy "group" column is dropped.

Dropped vs. the old Dirvish module: the `?` dispatch transient, `dirvish-side`
sidebar, preview side panel, async fd-based listing for >20 k-entry dirs, and the `o`
quick-access transient. The six quick-access destinations live on as a `consult-dir`
source — narrow to them with `< q`. To get a preview side panel back, add
`(use-package dired-preview :hook (dired-mode . dired-preview-mode))` to
[`lisp/init-dired.el`](lisp/init-dired.el).

---

## 13. Org-mode — light touch ([`init-org.el`](lisp/init-org.el))

- `org-startup-indented` (visually indent by outline level), `org-hide-emphasis-markers`
  (show `*bold*` as bold, hide the stars), `org-src-fontify-natively` (highlight inside
  `#+begin_src`), `org-fontify-whole-heading-line` / `org-fontify-done-headline` (heading
  faces span the full line; DONE headlines restyle their title too), `org-ellipsis " ▾"`
  (single fold glyph instead of `...`, which reads as literal text on a dense TTY).
- **org-modern**: restyles headings, lists, checkboxes, blocks and timestamps — pure
  display, never edits your files. Also styles the agenda. Tuned: distinct bullet glyph
  per heading depth (`◉ ○ ✸ ✿ ◆` — the default `'fold` left depth legible only via
  indentation), tables stay plain ASCII `|` (Unicode box-drawing reads too heavy with CJK),
  `org-modern-block-fringe` off (TTY frames have no fringe — the default `#+begin_src`
  side bar was silently invisible in the daily `emacsclient -nw` session).
- **valign**: overlay-based visual table column alignment — measures real display width
  (CJK glyphs count as 2 columns), so mixed CJK/ASCII rows line up despite the plain `|`
  separators. Pure display, TTY-safe; independent of `org-modern-table`'s on/off state.
- **org-appear**: temporarily reveals the `*bold*` / `=verbatim=` / `[[link]]` markup of
  whichever element point is on — the complement to `org-hide-emphasis-markers`, so you can
  still edit the markers without globally un-hiding them.
- **`C-c c` — `org-capture`** (global, fires from any buffer): drops a quick TODO (`t`) or
  note (`n`) into `inbox.org` at the org home (`org-directory` = `~/code/org-roam`). Distinct
  from `C-c r c` (`org-roam-capture`, §14) which creates a *linked* Zettelkasten node — this
  is a flat, unlinked inbox for later refiling; the captured entry has no `:ID:` so org-roam
  ignores it as a non-node. The `t` template stamps a back-link (`%a`) to the buffer you
  captured from.
- **org-babel** evaluates `#+begin_src` blocks in `emacs-lisp`, `python`, and `shell` (plus
  `plantuml` / `mermaid` from [`init-diagrams.el`](lisp/init-diagrams.el) — both use the same
  additive `org-babel-do-load-languages`). `org-confirm-babel-evaluate` stays at its default
  `t`, so every block execution prompts first (an org file can't silently run code on open).
- **`C-c A` — `org-agenda`** (global): scope is deliberately `inbox.org` **only**, not the
  whole vault (~1500 notes, almost none with TODO headlines — scanning them buys cost and
  noise for nothing). The agenda is legitimately empty until the first `C-c c` capture
  creates `inbox.org`; expanding `org-agenda-files` to more of the vault later is a
  deliberate choice, not an oversight.
- **`C-c M-o` — `olivetti-mode`** ([`init-gui.el`](lisp/init-gui.el), Tier B): centered
  prose margins for long-form reading/writing. Manual toggle (no org-mode hook — light
  touch); works fine on TTY.

---

## 14. org-roam — Zettelkasten over `~/code/org-roam` ([`init-org-roam.el`](lisp/init-org-roam.el))

`~/code/org-roam/` is the `.org` vault (~1400 notes, originally converted from the
Markdown Obsidian vault by `~/code/obsidian-to-org-roam.py`). org-roam layers an
SQLite-backed link cache on top of plain `.org` files: every note with a top-level
`:ID:` property is a *node*, `[[id:...]]` links between them are bidirectional, and
the side-window `org-roam-buffer` shows the backlinks of whatever you're viewing.

| Key | Command | What it does |
|---|---|---|
| `C-c r f` | `org-roam-node-find` | Open a note — or create one; the prompt accepts any title and `RET` on a non-existent title fires the default capture template |
| `C-c r i` | `org-roam-node-insert` | Insert an `[[id:...]]` link to an existing note at point |
| `C-c r b` | `org-roam-buffer-toggle` | Toggle the backlinks side window for the current note |
| `C-c r c` | `org-roam-capture` | Capture a new note via the default template (`<timestamp>-${slug}.org` + `#+title:` + tag prompt) |
| `C-c r d` | `org-roam-dailies-goto-today` | Open today's daily note (creates it if missing); each invocation appends a fresh `* HH:MM` heading — a running journal in one file per day |
| `C-c r g` | `org-roam-ui-mode` | Toggle the interactive D3 force-directed graph in a browser tab (follows point in Emacs, theme-matched, no Graphviz needed) |

- **First run**: `M-x my/package-refresh` → restart Emacs → `M-x org-roam-db-sync` to
  build the cache from the vault. After that, `org-roam-db-autosync-mode` keeps it
  fresh as you edit. The DB pulls in `emacsql`; Emacs 30's built-in SQLite covers it
  with no external `sqlite3` install needed.
- **Capture tag prompt**: the default `"d"` template runs `completing-read-multiple`
  against `(org-roam-tag-completions)` so you pick from your existing vocabulary
  instead of inventing typo-variants (`#meeting` vs `#meetings`). Empty input emits
  no `#+filetags:` line at all — no stray empty header.
- **Dailies live at the vault root**, not in a `daily/` subdir
  (`org-roam-dailies-directory ""`) — the conversion script flattened them. New days
  get `#+filetags: :daily:` on first creation; each later `C-c r d` adds a
  `* %H:%M %?` heading via the `entry` capture template, so a day's file is a
  chronological log of timestamped headings rather than a single body.
- **Static graph alternative**: `M-x org-roam-graph` renders the link graph via
  Graphviz (needs the `dot` binary — `apt install graphviz`). Use `C-u M-x
  org-roam-graph` for a *local* subgraph around point; the whole-vault render is
  unreadable at this scale. `org-roam-ui` (above) is the better daily-driver.

---

## 15. AI / agent tooling ([`init-ai.el`](lisp/init-ai.el), [`init-aidermacs.el`](lisp/init-aidermacs.el), [`init-tmux-claude.el`](lisp/init-tmux-claude.el), [`init-alacritty-claude.el`](lisp/init-alacritty-claude.el))

[`gptel`](https://github.com/karthink/gptel) — LLM chat client. Defaults to Gemini (model
`gemini-pro-latest`); switch backend/model via `M-x gptel-menu`. Seed API keys with
`M-x fenrir/gptel-set-api-key` (writes `~/.authinfo`, mode `0600`). Entry points: `M-x gptel`
(open chat), `M-x gptel-send` (send region/buffer).

[`aidermacs`](https://github.com/MatthewZMD/aidermacs) — Emacs front-end for the `aider`
AI pair-programmer, in its own module [`init-aidermacs.el`](lisp/init-aidermacs.el). Runs
`aider` in a `vterm` buffer, driven by a Magit-style transient; AI edits land through
`ediff`. Repo-map-aware and diff-first — distinct from `gptel` (free-form chat).
Defaults: model `gemini/gemini-2.5-pro`, `code` chat mode, `aidermacs-auto-commits` off
(Magit owns commits).

| Binding | Command |
|---------|---------|
| `C-c a` | `aidermacs-transient-menu` — transient: sessions, file management, model switch, code actions |

Prereqs: the `aider` CLI on PATH (installed via `uv tool install --python 3.12
aider-chat`); `vterm` ([`init-terminal.el`](lisp/init-terminal.el)). aider reads
`GEMINI_API_KEY` from the environment — exported by the untracked `~/.profile.local`,
harvested into the daemon by an `exec-path-from-shell-copy-env` call in the module.

[`claude-jobs-view`](lisp/claude-jobs-view.el) — a `tabulated-list-mode` UI over the
external `jobctl` CLI for persistent Claude Code background sessions: list, send a prompt,
dispatch a new session, attach (via `vterm`), tail logs, and kill/delete, all from one
buffer.

| Binding | Command |
|---------|---------|
| `C-c j` | `claude-jobs-view` — open the session list |

`:commands`-only autoload — the ~700-line module doesn't load until the first `C-c j`.

`M-x fenrir/tmux-claude-split` ([`init-tmux-claude.el`](lisp/init-tmux-claude.el)) — when
Emacs runs inside tmux, splits the current pane left/right (the equivalent of tmux's
`Prefix %`), launches the `claude` CLI in the new pane, and titles that pane
`claude-<pane-id>` (e.g. `claude-%2`). Two up-front guards abort with a message and create
no pane: Emacs not inside a tmux session (`$TMUX` unset), or `claude` not on `exec-path`.
The new pane runs `claude` as its command, so it closes when `claude` exits. The pane
title is only *visible* when your `tmux.conf` enables `pane-border-status` —
`select-pane -T` sets it regardless. `M-x`-only, no key binding.

`M-x fenrir/alacritty-tmux-claude` ([`init-alacritty-claude.el`](lisp/init-alacritty-claude.el))
— the "from-scratch external window" companion to `fenrir/tmux-claude-split`. Spawns a new
`alacritty` window asynchronously (`start-process`), runs `tmux new-session claude` inside
it, and inherits Emacs' `default-directory` via `--working-directory` so `claude` sees the
current project. Each invocation creates an independent tmux session (no `-A`, no fixed
`-s` name — `tmux ls` will show them auto-named `0`, `1`, …); two calls = two alacritty
windows = two unrelated sessions. Teardown is automatic: `claude` exits → window exits →
session exits → tmux exits → alacritty closes. Up-front guards abort with `user-error` if
any of `alacritty` / `tmux` / `claude` is missing from `exec-path`. The child's
query-on-exit flag is cleared so quitting Emacs doesn't prompt about it. `M-x`-only, no
key binding. Pick this one when Emacs is a GUI/daemon outside any tmux; pick
`tmux-claude-split` when you're already inside a tmux pane.

---

## Operational notes

- **No package-archive refresh at startup** (network-free boot). Before installing a new
  package run `M-x my/package-refresh`, then restart — otherwise the first launch after
  adding it fails to find it. See also [`README.md`](README.md).
- **New `M-x customize` settings go to [`custom.el`](custom.el)** — `custom-file` is set
  and loaded in [`init-defaults.el`](lisp/init-defaults.el).
- **no-littering** redirects package state into `var/` (volatile runtime state) and `etc/`
  (config-ish data); [`.gitignore`](.gitignore) ignores both in one line each. The orphaned
  pre-no-littering files still at the repo root (`transient/`, `tramp`, `history`,
  `auto-save-list/`, `init.el~`, `init.el.bak-*`) are safe to `rm`.
- `:ensure nil` packages are Emacs built-ins — they are never pulled from MELPA. Everything
  else is auto-installed on first run because `use-package-always-ensure` is `t`.

---

See also: [`README.md`](README.md) (what's tracked, fresh-clone bootstrap) ·
[`init.el`](init.el) (the config, section by section) · [`custom.el`](custom.el).
