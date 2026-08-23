---
captured: 2026-08-21 23:59
session: d79cf216-42ac-4576-a3c3-98ddc13f8524
project_dir: /home/fenrir/.emacs.d
cwd: /home/fenrir/.emacs.d
transcript: /home/fenrir/.claude/projects/-home-fenrir--emacs-d/d79cf216-42ac-4576-a3c3-98ddc13f8524.jsonl
source: ExitPlanMode (PostToolUse hook)
plan_source: /home/fenrir/.claude/plans/emacs-rosy-snail.md
---

# elisp-native org-index rebuild (`fenrir/org-index-rebuild` + save hook)

## Context

The org-roam vault's `:ID:` / `[[id:]]` GNU Global index (`.org-index/` with
GTAGS/GRTAGS/GPATH) is today maintained only from the Claude Code side: the
`~/.claude/bin/org-index` CLI and the PostToolUse hook `org-index-rebuild.sh`.
Emacs knows nothing about it — editing a vault `.org` file in Emacs leaves the
index stale until a Claude session happens to touch the vault. The user wants an
**elisp-native** equivalent of `org-index rebuild`: an interactive command plus
an after-save auto-rebuild, calling `gtags`/`global` directly (no dependency on
the bash CLI).

User decisions (AskUserQuestion): target = the GTAGS `.org-index` (same as CLI);
implementation = elisp-native gtags/global calls; triggers = manual M-x **and**
after-save auto incremental rebuild. User also said: auto-execute after plan.

## CLI semantics to replicate (read from `~/.claude/bin/org-index`)

- Root discovery: truename the path, file → its directory, walk up to the
  innermost ancestor containing a `.org-index/` **directory**.
- Env quartet (per-invocation, absolute paths):
  `GTAGSCONF=~/.claude/org-index/gtags.conf`, `GTAGSLABEL=org-roam`,
  `GTAGSROOT=<root>`, `GTAGSDBPATH=<root>/.org-index`.
- cwd must be the root. Incremental: `global -u` when `<root>/.org-index/GTAGS`
  exists; else full `gtags <root>/.org-index`.
- Non-blocking flock on `<root>/.org-index/.lock`; lock held → skip silently.
- Existing roots: `/home/fenrir/code/org-roam` (vault), `/home/fenrir/code/pg`.

## Key constraints

- **Never touch the daemon-wide `GTAGSCONF`/`GTAGSLABEL` setenv** from
  `lisp/init-tags.el:62-67` (`java-pygments`, CLAUDE.md trap). Override
  per-process only, by let-binding `process-environment` (prepend the quartet —
  earlier entries shadow later duplicates) around `make-process`.
- The org gtags.conf (`~/.claude/org-index/gtags.conf`) is deliberately separate
  from `~/.emacs.d/gtags.conf`; never mix.
- Model: `fenrir/gtags-build` + `fenrir/gtags--build-sentinel`
  (`lisp/init-tags.el:238-297`) — async make-process, sentinel messages,
  0-byte-stub wipe.
- This is a DIFFERENT mechanism from `fenrir/org-id-index-directory`
  (`lisp/init-org.el:89`, feeds `org-id-locations`) — the new code sits next to
  it with a contrasting comment.

## Implementation — new section at end-of-org area in `lisp/init-org.el`
(after `fenrir/org-id-index-directory` at line 99, before the org-modern block)

Long `;;` rationale header per repo convention: what `.org-index/` is, elisp
twin of `org-index rebuild`, per-process env (contrast daemon-wide
java-pygments), and the org-id-locations vs GTAGS distinction.

1. **Constants/vars**: `fenrir/org-index--conf`
   (`~/.claude/org-index/gtags.conf`), `fenrir/org-index--dir` (`".org-index"`),
   `fenrir/org-index--procs` (alist root → live process, redundant-spawn guard),
   `fenrir/org-index--warned` (one-shot missing-binary warning for the hook).
2. **`fenrir/org-index--root (path)`**: `file-truename` → dir-of-file →
   `locate-dominating-file` with a **predicate** checking
   `file-directory-p` of `.org-index` (string form would match a plain file;
   CLI requires `-d`). Returns directory string or nil. No caching (a few
   stats, microseconds).
3. **`fenrir/org-index--environment (root)`**: returns
   `(append '("GTAGSCONF=…" "GTAGSLABEL=org-roam" "GTAGSROOT=…"
   "GTAGSDBPATH=…") process-environment)`.
4. **`fenrir/org-index--rebuild (root &optional quiet)`** — core async runner:
   - skip if a live process for this root exists (alist guard);
   - 0-byte GTAGS → delete GTAGS/GRTAGS/GPATH stubs, force full build;
   - command: `("flock" "-n" "-E" "200" <lock> …)` wrapping either
     `("global" "-u")` (incremental) or `("gtags" <db>)` (full) — same
     flock(2) file as the CLI, so Emacs and the Claude hook truly serialize;
     `-E 200` distinguishes lock-skip from real failure;
   - `default-directory` = root, `process-environment` let-bound, output to a
     `generate-new-buffer " *fenrir-org-index*"`, sentinel below;
   - non-quiet: message "incremental/full rebuild in <root> …".
5. **`fenrir/org-index--sentinel (root buf quiet)`** — closure factory modeled
   on `fenrir/gtags--build-sentinel` (init-tags.el:238): clear the procs alist
   entry, kill buf; exit 0 → success message unless quiet; exit 200 → silent
   (lock held elsewhere, that run covers the edit); other → always `message`
   the last output line (never silent on real failure, never `user-error` in a
   sentinel).
6. **`fenrir/org-index-rebuild (path)`** — interactive command:
   default `buffer-file-name`/`default-directory`, `C-u` prompts via
   `read-directory-name`; `user-error` when `global`/`gtags`/`flock` missing
   (install hint), when the conf file is absent, or when no root found (message
   names `.org-index/` and the `org-index init` remedy); then
   `(fenrir/org-index--rebuild root)`.
7. **`fenrir/org-index--after-save ()`** + `(add-hook 'after-save-hook …)`:
   gates ordered cheapest-first — `buffer-file-name` non-nil, `string-suffix-p
   ".org"`, not `file-remote-p` (TRAMP skip); binaries missing → one-time
   message via `--warned`, then inert; root found → `(fenrir/org-index--rebuild
   root 'quiet)`; no root → silent no-op. No debouncing: 0.02 s runtime + flock
   + live-process guard make overlap safe (a running `global -u` picks up the
   newest write). Coexists with gtags-mode's own on-save single-update (that
   one only fires under a *code* GTAGS root, with the daemon env).

## Docs to update

- **`FEATURES.md`** (mandatory sync rule): org section — `M-x
  fenrir/org-index-rebuild` (+ `C-u` prompt) and the on-save auto-refresh note.
- **`_doc/ARCHITECTURE.md`**: extend the `init-org` module row.
- **`_doc/TAGS.md`**: short "two gtags universes" note — code index
  (`~/.emacs.d/gtags.conf`, java-pygments, daemon-wide setenv) vs org ID index
  (`~/.claude/org-index/gtags.conf`, org-roam label, per-process env,
  `.org-index/` db).
- No keybinding: Tier 3 (M-x only), no `<f5>` hub entry — with two automatic
  hooks (save + Claude PostToolUse), manual rebuild is a rare repair action.
  (`x` is free in `fenrir/hub-org` if it ever earns a slot; no wrapper needed
  since init-org.el is required at startup.)

## Verification

1. Visit a file under `~/code/org-roam`, `M-x fenrir/org-index-rebuild` →
   "incremental" message; `.org-index/GTAGS` mtime advances.
2. Full-build path on `~/code/pg`: move `GTAGS` aside, run command → full
   build recreates it; `org-index status ~/code/pg` reports fresh.
3. Save hook: whitespace-edit a vault note, `C-x C-s` → silent, GTAGS mtime
   updates; save a non-.org file and `/tmp/x.org` (no root) → no process.
4. Lock: `flock ~/code/org-roam/.org-index/.lock sleep 30 &`, then save a
   note → silent skip (exit 200); after release, next save updates.
5. Daemon env untouched: `M-: (getenv "GTAGSLABEL")` → `"java-pygments"`,
   `(getenv "GTAGSCONF")` → `~/.emacs.d/gtags.conf`.
6. Cross-tool: add a new `:ID:` to a note, save, `org-index d <new-id>`
   resolves (proves the org-roam label parsed the update).
7. Syntax check without artefacts (never leave an ad-hoc `.elc`); reload via
   the daemon (`load-file` on init-org.el or eval the new section).
