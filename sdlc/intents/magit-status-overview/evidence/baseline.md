# Magit status baseline

Recorded: 2026-09-10, Asia/Taipei (UTC+08:00), approximately 12:16–12:18.
Owning repository: `/home/fenrir/.emacs.d`, baseline `d65ffc852c29fdb2c0c5600074f7181b6ffc0001`.
Purpose: distinguish actual section visibility from plain buffer contents before designing the overview.

## Read-only runtime observation

Local `emacsclient --eval` queried frame/window metadata, Magit section objects, and `invisible-p` at file headings. No buffer/window selection, folding, refresh, or Git mutation was requested.

- Emacs 30.1; loaded Magit `20260506.643`.
- Visible GUI frame: `magit: hedge-detection-root`, body 279 columns × 71 lines, window start 1, point 91, end 186293, buffer size 186292; `fenrir/magit-hints-mode` enabled.
- Visible TTY frame: `*scratch*`, 80 × 22. This is evidence of coexistence, not a TTY Magit interaction test.
- `magit-section-initial-visibility-alist`: `((stashes . hide))`; `magit-section-cache-visibility`: `t`.
- Untracked group: `hidden=nil`, one file heading visible.
- Unstaged group: `hidden=t`, one child file with `hidden=nil`, heading invisible through its parent.
- Staged group: `hidden=t`, ten child files with `hidden=nil`, all headings invisible through their parent.

Thus the current GUI buffer has whole change groups folded. The earlier plain-text extraction cannot establish that XML occupied visible screen space. Opening a group alone may expose its already-open child bodies; a file-level overview is a distinct target state.

Limitations: historical observations only; no screenshot, rendered header capture, key interaction, controlled before/after comparison, or timing measurement. Untracked business files and original XML were not copied here. The section observation can be repeated with `magit-root-section` → `children`, selecting types `untracked`, `unstaged`, `staged`, then reading each group's and child's `hidden` slot and `invisible-p` at its `start` marker. Frame/window dimensions use `frame-list`, `window-list`, `window-body-width` and `window-body-height`.

## Local source evidence

Package sources below are installed dependencies, not tracked project artifacts. These hashes identify the actual inspected bytes; package upgrades require renewed checks.

| Source | SHA-256 | Relevant contract |
|---|---|---|
| `lisp/init-git.el` | `8eb0cd89304a25465dfa8c4c90aed6729dd6fa0dfb70c8ea51a69aeb551cc48b` | `fenrir/magit-hints--item`, `--layout`, `--render`: verify live bindings, responsive complete items, no Git subprocess in redisplay; local mode restores saved header |
| `elpa/magit-20260506.643/magit-status.el` | `99a9be694e91201049e1b99a7dff9bc51b9a3c8b91014941c8dfbf6dea689750` | `magit-status-initial-section` applies on buffer creation, not ordinary refresh/revisit; untracked insertion follows Git settings |
| `elpa/magit-20260506.643/magit-diff.el` | `9297cf7c151bce5f79e403b444106f0637555d2dddddafff305b0487f6449ade` | Native staged/unstaged groups, file and hunk sections, native diffstat path |
| `elpa/magit-20260506.643/magit-mode.el` | `63874bcbb50a7c79cb7bafaabeb928df90964301d61dd2210b71db720109a9c8` | Follow-up source check around 12:23: `magit-preserve-section-visibility-cache` and `magit-restore-section-visibility-cache` retain repository-local visibility across buffer recreation |
| `elpa/magit-section-20260503.2051/magit-section.el` | `6d984f1a8fd034000e891be15c3aa3902807a7f7a21d21aabea4903aee0debad` | `magit-insert-section--create`: visibility hook, old matching section, initial alist, default precedence; `magit-section-show-level-2-all` affects root tree; section visibility is buffer state |

Validation: source declarations read locally; hashes computed with Python hashlib SHA-256. These facts support a proposed design, not proof that the new behavior is implemented.

## Follow-up on the cache disagreement

Around 12:31, the design discussion claimed the preserve hook existed only in `magit-refs.el`. That search omitted `magit-section.el:521–522`, whose mode body conditionally adds `magit-preserve-section-visibility-cache` to `kill-buffer-hook`. Thus the source does contain another registration path.

A read-only runtime query in the observed Magit buffer then returned `:kill-hook-installed nil`, `:preserve-visibility t`, `:show-count t`, `:cache-size 56`, and `:status-jump magit-status-jump`. The hook check used `(and (memq 'magit-preserve-section-visibility-cache kill-buffer-hook) t)`; it proves only that this symbol was not directly present in that buffer's effective hook list at observation time. No kill/recreate cycle was performed, and the reason for the source/runtime difference was not investigated.

Specification consequence: preserve whatever native cache/old-section state is actually available, and define freshness by absence of such state. Do not promise that every killed status buffer will restore its folds, and do not assert that the source contains no status-capable preservation path. Implementation validation must distinguish bury/revisit, refresh, and kill/recreate.

Review A resolved the apparent hook discrepancy around 12:35: the local hook list can contain `t`, instructing Emacs to run the global value too. A second read-only query returned `:local-hook-p t`, `:local-includes-global t`, `:global-preserve-hook t`, using `local-variable-p`, `(memq t kill-buffer-hook)` and `(memq 'magit-preserve-section-visibility-cache (default-value 'kill-buffer-hook))`. Thus the earlier direct-member check was incomplete; the preservation hook is present through global inheritance in the observed buffer. The native kill/recreate path is supported by both source registration and this runtime hook evidence, although the cycle itself was not executed.

Review B also identified an initial-default asymmetry: `magit-insert-files` at `magit-status.el:793–803` passes HIDE=t for untracked, while diff group constructors omit HIDE and tracked file bodies pass hide in status mode. These are pinned source facts; the observed cached untracked show state does not prove a fresh-cache default. The final spec requires an untracked show initial rule and a later control fixture, not a new tracked-file hiding subsystem.
