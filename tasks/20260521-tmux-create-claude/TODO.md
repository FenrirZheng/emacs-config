# TODO — Emacs tmux+claude command (live progress log)

> Task list: [TASKS.md](./TASKS.md). Design doc: [plan.md](../plan.md).
> Append-only progress/decision notes below.

## Current focus

Daemon tmux-detection fix (T5) applied and verified end-to-end in an isolated
session. Awaiting the user's re-test in their live daemon Emacs.

## Next steps

1. Reload the fixed module in the running daemon:
   `M-x load-file RET ~/.emacs.d/lisp/init-tmux-claude.el RET`.
2. Live acceptance: `M-x fenrir/tmux-claude-split` from an `emacsclient -nw`
   frame inside tmux — confirm a new left/right pane runs `claude`, titled
   `claude-%N`.
3. Commit when ready (`lisp/init-tmux-claude.el`, `init.el`, `FEATURES.md`,
   `CLAUDE.md`).

## Decisions / notes

- 2026-05-21 — Placement: a new dedicated module `lisp/init-tmux-claude.el`
  (user choice), not folded into `init-ai.el` / `init-terminal.el`.
- 2026-05-21 — Invocation: `M-x` only, no key binding (user choice; matches
  `gptel` / `claude-jobs-view`).
- 2026-05-21 — Pane lifecycle: `claude` runs as the pane's command, so the pane
  closes when `claude` exits (user choice). A pre-flight `executable-find` check
  aborts in Emacs before any pane is created — this is the SPEC §4.2
  no-flash-close guard.
- 2026-05-21 — Pass `executable-find`'s absolute path (not the bare word
  `claude`) to `tmux split-window`, so the exact binary Emacs verified is the
  one tmux runs — eliminates an Emacs-`exec-path` vs tmux-server-`PATH`
  mismatch. `shell-quote-argument` guards it (tmux runs the command via `sh -c`).
- 2026-05-21 — Messages written in English to match every existing string in
  the config; the SPEC's Chinese example text expresses intent, not literal
  bytes. Both guards use `user-error` (clean echo-area message, no debugger pop).
- 2026-05-21 — `init-tmux-claude` appended to the **end** of `init.el`'s load
  list: it has no `use-package :after` edges, so order is free and appending
  avoids reflowing the order-sensitive block.
- 2026-05-21 — Added `(require 'subr-x)` to the module (`string-trim`,
  `string-empty-p`) so it byte-compiles with no warnings — same as
  `claude-jobs-view.el`.
- 2026-05-21 — All 4 tasks implemented + verified. Byte-compile clean; module
  loads (`featurep` t, `commandp` t); `init.el` parses. Both guards abort with
  `user-error` in batch Emacs; `split-window -h -P -F '#{pane_id}'` +
  `select-pane -T` verified in an isolated tmux session (new pane titled
  `claude-%21`, focus moved to it). The live interactive `M-x` run was left to
  the user — running it would split the live tmux layout and spawn a real
  `claude` TUI.
- 2026-05-21 — `CLAUDE.md` wording softened from "each correspond" to "mostly
  correspond" to the pre-split monolith: `init-aidermacs` (2026-05-20) and
  `init-tmux-claude` (2026-05-21) are post-split standalone additions.
- 2026-05-21 — **Bug from acceptance test (T5).** User ran the command and got
  "Not inside a tmux session" despite being in tmux. Cause: their Emacs is a
  daemon started outside tmux, so `(getenv "TMUX")` reads the daemon's own
  (tmux-less) environment. Fix: a `fenrir/tmux-claude--getenv` helper reads from
  the invoking frame's `environment` parameter — server.el sets that to the
  `emacsclient` connection's environment (confirmed: `server.el` 30.1 line 1012
  `(environment . ,(process-get proc 'env))`; line 939 shows core Emacs doing
  the same `getenv-internal`/client-env read for `DISPLAY`). Falls back to
  `getenv` for non-client frames. `TMUX`/`TMUX_PANE` are then re-injected into
  `process-environment` so the child `tmux` processes hit the right server and
  split the Emacs frame's pane. Verified end-to-end in an isolated tmux session
  with a fake `claude` (new pane created + titled `claude-%24`).

- None.
