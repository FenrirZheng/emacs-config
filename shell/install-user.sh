#!/usr/bin/env bash
# install-user.sh — user-scope deps for ~/.emacs.d.
# Refuses to run as root (cargo/go/rustup/npm caches would land under /root/).
# Idempotent: re-run anytime; already-installed components are no-ops.
#
# Sections:
#   1. npm globals  — LSPs / formatters / linters (skipped if no npm)
#   2. cargo        — emacs-lsp-booster, difftastic (skipped if no cargo)
#   3. go install   — gopls (skipped if no go)
#   4. rustup       — rust-analyzer component (skipped if no rustup)
#   5. terminfo     — tmux-256color +setf24/setb24 for Emacs TTY truecolor
#   6. lua-ls       — lua-language-server (GitHub release tarball; not on apt)
#   7. reminders    — manual follow-ups printed at end

if [ -z "${BASH_VERSION:-}" ]; then
  echo "install-user.sh: must be run with bash (you used sh/dash, which has no arrays)" >&2
  echo "  try:  bash $0    or just:  $0" >&2
  exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-lib.sh
. "$SCRIPT_DIR/install-lib.sh"

if [ "$EUID" -eq 0 ]; then
  echo "install-user.sh: refuse to run as root — cargo/go/rustup/npm caches" >&2
  echo "  would land under /root/. Run as your normal user without sudo." >&2
  exit 1
fi

# ── 1. npm globals ──────────────────────────────────────────────────────
section "npm globals"
if have npm; then
  # If npm's global prefix is still a root-requiring default, flip it to a
  # user-writable path so `npm install -g` no longer needs sudo. Idempotent:
  # the conditional no-ops on subsequent runs.
  npm_prefix="$(npm config get prefix 2>/dev/null || echo /usr/local)"
  npm_prefix_flipped=0
  if [ "$npm_prefix" = "/usr/local" ] || [ "$npm_prefix" = "/usr" ]; then
    npm config set prefix "$HOME/.npm-global"
    ok "npm prefix → $HOME/.npm-global  (add \$HOME/.npm-global/bin to PATH)"
    npm_prefix_flipped=1
  fi
  npm install -g \
    typescript typescript-language-server \
    vscode-langservers-extracted \
    prettier eslint \
    pyright
else
  skip "npm 不在 PATH — LSP / formatter 跳過; 自行裝 node 後重跑此腳本"
fi

# ── 2. cargo ────────────────────────────────────────────────────────────
section "cargo crates"
if have cargo; then
  # emacs-lsp-booster: version pin matches init.el:713
  cargo install --locked --version 0.2.1 emacs-lsp-booster
  cargo install --locked difftastic
else
  skip "cargo 不在 PATH — emacs-lsp-booster / difftastic 跳過"
fi

# ── 3. go install ───────────────────────────────────────────────────────
section "go binaries"
if have go; then
  go install golang.org/x/tools/gopls@latest
else
  skip "go 不在 PATH — gopls 跳過"
fi

# ── 4. rustup component ─────────────────────────────────────────────────
section "rustup components"
if have rustup; then
  rustup component add rust-analyzer
else
  skip "rustup 不在 PATH — rust-analyzer 跳過"
fi

# ── 5. terminfo ─────────────────────────────────────────────────────────
section "terminfo (Emacs truecolor)"
# Emacs emits 24-bit colour on a TTY only when terminfo carries the non-standard
# setf24/setb24 caps — it ignores $COLORTERM. Append those two caps to the live
# system tmux-256color entry and compile into ~/.terminfo, which ncurses searches
# before /usr/share/terminfo: the result shadows the stock entry, so tmux.conf's
# `default-terminal "tmux-256color"' needs no edit. A fresh `emacsclient -t'
# frame picks it up — terminfo is read per-frame, the daemon need not restart.
if have tic && infocmp tmux-256color >/dev/null 2>&1; then
  {
    infocmp -x tmux-256color
    # value packs the colour as one int: R=p1/65536, G=(p1/256)&255, B=p1&255
    printf '\t%s\n' \
      'setf24=\E[38;2;%p1%{65536}%/%d;%p1%{256}%/%{255}%&%d;%p1%{255}%&%dm,' \
      'setb24=\E[48;2;%p1%{65536}%/%d;%p1%{256}%/%{255}%&%d;%p1%{255}%&%dm,'
  } | tic -x -o "$HOME/.terminfo" -    # -x keeps the extended setf24/setb24 caps
  ok "~/.terminfo tmux-256color +setf24/setb24 — open a fresh 'emacsclient -t' frame"
else
  skip "tic / tmux-256color terminfo 不在 (apt: ncurses-bin ncurses-term) — TTY 真色彩跳過"
fi

# ── 6. lua-language-server ──────────────────────────────────────────────
# LuaLS isn't on apt and isn't a cargo/go/npm package — it ships as a
# self-contained tarball on upstream GitHub releases. Extract the WHOLE
# archive into ~/.local/share/ (the bin/ launcher needs its sibling
# script/ meta/ locale/ dirs), then symlink the launcher onto PATH. Eglot
# attaches it to `lua-mode' — see lisp/languages/init-lua.el. Idempotent: the
# version probe skips the download when the pinned release is already in.
section "lua-language-server"
luals_version="3.18.2"
luals_dest="$HOME/.local/share/lua-language-server"
luals_link="$HOME/.local/bin/lua-language-server"
if [ "$("$luals_link" --version 2>/dev/null | cut -d- -f1)" = "$luals_version" ]; then
  ok "lua-language-server $luals_version already installed"
elif have curl && have tar; then
  luals_url="https://github.com/LuaLS/lua-language-server/releases/download/${luals_version}/lua-language-server-${luals_version}-linux-x64.tar.gz"
  luals_tmp="$(mktemp -d)"
  if curl -fsSL -o "$luals_tmp/lls.tar.gz" "$luals_url"; then
    rm -rf "$luals_dest"
    mkdir -p "$luals_dest" "$HOME/.local/bin"
    tar -xzf "$luals_tmp/lls.tar.gz" -C "$luals_dest"
    ln -sfn "$luals_dest/bin/lua-language-server" "$luals_link"
    ok "lua-language-server $luals_version → $luals_dest"
  else
    skip "lua-language-server 下載失敗 — 檢查網路後重跑此腳本"
  fi
  rm -rf "$luals_tmp"
else
  skip "curl / tar 不在 PATH — lua-language-server 跳過"
fi

# ── 7. manual follow-ups ────────────────────────────────────────────────
section "Manual follow-ups"
if [ "${npm_prefix_flipped:-0}" -eq 1 ]; then
  echo '  • PATH: add $HOME/.npm-global/bin to your shell rc (npm prefix lives there now)'
fi
cat <<'EOF'
  • First Emacs launch: M-x nerd-icons-install-fonts (downloads TTFs once)
  • jinx compiles its C module on first load (~2s; needs libenchant-2-dev)
  • vterm compiles its C module on first launch (needs cmake + libvterm-dev)
  • Tree-sitter css/json/lua are ABI 15 and unusable on Emacs 30 (ABI 14);
    the treesit-auto exclusion in lisp/init-languages.el routes around this,
    with lua → lua-mode font-lock + lua-language-server LSP wired in
    lisp/languages/init-lua.el (server installed in section 6 above)
EOF
