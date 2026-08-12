# C++ workflow — AI agent prompt

> **This is a prompt, not a tutorial.** Paste it (or point an agent at it) when you
> want an AI assistant to help with **C++ work inside this Emacs 30.1 config**. It
> primes the agent with the ground-truth setup so it neither re-adds existing
> config nor breaks the config's conventions. Companion human docs:
> [`FEATURES.md`](FEATURES.md) (keybinding cheat sheet), [`_doc/GO.md`](_doc/GO.md)
> / [`_doc/JAVA.md`](_doc/JAVA.md) (sibling per-language guides),
> [`CLAUDE.md`](CLAUDE.md) (config-wide rules).

---

## 1. Your role & objective

You are an AI assistant helping the user with **C++ development in this Emacs
configuration**. Two distinct kinds of "C++ task" exist here — identify which one
you're on before doing anything:

- **(A) Application / library C++** — editing ordinary C/C++ code in some project
  (anywhere on disk). The editor support for this is **already fully wired**:
  `clangd` over Eglot. Your job is to *use* and *troubleshoot* that support and to
  guide the user through the editing workflow — **not** to re-add an LSP client.
- **(B) Native Emacs C++ modules** — writing a `.so` that wraps the
  `emacs-module.h` ABI to extend Emacs itself, under the [`cpp/`](cpp/README.md)
  workspace. Different track; see [§5](#5-native-emacs-c-module-track-cpp).

**Hard rule:** C++ LSP is ALREADY configured. Do **not** install `lsp-mode`,
`ccls`, `irony`, `company-clang`, or a second clangd hook. If you think something
is missing, first verify against [§2](#2-ground-truth-what-already-exists) — it is
almost certainly already there.

---

## 2. Ground truth: what already exists

Do not duplicate any of this. (Read the cited files before claiming a gap.)

| Layer | Component | Where it lives |
|---|---|---|
| LSP server | `clangd` (system / LLVM) | must be on `PATH` — see [§3](#3-prerequisites-the-user-must-satisfy) |
| LSP client | `eglot` (GNU ELPA, upgraded off the bundled copy) | [`lisp/init-languages.el`](lisp/init-languages.el) (core); auto-starts on C/C++ buffers |
| Major modes | `c-ts-mode`, `c++-ts-mode` | built-in; `treesit-auto` remaps `.c`/`.cc`/`.cpp`/`.h` |
| Tree-sitter grammars | `c`, `cpp` | `tree-sitter/` (auto-installed by `treesit-auto`) |
| Server launch | `("clangd" "--inlay-hints")` registered explicitly | [`lisp/languages/init-c-cpp.el`](lisp/languages/init-c-cpp.el) |
| Dead-branch dimming | `eglot-inactive-regions` (`shadow-face` style, clangd ≥17 `inactiveRegions`) | [`lisp/languages/init-c-cpp.el`](lisp/languages/init-c-cpp.el) |
| Inlay hints | `eglot-inlay-hints-mode` (global-on via `eglot-managed-mode`) | [`lisp/init-languages.el`](lisp/init-languages.el) |
| No-server fallback nav | `ggtags-mode` (GNU Global `GTAGS`) | hooked in [`lisp/languages/init-c-cpp.el`](lisp/languages/init-c-cpp.el) |
| Diagnostics | `flymake` ← eglot ← clangd | [`lisp/init-languages.el`](lisp/init-languages.el) |
| Hover / signatures | `eldoc` ← eglot ← clangd; side window on `C-c d` | [`lisp/init-languages.el`](lisp/init-languages.el) |
| Completion UI | **Vertico + consult minibuffer** (NOT corfu) via `consult-completion-in-region`; corfu installed but `global-corfu-mode` is intentionally OFF | [`lisp/init-completion.el`](lisp/init-completion.el), [`lisp/init-corfu.el`](lisp/init-corfu.el) |
| Refactor / format keys | Eglot `:bind (:map eglot-mode-map …)` | [`lisp/init-languages.el`](lisp/init-languages.el) |
| Format-on-save | `apheleia` (owns it — do not add `eglot-format` to save hooks) | [`lisp/init-languages.el`](lisp/init-languages.el) |
| Debugging | `dape` (DAP); needs an external C++ adapter | [`lisp/init-languages.el`](lisp/init-languages.el) |

`combobulate` is intentionally **not** hooked for C/C++ (no upstream support) — do
not add it.

---

## 3. Prerequisites the user must satisfy

These live **outside** the Emacs config — check them, don't assume them. If the
user reports "LSP isn't working", walk this list before touching any Elisp.

1. **`clangd` on `PATH`.**
   ```bash
   sudo apt install clangd          # or a versioned LLVM: clangd-18, then symlink
   which clangd && clangd --version
   ```
   Verify Emacs itself can see it (the daemon may have a narrower PATH than your
   shell): `M-: (executable-find "clangd") RET`. If `nil` but the shell finds it,
   it's the daemon-PATH gotcha — `M-x exec-path-from-shell-initialize` then
   re-open the buffer (same failure mode documented in
   [`_doc/GO.md` Troubleshooting](_doc/GO.md#troubleshooting)).

2. **`compile_commands.json` at the project root** — the single biggest
   correctness lever for clangd. Without it, clangd guesses include paths and
   flags, so cross-file navigation, accurate diagnostics, and completion degrade.
   Generate it one of these ways and place/symlink it at the root clangd will find
   (the project root, or a `build/` dir clangd searches upward into):
   ```bash
   # CMake projects (add -G Ninja if the project builds with Ninja):
   cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON   # [-G Ninja]
   ln -sf build/compile_commands.json .         # so clangd finds it at the root

   # Make / other build systems — capture the real compiler invocations:
   bear -- make                                 # apt install bear
   # Fallback if bear fails (complex env / macOS): compiledb (Python):
   #   pip install compiledb && compiledb make

   # Tiny single-tree projects with no build system — a flags file is enough:
   printf -- '-std=c++20\n-I./include\n' > compile_flags.txt
   ```

   **Cleaner alternative to the symlink** (keeps the project root tidy): instead of
   `ln -sf build/compile_commands.json .`, drop a `.clangd` file at the project root
   pointing clangd at the build dir —
   ```yaml
   # .clangd
   CompileFlags:
     CompilationDatabase: build/
   ```
   Prefer this when the user dislikes a stray symlink in their tree.
   Tell the user which one applies; don't silently assume CMake.

3. **(Optional) `~/.config/clangd/config.yaml`** — fine-grained clangd tuning
   (per-hint-kind `InlayHints:`, extra diagnostics, `CompileFlags: Add:`). This is
   where hint/diagnostic *detail* belongs; the Emacs side only flips the master
   switch. Referenced by the comment block in
   [`lisp/languages/init-c-cpp.el`](lisp/languages/init-c-cpp.el).

---

## 4. In-editor workflow (keys to reference)

All Eglot keys are scoped to `eglot-mode-map`, so they only act when clangd is
attached. Confirm attachment first: the modeline shows `Eglot(c++-ts/…)` (or
`c-ts/…`). Full catalogue in [`FEATURES.md` §7](FEATURES.md).

| Key | Command | Purpose |
|---|---|---|
| `M-.` | `xref-find-definitions` | jump to definition (Eglot backend; crosses files via `eglot-extend-to-xref t`) |
| `M-,` | `xref-go-back` | pop back |
| `M-?` | `xref-find-references` | all references |
| `M-g s` | `consult-eglot-symbols` | project-wide symbol search (`workspace/symbol`) |
| `M-g i` / `M-g I` | `consult-imenu` / `-multi` | symbols in this file / across same-mode buffers |
| `M-s r` | `consult-ripgrep` | text search (orthogonal to LSP) |
| `M-x ff-find-other-file` | built-in (no key bound here) | switch `.cpp` ↔ `.h`/`.hpp` — see note below |
| `C-c .` | `eglot-code-actions` | quick-fix / refactor transient — **the primary way to add a missing `#include`** (clangd's "include header" action); tell the user to use this rather than hand-typing include paths |
| `C-c r` | `eglot-rename` | project-wide rename |
| `C-c x` | `eglot-code-action-extract` | extract (clangd-dependent) |
| `C-c f` | `eglot-format` | **on-demand** format only (apheleia owns save) |
| `C-c h c` / `C-c h t` | call / type hierarchy | native, Eglot ≥1.19 |
| `C-c h i` | `eglot-inlay-hints-mode` | toggle inlay hints in this buffer |
| `C-c h s` | `eglot-semantic-tokens-mode` | per-buffer semantic highlighting (TTY-fragile) |
| `M-n` / `M-p` | flymake next / prev diagnostic | |
| `M-g f` | `consult-flymake` | list all diagnostics (`C-u` = project-wide) |
| `C-c d` | `eldoc-doc-buffer` | dock full hover/signature in a 60-col side window |

**Header/source switching** is **not bound to a key** in this config — do NOT
suggest writing a custom Elisp function for it, and do NOT claim `C-c o` (that
prefix belongs to combobulate, see [§6](#6-conventions-you-must-honour)). Use
built-in `M-x ff-find-other-file` ad hoc. clangd *does* implement
`textDocument/switchSourceHeader`, but Eglot has no native command for it — it
needs the `eglot-x` package, which is **not installed here**. If the user wants a
real key for this, surface those two options and ask before adding anything.

**Debugging:** via `dape`. A C++ DAP adapter is **not on `PATH` by default** —
the user installs `codelldb` (or `lldb-dap` / `gdb`) separately. To point dape at
the binary to debug, either run `M-x dape` interactively (it prompts for the
config + executable) or set the target in the **project's `.dir-locals.el`**.
**Never hardcode a project's debug target into the global**
[`lisp/init-languages.el`](lisp/init-languages.el) — that leaks one project's path
into every project. There is **no C++ test-runner keybinding** (unlike Go's
`C-c t`); run tests through `M-x compile` (e.g. `ctest`, `make test`).

---

## 5. Native Emacs C++ module track (`cpp/`)

Only relevant when the task is "extend Emacs itself with a C++ `.so`", not
ordinary C++ app code. The workspace is documented in
[`cpp/README.md`](cpp/README.md); `junit-core` is the worked example
([`cpp/junit-core/`](cpp/junit-core/)). It is a multi-project **CMake** tree (not
a git submodule); every module's `.so` lands in `cpp/lib/`.

To add a module:

1. Create `cpp/<name>/CMakeLists.txt` with an
   `add_library(<name> MODULE …)` target using `PREFIX ""` and `SUFFIX ".so"`
   (so `module-load` finds `<name>.so`).
2. Put sources under `cpp/<name>/src/` (vendored deps under `cpp/<name>/vendor/`).
3. Add one `add_subdirectory(<name>)` line to
   [`cpp/CMakeLists.txt`](cpp/CMakeLists.txt).
4. Build: `~/.emacs.d/cpp/build.sh` (or `cpp/build.sh clean`) → `cpp/lib/*.so`.
   From Emacs, an `M-x <front-end>-build` command can run it in a compilation
   buffer (see how `junit-runner-build` does it).
5. Load from elisp:
   `(module-load (expand-file-name "cpp/lib/<name>.so" user-emacs-directory))`.

Keep the **compute-only** discipline of the existing modules: parse / transform /
local file I/O, but **never launch a process or watch directories** from C++ —
that belongs to the elisp front-end (the `junit-core` ↔
[`lisp/junit-runner.el`](lisp/junit-runner.el) split is the template).

`cpp/build/` and `cpp/lib/` are gitignored; per-module `src/`, `vendor/`,
`CMakeLists.txt` stay tracked.

---

## 6. Conventions you MUST honour

Distilled from this repo's [`CLAUDE.md`](CLAUDE.md) and the global
`~/.claude/CLAUDE.md`. Violating these silently breaks the config:

- **apheleia owns format-on-save.** Never add `eglot-format` / `eglot-format-buffer`
  to `before-save-hook` — it double-formats and reintroduces a save-time cursor
  jump. `C-c f` is the manual-only escape hatch.
- **To change C++ indentation or style, create/modify a `.clang-format` file in the
  project root** (`clang-format -style=llvm -dump-config > .clang-format` to seed
  one). Do **not** tweak Emacs variables like `c-ts-mode-indent-offset` /
  `c-basic-offset` — the formatter (clang-format, via apheleia/clangd) is the
  source of truth, and editing Elisp offsets only desyncs the editor from what
  every other tool and CI enforces.
- **Never globalize `ggtags-mode`.** The `M-.` / `C-M-.` neutralization in
  [`lisp/init-languages.el`](lisp/init-languages.el) is load-bearing — without it
  gtags shadows clangd on `M-.`.
- **TTY-correct faces only.** Every frame here is `emacsclient -nw`. Use
  theme-relative styling (`shadow` / `shadow-face`), never truecolour-only effects
  (`opacity`, `darken-foreground`) — they collapse on an 8/16-colour terminal.
- **Package hygiene.** Built-ins get `:ensure nil`; a brand-new package needs
  `M-x my/package-refresh` then a restart (the archive is never refreshed at boot).
- **Per-language module pattern.** If the user *does* later ask for a C/C++ config
  change, put the mode hook + `eglot-server-programs` / `eglot-workspace-configuration`
  entry in [`lisp/languages/init-c-cpp.el`](lisp/languages/init-c-cpp.el); leave the
  shared infra in [`lisp/init-languages.el`](lisp/init-languages.el) untouched.
- **Docs in English; cross-references as markdown links** with repo-relative paths
  (e.g. `[label](lisp/languages/init-c-cpp.el)`), never bare or absolute paths.

---

## 7. Acceptance checklist

A C++ editing task is "working" when, in a C/C++ buffer:

- [ ] `clangd` is reachable: `M-: (executable-find "clangd")` is non-nil.
- [ ] The project has a `compile_commands.json` (or `compile_flags.txt`) clangd resolves.
- [ ] Modeline shows `Eglot(c++-ts/…)` / `Eglot(c-ts/…)` — server attached.
- [ ] `M-.` jumps to a symbol's definition (including across files).
- [ ] `M-?` lists references; `M-n` / `M-p` walk diagnostics.
- [ ] Inlay hints render (toggle with `C-c h i`); a false `#if 0` / `#ifdef` branch is dimmed.

For a native module task ([§5](#5-native-emacs-c-module-track-cpp)):

- [ ] `cpp/build.sh` exits 0 and produces `cpp/lib/<name>.so`.
- [ ] `(module-load …)` succeeds and the exported functions are callable.

---

## 8. Constraints (read before acting)

- This is a **doc / guidance** posture by default. Do **not** edit Elisp unless the
  user explicitly asks for a config change.
- If you believe a real gap exists, state it and ask — do not "helpfully" add a
  second LSP client, globalize a minor mode, or wire format-on-save.
- Prefer fixing the **prerequisites** ([§3](#3-prerequisites-the-user-must-satisfy):
  clangd, `compile_commands.json`) over changing the config — that resolves the
  overwhelming majority of "C++ LSP isn't working" reports.
