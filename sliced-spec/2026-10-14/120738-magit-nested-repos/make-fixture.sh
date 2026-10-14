#!/usr/bin/env bash
# Build the throwaway umbrella repo the 驗收條件 in SPEC.md run against.
# Usage: make-fixture.sh /tmp/magit-nested-fixture
#
# <dir>/                 umbrella repo: one commit on main; .gitignore hides the clones
#   .origins/<n>.git     bare origins the clones track (gitignored)
#   repos/dirty          clone of origin "dirty": +1 local commit on main (ahead 1),
#                        one unstaged edit (a.txt), one untracked file (new.txt)
#   repos/clean          clone of origin "clean", in sync, nothing to report
#   repos/detached       clone of origin "detached", checked out at a commit hash
#   repos/plain          a directory with one file and NO .git
#   deep/x/y             clone of origin "deep", three levels down (outside depth 2)
set -euo pipefail
dir=${1:?usage: make-fixture.sh <dir>}
marker=.magit-nested-fixture
if [[ -e $dir ]]; then
  [[ -e $dir/$marker ]] || { echo "refusing: $dir exists and is not a fixture" >&2; exit 1; }
  rm -rf -- "$dir"
fi
mkdir -p -- "$dir"
cd -- "$dir"
: > "$marker"
export GIT_AUTHOR_NAME="Fixture Author" GIT_AUTHOR_EMAIL=author@example.invalid
export GIT_COMMITTER_NAME="Fixture Committer" GIT_COMMITTER_EMAIL=committer@example.invalid
export GIT_AUTHOR_DATE="2026-01-02T03:04:00+08:00" GIT_COMMITTER_DATE="2026-01-02T03:04:00+08:00"
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null -c advice.detachedHead=false "$@"; }

# One bare origin per clone, each with one commit (a.txt).
mkdir .origins
make_origin() {
  local name=$1
  local work=.origins/$name.work
  g init -q "$work"
  echo "$name a" > "$work/a.txt"
  g -C "$work" add a.txt
  g -C "$work" commit -q -m "$name: initial"
  g clone -q --bare "$work" ".origins/$name.git"
  rm -rf -- "$work"
}
for n in dirty clean detached deep; do make_origin "$n"; done

# The umbrella itself.
g init -q
printf '/.origins/\n/repos/\n/deep/\n' > .gitignore
echo "umbrella" > README.md
g add .gitignore README.md "$marker"
g commit -q -m "umbrella: initial"

mkdir repos deep deep/x
g clone -q ".origins/dirty.git" repos/dirty
g clone -q ".origins/clean.git" repos/clean
g clone -q ".origins/detached.git" repos/detached
g clone -q ".origins/deep.git" deep/x/y

# repos/dirty: ahead 1, one unstaged edit, one untracked file.
echo "second" > repos/dirty/b.txt
g -C repos/dirty add b.txt
g -C repos/dirty commit -q -m "dirty: second"
echo "edited" >> repos/dirty/a.txt
echo "new" > repos/dirty/new.txt

# repos/detached: HEAD at a commit hash.
g -C repos/detached checkout -q --detach HEAD

# repos/plain: no .git at all.
mkdir repos/plain
echo "plain" > repos/plain/file.txt

echo "$dir"
