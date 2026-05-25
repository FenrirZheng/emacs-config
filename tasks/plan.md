# Plan: Emacs Lisp command — split a tmux pane running the Claude CLI

## Context

[`tasks/20260521-tmux-create-claude/SPEC.md`](20260521-tmux-create-claude/SPEC.md)
asks for an interactive Emacs command that drives `tmux` from inside Emacs: it
should make a vertical (left/right) split of the current pane — the equivalent
of tmux's `Prefix %` — launch the `claude` CLI in the new pane, and name the
pane `claude-<pane-id>` (e.g. `claude-%2`). It must degrade gracefully when run
outside tmux or when `claude` is not installed.

This is a personal Emacs 30.1 config (thin loader + per-area `init-<area>`
modules under [`lisp/`](../lisp/)). The closest existing precedent is
[`lisp/claude-jobs-view.el`](../lisp/claude-jobs-view.el), which already shells
out to `tmux` via `call-process` and detects tmux with `(getenv "TMUX")`. The
new command reuses those same patterns.

Decisions confirmed with the user:

- **Placement** — a new dedicated module `lisp/init-tmux-claude.el` (not folded
  into `init-ai.el` / `init-terminal.el`).
- **Invocation** — `M-x` only, no key binding (matches `gptel` / `claude-jobs-view`).
- **Pane lifecycle** — `claude` runs as the pane's command, so the pane closes
  when `claude` exits. A pre-flight `executable-find` check aborts in Emacs
  before any pane is created if `claude` is missing — this is the SPEC §4.2
  "no flash-close" guard.

Note: command/message strings are written in English to match every existing
string in the config (`claude-jobs-view.el`, `init-ai.el`); the SPEC's Chinese
example text expresses intent, not a literal byte requirement.

## Task breakdown

### Task 1 — Create `lisp/init-tmux-claude.el`

New module file with the standard header (lexical-binding cookie, `Commentary`,
`Code`), one interactive command, and the `(provide …)` footer. Reference shape:

```elisp
;;; init-tmux-claude.el --- tmux helper: split a pane running the Claude CLI -*- lexical-binding: t; -*-

;;; Commentary:
;; A single interactive command, `fenrir/tmux-claude-split', that splits the
;; current tmux pane left/right (like `Prefix %') and launches the `claude'
;; CLI in the new pane.  Shells out to `tmux' via `call-process' -- same
;; pattern as lisp/claude-jobs-view.el.

;;; Code:

(defun fenrir/tmux-claude-split ()
  "Split the current tmux pane vertically and launch the `claude' CLI in it.

Mirrors tmux's `Prefix %': makes a left/right split of the pane Emacs
occupies, runs `claude' in the new pane, and sets the new pane's title to
`claude-<pane-id>' (e.g. `claude-%2').

Requires Emacs to be running inside tmux and the `claude' executable to be
on `exec-path'.  Both are verified up front; if either is missing the
command aborts and no pane is created.  The new pane runs `claude' as its
command, so it closes when `claude' exits."
  (interactive)
  (unless (getenv "TMUX")
    (user-error "Not inside a tmux session -- cannot split a pane"))
  (let ((claude (executable-find "claude")))
    (unless claude
      (user-error "`claude' not found on `exec-path' -- install it first"))
    (with-temp-buffer
      (let* ((exit (call-process "tmux" nil t nil
                                 "split-window" "-h"
                                 "-P" "-F" "#{pane_id}"
                                 (shell-quote-argument claude)))
             (pane-id (string-trim (buffer-string))))
        (when (or (not (zerop exit)) (string-empty-p pane-id))
          (user-error "tmux split-window failed (exit %s): %s" exit pane-id))
        (unless (zerop (call-process "tmux" nil nil nil
                                     "select-pane" "-t" pane-id
                                     "-T" (concat "claude-" pane-id)))
          (message "tmux: pane %s created, but setting its title failed" pane-id))
        (message "tmux: claude launched in pane %s" pane-id)))))

(provide 'init-tmux-claude)
;;; init-tmux-claude.el ends here
```

Design notes:
- `executable-find` returns the **absolute path**; passing that (rather than the
  bare word `claude`) to `tmux split-window` removes any Emacs-`exec-path` vs
  tmux-server-`PATH` mismatch — the exact binary Emacs verified is the one tmux
  runs. `shell-quote-argument` guards the path (tmux runs `split-window`'s
  command argument via `/bin/sh -c`), mirroring `claude-jobs-view.el`.
- `split-window -h` = left/right split (tmux's `-h` is "horizontal layout"),
  which is what the SPEC and `Prefix %` mean by "vertical split". No `-d`, so
  focus moves to the new pane, matching `Prefix %`.
- `-P -F "#{pane_id}"` prints the new pane id to stdout; `call-process` with
  destination `t` captures it into the temp buffer.
- Title is set with `select-pane -t <id> -T claude-<id>` immediately after the
  split returns — well before `claude` could exit. A failed title-set is a soft
  `message`, not a hard error, since the pane already exists.
- Both guards use `user-error` (idiomatic interactive abort; surfaces a clean
  echo-area message — satisfying SPEC §4.1's "跳出 message 提示" intent — with
  no debugger pop).

**Acceptance criteria**
- File exists at `lisp/init-tmux-claude.el`, byte-compiles clean, ends with
  `(provide 'init-tmux-claude)`.
- `fenrir/tmux-claude-split` is an interactive command.

### Task 2 — Register the module in `init.el`

The module has no `use-package` `:after` edges, so load order is free; append it
to the **end** of the load list to avoid reflowing the order-sensitive block.

- In the header comment (after the `init-aidermacs` line): add a
  `init-tmux-claude` description line.
- In the `(mapc #'require …)` list: add `init-tmux-claude` after `init-aidermacs`.

**Acceptance criteria**
- `init.el`'s header comment and `mapc` list both include `init-tmux-claude`.
- A fresh Emacs start loads the module with no error; `(featurep 'init-tmux-claude)`
  is `t`.

### Task 3 — Update docs

- [`FEATURES.md`](../FEATURES.md) §14 (AI / agent tooling): add
  `init-tmux-claude.el` to the section's file-reference list and a short
  paragraph documenting `M-x fenrir/tmux-claude-split` (what it does, the two
  guards, the `pane-border-status` caveat).
- [`CLAUDE.md`](../CLAUDE.md): the "16 modules under `lisp/`" sentence →
  "17 modules", and add `init-tmux-claude` to the parenthesised list.

**Acceptance criteria**
- `FEATURES.md` and `CLAUDE.md` mention the new module/command; module count is
  consistent with `init.el`.

## Dependency order

Task 1 → Task 2 (the file must exist before `require` resolves) → Task 3 (docs
describe the finished behaviour). Task 3 may also run in parallel with Task 2.

## Verification

1. **Syntax / load** — `M-x load-file RET lisp/init-tmux-claude.el RET` (no
   error), then `M-x load-file RET init.el RET` or restart Emacs. Confirm
   `C-h f fenrir/tmux-claude-split RET` shows the command.
2. **Happy path** — in a TTY Emacs frame running inside tmux, with `claude` on
   `PATH`: `M-x fenrir/tmux-claude-split`. Expect a new left/right pane with
   `claude` running, focus moved to it, echo-area "tmux: claude launched in
   pane %N". Check `tmux list-panes -F '#{pane_id} #{pane_title}'` shows
   `claude-%N` for the new pane.
3. **Not in tmux** — run the command from GUI Emacs or a non-tmux terminal:
   expect `user-error` "Not inside a tmux session…", no pane created.
4. **`claude` missing** — temporarily shadow it (e.g. `let`-bind `exec-path` to
   exclude its dir, or test where it is not installed): expect `user-error`
   "`claude' not found…", no pane created.

Caveat to document, not fix: the pane *title* is only visible when the user's
`tmux.conf` enables `pane-border-status` (SPEC §3) — `select-pane -T` always
succeeds regardless. Also, an Emacs **daemon** started outside tmux will not see
`$TMUX` even when its `emacsclient -nw` frame is inside tmux; this matches the
existing `(getenv "TMUX")` convention in `claude-jobs-view.el` and is a known
limitation.

## Critical files

- `lisp/init-tmux-claude.el` — **new**, the command.
- [`init.el`](../init.el) — register the module (comment + `mapc` list).
- [`FEATURES.md`](../FEATURES.md) — §14 doc entry.
- [`CLAUDE.md`](../CLAUDE.md) — module count + list.
