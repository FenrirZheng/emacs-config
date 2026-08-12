# TODO — add Dirvish to the Emacs config

Spec: [`SPEC.md`](../SPEC.md). Plan: [`plan.md`](plan.md).

Tasks are ordered by dependency. Phase 2 produces exactly one commit
(per the [Commit Plan](plan.md#phases--commit-plan)); Phase 0 is a manual
package install with no commit; Phase 3 is a deferred follow-up.

## Phase 0 — Package install (manual, no commit)

- [ ] **T0.1 Refresh MELPA + restart daemon to pick up `dirvish`**
  - Acceptance:
    - `(package-installed-p 'dirvish)` returns `t` in the running daemon.
    - `(executable-find "fdfind")` returns a non-nil path
      (Debian's `fd` binary — already required by global
      [`~/.claude/CLAUDE.md`](../../../.claude/CLAUDE.md)).
  - Verify:
    ```bash
    emacsclient -e '(my/package-refresh)'
    # Wait for the message "Package refresh done." in *Messages*.
    # Then: M-x package-install RET dirvish RET   (or rely on use-package
    # auto-install after Phase 2 + restart).
    emacsclient -e '(package-installed-p (quote dirvish))'   # → t
    which fdfind                                              # non-empty
    ```
  - Files: none (touches `~/.emacs.d/elpa/`, gitignored).
  - Scope: **XS**.

## Phase 1 — Create the module file

- [ ] **T1.1 Write `lisp/init-dirvish.el`**
  - Acceptance:
    - File exists at [`../lisp/init-dirvish.el`](../lisp/init-dirvish.el).
    - First line:
      `;;; init-dirvish.el --- Dirvish: polished Dired with icons + preview -*- lexical-binding: t; -*-`.
    - File ends with `(provide 'init-dirvish)` followed by
      `;;; init-dirvish.el ends here`.
    - 40–70 lines.
    - Body matches [`SPEC.md` Code Style](../SPEC.md#code-style) verbatim:
      two `use-package` blocks (`dired :ensure nil`, `dirvish :ensure t`),
      `dirvish-override-dired-mode`, the six-entry quick-access list,
      icon-only `dirvish-attributes` (no `vc-state`, no `git-msg`),
      `(setq dirvish-fd-program (or (executable-find "fdfind")
      (executable-find "fd")))`, and the keybindings from the spec.
  - Verify:
    ```bash
    head -1 lisp/init-dirvish.el | rg -q 'lexical-binding'
    tail -2 lisp/init-dirvish.el | rg -q 'init-dirvish ends here'
    rg -n 'vc-state|git-msg' lisp/init-dirvish.el
    # expect: no matches outside the commentary header
    emacs -Q --batch -L lisp/ -f batch-byte-compile lisp/init-dirvish.el
    # expect: 0 errors (deferred-symbol warnings against nerd-icons are OK)
    rm -f lisp/init-dirvish.elc   # cleanup; .elc is gitignored anyway
    ```
  - Files: [`../lisp/init-dirvish.el`](../lisp/init-dirvish.el) (new).
  - Scope: **S**.

## Phase 2 — Wire + smoke + commit (single commit)

- [ ] **T2.1 Add `init-dirvish` to `init.el`**
  - Acceptance:
    - One new line in the commentary block (between the `init-appearance`
      and `init-org` description lines, around [`init.el:19`](../init.el)):
      `;;   init-dirvish        -- Dirvish: polished Dired with icons + preview`
    - One new line in the `(mapc #'require '(...))` block (between
      `init-appearance` and `init-org`, around [`init.el:121`](../init.el)):
      `init-dirvish`.
    - No other lines in [`init.el`](../init.el) change.
  - Verify:
    ```bash
    git diff --stat init.el
    # expect: init.el | 2 ++
    rg -n 'init-dirvish' init.el | wc -l    # 2
    ```
  - Files: [`../init.el`](../init.el).
  - Scope: **XS**.

- [ ] **T2.2 Checkpoint A — Batch load**
  - Acceptance:
    - `emacs --batch -l init.el --eval '(message "ok")'` exits 0,
      prints `ok`, no `Symbol's function definition is void`, no
      `Cannot open load file`.
  - Verify: see [`plan.md` Checkpoint A](plan.md#checkpoint-a--batch-load-parity-after-phase-2-edits-before-commit).
  - **Stop and diagnose if this fails** — do not proceed.
  - Files: none.
  - Scope: **XS**.

- [ ] **T2.3 Checkpoint B — Daemon smoke**
  - Acceptance (each is one check):
    - `(featurep 'init-dirvish)` is `t`.
    - `dirvish-override-dired-mode` is `t`.
    - `(package-installed-p 'dirvish)` is `t`.
    - `dirvish-attributes` equals
      `(subtree-state nerd-icons collapse file-time file-size)`.
    - `dirvish-fd-program` is a non-nil path string.
    - In the TTY frame: `C-c f` opens Dirvish; `C-x d` opens Dirvish (not
      classic Dired); `?` opens `dirvish-dispatch`; `TAB` expands a
      subtree; `o` opens the six-entry quick-access menu; `C-c s` opens
      `dirvish-side` and `q` closes it.
  - Verify: see [`plan.md` Checkpoint B](plan.md#checkpoint-b--daemon-smoke-after-phase-2-edits-before-commit).
  - Files: none.
  - Scope: **S**.

- [ ] **T2.4 Checkpoint C — `$HOME` hazard regression**
  - Acceptance:
    - `time emacsclient -e '(let ((default-directory "~/")) (dirvish))'`
      reports `real` < 1 s.
    - No visible CPU spike during the call.
    - Verify the regression vector: `dirvish-attributes` contains neither
      `vc-state` nor `git-msg`.
  - Verify: see [`plan.md` Checkpoint C](plan.md#checkpoint-c--home-hazard-regression-before-commit).
  - Files: none.
  - Scope: **XS**.

- [ ] **T2.5 Checkpoint D — Diff hygiene**
  - Acceptance:
    - `git status` shows: `init.el` modified, `SPEC.md` modified,
      `tasks/plan.md` modified, `tasks/todo.md` modified, and **one**
      new untracked file `lisp/init-dirvish.el`.
    - No `.elc` files in `git status`.
    - No edits to: [`../custom.el`](../custom.el),
      [`../early-init.el`](../early-init.el),
      [`../lisp/init-appearance.el`](../lisp/init-appearance.el),
      [`../lisp/init-editing.el`](../lisp/init-editing.el),
      [`../lisp/init-git.el`](../lisp/init-git.el),
      [`../lisp/init-defaults.el`](../lisp/init-defaults.el), or any
      other [`../lisp/init-*.el`](../lisp/) module.
  - Verify: see [`plan.md` Checkpoint D](plan.md#checkpoint-d--diff-hygiene-before-commit).
  - Files: none.
  - Scope: **XS**.

- [ ] **T2.6 Commit (one commit, on operator go-ahead)**
  - Acceptance:
    - Single commit on `main`; no `--no-verify`; gitleaks pre-commit hook
      passes.
    - Subject: `emacs: add init-dirvish module — Dirvish over Dired with icons + preview`.
    - Body: one short paragraph linking to [`SPEC.md`](../SPEC.md) and
      noting the deliberate `vc-state` + `git-msg` omissions plus the
      pending `FEATURES.md` follow-up.
    - `git log -1 --stat` shows 5 files changed (new
      `lisp/init-dirvish.el` + modified `init.el` + `SPEC.md` +
      `tasks/plan.md` + `tasks/todo.md`).
  - Verify:
    ```bash
    git log -1 --stat
    git status     # clean
    ```
  - Files: none beyond the previous tasks.
  - Scope: **XS**.

## Phase 3 — Deferred follow-up (separate commit)

- [ ] **T3.1 Add a "File manager (Dirvish)" section to [`FEATURES.md`](../FEATURES.md)**
  - Acceptance:
    - New top-level section in [`FEATURES.md`](../FEATURES.md), placed
      near the appearance / workflow sections, with a key table mirroring
      [`SPEC.md` Code Style](../SPEC.md#code-style)'s `:bind` form.
    - Cross-link points back to
      [`lisp/init-dirvish.el`](../lisp/init-dirvish.el) per the [global
      cross-references rule](../../../.claude/CLAUDE.md#cross-references-in-documentation).
  - Verify: read the rendered section in a markdown viewer; check that
    keybindings match the actual `init-dirvish.el` body.
  - Files: [`../FEATURES.md`](../FEATURES.md).
  - Commit: `emacs: FEATURES.md — add §"File manager (Dirvish)"`.
  - Scope: **S**.

## Phase 4 — Even-further-deferred (decide after daily use)

- [ ] **T4.1 (defer) Install optional preview binaries**
  - Decide whether to `apt install poppler-utils ffmpegthumbnailer
    mediainfo libvips-tools imagemagick` for PDF / video / audio /
    vector previews.
  - Trigger: operator reaches for `M-x dirvish-emerge-menu` / preview
    pane and notices a missing capability.

- [ ] **T4.2 (defer) Enable `dirvish-peek-mode` globally**
  - Decide whether `find-file` minibuffer previews are useful given the
    existing consult-preview flows in
    [`lisp/init-completion.el`](../lisp/init-completion.el).

- [ ] **T4.3 (defer) Enable `dirvish-side-follow-mode` globally**
  - Decide whether to make the side panel auto-track the current buffer
    (treemacs-style).

- [ ] **T4.4 (defer) Re-evaluate `vc-state` / `git-msg`**
  - If the operator habitually opens Dirvish in smaller repos (not
    `$HOME`), consider scoping the costly attributes via
    `dirvish-mode-hook` rather than turning them on globally.

## Checkpoint — End of implementation

- [ ] All Phase 0–2 acceptance criteria met.
- [ ] One commit landed (Phase 2).
- [ ] Daily-driver smoke: operator opens Dirvish at least three times in
      different repos without surprises.
- [ ] Pause and let the operator confirm before Phase 3 (FEATURES.md
      update).
