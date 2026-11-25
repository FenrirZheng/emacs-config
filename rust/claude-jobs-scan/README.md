# claude-jobs-scan — fast session & daemon scanner for claude-jobs-view

A standalone helper binary that [`lisp/claude-jobs-view.el`](../../lisp/claude-jobs-view.el) runs to populate `*claude-jobs*` and inspect sessions without spawning `jobctl list` (bash/jq/ps/awk) or repeated Elisp `file-expand-wildcards` globs.

```
claude-jobs-scan [--state-dir DIR] [--jobs-dir DIR] [--projects-dir DIR] [--head-bytes N] [--uuid UUID]
```

## Output

In full-scan mode (default), prints **one Elisp plist** on stdout:

```elisp
(:sessions
 ((:sid "..." :pid 123 :live-pids (123) :state "alive" :resumed nil
   :agent "..." :started "..." :cwd "..." :transcript-path "..." :first-user-text "...")
  ...)
 :daemons
 ((:short "..." :state "..." :updated "..." :intent "..." :raw-intent "..."
   :name "..." :cwd "...")
  ...))
```

In `--uuid UUID` mode, prints a single session plist or `nil`.

## Build

```bash
make -C ~/.emacs.d/rust/claude-jobs-scan          # -> ~/.emacs.d/rust/lib/claude-jobs-scan
make -C ~/.emacs.d/rust/claude-jobs-scan verify   # + verify Elisp read-from-string in emacs -Q --batch
cd ~/.emacs.d/rust/claude-jobs-scan && cargo test
```

Until built, `lisp/claude-jobs-view.el` logs a one-time hint naming `make -C rust/claude-jobs-scan` and falls back to `jobctl list`.
