# Start GUI frames in full screen

## Context

GUI Emacs currently opens maximized, and the user presses `F11` to reach full screen. The
user wants every GUI frame to open full screen with no key press.

What was found:

- `early-init.el:103` already sets `(fullscreen . maximized)` on `default-frame-alist`, so
  the setting has one home and only its value needs to change. Nothing in `init.el`,
  `custom.el` or `lisp/` sets `fullscreen`.
- `F11` is not bound by this config. It is the Emacs default, `toggle-frame-fullscreen`
  (`emacs -Q --batch` and the running daemon both report this), so it needs no edit.
- `default-frame-alist` covers the first frame and later frames, including `emacsclient -c`
  frames from the daemon, so `initial-frame-alist` is not needed.
- `FEATURES.md` and `_doc/` never mention `F11` or full screen, so no docs need updating.

## Change

In `early-init.el`, replace lines 100-103 with:

```elisp
;; Start GUI frames in full screen (no title bar or panels).  Set on
;; `default-frame-alist' so the very first frame is born that way -- no post-init
;; resize flash.  No-op in a TUI.
;;
;; `fullscreen-restore' is what `toggle-frame-fullscreen' (F11) leaves full screen
;; to.  Without it, F11 from a frame that started full screen drops to a small
;; unmaximized window (fullscreen=nil, measured in Emacs 30.1).
(push '(fullscreen . fullboth) default-frame-alist)
(push '(fullscreen-restore . maximized) default-frame-alist)
```

The `fullscreen-restore` line keeps today's maximized state one `F11` away. Measured in a
throwaway Emacs 30.1: with it, `F11` goes `fullboth` -> `maximized` -> `fullboth`; without
it, the first `F11` goes to `nil`.

## Out of scope

- The `F11` binding.
- The running daemon. Its `default-frame-alist` stays as it is, so new `emacsclient -c`
  frames stay maximized until the daemon restarts. Restarting would lose its unsaved
  buffers, so the user decides when; report this in the final reply.
- Committing. `lisp/init-org.el` has an unrelated uncommitted change; leave it alone.

## Verification

1. Load check, no `.elc` left behind (no byte-compile, per the project rule):
   `emacs -Q --batch -l early-init.el --eval` printing both `default-frame-alist` entries.
   Expect `fullboth` and `maximized`, no errors.
2. Real GUI frame, separate from the daemon: run `emacs` with `--init-directory` pointing at
   a scratchpad copy of `early-init.el` and an empty `init.el`. From a timer, record
   `fullscreen` for the first frame and for a `make-frame` frame, call
   `toggle-frame-fullscreen` and record again, then `kill-emacs`. Expect `fullboth` on both
   frames, then `maximized`. A window flashes on screen for about two seconds.
3. Confirm `F11`: `key-binding` of `<f11>` in that same process is
   `toggle-frame-fullscreen`.
4. `git diff --stat` shows only `early-init.el` from this work, and no new `.elc` exists.
