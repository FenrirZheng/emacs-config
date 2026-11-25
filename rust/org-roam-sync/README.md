# org-roam-sync

Parallel Rust indexer for `org-roam` SQLite cache (`org-roam.db`, schema v20) and `org-id-locations` (`id-locations.el`), integrated with `lisp/init-org-roam.el` and `lisp/init-org.el`.

Binary output: `../lib/org-roam-sync`.

## CLI Contract

```text
org-roam-sync --dir DIR [--db PATH] [--exclude REGEX]... [--exclude-elisp REGEX]... [--ext EXT]... [--force] [--ignore-case] [--emit-org-ids | --org-id-out PATH]
```

- `--dir DIR`: Root directory to walk (`walkdir` with `follow_links(true)`; includes hidden/dotdirs).
- `--db PATH`: SQLite cache DB path (optional when using `--emit-org-ids` or `--org-id-out` standalone).
- `--exclude REGEX`: Repeatable relative-path exclude regex in standard Rust `regex` syntax (e.g. `^records/`; `init-org-roam.el` translates Elisp `org-roam-file-exclude-regexp` entries into Rust regexes before passing `--exclude`).
- `--exclude-elisp REGEX`: Repeatable relative-path exclude regex in Elisp regexp syntax (e.g. ``\`records/``), translated to Rust `regex` syntax by the CLI.
- `--ext EXT`: Repeatable file extension filter (default: `org`).
- `--force`: Remove and rebuild `--db` from scratch.
- `--ignore-case`: Match `--exclude` / `--exclude-elisp` patterns case-insensitively (passed by `init-org-roam.el` when `case-fold-search` is non-nil).
- `--emit-org-ids`: Print `((abbreviated-path "id1" ...) ...)` to stdout for Emacs `read`.
- `--org-id-out PATH`: Merge scanned entries under `--dir` into `PATH` atomically, preserving all entries outside `--dir`.
- **Exit codes**:
  - `0`: Success.
  - `1`: Argument, I/O, or SQLite error.
  - `2`: Non-excluded `.org.gpg` or `.org.age` file detected in `--db` sync mode (exits before touching `--db` so `init-org-roam.el` falls back to Emacs/EPA).

## SQLite v20 & EmacSQL Format Rules

- Sets `PRAGMA busy_timeout = 20000`, `PRAGMA foreign_keys = ON`, `PRAGMA user_version = 20`, and wraps incremental updates in a single `BEGIN IMMEDIATE` transaction.
- Creates exact v20 tables (`files`, `nodes`, `aliases`, `citations`, `refs`, `tags`, `links`) and indices (`alias_node_id`, `refs_node_id`, `tags_node_id`).
- Serializes scalars matching EmacSQL `prin1-to-string` (`print-escape-newlines = t`, `print-escape-control-characters = t`, octal escapes zero-padded to 3 digits before `'0'..'7'`, `""` stored as `'""'`, `nil` as SQL `NULL`, `nodes.priority` as ASCII integer code, `pos` as 1-based Unicode scalar offset, `atime`/`mtime` as `(HIGH LOW USEC PSEC)`).
- Computes `files.hash` as lowercase hex SHA-1 over raw file bytes.
- Stores canonicalized (`file-truename`), `$HOME`-abbreviated (`~/...`) paths for `org-id-locations` entries.

## Build, Verify & Test

```bash
# Build release binary (uses .cargo/config.toml with mold) and deploy to ../lib/org-roam-sync
make

# Build, deploy, and verify org-roam-node-list reads the generated DB in emacs -Q --batch
make verify

# Run Rust unit tests (offline, locked)
cargo test --locked --offline

# Run Emacs ERT integration & parity suite
emacs -Q --batch -l ../../test/org-roam-sync-test.el -f ert-run-tests-batch-and-exit

# Confirm mold linker and system libsqlite3 linkage
readelf -p .comment ../lib/org-roam-sync
```

## Benchmarks (`~/code/org-roam`, 1,868 `.org` files / 1,849 nodes / 5,912 links)

Measured against `/tmp` DBs with `emacs -Q --batch` and `rust/lib/org-roam-sync`:

| Operation | Pure Elisp (median) | Rust-backed (median) | Speedup |
|---|---:|---:|---:|
| `org-roam-db-sync` cold (`force = t`) | 31,356.1 ms | 62.4 ms | **502.6x** |
| `org-roam-db-sync` warm (no-op) | 498.8 ms | 18.0 ms | **27.7x** |
| Standalone CLI cold (`--force`) | 31,356.1 ms (vs Elisp) | 53.6 ms | **584.9x** |
| Standalone CLI warm (no-op) | 498.8 ms (vs Elisp) | 25.1 ms | **19.8x** |
| `fenrir/org-id-index-directory` (1,849 IDs) | 5,291.0 ms | 57.0 ms | **92.5x** |
