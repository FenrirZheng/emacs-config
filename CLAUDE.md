# CLAUDE.md

Personal Emacs 30.1 config, TTY-first (daemon + `emacsclient -nw` inside tmux) with a GUI
frame served by the **same** daemon. Tracked: hand-authored Elisp ([`init.el`](init.el),
[`early-init.el`](early-init.el), [`custom.el`](custom.el), [`lisp/`](lisp/)), bootstrap
scripts ([`shell/`](shell/)), the GNU Global tag config ([`gtags.conf`](gtags.conf)), the
[pre-commit hook](.githooks/pre-commit), the native workspaces ([`cpp/`](cpp/),
[`rust/`](rust/)) and docs. Everything reproducible or stateful is gitignored — `elpa/`,
`eln-cache/`, the no-littering `var/` + `etc/`, the vendored `eca/` binary, `tree-sitter/`
grammars, and `*.elc`.

This file holds **only rules whose moment of need is unpredictable**. Anything with a
knowable trigger lives in [`_doc/`](_doc/README.md) and is read on demand.

## Where to look

| question | file |
|---|---|
| what keys do I press? | [FEATURES.md](FEATURES.md) — **keep in sync** when bindings or workflow change |
| what's in each module, why this load order, how is `init-gui` tiered, what is the `<f5>` hub | [_doc/ARCHITECTURE.md](_doc/ARCHITECTURE.md) |
| fresh clone, installing/upgrading a package, tree-sitter grammar ABI | [_doc/BOOTSTRAP.md](_doc/BOOTSTRAP.md) |
| why is this odd-looking line load-bearing? | [_doc/GOTCHAS.md](_doc/GOTCHAS.md) |
| `M-.` went to gtags / the GTAGS index is wrong | [_doc/TAGS.md](_doc/TAGS.md) |
| per-language workflow | [_doc/GO.md](_doc/GO.md), [_doc/JAVA.md](_doc/JAVA.md), [_doc/SNIPPETS.md](_doc/SNIPPETS.md) |
| everything above, indexed | [_doc/README.md](_doc/README.md) |
| plans / strategy for in-flight work | [`tasks/`](tasks/) |
| native modules | [`cpp/README.md`](cpp/README.md), [`rust/README.md`](rust/README.md) |

## Architecture rules

[`init.el`](init.el) is a thin loader: package bootstrap, `load-path`, then `mapc
#'require` over a fixed module list. Module inventory: [_doc/ARCHITECTURE.md](_doc/ARCHITECTURE.md).

- **The module load order in [`init.el`](init.el) is load-bearing** — cross-module
  `use-package :after` edges assume earlier modules already declared their packages. Don't
  reshuffle without verifying those edges.
- **[`lisp/init-languages.el`](lisp/init-languages.el) is language-agnostic infra only** and
  must load before [`lisp/languages/`](lisp/languages/); each per-language module hangs its
  `eglot-ensure` hook and `eglot-workspace-configuration` entry off it. Configure language X
  in `lisp/languages/init-X.el`, never in the core.
- **[`lisp/init-keys.el`](lisp/init-keys.el) is required LAST and adds no features** — it is
  a routing layer over commands defined elsewhere. Configure a command in its owning module;
  only *route* it here. It must never replace an existing `C-c` chord, only duplicate it.
- **Commands named in a `<f5>` hub transient must be autoloaded or wrapped** — check
  `<pkg>-autoloads.el` first, or a fresh session gets `void-function`.
- **Before "adding" a repeat map, check `(get COMMAND 'repeat-map)`** — Emacs 30.1 already
  ships and activates seven of them.
- **Never reduce `init-gui.el`'s auto-enable guard to `(display-graphic-p)`.** The
  no-real-TTY-frame condition (`fenrir/gui--real-tty-frame-p`) is what keeps a coexisting
  TTY frame working; the naive version was tried and reverted. Don't extend the automatic
  path beyond the two posframe modes.
  ([why](_doc/ARCHITECTURE.md#gui-tiering))
- **Section numbers in module headers are history**, not a TOC — read module names.

## Startup discipline (`early-init.el`)

[`early-init.el`](early-init.el) runs BEFORE the package system and the first frame, and
owns: GC tuning (`gc-cons-threshold` raised for startup, dropped to a 16 MB floor on
`emacs-startup-hook`, then adapted by `gcmh-mode`), `file-name-handler-alist` suspension
during init, frame chrome via `default-frame-alist` (bars off **before** the first frame
paints — `menu-bar-mode -1` in `init.el` is too late and flashes), and
`package-enable-at-startup nil` so the implicit pre-init `package-activate-all` doesn't
duplicate `init.el`'s explicit `(package-initialize)`.

**Don't move any of those into `init.el`** — by the time it runs, the cost has been paid.

## Package-install discipline (load-bearing quirks)

Operational how-to (fresh clone, the one-time Eglot upgrade, grammar ABI pinning):
[_doc/BOOTSTRAP.md](_doc/BOOTSTRAP.md).

- **The archive is NEVER refreshed at startup** (network-free boot). After adding a
  `use-package` block for a package not already in `elpa/`, run `M-x my/package-refresh`
  then restart, or the install fails to find it.
- **`use-package-always-ensure` is `t`, so built-ins must say `:ensure nil`** — otherwise
  MELPA pulls a redundant copy that may shadow the built-in. **`eglot` is the deliberate
  exception** (`:ensure t`, upgraded off the bundled 30.1 copy for call/type hierarchy);
  `:ensure t` alone can't upgrade a built-in, which is why `package-install-upgrade-built-in
  t` is set in [`init.el`](init.el) and a fresh clone needs one manual `package-install`.
- **GitHub-only packages use `:vc`** (Emacs 30 native `package-vc-install`) — no straight.el
  / quelpa. Pinned URLs live in [`custom.el`](custom.el)'s `package-vc-selected-packages`.
- **`M-x customize` writes to [`custom.el`](custom.el)** — never add a `custom-set-variables`
  block to `init.el`; a duplicate lets "whichever loads last" silently win.
- **`no-littering` loads eagerly (`:demand t`) before any state-dropping package.** Don't
  hand-set a package's state path (`keyfreq-file`, …) — no-littering already redirects it.

## Build / test / run

Plain Elisp — there is no compile or test command. Reload with `M-x load-file RET init.el`,
or per module once its `require` has run at least once. Details, native compilation and the
tree-sitter grammar ABI table: [_doc/BOOTSTRAP.md](_doc/BOOTSTRAP.md).

- **Never leave a `.elc` behind from an ad-hoc `byte-compile-file` syntax check.** A module
  compiled in a bare `emacs -Q --batch` has none of its runtime deps loaded, so macros that
  need them expand WRONG rather than erroring — `(setf (treesit-auto-recipe-abi14-revision
  r) …)` in [`init-rust.el`](lisp/languages/init-rust.el) compiled to a call to the
  non-existent function `(setf treesit-auto-recipe-abi14-revision)`, and because
  `load-prefer-newer` then preferred that fresh `.elc`, the daemon died at startup with
  `Symbol's function definition is void`. Delete the `.elc` in the same breath as creating it.
- **Deleting stale `.elc` needs `--no-ignore`**: `fdfind --no-ignore -e elc --exclude elpa
  --exclude eln-cache . -X rm`. Plain `fdfind -e elc -X rm` matches **nothing** — fd honours
  [`.gitignore`](.gitignore), which ignores `*.elc`, so the cleanup silently no-ops. The
  `--exclude elpa` matters too: those 644 `.elc` are package-installed and must stay.

Native modules are built out-of-band and their output is gitignored: `cpp/build.sh` (or
`M-x junit-runner-build`) → `cpp/lib/`; `make -C rust/<subproject>` (or `M-x
question-queue-build`) → `rust/lib/`. Both front-ends degrade to a build hint until then —
keep that behaviour when adding a module.

## Pre-commit hook

[`.githooks/pre-commit`](.githooks/pre-commit) runs `gitleaks git --staged`.
`core.hooksPath` is local config — **re-run `git config core.hooksPath .githooks` after any
fresh clone.** If the hook blocks a commit, fix the secret; do not reach for `--no-verify`.

## Editing traps — rules that bite

One line each; the evidence is in [_doc/GOTCHAS.md](_doc/GOTCHAS.md) and
[_doc/TAGS.md](_doc/TAGS.md).

- **`$HOME` is itself a git repo.** `project-try-vc` is advised to ignore it; drop an empty
  `.project` to mark a directory. Stale root? `M-x fenrir/project-reset-cache`.
- **Don't re-add the `magit-status-sections-hook` `remove-hook`** that hid untracked files —
  Magit now handles the `$HOME` case itself, and the hook broke every normal repo.
- **Don't enable `global-corfu-mode` casually** — Vertico drives in-buffer completion via
  `completion-in-region-function` = `consult-completion-in-region`; Corfu would silently
  override it buffer-locally.
- **`C-x b` is `ibuffer`**; the consult switcher is `C-x B` (tmux's `C-b` prefix rules out
  `C-x C-b` in a TTY frame).
- **Don't widen `gtags-mode-features` beyond `(xref hooks)`** ([`init-tags.el`](lisp/init-tags.el)) —
  `project` fights the tuned project.el setup, `completion` pollutes the curated
  Corfu/Cape capfs, `imenu` replaces the better tree-sitter/LSP imenu.
- **Don't unset the daemon-wide `GTAGSCONF`/`GTAGSLABEL` `setenv`** ([`init-tags.el`](lisp/init-tags.el))
  or revert to per-call env injection — `global -u` (and the on-save single-update)
  re-traverses the filesystem and re-bloats without the [`gtags.conf`](gtags.conf) skip
  list (measured: 2.5 MB → 3.85 GB). `C-c g d` diagnoses shadowing sub-indexes.
- **Never put `eglot-format` on `before-save-hook`** — apheleia owns format-on-save;
  doubling reintroduces the save-time cursor jump. `C-c f` stays manual.
- **Eglot refactor keys stay off the `C-c o` prefix** (combobulate owns it), and
  `eglot-semantic-tokens-mode` stays a per-buffer toggle, never a global hook.
- **`eglot-booster` advises `eglot--connect` / `jsonrpc--json-read`** — an Emacs or Eglot
  upgrade can break it; `M-x eglot-booster-mode` toggles it off at runtime.
- **Java deliberately runs with NO language server** — [`init-java.el`](lisp/languages/init-java.el)
  attaches no `eglot-ensure` and registers no `eglot-server-programs` entry; jdtls was
  removed for its startup stall and 3 GB heap. `M-.` is gtags (name-level, no types), and
  `.java` is parsed by the pygments plug-in via the `java-pygments` label. Don't "restore" the
  missing hook. ([why + what it costs](_doc/JAVA.md#there-is-no-language-server))
- **Java debugging is unsupported** (dape has no Java adapter) — use IntelliJ/VSCode; don't
  reintroduce `dap-mode`, whose fringe-bitmap breakpoints are invisible on TTY.
- **`push-mark` carries a global `:after` advice** — the merged jump history (`<f6>` /
  `<f7>`) in [`lisp/fenrir-back-forward.el`](lisp/fenrir-back-forward.el), which
  [`init-keys.el`](lisp/init-keys.el) merely requires and binds. Anything that pushes a mark feeds it; turn it off
  with `fenrir/back-forward-enable` / `M-x fenrir/back-forward-mode`, not by hand-removing
  the advice.
- **Don't override `interprogram-cut-function`** anywhere else — [`init-defaults.el`](lisp/init-defaults.el)
  owns it for the OSC 52 clipboard bridge.
