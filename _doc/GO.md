# Go development

How Go editing works in this Emacs configuration: which packages drive what,
where they're configured, what to do when it breaks. Companion to the
keybinding cheat sheet in [FEATURES.md](FEATURES.md).

## Stack

| Layer | Component | Where it lives |
|---|---|---|
| Compiler / runtime | `go` 1.24.4 | `/usr/bin/go` (or wherever `go env GOROOT` points) |
| LSP server | `gopls` v0.21.1 | `~/go/bin/gopls` — install via `go install golang.org/x/tools/gopls@latest` |
| Major mode | `go-ts-mode` | Built-in (Emacs 30+); auto-selected by `treesit-auto` |
| Tree-sitter grammar | `libtree-sitter-go.so` | `~/.emacs.d/tree-sitter/` (`treesit-install-language-grammar` populates this) |
| LSP client | `eglot` | Built-in; auto-starts on Go buffers — see [section 8 of init.el](init.el) |
| Diagnostics | `flymake` ← eglot ← gopls | Built-in; eglot pipes LSP diagnostics into it |
| Hover / signatures | `eldoc` ← eglot ← gopls | Echo area by default; `C-c d` summons full doc buffer as a 60-col side window |
| Symbol navigation | `xref` ← eglot ← gopls | `M-.` / `M-,` / `M-?` |
| Completion UI | Vertico + consult + orderless | Minibuffer-based — see [Completion flow](#completion-flow) |
| PATH for daemon | `exec-path-from-shell` | Bridges login-shell PATH into Emacs so `gopls` etc. are findable when launched as a systemd daemon |

The config is intentionally **eglot-based, not lsp-mode**: zero per-language setup, built-in, ~1k lines vs. lsp-mode's ~15k. Trade-off is fewer features (no codelens flexibility, no UI heatmaps); for Go-on-gopls that hasn't bitten yet.

## Prerequisites

```bash
# Go toolchain
sudo apt install golang-go               # or use your version manager

# gopls (the LSP server)
go install golang.org/x/tools/gopls@latest

# Confirm it landed somewhere on PATH (and on Emacs' exec-path):
which gopls                              # expect ~/go/bin/gopls or similar
gopls version                            # confirm install succeeded

# Tree-sitter Go grammar — handled automatically on first .go file open by
# `treesit-auto` (init.el's `treesit-auto-install t`), no manual step needed.
# Lands in ~/.emacs.d/tree-sitter/ which is on `treesit-extra-load-path`
# so it persists across restarts.
```

If `gopls` is installed but Emacs can't find it (Eglot errors with "Cannot find program 'gopls'"), it's the daemon-PATH gotcha — see [Troubleshooting](#troubleshooting).

## Project boundary

`gopls` is **module-scoped**. The active "project" is the directory tree of the nearest `go.mod` walking up from the open file. Without a `go.mod`, gopls runs in degraded "GOPATH mode" with limited cross-package resolution and **no auto-import**.

```bash
mkdir -p ~/code/scratch-go && cd ~/code/scratch-go
go mod init scratch-go                   # creates go.mod
```

`emacs main.go` from inside the module → Eglot starts, gopls indexes the module, everything works. From outside any module → Eglot still starts but capabilities are partial.

This is also why `eglot-extend-to-xref` matters (set `t` in [init.el's eglot block](init.el)): when `M-.` jumps from your code into the stdlib (e.g., `Unmarshal` → `encoding/json/decode.go`), the target file is outside your project's eglot session. `eglot-extend-to-xref t` reuses your gopls session to resolve symbols in the visited file rather than refusing.

## Completion flow

Single trigger, single UI for the whole editor — including in-buffer code completion:

```
.go buffer: type `json.Un`
            ↓
press M-TAB (or C-M-i)            ← single manual trigger; no auto-popup
            ↓
`completion-at-point` runs
            ↓
`completion-in-region-function` = `consult-completion-in-region`
            ↓
Eglot's CAPF queries gopls over LSP
            ↓
candidates flow into the minibuffer
            ↓
Vertico renders them vertically,
orderless filters as you type,
marginalia shows type/doc annotations,
embark exposes actions (C-.) on the current candidate
            ↓
RET → buffer is patched, import auto-added if applicable
```

The minibuffer feels like `C-x C-f` because it **is** the same UI — same Vertico, same orderless, same marginalia. There's no separate "code completion popup" to learn; the muscle memory from buffer-switching, file-finding, ripgrep search transfers wholesale.

**No auto-popup as you type**. This is a deliberate choice — see [section 5 of init.el](init.el) for the rationale and the one-line flip to re-enable Corfu's at-point popup if you change your mind.

### Auto-import of unimported packages

gopls ships with `completeUnimported: true` by default. Practical effect:

```go
// File: main.go, with NO `import "encoding/json"` yet.
func main() {
    data := json.Unm│
            ^^^^^^^
//          M-TAB here.
}
```

Vertico minibuffer shows `Unmarshal` (with a marginalia hint that it'll add `encoding/json` to imports). Accept it with RET → gopls inserts `import "encoding/json"` at the top of the file in the same edit. No separate "fix imports" step.

For `goimports`-style cleanup of unused imports on save, set up `eglot-format-buffer` on save or use `gofmt` separately — currently not wired in this config.

## Navigation

LSP-driven via xref. Eglot's xref backend prepends itself to `xref-backend-functions`, so these all flow through gopls:

| Key | Command | What it does |
|---|---|---|
| `M-.` | `xref-find-definitions` | Jump to where the symbol at point is defined. Crosses module boundaries thanks to `eglot-extend-to-xref t` |
| `M-,` | `xref-go-back` | Pop back to the previous position |
| `M-?` | `xref-find-references` | Show all references to the symbol at point in a `*xref*` buffer |
| `M-g i` | `consult-imenu` | Jump to a definition **in this file** via Vertico (gopls feeds the symbol list) |
| `M-s r` | `consult-ripgrep` | Project-wide text search — orthogonal to LSP, useful when gopls doesn't know |

`ggtags` is in the config (see [init.el's ggtags block](init.el)) but only takes over in buffers without an active LSP session — for Go, eglot always wins. Mostly relevant for Java, where Eglot isn't auto-hooked.

## Diagnostics

`flymake` (built-in, on for `prog-mode` via [section 8 of init.el](init.el)) receives error/warning streams from gopls. Visual: red/orange underlines + fringe markers.

| Key | Command |
|---|---|
| `M-n` | `flymake-goto-next-error` |
| `M-p` | `flymake-goto-prev-error` |
| `C-h .` | `display-local-help` (or hover at point with `eldoc`) |

To see all diagnostics in one place: `M-x flymake-show-buffer-diagnostics` (current file) or `flymake-show-project-diagnostics` (entire project).

Diagnostic *categories* gopls emits depend on its config:

- Syntax errors → always on
- Type errors → always on
- `staticcheck` warnings → opt-in; see [Per-project gopls config](#per-project-gopls-config)
- Unused variables → on by default

## Hover / signatures / docs

`eldoc` displays the type / signature / docstring of the symbol at point.

- **Echo area** (default): one line, brief, fast. Gets clobbered by other `message` calls; cheap and unobtrusive.
- **On-demand side window**: press `C-c d` (`eldoc-doc-buffer`, [bound in section 8](init.el)) → full doc opens in a 60-col right-side window. The display rule in init.el matches both `*eldoc*` and `* *eldoc for SYM*` buffer-name variants.

Why not `eldoc-box` (child-frame tooltips, pretty): child frames are GUI-only. In TTY frames (the daemon's common case) eldoc-box silently no-ops *and* bypasses the echo area fallback — net regression. The side-window approach works identically in TTY and GUI.

## Per-project gopls config

Two routes:

### 1. Per-directory via `eglot-workspace-configuration`

Create `.dir-locals.el` in the module root:

```elisp
((go-ts-mode
  . ((eglot-workspace-configuration
      . (:gopls (:staticcheck t
                 :usePlaceholders t
                 :gofumpt t
                 :analyses (:unusedparams t :unusedwrite t)))))))
```

Reopen the file; Eglot picks up the config and re-initialises gopls.

### 2. Global default in init.el

Add to the eglot use-package block:

```elisp
:custom
(eglot-workspace-configuration
 '((:gopls . (:staticcheck t :gofumpt t))))
```

Per-directory wins over global — useful when one repo wants strict `staticcheck` and another doesn't.

Reference: [gopls settings docs](https://github.com/golang/tools/blob/master/gopls/doc/settings.md).

## Configuration map

Where each piece lives:

| Concern | File | Section / line |
|---|---|---|
| Tree-sitter auto-install + grammar load path | [init.el](init.el) | Section 8 (treesit) |
| Eglot hook for `go-ts-mode` | [init.el](init.el) | Section 8 (`eglot` use-package, around line 417) |
| Eglot sync-connect, autoshutdown, xref extension | [init.el](init.el) | Section 8 (`eglot-*` custom vars) |
| Flymake hook + nav keys | [init.el](init.el) | Section 8 (`flymake` use-package) |
| Eldoc side-window display rule | [init.el](init.el) | Section 8 (`display-buffer-alist` near line 421) |
| `gopls`/`go` on `exec-path` for daemon | [init.el](init.el) | Section 1 (`exec-path-from-shell`) |
| Vertico minibuffer + orderless + marginalia | [init.el](init.el) | Section 4 |
| `completion-in-region-function` → consult | [init.el](init.el) | Section 4 (`consult` use-package `:init`) |
| Keybinding cheat sheet | [FEATURES.md](FEATURES.md) | — |

## Troubleshooting

### "Cannot find program 'gopls'"

Eglot couldn't locate gopls on `exec-path`. Causes:

1. gopls not installed → `go install golang.org/x/tools/gopls@latest`
2. `~/go/bin` not on PATH → check `echo $PATH` in a login shell
3. **Daemon PATH gotcha**: Emacs launched by systemd inherits the minimal PAM PATH, not your login PATH. `exec-path-from-shell` ([init.el section 1](init.el)) handles this — but only fires when the predicate matches (`(or (daemonp) (memq window-system '(x pgtk mac ns)))`). Verify with `M-: (executable-find "gopls") RET`.

Fix: `M-x exec-path-from-shell-initialize` then `M-x eglot` again in the buffer.

### Eglot starts but completion returns nothing useful

- Confirm gopls finished indexing — initial run on a fresh monorepo can take 10–30s. Modeline shows `Eglot(go-ts/starting)` during that window.
- Confirm you're inside a `go.mod` module — without one, gopls runs in degraded mode (no cross-package resolution, no completeUnimported).
- Check Eglot's JSON-RPC log: `(setq eglot-events-buffer-size 2000000)` then `M-x eglot-events-buffer`. Look for `completion` requests/responses.

### Tree-sitter grammar warnings on startup

`cannot open shared object file` for `tree-sitter-go.so` → grammar isn't installed yet. Fix:

```
M-x treesit-install-language-grammar RET go RET
```

This installs into `~/.emacs.d/tree-sitter/`, which is on `treesit-extra-load-path` (see [init.el section 8](init.el)) so it persists. `treesit-auto-install t` should do this on first `.go` open, but a fresh checkout occasionally needs the manual nudge.

### `M-.` lands in the wrong place / says "no definition found"

- Check the modeline: is `Eglot(go-ts/...)` present? If not, no LSP backend → `xref` falls through to the next backend (etags, ggtags) which doesn't know Go scoping.
- If Eglot is active and `M-.` still fails on stdlib symbols, check that `eglot-extend-to-xref` is `t` (it is in this config). Without it, xref refuses to follow into files outside the project's eglot session.

### gopls eats CPU after each save / completion is laggy

Likely a large module + analyses enabled. Disable `staticcheck` and the heavier analyses in `.dir-locals.el` for that repo (see [Per-project gopls config](#per-project-gopls-config)).

## What's NOT in this config (yet)

| Feature | Why not | Workaround |
|---|---|---|
| Debugging (DAP) | `dap-mode` is lsp-mode-flavoured; `dape` is the Eglot-aligned alternative but not configured yet | Use `dlv` from the command line in a separate `vterm` |
| `gofmt` on save | Would require `eglot-format-buffer` hook + per-mode opt-in | `M-x eglot-format-buffer` manually, or run `gofmt -w .` from shell |
| `goimports` on save | Same as above; gopls handles imports incrementally during completion | Auto-import via the completion flow handles 90% of cases |
| Test runner UI | None | `M-x compile RET go test ./... RET` |
| Struct tag generation | None | The gomodifytags binary + `M-x compile`, or `go-impl`-style helpers |

If any of these starts hurting, the small additions are documented inline in
[init.el section 8](init.el) as comments — the eglot block already has the
relevant hooks; format-on-save is a 3-line add.

## References

- [Eglot manual](https://www.gnu.org/software/emacs/manual/eglot.html) — the LSP client driving everything LSP-shaped here
- [gopls user guide](https://github.com/golang/tools/blob/master/gopls/doc/user.md)
- [gopls settings reference](https://github.com/golang/tools/blob/master/gopls/doc/settings.md)
- [Tree-sitter grammar usage in Emacs](https://www.gnu.org/software/emacs/manual/html_node/elisp/Parsing-Program-Source.html)
- [Local cheat sheet](FEATURES.md) — keybindings across all modes, not Go-specific
