# Repository Guidelines

## Project Structure & Module Organization

This is a personal Emacs 30.1 configuration supporting TTY and GUI frames on one daemon. `early-init.el` handles startup tuning; `init.el` bootstraps packages and loads modules. Area configuration lives in `lisp/init-<area>.el`; language configuration belongs in `lisp/languages/init-<language>.el`. Preserve load order, with `init-keys.el` last as a routing layer.

`shell/` contains dependency installers. `cpp/` holds native JUnit support; `rust/` holds grammar builders and question-queue support. `templates` contains TempEl snippets. Consult `_doc/` and `CLAUDE.md` for architecture and pitfalls; keep `FEATURES.md` synchronized with binding and workflow changes.

## Build, Test, and Development Commands

Run from the repository root:

- `bash shell/install.sh`: install system and user dependencies; the system phase uses sudo.
- `emacs`: start locally. If package metadata is missing, run `M-x my/package-refresh`, then restart.
- `M-x load-file RET init.el`: reload configuration in Emacs; use the module path for focused edits.
- `bash .githooks/pre-commit`: scan staged secrets when gitleaks is installed, check Lisp parentheses in `lisp/`, `lisp/languages/`, `shell/*.el` and the three root files, and smoke-test working-tree startup when Emacs is available.
- `emacs -Q --batch -l shell/test-magit-status-overview.el -f ert-run-tests-batch-and-exit`: the ERT suite for the Magit status overview. `emacs -Q` loads no user configuration, so the file loads its own dependencies (this repo's `elpa/`, `use-package`, `magit`, then the real `lisp/init-git.el`) and installs nothing.
- `bash cpp/build.sh`: build Release native modules into `cpp/lib/`.
- `make -C rust/question-queue-core verify`: build, deploy, and load-check the Rust module; `make -C rust verify` covers all native subprojects there.

## Coding Style & Naming Conventions

Use spaces and standard Emacs Lisp indentation (normally two spaces for bodies). Match existing `init-*` filenames, matching `provide` features, and `fenrir/` helper names. Keep package configuration in its owning module. Built-in packages normally use `:ensure nil`; Eglot is a documented exception. Apheleia owns format-on-save. Keep Customize output in `custom.el` and never leave ad-hoc `.elc` check artifacts.

## Testing Guidelines

There is no repository-wide test suite or coverage threshold; a few features carry a local ERT file under `shell/test-*.el`, listed above. Run the pre-commit checks for Lisp changes and any ERT file covering the code you touched, then exercise affected commands in TTY and GUI where relevant; batch startup omits frame-specific behavior, so a green batch run never stands in for interactive verification of rendering, window points, or timing. A local test file must load its own dependencies explicitly, install nothing, and leave no `.elc` or package state behind. Rust unit tests live beside implementation in `src/answer.rs`, using descriptive snake_case names. Run `cargo test --manifest-path rust/question-queue-core/Cargo.toml` for parser changes.

## Commit & Pull Request Guidelines

Follow history's concise `area: action` subjects, such as `keys: ...`, `org: ...`, or `docs: ...`. Keep commits focused. PRs should explain the behavior change, affected modules, and validation; link relevant issues and include screenshots for visual changes. Enable hooks with `git config core.hooksPath .githooks`. Exclude credentials, package caches, runtime state, and generated binaries.
