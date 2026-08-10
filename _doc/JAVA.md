# Java development

How Java editing works in this configuration: what drives it, where it's
configured, and — since this is the one language here deliberately left without
a language server — what you give up and what you use instead. Companion to the
keybinding cheat sheet in [FEATURES.md](../FEATURES.md) and the index mechanics
in [TAGS.md](TAGS.md).

All Java-specific code lives in
[`lisp/languages/init-java.el`](../lisp/languages/init-java.el).

## There is no language server

Java ran on `lsp-mode` + `lsp-java`, then on **Eglot + jdtls** (eclipse.jdt.ls).
Both are gone; jdtls was removed 2026-08-10.

**Why.** jdtls is an Eclipse OSGi application on the JVM. It was launched with
`-Xmx3G` on a 15 GB machine and attached unconditionally from both
`java-mode-hook` and `java-ts-mode-hook`, so merely opening a `.java` file
kicked off a full Maven/Gradle workspace import — a multi-second-to-minutes
stall with the whole editor unresponsive, then a resident 2–3 GB. On disk it
cost another 453 MB (`var/lsp-java/`: a 127 MB server bundle plus 325 MB of
workspace metadata).

**What replaced it.** Nothing, for the semantic layer. Java now gets:

| Capability | Provider |
|---|---|
| Fontification, indentation, imenu, structural motion | `java-ts-mode` (tree-sitter), in-process |
| Cross-file `M-.` / `M-?` / `M-,` | gtags / GNU Global via the xref backend in [`init-tags.el`](../lisp/init-tags.el) |
| Index rooting | `fenrir/project-find-java-build-root` (below) |
| Running tests | JUnit runner on `C-c t …` (tree-sitter + `compile`) |
| Snippets, structural editing | yasnippet, combobulate — never needed a server |

## What you gave up

Be honest with yourself about this list before filing a bug:

- **Type-aware completion.** No member list after `.`; completion is
  buffer/index-text-based (Cape / dabbrev), not semantic.
- **Hover javadoc** and signature help.
- **Live diagnostics.** No red squiggles, no unresolved-symbol warnings. The
  compiler is the feedback loop — `C-c t t` or a terminal `mvn`.
- **Refactors.** No rename, no extract-method. `M-x project-query-replace-regexp`
  is the blunt substitute; it is textual and does not know scope.
- **Find implementations / call hierarchy / type hierarchy.**
- **Navigation into JDK or third-party jar sources.** The `jdt://` URI handler
  that served this is gone. `M-.` on `ArrayList` finds nothing; the index
  contains project source only.

And the one that bites daily: **gtags answers at the NAME level.** `M-.` on an
overloaded or common name offers every same-named definition in the project
with no type information to discriminate them. Measured on `~/code/camhr/camhr`
(1078 `.java` files): `getId` has **75** definitions. Narrow by reading the
candidate list, not by expecting the right answer first.

If any of the above turns out to be non-negotiable, the deleted jdtls code is
recoverable from git history at the removal commit — restore it from there
rather than rewriting the `jdt://` plumbing, which took several rounds to get
the URI handler, read-only timing and `normal-mode` interaction right.

## The index

Java is parsed by **Universal Ctags**, not gtags' built-in Java parser, via the
`java-ctags` label in [`gtags.conf`](../gtags.conf). The built-in parser indexes
**no fields at all** and records call sites as definitions; see
[Why Java is not on the built-in parser](TAGS.md#why-java-is-not-on-the-built-in-parser)
for the measurements.

Build with **`C-c g g`**, refresh in bulk with **`C-c g u`**, diagnose shadowing
sub-indexes with **`C-c g d`**. Every save runs an incremental
`global --single-update` automatically.

Two things that will silently give you a worse index:

- **Building at the wrong root.** GNU Global resolves each lookup to the
  *nearest ancestor* `GTAGS`, so an index accidentally rooted at one Maven
  module hides the reactor index for every file beneath it. That is what the
  project-root finder below exists to prevent. `C-c g d` finds and deletes such
  shadows.
- **The wrong `GTAGSLABEL`.** It is re-read on *every* invocation and is not
  recorded in the database, so any build or update run under a different label
  re-parses with a different parser. `init-tags.el` exports `java-ctags`
  daemon-wide precisely so no call site can forget.

## Project resolution — where the index gets rooted

`fenrir/project-find-java-build-root` is prepended to `project-find-functions`
and claims Java buffers only. It ignores `.project` markers entirely — Eclipse
m2e left one inside every Maven module it ever imported, and project.el's
deepest-marker-wins logic would pin the root to a sub-module.

### Tier 1 — container marker (fuse many reactors)

If any ancestor holds `.eglot-java-workspace` (`fenrir/java-workspace-marker`),
that ancestor is the root for every Java file beneath it. Use it when several
independent reactors sit under one container directory and you want **one index
covering all of them**, so cross-reactor `M-.` / `M-?` resolve:

```bash
touch ~/code/hitok2/.eglot-java-workspace
```

Then `M-x fenrir/project-reset-cache`, and `C-c g g` from the container.

The filename is a fossil of the jdtls era (it once fused Eclipse workspaces).
Kept as-is so existing marker files keep working.

### Tier 2 — topmost-pom (standalone reactor)

Otherwise the root is the **topmost consecutive** ancestor holding `pom.xml` /
`build.gradle*` — the aggregator, not the module you happen to have open.
Nothing to configure; open a `.java` file and `C-c g g`.

### Verify

```
M-x fenrir/project-reset-cache      ; drop stale project.el roots
C-c g g                             ; build (defaults to the covering root)
C-c g d                             ; list every GTAGS in the subtree
```

`C-c g d` labels each index `[root]` or `[nested]` and offers to delete the
shadows. If `M-.` answers from stale data, this is the first thing to check.

## Navigation

| Key | Command | Notes |
|---|---|---|
| `M-.` | `xref-find-definitions` | Project source only. Overloads / common names return many candidates |
| `M-?` | `xref-find-references` | Textual: same-named local variables and parameters appear alongside real call sites |
| `M-,` | `xref-go-back` | |
| `M-g s` | `consult-imenu` (tree-sitter) | Current buffer's types/methods/fields — precise, because it is parsed not indexed |
| `<f6>` / `<f7>` | merged jump history | See [`init-keys.el`](../lisp/init-keys.el) |

`M-?` deserves a caveat. gtags' reference index is name-based, so
`global -r publishJob` on a method returns the parameter `PublishJob
publishJob`, every `publishJob.setX()` on that local, *and* the real
`jobService.publishJob(...)` call — undifferentiated. Read the list.

## Running tests

`C-c t t` (dwim) / `C-c t m` (method at point) / `C-c t f` (file) /
`C-c t b` (build the module). Backed by the `junit-core` dynamic module
(`cpp/junit-core/`), which does tree-sitter JUnit discovery and constructs the
Maven/Gradle command; the front-end runs it through `compile`. Build it once
with `M-x junit-runner-build` — until then the commands degrade to a build hint.

## Debugging

**Unsupported.** dape has no Java adapter, and dap-mode's fringe-bitmap
breakpoints are invisible on a TTY frame. Use IntelliJ or VSCode. Do not
reintroduce dap-mode.

## Troubleshooting

### `M-.` says "No tags here -- C-c g g builds a gtags index"

There is no index covering this file. Build one — but check the root first
(`C-c g d`), or you will create a nested index that shadows a good one.

### `M-.` finds nothing for a JDK or library class

Expected. The index contains project source only; jar and JDK sources are not
indexed and there is no server to decompile them. Read the source in your
browser or open the sources jar manually.

### `M-.` finds nothing for a field

If the index predates 2026-08-10 it was built with gtags' built-in Java parser,
which indexes no fields. Rebuild with `C-c g g` — `init-tags.el` now exports
`GTAGSLABEL=java-ctags`.

### Builds print `ctags-universal: Warning: Unknown language "…"`

Cosmetic. The plugin hands ctags the whole merged langmap and ctags does not
recognise pygments' language names. Verified: the tag set produced for a Java
file is byte-identical to a pure `new-ctags` build.

### The index misses a whole subtree

Check [`gtags.conf`](../gtags.conf)'s `common:` skip list — it drops `target/`,
`build/`, `node_modules/`, `.gradle/` and friends. That is deliberate (a bare
`global -u` without it once re-bloated an index from 2.5 MB to 3.85 GB), but it
does mean generated sources under `target/generated-sources/` are invisible.

### Java buffers resolve to the wrong project root

`M-x fenrir/project-reset-cache`, then re-check with
`M-: (project-root (project-current))`. If Tier 2 walked too far up, an
unexpected `pom.xml` sits in a parent directory; if it stopped too low, add a
Tier 1 marker at the level you want.

## Configuration map

| Concern | Symbol / file |
|---|---|
| Project root resolution | `fenrir/project-find-java-build-root`, `fenrir/java-workspace-marker` |
| Container marker filename | `fenrir/java-workspace-marker` (default `.eglot-java-workspace`) |
| Java parser routing | the `java-ctags` label + `universal-ctags-java` block in [`gtags.conf`](../gtags.conf) |
| Index build / update / diagnose | [`init-tags.el`](../lisp/init-tags.el) — `C-c g g` / `C-c g u` / `C-c g d` |
| JUnit runner | `junit-runner` elisp + `junit-core` module (`cpp/junit-core/`) |
| `C-c t` key table | `fenrir/junit-bind-keys` |

## What's NOT in this config

- **Any Java language server.** No jdtls, no `java-language-server`, no
  `lsp-java`. `init-java.el` adds no `eglot-ensure` hook and no
  `eglot-server-programs` entry.
- **`dap-mode` / Java debugging.** See above.
- **Formatting on save for Java.** apheleia owns format-on-save globally; if it
  has no Java formatter configured, Java simply isn't reformatted.
- **`var/lsp-java/`.** The 453 MB jdtls bundle and workspace are no longer read
  by anything. The directory is gitignored; delete it when you're confident you
  won't reinstate jdtls:
  ```bash
  rm -rf ~/.emacs.d/var/lsp-java
  ```

## References

- [TAGS.md](TAGS.md) — index creation, the `java-ctags` label, nested-index shadowing
- [FEATURES.md](../FEATURES.md) — the `C-c g` and `C-c t` key tables
- [GOTCHAS.md](GOTCHAS.md) — load-bearing oddities across the config
- [`cpp/README.md`](../cpp/README.md) — the `junit-core` dynamic module
