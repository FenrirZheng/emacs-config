#!/usr/bin/env bash
# fixture.sh [bin] — 驗收條件 1, 2 and 3 of the magit-nested-repos spec, run literally.
#
# Builds /tmp/magit-nested-fixture with the spec folder's make-fixture.sh (its layout is
# documented there), then runs the helper and compares whole outputs against the lines the
# fixture's construction predicts.  Every expected value below is derived from the fixture
# (git rev-parse for the commit ids), never from the binary under test.
#
# bin defaults to the deployed rust/lib/git-nested-status.  Prints `ok <what>` per check and
# `FAIL <what>` with a diff on a mismatch; exits 1 if anything failed.  stderr of every run
# must be empty.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../../.." && pwd)                   # ~/.emacs.d
bin=${1:-$root/rust/lib/git-nested-status}
fixture=/tmp/magit-nested-fixture
mk=$root/sliced-spec/2026-10-14/120738-magit-nested-repos/make-fixture.sh

[[ -x $bin ]] || { echo "FAIL $bin is not executable (make -C rust/git-tools)" >&2; exit 1; }
bash "$mk" "$fixture" >/dev/null

fails=0
check() {  # check <what> <expected-file> <actual-file>
  if diff -u "$2" "$3" >/tmp/magit-nested-fixture.diff; then echo "ok $1"
  else echo "FAIL $1"; cat /tmp/magit-nested-fixture.diff; fails=$((fails + 1)); fi
}
run() {  # run <args...>: stdout to $out, stderr must be empty
  out=$(mktemp); err=$(mktemp)
  "$bin" -C "$fixture" "$@" >"$out" 2>"$err" || { echo "FAIL exit $? for: $*"; cat "$err"; fails=$((fails + 1)); }
  if [[ -s $err ]]; then echo "FAIL stderr not empty for: $*"; cat "$err"; fails=$((fails + 1)); fi
}
short() { git -C "$fixture/$1" rev-parse --short HEAD; }
clean=$(short repos/clean); detached=$(short repos/detached); dirty=$(short repos/dirty); deep=$(short deep/x/y)
hdr='# git-nested-status v1'
row_clean=$(printf 'R\trepos/clean\tmain\t%s\torigin/main\t0\t0\t0\t0\t0' "$clean")
row_detached=$(printf 'R\trepos/detached\t-\t%s\t-\t-\t-\t0\t0\t0' "$detached")
row_dirty=$(printf 'R\trepos/dirty\tmain\t%s\torigin/main\t1\t0\t0\t1\t1' "$dirty")
row_deep=$(printf 'R\tdeep/x/y\tmain\t%s\torigin/main\t0\t0\t0\t0\t0' "$deep")

# 1. --porcelain: header, then exactly clean, detached, dirty, in that order (no plain, no deep).
run --porcelain
printf '%s\n' "$hdr" "$row_clean" "$row_detached" "$row_dirty" >"$out.want"
check "1 --porcelain lists the three clones with the fixture's values" "$out.want" "$out"

# 2. nested.depth 3 adds deep/x/y; nested.depth 0 gives the header only; nested.path deep/x gives deep/x/y only.
git -C "$fixture" config nested.depth 3
run --porcelain
printf '%s\n' "$hdr" "$row_deep" "$row_clean" "$row_detached" "$row_dirty" >"$out.want"
check "2a nested.depth 3 adds deep/x/y" "$out.want" "$out"
git -C "$fixture" config nested.depth 0
run --porcelain
printf '%s\n' "$hdr" >"$out.want"
check "2b nested.depth 0 lists nothing" "$out.want" "$out"
git -C "$fixture" config --unset nested.depth
git -C "$fixture" config --add nested.path deep/x
run --porcelain
printf '%s\n' "$hdr" "$row_deep" >"$out.want"
check "2c nested.path deep/x lists deep/x/y only" "$out.want" "$out"
git -C "$fixture" config --unset-all nested.path

# 3. --files: one F line per uncommitted path under repos/dirty, none under repos/clean.
run --porcelain --files
printf '%s\n' "$hdr" "$row_clean" "$row_detached" "$row_dirty" $'F\tunstaged\ta.txt' $'F\tuntracked\tnew.txt' >"$out.want"
check "3 --files lists repos/dirty's two paths with their kinds" "$out.want" "$out"

rm -f "$out" "$out.want" "$err" /tmp/magit-nested-fixture.diff
if (( fails )); then echo "$fails check(s) FAILED"; exit 1; fi
echo "all checks ok ($fixture left in place)"
