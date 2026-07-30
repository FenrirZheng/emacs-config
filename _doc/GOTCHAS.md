# Editing traps — the evidence behind the rules

Long-form companion to [CLAUDE.md → Editing traps](../CLAUDE.md#editing-traps--rules-that-bite).
Each rule is stated in one line there; here is why it exists, so a future editor can tell a
real regression from a harmless-looking cleanup.

## `$HOME` is itself a git repo

The dotfiles tree makes `$HOME` a VC root, which two subsystems get wrong.

**project.el.** [`init-languages.el`](../lisp/init-languages.el) advises `project-try-vc`
to ignore `$HOME` as a project root, and adds `.project`, `Cargo.toml`, `go.mod`,
`pyproject.toml`, `CLAUDE.md`, `package.json`, `Makefile` to
`project-vc-extra-root-markers`. Drop an empty `.project` file in any directory you want
treated as a project. If root detection seems stuck on a stale answer after editing the
markers list, run `M-x fenrir/project-reset-cache` — `project-try-vc` memoises via
`vc-file-setprop`, and that function clears the `vc-file-prop-obarray`.

**Magit.** With ~1500 tracked files plus `status.showUntrackedFiles=no` hiding ~1M items,
`diff-hl-dired-mode` was dropped from this config (see
[`init-git.el`](../lisp/init-git.el)). The untracked-files section used to be dropped for
the same reason (a `remove-hook` on `magit-status-sections-hook`), but that is no longer
needed and was restored: Magit now reads the **repo-local** `status.showUntrackedFiles` in
`magit-list-untracked-files` (returns nothing when it's `no`, so `$HOME` is never walked)
and caps any listing at `magit-status-file-list-limit` (100).

**Don't re-add that `remove-hook`** — it hides untracked files in every *normal* repo to
solve a problem Magit already solves for `$HOME`.

## Vertico, not Corfu, drives in-buffer completion

`completion-in-region-function` is bound to `consult-completion-in-region` in
[`init-completion.el`](../lisp/init-completion.el)'s `:init`. `global-corfu-mode` is **not**
enabled — Corfu stays installed (`:defer t`) so flipping back is a one-line edit.

Don't enable `global-corfu-mode` casually: it sets its own buffer-local
`completion-in-region-function` and silently overrides the consult routing.

## `C-x b` is `ibuffer`, not `switch-to-buffer`

The consult fuzzy switcher lives on `C-x B` (shift). Reason: tmux's default `C-b` prefix
swallows the second keystroke in a TTY frame, ruling out the default `C-x C-b`.

## eglot-booster monkey-patches `eglot--connect`

A `:filter-args` advice (`eglot-booster--wrap-contact`) plus an `:around` on
`jsonrpc--json-read`. An Emacs **or Eglot** upgrade may break it; recover at runtime with
`M-x eglot-booster-mode` (toggles off). Verified intact against the ELPA Eglot 1.23 bump —
both advices still attach.

## Eglot IDE keybindings: three regression traps

The bindings live in the core `:bind (:map eglot-mode-map …)` in
[`init-languages.el`](../lisp/init-languages.el): `C-c .` code actions, `C-c r` rename,
`C-c i` organize-imports, `C-c x` extract, `C-c f` `eglot-format`, `C-c h c` / `h t`
call / type hierarchy, `C-c h i` toggle inlay hints, `C-c h s` toggle semantic tokens. Full
prose: [FEATURES.md §7](../FEATURES.md).

1. **These refactor keys are deliberately NOT under `C-c o`** — that prefix belongs to
   combobulate (`combobulate-key-prefix`; `C-c o n` is combobulate-rename) and would collide
   in buffers where both minor modes are live.
2. **`C-c f` (`eglot-format`) is manual only.** apheleia owns format-on-save; never add
   `eglot-format` / `eglot-format-buffer` to `before-save-hook` or it double-formats against
   apheleia and reintroduces a save-time cursor jump.
3. **`eglot-semantic-tokens-mode` (`C-c h s`) is intentionally a per-buffer toggle, not a
   global hook** — it can fight tree-sitter font-lock, and its extra faces collapse on an
   8/16-colour TTY. Don't "helpfully" globalize it.

Inlay hints, by contrast, ARE global-on (`eglot-managed-mode` → `eglot-inlay-hints-mode`);
Java pushes `java.inlayHints.parameterNames=all` and C/C++ registers clangd with
`--inlay-hints` (belt-and-suspenders — clangd ≥ 14 defaults them on; per-hint-kind tuning
lives in clangd's `~/.config/clangd/config.yaml`, not the launch flags).

## Java runs on Eglot + jdtls

All Java code lives in [`init-java.el`](../lisp/languages/init-java.el); the full workflow,
the two-tier project-root resolution, the `.eglot-java-workspace` container marker, the
`~/.m2/settings-public.xml` Nexus workaround, the Gradle-importer caveat and the `jdt://`
URI handler are documented in [JAVA.md](JAVA.md).

The parts that bite an editor who isn't reading that file:

- The jdtls bundle at [`var/lsp-java/eclipse.jdt.ls/server/`](../var/lsp-java/) (~150 MB) is
  inherited from the pre-migration lsp-java install and kept in place to avoid a
  re-download. Workspace metadata lives at [`var/lsp-java/workspace/`](../var/lsp-java/) —
  delete that subdir out-of-band to force a re-import of every project.
- The launcher appends `:initializationOptions` (built by `fenrir/jdtls--java-settings`) so
  the `:java` settings reach jdtls at the `initialize` request, not just the later
  `workspace/didChangeConfiguration` — load-bearing for anything the initial project scan
  reads (Maven user-settings, the Gradle disable).
- The `jdt://` URI scheme handler is what makes `M-.` into a JDK / third-party-jar class
  work at all; Eglot has no native handler.
- `eglot--servers-by-project` is a hash-table — inspect with `maphash`, not
  `cl-loop for … in`.

## DAP debugging is `dape`

Eglot-aligned, ships with GNU ELPA, configured at the end of
[`init-languages.el`](../lisp/init-languages.el). Breakpoints render in the buffer
**margin** (`B` glyph), visible on TTY frames; lsp-mode's `dap-mode` (which drew them with
GUI-only fringe bitmaps) was removed when Java migrated to Eglot.

**Java debugging is unsupported** in this config until either dape grows a Java adapter or
someone writes a manual bridge to `java-debug` — use IntelliJ / VSCode for real Java
debugging until then. Debug-adapter binaries live outside the repo: only Go's `dlv` is on
`PATH`; `debugpy` / `gdb` / `codelldb` / `vscode-js-debug` install per language as needed.
Keybindings: [FEATURES.md §7](../FEATURES.md).

## OSC 52 clipboard bridge (TTY only)

Wired in [`init-defaults.el`](../lisp/init-defaults.el): `interprogram-cut-function` emits
`\e]52;c;…\a` so cuts cross the tmux/SSH boundary to the host clipboard. Don't override
`interprogram-cut-function` in another module.

## See also

- [CLAUDE.md](../CLAUDE.md) — the one-line rules
- [TAGS.md](TAGS.md) — the gtags / GTAGS traps (the largest one)
- [ARCHITECTURE.md](ARCHITECTURE.md) — module layout, including the `init-gui` tiering trap
