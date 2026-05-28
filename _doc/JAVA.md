# Java development

How Java editing works in this Emacs configuration: which packages drive what,
where they're configured, what to do when it breaks. Companion to the
keybinding cheat sheet in [FEATURES.md](../FEATURES.md), and to the
architecture notes in [CLAUDE.md](../CLAUDE.md) (the "Java on Eglot + jdtls"
and "Java project roots" bullets).

Java migrated from `lsp-mode` + `lsp-java` to **Eglot + jdtls** on the
`try/java-on-eglot` branch. The whole stack lives in
[`lisp/init-languages.el`](../lisp/init-languages.el).

## Stack

| Layer | Component | Where it lives |
|---|---|---|
| JDK | `java` (Corretto 21 here) | `~/.sdkman/candidates/java/current/bin/java` — any JDK 17+ on PATH works |
| LSP server | `eclipse.jdt.ls` (jdtls) | [`var/lsp-java/eclipse.jdt.ls/server/`](../var/lsp-java/) — ~150 MB bundle inherited from the old lsp-java install, kept to avoid a re-download |
| Server launcher | `fenrir/jdtls-launch-command` | [`lisp/init-languages.el`](../lisp/init-languages.el) — builds the `java -jar org.eclipse.equinox.launcher_*.jar …` argv |
| Major mode | `java-ts-mode` (falls back to `java-mode`) | Built-in; `treesit-auto` remaps `.java` when the grammar is installed |
| LSP client | `eglot` | Built-in; `eglot-ensure` hooked on `java-mode` / `java-ts-mode` like every other language |
| Client speedup | `emacs-lsp-booster` | `~/.cargo/bin/emacs-lsp-booster` — `eglot-booster` wraps the jdtls connection automatically |
| Workspace metadata | Eclipse `-data` dir | [`var/lsp-java/workspace/`](../var/lsp-java/) — delete out-of-band to force a full re-import |
| Diagnostics / hover / xref | `flymake` / `eldoc` / `xref` ← eglot ← jdtls | Built-in; `M-.` / `M-?` / `C-c d` |
| Maven settings | [`~/.m2/settings-public.xml`](file:///home/fenrir/.m2/settings-public.xml) | Pointed at via `java.configuration.maven.userSettings` — see [Maven dependency resolution](#maven-dependency-resolution) |

The launcher's JVM args mirror the old lsp-java preset (`-Xmx3G`, ParallelGC),
and the `:java` workspace config turns off decompiled-source/accessor matches
and code-lens for faster references. Both are pushed two ways: at the
`initialize` request (via the launcher's trailing `:initializationOptions`)
**and** via `workspace/didChangeConfiguration`. The init-time copy is
load-bearing for anything jdtls reads during its first project scan.

## Prerequisites

```bash
# A JDK 17+ on PATH (jdtls 1.57 needs 17+; this machine uses Corretto 21).
java -version

# The jdtls bundle is already vendored under var/lsp-java/ (not in git).
# To reinstall from scratch, download a jdtls release and unpack so that
# var/lsp-java/eclipse.jdt.ls/server/plugins/org.eclipse.equinox.launcher_*.jar
# exists; fenrir/jdtls-bundle-dir points there.

# emacs-lsp-booster (shared with the Eglot side for every language):
cargo install emacs-lsp-booster        # or grab a release binary onto PATH

# Tree-sitter Java grammar — installed automatically on first .java open by
# treesit-auto; lands in ~/.emacs.d/tree-sitter/.
```

## Project resolution — the crux

jdtls does cross-project find-references at the **Eclipse workspace** level:
every Maven/Gradle project imported into the single `-data` workspace is
searchable from any other. The hard part is making Eglot — which is
single-root per server — put the right set of projects into one workspace.

Root resolution is `fenrir/project-find-java-build-root`, prepended to
`project-find-functions` ahead of the built-in `project-try-vc`. It works in
two tiers:

### Tier 1 — container marker (fuse many reactors)

If any ancestor of the file holds a `.eglot-java-workspace` marker (filename
in `fenrir/java-workspace-marker`), **that ancestor is the project root for
every Java file beneath it**. Use this when one directory holds several
*independent* Maven/Gradle reactors that you want to navigate as a unit —
e.g. `~/code/hitok2/` containing `im-combined-api`, `im-combined-hitok`,
`hitok-java-backend`. All of them resolve to `~/code/hitok2/`, so they share
**one Eglot server → one jdtls workspace**, and opening a file in a sibling
repo never spawns a second jdtls fighting over the shared `-data` dir.

### Tier 2 — topmost-pom (standalone reactor)

Otherwise the root is the **highest consecutive ancestor** that has
`pom.xml` / `build.gradle` / `settings.gradle` (or the `.kts` variants). For a
normal multi-module Maven project this is the aggregator/parent-pom dir, and
jdtls auto-imports every module under it. No configuration needed.

`.project` files are deliberately **ignored** for root detection: Eclipse m2e
regenerates them inside every module on import, and the built-in
deepest-marker-wins logic would then pin jdtls to a too-deep sub-module
(symptom: `M-?` only returns hits inside that one sub-module).

## Setting up a new Java project

### Case A — a single reactor (one aggregator pom, nested modules)

Nothing to do. Open any `.java` file; Tier 2 finds the topmost pom and jdtls
imports the whole reactor. Cross-module references work immediately.

### Case B — a container of multiple independent reactors

```
M-x fenrir/eglot-java-set-workspace-root RET <container-dir> RET
```

This drops the `.eglot-java-workspace` marker, resets the project cache, and
offers to restart any running jdtls session. Then open a `.java` file under
the container — one server now covers every reactor beneath it.

To undo: `M-x fenrir/eglot-java-unset-workspace-root` (falls back to Tier 2).

There is also `M-x fenrir/eglot-java-add-roots-under RET <dir> RET`, which adds
Maven/Gradle roots to a *running* session via
`workspace/didChangeWorkspaceFolders` — handy for a one-off, but it does **not**
survive a restart and a sibling-repo buffer can still spawn a second server.
The marker is the durable mechanism; prefer it.

### Verify

```elisp
M-: (project-current) RET        ; should report the intended root
M-: (eglot-current-server) RET   ; non-nil once connected
M-x eglot-events-buffer          ; live JSON-RPC, or "No current Eglot" if unconnected
```

For a fused workspace, opening a file in each sub-repo should keep
`eglot--servers-by-project` at a single key (one server). A cross-project
`M-?` should list hits whose paths span more than one sub-repo.

## Maven dependency resolution

jdtls is pointed at [`~/.m2/settings-public.xml`](file:///home/fenrir/.m2/settings-public.xml)
through `java.configuration.maven.userSettings`. The default `~/.m2/settings.xml`
mirrors to an internal corporate Nexus (`nexus.mosainet.com:8081` /
`192.168.130.170:8081`) that is unreachable off the corp network — Maven then
hangs on TCP connect timeouts (75 s+ per uncached dependency), and because
jdtls' import job blocks its main thread, **every** LSP request times out
(even lightweight `workspace/symbol`). The public settings file shares the
`~/.m2/repository` cache but skips the corp profile and mirror, so dependencies
resolve from each pom's declared repositories + Maven Central, and anything
genuinely unavailable simply fails to resolve instead of hanging.

CLI `mvn` is unaffected — it still uses the default `~/.m2/settings.xml` unless
invoked with `-s ~/.m2/settings-public.xml`.

If a project needs deps that only live on a repo reachable from elsewhere
(corp Nexus, etc.), either connect to that network (VPN) or pre-cache the
deps into `~/.m2/repository` while you have access.

## The Gradle importer in container workspaces

`fenrir/jdtls--java-settings` sets `java.import.gradle.enabled = false` whenever
the connecting buffer is inside a container-marker workspace. Reason:
Buildship (jdtls' Gradle importer) **ignores `java.import.exclusions`**, so a
non-Java Gradle subtree under the container — e.g. a React Native app's
`android/` build referencing an absent `@react-native/gradle-plugin` — stalls
or crashes the import. Container Java here is all Maven, so disabling Gradle
costs nothing.

**Limitation:** this is keyed on the container marker, not per-subdirectory. If
you build a container that legitimately mixes Maven and Gradle *Java* projects,
the current helper turns Gradle off for the whole workspace. To support that,
edit `fenrir/jdtls--java-settings` to keep Gradle on and instead exclude the
specific offending subtree (note that, per the above, `import.exclusions` alone
won't stop Buildship — you'd need a sharper mechanism). Standalone Gradle
projects (no marker → their own server) keep Gradle enabled and need no change.

## Navigation

| Key | Command | Notes |
|---|---|---|
| `M-.` | `xref-find-definitions` | Into project source, or into JDK / jar classes via the `jdt://` handler (below) |
| `M-,` | `xref-go-back` | Pop the marker stack |
| `M-?` | `xref-find-references` | Cross-project across the whole fused workspace; results render in the consult minibuffer UI |
| `M-g s` | `consult-eglot-symbols` | Workspace-symbol search across all imported projects |
| `C-c .` | `eglot-code-actions` | Quick-fix / organize-imports / refactors |
| `C-c d` | `eldoc-doc-buffer` | Full hover doc in a side window |

`M-.` into a JDK class (`java.lang.String`) or a third-party-jar class returns a
`jdt://contents/…` URI, which Eglot has no native handler for. The handler
registered in `file-name-handler-alist` (see `fenrir/eglot--jdt-uri-handler`)
intercepts `jdt://`, finds the live jdtls server, requests source via the
`java/classFileContents` LSP extension, and shows it read-only. The matching
`extendedClientCapabilities.classFileContentsSupport` is sent in the launcher's
`:initializationOptions`.

## Code completion

There is **no Java-specific completion code** anywhere in the config. jdtls
completion rides the same generic Eglot capf path as gopls / pyright / rust-analyzer
— swap `java-ts-mode` for `go-ts-mode` and the picture below is identical.

### The flow

```
M-TAB / C-M-i  (completion-at-point)
      │
      ▼
completion-at-point-functions          ← buffer-local capf list
  ├─ eglot-completion-at-point          (Eglot prepends this when managing the buffer)
  │      │ textDocument/completion (JSON-RPC over stdio)
  │      ▼
  │   eglot-booster ──► jdtls ──► CompletionItem[]
  └─ cape-dabbrev / cape-file / cape-elisp-block   (global fallback capfs)
      │
      ▼
completion-in-region-function = consult-completion-in-region
      │
      ▼
Vertico minibuffer + orderless + marginalia   ← where candidates actually render
```

### The three environments

1. **jdtls (server).** Advertises `completionProvider` (and lazy
   `completionItem/resolve`) at the `initialize` handshake — LSP standard, on by
   default. This config pushes **no** `java.completion.*` settings, so completion
   runs on jdtls' factory defaults (see [What's NOT configured](#whats-not-in-this-config)).

2. **Eglot (client).** Once `eglot-ensure` (the `java-mode` / `java-ts-mode` hook
   in [`lisp/init-languages.el`](../lisp/init-languages.el)) attaches, Eglot adds
   `eglot-completion-at-point` to the buffer-local
   `completion-at-point-functions`. It sends `textDocument/completion`, turns the
   `CompletionItem[]` into Emacs candidates, and resolves documentation/detail
   lazily (only for the candidate you land on). Because `yas-global-mode` is on
   ([`lisp/init-snippets.el`](../lisp/init-snippets.el)), Eglot advertises
   `snippetSupport`, so completing a method expands its parameters into
   Tab-navigable placeholders. None of this is Java-specific.

3. **Frontend — Vertico minibuffer, not a Corfu popup.** The one non-default
   decision. `completion-in-region-function` is bound to
   `consult-completion-in-region` in
   [`lisp/init-completion.el`](../lisp/init-completion.el) (`:init`, so it wins
   before the first completion call), so candidates render **in the minibuffer**
   with the same Vertico + orderless + marginalia stack as `M-x` / `C-x C-f` —
   not in an at-point popup. `global-corfu-mode` is **deliberately off**
   ([`lisp/init-corfu.el`](../lisp/init-corfu.el)): enabling it would set its own
   buffer-local `completion-in-region-function` and silently override the consult
   routing. Corfu stays installed (`:defer t`) so flipping back is a one-line edit.

### Manual trigger — no type-as-you-go popup

`corfu-auto` is nil and `global-corfu-mode` is off, so there is **no auto-popup**.
Completion is manual: press `M-TAB` or `C-M-i` (`completion-at-point`). In a Java
buffer you will not see IntelliJ-style suggestions appearing as you type — you ask
for them.

### eglot-booster caveat

`eglot-booster` wraps the jdtls stdio (threaded I/O + JSON→bytecode pre-parse).
Its header note in [`lisp/init-languages.el`](../lisp/init-languages.el) flags that
tiny *per-keystroke* completion deltas may go marginally **slower** under the
bytecode trick. That's a non-issue here: completion is manual and routed through
the minibuffer, so there is no per-keystroke completion request to slow down.

## Troubleshooting

### `M-?` says "Visit tags table" / falls back to gtags

Eglot isn't attached to the buffer, so xref drops to the etags/ggtags
fallback. Check `M-: (eglot-current-server)` — if nil, the most common causes
are (1) no project root resolved (`M-: (project-current)` is nil — drop a
marker or check there's a pom above), or (2) jdtls failed to start (see below).

### Every request times out ("jsonrpc-error … Timed out")

jdtls' import is blocked. Almost always the unreachable-Nexus hang — confirm
with `ss -tnp | grep java` showing a `SYN-SENT` to a `:8081` host. The
`settings-public.xml` wiring should prevent this; if it regressed, verify
`M-: (fenrir/jdtls--java-settings)` includes the `userSettings` path. Otherwise
the import is just slow on a cold cache — wait and retry.

### jdtls crashes on restart (`DeltaDataTree` / workspace restore errors)

The on-disk workspace got into a half-imported state. Reset it:

```bash
pkill -9 -f eclipse.jdt.ls.core.product
rm -rf ~/.emacs.d/var/lsp-java/workspace
```
```elisp
M-x fenrir/project-reset-cache
;; then reopen a .java file
```

### `M-?` shows duplicate hits / "project already exists"

The same Maven artifact is checked out twice under one container (e.g. a
standalone `im-combined-hitok` plus a nested `im-combined-api/im-combined-hitok`).
jdtls imports both as duplicate JDT projects. Keep one copy under the container.

### Root resolved too deep (only one sub-module's references show)

Project detection landed on a sub-module. Confirm with `M-: (project-current)`.
If you want the whole container fused, run
`fenrir/eglot-java-set-workspace-root` at the container; if you want a single
reactor, make sure no stray `.eglot-java-workspace` marker sits in a deeper dir.
Run `M-x fenrir/project-reset-cache` after any marker change.

### `M-g s` (type search) errors with "stringp, nil" / shows nothing

`consult-eglot-symbols` (`M-g s`) drives **type search** via `workspace/symbol`.
On Java it used to crash with `Wrong type argument: stringp, nil` for almost any
query. Cause: jdtls returns JDK / jar types as `jdt://contents/…` URIs, and
consult-eglot's `consult-eglot--transformer` builds each candidate's display
label with `(file-relative-name (eglot-uri-to-path uri))` — `eglot-uri-to-path`
leaves a `jdt://` URI unchanged (it is not a `file://` URI), so
`file-relative-name` signals on the non-absolute path. The **same class of bug**
guarded for diff-hl / breadcrumb / org-roam / vc-refresh (see the `jdt://` block
in [`lisp/init-languages.el`](../lisp/init-languages.el)), but worse: the
transformer runs per candidate inside `consult--async-map`, so **one** throwing
candidate aborts the whole async refresh — and nearly every type search returns
at least one library type (even `Event` pulls in `java.util.EventListener`),
so the command errored before showing anything.

Fixed by a `:around` advice on `consult-eglot--transformer` (symbol
`fenrir/jdt-consult-eglot-transformer`) that scopes a `jdt://`-safe
`file-relative-name` to the transformer via `cl-letf` (for `jdt://` it returns
the URI minus its giant `?…` query string as the label). The jump path is
untouched — selecting a candidate goes through `eglot-uri-to-path` → `find-file`
→ the `jdt://` handler, which never calls `file-relative-name`. If `M-g s`
regresses to this error after a package upgrade, check the advice is still
attached: `M-: (advice-member-p 'fenrir/jdt-consult-eglot-transformer 'consult-eglot--transformer)`.

**Querying for types** (once the crash is fixed). The text you type after the
auto-inserted `#` is sent to jdtls as the `workspace/symbol` query; jdtls /
Eclipse matches it with **prefix + CamelCase + `*`/`?` wildcards**, case
-insensitive — **not** orderless (space-separated any-order tokens do *not* work
in that part). Measured semantics:

| Type after the `#` | Matches |
|---|---|
| `Event` / `Event*` | **starts** with `Event` (`EventListener`, `EventType`) |
| `*Event` | closest to "**ends** with `Event`" (`PaintEvent`, `OrderCreatedEvent`) — plus some CamelCase/package noise, and JDK/jar types |
| `*Event*` | **contains** `Event` |

jdtls has no clean "ends-with" mode, so `*Event` is the closest and carries some
noise. The text after a **second** `#` is an orderless filter applied
client-side to the candidate label (which includes the full path) — it does
**not** re-query jdtls. Use it to drop the JDK/jar noise and home in on your
project (measured against a real `*Event` search — 1140 hits, 25 of them project
types):

| Full minibuffer input | → jdtls query | → client filter | Result |
|---|---|---|---|
| `#*Event#src` | `*Event` | `src` | 25 — **only your project's types**; library `jdt://` URIs have no `src` in their path (`#main` / `#<repo-name>` isolate the same way) |
| `#*Event#src gcash` | `*Event` | `src gcash` | 7 — orderless tokens are **space-separated, any order, AND, case-insensitive** |
| `#*Event#src gcash success` | `*Event` | `src gcash success` | 1 — `GCashPaySuccessCallbackEvent` |
| `#*Event#src#gcash` | `*Event` | `src#gcash` | **0** — a *third* `#` is a literal char orderless can't match |

So: at most **two** `#` are structural — the 1st is the auto-inserted separator,
the 2nd is the jdtls-query ↔ filter boundary. Everything after the 2nd `#` is
the orderless filter; add further conditions with **spaces, not more `#`**. You
can also narrow by symbol kind with the consult narrow key (`< c` Class, `< i`
Interface, `< e` Enum).

**Where this syntax comes from** — `#*Event#src token token` is not one tool's
language; it is three independent conventions stacked in one input box:

1. **The `#…#` split → Consult.** This is consult's *async split*
   (`consult-async-split-style`, default `perl`). The `#async#filter` form — and
   the rule that the first punctuation char chooses the separator, so
   `/async/filter` works too — is named after Perl's swappable regex delimiter
   (`m#…#`). It shows up **only in consult's async commands**
   (`consult-ripgrep`, `consult-eglot-symbols`, …); plain `M-x` / `C-x C-f` /
   `C-s` (`consult-line`) have no `#` split, which is why this looks unfamiliar —
   there the whole input is orderless.
2. **The `*` / CamelCase in the query part → jdtls / Eclipse `SearchPattern`.**
   Consult passes that part verbatim to the backend; for `M-g s` the backend is
   jdtls' `workspace/symbol`. Nothing to do with consult or orderless — a
   different backend (ripgrep, gopls) would parse that part in its own language.
3. **The space-separated tokens in the filter part → orderless.** The filter is
   matched client-side by `completion-styles` (`'(orderless basic)` in
   [`lisp/init-completion.el`](../lisp/init-completion.el)); orderless splits on
   spaces (`orderless-component-separator`) → any-order, AND, case-insensitive.

Knobs: `(setq consult-async-split-style nil)` removes the `#` (whole input goes
to the backend, no client-side filter); `'comma` switches the separator to `,`
and stops auto-inserting it.

## Configuration map

| What | Symbol / file |
|---|---|
| `eglot-ensure` hooks | `eglot` `use-package` `:hook` in [`init-languages.el`](../lisp/init-languages.el) |
| jdtls launcher + JVM args + init options | `fenrir/jdtls-launch-command`, `fenrir/jdtls--java-settings` |
| Bundle / workspace paths | `fenrir/jdtls-bundle-dir`, `fenrir/jdtls-workspace-dir` |
| Project root resolution | `fenrir/project-find-java-build-root` (on `project-find-functions`) |
| Container marker filename | `fenrir/java-workspace-marker` (`.eglot-java-workspace`) |
| Set / unset container root | `fenrir/eglot-java-set-workspace-root`, `…-unset-workspace-root` |
| Ad-hoc workspace folders | `fenrir/eglot-java-add-roots-under` |
| `jdt://` source handler | `fenrir/eglot--jdt-uri-handler`, `fenrir/eglot--find-jdtls-server` |
| Per-server `:java` settings | `:java` entry of `eglot-workspace-configuration` |
| Maven settings | [`~/.m2/settings-public.xml`](file:///home/fenrir/.m2/settings-public.xml) |

## What's NOT in this config

- **Debugging.** `dap-java` went away with lsp-mode, and `dape` has no Java
  adapter. Use IntelliJ / VSCode for real Java debugging until either changes.
  See [FEATURES.md §7](../FEATURES.md) for the dape-based debugging that does
  work (Go, Python, etc.).
- **Build/test runner UI.** `M-x compile RET mvn test RET` from the project
  root; no integrated runner.
- **Completion tuning.** No `java.completion.*` keys are pushed to jdtls
  (`guessMethodArguments`, `maxResults`, `importOrder`, `favoriteStaticMembers`,
  …) — jdtls runs its factory completion defaults. To change that, add a
  `:completion (…)` entry to the `:java` plist in `eglot-workspace-configuration`
  (the `(setf (alist-get :java …))` block in
  [`lisp/init-languages.el`](../lisp/init-languages.el)). See
  [Code completion](#code-completion) for the path that those settings would feed.

## References

- [CLAUDE.md](../CLAUDE.md) — the "Java on Eglot + jdtls" and "Java project
  roots" architecture bullets.
- [_doc/GO.md](GO.md) — the sibling Go guide; same Eglot/xref/consult plumbing.
