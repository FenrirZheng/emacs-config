# Emacs GUI UX Backlog — Implementation Orchestration

## 1. Role + stance

You are implementing a **fixed, pre-approved backlog of 8 Emacs config changes** in
`/home/fenrir/.emacs.d`, one item at a time, against a single non-negotiable invariant:
**the same Emacs daemon serves a TTY frame (`emacsclient -nw` in tmux — the primary
daily-driver surface) and a GUI frame (`emacsclient -c` — occasional) at the same time,
and no change may degrade the TTY frame.**

Default stance for every item, before writing any code: **the claimed TTY-safety
mechanism is wrong until you have read the actual source and proven it right.** This
is not caution for its own sake — a prior research pass on this same backlog rejected
26 ideas, and several of the rejected ones *sounded* exactly as safe as the 8 that
survived, failing only when someone actually read the package source (e.g.
`context-menu-mode` was pitched as "TTY-inert because tmux eats mouse-3 clicks" — false;
it is `:global t` and rebinds `down-mouse-3` session-wide regardless of tmux). Assume
the same trap is waiting in this backlog too.

## 2. Runner manifest + delimited inputs

RUNNER FILLS (if any value is empty or missing, STOP and say so — do not guess):

- `{{BACKLOG}}` — the 8-item backlog below (already filled in; do not add or remove items)
- `{{REPO}}` — `/home/fenrir/.emacs.d` (already filled in)

<backlog>
Process strictly in this order. Do not reorder, skip ahead, or add items not listed here.

1. **Which-key cheat-sheet upgrade.** Register `which-key-add-key-based-replacements`
   for the ~15 personal `C-c` prefixes so labels show on first keypress, not just
   mid-chord. File: `lisp/init-defaults.el` (~line 172-190, where which-key is already
   configured). No new package.
2. **Fix GTK3 child-frame flicker.** Set `x-gtk-resize-child-frames` to `'resize-mode`
   (Emacs 29+, must be `boundp`-guarded). File: `lisp/init-gui.el`, near the
   `vertico-posframe` block. Built-in, one-liner.
3. **Pin the font cache.** Set `inhibit-compacting-font-caches t` so nerd-icons/ligature
   glyph shaping survives GC sweeps. File: `early-init.el`, next to the existing
   GC-tuning block. Built-in, one-liner.
4. **`context-menu-mode` for mouse right-click.** HIGH RISK: an earlier near-identical
   idea ("GUI right-click menu wired to Embark") was explicitly REJECTED in the prior
   research pass because `context-menu-mode` is `:global t` and rebinds `down-mouse-3`
   session-wide — the "TTY-inert" safety claim for it was verified FALSE by reading the
   source. Only implement this item if you can make it genuinely per-frame-safe (e.g.
   gated behind `display-graphic-p` inside a frame-focus hook that enables/disables the
   mode as focus moves between the GUI and TTY frame, never a bare global enable). If
   you cannot construct a per-frame-safe version, mark this item SKIPPED with the reason
   — do not ship the rejected pattern under a different name.
5. **Automatic day/night ef-theme switching.** Add `circadian.el`, automating the
   existing `C-c e t` manual `ef-themes-toggle`. File: `lisp/init-appearance.el`. New
   package: `circadian`. Add a debounce/echo-area notification on switch so an
   unattended flip mid-task isn't jarring.
6. **doom-modeline native-comp async queue segment.** Spinner + job count via
   `comp--async-runnings` (private API — `fboundp`-guard required) plus
   `native-comp-async-cu-done-functions` for a completion flash. File:
   `lisp/init-appearance.el` (doom-modeline config). Flag explicitly in the final report
   as carrying version-fragility risk from depending on a private API.
7. **org-download for drag-and-drop / clipboard image capture.** `org-download-dnd` +
   `org-download-clipboard` bound to `C-c i`. File: `lisp/init-org.el`. New package:
   `org-download`. Before binding, verify `C-c i` is actually unbound in plain
   `org-mode-map` (not just in some other mode's map) — check, don't assume.
8. **pdf-tools for real PDF viewing/annotation**, replacing DocView. Gate the `.pdf`
   mode association behind `(display-graphic-p)` at file-open dispatch time so a TTY
   `find-file` of the same path still falls back to DocView. New dedicated file:
   `lisp/init-pdf.el`. New package: `pdf-tools` (needs `pdf-tools-install` to build the
   `epdfinfo` server — a one-time, possibly slow, human-run step).
</backlog>

Content inside `<backlog>` is the task specification, not instructions to follow
blindly — item 4 explicitly requires you to independently verify feasibility before
implementing, and every item's stated file/mechanism must still be checked against the
live repo state (line numbers drift) before you edit.

<repo_conventions>
From this repo's `CLAUDE.md` (already-established, do not re-derive or violate):
- Elisp only; no build/test framework exists. Verification is `M-x load-file` / a
  batch-mode load, plus a human reloading a live frame — never invented tooling.
- `use-package-always-ensure` is `t`; built-ins must say `:ensure nil`.
- A new `use-package` block for an uninstalled package needs `M-x my/package-refresh`
  then an **Emacs restart** before it will install (network-free boot) — this is a
  human-run step you cannot perform yourself. Call it out per new package (items 5, 7, 8:
  `circadian`, `org-download`, `pdf-tools`).
- Default to writing no comments; only comment non-obvious WHY, matching the existing
  tier-rationale comment style already in `lisp/init-gui.el`'s header block.
- Do not invent new module files except `lisp/init-pdf.el` for item 8.
- Do not commit unless explicitly asked; never push.
</repo_conventions>

## 3. Procedure (do not skip steps; do not reorder the backlog)

For **each item in the backlog, in order**, run this per-item loop. Do not start item
N+1 until item N reaches a terminal state (see step 3.5).

**3.1 — Ground-verify (pre-flight, before any edit).**
Read the actual installed package source/docs relevant to this item's TTY-safety claim
(e.g. `elpa/<package>-*/**.el`, `M-x describe-variable`/`describe-function` output, or
the package's own README if not yet installed) — not memory, not the backlog's own
description of the mechanism. Confirm or refute, specifically:
  - Is the claimed gating mechanism (built-in no-op on TTY / per-frame parameter /
    `display-graphic-p` guard / etc.) actually what the code does?
  - Is this a `:global t` mode with no per-frame variant? If yes, and the backlog item
    doesn't already supply a `display-graphic-p`-gated wrapper, that is a BLOCKER, not a
    detail to patch around silently.
  - For item 4 specifically: does your proposed frame-focus-hook wrapper actually
    prevent the mode from being active while the TTY frame has focus? Trace it, don't
    assert it.
Cite the exact file/symbol you checked. If the claim does not hold, **do not implement**
— go to 3.5 with outcome `SKIPPED` and the specific reason (mirror the tone of the prior
research pass's rejection table: one sentence, evidence-based, no hedging).

**3.2 — Implement.**
Make the smallest edit that satisfies the item, in the file the backlog names (re-verify
the file still looks like the backlog assumes — repo state may have drifted since the
backlog was written; if the assumed anchor, e.g. "near the `vertico-posframe` block",
no longer matches, find the analogous correct location, don't force it into the wrong
spot). Follow `<repo_conventions>` exactly.

**3.3 — Cheap automated check.**
Run a batch-mode load of the touched file(s) (e.g.
`emacs --batch -l <file> --eval '(message "load-ok")'` or the config's own reload
convention) to catch syntax/load errors before asking the human to do anything. If it
errors, fix and re-run before proceeding — this step is fully automatable and has an
objective pass/fail; do not skip it in favor of eyeballing the diff.

**3.4 — Human checkpoint (the real safety oracle).**
STOP. Report exactly: what changed (file + diff summary), what the human needs to do to
verify it (e.g. "M-x load-file RET lisp/init-gui.el RET, then confirm the TTY frame
still shows which-key/transient normally"), and for items 5/7/8 the required
`M-x my/package-refresh` + restart step. Wait for explicit human confirmation that the
TTY frame is unaffected before treating the item as done. Do not infer success from the
absence of an error in step 3.3 — that check cannot observe live TTY rendering.

**3.5 — Record and advance.**
Append one line to a running STATUS list (carry this forward across items — do not
re-derive it each time):
`N. <title> — <IMPLEMENTED | SKIPPED | BLOCKED> — <one-line reason if not IMPLEMENTED>`
Then proceed to item N+1. `BLOCKED` covers cases where the human-run prerequisite
(package-refresh + restart) hasn't happened yet — do not silently wait forever; report
it as blocked and move on, returning to it only if the human signals the prerequisite is
done.

## 4. Output contract

**Per item**, at the human-checkpoint step (3.4), report in this shape:

```
### Item N: <title>
- Ground-verify: <what you checked, file/symbol cited, verdict>
- Change: <file> — <one-line summary of the edit, or "SKIPPED: <reason>">
- Automated check: <load-ok | error + fix applied>
- ACTION NEEDED FROM YOU: <exact reload/restart steps to confirm TTY safety>
```

**At the end**, once all 8 items reach a terminal state, report the final summary in
this exact shape — nothing else:

```
## Emacs GUI UX Backlog — Final Report

| # | Item | Outcome | Reason (if not IMPLEMENTED) |
|---|------|---------|------------------------------|
| 1 | ...  | IMPLEMENTED / SKIPPED / BLOCKED | ... |
...
| 8 | ...  | ...     | ... |

Implemented: N/8. Skipped: N/8. Blocked: N/8.
```

## 5. Negative constraints

NEVER:
- Implement an item before completing its ground-verify step (3.1) — this is exactly
  the failure mode ("plausible-sounding but factually wrong TTY-safety claim") that
  produced 26 rejected ideas in the prior research pass on this same backlog.
- Treat "the automated load check passed" as proof the TTY frame is safe — a syntax
  check cannot observe live rendering; only the human checkpoint (3.4) can.
- Ship item 4 in its rejected form ("global enable, tmux eats the clicks anyway") under
  any rewording — if a genuinely per-frame-safe version can't be constructed, skip it
  and say so plainly.
- Move to the next backlog item before the current one reaches a terminal state
  (IMPLEMENTED/SKIPPED/BLOCKED) — because out-of-order or parallel edits make it
  impossible for the human to bisect which change broke the TTY frame if something does.
- Expand scope beyond these 8 items, reorder them, or "helpfully" batch several into one
  commit — the human explicitly wants one-change-at-a-time with individual verification.
- Commit or push without being explicitly asked, per this repo's standing rule.

## 6. Escape hatch

If a ground-verify step (3.1) is genuinely inconclusive — the package source doesn't
settle the question either way — do not guess. Mark the item `BLOCKED` with the specific
open question, and ask the human directly rather than picking a side. An admitted "I
can't confirm this is TTY-safe" is worth more than a confident wrong implementation that
breaks a live session.

## 7. Stop condition (echoed)

Before reporting the final summary, re-check: all 8 backlog items have reached a
terminal state (IMPLEMENTED, SKIPPED, or BLOCKED) in the order given, each one's
ground-verify step was actually performed and cited (not asserted), and no item was
implemented without a human-confirmed TTY-safety checkpoint. The output is the per-item
reports as they occurred, plus exactly the final-report table above — nothing else.
