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
| `M-g s` | `consult-eglot-symbols` | **Project-wide LSP symbol jump** (LSP buffers only — bound in `eglot-mode-map`). Unlike `M-g I` (open buffers, same major mode), this hits the LSP's `workspace/symbol` index so unopened files are found too. See §7 |
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
| `C-=` | `er/expand-region` | Grow the region semantically: word → sexp → string → defun → … (`C-S-=` shrinks it back) |
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

---

## 7. Project, LSP & languages ([`init-languages.el`](lisp/init-languages.el))

- `project.el` **(built-in)**: project-aware file/buffer/command commands under `C-x p`.
- **envrc**: direnv integration. When you visit a file under a directory with an
  `.envrc`, envrc runs `direnv export json` and applies the result **buffer-locally**
  (`process-environment` + `exec-path`). Two concrete wins: Eglot picks the right server
  binary per project (e.g. a Go monorepo's pinned `gopls` in `./bin/`), and Node tooling
  follows whatever `nvm`/`volta`/`asdf` declared. Complements `exec-path-from-shell` in
  [`init.el`](init.el)'s bootstrap (one-shot global harvest at daemon launch) — neither replaces the other.
  Per-project setup: drop an `.envrc`, then `direnv allow` once. Needs the `direnv`
  binary (`apt install direnv`); without it the mode silently no-ops.
- **Eglot** **(built-in)**: a zero-config LSP client. Auto-starts when you open a file in
  a hooked mode **and** the language server binary is on `PATH`. Hooked modes:
  `python-ts-mode`, `go-ts-mode`, `rust-ts-mode`, `js-ts-mode`, `typescript-ts-mode`,
  `c-ts-mode`, `c++-ts-mode` (so: pyright/pylsp, gopls, rust-analyzer,
  typescript-language-server, clangd). `eglot-autoshutdown t` kills the server when its
  last buffer closes; the JSON-RPC events log is disabled.
- **consult-eglot**: `M-g s` → `consult-eglot-symbols` (bound only in
  `eglot-mode-map`). Asks the language server's `workspace/symbol` index for **every**
  symbol in the project, not just open buffers — fills the gap between `consult-imenu`
  (this file) and `consult-imenu-multi` (open buffers of the same major mode). Same
  vertico + orderless + marginalia UI as the rest of §1.
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
  Where `expand-region` (`C-=`, §5) grows by lisp sexps and gets non-Lisp wrong,
  combobulate operates on real syntactic nodes — if-statement, parameter list, JSX
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
  Globally enabled; toggle off per buffer with `M-x breadcrumb-local-mode`. From GNU
  ELPA (same author as eglot-booster and `indent-bars`).
- **flymake** **(built-in)**: on-the-fly diagnostics, fed by Eglot from the LSP. `M-n` /
  `M-p` jump to the next / previous error.
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
  to `eglot-mode-map` so it doesn't shadow `C-c .` in non-LSP buffers. The unified
  transient already lists `eglot-code-action-organize-imports` /
  `eglot-code-action-quickfix` as entries, so no separate keys for those.
- **Inlay hints**: parameter names, inferred types, `&` reference markers etc.
  rendered inline by the LSP. Built-in in Emacs 30 — no external package. Enabled
  via `(eglot-managed-mode . eglot-inlay-hints-mode)` so it lights up on every
  Eglot-attached buffer (Go parameter names before each arg, Rust `: Vec<i32>`
  after `let x = vec![…]`, …). Toggle per-buffer at runtime with
  `M-x eglot-inlay-hints-mode`; disable for a noisy language by removing its
  hook in [`init-languages.el`](lisp/init-languages.el) rather than touching the
  global setting.
- **markdown-mode**: `README.md` opens in GitHub-flavoured Markdown mode (`gfm-mode`);
  `markdown-command` is `pandoc`.
- **jinx**: fast spell checker for every text-mode buffer (org, markdown, gfm, ...).
  Backed by the `enchant-2` C binary — orders of magnitude faster than `flyspell`.
  `M-$` (was `ispell-word`) opens a vertico-driven correction menu for the word at point;
  `C-M-$` switches languages mid-buffer. Pinned to `en_US` by default; first load
  compiles a small C module (~2 s, one-off). Requires `apt install enchant-2
  libenchant-2-dev`.
- **lua-mode** (MELPA): `.lua` files open in `lua-mode` — regex-based highlighting.
  Picked over the built-in `lua-ts-mode` because the upstream
  `tree-sitter-grammars/tree-sitter-lua` grammar is ABI 15 at HEAD and Emacs
  30.1 caps at ABI 14 (same reason `css` and `json` are excluded from `treesit-auto`
  in [`init-languages.el`](lisp/init-languages.el)). **LSP**: Eglot attaches
  `lua-language-server` (LuaLS) — go-to-def, hover, `consult-eglot-symbols`,
  Flymake diagnostics. The server isn't on apt; [`shell/install-user.sh`](shell/install-user.sh)
  installs it from upstream GitHub releases into `~/.local/share/lua-language-server/`
  with a `~/.local/bin/` symlink. If the binary is missing, Eglot just declines to
  start — highlighting still works. No formatter / REPL wired.
- **dape**: Debug Adapter Protocol client — an in-editor step debugger, the
  Eglot-spirit counterpart to `dap-mode`. Core-only deps (`jsonrpc`), no
  `lsp-mode`, no child frames; breakpoints render in the buffer **margin**
  (a `B` glyph) so they stay visible on TTY frames (this config runs daemon +
  `emacsclient -nw`). `M-x dape` starts a session and prompts for a built-in
  config (`dlv`, `debugpy`, `codelldb`, `gdb`, `js-debug`, …) — you install the
  adapter **binary**, not write configs; only Go's `dlv` is on `PATH` today.
  Per-project overrides live in `.dir-locals.el`. Breakpoints persist across
  Emacs sessions (`dape-breakpoint-save` on quit, `dape-breakpoint-load` on
  startup). Modified buffers are saved before each run. Keymap below.

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

## 10. Snippets — YASnippet ([`init-snippets.el`](lisp/init-snippets.el))

`yas-global-mode` is on; `yasnippet-snippets` ships a large ready-made collection for many
major modes. Type a snippet's abbreviation and press `TAB` to expand it; `TAB` again jumps
between fields. Personal snippets live in [`snippets/`](snippets/).

---

## 11. Appearance ([`init-appearance.el`](lisp/init-appearance.el))

- **doom-themes** — `doom-one` loaded by default (swap for any `doom-*`); bold + italic
  enabled; `doom-themes-org-config` tweaks Org faces to match.
- **doom-modeline** — `doom-modeline-mode`, height 25.
- **nerd-icons** — glyph set used by doom-modeline, `nerd-icons-dired` (§12) and Corfu.
  Run `M-x nerd-icons-install-fonts` **once** after install to fetch the font.

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
  `#+begin_src`).
- **org-modern**: restyles headings, lists, checkboxes, tables, blocks and timestamps —
  pure display, never edits your files. Also styles the agenda.
- **org-appear**: temporarily reveals the `*bold*` / `=verbatim=` / `[[link]]` markup of
  whichever element point is on — the complement to `org-hide-emphasis-markers`, so you can
  still edit the markers without globally un-hiding them.

(Room to grow later: org-roam, org-agenda, capture templates.)

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
