# `_doc/` — index

Long-form documentation for this Emacs config. [`CLAUDE.md`](../CLAUDE.md) holds only the
rules that must fire without being looked up; everything with a knowable trigger lives
here and is read on demand.

| file | answers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | What is in each `init-<area>` module? Why is the load order fixed? How is `init-gui` tiered for the TTY+GUI daemon? What is the `<f5>` hub / keyfreq tier policy? What are `cpp/` and `rust/` for? |
| [BOOTSTRAP.md](BOOTSTRAP.md) | How do I set up a fresh clone? How do I install / upgrade a package here? Why is Eglot special? Why won't this tree-sitter grammar load? |
| [GOTCHAS.md](GOTCHAS.md) | Why is this odd-looking line load-bearing? (project.el at `$HOME`, Magit, Corfu-vs-Vertico, eglot-booster advice, Eglot key traps, dape, OSC 52) |
| [TAGS.md](TAGS.md) | Why does `M-.` land in gtags instead of the LSP? Why did the GTAGS index balloon / go stale? |
| [GO.md](GO.md) | Go workflow — go-ts-mode + Eglot + gopls + Vertico-driven symbol search |
| [JAVA.md](JAVA.md) | Java workflow — java-ts-mode + gtags, **no language server**: why jdtls went, what that costs, index rooting |
| [SNIPPETS.md](SNIPPETS.md) | Templates — TempEl + YASnippet: triggers, catalog per mode, writing your own |

Not in this directory:

- [FEATURES.md](../FEATURES.md) — the "what keys do I press" cheat sheet.
- [`tasks/`](../tasks/) — plans and strategy documents for work in progress, e.g.
  [keybinding-strategy.md](../tasks/keybinding-strategy.md),
  [back-navigation-strategy.md](../tasks/back-navigation-strategy.md).
- [`cpp/README.md`](../cpp/README.md), [`rust/README.md`](../rust/README.md) — the native
  module workspaces, with a README per module.

Future per-language guides land here.
