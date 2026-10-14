#!/usr/bin/env bash
# check-repo.sh <repo> [bin] — 驗收條件 6 and 7 of the magit-nested-repos spec on a real repo.
#
# 6. The clones the helper lists are exactly the directories with their own .git that
#    `find <repo> -mindepth 2 -maxdepth 3 -name .git` finds (a .git two or three levels
#    down = a clone one or two levels down, the default depth), minus any whose ancestor is
#    itself a clone: the helper never looks inside a clone, so a clone nested in a clone
#    belongs to the outer one.  <repo> is read with its own nested.* config, so run this on
#    a repo without such config (yeeya has none).
# 7. The 10-run median of `--porcelain --files`, warm (one untimed warm-up first), printed
#    in ms and checked against the 100 ms bound.  GNS_BENCH=0 skips the timing.
#
# bin defaults to the deployed rust/lib/git-nested-status.  Read-only: nothing is written.
set -euo pipefail
repo=${1:?usage: check-repo.sh <repo> [bin]}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin=${2:-$(cd "$here/../../../.." && pwd)/rust/lib/git-nested-status}
repo=$(cd "$repo" && pwd)
[[ -x $bin ]] || { echo "FAIL $bin is not executable (make -C rust/git-tools)" >&2; exit 1; }
fails=0

# ---- 6: the set of clones -------------------------------------------------
want=$(find "$repo" -mindepth 2 -maxdepth 3 -name .git \
  | sed "s#^$repo/##; s#/\.git\$##" | LC_ALL=C sort \
  | awk '{ keep = 1; for (i = 1; i <= n; i++) if (index($0, outer[i] "/") == 1) keep = 0; if (keep) { outer[++n] = $0; print } }')
got=$("$bin" -C "$repo" --porcelain | awk -F'\t' '$1 == "R" { print $2 }')
if [[ "$want" == "$got" ]]; then
  echo "ok 6 $(printf '%s\n' "$got" | ug -c . || true) clones, same set as find"
else
  echo "FAIL 6 clone sets differ (< find, > helper):"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") || true
  fails=$((fails + 1))
fi

# ---- 7: timing ------------------------------------------------------------
if [[ ${GNS_BENCH:-1} != 0 ]]; then
  "$bin" -C "$repo" --porcelain --files >/dev/null       # warm-up, untimed
  times=()
  for _ in $(seq 10); do
    s=$EPOCHREALTIME; "$bin" -C "$repo" --porcelain --files >/dev/null; e=$EPOCHREALTIME
    times+=("$(awk -v s="$s" -v e="$e" 'BEGIN { printf "%.1f", (e - s) * 1000 }')")
  done
  median=$(printf '%s\n' "${times[@]}" | sort -n | sed -n '5p;6p' | awk '{ s += $1 } END { printf "%.1f", s / 2 }')
  echo "7 median of 10 warm runs: $median ms (runs: ${times[*]})"
  if awk -v m="$median" 'BEGIN { exit !(m <= 100) }'; then echo "ok 7 median $median ms <= 100 ms"
  else echo "FAIL 7 median $median ms > 100 ms"; fails=$((fails + 1)); fi
fi

if (( fails )); then exit 1; fi
