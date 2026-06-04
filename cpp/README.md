# cpp/ — C++ libraries for Emacs

Workspace for native Emacs dynamic modules (C++ wrapping the
[`emacs-module.h`](/usr/include/emacs-module.h) ABI). Each library is a
self-contained subproject; the top-level [`CMakeLists.txt`](CMakeLists.txt) is
an aggregator that builds them all, and every module's `.so` is emitted into
`lib/` where the elisp loaders look for it.

## Layout

```
cpp/
├── CMakeLists.txt        # aggregator: add_subdirectory(<module>) per lib
├── build.sh              # build every module -> cpp/lib/*.so
├── lib/                  # built .so files (gitignored)
├── build/               # CMake build tree (gitignored)
└── junit-core/           # a module
    ├── CMakeLists.txt    # defines the junit-core MODULE target
    ├── README.md         # module docs
    ├── src/
    └── vendor/
```

## Modules

| module | feature | elisp front-end | docs |
|---|---|---|---|
| [`junit-core`](junit-core/) | JUnit test discovery (tree-sitter) + Maven/Gradle command construction | [`lisp/junit-runner.el`](../lisp/junit-runner.el) | [junit-core/README.md](junit-core/README.md) |

## Build

```bash
~/.emacs.d/cpp/build.sh            # all modules -> cpp/lib/*.so
~/.emacs.d/cpp/build.sh clean      # wipe build/ and lib/ first
```

Needs `cmake` + a C++17 compiler. Each module declares its own extra
dependencies in its `CMakeLists.txt` and fails configuration with an
actionable message if one is missing (junit-core needs `libtree-sitter-dev`).

From inside Emacs, `M-x junit-runner-build` runs this script in a compilation
buffer and loads the result.

## Adding a new module

1. `cpp/<name>/CMakeLists.txt` defining an `add_library(<name> MODULE …)` target
   with `PREFIX ""` and `SUFFIX ".so"` (so Emacs `module-load` finds `<name>.so`).
2. Put sources under `cpp/<name>/src/` (and any vendored deps under
   `cpp/<name>/vendor/`).
3. Add one `add_subdirectory(<name>)` line to the top-level
   [`CMakeLists.txt`](CMakeLists.txt).
4. Load it from elisp with
   `(module-load (expand-file-name "cpp/lib/<name>.so" user-emacs-directory))`.

Build outputs (`build/`, `lib/`) are gitignored; sources stay tracked.
