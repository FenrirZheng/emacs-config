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
