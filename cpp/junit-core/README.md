# junit-core — Emacs dynamic module

A module in the [cpp/ workspace](../README.md) (C++ wrapping the
[`emacs-module.h`](/usr/include/emacs-module.h) ABI) that discovers JUnit tests
in a Java file with **tree-sitter** and builds the **Maven/Gradle** command to
run them. The elisp front-end [`lisp/junit-runner.el`](../../lisp/junit-runner.el)
loads it on demand and runs that command through `compile`.

Division of labour: the C++ side parses + decides *what command to run*; it
never launches a process. Running is elisp's job (`compile`), so you get
compilation-mode error navigation and `recompile` (`g`) for free.

## What it exposes to elisp

| function | returns |
|---|---|
| `(junit-core-class-info FILE)` | plist `:package :class :fqcn :is-test-file :tool :directory`, or nil |
| `(junit-core-method-at-line FILE LINE)` | plist `:method :class :test :begin-line :end-line` for the method enclosing 1-based LINE, or nil |
| `(junit-core-command FILE &optional LINE)` | plist `:command :directory :tool :scope :class :method :description`; LINE → run that `@Test` method, no LINE → run the whole file; nil if no runnable test / no build tool |

`:class` in `junit-core-method-at-line` is the JVM binary name (nested classes
joined with `$`, e.g. `OuterTest$NestedTest`) so it drops straight into a
Surefire / Gradle test selector.

## Build

Requires `cmake`, a C++17 compiler, and the tree-sitter runtime:

```bash
sudo apt install libtree-sitter-dev      # provides <tree_sitter/api.h> + -ltree-sitter
~/.emacs.d/cpp/build.sh                   # -> cpp/lib/junit-core.so
```

Or from inside Emacs: `M-x junit-runner-build` (runs the workspace `build.sh`
in a compilation buffer and loads the `.so` on success).

The tree-sitter **java grammar** is vendored under
[`vendor/tree-sitter-java/`](vendor/tree-sitter-java/) (`parser.c` + its
`tree_sitter/` headers, `LANGUAGE_VERSION 14`) and compiled straight in — only
the *runtime* comes from apt. Build outputs land in the workspace `cpp/lib/`
and `cpp/build/`, both gitignored.

## Use

In a `java-ts-mode` / `java-mode` buffer (keys wired in
[`lisp/languages/init-java.el`](../../lisp/languages/init-java.el)):

| key | command | action |
|---|---|---|
| `C-c t t` | `junit-run-dwim` | method at point if it's a `@Test`, else whole file |
| `C-c t m` | `junit-run-method-at-point` | the `@Test` method enclosing point |
| `C-c t f` | `junit-run-file` | every test in the file |
| `C-c t b` | `junit-runner-build` | (re)build the module |

The buffer is saved first (the module reads the file from disk; mvn/gradle
compile the on-disk copy anyway).

## Detection rules

- **Test annotations** (JUnit 4 + 5): `@Test`, `@ParameterizedTest`,
  `@RepeatedTest`, `@TestFactory`, `@TestTemplate` — matched on the last dotted
  segment, so fully-qualified `@org.junit.jupiter.api.Test` works too.
- **Build tool**: walk up from the file's directory. The nearest `pom.xml`
  wins → Maven, run from that module dir. Otherwise the nearest
  `build.gradle{,.kts}` / `settings.gradle{,.kts}` → Gradle, run from the
  nearest `gradlew` root (falls back to a `gradle` on `PATH`).
- **Commands**:
  - Maven method: `mvn test -Dtest='Class#method' -DfailIfNoTests=false`
  - Maven file: `mvn test -Dtest='Class'`
  - Gradle method: `./gradlew test --tests 'com.pkg.Class.method'`
  - Gradle file: `./gradlew test --tests 'com.pkg.Class'`

## Known limitations (v1)

- Whole-file scope targets the first top-level type; a file with several
  top-level test classes runs only the first.
- Multi-module reactors: Maven runs in the nearest module (fast, correct);
  Gradle runs from the wrapper root with a global `--tests` filter (correct,
  configures all subprojects so slightly slower).
