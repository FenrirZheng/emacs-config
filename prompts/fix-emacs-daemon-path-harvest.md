# Fix: Emacs daemon startup errors (exec-path-from-shell + eglot-booster)

You are a dotfiles surgeon working on /home/fenrir. Default stance: the
diagnosis below is PRE-VERIFIED — your job is to apply the minimal fix and
prove it with the oracles, not to re-explore alternative theories.

RUNNER FILLS: none — all facts are pre-verified and inlined. If any inlined
fact fails to reproduce on your machine state (file content differs, binary
missing), STOP and report the mismatch — do not improvise a different fix.

<verified_facts>
- Root cause: ~/.bashrc lines ~26-34 auto-`exec tmux attach-session` for any
  interactive shell. exec-path-from-shell (init.el:138) spawns
  `bash -l -i -c …` with no TTY; guards ($TMUX empty, TERM=dumb) all pass,
  tmux attach fails with "open terminal failed: not a terminal", exit 1.
- Downstream: PATH never harvested → daemon exec-path lacks ~/.cargo/bin →
  eglot-booster reports "emacs-lsp-booster is not installed" even though
  /home/fenrir/.cargo/bin/emacs-lsp-booster exists.
- Rejected fix (tested): dropping `-i` via exec-path-from-shell-arguments —
  `bash -l -c 'echo $PATH'` loses go/bin, sdkman, pnpm (they export after
  .bashrc's interactive guard). Would silently break gopls/jdtls discovery.
</verified_facts>

PROCEDURE (do not skip steps):
1. Read the tmux auto-attach block in ~/.bashrc → confirm it matches the
   shape in <verified_facts> (guards: $TMUX, NO_TMUX, INSIDE_EMACS, TERM).
2. Edit ~/.bashrc: add `&& [ -t 0 ]` to that guard chain, plus one guard
   comment line (`stdin is a tty : never exec tmux from a tty-less spawn
   like exec-path-from-shell's bash -l -i -c`). → diff shows exactly the
   guard line + comment changed, nothing else.
3. ORACLE A (root cause): run
   `env -u TMUX -u INSIDE_EMACS TERM=dumb bash -l -i -c 'echo $PATH' </dev/null`
   → exit 0, no "open terminal failed" text, output contains BOTH
   `/home/fenrir/.cargo/bin` AND `/home/fenrir/go/bin`. Paste real output.
   If red: revise the edit and repeat. Max 3 rounds, then stop and report.
4. ORACLE B (no regression): confirm interactive auto-attach still fires by
   reading the logic — `[ -t 0 ]` is true for a real terminal, so behavior
   there is unchanged. Mark this MANUAL-VERIFY: user opens one new terminal
   window and confirms it lands in tmux.
5. CONFIRM GATE — daemon restart is user-visible (this daemon serves live
   TTY + GUI frames). Ask the user to run, at a moment of their choosing:
   `systemctl --user restart emacs` (or their restart path).
6. ORACLE C (end-to-end, after the user restarts):
   `emacsclient --eval '(executable-find "emacs-lsp-booster")'` → non-nil
   path; `emacsclient --eval '(getenv "PATH")'` contains .cargo/bin; opening
   /home/fenrir/code/rust_integration/python_rust_ffi_example/example.py
   shows no use-package warnings and Eglot attaches.
7. ~/.bashrc is tracked in the $HOME dotfiles repo: commit with
   `git -C ~ add .bashrc` (NEVER `git add .` at $HOME) once Oracle A is
   green. No push.

OUTPUT — return exactly this shape:
- diff applied: <the .bashrc hunk>
- Oracle A: <pasted command output + exit code>
- Oracle B: MANUAL-VERIFY handed to user
- Oracle C: <pasted output, or "pending user daemon restart">
- commit: <sha or "not yet — pending Oracle A">

NEVER:
- reinstall emacs-lsp-booster — it exists at ~/.cargo/bin; reinstalling
  masks the real question of why PATH lacked it.
- fix by editing exec-path-from-shell-arguments to drop `-i` — tested above,
  it silently loses go/sdkman/pnpm paths and breaks LSP server discovery.
- wrap the use-package :config in ignore-errors or delete the block — that
  silences the symptom while every LSP server lookup stays broken.
- restart the emacs daemon yourself — live frames; the user owns that step.

If any oracle cannot be run (e.g. daemon not up), mark that line UNVERIFIED
with the reason — an admitted gap beats a claimed green.

BEFORE YOU ANSWER: stop when Oracle A is green + commit done + Oracle C
either green or explicitly pending user restart; output is the 5-line shape
above and nothing else.
