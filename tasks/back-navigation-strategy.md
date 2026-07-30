# Back-navigation strategy — collapse four histories into one gesture

Date: 2026-07-30 · Scope: Emacs (mark ring, global mark ring, xref stack, last-change)
Status: **layers 1 + 2 implemented 2026-07-30** in [`init-keys.el`](../lisp/init-keys.el)
(`<f6>` / `<f7>` merged history; `<f5> b` intent menu). Step 3 was resolved *against*
adopting `backward-forward` — see [Rollout order](#rollout-order). Steps 4–5 are gated on
`keyfreq` data and remain open.
Companion to [`keybinding-strategy.md`](keybinding-strategy.md); this is the same tier
policy applied to one specific, high-frequency gesture.

## Problem

"Go back to where I was" is used dozens of times an hour and still can't be recalled.
The chords are not the problem — they are 2–3 keys each. The problem is that **a decision
has to happen before the keystroke**: Emacs keeps four unrelated histories, and you must
first classify *which kind of "back"* you mean before any key is correct.

| what you want | key today | underlying store | is it a ring or a stack? |
|---|---|---|---|
| earlier position in **this** buffer | `C-u C-SPC`, then bare `C-SPC` | buffer-local `mark-ring` | **ring** — cycles, never empties |
| the **file** I was in before | `C-x C-SPC`, then bare `C-SPC` | `global-mark-ring`, one slot per buffer | **ring** |
| where I jumped **from** (`M-.`) | `M-,` (and `C-M-,` forward) | xref marker stack | **stack** — does empty |
| where I last **edited** | `C-c ;` (`goto-last-change`) | undo records | linear, edit-only |
| flip between two points | `C-x C-x` | point ↔ mark | not a history at all |

Two more front-ends exist over the same data: `M-g m` (`consult-mark`) and `M-g k`
(`consult-global-mark`).

So: **9 keys and 5 mental models for one intent.** By the tier policy in
[`keybinding-strategy.md`](keybinding-strategy.md) this is Tier-1 frequency, but Tier 1
has a hard cap of ~15 chords and cannot absorb four mechanisms × two directions. The fix
therefore cannot be "memorise better" or "add a nicer key" — it has to **remove the
classification step**.

### Measured facts (this config, verified 2026-07-30)

Not from memory — read out of the running daemon:

- `mark-ring-max` = 16, `global-mark-ring-max` = 16, `set-mark-command-repeat-pop` = `t`.
- `pop-mark` appends the current mark to the *end* of the ring (`nconc` in `simple.el`),
  which is why hammering `C-SPC` cycles forever instead of running out.
- The global ring keeps **one slot per buffer**, so it is a trail of *files*, not of
  positions — using it to move within one file is a category error.
- Free key slots: `M-[`, `M-]`, `<f6>`, `<f7>`, `C-M-;`, `s-[`, `s-]`, `M-g b`, `M-g B`,
  `C-c b`. Already taken: `C-M-,` (`xref-go-forward`), `C-M-.` (`xref-find-apropos`),
  `C-c <left>`/`<right>` (winner), `M-{`/`M-}` (paragraphs), `C-<left>`/`C-<right>`
  (`left-word`/`right-word` — **and keyd's Left-Win `opt` layer emits exactly these**).

## What already exists — do NOT rebuild

| capability | where | state |
|---|---|---|
| `set-mark-command-repeat-pop t` (bare `C-SPC` repeats a pop) | [`init-defaults.el`](../lisp/init-defaults.el) | on |
| `consult-mark` / `consult-global-mark` with preview | [`init-completion.el`](../lisp/init-completion.el) | on, `M-g m` / `M-g k` |
| `goto-last-change` | [`init-ide.el`](../lisp/init-ide.el) | on, `C-c ;` |
| xref repeat map (`,` / `.` after `M-,`) | [`init-keys.el`](../lisp/init-keys.el) | on (added 2026-07-30) |
| `<f5> n` Navigate menu — already lists back, mark ring, last change | [`init-keys.el`](../lisp/init-keys.el) | on |
| merged back/forward + `<f5> b` intent menu (layers 1–2 of this doc) | [`init-keys.el`](../lisp/init-keys.el) | on (added 2026-07-30) |
| mark-ring prose documentation | [FEATURES.md §1](../FEATURES.md) | accurate |

The gap is not tooling and not documentation. It is that all four stores remain
*separately addressable*, so the user still routes the request by hand.

## Strategy: three layers, one gesture each

### Layer 1 — one linear back/forward pair (the actual fix)

Two keys, browser semantics: **back** and **forward** over a *single* merged jump history
covering every far jump regardless of which store Emacs used. No classification, no
prefix, no ring-vs-stack distinction. This is what `C-o`/`C-i` is in vim and
Back/Forward is in every IDE, and it is the only change that deletes a *decision* rather
than adding a shortcut.

Target: ~90% of "go back" intents. The remaining 10% — "no, the *other file*", "no, where
I last *typed*" — go to layer 2.

### Layer 2 — a `Back` group in the `<f5>` hub, labelled by intent

The four mechanisms stay reachable, but the menu is worded by **what you want**, never by
the store's name, so no Emacs vocabulary is required at the moment of use:

```
<f5> b   Back
  b  earlier position in this file
  f  the file I was in before
  d  where I jumped from (definition)
  e  where I last edited
  l  pick from a list (this file)      -> consult-mark
  L  pick from a list (all files)      -> consult-global-mark
  x  flip between two points           -> exchange-point-and-mark
```

Cost: ~15 lines of `transient` in [`init-keys.el`](../lisp/init-keys.el), zero new
packages, fully reversible. **This layer is worth doing even if layer 1 is never
installed**, and it is the cheapest place to start.

### Layer 3 — deep history, browsable

Already covered by `M-g m` / `M-g k`. Only add a persistent place list (see `dogears`
below) if the keyfreq review shows layers 1–2 genuinely running out of depth.

### Non-goals

- **No fifth mechanism that doesn't remove a decision.** Any package that adds another
  independently-addressed history makes the original problem worse.
- **No new prefix namespace** (the standing rule from
  [`keybinding-strategy.md`](keybinding-strategy.md)).
- **No promotion to Tier 1 by assertion.** `keyfreq` has been collecting since
  2026-07-30; the promotion decision waits for that data.

## Layer-1 candidates — evaluated, with evidence

Sources were downloaded from MELPA and read; findings below are from the source, not from
recollection. Version = current MELPA build.

| package | how a jump gets recorded | integration cost here | last MELPA build |
|---|---|---|---|
| `backward-forward` | ONE `advice-add 'push-mark :after` → a single global 32-marker ring with a traversal position | lowest: nothing per-command | 2016-12-29 |
| `dogears` | `dogears-hooks` (defaults to only `imenu-after-jump-hook`) + a 5 s idle timer; also `dogears-functions` to advise commands | moderate: must populate `dogears-functions` for jump commands | 2024-04-12 |
| `better-jumper` | none automatic — `better-jumper-set-jump` must be called; the only built-in auto path advises `evil-set-jump` | highest: Doom advises ~30 commands to feed it; this config is not evil | 2024-10-09 |
| `gumshoe` | backtracker / context / etree modules — not read in depth | `[未驗證]` | 2026-02-17 |

### The decisive finding for `backward-forward`

Its whole design rests on advising `push-mark`, and almost every far jump in Emacs
(isearch, xref, `M-<`/`M->`, the `consult-*` family) calls it — so one advice captures
everything with no per-command wiring. **But** in Emacs 30.1 `push-mark` is a
*natively compiled* function (`(subrp (symbol-function 'push-mark))` → `t`,
`symbol-file` → `simple.elc`), which raises the known hazard that callers inside the same
compilation unit direct-call past symbol advice — the reason advising built-in primitives
is not a reliable instrumentation strategy in general.

Probed directly rather than assumed: advice was attached, `mark-whole-buffer` (an
intra-`simple.el` caller) was run in a temp buffer, and the counter incremented — **2
hits via `mark-whole-buffer`, 1 via a direct call**. Advice removed cleanly afterwards
(`advice--p` → nil). So the mechanism is sound on this Emacs.

Two real risks that survive that result:

1. **Default keys collide with keyd.** `backward-forward-mode`'s keymap binds
   `<C-left>` / `<C-right>`, which are `left-word` / `right-word` here *and* are what
   keyd's Left-Win `opt` layer emits for word-jump. Its keymap must be overridden, not
   accepted.
2. **Unmaintained since 2016, and it advises three things** — `push-mark`,
   `switch-to-buffer`, and `ggtags-find-tag-dwim`. This config uses ggtags with a
   deliberately neutralised `M-.` (see [CLAUDE.md](../CLAUDE.md)), so that third advice
   must be read before enabling, not after.

### Key-slot recommendation for layer 1

`M-[` / `M-]` read as directional, are adjacent, single-modifier, and verified free — but
in a **TTY frame** `M-[` is sent as `ESC [`, the CSI introducer that begins every arrow-key
escape sequence, so it is a poor choice while this daemon can still serve
`emacsclient -nw`. Safer pairs, also verified free: `<f6>` / `<f7>` (function keys, and
`<f5>` is already the hub, so the neighbourhood is consistent) or `M-g b` / `M-g B`
(inside the existing "goto" prefix, zero namespace growth).

## Rollout order

1. ✅ **Done 2026-07-30** — the `<f5> b` Back group (layer 2), worded by intent, with the
   merged pair listed first and labelled with its real keys. Nothing installed, no existing
   key changed. [FEATURES.md §0](../FEATURES.md) updated.
2. ✅ **Done 2026-07-30** — the four-way distinction table now sits in
   [FEATURES.md §0 → Going back where you were](../FEATURES.md), next to the daily card,
   with the native key, the `<f5> b` letter, the store and ring-vs-stack per row.
3. ✅ **Resolved 2026-07-30 — `backward-forward` NOT adopted; went straight to step 6.**
   Its source was read at the pinned MELPA commit (`58489957`, 2016-12-29) as this step
   required, and the read turned up two defects on top of the two risks already listed
   above:
   - `backward-forward-previous-location` evaluates `(elt RING 0)` *before* checking the
     ring is non-empty → `wrong-type-argument markerp nil` on the first press of a fresh
     session;
   - the mode's disable branch calls `(advice-remove 'ggtags-find-tag-dwim #'push-mark)` —
     the wrong symbol (the advice added is `backward-forward-push-mark-wrapper`), so that
     advice leaks and never comes off.

   Two latent bugs in ~200 unmaintained lines, plus a keymap that must be overridden
   anyway, is worse than owning ~40 lines. Step 6 was already the sanctioned fallback and
   the `push-mark` probe had already proved the mechanism, so it was taken now.
4. ⏳ **Open — week 2, judge with data, not feel**: `<f5> k` (`fenrir/keyfreq-report`).
   Promote the pair to Tier 1 only if `fenrir/back` out-ranks the four mechanisms it
   replaced; if the old keys still dominate, the unified history is not being trusted —
   remove it rather than keeping a fifth mechanism around. `fenrir/back-forward-enable` →
   nil is the whole removal.
5. ⏳ **Open — only if depth is the complaint**: add `dogears` for a persistent browsable
   place list (layer 3), wired via `dogears-functions`, not as another back/forward pair.
6. ✅ **Taken at step 3** (above): one `push-mark` `:after` advice, one marker list, one
   index, in [`init-keys.el`](../lisp/init-keys.el) — no dependency, no keymap to fight.

### What shipped (layer 1)

| piece | value |
|---|---|
| commands | `fenrir/back` / `fenrir/forward` |
| keys | `<f6>` / `<f7>`; `M-g b` / `M-g B` as the TTY fallback (both verified free) |
| repeat map | `fenrir/back-forward-repeat-map` — bare `b` / `f` after the first press |
| store | `fenrir/back-forward-ring`, 32 markers, newest first; `fenrir/back-forward-position` is the traversal index |
| recording | one `:after` advice on `push-mark`; suppressed while traversing and in the minibuffer; identical consecutive marks deduped |
| off switch | `fenrir/back-forward-enable` → nil (or `M-x fenrir/back-forward-mode`, which also releases the markers) |

`M-[` / `M-]` were rejected on the TTY ground given above; the four native mechanisms and
their keys are untouched, so nothing that worked before stopped working.

Behaviour verified in a batch Emacs before shipping (23 assertions): first press on an
empty ring signals a `user-error` rather than the `markerp nil` crash the package has,
back/forward round-trip within and across buffers, the anchor push makes `forward` return
to where `back` started, a new mark truncates the forward branch, killed-buffer markers are
pruned mid-walk instead of erroring, the ring honours its cap, and disabling the mode
removes the advice and releases every marker.

## Success criteria

- ✅ "Go back" is **one key, no prefix, no choice** in the common case (`<f6>`); the
  four-way distinction is needed only when the first press lands somewhere unintended, and
  it is then one menu away (`<f5> b`).
- ✅ Total keys in Tier 1 for back-navigation drops from 4+ mechanisms to **1 pair**, and
  the overall Tier-1 list stays ≤15.
- ✅ No new prefix namespace (`M-g` was already the goto prefix), and no fifth
  *independently addressed* history: the merged ring is fed automatically and is never
  something you choose between — that was the whole point.
- ⏳ The promotion/removal decision at step 4 is made from `keyfreq` output, and the daily
  card in [FEATURES.md §0](../FEATURES.md) stops being labelled *provisional*. Still open —
  the card carries the pair as a candidate, not as measured data.
