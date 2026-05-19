# Implementation Plan: split `init.el` into `lisp/init-<area>.el` modules

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
Parent dotfiles repo: `/home/fenrir` ([CLAUDE.md](../../CLAUDE.md) covers that).
Spec: [`SPEC.md`](../SPEC.md).

## Overview

Move the 16 numbered sections in [`init.el`](../init.el) (1320 lines) into 13
per-section module files under [`lisp/`](../lisp/). `init.el` shrinks to a
~60-line loader. Content moves **verbatim** — no behaviour change, only file
layout.

§1 (package bootstrap) stays inline in `init.el` because `use-package` must be
loaded before any module file can call it. §16 is just an end-of-file comment
and collapses into a one-liner.

## Architecture Decisions

- **One file per section, exactly 13 modules.** Mirrors the existing
  `;; N. <name>` divider scheme; minimal cognitive remapping. Sub-splitting
  §8 (the 439-line languages section) is **deferred** to a separate RFC —
  this refactor is layout-only.
- **Use `(require 'init-<area>)`, not `(load …)`.** `require` is idempotent and
  registers a feature symbol so the audit query (Phase 4) can verify each
  module loaded exactly once.
- **Preserve the existing load order.** Cross-section glue currently relies on
  `use-package :after` against feature symbols, which doesn't care about file
  boundaries — but only one cross-section `:after` exists (`consult-eglot`
  :after `(consult eglot)`, bridging §4 → §8), and the original §4-before-§8
  ordering already satisfies it. Re-ordering modules in `init.el` would risk
  breaking that bridge silently. Don't.
- **No `eval-after-load` / `with-eval-after-load` to migrate.** Confirmed by
  `rg -n 'eval-after-load' init.el` → zero hits. All cross-refs are
  `use-package`'s symbol-based wiring, which survives the split untouched.
- **Per-module byte-compilation is optional.** Don't byte-compile during the
  refactor — a stale `.elc` shadowing a freshly-edited `.el` would be the
  worst kind of bug to debug mid-move. Do one batched
  `emacs -Q --batch -L lisp/ -f batch-byte-compile lisp/init-*.el` after the
  refactor lands, and only after the smoke test passes.
- **Move in 7 batches of one or more sections.** Each batch is one commit,
  independently smoke-tested and revertable. Batching by domain (completion
  cluster, org cluster, …) keeps each diff conceptually focused. A single
  "move-the-lot" commit is also acceptable if reviewer prefers — 7 commits
  is the conservative default.
- **Drop the stale [`init.elc`](../init.elc) once, at the end.** It's
  byte-compiled against the pre-refactor file shape and would shadow the new
  `init.el` on next daemon start if left in place.
- **Defer [`FEATURES.md`](../FEATURES.md) cross-reference updates** to a
  separate follow-up commit. Bundling them with the move bloats the diff and
  makes the move itself harder to review. The text references to "§N" in
  `FEATURES.md` still resolve via [`init.el`](../init.el)'s comment block
  during the refactor; they only need swapping to file-path links once the
  move is in.

## Phase Ordering

```
Phase 0 (Baseline)         → capture pre-refactor *Messages* + feature snapshot
Phase 1 (Loader prep)      → bump load-path line to top of init.el
Phase 2 (Section moves)    → 7 batches, one commit each
  Batch A: §2 + §3   (defaults + system-packages)
  Batch B: §4 + §5 + §6   (completion stack: vertico + corfu + snippets)
  Batch C: §7        (editing)
  Batch D: §8        (languages — alone, biggest section)
  Batch E: §9 + §10 + §11 (git + terminal + appearance)
  Batch F: §12 + §13 + §14 (org + obsidian + org-roam)
  Batch G: §15       (AI — keeps the claude-jobs-view require)
Phase 3 (Finalize init.el) → shrink to loader form, drop §16 commentary
Phase 4 (Cleanup)          → rm init.elc, optional byte-compile pass, audit
```

Phases are sequential. **Inside Phase 2, batches must run in order** — a later
batch's smoke test would fail if an earlier batch's module is missing from the
`(mapc #'require …)` list. (The list is built incrementally; this is fine but
non-parallelizable.)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Stale `init.elc` shadows new `init.el` mid-refactor | High — daemon silently loads old config | Delete `init.elc` once before Phase 1; never byte-compile until Phase 4 |
| One section reads a variable / function defined later in the file | Medium — would have already broken in the monolith, but easier to spot post-split | Move sections in original order; smoke after every batch. If a `void-function` error fires, the dependency was implicit — promote the require to an earlier batch |
| `use-package :after` chain breaks because module load order shifts | Low — `:after` is symbol-based and original order is preserved | Verified: only one cross-section `:after` exists (`consult-eglot`, §4→§8). Both modules load in original order |
| `lisp/claude-jobs-view.el` require fires before its containing module loads | Low — the `:ensure nil` + `:commands` autoload is lazy | Keep the `(use-package claude-jobs-view …)` block inside `init-ai.el` (§15's new home). It's lazy-loaded; first-call triggers the actual file read |
| Smoke test passes but a specific feature regresses (e.g. obscure keybinding) | Medium — auto-test coverage is thin | Phase 4 audit includes manual spot-checks of the 8 highest-traffic features (`C-x C-f`, `consult-ripgrep`, `magit-status`, `eglot` on `.go`, …) |
| User edits a different file mid-refactor and the merge gets hairy | Medium — `init.el` is being heavily rewritten | Each batch is one commit; if user wants to land a parallel edit, do it between batches, not during one |
| `*Messages*` baseline diff shows spurious differences | Low — daemon startup messages vary in trivial ordering | Compare last 8 KB of `*Messages*`, ignore line order; only flag new warnings (`Warning`, `error`, `Cannot open`) |

## Verification Checkpoints

After each batch:

```bash
# 1. Static parse — should print "ok" and exit 0
emacs --batch -l init.el --eval '(message "ok")'

# 2. Daemon boot smoke
emacs --daemon=split-check
emacsclient -s split-check -e '(message "alive")'
emacsclient -s split-check -e '(kill-emacs)'

# 3. Feature audit (modules loaded so far)
emacsclient -s split-check -e \
  '(mapcar (lambda (s) (cons s (featurep s)))
           (quote (init-defaults init-system-packages …)))'
# every cell loaded in batches so far should be (symbol . t)

# 4. *Messages* diff vs Phase 0 baseline
emacsclient -s split-check -e \
  '(with-current-buffer "*Messages*"
     (buffer-substring-no-properties
       (max (point-min) (- (point-max) 8000)) (point-max)))' \
  > /tmp/messages-after-batch-N.txt
diff <(rg -v '^Wrote ' /tmp/messages-baseline.txt) \
     <(rg -v '^Wrote ' /tmp/messages-after-batch-N.txt) | rg -i 'warn|error|unable|cannot'
# expect: no output (no NEW warnings/errors vs baseline)
```

After Phase 4 (final):

```bash
# 5. Line-count sanity
wc -l init.el lisp/init-*.el
# expect: init.el ≤ 80; sum of lisp/init-*.el ≈ pre-refactor (init.el - 80)

# 6. Diff stat
git diff --stat HEAD~7..HEAD -- init.el lisp/init-*.el
# expect: ~1260 deletions from init.el, ~1260 insertions across 13 new files

# 7. Manual smoke — high-traffic features
#   C-x C-f         → vertico minibuffer + marginalia annotations
#   M-x consult-ripgrep  → works
#   open .go file   → go-ts-mode, eglot starts, gopls connects
#   open .lua file  → lua-mode (regex), no tree-sitter ABI warning
#   M-x magit-status → opens; diff-hl fringe present
#   M-x org-roam-node-find → org-roam minibuffer
#   M-x claude-jobs-view  → tabulated UI opens
```

## Per-batch Section Mapping

| Batch | Sections | New files | Approx LoC |
|---|---|---|---|
| Pre-Phase-1 | (none — `init.elc` removal + load-path move) | — | — |
| A | §2, §3 | `init-defaults.el`, `init-system-packages.el` | 64, 9 |
| B | §4, §5, §6 | `init-completion.el`, `init-corfu.el`, `init-snippets.el` | 144, 59, 10 |
| C | §7 | `init-editing.el` | 180 |
| D | §8 | `init-languages.el` | 439 |
| E | §9, §10, §11 | `init-git.el`, `init-terminal.el`, `init-appearance.el` | 87, 15, 20 |
| F | §12, §13, §14 | `init-org.el`, `init-obsidian.el`, `init-org-roam.el` | 28, 34, 93 |
| G | §15 | `init-ai.el` (folds in the `claude-jobs-view` `use-package` block) | 22 |
| Phase 3 | (none — shrinks `init.el` to loader form) | — | — |

Total new files: 13. Total moved LoC: ~1204. Per-file header overhead: ~6 lines
× 13 = ~78. Expected `init.el` final size: ~60 lines (§1 bootstrap + load-path
+ `mapc require` block + `(load custom-file)` tail).

## Commit Plan

Each batch is one commit. Commit subjects mirror the area-prefixed style in
recent history (see [`CLAUDE.md` "Commit conventions"](../../CLAUDE.md#commit-conventions)):

| # | Subject |
|---|---|
| 0 | `emacs: drop stale init.elc + move load-path push above the loader` |
| 1 | `emacs: split §2-§3 into lisp/init-defaults.el + init-system-packages.el` |
| 2 | `emacs: split §4-§6 into lisp/init-{completion,corfu,snippets}.el` |
| 3 | `emacs: split §7 (editing) into lisp/init-editing.el` |
| 4 | `emacs: split §8 (languages) into lisp/init-languages.el` |
| 5 | `emacs: split §9-§11 into lisp/init-{git,terminal,appearance}.el` |
| 6 | `emacs: split §12-§14 into lisp/init-{org,obsidian,org-roam}.el` |
| 7 | `emacs: split §15 (ai) into lisp/init-ai.el; init.el now thin loader` |
| 8 (optional) | `emacs: byte-compile lisp/init-*.el modules` |
| 9 (deferred) | `docs: update FEATURES.md to link new init-*.el module files` |

Commits 8 and 9 are optional / deferred — call them out separately in the
final summary; don't bundle into the move commits.

## Open Questions

None blocking the refactor. Surface to user **after** Phase 4:

- Sub-split §8 further (`init-eglot.el` + `init-treesit.el` + per-language)?
  Defer until we see how often `lisp/init-languages.el` is edited.
- Add a `make compile` shortcut or post-package-install recompile hook? Defer.
- Update [`FEATURES.md`](../FEATURES.md) to link the new file paths instead
  of "§N" references? Yes — but as commit 9, after the move is in.

## Deferred (NOT in scope)

- §8 internal sub-split (see Open Questions).
- Migration from `use-package` / MELPA to `straight.el` / `elpaca`.
- Literate config (init.org + org-babel-load-file).
- Auto-byte-compile-on-save (e.g. via `auto-compile`).
- Documentation overhaul of [`FEATURES.md`](../FEATURES.md) (track as commit 9).
