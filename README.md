# .emacs.d

Personal Emacs 30.1 configuration. See [`init.el`](init.el) for the section-by-section
layout; [`custom.el`](custom.el) holds the `M-x customize` block. For a key-by-key tour of
what's actually configured — completion UI, project search, Magit, LSP, motion tools — see
the [features & cheat sheet](FEATURES.md).

## What's tracked

Only hand-authored config: [`init.el`](init.el), [`custom.el`](custom.el), this README,
and [`.gitignore`](.gitignore). Everything reproducible or stateful is ignored —
`elpa/` (MELPA downloads), `eln-cache/` (native-comp output), `auto-save-list/`,
`transient/`, `tramp`, `history`, and the vendored `eca/` binary.

## Fresh-clone bootstrap

```bash
git clone <remote> ~/.emacs.d
git -C ~/.emacs.d config core.hooksPath .githooks   # wire pre-commit (local config, not tracked)
~/.emacs.d/install.sh                               # apt/npm/cargo/go/rustup deps (see below)
emacs                                               # first launch: use-package installs missing packages
```

The [bootstrap script](install.sh) is idempotent — it installs system packages
that the config references (jinx → enchant-2, vterm → cmake + libvterm-dev,
magit-delta → git-delta, etc.) plus the npm / cargo / go / rustup binaries used
by `eglot`, `apheleia`, and `eglot-booster`. Re-run safely after pulling new
`init.el` deps. Toolchains that aren't on `PATH` (cargo / go / rustup) are
skipped with a warning rather than aborting the run.

Internally, [`install.sh`](install.sh) is a thin orchestrator calling two
halves: [`install-root.sh`](install-root.sh) (apt packages — self-elevates
via `sudo` if not already root) and [`install-user.sh`](install-user.sh)
(cargo / go / rustup / npm — refuses to run as root so user toolchain
caches don't land under `/root/`). Shared helpers live in
[`install-lib.sh`](install-lib.sh). `install-user.sh` also flips npm's
global prefix to `$HOME/.npm-global` so `npm install -g` no longer needs
`sudo` — add `$HOME/.npm-global/bin` to your shell `PATH` once for the new
prefix to be useful. See [`SPEC.md`](SPEC.md) for the privilege-boundary
rationale.

The pre-commit hook ([`.githooks/pre-commit`](.githooks/pre-commit)) runs `gitleaks`
on staged content; it no-ops if `gitleaks` isn't on `PATH`.

Gotchas on first launch:

- `init.el` does **not** refresh the package archive at startup (network-free boot).
  If a `use-package` form names a package that isn't in the local archive cache yet,
  the install fails. Run `M-x my/package-refresh` first, then restart.
- Packages with `:ensure nil` are built-ins — they won't be pulled from MELPA.
- `vterm` and jinx compile their C modules on first load (~2s each); install.sh
  ensures `cmake` / `libvterm-dev` / `libenchant-2-dev` are present.
- Tree-sitter css/json/lua grammars are ABI 15 and unusable on Emacs 30 (ABI 14);
  `init.el:873-895` routes around this.

## Conventions

- `use-package-always-ensure` is `t` — plain `(use-package foo ...)` installs `foo`
  from MELPA on first run. Built-ins must say `:ensure nil`.
- Timestamped backups (`init.el.bak-YYYYMMDD-HHMM`) are left by ad-hoc edits and are
  gitignored — clean them up periodically.
