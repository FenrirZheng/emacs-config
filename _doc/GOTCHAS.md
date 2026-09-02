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

**Magit.** With ~1500 tracked files plus ~1M untracked items under `$HOME`,
`diff-hl-dired-mode` was dropped from this config (see
[`init-git.el`](../lisp/init-git.el)). The untracked-files section used to be dropped for
the same reason (a `remove-hook` on `magit-status-sections-hook`), but that is no longer
needed and was restored: Magit reads the **repo-local** `status.showUntrackedFiles` in
`magit-list-untracked-files` and caps any listing at `magit-status-file-list-limit` (100).
Since that key became `normal` for `$HOME` (2026-09-02) the Untracked section does appear
there, listing the ~237 collapsed top-level entries rather than walking the whole tree.

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

## Java has no language server — on purpose

Java is the one language with a [`lisp/languages/`](../lisp/languages/) module that does
**not** attach Eglot. jdtls was removed 2026-08-10; the full rationale, what capabilities
that costs, and the gtags-based replacement are in [JAVA.md](JAVA.md).

The parts that bite an editor who isn't reading that file:

- **Don't "fix" the missing `eglot-ensure` hook.** Its absence from
  [`init-java.el`](../lisp/languages/init-java.el) is the feature. Adding it back does
  nothing on its own anyway — the `eglot-server-programs` entry is gone too.
- **Java's `M-.` is name-level, not type-level.** It answers from the gtags index, so an
  overloaded or common name returns every same-named definition (`getId`: 75 in one real
  project) and `M-?` mixes same-named locals in with real call sites. That is the expected
  behaviour, not a broken index.
- **`.java` is parsed by the pygments plug-in, not gtags' built-in parser** — the
  `java-pygments` label in [`gtags.conf`](../gtags.conf). The built-in Java parser indexes
  **no fields**. An index built before the switch needs one `C-c g g`.
- **Don't "simplify" that label to Universal Ctags.** It gives an identical definition set
  and empties `GRTAGS` — ctags has no notion of references, so `M-?` goes silently dead.
  Measured both ways; the numbers are in [TAGS.md](TAGS.md#why-java-is-not-on-the-built-in-parser).
- **Annotations are indexed as `@Autowired`, not `Autowired`** — pygments keeps the sigil.
  `init-tags.el` carries an `:around` method that retries `@SYMBOL` in Java buffers; don't
  delete it or `M-?` on every Spring annotation returns nothing.
- **`var/lsp-java/` (453 MB) is dead weight**, not a dependency. Nothing reads it. Delete
  it once you're sure jdtls isn't coming back.
- The deleted jdtls code — launcher, `jdt://` URI handler, and the five advices that kept
  diff-hl / org-roam / breadcrumb / vc-refresh / consult-eglot from choking on synthetic
  non-`file://` URIs — lives in git history at the removal commit. **Recover it from
  there**, don't rewrite it.

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
