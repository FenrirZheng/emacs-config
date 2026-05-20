# Spec: Add `dape` (DAP debugger) to the Emacs config

Status: draft — awaiting approval
Date: 2026-05-20
Author: fenrir (with Claude Code)

## Objective

Wire the **`dape`** package (Debug Adapter Protocol client) into this Emacs
config so the user has an in-editor step debugger across the languages already
covered by Eglot (Go, Python, Rust, C/C++, JS/TS).

`dape` was installed ad-hoc earlier today (2026-05-20 18:03) via
`package-vc-install` (version 0.27.1) but is **not referenced anywhere in
`init.el` or the modules** — it is currently a dead orphan checkout. This change
makes it a first-class, reproducible part of the config.

**Why `dape` and not `dap-mode`:** this config is daemon + `emacsclient -nw`
inside tmux — every frame is a TTY frame. `dap-mode` draws breakpoints with
GUI-only fringe bitmaps (invisible on TTY) and pulls in the whole `lsp-mode`
stack, conflicting with the config's Eglot. `dape` draws breakpoints in the
buffer **margin** (TTY-visible), has no child-frame / posframe UI, and depends
only on Emacs core (`jsonrpc`). It is the Eglot-spirit DAP client.

**Success looks like:** `M-x dape` starts a debug session; on a Go project
(adapter `dlv`, already on PATH) the user can set a breakpoint, hit it, and step
— all in a TTY frame.

## Tech Stack

- Emacs 30.1 (daemon, systemd-launched, TTY-first)
- `dape` — DAP client. Pulled from **GNU ELPA** (not the current VC checkout).
  Requires Emacs ≥ 29.1 + `jsonrpc` ≥ 1.0.25 (both satisfied).
- `repeat-mode` — already enabled in [init-defaults.el](lisp/init-defaults.el);
  gives ergonomic step/continue without re-pressing the `C-x C-a` prefix. No new
  wiring needed.
- Debug adapters (external binaries, **out of scope for this change** — listed
  for the follow-up): Go `dlv` (✅ already on PATH), Python `debugpy`, C/C++
  `gdb` ≥ 14.1, Rust/C++ `codelldb`, JS/TS `vscode-js-debug`.

## Commands

This is a plain Elisp config — no build/test/lint pipeline.

```
Reload the module:   M-x load-file RET lisp/init-languages.el RET
Apply live (daemon): emacsclient -e '(progn ...side-effects... :ok)'
Query the daemon:    emacsclient -e '(FORM)'
Refresh archives:    M-x my/package-refresh   (startup never auto-refreshes)
```

## Project Structure

```
lisp/init-languages.el   → section 8 "Project, LSP & languages".
                           The dape use-package block is appended here,
                           AFTER the markdown-mode block, BEFORE
                           (provide 'init-languages).
custom.el                → package.el will append `dape` to
                           package-selected-packages here on reinstall —
                           this is what makes a fresh clone reproduce it.
SPEC.md                  → this document.
```

No new files. No change to [init.el](init.el)'s module load order.

## Code Style

Match the surrounding `use-package` blocks in
[init-languages.el](lisp/init-languages.el): a WHY-comment block above the
block (explain the gotcha, not the obvious), English only, `:custom` for
defcustoms, `:hook` for hooks. No `:ensure nil` — `dape` is a real GNU ELPA
package, so the config's `use-package-always-ensure t` default (`:ensure t`)
is correct (contrast `eglot`, which is built-in and needs `:ensure nil`).

Planned block (the source of truth for implementation):

```elisp
;; dape: Debug Adapter Protocol client.  The Eglot-spirit counterpart to
;; dap-mode -- core-only deps (jsonrpc), no lsp-mode, no child frames.
;; Breakpoints render in the buffer MARGIN ("B"), not the fringe, so they
;; stay visible on TTY frames (this whole config is daemon + emacsclient -nw).
;; That margin-vs-fringe difference is exactly why dap-mode is rejected here:
;; its fringe-bitmap breakpoints are invisible on a terminal frame.
;;
;; dape ships built-in `dape-configs' entries for debugpy / dlv / codelldb /
;; gdb / js-debug -- you install the adapter BINARY, not write configs.  Only
;; `dlv' (Go) is on PATH today; other languages need their adapter installed
;; before `M-x dape' can debug them.  Per-project overrides: `.dir-locals.el'.
;;
;; `repeat-mode' (enabled in init-defaults) makes step/continue repeatable
;; without re-pressing the `C-x C-a' prefix each time.
(use-package dape
  :custom
  (dape-buffer-window-arrangement 'right)  ; info + REPL docked right
  (dape-info-hide-mode-line t)             ; reclaim modeline in info buffers
  (dape-inlay-hints t)                     ; variable values shown inline
  :hook
  ;; Persist breakpoints across Emacs sessions.
  (kill-emacs . dape-breakpoint-save)
  (after-init . dape-breakpoint-load)
  :config
  ;; Save modified buffers before a run -- matters for interpreted langs.
  (add-hook 'dape-start-hook (lambda () (save-some-buffers t t))))
```

## Testing Strategy

No automated tests (Elisp config). Verification is by `emacsclient` query
against the live daemon plus one manual smoke test.

Post-apply daemon queries (all must hold):
- `(fboundp 'dape)` → `t`
- `dape-buffer-window-arrangement` → `right`
- `dape-info-hide-mode-line` → `t`
- `dape-inlay-hints` → `t`
- `(memq 'dape-breakpoint-save kill-emacs-hook)` → non-nil
- `dape-start-hook` contains the save-some-buffers lambda
- `(memq 'dape package-selected-packages)` → non-nil (reproducibility check)

Manual smoke test (user, in a TTY frame): open a Go file in a project with a
`go.mod`, `M-x dape`, pick the `dlv` config, set a breakpoint with `C-x C-a b`,
confirm the `B` margin marker appears, run, confirm the session stops at the
breakpoint and `dape-info` shows locals/stack.

## Boundaries

- **Always:** match the surrounding `use-package` style; English WHY-comments;
  verify every side-effect with an `emacsclient` query after applying; apply to
  the daemon live (no restart).
- **Ask first:** installing language debug adapters (`debugpy`, `gdb`,
  `codelldb`, `vscode-js-debug`); `git commit`; any keybinding change beyond
  dape's default `C-x C-a` prefix; touching `custom.el` by hand.
- **Never:** kill or restart the daemon (`pkill`, `systemctl restart`,
  `kill-emacs`) — it holds live buffers/LSP sessions; enable any GUI-only debug
  UI; `git push` or open PRs; commit without explicit approval.

## Success Criteria

1. The `dape` `use-package` block is present in
   [init-languages.el](lisp/init-languages.el), styled to match the file.
2. `dape` is installed from **GNU ELPA** (the VC checkout removed) and recorded
   in `package-selected-packages` (`custom.el`) — a fresh clone reproduces it.
3. All daemon-query checks in **Testing Strategy** pass.
4. `M-x dape` launches; a Go debug session via `dlv` starts and hits a
   breakpoint shown as a `B` margin marker on a TTY frame.
5. Daemon was never restarted; no unrelated config changed.

## Open Questions

None blocking. Resolved decisions:
- Install source — **GNU ELPA** (`package-delete` the VC checkout, reinstall).
- Adapter installs — **out of scope**; tracked as the follow-up below.

## Follow-up (not this change)

Install debug adapters per language as needed (see the research summary):
`pip install debugpy` (into the target venv); `sudo apt install gdb` (Debian 13
ships 16.3, DAP-capable); unzip `codelldb` `.vsix` into `~/.emacs.d/debug-adapters/`;
unzip `vscode-js-debug` release tarball likewise. Go's `dlv` is already present.
