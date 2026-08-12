# Implementation Plan: add Dirvish to the Emacs config

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
Spec: [`SPEC.md`](../SPEC.md).
Companion task list: [`todo.md`](todo.md).
Harness mirror: [`~/.claude/plans/jaunty-nibbling-scott.md`](/home/fenrir/.claude/plans/jaunty-nibbling-scott.md)
(the same plan; this file is the in-repo, relative-path version meant to
land alongside `SPEC.md`).

## Context

Vanilla Dired in this Emacs 30.1 config works but is bare — no icons, no
preview, no quick-access launcher, no `?`-dispatch transient, no side
panel. [Dirvish](https://github.com/alexluigit/dirvish) layers all of that
on top of Dired without replacing it. Single operator, single machine,
additive change.

Two existing decisions constrain how Dirvish is configured here:

1. [`lisp/init-git.el:22-23`](../lisp/init-git.el) sets `vc-handled-backends`
   to `nil` (Magit replaces the built-in VC framework). Dirvish's `vc-state`
   attribute reads from that list and would silently no-op while still
   costing a per-row query.
2. [`lisp/init-git.el:29-33`](../lisp/init-git.el) documents why
   `diff-hl-dired-mode` is deliberately NOT hooked: `$HOME` is a
   1500-tracked-file git repo and the per-row `git status` / `git ls-files`
   scan caused a CPU spike on `emacs ~/`. Dirvish's `git-msg` attribute
   would hit the same hazard.

→ Both attributes are **omitted** from the default `dirvish-attributes`
list. Operator can toggle them per-buffer via `a` (`dirvish-setup-menu`)
in smaller repos where the cost is acceptable.

Outcome: `C-c f` and `C-c s` open Dirvish; every existing `C-x d` /
`C-x C-f`-into-a-dir flow routes through Dirvish via
`dirvish-override-dired-mode`; nerd-icons reuses the glyph stack already
declared in [`lisp/init-appearance.el`](../lisp/init-appearance.el).

## Architecture Decisions

- **New per-section module, not a fold-in.** [`lisp/init-dirvish.el`](../lisp/init-dirvish.el)
  joins the 14 existing `lisp/init-*.el` modules. Granularity matches
  [`init-corfu.el`](../lisp/init-corfu.el) / [`init-obsidian.el`](../lisp/init-obsidian.el)
  / [`init-org-roam.el`](../lisp/init-org-roam.el) (one package, one file).
- **Load order: between `init-appearance` and `init-org`.** Visually
  grouped with "appearance / UI" modules; ensures `nerd-icons` is
  use-package-declared before `dirvish-attributes` references it.
- **`dirvish-override-dired-mode` is on globally** (no opt-in keybind
  gate). Every directory-open goes through Dirvish.
- **Attribute set is icon-only** (`subtree-state nerd-icons collapse
  file-time file-size`). No `vc-state`, no `git-msg` — see the two
  hazards above.
- **`dirvish-fd-program` uses `executable-find`** so Debian's `fdfind`
  and upstream's `fd` both work without a config rewrite.
- **One-time install via `M-x my/package-refresh` + restart.** Same
  drill as every other MELPA package added to this config — see
  [`init.el:54-59`](../init.el).
- **`FEATURES.md` update is deferred** to a follow-up commit (per
  [`SPEC.md` Open Questions](../SPEC.md#open-questions)). Keeps the
  implementation diff reviewable.

## Files Touched

| file | change |
|---|---|
| [`lisp/init-dirvish.el`](../lisp/init-dirvish.el) | **new** — see [`SPEC.md` Code Style](../SPEC.md#code-style) for the verbatim content |
| [`init.el`](../init.el) | one-line addition to commentary (line ~19) + one-line addition to the `mapc #'require` list (line ~110-124), placed between `init-appearance` and `init-org` |
| [`SPEC.md`](../SPEC.md) | already updated this session — replaces the prior init-split spec |
| [`tasks/plan.md`](plan.md) | this file (replaces the prior init-split plan) |
| [`tasks/todo.md`](todo.md) | task checklist (replaces the prior init-split todo) |

Untouched: [`custom.el`](../custom.el), [`early-init.el`](../early-init.el),
[`lisp/init-appearance.el`](../lisp/init-appearance.el),
[`lisp/init-editing.el`](../lisp/init-editing.el),
[`lisp/init-git.el`](../lisp/init-git.el),
[`lisp/init-defaults.el`](../lisp/init-defaults.el), and every other
existing `lisp/init-*.el` module.

## Phases & Commit Plan

One commit per phase, except Phase 0 (pre-flight, no commit).

| phase | scope | commit subject |
|---|---|---|
| 0 | install dirvish from MELPA + restart daemon | (no commit — package state, not repo state) |
| 1 | create `lisp/init-dirvish.el` | (folded into Phase 2 commit) |
| 2 | wire into `init.el` + smoke + commit | `emacs: add init-dirvish module — Dirvish over Dired with icons + preview` |
| 3 | (deferred) `FEATURES.md` section | `emacs: FEATURES.md — add §"File manager (Dirvish)"` |

The Phase 1 file creation does **not** get its own commit because the file
is functionally dead until Phase 2's `init.el` require lands. Bundling
them keeps the working tree in a "loads cleanly at every commit" state.

## Verification Checkpoints

Run before each commit. Source of truth: [`SPEC.md` Testing
Strategy](../SPEC.md#testing-strategy).

### Checkpoint A — Batch load parity (after Phase 2 edits, before commit)

```bash
emacs --batch -l init.el --eval '(message "ok")' 2>&1 | tail -10
```

Exits 0, prints `ok`, no `Symbol's function definition is void`, no
`Cannot open load file`, no `Wrong type argument`. If this fails, stop
and diagnose — do not proceed to Checkpoint B.

### Checkpoint B — Daemon smoke (after Phase 2 edits, before commit)

Fresh daemon, TTY client frame. Run each:

```bash
emacsclient -e '(featurep (quote init-dirvish))'        # → t
emacsclient -e 'dirvish-override-dired-mode'            # → t
emacsclient -e '(package-installed-p (quote dirvish))'  # → t
emacsclient -e 'dirvish-attributes'
# expect: (subtree-state nerd-icons collapse file-time file-size)
emacsclient -e 'dirvish-fd-program'                     # → "/usr/bin/fdfind"
```

Then in the client frame:
- `C-c f` opens Dirvish on `default-directory`.
- `C-x d` (vanilla Dired binding) opens **Dirvish**, not classic Dired.
- `?` opens `dirvish-dispatch`.
- `TAB` on a directory expands a subtree.
- `o` opens the six-entry quick-access menu.
- `C-c s` opens `dirvish-side`; `q` closes it.

### Checkpoint C — `$HOME` hazard regression (before commit)

```bash
time emacsclient -e '(let ((default-directory "~/")) (dirvish))'
```

Real time < 1 s. No visible CPU/disk spike. If this regresses,
suspect `git-msg` / `vc-state` re-entered `dirvish-attributes`.

### Checkpoint D — Diff hygiene (before commit)

```bash
git status
# expect:
#   Changes not staged for commit:
#     modified:   init.el
#     modified:   SPEC.md
#     modified:   tasks/plan.md
#     modified:   tasks/todo.md
#   Untracked files:
#     lisp/init-dirvish.el
git diff --stat init.el        # 2 ++ (one commentary, one require entry)
ls lisp/init-dirvish.elc       # MUST NOT EXIST
```

If `.elc` exists from byte-compile checks, remove it before commit — it's
gitignored but a stray binary in the working tree is sloppy.

## Risks & Mitigations

| risk | likelihood | mitigation |
|---|---|---|
| `dirvish` fails to install (MELPA stale, network blip) | low | Phase 0 verifies `(package-installed-p 'dirvish)` before proceeding. Fallback: pin via `:vc (:url "https://github.com/alexluigit/dirvish" :rev :newest)`. |
| `nerd-icons` glyphs render as boxes (font not installed in the terminal) | medium | Terminal-side, not config. `M-x nerd-icons-install-fonts` was the documented one-off for [`lisp/init-appearance.el:17`](../lisp/init-appearance.el); assume it ran. If not, surface to user. |
| Operator later re-adds `vc-state` / `git-msg` to `dirvish-attributes`, then opens `~/` → CPU spike | medium | Documented in both [`SPEC.md` Boundaries](../SPEC.md#boundaries) ("Ask first") and the new module's commentary header. Discoverable on the next reading. |
| Stale `init.elc` shadows the new `init.el` | low | Already deleted in the prior init-split commit (`fd6d8d0`). Confirm with `ls init.elc` before Checkpoint B if there's any doubt. |
| `executable-find` returns `nil` on a host without `fd` | low | Block degrades gracefully — `dirvish-fd-program` becomes `nil`, and Dirvish falls back to in-process listing for small dirs. Large-dir async path is the only thing that breaks; operator gets a clear error then. |

## Out of Scope

Captured in [`SPEC.md` Open Questions](../SPEC.md#open-questions); not
implemented in this plan:

- Installing the optional preview binaries (`poppler-utils ffmpegthumbnailer
  mediainfo libvips-tools imagemagick`).
- Enabling `dirvish-peek-mode` globally.
- Enabling `dirvish-side-follow-mode` globally.
- Updating [`FEATURES.md`](../FEATURES.md) — separate commit (Phase 3).
- Pinning Dirvish via `:vc` or `package-vc-selected-packages`.
