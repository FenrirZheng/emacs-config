; -*- mode: markdown -*-

# Spec: add Dirvish (polished Dired) to the Emacs config

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
Previous SPEC ("split monolithic `init.el` into `lisp/init-<area>.el` modules",
commit `fd6d8d0`) is now history — that refactor landed; this file replaces it
with the next planned change. Past SPEC.md content remains accessible via
`git show fd6d8d0:SPEC.md`.

## Objective

Add [Dirvish](https://github.com/alexluigit/dirvish) — a UI-rich enhancement
of Dired — to this Emacs 30.1 config as a new per-section module
[`lisp/init-dirvish.el`](lisp/init-dirvish.el), loaded by the [`init.el`](init.el)
thin loader after [`init-appearance.el`](lisp/init-appearance.el).

Why this matters:
- Default Dired is fine for one-off file ops but lacks icons, preview,
  history, a follow-mode side panel, and the `?`-dispatch transient that
  makes file management discoverable.
- `nerd-icons` is already configured (deferred) in
  [`init-appearance.el`](lisp/init-appearance.el) — Dirvish reuses that
  glyph set, no second icon stack.
- The config already has a workflow for "open a tree of files via the
  minibuffer" (vertico + consult-find) but no spatial file browser; a
  side-panel Dirvish complements rather than replaces consult-find.

### Target user

The single operator of this repo (one machine). Like every prior section,
this is for that operator's daily use, not for packaging or sharing.

### Assumptions I'm making

1. **New module file, not a fold-in.** Dirvish gets its own
   [`lisp/init-dirvish.el`](lisp/init-dirvish.el), mirroring the
   one-file-per-package granularity of `init-corfu.el`, `init-obsidian.el`,
   `init-org-roam.el`. It is **not** folded into `init-editing.el` or
   `init-appearance.el`.
2. **`use-package` MELPA install.** `dirvish` is installed from MELPA via
   `(use-package dirvish :ensure t …)`. `use-package-always-ensure` is `t`
   in [`init.el`](init.el), so `:ensure t` is redundant but kept for
   readability.
3. **`dirvish-override-dired-mode` is on.** Every `C-x d` / `C-x C-f` into
   a directory routes through Dirvish, not vanilla Dired. There is no
   "Dirvish only on opt-in key" mode in this spec.
4. **`vc-handled-backends` stays `nil`.** [`init-git.el`](lisp/init-git.el)
   intentionally turns the built-in VC framework off (Magit replaces it,
   line 22-23). Dirvish's `vc-state` attribute reads from that framework,
   so it is **omitted** from the default `dirvish-attributes` list — it
   would silently show nothing while still costing a per-file query.
5. **`git-msg` attribute is off by default.** `$HOME` is itself a git repo
   with ~1500 tracked files; in [`init-git.el`](lisp/init-git.el) we already
   disabled `diff-hl-dired-mode` for exactly that reason (line 29-33). The
   `git-msg` attribute calls `git log -1` per visible file — same risk.
   Operator can toggle per-buffer via Dirvish's `a` (`dirvish-setup-menu`).
6. **TTY and GUI both supported.** This config runs Emacs as a daemon with
   `emacsclient -c -nw` (TTY) frames; Dirvish's image previewer falls back
   to text on TTY automatically. No GUI-only code paths are introduced.
7. **No new preview-tool installs in this pass.** The system already has
   `fd-find` (per global [`~/.claude/CLAUDE.md`](.claude/CLAUDE.md)). The
   optional preview helpers (`poppler-utils`, `ffmpegthumbnailer`,
   `mediainfo`, `libvips-tools`, `imagemagick`) are listed in [Open
   Questions](#open-questions); they are NOT installed as part of this
   change.
8. **Network-free boot survives.** [`init.el`](init.el) deliberately skips
   `package-refresh-contents` at startup. First-time install requires
   `M-x my/package-refresh` once, then a restart — same drill as every
   other package added to this config.

→ Correct any of these now or the implementation will assume them.

## Tech Stack

- Emacs 30.1 with `use-package` (built-in since Emacs 29) — unchanged.
- New MELPA package: `dirvish` (current release line, no version pin).
- Reuses existing packages: `nerd-icons` (declared `:defer t` in
  [`init-appearance.el`](lisp/init-appearance.el)), Emacs built-in `dired`.
- No new system binaries required for the minimum-viable install. Optional
  preview binaries deferred (see Open Questions).

## Commands

After the change:

| step | command | notes |
|---|---|---|
| install package (one-shot, online) | `M-x my/package-refresh` then restart | required because boot is network-free; `use-package` then auto-installs `dirvish` from MELPA on the next launch |
| batch sanity | `emacs --batch -l init.el --eval '(message "ok")'` | exits 0, prints `ok`, no `Symbol's function definition is void`, no `Cannot open load file` |
| daemon smoke | `emacs --daemon` then `emacsclient -c -nw` | mode-line + appearance load as before; opening a dir uses Dirvish |
| feature audit | `emacsclient -e '(featurep (quote init-dirvish))'` | must return `t` |
| Dired override check | `emacsclient -e 'dirvish-override-dired-mode'` | must return `t` |
| open via dispatcher | `C-c f` inside any frame | opens `M-x dirvish` on `default-directory` |
| open side panel | `C-c s` | opens `dirvish-side` follow panel |
| transient cheat-sheet | inside a Dirvish buffer: `?` | `dirvish-dispatch` transient |
| $HOME perf smoke | `M-x dirvish RET ~ RET` | must render in < 1 s; **not** trigger the 1500-file `git status` spike that motivated the `diff-hl-dired-mode` disable |

## Project Structure

```
init.el                       → loader; the `mapc #'require '(...)` list
                                gains `init-dirvish` between `init-appearance`
                                and `init-org` (one-line edit + commentary
                                update)
lisp/init-dirvish.el          → NEW. Sole `use-package dirvish` block plus a
                                tiny `use-package dired :ensure nil` config
                                that sets `dired-listing-switches` and
                                re-enables `dired-find-alternate-file`
                                (per Dirvish's upstream "Getting Started")
lisp/init-appearance.el       → unchanged (nerd-icons already declared here)
lisp/init-git.el              → unchanged (vc-handled-backends stays nil;
                                this spec explicitly does NOT touch it)
FEATURES.md                   → follow-up commit, not bundled with this change:
                                add a §"File manager (Dirvish)" entry with
                                the key table from this spec
SPEC.md                       → this file
```

The `init.el` require list after the change:

```elisp
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
        init-dirvish      ; ← new, here
        init-org
        init-obsidian
        init-org-roam
        init-ai))
```

Placement rationale: Dirvish reads `dirvish-attributes` containing
`nerd-icons` — that symbol must be `require`-able when Dirvish first opens.
`nerd-icons` is `:defer t` in `init-appearance`, so use-package autoloads
take care of it whenever Dirvish first runs — but loading `init-dirvish`
*after* `init-appearance` keeps the conceptual ordering ("icons exist before
the thing that draws icons") obvious to anyone reading the loader.

## Code Style

The new file follows the same canonical header used by every other module
(see [`lisp/init-corfu.el`](lisp/init-corfu.el),
[`lisp/init-obsidian.el`](lisp/init-obsidian.el)):

```elisp
;;; init-dirvish.el --- Dirvish: polished Dired with icons + preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish (https://github.com/alexluigit/dirvish) layers icons, preview,
;; history, a side panel, and a `?'-driven transient cheat-sheet on top of
;; Dired.  `dirvish-override-dired-mode' makes every `C-x d' / `C-x C-f'
;; into-a-directory route through Dirvish without a separate keybind.
;;
;; Two deliberate omissions vs. upstream's sample config:
;;   * `vc-state' is NOT in `dirvish-attributes' -- init-git.el sets
;;     `vc-handled-backends' to nil (Magit replaces vc), so vc-state would
;;     silently no-op while still costing a per-line query.
;;   * `git-msg' is NOT in `dirvish-attributes' -- $HOME is itself a git
;;     repo with ~1500 tracked files; `git-msg' calls `git log -1' per
;;     visible row, same hazard that motivated disabling
;;     `diff-hl-dired-mode' in init-git.el.  Toggle per-buffer with `a'
;;     (`dirvish-setup-menu') when you want it.

;;; Code:

(use-package dired
  :ensure nil
  :config
  (setq dired-listing-switches
        "-l --almost-all --human-readable --group-directories-first --no-group")
  ;; Let `a' (dired-find-alternate-file) reuse the current Dired buffer
  ;; instead of leaving a trail of stale Dired buffers behind every descent.
  ;; Also lets `dirvish-side' auto-close its window when opening a file.
  (put 'dired-find-alternate-file 'disabled nil))

(use-package dirvish
  :ensure t
  :init
  (dirvish-override-dired-mode)
  :custom
  (dirvish-quick-access-entries
   ;; Keep this list short and curated -- it's a personal launcher, not a
   ;; fileystem dump.  Order = quick-key order in `o' (dirvish-quick-access).
   '(("h" "~/"                            "Home")
     ("e" "~/.emacs.d/"                   "Emacs config")
     ("c" "~/.claude/"                    "Claude config")
     ("o" "~/code/obsidian/"              "Obsidian vault")
     ("r" "~/code/org-roam/"              "org-roam vault")
     ("t" "~/fenrir-tools/"               "fenrir-tools")))
  :config
  (setq dirvish-mode-line-format
        '(:left (sort symlink) :right (omit yank index)))
  ;; Attribute order MATTERS (upstream warning).  See header comment for
  ;; why vc-state and git-msg are omitted from the default set.
  (setq dirvish-attributes
        '(subtree-state nerd-icons collapse file-time file-size))
  (setq dirvish-side-attributes
        '(nerd-icons collapse file-size))
  ;; Hand off >20k-entry dirs to `fd' so the UI doesn't block.  `fdfind' is
  ;; the Debian binary name; Dirvish auto-detects via `dirvish-fd-program'.
  (setq dirvish-large-directory-threshold 20000)
  (setq dirvish-fd-program (or (executable-find "fdfind")
                               (executable-find "fd")))
  :bind
  (("C-c f" . dirvish)
   ("C-c s" . dirvish-side)
   :map dirvish-mode-map
   (";"   . dired-up-directory)
   ("?"   . dirvish-dispatch)
   ("a"   . dirvish-setup-menu)
   ("f"   . dirvish-file-info-menu)
   ("o"   . dirvish-quick-access)
   ("s"   . dirvish-quicksort)
   ("r"   . dirvish-history-jump)
   ("l"   . dirvish-ls-switches-menu)
   ("v"   . dirvish-vc-menu)
   ("y"   . dirvish-yank-menu)
   ("N"   . dirvish-narrow)
   ("TAB" . dirvish-subtree-toggle)
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)))

(provide 'init-dirvish)
;;; init-dirvish.el ends here
```

## Testing Strategy

No test framework. Verification is smoke + behaviour spot-checks, matching
the discipline established by the prior init-split SPEC:

- **Batch load**: `emacs --batch -l init.el --eval '(message "ok")'` exits 0,
  prints `ok`, no `Symbol's function definition is void`, no `Cannot open
  load file`. Run before and after to confirm parity.
- **Feature presence**: `(featurep 'init-dirvish)` is `t` after a clean
  daemon start. `(featurep 'dirvish)` is `nil` until Dirvish is first
  invoked (autoload), then becomes `t` after `C-c f`.
- **`dirvish-override-dired-mode` is on**: in the running daemon,
  `dirvish-override-dired-mode` evaluates to `t`.
- **Behaviour spot-checks**:
  - `C-c f` in a code buffer opens Dirvish on `default-directory` with
    `nerd-icons` glyphs visible (TTY frame may show fallback glyphs if the
    nerd font isn't deployed in the terminal — that's the terminal's
    problem, not Dirvish's).
  - `C-x d` (vanilla Dired binding) opens **Dirvish**, not classic Dired —
    proves the `dirvish-override-dired-mode` global hook is live.
  - `?` inside the Dirvish buffer opens the transient cheat-sheet
    (`dirvish-dispatch`).
  - `TAB` on a directory line expands a subtree (`dirvish-subtree-toggle`).
  - `o` opens the quick-access menu containing the six personal entries
    from `dirvish-quick-access-entries`.
  - `C-c s` opens `dirvish-side` as a side window; `q` closes it.
- **$HOME hazard regression**: `M-x dirvish RET ~ RET` renders in under one
  second on this machine. If it stalls, suspect `git-msg` / `vc-state`
  silently re-entering the attribute list — verify with
  `(symbol-value 'dirvish-attributes)`.
- **Large-dir async path**: `M-x dirvish` on a directory with >20 000
  entries (e.g. `~/.emacs.d/var/` after long use, or an apt cache mirror)
  must not block the Emacs UI — Dirvish should spawn `fdfind` and stream.
- **Diff hygiene**:
  - `git diff init.el` shows two changes: the require list gains
    `init-dirvish` (one line) and the loader commentary block grows by one
    description line — nothing else.
  - `git status` shows one new file: `lisp/init-dirvish.el`.
  - No edits to [`init-appearance.el`](lisp/init-appearance.el),
    [`init-editing.el`](lisp/init-editing.el),
    [`init-git.el`](lisp/init-git.el),
    [`init-defaults.el`](lisp/init-defaults.el),
    [`custom.el`](custom.el), or
    [`early-init.el`](early-init.el).

## Boundaries

- **Always**:
  - Keep the new module's content additive — no edits to existing module
    files except the one-line require list addition in [`init.el`](init.el)
    and its commentary update.
  - End the new file with `(provide 'init-dirvish)` and the canonical
    `;;; init-dirvish.el ends here` trailer.
  - Put the file's lexical-binding cookie on line 1, matching every other
    module.
  - Use `executable-find` for `fdfind` / `fd` so the config still loads on
    a non-Debian box (Arch, macOS) where the binary is just `fd`.
- **Ask first**:
  - Adding any of the optional preview binaries to the host (`apt install
    poppler-utils ffmpegthumbnailer mediainfo libvips-tools imagemagick`) —
    these expand Dirvish's preview range to PDF / video / audio / vector
    images, but are out of scope for this initial install.
  - Enabling `dirvish-peek-mode` globally (preview files in the
    `find-file` minibuffer) — interaction with vertico-posframe / consult
    preview deserves its own dry-run.
  - Enabling `dirvish-side-follow-mode` (treemacs-like auto-track) by
    default — current spec leaves it off, opt-in via `M-x`.
  - Re-introducing `vc-state` / `git-msg` to `dirvish-attributes` — only
    after measuring the $HOME-open latency cost and deciding it's
    acceptable (or scoping the attribute to non-$HOME dirs).
  - Pinning the Dirvish MELPA version via `package-vc-selected-packages`
    or a `:vc` form — current install tracks MELPA's latest release.
- **Never**:
  - Re-enable `vc-handled-backends` to make `vc-state` work — that undoes
    a deliberate `init-git.el` decision (line 22-23) and would also affect
    every non-Dirvish file open.
  - Re-enable `diff-hl-dired-mode` — same $HOME hazard documented in
    `init-git.el` (line 29-33).
  - Add Dirvish config to `init-appearance.el`, `init-editing.el`, or any
    other existing module — keep the per-package granularity intact.
  - Commit the byte-compiled `lisp/init-dirvish.elc` — `.gitignore` already
    excludes `lisp/*.elc`; verify before commit.
  - Inline `(load ".../init-dirvish.el")` — use `(require 'init-dirvish)`
    so duplicate loads are no-ops.

## Success Criteria

1. `emacs --batch -l init.el --eval '(message "ok")'` exits 0 with `ok` on
   stdout, no errors / warnings.
2. `(featurep 'init-dirvish)` is `t` after a clean daemon start.
3. `dirvish-override-dired-mode` is `t`; `C-x d` opens a Dirvish buffer.
4. `C-c f` opens Dirvish; `C-c s` opens the side panel; `?` opens the
   transient.
5. Opening `~` (this user's $HOME, a 1500-tracked-file git repo) renders
   in < 1 s and shows no per-row `git` invocation in
   `dirvish-attributes`-emitted code paths.
6. `wc -l lisp/init-dirvish.el` is in the 40–70 line range — matches the
   density of the other small-package modules
   ([`init-corfu.el`](lisp/init-corfu.el) is the size benchmark).
7. `git diff --stat` shows one new file
   (`lisp/init-dirvish.el`) and a tiny edit to [`init.el`](init.el).
   Nothing else.
8. Restart-cycle proof: `emacs --daemon` → `emacsclient -c -nw` → close →
   re-open is uneventful; `*Messages*` shows no new warnings against the
   pre-Dirvish baseline.

## Open Questions

Non-blocking. Decide after the minimal install is in:

- **Optional preview binaries**: install
  `poppler-utils ffmpegthumbnailer mediainfo libvips-tools imagemagick`
  to unlock PDF / video / audio / vector previews? Defer until the bare
  Dirvish is in and we see whether the operator misses these.
- **`dirvish-peek-mode`**: enable globally so `find-file` candidates get
  inline previews? Defer — overlaps with `consult-preview`-style flows in
  [`init-completion.el`](lisp/init-completion.el) and needs a side-by-side
  trial.
- **`dirvish-side-follow-mode`**: turn on by default so the side panel
  tracks the current buffer? Defer — opt-in via `M-x` is fine until daily
  use says otherwise.
- **`FEATURES.md` section**: add a new "File manager (Dirvish)" entry with
  the key table from this spec. Do it as a follow-up commit, not bundled,
  to keep the implementation diff reviewable.
- **`pdf-tools` swap**: if PDF preview is ever wanted, substitute
  `pdf-tools` for the default `pdftoppm` dispatcher
  (`cl-substitute 'pdf-tools 'pdf dirvish-preview-dispatchers`). Out of
  scope here.
