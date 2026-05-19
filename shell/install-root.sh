#!/usr/bin/env bash
# install-root.sh — root-scope deps for ~/.emacs.d (apt packages).
# Self-elevates if EUID != 0. Idempotent: re-run anytime;
# already-installed packages are no-ops.

if [ -z "${BASH_VERSION:-}" ]; then
  echo "install-root.sh: must be run with bash (you used sh/dash, which has no arrays)" >&2
  echo "  try:  bash $0    or just:  $0" >&2
  exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-lib.sh
. "$SCRIPT_DIR/install-lib.sh"

if [ "$EUID" -ne 0 ]; then
  exec sudo --preserve-env=PATH "$0" "$@"
fi

# ── 1. apt ──────────────────────────────────────────────────────────────
section "apt packages"
APT_PKGS=(
  # core — config 載入必要
  ripgrep fd-find
  enchant-2 libenchant-2-dev          # jinx  (init.el:549-559)
  cmake libvterm-dev                  # vterm (init.el:1097-1106)
  build-essential                     # treesit grammar 編譯 (init.el:874)
  # recommended — 缺了功能會降級但 Emacs 仍可啟動
  graphviz                            # org-roam-graph (init.el:1213)
  direnv                              # envrc          (init.el:636-638)
  git-delta                           # magit-delta    (init.el:1060-1063)
  clangd                              # eglot C/C++    (init.el:643)
)
missing=()
for p in "${APT_PKGS[@]}"; do
  if dpkg_installed "$p"; then
    ok "$p"
  else
    missing+=("$p")
  fi
done
if (( ${#missing[@]} > 0 )); then
  printf '  installing: %s\n' "${missing[*]}"
  apt update
  apt install -y "${missing[@]}"
fi
