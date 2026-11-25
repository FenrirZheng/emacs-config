# git-diff-hl

Computes `vc-git` file states and `diff-hl` `(line inserts deletes type)` hunks in one batch
pass across a list of paths (or all tracked paths) in a Git repository. Reading and diffing
are done in-process with [gix](https://github.com/GitoxideLabs/gitoxide) and `imara-diff`
(`gix::diff::blob`), using a `HEAD` + index `lstat` fast-path for clean files and a small
`std::thread::scope` worker pool for changed files. It never runs `git` and never writes.

## Options

```
git-diff-hl [options] [<path>...]

  -C <dir>        run in <dir> instead of the current directory
  --porcelain     emit '# git-diff-hl v1' + tab-separated F/H records
  --sexp          emit a single Elisp alist for Emacs `read'
  --all           inspect all tracked paths in index/HEAD (not only changed)
  --stdin         read repo-relative paths from stdin (newline-delimited)
  -z              with --stdin, read NUL-delimited paths from stdin
  --exit-code     exit 1 if any inspected file has state != up-to-date
  -h, --help      this help
  -V, --version   print the version
```

`--porcelain` emits a `# git-diff-hl v1` header line, then per inspected path:

```
F\t<state>\t<path>
H\t<line>\t<inserts>\t<deletes>\t<type>
```

where `<state>` is one of `up-to-date`, `edited`, `added`, `removed`, `conflict`,
`unregistered`, `ignored`, `<line>` is 1-based, and `<type>` is `insert`, `delete`, or
`change`.

The Emacs front end in [`lisp/init-git.el`](../../../lisp/init-git.el) invokes
`rust/lib/git-diff-hl -C <topdir> --porcelain --stdin -z` once per `diff-hl-magit-post-refresh`.

## Build and install

A member of the [`git-tools` cargo workspace](../README.md) in this Emacs config's
[`rust/` workspace](../../README.md).

```bash
make -C rust/git-tools                     # cargo build --release (all members), deploy to rust/lib/
make -C rust/git-tools verify              # also check each bin's porcelain header
cargo test -p git-diff-hl                  # from rust/git-tools/
```
