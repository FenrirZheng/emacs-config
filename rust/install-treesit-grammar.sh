#!/usr/bin/env bash
#
# install-treesit-grammar.sh — build & deploy the Rust tree-sitter grammar,
# pinned to an ABI-14 tag, for this Emacs.
#
# WHY this exists (short version): Emacs 30.1 on Debian trixie is linked against
# libtree-sitter 0.22.6, which caps the grammar ABI at 14 (`M-:
# (treesit-library-abi-version)` => 14). tree-sitter-rust master is ABI 15 since
# v0.24.0, so a grammar built from master loads as `(nil version-mismatch 15)`
# and `rust-ts-mode` falls over. Debian can't lift the cap by `apt upgrade`
# (both emacs and libtree-sitter are already at their newest trixie candidate),
# so we pin the grammar to the newest ABI-14 tag instead. Full rationale +
# folder layout: see the companion README ([rust/README.md](README.md)). The
# matching `treesit-auto` pin lives in
# [lisp/languages/init-rust.el](../lisp/languages/init-rust.el) — keep
# GRAMMAR_TAG below in sync with its `abi14-revision`.
#
# This script is standalone: it does NOT need a running Emacs daemon. It mirrors
# what `M-x treesit-install-language-grammar` does internally (clone -> cc
# -fPIC -> link a shared object), then verifies the result in a throwaway
# `emacs -Q --batch` so a broken build fails loudly here, not at first `.rs`
# visit.
#
set -euo pipefail

# ---- config (single source of truth) ------------------------------------
LANG_NAME="rust"
REPO_URL="https://github.com/tree-sitter/tree-sitter-rust"
# v0.23.3 is the newest tag still at tree-sitter LANGUAGE_VERSION 14
# (v0.24.0 is the first ABI-15 tag). MUST match `abi14-revision` in
# ../lisp/languages/init-rust.el.
GRAMMAR_TAG="v0.23.3"
SRC_SUBDIR="src"   # where parser.c / scanner.c live inside the grammar repo
# -------------------------------------------------------------------------

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emacs_dir="$(cd "$here/.." && pwd)"
treesit_dir="$emacs_dir/tree-sitter"           # where Emacs looks (treesit-extra-load-path)
repo_dir="$here/tree-sitter-${LANG_NAME}"      # persistent source checkout (gitignored)
build_dir="$here/build"                        # objects + .so (gitignored)
so_name="libtree-sitter-${LANG_NAME}.so"

CC="${CC:-cc}"
CXX="${CXX:-c++}"

log() { printf '>> %s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found on PATH"
command -v "$CC" >/dev/null 2>&1 || die "C compiler '$CC' not found on PATH"

# ---- 1. fetch the pinned grammar source ---------------------------------
if [ -d "$repo_dir/.git" ]; then
  log "updating $(basename "$repo_dir") -> $GRAMMAR_TAG"
  git -C "$repo_dir" fetch --tags --depth 1 origin "$GRAMMAR_TAG"
  git -C "$repo_dir" checkout -q "$GRAMMAR_TAG"
else
  log "cloning $REPO_URL @ $GRAMMAR_TAG"
  git clone --depth 1 --branch "$GRAMMAR_TAG" "$REPO_URL" "$repo_dir"
fi

src="$repo_dir/$SRC_SUBDIR"
[ -f "$src/parser.c" ] || die "$src/parser.c not found (wrong SRC_SUBDIR or tag?)"

# ---- 2. compile parser.c (+ external scanner if the grammar ships one) ---
# tree-sitter-rust ships BOTH parser.c and scanner.c; a parser-only build would
# dlopen-fail on the undefined external-scanner symbols, so the scanner is not
# optional here. The .c/.cc detection keeps the script reusable for grammars
# that have a C++ scanner (link with c++ then, for libstdc++).
mkdir -p "$build_dir"
objs=()
link="$CC"

log "compiling parser.c"
"$CC" -fPIC -c -I"$src" "$src/parser.c" -o "$build_dir/parser.o"
objs+=("$build_dir/parser.o")

if [ -f "$src/scanner.c" ]; then
  log "compiling scanner.c"
  "$CC" -fPIC -c -I"$src" "$src/scanner.c" -o "$build_dir/scanner.o"
  objs+=("$build_dir/scanner.o")
elif [ -f "$src/scanner.cc" ]; then
  log "compiling scanner.cc (C++)"
  "$CXX" -fPIC -c -I"$src" "$src/scanner.cc" -o "$build_dir/scanner.o"
  objs+=("$build_dir/scanner.o")
  link="$CXX"
fi

log "linking $so_name"
"$link" -shared "${objs[@]}" -o "$build_dir/$so_name"

# ---- 3. deploy into Emacs' tree-sitter dir ------------------------------
mkdir -p "$treesit_dir"
install -m 0755 "$build_dir/$so_name" "$treesit_dir/$so_name"
log "installed -> $treesit_dir/$so_name"

# ---- 4. verify ABI in a clean Emacs (no daemon dlopen-cache to fool us) --
if command -v emacs >/dev/null 2>&1; then
  log "verifying in a fresh 'emacs -Q --batch' ..."
  emacs -Q --batch --eval "(progn
    (add-to-list 'treesit-extra-load-path \"$treesit_dir\")
    (let ((r (treesit-language-available-p '${LANG_NAME} t)))
      (princ (format \"   ${LANG_NAME} grammar: %S\n\" r))
      (unless (car r) (kill-emacs 1))))" \
    || die "grammar built but Emacs rejected it (see status above)"
  log "OK: ${LANG_NAME} grammar loads (ABI <= 14)."
else
  log "emacs not on PATH; skipped load verification."
fi

cat <<EOF

Done.

NOTE: a RUNNING Emacs daemon has the previous grammar dlopen'd and will NOT pick
up the new .so until restarted (same path, cached handle):

    # confirm nothing unsaved first:
    emacsclient -e '(length (seq-filter (lambda (b) (and (buffer-file-name b) (buffer-modified-p b))) (buffer-list)))'
    systemctl --user restart emacs

A fresh Emacs / the next daemon start uses the new grammar automatically.
EOF
