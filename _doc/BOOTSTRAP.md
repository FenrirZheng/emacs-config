# Bootstrap, packages and build operations

Long-form companion to [CLAUDE.md → Package-install discipline](../CLAUDE.md#package-install-discipline-load-bearing-quirks)
and [CLAUDE.md → Build / test / run](../CLAUDE.md#build--test--run). Everything here has an
obvious trigger — a fresh clone, an install that failed, a grammar that won't load — so it
lives out of line.

## Fresh clone

```bash
git clone <remote> ~/.emacs.d
git -C ~/.emacs.d config core.hooksPath .githooks   # wire pre-commit (local config, not tracked)
~/.emacs.d/shell/install.sh                         # apt + npm/cargo/go/rustup deps
emacs                                               # first launch: use-package installs missing packages
```

[`shell/install.sh`](../shell/install.sh) is a thin orchestrator over two halves:
[`install-root.sh`](../shell/install-root.sh) (apt packages; self-elevates via `sudo`) and
[`install-user.sh`](../shell/install-user.sh) (cargo / go / rustup / npm / terminfo;
refuses to run as root so toolchain caches don't land under `/root/`). Shared helpers live
in [`install-lib.sh`](../shell/install-lib.sh). `install-user.sh` flips npm's global prefix
to `$HOME/.npm-global` so `npm install -g` no longer needs sudo — add
`$HOME/.npm-global/bin` to `PATH` once for the new prefix to be useful.

After the first launch:

1. `M-x nerd-icons-install-fonts` — modeline glyphs.
2. `M-x org-roam-db-sync` — first roam DB build (`~/code/org-roam/`).
3. `M-x my/package-refresh`, then `M-x package-install RET eglot RET`, then restart —
   upgrades Eglot off the bundled 30.1 copy (see [below](#eglot-is-upgraded-off-the-bundled-copy)).
4. *(optional, Java JUnit-at-point)* `sudo apt install libtree-sitter-dev` then
   `~/.emacs.d/cpp/build.sh` (or `M-x junit-runner-build`) — builds `junit-core` into
   `cpp/lib/`. Skippable: [`junit-runner.el`](../lisp/junit-runner.el) degrades to a build
   hint until then.
5. *(optional, question-queue)* `M-x question-queue-build` — builds
   `rust/question-queue-core` into `rust/lib/`.

## Pre-commit hook

[`.githooks/pre-commit`](../.githooks/pre-commit) runs `gitleaks git --staged`.
`core.hooksPath` is local config, so re-run `git config core.hooksPath .githooks` after any
fresh clone. If `gitleaks` isn't on `PATH`, the hook prints a warning and no-ops — install
from the upstream releases. If the hook blocks a commit, fix the underlying secret; do not
reach for `--no-verify`.

## Installing a package

The archive is **never** refreshed at startup (network-free boot). After adding a new
`use-package` block whose package isn't already in `elpa/`, run `M-x my/package-refresh`
then restart Emacs — otherwise the install fails to find the package.

`use-package-always-ensure` is `t`, so plain `(use-package foo …)` auto-installs `foo` from
MELPA. **Built-ins must say `:ensure nil`** (`project`, `flymake`, `ibuffer`, `recentf`,
`savehist`, `saveplace`, `winner`, `which-key`, `org`, `vertico-directory`,
`corfu-popupinfo`, `dired`, …). Forgetting it pulls a redundant MELPA copy that may shadow
the built-in.

GitHub-only packages use `use-package`'s `:vc` keyword (Emacs 30 native
`package-vc-install`; no straight.el / quelpa) — see `eglot-booster` and `combobulate` in
[`init-languages.el`](../lisp/init-languages.el). The pinned URLs are recorded in
[`custom.el`](../custom.el) under `package-vc-selected-packages` so a fresh clone
reproduces the same fetch. Update later with `M-x package-vc-upgrade RET <name> RET`.

`M-x customize` writes to [`custom.el`](../custom.el) (`custom-file` is set in
[`init-defaults.el`](../lisp/init-defaults.el), which also `(load custom-file)`). There is
intentionally **no** `custom-set-variables` block in `init.el` — a duplicate would let
"whichever loads last" silently win.

`no-littering` is loaded eagerly (`:demand t`) in `init.el` **before** the modules require
packages that drop state files. The `.gitignore` whitelists `/var/` and `/etc/` in one line
each, replacing per-file ignores.

## Eglot is upgraded off the bundled copy

Eglot is the deliberate `:ensure t` exception among built-ins: this config runs the GNU
ELPA release, not the copy bundled with Emacs 30.1, because native call / type hierarchy
(`eglot-show-call-hierarchy` / `eglot-show-type-hierarchy`, on `C-c h c` / `C-c h t`) only
exists in Eglot ≥ 1.19 (2025-10).

Two load-bearing quirks:

1. **`:ensure t` alone cannot upgrade a built-in.** use-package's ensure short-circuits on
   `package-installed-p` (always `t` for a bundled package) and never calls
   `package-install`. The repo therefore sets `package-install-upgrade-built-in t` in
   [`init.el`](../init.el) so a manual `M-x package-install RET eglot` actually replaces the
   built-in.
2. **A fresh clone falls back to the bundled Eglot** until you run that one-time install,
   because `elpa/` is gitignored.

Side effect: installing Eglot 1.23 also pulls `flymake` 1.4.5 into `elpa/` as a dependency,
which then shadows the built-in `flymake` even though its `use-package` block still says
`:ensure nil` — benign (the block just configures the newer copy). eglot-booster's
`eglot--connect` / `jsonrpc--json-read` advice was verified to still apply against 1.23.

## Reload / rebuild

- **Reload after editing**: `M-x load-file RET init.el RET`, or restart Emacs. Individual
  modules reload via `M-x load-file RET lisp/init-<area>.el RET` once their
  `(require 'init-<area>)` has run at least once (otherwise `provide` hasn't registered).
- **Stale `.elc` artefacts**: byte-compiled `*.elc` files sit next to their `.el` siblings
  in [`lisp/`](../lisp/) and are gitignored. `load-prefer-newer t` (set in `early-init.el`)
  means a fresh `.el` wins, but if you suspect a stale `.elc` is preferred, delete it:
  `fdfind -e elc -X rm` from the repo root.
- **Native compilation**: `M-x my/native-compile-config` pre-warms `elpa/` + `lisp/`
  asynchronously; it skips files whose `.eln` is current, so re-running is cheap.
- Timestamped backups (`init.el.bak-YYYYMMDD-HHMM`) from ad-hoc edits are gitignored —
  clean them up periodically.

There is no compile or test command: this is plain Elisp.

## Tree-sitter grammars  <a id="tree-sitter-grammars"></a>

Grammars live in [`tree-sitter/`](../tree-sitter/) (gitignored, regenerated by
`treesit-install-language-grammar`). `treesit-extra-load-path` in
[`init-languages.el`](../lisp/init-languages.el) adds that dir so the next startup finds
them.

Emacs 30.1 caps the grammar ABI at 14 (`treesit-library-abi-version` ⇒ 14), and several
upstream grammars have moved to ABI 15 (they load as `version-mismatch: 15`). Two
strategies, and **(b) is preferred whenever an ABI-14 tag exists**:

| strategy | languages | how |
|---|---|---|
| **(a)** exclude + fall back | `css`, `json` | dropped from `treesit-auto-langs`; use built-in `css-mode` / `js-json-mode` |
| **(b)** pin to the newest ABI-14 tag + rebuild | `c` (v0.23.6), `lua` (v0.3.0), `rust` (v0.23.3) | stay in `treesit-auto-langs`; the language module sets the grammar's `abi14-revision` recipe slot, and a standalone Makefile deployer lives under [`rust/treesit-grammar*/`](../rust/) |

`lua` was an (a)-style exclusion until 2026-06-08, when `v0.3.0` was found to be a valid
ABI-14 tag and it moved to (b) (`lua-ts-mode`, with `lua-mode` kept as the no-grammar
fallback).

**Keep each deployer Makefile's `GRAMMAR_TAG` in sync with its module's
`abi14-revision`** — [`init-rust.el`](../lisp/languages/init-rust.el) /
[`init-c-cpp.el`](../lisp/languages/init-c-cpp.el) /
[`init-lua.el`](../lisp/languages/init-lua.el) respectively. The three Makefiles are
near-identical; the build auto-detects whether the grammar ships a `scanner.c` (rust and
lua do, c is parser-only).

## See also

- [CLAUDE.md](../CLAUDE.md) — the rules extracted from this file
- [ARCHITECTURE.md](ARCHITECTURE.md) — what each module holds
- [GOTCHAS.md](GOTCHAS.md) — editing traps
