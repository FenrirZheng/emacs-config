# Keybinding overload strategy — stop memorizing, start routing

Date: 2026-07-30 · Scope: Emacs (GUI-only now), tmux, keyd
Status: **implemented 2026-07-30** — see [Implementation status](#implementation-status) at
the bottom for what landed, what changed vs. this proposal, and what is inherently
deferred (the measurement reviews).

## Problem

Coding touches too many chords: Eglot/xref (`C-c h c/t`, `M-.`), symbol-overlay
(`C-c s`), git-extras (`C-c G`), smerge (`C-c m`), devdocs (`C-c k`), sidebar
(`C-c B`), tabspaces (`C-c W`), vterm (`C-c T`), docker (`C-c D`), consult
(`M-s`/`M-g`), plus tmux prefix keys and keyd layers. Recall fails exactly when
focus is on the code, not the keys.

## What already exists (do NOT rebuild these)

| capability | where | state |
|---|---|---|
| which-key panel, 0.2 s delay | `init-defaults.el` | on |
| embark `C-.` / `C-;` / `C-h B` (searchable bindings) | `init-completion.el` | on |
| repeat-mode + repeat maps (diff-hl, smerge, flymake, dape) | several modules | on |
| `FEATURES.md` cheat sheet | `~/.emacs.d/` | manual, drifts |
| which-key-posframe / transient-posframe | `init-gui.el` Tier C | **off by default** (TTY-safety gate, now obsolete) |
| tmux-thumbs / tmux-ace-window (`prefix+a`) | `.tmux/` | on |

One gesture turned out to need its own document: "go back to where I was" has
four independent histories behind it, so it fails for a *different* reason than
the rest (a classification step before the keystroke, not a forgotten chord).
That is planned separately in
[`back-navigation-strategy.md`](back-navigation-strategy.md).

The gap is not discoverability tooling — it's that everything still competes for
the same muscle-memory budget. The strategy below is a **routing policy**: decide
per command *which of three tiers* it lives in, so only one tier needs memory.

## Strategy: three tiers, one entry key

### Tier 1 — muscle memory (hard cap ~15 chords)

Only commands used many times per hour earn a direct chord. Everything else is
evicted to Tier 2/3. Candidates (to be confirmed by measurement, see below):
`M-.` `M-,` `C-.` `M-x` `C-x g` `M-s r` window/other-window, save, and the tmux
prefix pair.

**Measure before choosing**: install `keyfreq` (two lines of config), collect
2 weeks of real usage, then `keyfreq-show` decides the cap-15 list. No guessing
— frequency data picks the survivors.

### Tier 2 — one entry key, scenario menus (the main fix)

Memorize **one key**, e.g. `<f5>` (unbound, single keypress, works in any mode):
it opens a personal `transient` hub grouped by *scenario*, not by package:

```
<f5>
 n Navigate   (xref stack, consult-imenu, avy, breadcrumb, goto-chg)
 d Diagnose   (flymake list, eldoc-box, devdocs, consult-todo)
 g Git        (magit, git-link, timemachine, blamer, diff-hl)
 r Refactor   (eglot-rename, string-inflection, combobulate, symbol-overlay)
 w Workspace  (tabspaces, dired-sidebar, vterm-toggle, popper)
 a AI         (copilot toggle, claude-jobs-view, aidermacs)
```

Two ready-made accelerators for this tier:

- **casual-suite** (MELPA): pre-built transient menus for dired, ibuffer, avy,
  symbol-overlay, re-builder, bookmarks, agenda — one `M-o`-style dispatch per
  mode. Covers the "I know the feature exists but not its key" case for
  built-ins without writing any transient code.
- The existing `C-c <letter>` prefixes stay as power-user shortcuts — the hub
  *duplicates* them, it doesn't replace them. Tier 2 is the discoverable path;
  Tier 1 users bypass it for free.

### Tier 3 — no key at all: `M-x` + embark

Long-tail commands get **good names instead of keys**. Vertico+orderless makes
`M-x string infl` faster than recalling `C-c S`. Rule: if keyfreq shows a
binding fired <1×/day, unbind nothing, memorize nothing — just know its name
family. `C-h B` (embark-bindings) is the searchable escape hatch when the name
is forgotten too.

## GUI-only dividend (config change, small)

`which-key-posframe` / `transient-posframe` were gated behind
`fenrir/gui-popups-toggle` (`C-c M-g`) **only because the daemon used to serve a
TTY frame**. Now GUI-only: auto-enable them on a `server-after-make-frame-hook`
that checks `(display-graphic-p)` — centered popups make Tier 2 menus and
which-key legible instead of a bottom side-window strip. Keep the toggle as the
manual off-switch; note in `init-gui.el` that the Tier-C rationale is retired
*conditionally* (if a TTY frame ever reconnects, the old warning applies again).

## Extend repeat-mode (cheap wins)

Pattern already proven in this config (diff-hl/smerge/flymake). Add repeat maps
for: window sizing/other-window (`C-x o o o…`), tab-bar switch, xref
`M-,`-pop, symbol-overlay next/prev. Each map deletes N chords from the recall
budget for the price of one `defvar-keymap :repeat`.

## Cross-tool layer discipline (tmux / keyd)

- Keep exactly **one prefix per layer**: keyd = physical remap only (no new
  layers), tmux = `C-b`, Emacs = `C-c` + the `<f5>` hub. Do not add a keyd
  leader layer — a 4th namespace is the disease, not the cure.
- tmux already has thumbs + ace-window; the only addition worth it is a
  `bind ?` popup showing a curated 10-line cheat (`display-popup` of a static
  file), mirroring the which-key idea at the tmux layer.

## Keep FEATURES.md honest

FEATURES.md stays the deep reference, but derive the *daily card* from data:
after the keyfreq review, keep a 20-line "this week's actual top keys" block at
the top of FEATURES.md. `C-h B` remains the live searchable view; the doc is
for reading, not recall.

## Rollout order

1. **Week 0**: install `keyfreq` (start measuring immediately — everything else
   can proceed in parallel while data accumulates).
2. **Week 0**: flip the GUI posframe gate to auto-on for graphical frames.
3. **Week 1**: install `casual-suite`; bind its per-mode dispatch.
4. **Week 1–2**: write the `<f5>` transient hub (one `transient-define-prefix`,
   ~40 lines) with the 6 scenario groups above.
5. **Week 2**: add the 4 new repeat maps.
6. **Week 3**: `keyfreq-show` review → fix the Tier-1 cap-15 list, demote the
   rest mentally to Tier 2/3; update FEATURES.md top-of-file card.
7. **Monthly**: re-run the keyfreq review; promote/demote. The tier assignment
   is a living policy, not a one-time layout.

## Success criteria

- Zero "what was that key again?" pauses that end in a web search — worst case
  is `<f5>` + reading a menu, or `C-h B` + typing a word.
- Tier-1 list ≤15 and stable across two consecutive monthly reviews.
- No new prefix namespaces added anywhere (keyd/tmux/Emacs) after rollout.

---

## Implementation status

Landed 2026-07-30. Verified by loading each changed module into the live daemon, by a
clean byte-compile (zero new warnings), and by a full `emacs --batch -l init.el`
fresh-session boot.

| rollout step | state | where |
|---|---|---|
| 1. keyfreq | **done** | [`lisp/init-keys.el`](../lisp/init-keys.el) — `keyfreq-mode` + `keyfreq-autosave-mode` from startup, state in `var/keyfreq.el`, report via `fenrir/keyfreq-report` |
| 2. GUI posframe gate | **done, with a stricter condition** | [`lisp/init-gui.el`](../lisp/init-gui.el) — `fenrir/gui-popups-auto` |
| 3. casual-suite | **done** | [`lisp/init-keys.el`](../lisp/init-keys.el) — `C-o` in 12 built-in mode maps |
| 4. `<f5>` transient hub | **done** | [`lisp/init-keys.el`](../lisp/init-keys.el) — 6 scenario sub-prefixes + escape hatches; `C-c ?` alias |
| 5. repeat maps | **done — 2 of 4 needed** | see below |
| tmux `bind ?` cheat popup | **done** | [`~/.tmux/cheat.txt`](../../.tmux/cheat.txt) + `bind ?` in [`~/.tmux/tmux.conf`](../../.tmux/tmux.conf); full `list-keys` moved to `prefix + M-?` |
| FEATURES.md daily card | **done, marked unmeasured** | [FEATURES.md §0](../FEATURES.md) |
| 6–7. keyfreq review → fix the Tier-1 15 | **deferred by design** | needs ~2 weeks of collected data; nothing to implement |

### Where the implementation deviates from the proposal above

1. **The GUI posframe gate needed a second condition, not just `display-graphic-p`.**
   The proposal's version (auto-enable on `server-after-make-frame-hook` when the new
   frame is graphical) is exactly the version that was tried and reverted before, and it
   would have regressed again: these are *process-global* modes, so enabling them for a
   GUI frame sets `which-key-popup-type` to `custom` for the coexisting TTY frame too,
   where which-key then shows nothing and transient errors. What shipped enables them
   only while **no real terminal frame exists**, and switches them back off the moment
   one connects. Distinguishing a real TTY client frame from the daemon's own
   non-graphical bootstrap frame is done on the `tty` frame parameter (`/dev/pts/N` vs
   nil) — verified live on this daemon.
   Also scoped down: only the two *posframe* modes are automatic. `nyan-mode`,
   `mlscroll`, `good-scroll` and `spacious-padding` stay behind `C-c M-g` — they are a
   taste decision, not a legibility fix, and should not appear by themselves.

2. **Two of the four proposed repeat maps already existed.** Emacs 30.1 ships and
   activates `other-window-repeat-map`, `resize-window-repeat-map`,
   `tab-bar-switch-repeat-map`, `tab-bar-move-repeat-map`, `winner-repeat-map`,
   `undo-repeat-map` and `next-error-repeat-map` (confirmed via
   `(get COMMAND 'repeat-map)`), so "window sizing / other-window" and "tab-bar switch"
   needed nothing. Only **xref pop** (`,` / `.`) and **symbol-overlay next/prev**
   (`n` / `p`) were genuinely missing. Adding punctuation repeat keys also forced
   `repeat-exit-timeout` to 3 s so a stale armed map can't turn a literal `.` into an
   xref jump minutes later.

3. **`M-o` was not available for the casual edit-kit dispatch** (it is `ace-window`), so
   `casual-editkit-main-tmenu` lives at `<f5> e` instead — which fits the one-entry-key
   policy better anyway.

4. **A stale fact was corrected while doing this**: the "what already exists" table
   above (and the comment in `tmux.conf`) said tmux-ace-window is on `prefix + a`. The
   plugin's actual defaults are `prefix + o` (jump) and `prefix + O` (swap) — verified
   with `tmux list-keys -T prefix`. The tmux comment and the new cheat sheet now say
   `o`/`O`. `FEATURES.md` also claimed `pixel-scroll-precision-mode` was part of the
   `C-c M-g` batch; it never was (see the toggle's own docstring) — fixed.

### The one thing that cannot be done now

Steps 6 and 7 — "`keyfreq-show` review → fix the Tier-1 cap-15 list" and the monthly
re-review — are blocked on data that does not exist yet: keyfreq started collecting on
2026-07-30. The daily card in [FEATURES.md §0](../FEATURES.md) is therefore explicitly
labelled *provisional, not measured*, and carries the instruction to regenerate it from
`<f5> k` after ~2 weeks. Until then any Tier-1 list is a guess, which is the exact
failure mode this document set out to avoid.
