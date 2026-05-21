# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal Emacs 30.1 config. Tracked: hand-authored Elisp ([`init.el`](init.el), [`early-init.el`](early-init.el), [`custom.el`](custom.el), [`lisp/`](lisp/)), bootstrap scripts ([`shell/`](shell/)), the [pre-commit hook](.githooks/pre-commit), and docs (`CLAUDE.md` itself, [`README.md`](README.md), [`FEATURES.md`](FEATURES.md), [`_doc/GO.md`](_doc/GO.md)). Everything reproducible or stateful is gitignored — `elpa/`, `eln-cache/`, the no-littering `var/` + `etc/`, the vendored `eca/` binary, and `tree-sitter/` grammars.

The companion to this file is [`FEATURES.md`](FEATURES.md) (the "what keys do I press" cheat sheet) — keep them in sync when bindings or workflow change.

## Architecture: thin loader + per-area modules

[`init.el`](init.el) is intentionally tiny. It bootstraps the package system (MELPA + GNU ELPA, `use-package-always-ensure t`, `no-littering`, `exec-path-from-shell`), pushes `lisp/` onto `load-path`, then `mapc #'require`s a fixed list of `init-<area>` modules in the order shown in the file's header comment. **That load order is load-bearing**: cross-section `use-package :after` wiring in the modules (e.g. `consult-eglot :after (consult eglot)`, `magit-delta :after magit`) assumes earlier modules have already declared their packages. Do not reshuffle without verifying the `:after` edges.

The 16 modules under [`lisp/`](lisp/) (`init-defaults`, `init-system-packages`, `init-completion`, `init-corfu`, `init-snippets`, `init-editing`, `init-languages`, `init-git`, `init-terminal`, `init-appearance`, `init-dirvish`, `init-org`, `init-obsidian`, `init-org-roam`, `init-ai`, `init-aidermacs`) each correspond to one section of the pre-2026-05-19 monolithic `init.el` (see `git log --oneline` for the split commits). Section numbers in module headers refer to that pre-split layout — they're history, not a current TOC; read the module names instead.

Local Elisp (not on MELPA): [`lisp/claude-jobs-view.el`](lisp/claude-jobs-view.el) — a `tabulated-list-mode` UI over the external `jobctl` CLI for persistent Claude Code sessions. Entry point `M-x claude-jobs-view`. Loaded lazily via `:commands` autoload in [`lisp/init-ai.el`](lisp/init-ai.el).

## Startup discipline (`early-init.el`)

[`early-init.el`](early-init.el) runs BEFORE the package system and the first frame. It owns:
- GC tuning (`gc-cons-threshold` raised to `most-positive-fixnum` for startup, restored to 32 MB on `emacs-startup-hook`).
- `file-name-handler-alist` suspension during init (every `require` walks it — emptying it saves measurable time).
- Frame chrome via `default-frame-alist` (menu/tool/scroll bars off **before** the first frame paints — calling `menu-bar-mode -1` in `init.el` is too late and causes a flash).
- `package-enable-at-startup nil` so the implicit pre-init `package-activate-all` doesn't duplicate `init.el`'s explicit `(package-initialize)`.

Don't move any of those into `init.el` — the cost has already been paid by the time it runs.

## Package-install discipline (load-bearing quirks)

- **The archive is NEVER refreshed at startup** (network-free boot). After adding a new `use-package` block whose package isn't already in `elpa/`, run `M-x my/package-refresh` then restart Emacs — otherwise the install fails to find the package.
- **`use-package-always-ensure` is `t`** — plain `(use-package foo …)` auto-installs `foo` from MELPA. **Built-ins must say `:ensure nil`** (e.g. `eglot`, `project`, `flymake`, `ibuffer`, `recentf`, `savehist`, `saveplace`, `winner`, `which-key`, `org`, `vertico-directory`, `corfu-popupinfo`, `dired`). If you forget, MELPA pulls a redundant copy that may shadow the built-in.
- **GitHub-only packages use `use-package`'s `:vc` keyword** (Emacs 30 native `package-vc-install`, no straight.el / quelpa needed) — see `eglot-booster` and `combobulate` in [`lisp/init-languages.el`](lisp/init-languages.el). The pinned URLs are recorded in [`custom.el`](custom.el) under `package-vc-selected-packages` so a fresh clone reproduces the same fetch. Update later via `M-x package-vc-upgrade RET <name> RET`.
- **`M-x customize` writes to [`custom.el`](custom.el)** (`custom-file` is set in [`lisp/init-defaults.el`](lisp/init-defaults.el), which also `(load custom-file)`). There is intentionally **no** `custom-set-variables` block in `init.el` — keeping a duplicate would let "whichever loads last" silently win.
- **`no-littering` is loaded eagerly (`:demand t`)** in `init.el` BEFORE the modules require packages that drop state files. The repo's `.gitignore` whitelists `/var/` and `/etc/` in one line each, replacing per-file ignores.

## Build / test / run

This is plain Elisp — there is no compile or test command. Workflow:

- **Reload after editing**: `M-x load-file RET init.el RET`, or just restart Emacs. Modules can be reloaded individually via `M-x load-file RET lisp/init-<area>.el RET` once their `(require 'init-<area>)` has already run once (otherwise `provide` hasn't registered).
- **Stale `.elc` artefacts**: byte-compiled `*.elc` files sit next to their `.el` siblings in [`lisp/`](lisp/) and are gitignored. `load-prefer-newer t` (set in `early-init.el`) means a fresh `.el` wins, but if you suspect a stale `.elc` is being preferred, delete it: `fdfind -e elc -X rm` from this directory.
- **Tree-sitter grammars** live in [`tree-sitter/`](tree-sitter/) (gitignored, regenerated by `treesit-install-language-grammar`). `treesit-extra-load-path` in `init-languages.el` adds that dir so next startup finds them. Three grammars (`css`, `json`, `lua`) are deliberately excluded from `treesit-auto-langs` — they're ABI 15 upstream and Emacs 30 caps at ABI 14. Falls back to the built-in `css-mode` / `js-json-mode` / MELPA `lua-mode`.

## Fresh-clone bootstrap

```bash
git clone <remote> ~/.emacs.d
git -C ~/.emacs.d config core.hooksPath .githooks   # wire pre-commit (local config, not tracked)
~/.emacs.d/shell/install.sh                         # apt + npm/cargo/go/rustup deps
emacs                                               # first launch: use-package installs missing packages
```

[`shell/install.sh`](shell/install.sh) is a thin orchestrator over two halves: [`install-root.sh`](shell/install-root.sh) (apt packages; self-elevates via `sudo`) and [`install-user.sh`](shell/install-user.sh) (cargo / go / rustup / npm; refuses to run as root so toolchain caches don't land under `/root/`). Shared helpers live in [`install-lib.sh`](shell/install-lib.sh). `install-user.sh` flips npm's global prefix to `$HOME/.npm-global` so `npm install -g` no longer needs sudo — add `$HOME/.npm-global/bin` to `PATH` once for the new prefix to be useful.

After first launch, also:
- `M-x nerd-icons-install-fonts` once (modeline glyphs).
- `M-x org-roam-db-sync` once (first roam DB build, `~/code/org-roam/`).

## Pre-commit hook

[`.githooks/pre-commit`](.githooks/pre-commit) runs `gitleaks git --staged`. `core.hooksPath` is local config, so re-run `git config core.hooksPath .githooks` after any fresh clone. If `gitleaks` isn't on `PATH`, the hook prints a warning and no-ops — install from the upstream releases.

If the hook blocks a commit, fix the underlying secret; do not reach for `--no-verify` (per global rule).

## Conventions & gotchas worth knowing before editing

- **`$HOME` is itself a git repo** (the dotfiles tree). [`lisp/init-languages.el`](lisp/init-languages.el) advises `project-try-vc` to ignore `$HOME` as a project root, and adds `.project`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `CLAUDE.md`, `package.json`, `Makefile` to `project-vc-extra-root-markers`. Drop an empty `.project` file in any directory you want treated as a project. If project root detection seems stuck on a stale answer after editing the markers list, run `M-x fenrir/project-reset-cache` — `project-try-vc` memoises via `vc-file-setprop` and the function clears the `vc-file-prop-obarray`.
- **`$HOME` is also a Magit hazard**: with ~1500 tracked files plus `status.showUntrackedFiles=no` hiding ~1M items, the untracked-files section and `diff-hl-dired-mode` were dropped from this config — see [`lisp/init-git.el`](lisp/init-git.el).
- **Vertico, not Corfu, drives in-buffer completion**: `completion-in-region-function` is bound to `consult-completion-in-region` in [`lisp/init-completion.el`](lisp/init-completion.el)'s `:init`. `global-corfu-mode` is **not** enabled — Corfu stays installed (`:defer t`) so flipping back is a one-line edit. Don't enable `global-corfu-mode` casually; it sets its own buffer-local `completion-in-region-function` and silently overrides the consult routing.
- **`C-x b` is `ibuffer`, not `switch-to-buffer`** — the consult fuzzy switcher lives on `C-x B` (shift). Reason: tmux's default `C-b` prefix swallows the second keystroke in a TTY frame, ruling out the default `C-x C-b`.
- **`eglot-booster` monkey-patches `eglot--connect`**. An Emacs upgrade may break it; recover at runtime with `M-x eglot-booster-mode` (toggles off). Built-in Eglot is recommended over `lsp-mode` here.
- **DAP debugging is `dape`, not `dap-mode`** — `dape` (GNU ELPA; the `use-package` block at the end of [`lisp/init-languages.el`](lisp/init-languages.el)) renders breakpoints in the buffer **margin** (`B` glyph), visible on TTY frames; `dap-mode` draws them with GUI-only fringe bitmaps (invisible in `emacsclient -nw`) and pulls in the `lsp-mode` stack that conflicts with Eglot. Don't swap in `dap-mode` or any child-frame / posframe debug UI. It's a plain `:ensure t` block — a real GNU ELPA package, contrast the `:vc` (GitHub-only) and `:ensure nil` (built-in) cases in the [package-install discipline](#package-install-discipline-load-bearing-quirks) section. Debug-adapter binaries live outside the repo: only Go's `dlv` is on `PATH`; `debugpy` / `gdb` / `codelldb` / `vscode-js-debug` install per language as needed. Keybindings are catalogued in [FEATURES.md §7](FEATURES.md).
- **OSC 52 clipboard bridge** (TTY-only) is wired in [`lisp/init-defaults.el`](lisp/init-defaults.el) — `interprogram-cut-function` emits `\e]52;c;...\a` so cuts cross the tmux/SSH boundary to the host clipboard. Don't override `interprogram-cut-function` in another module.
- **Byte-compilation byproducts** (`init-<area>.elc`) are gitignored but persist locally; they're regenerated on demand. Timestamped backups (`init.el.bak-YYYYMMDD-HHMM`) from ad-hoc edits are also gitignored — clean them up periodically.

## Language-specific docs

[`_doc/GO.md`](_doc/GO.md) — Go workflow (go-ts-mode + Eglot + gopls + Vertico-driven symbol search). Future per-language guides land in [`_doc/`](_doc/).
