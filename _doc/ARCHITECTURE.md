# Architecture — thin loader + per-area modules

Long-form companion to [CLAUDE.md → Architecture](../CLAUDE.md#architecture-rules).
This file is the *content*: what each module holds and why the tricky ones are shaped
the way they are. The rules that must fire without being looked up stay in
[CLAUDE.md](../CLAUDE.md).

## The loader

[`init.el`](../init.el) is intentionally tiny. It bootstraps the package system (MELPA +
GNU ELPA, `use-package-always-ensure t`, `no-littering`, `exec-path-from-shell`), pushes
`lisp/` and `lisp/languages/` onto `load-path`, then `mapc #'require`s a fixed list of
`init-<area>` modules in the order shown in the file's header comment.

**That load order is load-bearing**: cross-section `use-package :after` wiring in the
modules (e.g. `consult-eglot :after (consult eglot)`, `magit-delta :after magit`) assumes
earlier modules have already declared their packages. Do not reshuffle without verifying
the `:after` edges.

Section numbers in module headers refer to the pre-2026-05-19 monolithic `init.el`
layout — they're history, not a current TOC. Read the module names instead.

## Module map

Top-level `init-<area>` modules under [`lisp/`](../lisp/):

| module | holds |
|---|---|
| `init-defaults` | better built-in defaults, `custom-file`, which-key, ibuffer, the OSC 52 clipboard bridge, `gcmh-mode` |
| `init-system-packages` | OS package helper (apt/brew/…) |
| `init-completion` | minibuffer / completion UI (Vertico ecosystem), `consult-completion-in-region` routing |
| `init-corfu` | in-buffer completion packages (installed, **not** globally enabled) |
| `init-snippets` | TempEl + YASnippet — see [SNIPPETS.md](SNIPPETS.md) |
| `init-editing` | avy, pulsar, popper, jinx, `undo-fu-session`, `fenrir/hideshow-menu` |
| `init-ide` | the cross-cutting modern-IDE layer (below) |
| `init-languages` | **language-agnostic** infra only (below) |
| `init-tags` | GNU Global: `gtags-mode` xref fallback, `C-c g` index management, daemon-wide `GTAGSCONF`/`GTAGSLABEL` — see [TAGS.md](TAGS.md) |
| `init-git` | Magit, diff-hl, magit-todos, delta, difftastic, `smerge-mode` auto-enable, `consult-todo` |
| `init-terminal` | vterm + `vterm-toggle` (`C-c T`) |
| `init-docker` | `dockerfile-mode` + `docker.el` container UI (`C-c D`) |
| `init-diagrams` | `plantuml-mode` (local `java -jar`, jar at `var/plantuml/plantuml.jar`) + `mermaid-mode` / `ob-mermaid` (`mmdc` CLI), both wired into `org-babel` |
| `init-appearance` | doom-themes, doom-modeline, nerd-icons |
| `init-gui` | GUI-frame-only eye-candy, TTY-gated (below) |
| `init-dired` | dired + diredfl, nerd-icons-dired, dired-subtree, dired-narrow, consult-dir |
| `init-org` / `init-org-roam` | Org (light touch) + the org-roam Zettelkasten at `~/code/org-roam/` |
| `init-ai` | `claude-jobs-view`, `gptel`, GitHub Copilot (opt-in per buffer on `C-c M-c`), `question-queue` |
| `init-aidermacs` | aidermacs (aider pair-programmer, vterm, Gemini) |
| `init-tmux-claude` / `init-alacritty-claude` | split a tmux pane / launch an external alacritty running the `claude` CLI |
| `init-audit` | config self-audit commands: `fenrir/features-audit` (FEATURES.md drift vs. the routing layer) and `fenrir/package-usage-audit` (keyfreq-backed prune candidates) |
| `init-keys` | the keybinding **routing layer** — required LAST (below) |

Most of these correspond to one section of the pre-split monolith (`git log --oneline`
for the split commits); `init-ide`, `init-tags`, `init-docker`, `init-diagrams`,
`init-gui`, `init-aidermacs`, `init-tmux-claude`, `init-alacritty-claude` and `init-keys`
are later standalone additions.

Local Elisp (not on MELPA), all lazily autoloaded from their owning module:
[`lisp/claude-jobs-view.el`](../lisp/claude-jobs-view.el) (a `tabulated-list-mode` UI over
the external `jobctl` CLI, `M-x claude-jobs-view`),
[`lisp/junit-runner.el`](../lisp/junit-runner.el) (front-end for the `junit-core` C++
module), [`lisp/question-queue.el`](../lisp/question-queue.el) (front-end for the
`question-queue-core` Rust module),
[`lisp/fenrir-back-forward.el`](../lisp/fenrir-back-forward.el) (the merged jump history
behind `<f6>` / `<f7>`, `require`d by `init-keys`).

## `init-ide.el` — the modern-IDE layer

Loaded right after `init-editing`. Built-in toggles (`hl-line`, `global-subword-mode`)
plus: indent guides (`indent-bars`, TTY char backend), highlight-occurrences
(`symbol-overlay`, `C-c s`), inline colour swatches (`colorful-mode`), a ripgrep `M-.`
fallback (`dumb-jump`, appended **LAST** on `xref-backend-functions` so it never shadows
Eglot/gtags), offline docs (`devdocs`, `C-c k`), `goto-chg`, `move-text`
(`M-<up>`/`M-<down>`), `string-inflection` (`C-c S`), diff-safe on-save whitespace trim
(`ws-butler`), the `C-c G` git-extras prefix (`git-link` / `git-timemachine` / `blamer`),
a dired-backed file-tree sidebar (`dired-sidebar`, `C-c B`), project-scoped workspaces
(`tabspaces`, `C-c W`, layered on the existing tab-bar), and a `.http` / `.rest` client
(`restclient`).

Everything in it installs and runs on **both TTY and GUI** Emacs. It's chosen to be
TTY-safe — the stricter constraint, since this setup is daemon + `emacsclient -nw` — which
makes it a strict subset of what a GUI frame supports, so a GUI Emacs runs the same layer
unchanged (a few pieces just render richer there, e.g. `indent-bars`' stipple backend vs.
the TTY character backend). User-facing tables: [FEATURES.md §5b](../FEATURES.md).

The same modern-IDE initiative deliberately placed a few items in their thematic home
module rather than here: `vterm-toggle` in [`init-terminal.el`](../lisp/init-terminal.el);
`undo-fu-session` in [`init-editing.el`](../lisp/init-editing.el); `smerge-mode` +
`consult-todo` in [`init-git.el`](../lisp/init-git.el); the standalone
[`init-docker.el`](../lisp/init-docker.el); Copilot in [`init-ai.el`](../lisp/init-ai.el).

## `init-languages.el` vs. `lisp/languages/`

[`lisp/init-languages.el`](../lisp/init-languages.el) holds **only** the
language-agnostic infrastructure: project.el, envrc, the Eglot core block, eglot-booster,
consult-eglot, xref, breadcrumb, eldoc routing, the combobulate package declaration,
treesit-auto, flymake, sideline, apheleia, dape. The GNU Global stack (gtags-mode xref
fallback, `C-c g` index management, daemon-wide `GTAGSCONF`/`GTAGSLABEL`) lives in the
separate [`lisp/init-tags.el`](../lisp/init-tags.el) (see [TAGS.md](TAGS.md)), loaded
right after `init-languages`.

Per-language modules live under [`lisp/languages/`](../lisp/languages/) — `init-java`,
`init-go`, `init-python`, `init-rust`, `init-typescript`, `init-c-cpp`, `init-lua`,
`init-vue`, `init-web`, `init-markdown`, `init-toml` (taplo LSP for `Cargo.toml` /
`pyproject.toml`; format-on-save via apheleia's built-in taplo formatter). They were split
out of the former monolithic `init-languages.el` so each language is easy to edit in
isolation.

**`init-languages` must load before them**: each per-language module attaches its own
`eglot-ensure` hook (`add-hook`), registers its server's `eglot-workspace-configuration`
entry (`(with-eval-after-load 'eglot (setf (alist-get :SERVER …) …))`), and adds its
`combobulate-mode` hooks onto the shared package declarations in the core. (gtags needs
no per-language hooks — `gtags-mode` is global and self-scoping.)

So: *"where is language X configured"* → [`lisp/languages/init-X.el`](../lisp/languages/);
*"where is the shared Eglot / tree-sitter / debugger setup"* →
[`lisp/init-languages.el`](../lisp/init-languages.el).

## `init-gui.el` — GUI-only tiering  <a id="gui-tiering"></a>

This layer is load-bearingly careful because **this daemon serves a TTY frame and a GUI
frame at the same time** (verified live). Packages are gated by their TTY behaviour into
three tiers:

| tier | behaviour on TTY | members |
|---|---|---|
| **A** — auto-on | self-falls-back per display | `vertico-posframe` (→ plain Vertico), `ligature` (ignored) |
| **B** — on demand | explicit TTY fallback | `eldoc-box` on `C-c H` (child frame on GUI, eldoc doc-buffer on TTY) |
| **C** — global, display-replacing | **no** per-display fallback | `which-key-posframe` (show fn no-ops → which-key shows nothing), `transient-posframe` (show fn *errors*), `spacious-padding`, `nyan-mode`, `good-scroll`, `mlscroll` |

All six Tier-C modes are on `fenrir/gui-popups-toggle` (`C-c M-g`, refuses on a
non-graphical frame). Since 2026-07-30 the **two posframe ones only** are additionally
auto-driven by `fenrir/gui-popups-auto` (on `server-after-make-frame-hook` +
`after-delete-frame-functions`, defeatable via `fenrir/gui-popups-auto-enable`).

### Why the auto-enable guard has two conditions

**The naive version is forbidden.** Checking only `(display-graphic-p)` of the new frame
was tried and reverted: it broke which-key/transient on the coexisting TTY frame
(`which-key-popup-type` stuck at `custom`, `transient-display-buffer-action` at the
posframe show fn).

What makes the current one safe is the *second* condition — enable only while **no real
terminal frame exists**. `fenrir/gui--real-tty-frame-p` tests non-graphical **and**
carrying a `tty` frame parameter, which excludes the daemon's own `initial_terminal`
bootstrap frame; everything Tier C switches back off the moment a real TTY frame connects.

Do not "simplify" that condition away, and do not extend the automatic path to the four
eye-candy modes — a nyan cat that appears by itself is a surprise, not a dividend.

## `init-keys.el` — the keybinding routing layer  <a id="keybinding-routing-layer"></a>

Required **LAST** in [`init.el`](../init.el) and adds **no features** — every command it
names is configured in another module. It is a *routing policy* over them, answering "this
config has too many chords to remember": each command is assigned to one of three tiers so
only one tier needs memory. Rationale and rollout:
[`tasks/keybinding-strategy.md`](../tasks/keybinding-strategy.md); user-facing tables:
[FEATURES.md §0](../FEATURES.md).

**Tier 1 (muscle memory, cap ~15)** is decided by **measurement, not taste**: `keyfreq` +
`keyfreq-autosave` run from startup (state in `var/keyfreq.el` via no-littering — don't set
`keyfreq-file` by hand), and `M-x fenrir/keyfreq-report` shows the ranking.
`self-insert-command`, single-char motion and mouse events are excluded via
`keyfreq-excluded-commands` / `keyfreq-excluded-regexp` (matched against the **command
name**, `string-match-p`, so regexps must be anchored) — otherwise `self-insert-command` is
~90% of the table. `keyfreq-show` is **not autoloaded**, which is why the wrapper exists;
call the wrapper, not the raw command.

**Tier 2** is the `<f5>` hub (`fenrir/hub`, also on `C-c ?` for terminals that eat function
keys) — transient sub-prefixes grouped by *scenario*, plus `casual-suite` menus on **`C-o`
in each built-in mode's own map** (never globally; `open-line` is untouched). Two
load-bearing details:

1. The hub *duplicates* the existing `C-c` chords and must never replace them — Tier-1
   habits have to keep working.
2. The transient prefixes are defined inside `with-eval-after-load 'transient`, and `<f5>`
   is bound to a thin wrapper that `require`s transient on first press, because nothing
   loads transient at startup (magit is deferred) and defining prefixes at top level would
   drag it into every boot. Same lazy-require discipline as `fenrir/hideshow-menu` in
   [`init-editing.el`](../lisp/init-editing.el).

**Tier 3** needs no config — Vertico + orderless `M-x` and `embark-bindings` (`C-h B`)
already are it.

**The one exception to tiering** is back-navigation: a frequent intent fragmented across
four unrelated stores (buffer `mark-ring`, `global-mark-ring`, the xref stack,
`goto-last-change`), where the cost is the *classification*, not the chord. No tier
assignment fixes that, so the mechanisms were merged instead: a single `:after` advice on
`push-mark` feeds one 32-marker ring, walked by `fenrir/back` / `fenrir/forward`
(`<f6>` / `<f7>`, `M-g b` / `M-g B`, then bare `b` / `f`), with the four native mechanisms
still reachable *by intent* from `<f5> b`. The feature itself lives in the standalone
library [`lisp/fenrir-back-forward.el`](../lisp/fenrir-back-forward.el) (extracted 2026-08
so the routing layer keeps adding no features); `init-keys` only `require`s it and binds
the keys. `fenrir/back-forward-enable` → nil is the whole off switch. The MELPA package `backward-forward` was read and rejected (two latent bugs, a
keymap that collides with keyd's word-jump layer) — rationale and the alternatives
evaluated: [`tasks/back-navigation-strategy.md`](../tasks/back-navigation-strategy.md).

**Repeat maps**: only `xref` (`,` / `.`), `symbol-overlay` (`n` / `p`) and back/forward
(`b` / `f`) were added. Emacs 30.1 **already ships and activates**
`other-window-repeat-map`, `resize-window-repeat-map`, `tab-bar-switch-repeat-map`,
`tab-bar-move-repeat-map`, `winner-repeat-map`, `undo-repeat-map` and
`next-error-repeat-map` — verify with `(get COMMAND 'repeat-map)` before "adding" one. The
module also sets `repeat-exit-timeout` to 3 s **globally**, which is what makes a
punctuation repeat key (`.` after `M-,`) safe; that value is deliberate, not a stray
default.

**Commands referenced from the hub must be autoloaded or wrapped.** `combobulate` (the
entry command) is *not* autoloaded — only `combobulate-mode` and
`combobulate-query-builder` are — hence `fenrir/combobulate-dwim`. The same trap caught
eight more entries (dape's `dape-breakpoint-toggle` / `-remove-all` / `dape-info` /
`dape-repl`, eglot's `eglot-reconnect` / `eglot-shutdown` / `eglot-events-buffer`, and
`envrc-reload`), so they go through `fenrir/hub-…` wrappers generated by the
`fenrir/hub--defwrapper` macro, which `require`s the feature before dispatching. Check
`<pkg>-autoloads.el` before naming a command directly in a transient suffix, or a fresh
session gets `void-function`.

**Hub scenarios** (user-facing table: [FEATURES.md §0](../FEATURES.md)): `n` navigate,
`d` diagnose, `g` git, `x` run/debug, `r` refactor, `w` workspace, `a` AI, `o` org/notes,
`b` back, then the escape-hatch column. `x` and `o` were added from keyfreq evidence —
zero recorded `dape`/`compile` uses despite ~80 lines of dape config, and no door at all
for the org/roam workflow — and they took the prime slots from `b`, whose menu "taught
its own obsolescence": `fenrir/back` is pressed 136× directly on `<f6>` while the hub
path is effectively unused, so `<f5> b` was demoted (kept, moved down), not deleted.

## Native module workspaces

Both are multi-project trees in this repo, **not** git submodules, and both emit their
build output into a workspace-wide `lib/` that elisp `module-load`s by bare name.

- [`cpp/`](../cpp/README.md) — C++ dynamic modules over `emacs-module.h`, aggregated by
  CMake (`add_subdirectory` per module), built with [`cpp/build.sh`](../cpp/build.sh).
  Current module: `junit-core` (JUnit test discovery for Java; tree-sitter C API + a
  vendored java grammar; **stops at command construction — never launches a process**),
  front-ended by [`lisp/junit-runner.el`](../lisp/junit-runner.el) and bound under `C-c t`
  in [`init-java.el`](../lisp/languages/init-java.el).
- [`rust/`](../rust/README.md) — Rust analogue, aggregated by a Make fan-out. Holds
  `question-queue-core` (a cargo `cdylib` over the raw emacs-module ABI via bindgen; pure
  compute + atomic local file I/O) and the three tree-sitter grammar deployers
  (`treesit-grammar{,-c,-lua}` — `cc` builds of C grammar sources, see
  [BOOTSTRAP.md → tree-sitter grammars](BOOTSTRAP.md#tree-sitter-grammars)).

The elisp↔native split is the same in both: compute and atomic I/O in the native module,
capture / watch / display in elisp. Per-module API docs live in each module's own README —
[`cpp/junit-core/README.md`](../cpp/junit-core/README.md),
[`rust/question-queue-core/README.md`](../rust/question-queue-core/README.md).

### question-queue front-end

[`lisp/question-queue.el`](../lisp/question-queue.el) (lazy-wired in
[`init-ai.el`](../lisp/init-ai.el)): `M-x question-queue-ask` (**`C-c q q`**) ships a typed
question — optionally with the highlighted region as code context (no region =
question-only) — through `qq-core-submit` into the queue's `input/`, watches `output/` with
`file-notify` (inotify), and opens the matching answer file directly in a bottom side
window. The source buffer is never modified. Build once with `M-x question-queue-build`.

**Queue directory**: there is **no built-in default** — `question-queue-dir` defaults to
nil. The normal path is the interactive prompt on the first `C-c q q` of a session
(remembered thereafter); it can also be customized persistently, or changed with
`question-queue-set-dir` (**`C-c q d`**) / `C-u C-c q q`. If none is set,
`question-queue-ask` errors via `question-queue--root` rather than falling back to a
baked-in path. `file-notify` watches are keyed per `output/` directory and each request
stamps its own `:input-dir` / `:output-dir` at submit time, so changing the root mid-flight
keeps pending requests resolving to their original queue.

## See also

- [CLAUDE.md](../CLAUDE.md) — the rules extracted from this file
- [BOOTSTRAP.md](BOOTSTRAP.md) — install, upgrade and grammar operations
- [GOTCHAS.md](GOTCHAS.md) — the editing traps and the evidence behind them
- [FEATURES.md](../FEATURES.md) — the keybinding cheat sheet
