# TODO — split `init.el` into `lisp/init-<area>.el` modules

Spec: [`SPEC.md`](../SPEC.md). Plan: [`plan.md`](plan.md).

Tasks are ordered by dependency. Each batch produces exactly one commit per
the [Commit Plan](plan.md#commit-plan); do not bundle batches together.

## Phase 0 — Baseline capture (blocks everything else)

- [ ] **T0.1 Capture `*Messages*` + feature snapshot from the current monolith**
  - Acceptance:
    - `/tmp/messages-baseline.txt` exists with the last 8 KB of `*Messages*`
      after a clean `emacs --daemon` boot of the pre-refactor `init.el`.
    - `/tmp/features-baseline.txt` exists with the value of `features`
      (truncated to entries with the `init-` prefix or the
      `use-package`-managed symbols — for diffing later).
    - The currently-running daemon (if any) is **not** killed; the baseline
      is captured in a throwaway daemon socket `split-check`.
  - Verify:
    ```bash
    emacs --daemon=split-check
    emacsclient -s split-check -e \
      '(with-current-buffer "*Messages*"
         (buffer-substring-no-properties
           (max (point-min) (- (point-max) 8000)) (point-max)))' \
      | sed 's/^"//; s/"$//' > /tmp/messages-baseline.txt
    emacsclient -s split-check -e '(prin1-to-string features)' \
      > /tmp/features-baseline.txt
    emacsclient -s split-check -e '(kill-emacs)'
    test -s /tmp/messages-baseline.txt && test -s /tmp/features-baseline.txt && echo ok
    ```
  - Files: none modified — produces `/tmp/messages-baseline.txt`,
    `/tmp/features-baseline.txt` (not tracked).
  - Scope: **XS**.

## Phase 1 — Loader prep

- [ ] **T1.1 Drop stale `init.elc` + move `(add-to-list 'load-path …)` to §1**
  - Acceptance:
    - [`init.elc`](../init.elc) deleted (`rm init.elc`).
    - The single `(add-to-list 'load-path (expand-file-name "lisp"
      user-emacs-directory))` line currently at
      [`init.el:1301`](../init.el) moves to just under §1's bootstrap (right
      after the `exec-path-from-shell` `use-package` block, ~line 92).
    - No other lines in `init.el` move; behaviour identical.
  - Verify (Phase 1 checkpoint):
    ```bash
    emacs --batch -l init.el --eval '(message "ok")'   # exit 0, prints ok
    emacs --daemon=split-check
    emacsclient -s split-check -e '(member (expand-file-name "lisp" user-emacs-directory) load-path)'
    # expect: a non-nil list (lisp/ is on load-path)
    emacsclient -s split-check -e '(kill-emacs)'
    ```
  - Files: [`init.el`](../init.el), `init.elc` (deleted).
  - Commit: `emacs: drop stale init.elc + move load-path push above the loader`
  - Scope: **XS**.

## Phase 2 — Section moves (7 batches, sequential)

Each batch follows the same template:

> 1. Create the new `lisp/init-<area>.el` files with the canonical library
>    header + `(provide …)` trailer (see [`SPEC.md` Code Style](../SPEC.md#code-style)).
> 2. Cut the corresponding `;; N.` block(s) from [`init.el`](../init.el),
>    paste verbatim between the header and `(provide …)`.
> 3. Add the new `(require 'init-<area>)` line(s) to the `(mapc #'require '(…))`
>    block — which is being built incrementally during Phase 2.
> 4. Smoke-test (see [plan.md Verification Checkpoints](plan.md#verification-checkpoints)).
> 5. Commit with the subject from [Commit Plan](plan.md#commit-plan).

### Batch A — §2 + §3

- [ ] **T2.A.1 Move §2 (defaults) → `lisp/init-defaults.el`**
  - Acceptance:
    - [`lisp/init-defaults.el`](../lisp/init-defaults.el) exists, header + body
      ([`init.el:94-158`](../init.el)) + `(provide 'init-defaults)`.
    - `init.el` no longer contains the `;; 2. Better built-in defaults` block.
    - `init.el` has `(require 'init-defaults)` inside a (newly-introduced)
      `(mapc #'require '(...))` block placed below the `(add-to-list 'load-path …)`.
    - `custom-file` resolution still works (smoke check below).
  - Verify: Phase 2 checkpoint (batch-level, see T2.A.3).
  - Files: [`init.el`](../init.el), [`lisp/init-defaults.el`](../lisp/init-defaults.el).
  - Scope: **S**.

- [ ] **T2.A.2 Move §3 (system-packages) → `lisp/init-system-packages.el`**
  - Acceptance:
    - [`lisp/init-system-packages.el`](../lisp/init-system-packages.el) exists with
      header + body ([`init.el:159-168`](../init.el)) + `(provide …)`.
    - `init.el` no longer contains the `;; 3. system-packages` block.
    - `(require 'init-system-packages)` appended after `init-defaults` in the
      `mapc` block.
  - Verify: Phase 2 checkpoint (batch-level, see T2.A.3).
  - Files: [`init.el`](../init.el), [`lisp/init-system-packages.el`](../lisp/init-system-packages.el).
  - Scope: **XS**.

- [ ] **T2.A.3 Batch A smoke + commit**
  - Acceptance:
    - All 4 verification commands (1-4 in [plan.md
      Verification Checkpoints](plan.md#verification-checkpoints)) pass.
    - `git status` shows: `init.el` modified, two new `lisp/init-*.el` files,
      no other changes.
  - Commit: `emacs: split §2-§3 into lisp/init-defaults.el + init-system-packages.el`
  - Scope: **XS** (just commit).

### Batch B — §4 + §5 + §6

- [ ] **T2.B.1 Move §4 (Vertico ecosystem) → `lisp/init-completion.el`**
  - Acceptance:
    - Header + body ([`init.el:169-313`](../init.el), 144 lines) +
      `(provide 'init-completion)`.
    - Intra-section `:after` chains preserved (vertico-directory →
      vertico, embark-consult → embark + consult, etc.).
  - Files: [`init.el`](../init.el), [`lisp/init-completion.el`](../lisp/init-completion.el).
  - Scope: **S**.

- [ ] **T2.B.2 Move §5 (Corfu + Cape) → `lisp/init-corfu.el`**
  - Acceptance: header + body ([`init.el:314-373`](../init.el)) + provide.
  - Files: [`init.el`](../init.el), [`lisp/init-corfu.el`](../lisp/init-corfu.el).
  - Scope: **XS**.

- [ ] **T2.B.3 Move §6 (YASnippet) → `lisp/init-snippets.el`**
  - Acceptance: header + body ([`init.el:374-384`](../init.el)) + provide.
  - Files: [`init.el`](../init.el), [`lisp/init-snippets.el`](../lisp/init-snippets.el).
  - Scope: **XS**.

- [ ] **T2.B.4 Batch B smoke + commit**
  - Acceptance: verification commands 1-4 pass; vertico minibuffer shows on
    `C-x C-f`; corfu pops on a real buffer.
  - Commit: `emacs: split §4-§6 into lisp/init-{completion,corfu,snippets}.el`
  - Scope: **XS**.

### Batch C — §7

- [ ] **T2.C.1 Move §7 (editing) → `lisp/init-editing.el`**
  - Acceptance: header + body ([`init.el:385-565`](../init.el), 180 lines) +
    `(provide 'init-editing)`. which-key, helpful, jinx, avy, expand-region,
    multiple-cursors, rainbow-delimiters, vundo, hl-todo, pulsar,
    ace-window, popper, winner, breadcrumb all moved.
  - Verify: verification commands 1-4 pass; `which-key` pops on partial
    chord; `M-x avy-goto-char` works.
  - Files: [`init.el`](../init.el), [`lisp/init-editing.el`](../lisp/init-editing.el).
  - Commit: `emacs: split §7 (editing) into lisp/init-editing.el`
  - Scope: **S**.

### Batch D — §8 (the elephant)

- [ ] **T2.D.1 Move §8 (Project / LSP / languages) → `lisp/init-languages.el`**
  - Acceptance:
    - Header + body ([`init.el:566-1005`](../init.el), 439 lines) +
      `(provide 'init-languages)`.
    - Includes: project.el, envrc, eglot, eglot-booster, consult-eglot,
      vue-mode, ggtags, treesit-auto, lua-mode, combobulate, flymake,
      flymake-eslint, apheleia, markdown-mode.
    - `consult-eglot :after (consult eglot)` works — consult is in
      `init-completion` (loaded first), eglot is in this file. Verify
      symbolically + smoke.
    - The treesit-extra-load-path setup ([`init.el:871`](../init.el)) moves
      with §8.
  - Verify (in addition to commands 1-4):
    ```bash
    emacsclient -s split-check -e \
      '(progn (find-file "/tmp/lang-smoke.go") (insert "package main\nfunc main(){}\n") major-mode)'
    # expect: go-ts-mode (eglot may take a beat to start, that's fine)
    emacsclient -s split-check -e \
      '(progn (find-file "/tmp/lang-smoke.lua") (insert "local x = 1\n") major-mode)'
    # expect: lua-mode (no tree-sitter ABI warning)
    ```
  - Files: [`init.el`](../init.el), [`lisp/init-languages.el`](../lisp/init-languages.el).
  - Commit: `emacs: split §8 (languages) into lisp/init-languages.el`
  - Scope: **M** (one file, but the biggest and most cross-referenced).

### Batch E — §9 + §10 + §11

- [ ] **T2.E.1 Move §9 (Git) → `lisp/init-git.el`**
  - Acceptance: header + body ([`init.el:1006-1093`](../init.el)) +
    provide; magit + diff-hl + magit-todos + magit-delta + difftastic all
    moved together (intra-batch `:after magit` chain preserved).
  - Files: [`init.el`](../init.el), [`lisp/init-git.el`](../lisp/init-git.el).
  - Scope: **S**.

- [ ] **T2.E.2 Move §10 (vterm) → `lisp/init-terminal.el`**
  - Acceptance: header + body ([`init.el:1094-1109`](../init.el)) + provide.
  - Files: [`init.el`](../init.el), [`lisp/init-terminal.el`](../lisp/init-terminal.el).
  - Scope: **XS**.

- [ ] **T2.E.3 Move §11 (appearance) → `lisp/init-appearance.el`**
  - Acceptance: header + body ([`init.el:1110-1130`](../init.el)) + provide;
    doom-themes + nerd-icons + doom-modeline all moved.
  - Files: [`init.el`](../init.el), [`lisp/init-appearance.el`](../lisp/init-appearance.el).
  - Scope: **XS**.

- [ ] **T2.E.4 Batch E smoke + commit**
  - Acceptance: verification commands 1-4 pass; `M-x magit-status` opens;
    doom-modeline visible.
  - Commit: `emacs: split §9-§11 into lisp/init-{git,terminal,appearance}.el`
  - Scope: **XS**.

### Batch F — §12 + §13 + §14

- [ ] **T2.F.1 Move §12 (Org-mode) → `lisp/init-org.el`**
  - Acceptance: header + body ([`init.el:1131-1159`](../init.el)) + provide;
    org + org-modern + org-appear all moved.
  - Files: [`init.el`](../init.el), [`lisp/init-org.el`](../lisp/init-org.el).
  - Scope: **XS**.

- [ ] **T2.F.2 Move §13 (Obsidian) → `lisp/init-obsidian.el`**
  - Acceptance: header + body ([`init.el:1160-1194`](../init.el)) + provide.
  - Files: [`init.el`](../init.el), [`lisp/init-obsidian.el`](../lisp/init-obsidian.el).
  - Scope: **XS**.

- [ ] **T2.F.3 Move §14 (org-roam) → `lisp/init-org-roam.el`**
  - Acceptance: header + body ([`init.el:1195-1288`](../init.el)) + provide;
    `org-roam-ui :after org-roam` works (intra-batch).
  - Files: [`init.el`](../init.el), [`lisp/init-org-roam.el`](../lisp/init-org-roam.el).
  - Scope: **S**.

- [ ] **T2.F.4 Batch F smoke + commit**
  - Acceptance: verification commands 1-4 pass; `M-x org-roam-node-find`
    opens minibuffer.
  - Commit: `emacs: split §12-§14 into lisp/init-{org,obsidian,org-roam}.el`
  - Scope: **XS**.

### Batch G — §15

- [ ] **T2.G.1 Move §15 (AI tooling + claude-jobs-view) → `lisp/init-ai.el`**
  - Acceptance:
    - Header + body ([`init.el:1289-1309`](../init.el)) + provide.
    - The `(use-package claude-jobs-view :ensure nil :commands (claude-jobs-view))`
      block (currently [`init.el:1307-1309`](../init.el)) moves into
      `init-ai.el`. [`lisp/claude-jobs-view.el`](../lisp/claude-jobs-view.el)
      itself is NOT moved or renamed.
    - The standalone `(add-to-list 'load-path …)` line is gone from §15's
      former location (already moved to §1 in Phase 1).
  - Verify: `M-x claude-jobs-view` opens the tabulated UI.
  - Files: [`init.el`](../init.el), [`lisp/init-ai.el`](../lisp/init-ai.el).
  - Commit: `emacs: split §15 (ai) into lisp/init-ai.el; init.el now thin loader`
  - Scope: **XS**.

## Phase 3 — Finalize `init.el` shape

- [ ] **T3.1 Collapse §16 commentary + tidy loader**
  - Acceptance:
    - The `;; ----- 16. End of file -----` divider + its commentary block
      ([`init.el:1311-1318`](../init.el)) shrink to a single one-liner
      explaining custom-file ownership.
    - `init.el` final structure: file header → §1 bootstrap (package +
      use-package + no-littering + exec-path-from-shell + load-path push)
      → `(mapc #'require '(13-element list))` → `(load custom-file 'noerror
      'nomessage)` (if not already implicit via §2's `custom-file` setq)
      → trailer.
    - `wc -l init.el` ≤ 80.
    - No content from any moved section remains inline.
  - Verify:
    ```bash
    wc -l init.el            # ≤ 80
    rg -n '^;; [0-9]+\. ' init.el | wc -l  # should print 1 (only §1)
    emacs --batch -l init.el --eval '(message "ok")'
    ```
  - Files: [`init.el`](../init.el).
  - Commit: folded into the last Phase 2 batch (Batch G) — same commit
    subject (`… init.el now thin loader`).
  - Scope: **XS**.

## Phase 4 — Cleanup + final audit

- [ ] **T4.1 Final daemon smoke + feature audit**
  - Acceptance: every check passes (see [plan.md Verification
    Checkpoints](plan.md#verification-checkpoints) #5-#7):
    - Line counts match expected (`init.el` ≤ 80; sum of `lisp/init-*.el`
      ≈ pre-refactor `init.el` − 80).
    - `git diff --stat HEAD~7..HEAD` shows ~1260 deletions / ~1260
      insertions.
    - Feature audit query returns every cell `(symbol . t)`.
    - All 7 high-traffic features (`C-x C-f`, `consult-ripgrep`, `.go` →
      eglot, `.lua` → lua-mode, `magit-status`, `org-roam-node-find`,
      `claude-jobs-view`) work.
    - `*Messages*` diff vs baseline has no new `Warning`, `error`,
      `Cannot open`, `unable` lines.
  - Files: none.
  - Scope: **XS** (audit only).

- [ ] **T4.2 (optional) Batch byte-compile `lisp/init-*.el`**
  - Acceptance:
    - `emacs -Q --batch -L lisp/ -f batch-byte-compile lisp/init-*.el`
      produces 13 `.elc` files with no warnings.
    - Daemon re-boots cleanly with the `.elc`s present.
    - `.elc` files are gitignored — `git status` shows nothing new.
  - Verify:
    ```bash
    emacs -Q --batch -L lisp/ -f batch-byte-compile lisp/init-*.el
    ls lisp/init-*.elc | wc -l       # 13
    emacs --daemon=split-check && emacsclient -s split-check -e '(kill-emacs)'
    git status --porcelain lisp/     # no .elc entries
    ```
  - Files: produces 13 `lisp/init-*.elc` files (gitignored).
  - Commit: `emacs: byte-compile lisp/init-*.el modules` (optional).
  - Scope: **XS**.

## Phase 5 — Deferred follow-ups (NOT in scope of the refactor)

- [ ] **T5.1 (deferred) Update [`FEATURES.md`](../FEATURES.md) to link new module files**
  - Currently references "§N" by number. After the refactor, swap to
    `[init-editing.el](lisp/init-editing.el)`-style links per the
    [global cross-references rule](../../.claude/CLAUDE.md#cross-references-in-documentation).
  - Separate commit; don't bundle into the move.

- [ ] **T5.2 (deferred) RFC for sub-splitting `lisp/init-languages.el`**
  - Trigger: if `git log --follow lisp/init-languages.el` shows >5 commits
    in any 3-month window, draft an RFC for splitting into `init-eglot.el`
    + `init-treesit.el` + per-language modules.

- [ ] **T5.3 (deferred) Auto-compile hook**
  - Decide whether `auto-compile-mode` or a `package-install`-time recompile
    hook is worth the complexity.

## Checkpoint — End of refactor

- [ ] All Phase 0-4 acceptance criteria met.
- [ ] 7 commits landed (8 with the optional byte-compile).
- [ ] No regressions in the 7 high-traffic features.
- [ ] User has manually opened a TTY frame and used the editor for at least
      10 minutes without surprises.
- [ ] Pause and let the user confirm before any deferred Phase 5 work.
