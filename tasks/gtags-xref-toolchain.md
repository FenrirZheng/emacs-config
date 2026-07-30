# gtags → xref toolchain rebuild — plan

Status: **implemented 2026-07-30** (see [§9 Implementation record](#9-implementation-record-2026-07-30)).
Scope: replace the current GNU Global machinery end-to-end — index **create**, index
**update**, and **import into xref** — with a smaller, working stack. The current
implementation is approved for deletion ("幾乎不能用", user, 2026-07-30).

Companion docs that will need rewriting when this lands:
[TAGS.md](../_doc/TAGS.md), [FEATURES.md](../FEATURES.md) (§ggtags / `C-c g`),
[GOTCHAS.md](../_doc/GOTCHAS.md), the two gtags bullets in [CLAUDE.md](../CLAUDE.md).

---

## 1. Current state (verified 2026-07-30)

### Toolchain on this box — all healthy

| component | state |
|---|---|
| `gtags` / `global` | 6.6.13, `/usr/bin` |
| Universal Ctags | `/usr/bin/ctags-universal` |
| pygments parser | `/usr/share/global/gtags/script/pygments_parser.py` present; `python-is-python3` installed → shebang resolves |
| tracked conf | [`gtags.conf`](../gtags.conf) (system copy + extended skip list: `node_modules/ vendor/ venv/ dist/ build/ target/ …`) |
| ggtags (ELPA) | `ggtags-20230602.133` — last upstream release 2023, effectively unmaintained |

So the CLI layer works; the pain is in the Emacs-side machinery.

### What exists in Emacs today (deletion inventory)

| item | location | size |
|---|---|---|
| ggtags `use-package` + `M-.` neutralize + ~30 `fenrir/gtags-*` defuns/defcustoms (async build, corrupt-stub validation, nested-index sweep, forbidden-roots guard, gopls steering, etags-prompt hijack advice) | [`lisp/init-languages.el`](../lisp/init-languages.el) ~L464–1473 | ~1000 lines |
| `C-c g` keymap (g d . r s f / p) | same file, L1455–1473 | 8 bindings |
| `ggtags-mode` hooks | [`languages/init-c-cpp.el`](../lisp/languages/init-c-cpp.el) L88–91, [`init-python.el`](../lisp/languages/init-python.el) L20–21, [`init-go.el`](../lisp/languages/init-go.el) L25, [`init-typescript.el`](../lisp/languages/init-typescript.el) L37 | 8 hooks |
| `<f5> d` → "gtags index check" entry | [`lisp/init-keys.el`](../lisp/init-keys.el) L209 | 1 entry |
| `ggtags-find-tag-dwim` push-mark advice note (merged jump history) | [`lisp/init-keys.el`](../lisp/init-keys.el) ~L330 | comment + advice |
| `ggtags` in `package-selected-packages` | [`custom.el`](../custom.el) | 1 symbol |

**Kept, not deleted**: [`gtags.conf`](../gtags.conf) (the skip list is the only lever that
reaches the `global -u` re-traversal — incident: 2.5 MB → 3.85 GB), and the
`tags-file-name` / `tags-table-list` nil-out (etags must never prompt).

### Related external artifact

The Claude skill `tags-symbol-lookup` ships its own `gtags.sh` which builds with
`GTAGSLABEL=native-pygments` but writes the DB into a **`./tags/` subdirectory** via
`gtags -f gtags.files ./tags`. Emacs-side resolution (dominating-file / `global -pr`)
expects the DB at the **project root**. This mismatch is one plausible reason an
existing index "isn't picked up" — see D5.

---

## 2. Why the current one fails (assumptions — confirm/correct)

The user verdict is "almost unusable"; the specific failure was not stated. Candidate
pain points observed from the code, each marked [未驗證] as the actual complaint:

1. [未驗證] **Too much ceremony**: build is manual (`C-c g g`), update is manual, no
   on-save refresh — index is stale the moment you edit, so `M-?` answers are wrong.
2. [未驗證] **ggtags frontend fights the config**: its keymap had to be neutralized,
   its project cache had to be manually invalidated after every build, and its xref
   backend declines silently when resolution misses the index.
3. [未驗證] **Index built by the CLI skill (`./tags/` layout) is invisible to Emacs**
   (D5 mismatch above).
4. [未驗證] **The 1000-line safety net itself** (guards, prompts, steering messages)
   gets in the way more than it protects.

→ First implementation step is a 10-minute repro with the user: one `M-.` / `M-?` /
build round-trip on a real repo, capture what actually breaks. The redesign below is
valid under any of the four, but the acceptance tests in §6 should target the
confirmed one(s).

---

## 3. Design decisions

Options listed descriptively; recommendation in §4, separately.

### D1 — xref frontend (the "導入" layer)

| option | shape | notes |
|---|---|---|
| a. `gtags-mode` (GNU ELPA, maintained) | one global minor mode; integrates with project.el + xref + completion-at-point + imenu; ships **auto `global --single-update` on save** | replaces both ggtags and most of the hand-rolled update layer; Emacs ≥28; [未驗證] exact backend-ordering vs Eglot and env handling — spike task T1 reads its source first |
| b. keep ggtags | current frontend, keymap neutralized | unmaintained since 2023; needs cache-invalidation dance; keeps the machinery this plan wants to delete |
| c. hand-rolled xref backend over `global` CLI | ~150 lines: `xref-backend-functions` entry + 4 methods shelling to `global -x` / `-rx` / `-sx` / `-Poa` | full control, no package dependency; we own parsing and edge cases forever |

### D2 — build/create engine (the "建立" layer)

| option | shape |
|---|---|
| a. thin elisp command wrapping `gtags` via `make-process` (async, sentinel validates result) | |
| b. external script `shell/gtags-build.sh`, called from both Emacs and terminal; single source of truth shared conceptually with the `tags-symbol-lookup` skill | |
| c. `gtags-mode`'s built-in create command, with env prepared daemon-wide (see D4) | |

### D3 — update strategy (the "更新" layer)

| option | shape |
|---|---|
| a. on-save `global --single-update <file>` (built into `gtags-mode`) | per-file, no re-traversal, near-zero cost |
| b. manual command (`global -u`, async) for bulk refresh after branch switches / pulls | |
| c. idle-timer or focus-change bulk update | |

(a) and (b) compose; (c) is an alternative to (b).

### D4 — env injection (GTAGSCONF / GTAGSLABEL)

| option | shape |
|---|---|
| a. daemon-wide `setenv` once in init: `GTAGSCONF=~/.emacs.d/gtags.conf`, `GTAGSLABEL=native-pygments` — every gtags/global subprocess (create, single-update, `global -u`, xref queries) inherits automatically | one line each; removes the entire per-call injection plumbing of the current code |
| b. per-call `process-environment` injection (current approach) | env only where needed; but every new call site must remember it — the exact bug class that caused the 3.85 GB incident |

### D5 — canonical DB location

| option | shape |
|---|---|
| a. project root (`<root>/GTAGS`) | what dominating-file lookup, `global -pr`, and every Emacs frontend expect; requires teaching the `tags-symbol-lookup` skill's script to also write to root (or accept divergence) |
| b. `./tags/` subdir (the skill's current layout) via `GTAGSDBPATH`/`GTAGSROOT` env | keeps repo root clean; but the env must then be present in **every** querying process, including the Emacs daemon and any future tool |

### D6 — scope of retained guard rails

Each guard below was bought with a real incident. Decide keep/drop individually:

| guard | incident | keep? |
|---|---|---|
| GTAGSCONF skip list reaching the update path | 2.5 MB → 3.85 GB on one bare `global -u` | keep — subsumed by D4a (env is always present) |
| forbidden roots (`~/`, `/`, `/tmp`, …) | `project-try-vc` degenerates to `$HOME` (dotfiles repo) / `/` → runaway walk | keep — small predicate on the create command |
| 0-byte corrupt-stub detection + wipe | pygments shebang failure left a stub every later update rejects | keep, simplified: post-create check `GTAGS` size > 0 and `global -c` exits 0, else wipe + one-line hint |
| nested-index sweep + `C-c g d` diagnose | `backend/GTAGS` shadowed the root index | keep diagnose command; sweep-on-build optional |
| gopls steering ("Go repo → use gopls, not gtags") | — | drop; one doc line suffices |
| etags `visit-tags-table-buffer` prompt hijack advice | the 1990s "Visit tags table" prompt | replace with the simpler fix: keep `tags-file-name`/`tags-table-list` nil **and** remove `etags--xref-backend` from the equation by ensuring the gtags backend answers first when an index exists; if still reachable, keep a minimal advice that just messages the build key |

---

## 4. Recommendation (separate from the neutral tables above)

**D1a + D2c + D3a+b + D4a + D5a**, i.e.:

- `gtags-mode` from GNU ELPA as the single frontend: xref backend, project.el
  integration, capf, and on-save single-update all come from one maintained package.
- Env prepared once, daemon-wide (`setenv` in the new module) so create/update/query
  all inherit `GTAGSCONF` + `GTAGSLABEL` — the whole per-call injection layer and its
  bug class disappear.
- A thin `fenrir/gtags-*` layer (~150–250 lines, target) keeps only: root guard,
  post-create validation, nested-index diagnose, and the `C-c g` entry points.
- DB at project root; adjust or document the skill-script divergence.

Self-grill (answered before recommending):

- *"gtags-mode is yet another package — how is that different from ggtags?"* It is in
  GNU ELPA (not MELPA snapshot), actively maintained, and its feature set covers
  exactly the three plan pillars (create/update/xref) natively, so the custom code
  shrinks instead of growing around it. If spike T1 falsifies this, fall back to D1c.
- *"Does daemon-wide GTAGSLABEL leak into unrelated subprocesses?"* Only the
  gtags/global family reads these vars; no other tool in this config consumes them.
- *"Eglot ordering: will gtags-mode shadow gopls on `M-.`?"* gtags-mode contributes an
  xref backend, not a keymap grab, and Eglot **prepends** its backend buffer-locally on
  attach, so Eglot wins whenever a server is live. [未驗證] — this exact claim is
  acceptance test V3 and must be verified, not assumed.

---

## 5. Invariants (survive the rewrite, regardless of options chosen)

1. **`M-.` stays `xref-find-definitions`** and dispatches over
   `xref-backend-functions`; Eglot wins when attached; gtags answers as fallback. No
   frontend may bind `M-.` to a command that shells out directly.
2. **The update path must see the skip list** (GTAGSCONF), or the index re-bloats.
3. **Never index `$HOME` or filesystem roots.**
4. **Never leave a 0-byte index corpse** — validate after create, wipe on failure.
5. **Network-free startup**: new package install requires `M-x my/package-refresh`
   once, then restart; the config itself never refreshes archives.
6. **TTY-safe**: everything here is process + minibuffer work; no child frames.
7. **Jump history**: xref-based navigation already feeds `push-mark`, which the merged
   `<f6>`/`<f7>` history advises. Removing ggtags removes its direct-jump commands, so
   the special-case advice for `ggtags-find-tag-dwim` in
   [`init-keys.el`](../lisp/init-keys.el) goes away cleanly — verify `<f6>` still
   captures gtags-backed jumps (V6).

---

## 6. Task breakdown

### T0 — repro session (with user, ~10 min)
Confirm which §2 assumption is the real pain. Adjust acceptance tests below.

### T1 — spike: read `gtags-mode` source (blocking gate for D1a)
Verify: backend registration point and ordering vs Eglot; whether create/update run
async; env/`process-environment` handling; behavior when no index exists (must decline
silently, not prompt); Emacs 30.1 compatibility. **Exit criteria**: each [未驗證] in
§3/§4 flipped to verified-yes or the plan falls back to D1c.

### T2 — new module `lisp/init-tags.el`
- `setenv` GTAGSCONF/GTAGSLABEL (D4a) + `gtags-mode` `use-package` block.
- Thin layer: `fenrir/gtags-build` (root-guarded, validated create),
  `fenrir/gtags-update` (bulk `global -u`, async), `fenrir/gtags-diagnose`
  (nested-index lister, successor of `C-c g d`), `fenrir/gtags-prefer-here`
  (per-buffer "gtags before LSP" toggle) if T0 shows it's actually used.
- `C-c g` keymap: `g` build, `u` update, `d` diagnose (final set after T0).
- Add module to [`init.el`](../init.el) load list **before**
  [`init-keys.el`](../lisp/init-keys.el) (routing layer stays last).

### T3 — deletion pass
Remove every row of the §1 inventory; keep the two "kept" items. Re-point
`<f5> d` diagnose entry. Drop per-language `ggtags-mode` hooks (gtags-mode is global
and self-scoping [未驗證 — T1 confirms]; otherwise re-hook per language).

### T4 — CLI alignment (D5)
Either update the `tags-symbol-lookup` skill's `gtags.sh` to build at root with
`GTAGSCONF=~/.emacs.d/gtags.conf`, or document the divergence in both places.
(Skill lives in `.claude/` submodule → separate commit there.)

### T5 — docs
Rewrite [TAGS.md](../_doc/TAGS.md); update [FEATURES.md](../FEATURES.md) `C-c g`
table, [GOTCHAS.md](../_doc/GOTCHAS.md), [CLAUDE.md](../CLAUDE.md) trap bullets
(the "don't delete the ggtags `define-key` nil block" rule becomes obsolete — replace
with whatever new invariant T1/T2 produce), [`custom.el`](../custom.el)
`package-selected-packages`.

### T6 — commit
One commit in `~/.emacs.d` (module + deletions + docs together, per repo convention);
separate commit in `.claude/` submodule if T4 touches the skill.

---

## 7. Verification plan (acceptance tests)

Run on a real multi-language repo (`~/code/coinsasia` or a scratch Go+Py+TS tree):

- **V1 create**: `C-c g g` on an un-indexed repo → async build, `GTAGS` > 0 bytes,
  `global -c` exits 0, Go/Python/TS symbols present (`global -d <known-symbol>` hits).
- **V2 fallback navigation**: kill the LSP (`M-x eglot-shutdown`), `M-.` on a symbol →
  jumps via gtags backend; `M-?` lists references; `M-,` returns.
- **V3 Eglot priority**: with gopls attached, `M-.` resolves via Eglot (check
  `xref-find-backend` returns the eglot backend), gtags untouched.
- **V4 on-save update**: edit a file, add a function, save → `global -d newfunc` hits
  within a second, no full re-traversal observed.
- **V5 no re-bloat**: `du -sh` the index, run bulk update, size stays same order of
  magnitude (skip list active in update path).
- **V6 jump history**: gtags-backed `M-.` jump appears in `<f6>` back-history.
- **V7 guards**: attempt build in a buffer under `~/` → refused with message;
  0-byte-stub simulation (`truncate -s 0 GTAGS`) → next build wipes and rebuilds.
- **V8 un-indexed, no-LSP buffer**: `M-.` must NOT show the etags "Visit tags table"
  prompt — either the build offer or a clean "no definitions" message.
- **V9 daemon-restart clean**: restart daemon, open indexed repo, V2 still passes
  (no session-state dependence).

---

## 8. Rollback

The entire current machinery is deleted in one commit (T3+T2 land together); rollback
is `git revert` of that commit. `gtags.conf` and existing on-disk indexes are shared
by both worlds, so switching back requires no index rebuild.

---

## 9. Implementation record (2026-07-30)

Landed as recommended (**D1a + D3a+b + D4a + D5a**) with two deviations:

- **D2: create is a thin `make-process` wrapper (D2a), not `gtags-mode-create` (D2c).**
  T1 found `gtags-mode-create`'s sentinel is fixed — no hook point for invariant #4's
  post-create validation — so `fenrir/gtags-build` owns create (root guard, stub wipe,
  validate-else-wipe) and hands everything downstream to gtags-mode.
- **`gtags-mode-features` trimmed to `(xref hooks)`** — `project` would fight the tuned
  project.el setup, `completion` the curated capfs, `imenu` the tree-sitter imenu.

T1 spike results (all [未驗證] resolved, no D1c fallback needed): backend ordering
verified in source (Eglot registers buffer-locally → precedes gtags-mode's global entry);
create/update/single-update all async via `make-process`; env inherited from
`process-environment` → daemon-wide `setenv` covers every path; no-index buffers decline
silently; the etags `read-file-name` prompt IS still reachable → replaced by a minimal
advice (`user-error` naming `C-c g g`).

T0 was skipped (autonomous run, user unavailable); the general acceptance tests were used.
All pass, verified live against the running daemon (V1–V8; V9 by clean-batch-load proxy —
confirm on next daemon restart): V1 create Go/Py/TS + nested, V2 gtags backend answers
def/ref without LSP, V3 gopls attached → `xref-find-backend` = `eglot`, V4 on-save
`--single-update` indexes a new function in <1 s, V5 bulk update ignores `node_modules`
(skip list active, size stable), V6 gtags jump feeds the `<f6>` merged ring, V7 forbidden
roots refused + 0-byte stub wiped and rebuilt, V8 clean `user-error` instead of the etags
prompt.

T4 correction: the `tags-symbol-lookup` skill lives in
`~/code/ai-skills/claude-code-public-skill` (plugin cache under `.claude/plugins/` is a
copy), NOT the `.claude/` submodule. Took the document-the-divergence branch: note added
to the skill's `gtags.sh` (commit `65cb976` there) + the "CLI alignment" section in
[TAGS.md](../_doc/TAGS.md).

New module: [`lisp/init-tags.el`](../lisp/init-tags.el) (~270 lines incl. docs, replacing
~1010). Deleted: the whole §1 inventory (ggtags package + hooks + `C-c g` search keys +
`fenrir/gtags-*` layer). `<f5> d g` now runs `fenrir/gtags-diagnose`. The
`ggtags-find-tag-dwim` note in init-keys.el needed no change — it documents a rejected
package's internal bug, not a live advice.
