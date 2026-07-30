# GNU Global (gtags) — create / update / xref via gtags-mode

Long-form companion to the gtags rules in
[CLAUDE.md → Editing traps](../CLAUDE.md#editing-traps--rules-that-bite).
The whole Emacs side lives in [`lisp/init-tags.el`](../lisp/init-tags.el); the tracked
skip list lives in [`gtags.conf`](../gtags.conf). Rebuilt 2026-07-30 — design decisions
and the deleted-machinery inventory are in
[the toolchain rebuild plan](../tasks/gtags-xref-toolchain.md).

## The stack

| layer | owner |
|---|---|
| xref backend (`M-.` / `M-?` / `M-,`) | `gtags-mode` (GNU ELPA, maintained) — one **global** minor mode, features trimmed to `(xref hooks)` |
| index create | `fenrir/gtags-build` (`C-c g g`) — async `gtags` with root guard + post-build validation |
| index update, per save | `gtags-mode`'s after-save hook → async `global --single-update <file>` |
| index update, bulk | `gtags-mode-update` (`C-c g u`) — async `global -u`, for branch switches / pulls |
| env (`GTAGSCONF` / `GTAGSLABEL`) | one `setenv` pair in `init-tags.el`, **daemon-wide** |

## Backend ordering — why Eglot always wins

`gtags-mode` adds its backend to the **global** `xref-backend-functions`; Eglot adds
`eglot-xref-backend` **buffer-locally** on attach, and buffer-local hook entries run
before global ones. So per buffer the effective order is:

1. `eglot-xref-backend` — only while a server is attached; wins when present.
2. `gtags-mode--local-plist` — answers only under an indexed root, declines silently
   otherwise (it caches a per-buffer "no index here" verdict; a finished build clears
   those caches via its sentinel).
3. `etags--xref-backend` — the built-in tail. Its "Visit tags table" `read-file-name`
   prompt is replaced by an advice in `init-tags.el` with a one-line
   `No tags here -- C-c g g builds a gtags index` message. `tags-file-name` /
   `tags-table-list` are kept nil so nothing can seed etags with a binary `GTAGS`.

Unlike the previous ggtags frontend, `gtags-mode` never binds `M-.` — there is no keymap
grab to neutralize, so the old "don't delete the `define-key … nil` block" trap is gone.

`gtags-mode-features` is deliberately **not** the full set: `project` would fight the
tuned project.el setup ($HOME-repo ignore), `completion` would add a global tags capf to
the curated Corfu/Cape stack, `imenu` would replace the better tree-sitter/LSP imenu.

## Env — one setenv, every subprocess

`init-tags.el` exports once, daemon-wide:

- `GTAGSCONF` → the tracked [`gtags.conf`](../gtags.conf) (falls back to
  `/etc/gtags/gtags.conf` if missing): a self-contained copy of the system conf whose
  `common:` skip list additionally drops `node_modules/ vendor/ venv/ .venv/ dist/
  build/ target/ …`.
- `GTAGSLABEL=native-pygments`: gtags' built-in parser is C/Java/PHP-only (Go/Python/TS
  blind); pygments covers the rest. Only create consumes the label (gtags records it in
  the DB and updates reuse it), but exporting it always is harmless — only the
  gtags/global family reads these vars.

Every `make-process` / `process-file` child inherits `process-environment`, so create,
`global -u`, the on-save single-update and every xref query all see the skip list. This
is what buries the old bug class where **one call site forgot the env**: `global -u`
re-traverses the filesystem and re-adds anything not skipped — measured on coinsasia,
2.5 MB → **3.85 GB** from a single bare `global -u`.

## Index hygiene

### 0-byte corrupt stubs

A crashed parser helper (missing interpreter, broken PATH) makes `gtags` leave
`GTAGS`/`GRTAGS`/`GPATH` as 0-byte stubs that every later `global -u` rejects with
`GTAGS seems corrupted`. Guards in `fenrir/gtags-build`:

- pre-build: an existing 0-byte `GTAGS` is wiped (gtags refuses to overwrite it);
- post-build: exit status + `GTAGS` size + a `global` probe are checked, and an invalid
  result is **deleted** — never leave a corpse.

### Nested-index shadowing

GNU Global resolves a lookup to the **nearest ancestor `GTAGS`**, so an index in a
subdirectory silently hides the root index for every file beneath it (`backend/GTAGS`
hid `coinsasia/GTAGS`; xref answered from the stale sub-index). **`C-c g d`**
(`fenrir/gtags-diagnose`) lists every `GTAGS` in the subtree (`[root]` / `[nested]`,
sizes) and offers to delete the shadows.

### Forbidden roots

`fenrir/gtags-build` refuses `$HOME` (the dotfiles repo), `/`, `/tmp/` and other system
roots (`fenrir/gtags-forbidden-roots`) — `project-try-vc` can degenerate to those and a
gtags walk there is runaway.

## CLI alignment (the `tags-symbol-lookup` skill)

The Claude skill's `gtags.sh` builds with the same `GTAGSLABEL=native-pygments` but
historically wrote the DB into a `./tags/` subdirectory; Emacs-side resolution
(`global --print-dbpath` from the file's directory) expects it at the **project root**.
An index at root serves both worlds — see the plan's D5 and the skill-side note.

## See also

- [CLAUDE.md](../CLAUDE.md) — the extracted rules
- [JAVA.md](JAVA.md) — the Java side, where `M-?` falling back to gtags is a symptom
- [FEATURES.md](../FEATURES.md) — the `C-c g` key table
