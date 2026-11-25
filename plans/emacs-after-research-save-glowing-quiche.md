# Plan: deep-research "how to improve Emacs performance" → org-roam note

## Context
User ran `/deep-research` with args "關於如何提升emacs的效能, after research, save into org roam". Plan mode is active, so nothing is run or written yet. The research itself is read-only (web search/fetch); only the final org-roam write is a change.

## Scope (refined from the user's config, no extra questions needed)
Emacs 30.1, TTY-first daemon + `emacsclient -nw` in tmux plus a GUI frame on the same daemon; eglot (+booster), tree-sitter, corfu/vertico, magit, org-roam. Already done in repo: GC tuning in `early-init.el`, `gcmh-mode`, `file-name-handler-alist` suspension, `eglot-booster`, native-comp, no-littering. The note should cover what is generalizable, and flag what is already applied here.

## Steps
1. Invoke `Workflow({ name: "deep-research", args: "How to improve GNU Emacs performance (Emacs 30.x): startup time (early-init, GC, native-comp, lazy loading/use-package), runtime responsiveness (long lines, so-long, bidi, redisplay, font-lock/tree-sitter, jit-lock), LSP/eglot (plist deserialization, eglot-booster, jsonrpc), process I/O (read-process-output-max, plists), daemon/TTY specifics, org-mode and magit slowness, profiling tools (profiler, esup, benchmark-init, M-x profiler-start). Prefer primary sources: Emacs manual/NEWS, emacs-devel, package READMEs, maintainer blogs. Report with citations and confidence." })`.
2. Review the synthesized report: drop refuted/low-confidence claims; mark which items are already in this config (check `early-init.el`, `lisp/init-defaults.el`, `_doc/GOTCHAS.md` via grep before claiming "already done").
3. Save to org-roam via the `org-roam-vault` skill (vault `/home/fenrir/code/org-roam`, atomic-kb note format, `:ID:` node, English prose, Chinese only in glosses/quoted data). Read the vault's existing Emacs notes first (`rg` the vault for "emacs performance"/"gcmh") to link rather than duplicate; org-roam is for generalizable knowledge, so no project-specific state.
4. Run the `refresh-org-indexes` skill (`org-index rebuild` + `org-roam-db-sync`) so the new note is findable.

## Critical files / tools
- Read-only references: `/home/fenrir/.emacs.d/early-init.el`, `lisp/init-defaults.el`, `_doc/GOTCHAS.md`
- Write target: new `.org` under `/home/fenrir/code/org-roam/`
- Skills: `org-roam-vault`, `atomic-kb`, `refresh-org-indexes`

## Verification
- Note has `:ID:`, every claim has a cited URL, `[[id:...]]` links resolve.
- `org-index d <ID>` finds the new note; `emacsclient -e '(org-roam-db-sync)'` succeeds.
- Final reply: one-line summary + note path (English).

## Cost note
The workflow fans out ~5 search agents + ~15 fetches + 3-vote verification per claim (dozens of agent runs, roughly the "medium" size guideline or above). Requires approval to run.
