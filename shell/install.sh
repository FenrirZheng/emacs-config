#!/usr/bin/env bash
# install.sh — orchestrator: bootstrap external system deps for ~/.emacs.d.
# Calls install-root.sh (apt, needs sudo) then install-user.sh
# (cargo / go / rustup / npm + manual reminders). Both halves are
# independently runnable; see ../SPEC.md for the privilege boundary rationale.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo bash "$SCRIPT_DIR/install-root.sh"
bash "$SCRIPT_DIR/install-user.sh"
