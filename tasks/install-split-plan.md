# Implementation Plan: split `install.sh` into root / non-root scopes

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
Spec: [`SPEC.md`](../SPEC.md) — read that first; this plan refers back to it.

Parent dotfiles repo guidance: [`/home/fenrir/CLAUDE.md`](../../CLAUDE.md).
Distinct from the in-flight Lua work tracked in [`plan.md`](plan.md) /
[`todo.md`](todo.md) — these two task streams touch disjoint files and can
proceed independently.

## Overview

Refactor the existing monolithic [`install.sh`](../install.sh) into four files
to make the `sudo`-vs-user privilege boundary explicit:

- `install-lib.sh` — shared helpers (no execution)
- `install-root.sh` — apt section, self-elevates via `exec sudo`
- `install-user.sh` — cargo / go / rustup / npm + manual reminders, refuses
  to run as root, **flips `npm config prefix` to `$HOME/.npm-global`** so
  `npm install -g` no longer needs `sudo`
- [`install.sh`](../install.sh) — thin orchestrator (calls the two scripts in
  order), kept at its current path so the README bootstrap one-liner still
  works untouched

All design rationale lives in [`SPEC.md`](../SPEC.md); this doc is the
implementation breakdown.

## Architecture Decisions

- **Four files, flat layout, no `scripts/` subdir.** Matches the current
  layout — the repo only has `install.sh` at root today, no `scripts/`
  directory. Keeps the README bootstrap one-liner pointing at the same path.
- **`install-lib.sh` is source-only (no shebang shellcheck directive needed).**
  Helpers move out of [`install.sh:21-29`](../install.sh) verbatim — `have`,
  `dpkg_installed`, `section`, `ok`, `skip`. Both runnables `source` it via
  `. "$SCRIPT_DIR/install-lib.sh"` after computing `SCRIPT_DIR` from
  `BASH_SOURCE[0]`. Allows running each script directly without cwd
  assumptions.
- **`install-root.sh` self-elevates via `exec sudo "$0" "$@"`.** Better UX
  than refusing-with-message: the user can just `bash install-root.sh` and
  the script handles the elevation. Matches how the current monolith works
  (it calls `sudo apt update` interactively in the middle of the run, not at
  the top — moving the sudo to a re-exec at the top is a minor improvement,
  same number of password prompts).
- **`install-user.sh` refuses if `EUID == 0`.** Asymmetric on purpose — user
  scripts under `sudo` is the silent-corruption case (cargo / go / rustup /
  npm caches end up under `/root/`). Fail loud, fail early.
- **npm-prefix flip is conditional + idempotent.** Only fire `npm config set
  prefix` if `npm config get prefix` is still `/usr/local` or `/usr` (the
  root-requiring defaults). If the user already pointed npm at a custom
  user-writable prefix, leave it alone. Subsequent runs are no-ops (the
  conditional fails on the second pass).
- **`emacs-lsp-booster` version pin stays in place.** Comment at
  [`install.sh:74`](../install.sh) flags coupling to
  [`init.el:713`](../init.el); the new `install-user.sh` preserves the
  `--version 0.2.1` flag and the explanatory comment verbatim.
- **Existing Chinese comments preserved verbatim.** Lines like
  `# core — config 載入必要` ([`install.sh:34`](../install.sh)) move into
  `install-root.sh` unchanged. No translation, no rewording — just relocate.

## Task List

### Phase 1: Extract helpers

#### Task 1: Create `install-lib.sh` with the five helpers

**Description:** Extract `have`, `dpkg_installed`, `section`, `ok`, `skip` from
[`install.sh:21-29`](../install.sh) into a new file `install-lib.sh` at the
repo root. Identical byte content for those five functions; add a one-line
banner comment at the top stating that this file is source-only.

**Acceptance criteria:**
- [ ] `install-lib.sh` exists at [`/home/fenrir/.emacs.d/install-lib.sh`](../install-lib.sh).
- [ ] Contains exactly the five helpers from [`install.sh:21-29`](../install.sh),
      byte-identical bodies.
- [ ] Top of file has a comment `# install-lib.sh — shared helpers for install-{root,user}.sh.`
      and `# Source-only; do not execute directly.`
- [ ] No shebang line (it's not executable on its own).
- [ ] File is NOT marked executable (`chmod -x` not needed if `Write` creates
      it without the bit — confirm with `ls -l`).

**Verification:**
- [ ] `shellcheck install-lib.sh` exits 0 (or warnings only — no errors).
- [ ] Sourcing it from a one-shot bash repl exposes the five functions:
      `bash -c '. ./install-lib.sh && declare -F have dpkg_installed section ok skip'`
      → prints all five `declare -f` lines.

**Dependencies:** None.

**Files likely touched:**
- `install-lib.sh` (new, ~12 lines)

**Estimated scope:** **XS** — single new file, mechanical copy.

### Phase 2: Build the two runnables in parallel

Tasks 2 and 3 are independent — both depend only on Task 1 — and could run in
parallel sessions. Serialize them in a single session.

#### Task 2: Create `install-root.sh` (apt section + self-elevate)

**Description:** New file at [`/home/fenrir/.emacs.d/install-root.sh`](../install-root.sh).
Contains:

1. Shebang `#!/usr/bin/env bash`, `BASH_VERSION` gate
   ([`install.sh:14-18`](../install.sh) idiom), `set -euo pipefail`.
2. `SCRIPT_DIR` resolution + `. "$SCRIPT_DIR/install-lib.sh"`.
3. Self-elevate idiom: if `EUID != 0`, `exec sudo --preserve-env=PATH "$0" "$@"`.
4. The apt section from [`install.sh:31-57`](../install.sh) verbatim
   (`APT_PKGS` array + the `missing` loop + the `apt update && apt install`
   block). Drop the `sudo` prefix from `apt update` / `apt install` since
   we're already root at this point — both `apt` invocations run as root
   directly.

**Acceptance criteria:**
- [ ] `install-root.sh` exists and is executable (`chmod +x` applied).
- [ ] `APT_PKGS` array byte-identical to [`install.sh:33-44`](../install.sh)
      (preserve the Chinese comments).
- [ ] No `cargo` / `go` / `rustup` / `npm` references in this file.
- [ ] The `apt update` + `apt install` calls do NOT have a `sudo` prefix
      (they're already running as root after the re-exec).
- [ ] `git diff` shows no changes to the apt section's package list relative
      to the current [`install.sh`](../install.sh) — same packages, same order.

**Verification:**
- [ ] `shellcheck install-root.sh` exits 0 (errors only — `SC2086`-style
      warnings on the `apt install -y "${missing[@]}"` line are acceptable).
- [ ] Privilege-elevate smoke: `bash install-root.sh` from an unprivileged
      shell should prompt for sudo password, then re-enter the script as root
      and proceed. Confirm `[ "$EUID" -eq 0 ]` post-re-exec via a temp
      `echo "EUID=$EUID"` line (remove before finishing the task).
- [ ] Re-run idempotency: `sudo bash install-root.sh` immediately after a
      successful run should print only `[ok] <pkg>` lines, no `installing:`.

**Dependencies:** Task 1.

**Files likely touched:**
- `install-root.sh` (new, ~40 lines)

**Estimated scope:** **S** — single new file, mostly copy + privilege idiom.

#### Task 3: Create `install-user.sh` (cargo + go + rustup + npm + reminders)

**Description:** New file at [`/home/fenrir/.emacs.d/install-user.sh`](../install-user.sh).
Contains:

1. Shebang `#!/usr/bin/env bash`, `BASH_VERSION` gate, `set -euo pipefail`.
2. `SCRIPT_DIR` resolution + `. "$SCRIPT_DIR/install-lib.sh"`.
3. Reverse-guard: if `EUID == 0`, print refuse message + `exit 1`.
4. **New: npm-prefix flip** — see [`SPEC.md` "npm-globals → user prefix idiom"](../SPEC.md#npm-globals--user-prefix-idiom-the-one-new-piece-of-logic).
   Conditional `npm config set prefix "$HOME/.npm-global"` only when current
   prefix is `/usr/local` or `/usr`. Place this immediately BEFORE the
   existing npm section.
5. **npm globals section** moved from [`install.sh:59-69`](../install.sh)
   verbatim, with the call site unchanged (`npm install -g typescript …`).
6. **cargo section** moved from [`install.sh:71-79`](../install.sh) verbatim,
   including the `# emacs-lsp-booster: version pin matches init.el:713`
   comment and the `--version 0.2.1` flag.
7. **go section** moved from [`install.sh:81-87`](../install.sh) verbatim.
8. **rustup section** moved from [`install.sh:89-95`](../install.sh) verbatim.
9. **Manual follow-ups heredoc** moved from [`install.sh:97-107`](../install.sh)
   with ONE added bullet at the top of the heredoc:
   `• PATH: add $HOME/.npm-global/bin to your shell rc (npm prefix lives there now)`.

**Acceptance criteria:**
- [ ] `install-user.sh` exists and is executable.
- [ ] Running as root (`sudo bash install-user.sh`) exits 1 with the refuse
      message on stderr; produces no filesystem writes.
- [ ] On a machine where `npm config get prefix` currently returns
      `/usr/local`, running `bash install-user.sh` flips it to
      `$HOME/.npm-global`.
- [ ] On a machine where `npm config get prefix` already returns a non-default
      path, the script does NOT call `npm config set prefix` (verify via
      `bash -x install-user.sh 2>&1 | grep 'npm config set'` returning empty).
- [ ] No `apt` / `dpkg-query` references in this file.
- [ ] The `--version 0.2.1` pin on `cargo install emacs-lsp-booster` is
      preserved.
- [ ] Manual-follow-ups heredoc contains both the new `PATH:` bullet AND the
      existing four bullets (nerd-icons, jinx, vterm, ABI-15).

**Verification:**
- [ ] `shellcheck install-user.sh` exits 0 (errors only).
- [ ] Refuse-as-root smoke: `sudo bash install-user.sh` → exits 1 with
      stderr matching `refuse to run as root`.
- [ ] Normal-user smoke: `bash install-user.sh` → completes; all sections
      print either `[ok]` / `[skip]` / `installing:` per their existing
      semantics; `npm config get prefix` afterwards is `$HOME/.npm-global`
      (assuming starting state was `/usr/local`).
- [ ] Re-run idempotency: second `bash install-user.sh` immediately after
      the first should produce no `npm config set` activity (the conditional
      no longer fires) and `[ok]` / already-installed paths through the
      cargo / go / rustup tools.

**Dependencies:** Task 1.

**Files likely touched:**
- `install-user.sh` (new, ~60 lines — slightly longer than `install-root.sh`
  because of the new npm-prefix block + the multiline heredoc)

**Estimated scope:** **S/M** — single new file, but contains the one piece of
new logic (npm-prefix flip) that didn't exist before.

### Checkpoint: After Tasks 1–3

- [ ] `shellcheck install-lib.sh install-root.sh install-user.sh` exits 0.
- [ ] Three new files exist alongside the still-monolithic
      [`install.sh`](../install.sh) (which Task 4 will shrink). At this point
      [`install.sh`](../install.sh) is unchanged from `main` HEAD.
- [ ] Privilege guards verified (root self-elevates; user refuses root).
- [ ] Pause briefly to eyeball the three files before collapsing the
      orchestrator.

### Phase 3: Collapse the orchestrator

#### Task 4: Shrink [`install.sh`](../install.sh) to orchestrator (~8 lines)

**Description:** Replace the entire body of [`install.sh`](../install.sh)
(currently lines 1–107) with the orchestrator form from
[`SPEC.md` "Code Style"](../SPEC.md#code-style):

```bash
#!/usr/bin/env bash
# install.sh — orchestrator. Calls install-root.sh (via sudo) then install-user.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo bash "$SCRIPT_DIR/install-root.sh"
bash "$SCRIPT_DIR/install-user.sh"
```

Note: `install-root.sh` itself self-elevates, so the `sudo` prefix here is
redundant — but explicit, so the user sees the password prompt come from
`install.sh` rather than from a re-exec hop. Acceptable redundancy.

**Acceptance criteria:**
- [ ] [`install.sh`](../install.sh) is ~8 lines.
- [ ] Existing executable bit preserved.
- [ ] No `APT_PKGS` / `cargo` / `go` / `rustup` / `npm` / `EOF` references
      remain — they're all delegated to the two sub-scripts.
- [ ] `git diff install.sh` shows ~100 lines deleted, ~8 lines remain.

**Verification:**
- [ ] `shellcheck install.sh` exits 0.
- [ ] End-to-end smoke on a machine that's already fully bootstrapped:
      `bash install.sh` runs cleanly, prompts once for sudo password (the
      `sudo bash install-root.sh` line), produces only `[ok]` / `[skip]`
      output, ends with the manual-follow-ups heredoc.
- [ ] Confirm the README bootstrap one-liner at
      [`README.md:20`](../README.md) (`~/.emacs.d/install.sh`) still works
      — exactly the same call, now an orchestrator under the hood.

**Dependencies:** Tasks 1, 2, 3.

**Files likely touched:**
- [`install.sh`](../install.sh) (rewrite — net ~100 lines removed)

**Estimated scope:** **XS** — one file, mostly deletion.

### Phase 4: Documentation

#### Task 5: Update [`README.md`](../README.md) Fresh-clone bootstrap section

**Description:** Light touch on [`README.md`](../README.md) lines 15–43.
The bootstrap one-liner at line 20 stays unchanged (`install.sh` is now an
orchestrator at the same path). Add ONE sentence after line 24's "The
[bootstrap script](install.sh) is idempotent…" paragraph noting that
advanced users can call `install-root.sh` and `install-user.sh` independently
— root half needs sudo, user half explicitly refuses sudo. Also note the
new npm-prefix behaviour in one line, so the reader doesn't get confused
why their `npm config get prefix` suddenly says `~/.npm-global`.

**Acceptance criteria:**
- [ ] [`README.md`](../README.md) "Fresh-clone bootstrap" section mentions
      that `install.sh` is now an orchestrator, with the two halves
      independently runnable.
- [ ] Mentions the npm-prefix flip and the PATH requirement (one line, not
      a sub-section).
- [ ] Bootstrap one-liner at line 20 is unchanged.
- [ ] No incidental reflowing of other paragraphs.

**Verification:**
- [ ] `git diff README.md` shows the additions in one contiguous block, no
      drive-by edits.
- [ ] `rg -n 'install-(root|user|lib)\.sh' README.md` returns at least one
      hit per filename.

**Dependencies:** Task 4 (document only after the orchestrator is in place,
so the README describes shipping behaviour).

**Files likely touched:**
- [`README.md`](../README.md) (~3-5 lines added)

**Estimated scope:** **XS** — single doc edit.

### Checkpoint: End of Phase 4

- [ ] All five tasks' acceptance criteria met.
- [ ] `shellcheck install.sh install-root.sh install-user.sh install-lib.sh`
      exits 0.
- [ ] End-to-end re-run produces no `installing:` / `cargo install` write
      activity (the bootstrap is idempotent on an already-bootstrapped
      machine — same property as today's
      [`install.sh`](../install.sh)).
- [ ] `git status` shows: modified [`install.sh`](../install.sh),
      modified [`README.md`](../README.md), three new files
      (`install-root.sh`, `install-user.sh`, `install-lib.sh`).
- [ ] Pre-existing dirty files ([`custom.el`](../custom.el),
      [`_doc/GO.md`](../_doc/GO.md), [`FEATURES.md`](../FEATURES.md), and
      the Lua-work [`tasks/`](.) directory) stay out of this commit.
- [ ] Commit per [repo commit conventions](../../CLAUDE.md):
      `install: split into root (apt) and user (cargo/go/rustup/npm) scopes`
      — single commit bundling the four-file refactor + the README update,
      matching the `<area>: <verb> <thing>` style of recent commits.
- [ ] Pause and let the user verify on their machine before any follow-up
      work.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `exec sudo "$0" "$@"` shellcheck warning on argument splitting | Low — idiom is standard | If `SC2128` or similar fires, switch to `exec sudo --preserve-env=PATH bash "$0" "$@"` (explicit interpreter) |
| `npm config set prefix` mutates user-global npm state | Low — single-user repo, one machine | Conditional fires only when prefix is still the root-requiring default (`/usr/local` or `/usr`); subsequent runs no-op; printed in `[ok]` line so the change is visible in output |
| `$HOME/.npm-global/bin` not on PATH after npm-prefix flip | Medium — user runs `npm install -g foo`, then `foo` not found | Manual-follow-ups heredoc gets a new top bullet flagging the PATH requirement; this is a one-time setup step, not a per-run problem |
| `apt update` no longer behind `sudo` prefix in `install-root.sh` | Low — script is already root post-elevate | Acceptance criterion on Task 2 explicitly checks for absence of `sudo` prefix; shellcheck `SC2086`-class warnings are unrelated |
| User runs `bash install-user.sh` BEFORE `install-root.sh` on a fresh machine, hitting a missing apt dep (e.g. cargo not installed) | Low — all user-section steps `have <cmd>` skip when toolchain is absent | Existing skip semantics preserve correctness; first run of `install-user.sh` on a clean machine simply prints `[skip]` for everything until [`install-root.sh`](../install-root.sh) runs separately. Orchestrator `install.sh` always calls root first. |
| Chinese comments lost during refactor | Low — pure copy | Acceptance criterion calls out byte-identical preservation; spot-check after each Edit |
| Breaking change to README bootstrap path | Zero | [`install.sh`](../install.sh) stays at the same path with the same name — same one-liner works |
| Existing `tasks/plan.md` / `tasks/todo.md` (Lua work) collision | None | This plan lives at `install-split-plan.md` / `install-split-todo.md` — distinct filenames, disjoint scope |

## Open Questions

None blocking. Surface to the user after Phase 4 ships, not before:

- Should `install.sh` accept flags (`--root-only`, `--user-only`) instead
  of running both unconditionally? Adds a small amount of arg-parsing for
  marginal value — defer unless the user asks.
- Should `apt update` gain a "stamp file older than 24h" guard? Flagged in
  [`SPEC.md` "Open Questions"](../SPEC.md#open-questions) — deferred.

## Parallelization

Tasks 2 and 3 are independent after Task 1 lands. In a single-session run
they go sequentially (Task 2 → Task 3 → checkpoint). If multi-session
work makes sense at any point, they're the cleanest fan-out point.
