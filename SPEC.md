# Spec: split monolithic `init.el` into `lisp/init-<area>.el` modules

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
Source-of-truth before this change: [`init.el`](init.el) (1320 lines, 68 KB,
sixteen `;; N. <name>` sections under one `;;; Code:` block).

## Objective

Move from one ~1320-line `init.el` to a thin loader plus per-section module
files under [`lisp/`](lisp/), one file per current top-level section. The
section content moves verbatim; this refactor is a **layout change, not a
behaviour change**.

Why this matters:
- §8 (Project / LSP / languages) alone is 439 lines, one-third of the file.
  Adding a new language mode currently means scrolling past 870 lines of
  unrelated config.
- Cross-section navigation today relies on remembering the section number
  (`;; 8.`) — file names like `init-languages.el` are self-describing.
- Byte-compilation is currently all-or-nothing; per-module `.elc` lets one
  section's edit invalidate only its own compiled file.
- The infrastructure is already half-built: `lisp/` exists,
  [`init.el:1301`](init.el) already adds it to `load-path`, and
  [`lisp/claude-jobs-view.el`](lisp/claude-jobs-view.el) already follows the
  `(use-package … :ensure nil)` + local-`provide` pattern.

### Target user

The single operator of this repo (one machine). The split is for that operator's
own future edits — not for sharing, packaging, or third-party reuse.

### Assumptions I'm making

1. **No behaviour change.** Every section's content moves verbatim — same
   `use-package` blocks, same `setq`s, same hooks, same order. If a smoke
   test passes today, it must pass after the split with no edits.
2. **Section boundaries are correct as drawn.** The existing 16 `;; N.` blocks
   are the unit of split. No collapsing or further sub-splitting in this pass.
3. **`use-package` is the only loading mechanism.** No transition to
   `straight.el` / `elpaca` / literate org. Boot path stays
   `early-init.el` → `init.el` → `(require 'init-<area>)` × N → `custom.el`.
4. **Byte-compiled `.elc` files are disposable.** Existing
   [`init.elc`](init.elc) will be deleted; modules can be byte-compiled or
   not, the config must work either way.
5. **`claude-jobs-view.el` is NOT a section.** It's a real elisp library that
   happens to live under `lisp/`. It stays where it is and is still required
   from `init-ai.el` (the new home of current §15).
6. **Network-free boot stays.** `package-refresh-contents` is still **not**
   called at startup (see [`init.el:49-54`](init.el)); `my/package-refresh`
   stays as the on-demand command.

→ Correct any of these now or the implementation will assume them.

## Tech Stack

- Emacs 30.1 with `use-package` (built-in since Emacs 29). No new packages
  introduced.
- Existing `lisp/` directory on `load-path` (added at
  [`init.el:1301`](init.el); moves up to the bootstrap section after the
  split).
- `no-littering` (already in §1) — module load order keeps it loading before
  any section that creates state files.

## Commands

After the refactor:

| step | command | notes |
|---|---|---|
| start daemon (smoke) | `emacs --daemon` | should complete without errors |
| start client (smoke) | `emacsclient -c -nw` | mode-line, fonts, modules all live |
| byte-compile all modules | `emacs -Q --batch -L lisp/ -f batch-byte-compile lisp/init-*.el` | optional but recommended after edits |
| clean stale top-level `.elc` | `rm -f init.elc` | one-shot at the end of the refactor |
| audit load order | `emacsclient -e '(mapcar #'\''car load-history)'` | confirm every `init-<area>` appears exactly once |
| feature audit | `emacsclient -e '(mapcar (lambda (s) (cons s (featurep s))) (quote (init-defaults init-completion init-corfu init-snippets init-editing init-languages init-git init-terminal init-appearance init-org init-obsidian init-org-roam init-ai)))'` | every cell should be `(symbol . t)` |
| batch sanity | `emacs --batch -l init.el --eval '(message "ok")'` | exits 0, prints `ok`, no `Symbol's function definition is void` |

## Project Structure

```
init.el              → thin loader (~60 lines)
                       §1 (package + use-package bootstrap) +
                       load-path push for `lisp/` +
                       sequential `(require 'init-…)` block +
                       `(load custom-file)` tail
custom.el            → unchanged (managed by M-x customize)
early-init.el        → unchanged
lisp/init-defaults.el        → §2  Better built-in defaults
lisp/init-system-packages.el → §3  system-packages wrapper
lisp/init-completion.el      → §4  Vertico ecosystem
lisp/init-corfu.el           → §5  Corfu + Cape (in-buffer completion)
lisp/init-snippets.el        → §6  YASnippet
lisp/init-editing.el         → §7  Editing enhancements
lisp/init-languages.el       → §8  Project / LSP / tree-sitter / languages
lisp/init-git.el             → §9  Magit + diff-hl + magit-todos
lisp/init-terminal.el        → §10 vterm
lisp/init-appearance.el      → §11 doom-themes + doom-modeline + nerd-icons
lisp/init-org.el             → §12 Org-mode (minimal)
lisp/init-obsidian.el        → §13 obsidian.el
lisp/init-org-roam.el        → §14 org-roam
lisp/init-ai.el              → §15 AI / agent tooling (eca / acp / shell-maker
                                   + the existing `claude-jobs-view` require)
lisp/claude-jobs-view.el     → UNCHANGED (real library, not a section)
SPEC.md                      → this file
```

Section 1 (package bootstrap) **must** stay in `init.el` itself — `use-package`
has to be `require`d before any module file can use it. Section 16 (end-of-file
comment about `custom.el`) folds into a one-liner at the bottom of the new
`init.el`.

## Code Style

Every new `lisp/init-<area>.el` file follows the canonical Emacs Lisp library
header that [`lisp/claude-jobs-view.el`](lisp/claude-jobs-view.el) already
uses:

```elisp
;;; init-completion.el --- Minibuffer / completion UI -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 4 of the original init.el.
;; Vertico + Orderless + Marginalia + Consult + Embark + Wgrep.
;; Behaviour: identical to pre-split init.el §4 — this is a layout change only.

;;; Code:

;; ... use-package blocks moved verbatim from old init.el §4 ...

(provide 'init-completion)
;;; init-completion.el ends here
```

The post-split [`init.el`](init.el) shrinks to roughly this shape:

```elisp
;;; init.el --- Personal Emacs configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; Thin loader. Each `lisp/init-<area>.el' module corresponds to one
;; section of the pre-2026-05-19 monolithic init.el (see git log for the
;; split commit).
;;; Code:

;; §1. Package system & use-package bootstrap  (kept inline — `use-package'
;;     must be loaded before any module file can call it).
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(defun my/package-refresh () "Refresh package archive on demand."
       (interactive) (package-refresh-contents))
(require 'use-package)
(setq use-package-always-ensure t)
(use-package no-littering :demand t :config ...)
(use-package exec-path-from-shell :demand t :if ... :config ...)

;; Local-lisp dir for the per-section modules and hand-written libraries.
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Modules — load order matters: no-littering is already up; the rest
;; follow the original section ordering verbatim.
(mapc #'require
      '(init-defaults
        init-system-packages
        init-completion
        init-corfu
        init-snippets
        init-editing
        init-languages
        init-git
        init-terminal
        init-appearance
        init-org
        init-obsidian
        init-org-roam
        init-ai))

;;; init.el ends here
```

`custom-file` resolution (currently inside §2) stays in `init-defaults.el`.

## Testing Strategy

No test framework. Verification is smoke + diff-based:

- **Batch load**: `emacs --batch -l init.el --eval '(message "ok")'` exits 0,
  prints `ok`, prints no `Symbol's function definition is void`, no
  `Cannot open load file`, no `Wrong type argument`.
- **Daemon smoke**: `emacs --daemon` produces only the existing benign
  messages (no new warnings). `emacsclient -c -nw` opens a usable frame with
  doom-modeline, doom-themes, vertico minibuffer, corfu in-buffer completion.
- **Feature presence**: every expected `init-<area>` is in `features`:
  ```
  emacsclient -e '(mapcar (lambda (s) (cons s (featurep s)))
                          (quote (init-defaults init-completion init-corfu
                                  init-snippets init-editing init-languages
                                  init-git init-terminal init-appearance
                                  init-org init-obsidian init-org-roam
                                  init-ai)))'
  ```
  Every cell `(symbol . t)`.
- **Behaviour parity** spot-checks (the high-traffic features):
  - `C-x C-f` → vertico minibuffer with marginalia annotations.
  - `M-x consult-ripgrep` → works.
  - Open a `.go` file → `go-ts-mode`, eglot starts, gopls connects.
  - Open a `.lua` file → `lua-mode` (regex), no tree-sitter ABI warning.
  - `M-x magit-status` → Magit opens normally; diff-hl fringe present.
  - `M-x org-roam-node-find` → org-roam minibuffer.
  - `M-x claude-jobs-view` → tabulated UI opens (proves the local-lisp
    require still works).
- **`*Messages*` audit** after a clean daemon start:
  ```
  emacsclient -e '(with-current-buffer "*Messages*"
                    (buffer-substring-no-properties
                      (max (point-min) (- (point-max) 8000)) (point-max)))'
  ```
  Diff against a captured pre-refactor baseline — no new warnings or
  errors, may differ in ordering of benign init messages.
- **Diff hygiene**:
  - `git diff init.el` shows ~1260 lines removed, the new thin-loader content
    added — net file becomes ~60 lines.
  - Each new `lisp/init-<area>.el` has a `git status` "new file" entry whose
    content equals the corresponding pre-refactor section + the
    library-header / `provide` wrapping. Nothing else.
  - `git diff custom.el early-init.el` empty (untouched).

## Boundaries

- **Always**:
  - Preserve every section's content **verbatim** (modulo the file header /
    `provide` wrapping). No "while I'm in here" cleanups.
  - Preserve section ordering. `no-littering` loads first, then everything
    else in the original §2 → §15 order, then `custom.el` last.
  - Every new file gets the `-*- lexical-binding: t; -*-` cookie on line 1.
  - Every new file ends with `(provide 'init-<area>)` and the `;;; … ends
    here` trailer (matches the convention in
    [`lisp/claude-jobs-view.el`](lisp/claude-jobs-view.el)).
  - Cross-section `with-eval-after-load` / `:after` references keep working
    untouched — they operate by feature symbol, not by file boundary, and
    the load order is preserved.
  - Delete [`init.elc`](init.elc) once at the end so a stale compiled file
    can't shadow the new `init.el`.
- **Ask first**:
  - Splitting one of the existing 16 sections further (e.g. teasing
    `init-languages.el` into `init-eglot.el` + `init-treesit.el` + per-lang
    files). Tempting for §8 specifically — defer to a follow-up RFC.
  - Collapsing two small sections into one file (e.g. §6 snippets + §5 corfu).
  - Switching to `straight.el` / `elpaca` / literate org / any non-`use-package`
    loader.
  - Renaming `lisp/claude-jobs-view.el` or moving it under any of the new
    `init-*.el` modules.
- **Never**:
  - Re-order sections to "feel cleaner". Order is part of the contract
    (no-littering before recentf, exec-path-from-shell before eglot, …).
  - Inline `(load "lisp/init-X")` calls — use `(require 'init-X)` so duplicate
    loads are no-ops and the feature list reflects what's actually loaded.
  - Add a `:after` / `with-eval-after-load` indirection that wasn't already
    in the monolith — behaviour must stay byte-identical.
  - Introduce a `Makefile` or build script to byte-compile. Manual
    `emacs --batch … -f batch-byte-compile` invocation is fine for a single
    operator.
  - Commit the per-module `.elc` files (they're already covered by
    [`.gitignore`](.gitignore) — verify before commit).

## Success Criteria

1. `emacs --batch -l init.el --eval '(message "ok")'` exits 0 with `ok` on
   stdout, no errors / warnings.
2. `emacs --daemon` + `emacsclient -c -nw` opens a frame; every smoke-check
   in "Testing Strategy" passes.
3. `wc -l init.el` ≤ 80 lines; `wc -l lisp/init-*.el` shows roughly the
   pre-split section sizes (file-by-file delta ≤ ~6 lines of header
   wrapping per file).
4. `git diff --stat` shows ~1260 lines deleted from `init.el`, ~1260 lines
   added across the 13 new `lisp/init-*.el` files. Net repo line count
   roughly conserved.
5. Feature audit query (Commands table) returns every cell as `(symbol . t)`.
6. `*Messages*` after a clean daemon start contains no new warnings vs the
   pre-refactor baseline (captured once before any moves).
7. Re-running the daemon after `M-x package-refresh` + `M-x package-upgrade-all`
   continues to work — module file paths don't bake in any MELPA-version
   assumptions.
8. [`init.elc`](init.elc) is removed; `git status` confirms it's untracked-
   ignored (already covered by [`.gitignore`](.gitignore)).
9. `M-x claude-jobs-view` still launches the tabulated UI — proves the
   pre-existing local-lisp require chain survives the refactor.

## Open Questions

None blocking. Surface to the user **after** the split lands, not before:

- Should §8 (`init-languages.el`, the 439-line elephant) be sub-split in a
  follow-up — e.g. `init-eglot.el` + `init-treesit.el` + per-language files?
  Defer until the simple split is in and we can see how often §8 alone is
  edited.
- Byte-compilation: do we want a `make compile` shortcut or a
  `post-package-install-hook` that recompiles changed modules? Defer —
  manual `emacs --batch -L lisp/ -f batch-byte-compile lisp/init-*.el` is
  fine for now.
- Documentation: [`FEATURES.md`](FEATURES.md) currently references sections
  by number (e.g. "§7 Editing"). Should those become file-path links
  (`[init-editing.el](lisp/init-editing.el)`) once the split lands? Yes —
  do it as a follow-up commit, not bundled with the move (keeps the diff
  reviewable).
