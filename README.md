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
emacs                                               # first launch: use-package installs missing packages
```

The pre-commit hook ([`.githooks/pre-commit`](.githooks/pre-commit)) runs `gitleaks`
on staged content; it no-ops if `gitleaks` isn't on `PATH`.

Gotchas on first launch:

- `init.el` does **not** refresh the package archive at startup (network-free boot).
  If a `use-package` form names a package that isn't in the local archive cache yet,
  the install fails. Run `M-x my/package-refresh` first, then restart.
- Packages with `:ensure nil` are built-ins — they won't be pulled from MELPA.
- `eca/`, `vterm`, and tree-sitter grammars may need a compiler / external deps on
  the new machine.

## Conventions

- `use-package-always-ensure` is `t` — plain `(use-package foo ...)` installs `foo`
  from MELPA on first run. Built-ins must say `:ensure nil`.
- Timestamped backups (`init.el.bak-YYYYMMDD-HHMM`) are left by ad-hoc edits and are
  gitignored — clean them up periodically.
