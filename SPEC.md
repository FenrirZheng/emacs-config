# Spec: split `install.sh` into root-scope vs user-scope

Working tree: `/home/fenrir/.emacs.d` on branch `main`.
Source-of-truth before this change: [`install.sh`](shell/install.sh) (current monolith,
107 lines, six sections).

## Objective

Refactor the single bootstrap script into two independently-runnable scripts so
that the privilege boundary is explicit:

- **`install-root.sh`** — only the part that genuinely needs `sudo` (apt
  packages). Safe to hand off to a sysadmin or run once per machine.
- **`install-user.sh`** — everything that should write to the invoking user's
  home directory (`$HOME/.cargo`, `$HOME/go`, `$HOME/.rustup`, `$HOME/.npm-global`).
  Must NOT be run as root, or those caches end up owned by root and break next
  user-mode invocation.

Why this matters: today's [`install.sh`](shell/install.sh) mixes `sudo apt …` with
`cargo install …` in the same `set -euo pipefail` flow. If the caller forgets
and runs it under `sudo`, every cargo/go/rustup artefact lands in `/root/…` —
silent corruption the user discovers later. The split removes that footgun.

**npm-globals belongs in user scope** (per user clarification 2026-05-19):
`install-user.sh` reconfigures `npm config set prefix "$HOME/.npm-global"` on
first run so that `npm install -g` no longer needs `sudo`. PATH reminder
printed in the manual-follow-ups block.

### Target users

The single user of this dotfiles repo (one machine, one operator). The split is
about safety / mental clarity for that one user, not multi-tenant deployment.

## Tech Stack

- Pure `bash` (already required — [`install.sh:14-18`](shell/install.sh) gates on
  `BASH_VERSION`). No introduction of Make, Just, Ansible, or other tooling.
- Same external dependencies as today: `dpkg-query`, `apt`, optionally `npm`,
  `cargo`, `go`, `rustup`. All `have <cmd>` skips preserved.

## Commands

After the refactor:

| step | command | who runs it |
|---|---|---|
| install apt packages | `sudo bash install-root.sh` | root (or user under `sudo`) |
| install user-level toolchain pieces | `bash install-user.sh` | the user, **NOT** under `sudo` |
| one-shot orchestrator | `bash install.sh` | the user — internally calls `sudo` for the root half |
| verify shellcheck | `shellcheck install.sh install-root.sh install-user.sh install-lib.sh` | the user |

Each of the three scripts (`install.sh`, `install-root.sh`, `install-user.sh`)
is independently executable; `install.sh` is convenience, not a hard dependency.

## Project Structure

```
shell/install.sh       → thin orchestrator (entry point preserved for muscle memory)
shell/install-root.sh  → apt section only; self-elevates via exec sudo if EUID != 0
shell/install-user.sh  → cargo + go + rustup + npm-globals + manual reminders;
                         refuses to run if EUID == 0
shell/install-lib.sh   → shared helpers (have / dpkg_installed / section / ok / skip);
                         sourced by the three runnables, never executed directly
SPEC.md                → this file (added by this change)
```

All four shell files live under [`shell/`](shell/) — they were moved out of the
repo root after the split landed, so all install machinery sits in one folder.

## Code Style

Mirror the existing helpers in [`install.sh:21-29`](shell/install.sh) verbatim — they
move into `install-lib.sh` unchanged:

```bash
# install-lib.sh — shared helpers for install-{root,user}.sh.
# Source-only; do not execute directly.

have() { command -v "$1" >/dev/null 2>&1; }
dpkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null \
    | grep -q "install ok installed"
}
section() { printf '\n\033[1;34m── %s ──\033[0m\n' "$1"; }
ok()      { printf '  \033[32m[ok]\033[0m   %s\n' "$1"; }
skip()    { printf '  \033[33m[skip]\033[0m %s\n' "$1"; }
```

`install-root.sh` privilege-elevation idiom:

```bash
#!/usr/bin/env bash
# install-root.sh — root-scope deps (apt only). Self-elevates if EUID != 0.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-lib.sh
. "$SCRIPT_DIR/install-lib.sh"

if [ "$EUID" -ne 0 ]; then
  exec sudo --preserve-env=PATH "$0" "$@"
fi
# ... apt section ...
```

`install-user.sh` reverse-guard:

```bash
#!/usr/bin/env bash
# install-user.sh — user-scope deps. Refuses to run as root.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-lib.sh
. "$SCRIPT_DIR/install-lib.sh"

if [ "$EUID" -eq 0 ]; then
  echo "install-user.sh: refuse to run as root — cargo/go/rustup/npm caches" >&2
  echo "  would land under /root/. Run as your normal user without sudo." >&2
  exit 1
fi
# ... cargo / go / rustup / npm / reminders ...
```

`install.sh` post-refactor (orchestrator only):

```bash
#!/usr/bin/env bash
# install.sh — orchestrator. Calls install-root.sh (via sudo) then install-user.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo bash "$SCRIPT_DIR/install-root.sh"
bash "$SCRIPT_DIR/install-user.sh"
```

### npm-globals → user prefix idiom (the one new piece of logic)

Inside `install-user.sh`, before any `npm install -g`:

```bash
if have npm; then
  npm_prefix="$(npm config get prefix 2>/dev/null || echo /usr/local)"
  if [ "$npm_prefix" = "/usr/local" ] || [ "$npm_prefix" = "/usr" ]; then
    section "npm: switching global prefix to user-writable path"
    npm config set prefix "$HOME/.npm-global"
    ok "npm prefix → $HOME/.npm-global  (add $HOME/.npm-global/bin to PATH)"
  fi
  # then the existing npm install -g ... block, unchanged
fi
```

The PATH reminder also gets a line in the manual-follow-ups heredoc at the
bottom of `install-user.sh`.

## Testing Strategy

No test framework — these are bootstrap shell scripts run a handful of times
per machine. Verification is static + smoke:

- **Static**: `shellcheck install.sh install-root.sh install-user.sh install-lib.sh`
  must exit 0. The split should not regress any lint that the current
  monolith passes.
- **Idempotency smoke**: running each script twice in a row produces no
  failures and the second run's output is mostly `[ok]` / `[skip]` lines, no
  `installing:` lines. (Today's [`install.sh`](shell/install.sh) already has this
  property — preserve it.)
- **Privilege-guard smoke**:
  - `bash install-root.sh` with no `sudo` should re-exec under sudo (prompt for
    password) rather than fail with EACCES on `apt update`.
  - `sudo bash install-user.sh` should exit non-zero with the refuse-to-run
    message, NOT proceed to write `/root/.cargo/`.
- **npm-prefix smoke**: after a fresh `install-user.sh` run on a machine where
  `npm config get prefix` was `/usr/local`, the new prefix is `$HOME/.npm-global`
  and a subsequent `npm install -g pkg` (manual, outside this script) succeeds
  without `sudo`.

## Boundaries

- **Always**:
  - Preserve every existing `have <cmd>` skip — no new hard dependencies.
  - Preserve `dpkg_installed` idempotency — never re-`apt install` already-installed packages.
  - Preserve the `# ── N. <name> ──` section headers and `[ok]` / `[skip]`
    output style — the user reads these visually.
  - Keep the BASH_VERSION gate at the top of every runnable script (sh/dash
    has no arrays — same reason as today's [`install.sh:14-18`](shell/install.sh)).
  - `set -euo pipefail` at the top of every runnable; `set -u`-safe parameter
    expansion (`${VAR:-default}`) where applicable.
- **Ask first**:
  - Adding a sixth or seventh script — keep the surface area small.
  - Changing what goes in root vs user scope beyond the npm-globals move
    already specified.
  - Introducing a `Makefile` / `Justfile` / external runner.
- **Never**:
  - Run `sudo` inside `install-user.sh` (it's the user-scope script — if a
    step needs root, that step belongs in `install-root.sh`).
  - Use `npm install -g` without first ensuring the user-writable prefix is
    configured (defeats the whole "npm-in-user-scope" decision).
  - Touch the `cargo --locked --version 0.2.1 emacs-lsp-booster` pin without
    also updating [`init.el:713`](init.el) — the comment at
    [`install.sh:74`](shell/install.sh) flags this coupling.
  - Add backwards-compat shims for "what if someone still calls the old
    script?" — `install.sh` keeps working (it's now the orchestrator), no
    deprecation theatre needed.

## Success Criteria

1. `shellcheck install.sh install-root.sh install-user.sh install-lib.sh` exits 0.
2. Fresh machine flow works: `bash install.sh` from a clean checkout installs
   everything that today's [`install.sh`](shell/install.sh) installs, in one invocation,
   prompting for sudo password once.
3. `sudo bash install-user.sh` exits non-zero with the refuse message — does NOT
   write to `/root/.cargo/` or `/root/go/`.
4. `bash install-root.sh` from an unprivileged shell self-elevates (one sudo
   password prompt) and completes the apt section.
5. On a machine where `npm config get prefix` was `/usr/local`, running
   `bash install-user.sh` flips the prefix to `$HOME/.npm-global` and then
   `npm install -g` works without `sudo`. The manual-follow-ups block at end
   of `install-user.sh` reminds the user to add `$HOME/.npm-global/bin` to PATH.
6. Re-running any of the three scripts produces no `installing:` / `cargo
   install` write activity for already-installed components — output is
   dominated by `[ok]` / `[skip]` lines.
7. `git diff install.sh` shows the file shrunk to the orchestrator form (~8
   lines); the three new files (`install-root.sh`, `install-user.sh`,
   `install-lib.sh`) appear as untracked, ready to commit alongside.
8. No regression in the section coverage: every section in today's
   [`install.sh`](shell/install.sh) (apt / npm / cargo / go / rustup / reminders) is
   present in exactly one of the two new scripts.

## Open Questions

None blocking — proceed to plan / implement under the assumptions above. Note
for after implementation:

- Whether to also gate `install-root.sh`'s `apt update` behind a "stamp file
  is older than 24h" check, to avoid hitting Debian mirrors on every run. Not
  in scope for this change — current behaviour (`apt update` runs only when
  the `missing` array is non-empty) is already conservative.
