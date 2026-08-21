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
- `GTAGSLABEL=java-pygments` — the parser routing, and a fenrir-local label in that same
  tracked [`gtags.conf`](../gtags.conf). Upstream's `native-pygments` (built-in parser for
  C/C++/Java/PHP, pygments for the Go/Python/TS the built-in is blind to) is the baseline;
  `java-pygments` is that chain with `.java` lifted to the front and routed to the
  pygments plug-in, every other extension keeping the parser it had. See
  [Why Java is not on the built-in parser](#why-java-is-not-on-the-built-in-parser).

**The label is read on EVERY invocation, not just create.** The DB does *not* record it.
Measured: with a `java-pygments` index in place, running `global --single-update` **or**
`global -u` under `GTAGSLABEL=native-pygments` re-parses the touched file with the
built-in parser and silently drops its fields — no error, no warning, the index just
rots. This is why the label is one daemon-wide `setenv` rather than a per-project
choice: per-project would mean injecting the right label at every update call site,
which is the exact bug class the `setenv` was introduced to bury (below).

Every `make-process` / `process-file` child inherits `process-environment`, so create,
`global -u`, the on-save single-update and every xref query all see the skip list. This
is what buries the old bug class where **one call site forgot the env**: `global -u`
re-traverses the filesystem and re-adds anything not skipped — measured on coinsasia,
2.5 MB → **3.85 GB** from a single bare `global -u`.

## Why Java is not on the built-in parser

gtags' built-in Java parser is lexer-level. Measured on `~/code/camhr/camhr`
(1078 `.java` files, 153 MB), same tree, same sub-second build:

| | built-in (`native-pygments`) | Universal Ctags alone | pygments (`java-pygments`) |
|---|---|---|---|
| distinct definition tags | 4904 | 6729 | 6729 |
| fields (`private JobMapper jobMapper;`) | **none indexed** | indexed | indexed |
| `Constants.of(…)` in an enum constant | a **definition** of `of` | not a definition | not a definition |
| `of` definitions | call sites + real decls, mixed | 28, all real | 28, all real |
| `GRTAGS` | 2.5 MB | 912 KB | 2.7 MB |
| `-r publishJob` / `-s ArrayList` | 8 / 39 | **0 / 0** | 7 / 37 |
| build time | ~1 s | ~1 s | ~2 s |

The middle column is the trap. Universal Ctags fixes definitions and **destroys
references**: ctags has no concept of a reference, so pointing `.java` at it empties
`GRTAGS` and `M-?` returns nothing at all. Java has no language server in this config, so
gtags *is* its `M-?` — that trade is not worth fields.

`java-pygments` gets both because
`/usr/share/global/gtags/script/pygments_parser.py` runs a
`MergingParser(ctags_parser, pygments_parser)`: ctags supplies the definitions (hence a
tag set byte-identical to the middle column — 6729 symbols, verified by diff) and
pygments supplies the token stream the reference index is built from. It therefore needs
**both** `/usr/bin/ctags-universal` (apt `universal-ctags`, hardcoded in that script) and
python3 + `pygments`.

The label is `native-pygments` with one language moved: the `pygments-java` block
declares exactly `langmap=Java\:.java`, chained *ahead* of `builtin-parser`, so `.java` is
claimed before the built-in parser sees it and nothing else moves. Capitalisation is
load-bearing — `builtin-parser` spells its entry `java\:.java` in lower case with no
matching `gtags_parser` line, which is why plain `native-pygments` lands on the built-in
parser even though pygments also declares `Java`.

Not the stock `new-ctags` or `pygments` labels: those apply one parser to *every*
language, and `new-ctags` additionally has no TypeScript entry in this file's langmap, so
it would silently drop `.ts` / `.tsx`.

### Annotations carry their `@`

pygments emits a Java annotation as one token *including* the sigil, so the index key is
`@Autowired`, while Emacs' `find-tag-default` returns the bare `Autowired` (`@` is
punctuation). Left alone, `M-?` on any annotation answers nothing — 623 `@Autowired`
occurrences in one measured project, zero hits. [`init-tags.el`](../lisp/init-tags.el)
closes this with an `:around` method on the `:gtagsroot` backend's
`xref-backend-references` that retries `@SYMBOL` when the bare form misses, in Java
buffers only. The built-in parser stored annotations under the bare name, so this is a
cost of the parser switch, not a pre-existing gap.

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

Both `C-c g g` and `C-c g d` default their directory to the **covering index root**
(`global --print-dbpath`, which walks *up* exactly like queries resolve), falling back
to the project.el root. The two can differ: a sub-crate/sub-module with its own root
marker (`crates/server/Cargo.toml`) makes project.el resolve to the *subdir* while the
index lives at the repo top — defaulting to the sub-project would make a rebuild
create precisely the nested shadowing index described above.

### Forbidden roots

`fenrir/gtags-build` refuses `$HOME` (the dotfiles repo), `/`, `/tmp/` and other system
roots (`fenrir/gtags-forbidden-roots`) — `project-try-vc` can degenerate to those and a
gtags walk there is runaway.

## CLI alignment (the `tags-symbol-lookup` skill)

The Claude skill's `gtags.sh` historically wrote the DB into a `./tags/` subdirectory;
Emacs-side resolution (`global --print-dbpath` from the file's directory) expects it at
the **project root**. An index at root serves both worlds — see the plan's D5 and the
skill-side note.

**Label drift is now a live hazard.** `gtags.sh` still exports
`GTAGSLABEL=native-pygments`, while Emacs exports `java-pygments`. Since the label is read
per invocation and never recorded in the DB (above), a shared index alternates parsers:
a `gtags.sh` build indexes Java without fields, and the next Emacs on-save update
re-parses only the touched file *with* them. Nothing errors; the index is just
inconsistent. Point `gtags.sh` at `java-pygments` too, or keep the two indexes separate.

## The second gtags universe: the org-ID index

Everything above is the **code** index. There is a second, fully disjoint GNU Global
deployment on this machine — the **org-ID index**: any directory carrying `.org-index/`
(currently `~/code/org-roam` and `~/code/pg`) holds a db mapping `:ID:` lines
(definitions) and `[[id:` links (references) in `.org` files. When gtags behaves oddly,
first establish which universe you're in:

| | code index (this doc) | org-ID index |
|---|---|---|
| conf | [`~/.emacs.d/gtags.conf`](../gtags.conf) | `~/.claude/org-index/gtags.conf` |
| label | `java-pygments` | `org-roam` |
| env delivery | `setenv`, **daemon-wide** | let-bound `process-environment`, **per-process** |
| db location | project root | `<root>/.org-index/` |
| owners | `gtags-mode` + `fenrir/gtags-build` ([`init-tags.el`](../lisp/init-tags.el)) | `fenrir/org-index-rebuild` + save hook ([`init-org.el`](../lisp/init-org.el)), the `~/.claude/bin/org-index` CLI, and Claude Code's PostToolUse hook |

The two confs are deliberately **never merged** (each file's header says so): merging
would let the OrgRoam ctags language leak into code runs and let upstream conf refreshes
clobber the org label. Because the org quartet (`GTAGSCONF`/`GTAGSLABEL`/`GTAGSROOT`/
`GTAGSDBPATH`) is injected per-process, the daemon-wide `java-pygments` pair stays
untouched — `(getenv "GTAGSLABEL")` is still `java-pygments` after an org rebuild, which
is exactly the CLAUDE.md invariant.

Writers serialize via a non-blocking `flock(1)` on `<root>/.org-index/.lock` — the CLI,
the Claude hook, and the Emacs side all take the same lock and silently skip when it's
held (a concurrent `global -u` re-reads the files, so it covers the edit anyway; Emacs
distinguishes the skip from real failure via `flock -E 200`).

## See also

- [CLAUDE.md](../CLAUDE.md) — the extracted rules
- [JAVA.md](JAVA.md) — the Java side, where `M-?` falling back to gtags is a symptom
- [FEATURES.md](../FEATURES.md) — the `C-c g` key table
