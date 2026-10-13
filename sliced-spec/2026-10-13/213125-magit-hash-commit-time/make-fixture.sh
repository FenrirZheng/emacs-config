#!/usr/bin/env bash
# Build the throwaway repo the 驗收條件 in SPEC.md run against.
# Usage: make-fixture.sh /tmp/magit-time-fixture
# Two commits by "Fixture Author"; author date 2026-01-02 03:04 +0800,
# committer date 2026-02-03 04:05 +0800 (deliberately different); no upstream.
set -euo pipefail
dir=${1:?usage: make-fixture.sh <dir>}
marker=.magit-time-fixture
if [[ -e $dir ]]; then
  [[ -e $dir/$marker ]] || { echo "refusing: $dir exists and is not a fixture" >&2; exit 1; }
  rm -rf -- "$dir"
fi
mkdir -p -- "$dir"
cd -- "$dir"
: > "$marker"
export GIT_AUTHOR_NAME="Fixture Author" GIT_AUTHOR_EMAIL=author@example.invalid
export GIT_COMMITTER_NAME="Fixture Committer" GIT_COMMITTER_EMAIL=committer@example.invalid
export GIT_AUTHOR_DATE="2026-01-02T03:04:00+08:00" GIT_COMMITTER_DATE="2026-02-03T04:05:00+08:00"
git -c init.defaultBranch=main init -q
for n in one two; do
  echo "$n" > "$n.txt"
  git add -- "$n.txt"
  git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "fixture $n"
done
echo "$dir"
