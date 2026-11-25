# Plan: remove eglot-booster

## Context

The 2026-11-06 gopls benchmark gave the verdict `no-win`. On a 330 KB references reply, Emacs blocked for 1.3 ms with no booster, 1.3 ms with I/O-only and 1.8 ms with bytecode. Bytecode mode, the current setting, also leaves non-ASCII LSP text undecoded in batch runs. Upstream is archived, and the package advises Eglot internals.

The user's decisions:
- Remove the package instead of switching to I/O-only. The request named both, and they were confirmed as alternatives.
- Keep the benchmark and the dated evidence as history.

Prior evidence read: `_doc/GOTCHAS.md` (both 2026-11-06 entries), `tasks/emacs-perf-followups.org`, `plans/twinkly-tumbling-bengio.md` (P3 `no-win` removal list). That list's line numbers are stale, and its "delete the harness" item is overridden by the user's decision. Find each edit by searching for the text.

## Changes

Load the `emacs-config` skill before editing. Don't commit; the user didn't ask for one. The working tree already holds unrelated uncommitted edits (`early-init.el`, `lisp/init-org.el`, other plans), and those stay untouched.

**Active config: no mention left**
- `lisp/init-languages.el`: delete the `use-package eglot-booster` block and its whole comment (about lines 312-358); drop the name from the header list (line 12) and from the note about the Eglot upgrade (lines 143-145).
- `custom.el`: remove `eglot-booster` from `package-selected-packages` (line 23) and `package-vc-selected-packages` (line 44).
- `lisp/languages/init-toml.el:41`: reword, because it would falsely say the booster wraps the connection.
- `lisp/languages/init-rust.el:58` and `lisp/init-ide.el:68`: drop the name from the comparisons.
- `shell/install-user.sh`: remove the `emacs-lsp-booster` cargo install (lines 59-60) and its mentions (lines 8, 68), keeping difftastic.

**Current-state docs**
- `CLAUDE.md:158-161`: delete the `eglot-booster` trap bullet.
- `FEATURES.md`: delete the bullet at about lines 664-683; drop the author mention at about line 704.
- `README.md:27`, `_doc/ARCHITECTURE.md:97`, `_doc/BOOTSTRAP.md:62,95`, `_doc/README.md:11`: reword so none describes the booster as present. `BOOTSTRAP.md:62` keeps combobulate as its `:vc` example.
- `lisp/init-languages.el` keeps no pointer to the removed section.

**Evidence: kept, with the decision recorded through `record-convention`**
- `_doc/GOTCHAS.md`: retitle the section to say the booster was removed, delete the present-tense toggle instructions, keep both dated measurement entries, and add a dated entry for the removal decision with its reasons and rollback.
- `tasks/emacs-perf-followups.org`: mark the benchmark heading DONE with the outcome; fix the "Already used" line at about line 73, which says the booster is in use.
- `test/booster-bench.el`: keep; add one header line saying a rerun first needs `M-x package-vc-install` of eglot-booster.
- Leave as they are: `plans/`, `tasks/20260610/`, `prompts/`.

**Installed package and live daemon**

This goes beyond editing files, and approving this plan approves it. In the running daemon, in this order:
1. `(eglot-shutdown-all)`. This stops every language server. File buffers are not affected, and Eglot reconnects on the next visit or `M-x eglot`. It has to come first, because a bytecode server still running loses the advice that reads its messages.
2. `(eglot-booster-mode -1)`.
3. `(package-delete (cadr (assq 'eglot-booster package-alist)) t t)`, which removes `elpa/eglot-booster`.
4. `setq` both package variables without the entry, so a later `customize-save` in this daemon doesn't write it back to `custom.el`. Use plain `setq`, not `customize-set-variable`.

Left in place: `~/.cargo/bin/emacs-lsp-booster`, which is outside `~/.emacs.d`. Report it so the user can delete it with `cargo uninstall emacs-lsp-booster`.

## Verification

Capture a baseline of the fresh-init check before editing, so existing warnings aren't blamed on this change.

1. **References:** `ug -rn --ignore-files -i 'booster' lisp custom.el shell init.el early-init.el` returns nothing. The same search over the whole repo, excluding `elpa`, `eln-cache` and `var`, hits only the kept history: `_doc/GOTCHAS.md`, `tasks/`, `plans/`, `prompts/`, `test/booster-bench.el`.
2. **Fresh init loads, in a separate process:** `emacs --batch -l ~/.emacs.d/early-init.el -l ~/.emacs.d/init.el --eval "(progn (require 'eglot) (princ (list (featurep 'eglot-booster) (advice-member-p 'eglot-booster--jsonrpc--json-read 'jsonrpc--json-read))))"` exits 0 and prints `(nil nil)`, with no new errors against the baseline.
3. **Regression suite:** `emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit` passes, with a 10 s timeout.
4. **Live daemon:** `emacsclient -e` shows the mode off, no advice, and `(package-installed-p 'eglot-booster)` nil.
5. **Eglot still works unboosted:** open a Go file in the daemon so gopls connects, then confirm through `emacsclient -e` that the server process's command has no `emacs-lsp-booster` in it and that a hover request returns.
6. **`custom.el`:** `git diff custom.el` shows only the two removed entries.

## Rollback

Restore the `use-package` block and the `custom.el` entries, run `M-x package-vc-install RET https://github.com/jdtsmith/eglot-booster`, then restart. The binary is still on this machine.
