# Design discussion — magit-status-overview

- Task: `magit-spec-discussion` / message `discuss-001`; worker `discuss` (Claude Code, `claude-opus-5[1m]`, session `8b431f0a-884e-43af-bdc9-df07bae10131`, pane `%60`).
- Baseline accepted: `d65ffc852c29fdb2c0c5600074f7181b6ffc0001`, untracked `AGENTS.md` and `records/` unrelated.
- Read: `/home/fenrir/.emacs.d/sdlc/intents/magit-status-overview/intent.md`, `lisp/init-git.el`, `FEATURES.md`, and the installed sources `elpa/magit-20260506.643/{magit-status.el,magit-diff.el}` and `elpa/magit-section-20260503.2051/magit-section.el`. Emacs 30.1.
- Nothing in the project, the live Emacs daemon, or Git was modified. One read-only batch probe was run (`emacs -Q --batch`, scratchpad file, no repo created) — described under "Probe" below.

---

## 1. Bottom line

**Most of the proposal already exists upstream, and the part that does not is one command plus one hook function — not a subsystem.** Concretely:

1. "Hide tracked file bodies" is **already the unconditional default** for file sections in `magit-status-mode` (`magit-diff.el:2779-2786`). No new code is needed for the fresh-buffer case.
2. "Open change groups, collapse file bodies, keep untracked visible" is **exactly what `M-2` (`magit-section-show-level-2-all`) produces today**, including leaving the untracked file list untouched. This is the "explicit return-to-overview action" the proposal asks for; it already has a keybinding.
3. "Per-group file counts" already render — `magit-insert-heading`'s CHILD-COUNT argument is passed `t` for both change groups (`magit-diff.el:3431`, `3455`) and the length for file lists (`magit-status.el:798`).
4. What is **genuinely missing**: `M-2` writes the visibility cache, so it destroys the user's manual folds; and there is no way to say "give *newly appearing* sections the overview shape while leaving everything I touched alone."

So I recommend the spec **shrink to two deliverables**, and explicitly document that the rest is native behaviour rather than reimplementing it.

**Recommended scope**

| # | Deliverable | Size |
|---|---|---|
| A | `fenrir/magit-status-overview` — a non-destructive return-to-overview command (M-2's shape without clobbering the cache), bound in `init-keys.el` | ~25 lines |
| B | A **late-appended** `magit-section-set-visibility-hook` entry giving fresh `unstaged`/`staged` sections `show` and leaving files at their native `hide` | ~10 lines, or zero if the native default is judged sufficient |
| C | FEATURES.md §8 entry + one hint alist row | docs |

**Recommended non-goals**: per-window folds (§4), `--stat` in the status buffer (§5), any custom line-count statistics (§5), any change to buffer size (§6).

---

## 2. What the sources actually say (the load-bearing facts)

### 2.1 Status-buffer file sections are already collapsed by default

`magit-diff-insert-file-section` (`magit-diff.el:2779`) passes HIDE as:

```elisp
(magit-insert-section
    ( file file
      (or (equal status "deleted") (derived-mode-p 'magit-status-mode))
      :source ... :header header :binary binary)
```

In a status buffer that predicate is unconditionally `t`. Every tracked file in "Unstaged changes" / "Staged changes" starts collapsed, on every fresh section. The proposal's headline behaviour is upstream default, not a gap.

The user's observed screen — *top* sections `hidden t`, no file headings visible at all — is the **opposite** problem: the two group sections were collapsed (almost certainly by a `TAB` at some point, cached), which hides the file headings that the native default was already giving them.

### 2.2 The visibility precedence chain

`magit-insert-section--create` (`magit-section.el:1441`, decision at 1455-1470) resolves `hidden` in this fixed order, first hit wins:

1. `magit-section-set-visibility-hook` — `run-hook-with-args-until-success`. Default members: `magit-section-cached-visibility` (`magit-section.el:130-136`, `1996`) and `magit-diff-expansion-threshold` (added at `magit-diff.el:2948`).
2. If `magit-section-preserve-visibility` is nil (it defaults to `t`, `magit-section.el:337`), inherit the predecessor's `hidden`.
3. `magit-section-initial-visibility-alist` (`magit-section.el:184`), matched by type *or lineage*, value may be a function.
4. The literal HIDE argument.

**Three consequences the spec must state:**

- **`add-hook` depth is load-bearing.** `(add-hook 'magit-section-set-visibility-hook #'fn)` prepends at depth 0, ahead of `magit-section-cached-visibility`, and would therefore **override every manual fold on every refresh** — the exact failure the intent forbids ("保留使用者手動展開與收合的操作意圖"). Deliverable B must append: `(add-hook 'magit-section-set-visibility-hook #'fn 90)`.
- **The cache only records *deliberate* show/hide.** `magit-insert-section-hook` is nil by default (`magit-section.el:1366`) and nothing calls `magit-section-maybe-cache-visibility` at insert time; only `magit-section-show`/`-hide` do (`magit-section.el:953`, `974`). So a section the user never touched has no cache entry and re-derives its default every refresh — which is precisely the "fresh-section defaults, preserve manual folds" split the proposal wants. **This works today with no code.**
- **Therefore the visibility hook cannot implement "return to overview."** Once the user has expanded a file, that file has a permanent cache entry (`magit-section-visibility-cache` is `permanent-local`, `magit-section.el:1993-1994`, and there is no pruning API), so an appended hook never fires for it again. Return-to-overview must be an *imperative command* that walks sections, not a hook.

### 2.3 `magit-section-initial-visibility-alist` is a real alternative to a hook

It accepts a lineage and a function, and sits at priority 3 — *below* the cache. A one-line

```elisp
(setopt magit-section-initial-visibility-alist '((stashes . hide) (untracked . show)))
```

would be enough if the only fresh-default change wanted is per-type. Prefer this over a hook function wherever it suffices: it is declarative, it cannot get the depth wrong, and it is already below the cache by construction. **Reach for `magit-section-set-visibility-hook` only if the decision needs the section object** (e.g. "show this group only when it has ≤ N children").

### 2.4 `M-2` semantics, exactly

`magit-section-show-level-2-all` → `(magit-section-show-level -2)` (`magit-section.el:1139-1142`, `1101`). The negative branch:

```elisp
(let ((s (magit-current-section)))
  (setq level 2)
  (while (> (1- (length (magit-section-ident s))) level)
    (setq s (oref s parent)) (goto-char (oref s start)))
  (magit-section-show-children magit-root-section 1))
```

`magit-section-show-children-1 root 1` (`magit-section.el:1004`) unhides root's children (the status groups), recurses with depth 0 into each, unhides their children (files), then `magit-section-hide`s each file. Net: **groups open, file bodies collapsed, file headings visible.** Then `magit-section-show root` (`996`, `945`) re-applies each descendant's own `hidden`.

Behaviour on the three group kinds:

- **unstaged / staged** — files collapsed, headings shown. The target overview.
- **untracked** — its `file` sections are inserted without `magit-insert-heading` (`magit-status.el:808-811`), so their `content` slot is nil; `magit-section-hide` short-circuits on `(when-let ((beg (oref section content))))` (`magit-section.el:964`). The list stays fully visible. **The intent's "不得隱藏 untracked section" is satisfied for free.**
- **status headers** — `magit-insert-headers` makes the first header the parent of the rest (`magit-section.el:1610-1630`); the sub-headers are one-liners with nil `content`, so they too survive.

Two side effects worth specifying rather than discovering later:

- **`M-2` moves point** to the level-2 ancestor of the current section — from a hunk, point lands on that file's heading. For a return-to-overview command this is arguably the *right* behaviour ("collapse, and park me on the file I was reading"), but it must be intentional and tested.
- **`M-2` writes the cache** for every section it touches (each `show`/`hide` calls `magit-section-maybe-cache-visibility`). This is the one real defect: after `M-2` the user's prior manual folds are gone permanently. **This is the sole justification for deliverable A.**

### 2.5 `<backtab>` does not give an overview, and `magit-section-show-headings` is misleading

`magit-section-cycle-global` (`magit-section.el:1064`) has three branches: `magit-section-show-headings` on root, `magit-section-show-children` on root (no depth), else hide all top-level children.

`magit-section-show-headings-1` (`magit-section.el:1026`) sets `hidden nil` on **every** child before deciding whether to recurse, so despite its docstring ("Only show the headings, previously shown text-only bodies are hidden") it produces the same result as `magit-section-show-children-1` with `depth` nil.

**Probe.** `emacs -Q --batch` with the elpa `magit-section`/`compat`/`cond-let`/`llama`/`dash` load paths, on a synthetic `status → unstaged → file → hunk` tree with every node `hidden t`:

```
show-headings-1              unstaged=nil  file=nil  hunk=nil
show-children-1 depth=nil    unstaged=nil  file=nil  hunk=nil
```

Identical — hunks unhidden in both. (No repo was created; the two later `depth=0/1` cases errored in the fixture because `magit-section-hide` wants real markers and a buffer, so the depth arithmetic in §2.4 is source-derived, not probe-derived.)

**Implication:** `<backtab>` toggles between fully-expanded and fully-collapsed, with no intermediate state. `M-2` is the only native path to the overview shape. This *supports* the proposal's premise that a scoped overview action is worth having — it just means the gap is narrower than "build an overview mode."

### 2.6 Counts are already there

`magit-insert-heading`'s first argument may be a CHILD-COUNT (`magit-section.el:1527`, resolved by `magit-insert-child-count` at `1669`), gated on `magit-section-show-child-count` (default `t`, `magit-section.el:160`). Both change groups pass `t` (`magit-diff.el:3431`, `3455`) and file lists pass `(length files)` (`magit-status.el:798`). "各暫存狀態的檔案清單與數量" is satisfied by native behaviour — **provided the group section is open**, which is what §2.4 fixes.

---

## 3. Native `M-2` vs a scoped overview command — recommendation

**Recommendation: build A, and build it as a thin, cache-preserving wrapper around the same primitive `M-2` uses. Do not build an "overview mode" with its own state.**

Reasoning:

- The visible result of `M-2` is already correct (§2.4). Reimplementing the tree walk would only add a second, drifting copy of `magit-section-show-children-1`'s depth semantics.
- The only defect is cache destruction, and that is fixable by binding `magit-section-cache-visibility` to nil around the call — `magit-section-maybe-cache-visibility` (`magit-section.el:2011-2016`) is a no-op when that variable is nil and the section type is not in it. That is a one-line let-binding, not a fork.

Sketch (illustrative, **not** proposed for commit in this task):

```elisp
(defun fenrir/magit-status-overview ()
  "Collapse to the change overview without discarding remembered folds."
  (interactive)
  (unless (derived-mode-p 'magit-status-mode)
    (user-error "Not in a Magit status buffer"))
  (let ((magit-section-cache-visibility nil))
    (magit-section-show-level-2-all)))
```

Open design choices the spec should settle, not the implementation:

- **Should it be idempotent-toggling?** i.e. a second press restores the pre-overview folds. That requires snapshotting `magit-section-visibility-cache` and re-applying it — meaningfully more code and a new failure mode (stale idents after a refresh). **My recommendation: no.** One-way "return to overview" plus the existing per-section `TAB` is enough, and it matches the intent's phrasing ("返回概況").
- **Which key?** Per this repo's rules, `init-keys.el` only *routes* and must never replace an existing `C-c` chord (`.emacs.d/CLAUDE.md`, "Architecture rules"). `M-2` is already `magit-section-show-level-2-all` in `magit-section-mode-map` (`magit-section.el:478-479`); **rebinding `M-2` to the wrapper inside `magit-status-mode-map` is the honest choice** — same muscle memory, strictly better behaviour, no new key to document. If the reviewer objects to shadowing an upstream binding, `j` already opens `magit-status-jump` (`magit-status.el:391`, `394`) and an entry could be appended there instead.
- **Does A also need to *open* collapsed groups?** Yes, and `M-2` already does — this is what fixes the user's actual observed screen (§2.1).

---

## 4. Per-window constraints in a shared status buffer — recommendation: declare out of scope

This is not a tuning question; it is structurally impossible without forking `magit-section`'s visibility layer.

- Fold state lives in **two buffer-wide places**: the `hidden` slot of the section object, and `magit-section-visibility-cache`, a `defvar-local` marked `permanent-local` (`magit-section.el:1993-1994`).
- Hiding is implemented with a plain overlay carrying `invisible t` / `cursor-intangible t` (`magit-section.el:966-973`). Emacs overlays *do* support a `window` property that would scope them per-window, but `magit-section-hide` never sets it, and the single `hidden` boolean has nowhere to store a per-window answer anyway.
- Magit keeps one status buffer per repository, so two windows on the same repo necessarily share it.

The only honest per-window story is *two different buffers* — e.g. `magit-status` in one window and `magit-diff-unstaged` / a `magit-diff-buffer-file` in the other, which is already the native workflow (`RET` from a file section, already advertised in `fenrir/magit-hints-alist`, `init-git.el:34-37`). **I recommend the spec state this as an explicit non-goal with the overlay/slot reason,** so it is not re-litigated during implementation. Indirect buffers are not a workaround: Magit's refresh drives buffer-local state (`magit-buffer-diff-args`, the cache, the root section) that indirect buffers share with the base.

**Corollary for A**: because the state is buffer-wide, `fenrir/magit-status-overview` invoked from either window changes both. That is correct and should simply be documented, not fought.

---

## 5. Statistics vs. avoiding complexity — recommendation: **do not add statistics**

I disagree with keeping this option open. Three findings make it a bad trade:

1. **Upstream deliberately withholds `--stat` from status buffers.** The transient argument carries `:if 'magit-diff-argument-predicate` (`magit-diff.el:1252-1257`), and that predicate is `(or (eq (oref transient--prefix command) 'magit-diff) (derived-mode-p 'magit-diff-mode))` (`magit-diff.el:1266-1268`). The `-s` toggle is not offered in `magit-status-mode`.

2. **Forcing it in would produce malformed sections.** `magit-diff-wash-diffstat` (`magit-diff.el:2596`) first consumes `--numstat` lines (`^[-0-9]+\t[-0-9]+\t\(.+\)$`, line 2606) to build `files`, then pops from that list while washing the human-readable stat lines (`(magit-insert-section (file (pop files))`, line 2629). Only `magit-insert-diff` — the **diff-mode** inserter — adds `--numstat` alongside `--stat` (`magit-diff.el:2491`). The status inserters `magit-insert-unstaged-changes` / `magit-insert-staged-changes` (`magit-diff.el:3428`, `3450`) pass neither. With `--stat` but no `--numstat`, `files` is empty, `(pop files)` yields nil for every row, and each diffstat entry becomes a `file` section with value nil — i.e. **N sections sharing the ident `((file . nil) (diffstat) (unstaged) (status))`**, since `magit-section-ident` is the type/value chain up to root (`magit-section.el:577`). Shared idents corrupt exactly the cache the rest of this design depends on.

3. **Even done correctly it works against the goal.** A `diffstat` section duplicates the file list vertically, roughly doubling the rows the overview is trying to compress.

**Custom stats are also not worth it.** Computing per-file `+/-` from the already-washed hunk sections at `magit-refresh-buffer-hook` is Git-free and correct in principle, but it means a buffer-wide walk on every refresh plus text surgery on headings, to replace information the user gets by pressing `TAB` on the one file they care about. `magit-format-file-function` (`magit-diff.el:362`) is not a way out either: it runs while the file heading is inserted, before the hunks are parsed, so it would have to shell out to Git — violating the "no Git in redisplay/refresh path" constraint the existing hints code was written to honour (`init-git.el:27-28`, `191-199`).

**What to do instead, at zero cost:** confirm `magit-section-show-child-count` is `t` (it is, by default) and let §2.6's native counts answer "how many files per group". If the reviewer still wants a magnitude cue, the cheapest correct option is a **hints-side** one: `fenrir/magit-hints--render` (`init-git.el:140`) already runs Git-free on redisplay and already walks the section ancestry to derive `diff-type` (lines 155-163). Adding "N files" for the group at point is a few lines there and costs nothing extra. I would still leave it out of v1.

---

## 6. Testable criteria — recommendation

The intent's proposed acceptance scenarios are the right shape (disposable repo, mixed staging, partial staging, 1000-line XML). Refinements:

**Do not use buffer size as a criterion.** Hunks are washed eagerly inside the file section body (`magit-wash-sequence #'magit-diff-wash-hunk`, `magit-diff.el:2800`) — collapsing changes overlays, not text. The observed 186,292 chars will be essentially unchanged by this feature, and a size-based assertion would fail for the wrong reason. Assert on **visible lines** (`count-lines` over non-invisible text, or `(oref section hidden)` per section), not `buffer-size`.

Concrete criteria I would put in the spec:

| # | Criterion | Check |
|---|---|---|
| T1 | Fresh status buffer: every `unstaged`/`staged` file section is `hidden`, every file **heading** is visible | walk `magit-root-section`, assert `hidden` per file and `magit-section-hidden` nil for the group |
| T2 | Fresh status buffer: `untracked` group and its entries visible | `(oref untracked hidden)` nil after the intended default |
| T3 | Expand file X's diff, refresh (`g`): X stays expanded, all others stay collapsed | cache path, §2.2 |
| T4 | Expand X, invoke the overview command, then refresh: overview is applied **and** X's remembered fold is intact after the *next* manual expansion cycle | this is what distinguishes A from bare `M-2`; bare `M-2` fails it |
| T5 | Overview command leaves point on a section that still exists, and never inside invisible text | `(magit-section-hidden (magit-current-section))` is nil |
| T6 | 1000-line XML staged: after the overview command its file heading is one line, and `n`/`p` step file-to-file | visible-line count, not buffer size |
| T7 | Git index and worktree byte-identical before/after every display operation | `git status --porcelain=v2` + `git diff --cached --binary \| sha256sum` before/after — this is the intent's hard constraint and is cheap to assert |
| T8 | TTY frame and GUI frame in the same daemon both render correctly | manual; note `magit-section-visibility-indicators` differs by frame type (`magit-section.el:212`, `magit-section-visibility-indicator` at `2018`) — **the fringe indicator is GUI-only, the "…" ellipsis is the TTY path**, so a collapsed-state assertion phrased in terms of the fringe would silently pass on TTY |
| T9 | `magit-todos` and `forge` sections (both add level-1 sections, `init-git.el:415` and `421`) are not left in a broken state by the overview command | they are level-1, so depth-1 collapse touches their children |

T8 and T9 are the two I would most expect an implementation to miss.

---

## 7. Disagreements with the proposal, stated plainly

1. **"status-only overview … hides tracked file bodies" is not new work.** It is `magit-diff.el:2779-2786`. The spec should say so and not budget for it; otherwise the implementation will add a hook that fights the native default and, if added at depth 0, destroys manual folds (§2.2).
2. **The problem statement should be corrected.** The observed defect was collapsed *group* sections, not expanded file bodies. The intent already flags the "XML filling the screen" claim as unverified; the spec should go further and record the actual mechanism, because it changes the fix (open the groups) from the proposed one (hide the files — already true).
3. **"Explicit return-to-overview action" mostly exists** as `M-2`. The delta is cache preservation and point behaviour. Framing it as a *fix to `M-2`* rather than a *new mode* keeps the surface small and keeps the key the user may already know.
4. **Statistics: recommend dropping outright**, not deferring (§5).
5. **Per-window: recommend declaring impossible**, with the overlay/slot reason recorded so it is not revisited (§4).
6. **`magit-section-initial-visibility-alist` should be tried before any hook function** (§2.3). The proposal's "fresh-section defaults" reads as if a hook is assumed.

---

## 8. Material questions for the coordinator

1. **Is the real complaint "I can't see the file list" or "the diffs are too long"?** Everything above says it was the former (collapsed groups). If the user's lived complaint is genuinely the latter, then the native default is failing for some reason I have not identified from source, and we need a fresh observation with fold state recorded per section — not just a `buffer-substring` dump. **This is the single question that most changes the spec.**

2. **Had the user pressed `TAB` on "Unstaged changes"/"Staged changes", or did those sections arrive collapsed on their own?** If the latter, something in this config or in `magit-todos`/`forge` is writing the cache, and *that* is the bug. The `magit-todos` source carries a stale comment claiming `magit-insert-section` binds `magit-section-visibility-cache` to nil (`magit-todos.el:868`, `935`) — I found no such binding in magit-section 20260503.2051, so its cache handling around that assumption is worth one look before we design around it.

3. **Should the overview command shadow `M-2`, or take a new key?** (§3.) I lean shadow. This is a user-taste call that affects `init-keys.el` routing and FEATURES.md.

4. **Is one-way "return to overview" acceptable, or is a toggle required?** (§3.) A toggle roughly triples the code and adds a stale-ident failure mode.

5. **Does the reviewer accept "no statistics at all" for v1?** (§5.) If not, the fallback I would accept is the Git-free hints-side count, not `--stat`.

6. **Is `magit-status-file-list-limit` (100, `magit-status.el:184`) relevant here?** In `$HOME` the untracked list is long; the overview will show "N files not listed" (`magit-status.el:815-819`). Should the spec say anything about that, or is it out of scope?

---

## 9. Limitations of this analysis

- **Source reading, not live observation.** Every claim above about defaults, precedence and `M-2` is derived from the installed `.el` files at the versions named (magit `20260506.643`, magit-section `20260503.2051`, Emacs 30.1). I did **not** open a status buffer, and I did not touch the running daemon. The §2.4 claim that `M-2` yields the overview shape is a source derivation and should be confirmed interactively before the spec is accepted — it is one keypress to check.
- **The only execution was the §2.5 batch probe**, on a synthetic section tree, covering `show-headings-1` vs `show-children-1 depth=nil` only. Its two `depth=0/1` cases did not run.
- **Byte-compiled `.elc` files exist alongside every source read.** I read `.el`; if a stale `.elc` were loaded at runtime, behaviour could differ. I did not verify load order and did not create or delete any `.elc`.
- `magit-todos` (`20250928.1611`) and `forge` were inspected only far enough to establish that they insert level-1 status sections. Their interaction with the overview command (T9) is untested.
- No claim here is evidence that the user's current worktree passes any test; no tests were run.

---

# Addendum v2 — response to updates `discuss-update-002` and `discuss-update-003`

This section **supersedes §1's deliverable A and §3's implementation sketch**, and adds §10-§13. Everything else in §1-§9 stands as written. Both updates were read from the mailbox and acknowledged before this was written.

## 10. `magit-restore-section-visibility-cache` — update-002's question, answered

**Codex is right that the restore path exists, and it changes what "fresh" means. It is also, in this exact version, inert for status buffers. Both halves matter.**

- `magit-generate-new-buffer` calls `(magit-restore-section-visibility-cache mode)` on every newly created Magit buffer (`magit-mode.el:917`). That function reads `magit-section-visibility-cache` out of `magit-repository-local-cache` under the key `(MODE . magit-section-visibility-cache)` (`magit-mode.el:1554-1557`). So a brand-new status buffer can inherit folds from a killed predecessor — **"new buffer" is not "no cache"**, exactly as update-002 says.
- **But nothing populates that key for status buffers in magit `20260506.643`.** The writer is `magit-preserve-section-visibility-cache` (`magit-mode.el:1548-1552`), and its sole `kill-buffer-hook` registration in the whole tree is inside `magit-refs-refresh-buffer` (`magit-refs.el:328`) — `magit-refs-mode` only. Grepped across `elpa/magit-20260506.643/*.el`; there is no other caller. `magit-status-mode`'s body (`magit-status.el:439-442`) adds no such hook.
- The function's own guard is `(derived-mode-p 'magit-status-mode 'magit-refs-mode)`, i.e. it was *written* to cover status buffers. So this reads as an upstream oversight, not a deliberate exclusion — which means a later magit could start populating it and silently flip the semantics.

**Recommendation for the spec:** do not depend on either behaviour. Define "fresh" the way the code actually decides it — **a section with no entry in `magit-section-visibility-cache` at the moment `magit-insert-section--create` runs** (`magit-section.el:1455-1470`) — not "a new buffer". That definition is correct under both the current inert path and a future working one. Update-002's proposed wording ("fresh means no prior restored cache") is right; I'd just anchor it to the cache lookup rather than to buffer creation.

**Related fact the spec should carry:** `q` is `magit-mode-bury-buffer`, not kill. A buried status buffer keeps its own buffer-local cache (`permanent-local`, `magit-section.el:1994`), so `q` followed by `C-x g` preserves folds through the ordinary buffer, with no repository-local cache involved. The native full reset is `magit-zap-caches` (`magit-mode.el:1559-1591`), which nils the cache in every Magit buffer of the repository — that is the existing escape hatch, and the spec should point at it rather than invent one.

## 11. Conceded: the overview command must cache. My §3 sketch was wrong.

Update-003 is correct, and on mechanics rather than taste. My proposed `(let ((magit-section-cache-visibility nil)) ...)` wrapper would set the `hidden` slots but leave the stale `show` entries in place; the next `g` recreates every section, `magit-section-cached-visibility` returns `show` for each previously-expanded file (`magit-section.el:1996-2001`, consulted first at `1455-1458`), and **the overview silently evaporates on the very next refresh.** That is a worse failure than the one I was trying to avoid, because it is invisible until the user refreshes.

I withdraw the cache-preserving wrapper. The correct division, which I now agree is the right one to write into the spec:

- **Ordinary refresh (`g`) preserves manual folds** — free, native, already true (§2.2).
- **The explicit overview command is itself a deliberate fold choice and is therefore cached**, so it survives `g`. Using the plain `magit-section-show`/`-hide` path gives this automatically, since both call `magit-section-maybe-cache-visibility` (`magit-section.el:953`, `974`).

The cost — the user's earlier per-file folds are overwritten — is real and should be stated in the docstring and in FEATURES.md, not engineered around. Recovering them is re-expanding the file, which is one `TAB`.

## 12. Conceded: scope to the change groups; leave `M-2` alone.

Also correct, and I now think my "shadow `M-2`" suggestion was the weaker option for a reason I under-weighted: `magit-section-show-level -2` acts on `magit-root-section` (`magit-section.el:1109-1113`), so it collapses the children of **every** level-1 section — including `stashes`, `unpushed`/`unpulled`, forge's "Pull requests"/"Issues" (`init-git.el:415`) and magit-todos' "TODOs" (`init-git.el:421`). The intent limits the change to the staging groups, so a global operator overreaches by construction, and shadowing an upstream binding to do it makes the overreach harder to notice.

**Revised deliverable A**: a scoped command that walks `magit-root-section`'s children, and for the `unstaged` and `staged` sections only — `magit-section-show` the group, then `magit-section-hide` each `file` child. `untracked` is left entirely untouched (it needs no special-casing for the intent's "不得隱藏 untracked" rule; §2.4 explains why hiding is a no-op there anyway, but *not touching it* is cleaner and does not write cache entries for it). New key, `M-2` unchanged. `magit-section-match-assoc` (`magit-section.el:1358`) is the native way to test a section's type or lineage if the walk needs it.

Two implementation costs update-002 asked about:

- **Point.** The native `M-2` relocates point to the level-2 ancestor (§2.4). A scoped command has no such behaviour for free and must decide explicitly. **Recommendation: if point is inside a section that is about to be hidden, move it to that section's file heading; otherwise leave it alone.** `magit-section-hide` already does a narrow version of this (`(when (< beg (point) end) (goto-char (oref section start)))`, `magit-section.el:966-968`), so hiding the file at point lands point on the file heading with no extra code — but only for the *selected* window's point. Criterion T5 covers this.
- **Lazy wash.** `magit-insert-section-body` (`magit-section.el:1585-1608`) defers a hidden section's body into a `washer` closure, and `magit-section-show` runs it via `magit-section--opportunistic-wash` (`magit-section.el:1699-1710`). In the status buffer only the file-list sections use this (`magit-status.el:803`); `unstaged`/`staged` hunks are washed eagerly (`magit-diff.el:2800`). So the scoped command **never triggers a wash** as long as it does not show `untracked` — another argument for leaving that section alone. Showing an already-shown group is free.
- **Windows.** Unchanged from §4: state is buffer-wide, so the command affects every window on that status buffer. Document, don't fight.

## 13. Corrections and precision update-003 asked for

**13.1 I withdraw the causal speculation about the observed folds.** §8 question 2 asked whether the user pressed `TAB` or an extension wrote the cache. I have no evidence for either and should not have framed it as a binary. What is established: the two group sections were `hidden t`, and `hidden` for a group section is only reached through the four-step precedence in `magit-section.el:1455-1470`, of which the cache is the first. Who or what wrote that cache entry is **unknown and not worth determining** — the fix (a scoped command that opens the groups) is the same either way. Please treat §8 Q2 as withdrawn rather than open.

Correspondingly, my §8 remark about the `magit-todos` comment (`magit-todos.el:868`, `935`) claiming `magit-insert-section` binds the cache to nil should be read only as "that comment does not match magit-section `20260503.2051`, where no such binding exists" — not as a suggestion that magit-todos caused anything.

**13.2 Untracked listing is not an exhaustive inventory, and the spec must say so.** Two independent truncations apply, and an overview that implies completeness would be wrong:

- `magit-status-show-untracked-files` (`magit-status.el:147-181`) defers to the **Git** setting `status.showUntrackedFiles` when the Lisp variable is not locally set. Its own docstring points at `git config set --local status.showUntrackedFiles no` as the speed knob. With Git's `normal`, untracked *directories* are collapsed to one entry — the entries are not files. (`git config --get status.showUntrackedFiles` is unset in `/home/fenrir/.emacs.d`; the `$HOME` repo is documented as `normal` in its `CLAUDE.md`, and `$HOME` is the pathological case this config is tuned around.)
- `magit-status-file-list-limit` is 100 (`magit-status.el:184-188`); beyond it Magit inserts an `info` section reading "N files not listed" in the `warning` face (`magit-status.el:815-819`).

**Recommendation:** the spec should state that the overview presents **the change groups Magit was asked to compute**, that the untracked list is subject to the Git setting and the 100-file cap, and that the "N files not listed" line is the disclosure — and should require that the overview never hides that line. It follows that "使用者可快速掌握……各暫存狀態的檔案清單與數量" in the intent is achievable for staged/unstaged (where the counts are exact, §2.6) but is **bounded** for untracked, and that bound should be written down rather than glossed.

**13.3 Everything else in update-003 I agree with as already stated**: native status file bodies default hidden (§2.1), no statistics subsystem (§5), one-way command (§3), folds shared across windows (§4), `magit-section-initial-visibility-alist` before hooks (§2.3).

## 14. Remaining material objections — none blocking

I have no further objection to the direction. Two things I would still like the frozen draft to contain, both cheap:

1. **The definition of "fresh" anchored to the cache lookup, not to buffer creation** (§10), plus a one-line note that `magit-restore-section-visibility-cache` is wired for `magit-refs-mode` only today, so the spec is not surprised if a magit upgrade changes it.
2. **Criterion T8 restated in TTY terms** — `magit-section-visibility-indicators` (`magit-section.el:212`) resolves to the fringe bitmap in GUI frames and the `…` ellipsis in terminal frames (`magit-section-visibility-indicator`, `magit-section.el:2018`). A collapsed-state assertion written against the fringe passes vacuously on TTY. Given this config is TTY-first with a coexisting GUI frame on the same daemon, that is the likeliest way for the acceptance run to report a false pass.

Superseded by this addendum: §1 deliverable A's description, §3's `fenrir/magit-status-overview` sketch and its "shadow `M-2`" recommendation, and §8 question 2. Section 9's limitations still apply in full — in particular, §2.4 remains source-derived and unconfirmed in a live status buffer.
