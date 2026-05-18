# Features & cheat sheet

What this Emacs 30.1 config actually gives you, grouped by workflow. Section numbers
match the section headers in [`init.el`](init.el). For the package list and *why* each
choice was made, read the comments in [`init.el`](init.el) itself — this file is the
"what keys do I press" companion.

Language-specific guides (architecture, workflows, troubleshooting):

- [Go development](GO.md) — `go-ts-mode` + Eglot + gopls + Vertico-driven completion

> Conventions in the tables: `C-x` = Ctrl+x, `M-x` = Alt/Meta+x, `C-S-x` = Ctrl+Shift+x,
> `SPC` = space, `RET` = Enter. Built-in packages are marked **(built-in)** — they ship
> with Emacs 30 and the config only enables/configures them.

---

## 1. Minibuffer: finding things (Vertico ecosystem — §4)

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
| `C-s` | `consult-line` | Search lines in this buffer (incremental, jumps live) |
| `M-s r` | `consult-ripgrep` | **ripgrep across the whole project** |
| `M-s f` | `consult-find` | Find files by name |
| `M-g i` | `consult-imenu` | Jump to a definition in this file (functions / classes …) |
| `M-g g` | `consult-goto-line` | Go to line number |
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

---

## 2. ⭐ Combo — project-wide search-and-replace with undo (§4)

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

## 3. Embark — a context menu for "the thing at point" (§4)

| Key | Command | What it does |
|---|---|---|
| `C-.` | `embark-act` | Act on point / the current minibuffer candidate — the offered actions change with the object type (file → open/rename/grep; symbol → describe/find-def; …) |
| `C-;` | `embark-dwim` | "Do What I Mean" — run the single most sensible default action |
| `C-h B` | `embark-bindings` | Browse every active key binding via `completing-read` |

`embark-consult` glue: exporting from a consult command formats the export buffer nicely
and previews entries at point.

---

## 4. In-buffer code completion — Corfu + Cape (§5)

- Popup appears automatically after **2 characters**, **0.2 s** delay (`corfu-auto`,
  `corfu-auto-prefix 2`, `corfu-auto-delay 0.2`); `corfu-cycle` wraps the list.
- `corfu-popupinfo` **(built-in extension)**: a second popup beside the list shows the
  selected candidate's docstring / signature (0.5 s to first appear, 0.2 s when stepping
  between candidates).
- `cape` adds generic completion backends usable in any buffer: **dabbrev** (words from
  open buffers), **file paths**, **elisp symbols / elisp code blocks**. Eglot layers
  language-aware completions on top in programming buffers.

---

## 5. Motion & editing power tools (§7)

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

Always-on editing defaults (§2, §4): `electric-pair-mode` (auto-insert matching brackets
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

---

## 6. Help system, upgraded (§2, §7)

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

## 7. Project, LSP & languages (§8)

- `project.el` **(built-in)**: project-aware file/buffer/command commands under `C-x p`.
- **envrc**: direnv integration. When you visit a file under a directory with an
  `.envrc`, envrc runs `direnv export json` and applies the result **buffer-locally**
  (`process-environment` + `exec-path`). Two concrete wins: Eglot picks the right server
  binary per project (e.g. a Go monorepo's pinned `gopls` in `./bin/`), and Node tooling
  follows whatever `nvm`/`volta`/`asdf` declared. Complements `exec-path-from-shell` in
  §1 (one-shot global harvest at daemon launch) — neither replaces the other.
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
- **markdown-mode**: `README.md` opens in GitHub-flavoured Markdown mode (`gfm-mode`);
  `markdown-command` is `pandoc`.
- **jinx**: fast spell checker for every text-mode buffer (org, markdown, gfm, ...).
  Backed by the `enchant-2` C binary — orders of magnitude faster than `flyspell`.
  `M-$` (was `ispell-word`) opens a vertico-driven correction menu for the word at point;
  `C-M-$` switches languages mid-buffer. Pinned to `en_US` by default; first load
  compiles a small C module (~2 s, one-off). Requires `apt install enchant-2
  libenchant-2-dev`.

---

## 8. Git — Magit + diff-hl (§9)

| Key | Command | What it does |
|---|---|---|
| `C-x g` | `magit-status` | The full Git porcelain — stage hunks, commit, rebase, log, … |
| `C-x M-g` | `magit-dispatch` | Menu of all Magit commands |

- **diff-hl**: live added/changed/removed markers in the fringe (in `prog-mode` and
  Dired); refreshes right after a Magit commit/stage via `magit-post-refresh`.
- **magit-todos**: adds a "TODOs" section to the Magit status buffer listing
  `TODO`/`FIXME`/`HACK`/`NOTE`/`BUG` keywords found across the repo (uses `rg` if present,
  else `git grep`); jump to them like any other section.
- **hl-todo**: colours those same keywords in code comments (`prog-mode`).

---

## 9. Terminal — vterm (§10)

| Key | Command | What it does |
|---|---|---|
| `C-c t` | `vterm` | A real libvterm-backed terminal emulator — far more capable than `term` / `eshell` |

`vterm-max-scrollback` 10000 lines. `vterm-always-compile-module t` compiles the C module
when `vterm.el` loads, so a missing `cmake` / `libvterm-dev` shows up as a loud startup
error rather than on first `M-x vterm`. (Prefer no C toolchain? Comment the block out and
use `M-x eshell`.)

---

## 10. Snippets — YASnippet (§6)

`yas-global-mode` is on; `yasnippet-snippets` ships a large ready-made collection for many
major modes. Type a snippet's abbreviation and press `TAB` to expand it; `TAB` again jumps
between fields. Personal snippets live in [`snippets/`](snippets/).

---

## 11. Appearance (§11)

- **doom-themes** — `doom-one` loaded by default (swap for any `doom-*`); bold + italic
  enabled; `doom-themes-org-config` tweaks Org faces to match.
- **doom-modeline** — `doom-modeline-mode`, height 25.
- **nerd-icons** — glyph set used by doom-modeline (and optionally Dired/Corfu). Run
  `M-x nerd-icons-install-fonts` **once** after install to fetch the font.

---

## 12. Org-mode — light touch (§12)

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

## 13. AI / agent tooling (§13)

`eca` (Editor Code Assistant client), `acp` (Agent Client Protocol library) and
`shell-maker` (the shared shell framework they build on) are installed but **not yet bound
to keys** — invoke via `M-x eca` etc. Add `(use-package eca ...)` config in §13 of
[`init.el`](init.el) when you want bindings or tweaks.

---

## Operational notes

- **No package-archive refresh at startup** (network-free boot). Before installing a new
  package run `M-x my/package-refresh`, then restart — otherwise the first launch after
  adding it fails to find it. See also [`README.md`](README.md).
- **New `M-x customize` settings go to [`custom.el`](custom.el)** (`custom-file` is set in
  §2). The legacy `custom-set-variables` block at the bottom of [`init.el`](init.el) is
  kept only for compatibility with older Emacs.
- **no-littering** redirects package state into `var/` (volatile runtime state) and `etc/`
  (config-ish data); [`.gitignore`](.gitignore) ignores both in one line each. The orphaned
  pre-no-littering files still at the repo root (`transient/`, `tramp`, `history`,
  `auto-save-list/`, `init.el~`, `init.el.bak-*`) are safe to `rm`.
- `:ensure nil` packages are Emacs built-ins — they are never pulled from MELPA. Everything
  else is auto-installed on first run because `use-package-always-ensure` is `t`.

---

See also: [`README.md`](README.md) (what's tracked, fresh-clone bootstrap) ·
[`init.el`](init.el) (the config, section by section) · [`custom.el`](custom.el).
