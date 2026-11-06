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

## Extending the Magit status buffer

From building [`fenrir-magit-subtree.el`](../lisp/fenrir-magit-subtree.el) (2026-10-14):

- **A collapsed section has no child sections.** `magit-insert-section-body`
  defers the body, so walking `(oref section children)` of a folded Untracked
  group returns nil. Get the data from the function that built it instead.
- **Magit's refresh cache does not cover `git status`.** If you call
  `magit-list-untracked-files` again during a refresh, the command runs again
  (~70 ms on ig_lottery). `fenrir-magit-subtree.el` instead records Magit's own
  result with a `:filter-return` advice.
- **A defcustom default must not depend on `load-file-name` alone.** Outside a
  load, for example `custom-reevaluate-setting` run through `emacsclient -e`,
  both `load-file-name` and `buffer-file-name` are nil, and `expand-file-name`
  errors. `user-emacs-directory` works in every case.
  `fenrir-libsrc.el`'s `fenrir/libsrc-classes-program` uses the same pattern, but
  it has never failed, so it is left as it is.
- **Time one `magit-refresh-buffer`, not `magit-status-setup-buffer` plus a
  refresh.** The pair refreshes twice and doubles any per-refresh cost (this
  session's first figure, 0.52 → 0.77 s, was that error; one refresh is ~+0.09 s).

## Org heading lag: leaked `org-indent` timers multiplied by valign

Measured 2026-11-06 on Emacs 30.1 / Org 9.7.11, GUI frame. The fix is
`fenrir/org-indent--cancel-spent-agent` in [`init-org.el`](../lisp/init-org.el).

- **Leak.** `org-indent-mode` overwrites `org-indent-agent-timer`, its only handle on a
  repeating idle timer, whenever `org-indent-agentized-buffers` is empty. The old timer only
  cancels itself on its next idle period, so an Org buffer opened before then strands it.
  `emacsclient` opening an Org file while nobody types hits this every time: 4 opens leaked 4
  timers before the fix and 0 after. The daemon had 26 after 21 h.
- **Multiplier.** valign's `:after` advice on `org-indent-initialize-agent` realigns the whole
  current buffer when the agent list is empty, so N timers mean N synchronous realigns on every
  idle period.
- **Symptom.** A freeze about 0.2 s after a key, not during the command. A 180 s capture in a
  real note with 28 timers: 38.9 s of non-GC stalls, each up to 5.8 s, with 86% of CPU samples
  under `valign-region`.
- **Folding makes each realign slower.** One `valign-region` on the same note (26 table lines):
  17-20 ms unfolded, 113 ms folded at full width, 179 ms folded in a half-width split. 28 × 179 ms
  is 5.0 s, the size of the freezes seen after `org-cycle`. Unfolded copies understate this: the
  same copy, unfolded, froze for only about 0.5 s per key.
- **Not the cause.** With no leaked timers, a heading command on a 175 KB, 522-heading copy has
  a median of 24 ms from key to repaint with pulsar and beacon on, 2 ms with pulsar off, 27 ms
  with beacon off, 1 ms with both off, and no stall in the 0.75 s after each press. pulsar's
  cost is the repaint; it can stay on.
- **Timing it.** `(redisplay t)` in a loop never goes idle, and `emacsclient -e` doesn't end an
  idle period, so neither fires these timers: that benchmark showed 1-2 ms per move while the
  user saw freezes. Inject real keys with `unread-command-events` and log gaps from a 20 ms timer.
- **`profiler-stop` replaces the saved log.** It runs `(setq profiler-cpu-log (profiler-cpu-log))`,
  so a log saved just before it is lost. Stop first, then read `(profiler-cpu-profile)`.

## See also

- [CLAUDE.md](../CLAUDE.md) — the one-line rules
- [TAGS.md](TAGS.md) — the gtags / GTAGS traps (the largest one)
- [ARCHITECTURE.md](ARCHITECTURE.md) — module layout, including the `init-gui` tiering trap
