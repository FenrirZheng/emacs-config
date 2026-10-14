# Spec: git-nested-status — leave out the clones the umbrella gitignores, per repo

Status: draft
Date: 2026-10-14 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)

## 目標

- A repo can tell [`git-nested-status`](../../../rust/git-tools/git-nested-status/README.md)
  to leave out the nested clones that its own ignore rules hide. Then `~/.emacs.d`'s
  `package-vc` clones under the ignored `/elpa/` (`elpa/combobulate`, `elpa/eglot-booster`,
  `elpa/eglot-x`) stop appearing in the Magit **Nested repos** section, and in the CLI table.
- The skip is opt-in per repo, through the umbrella's git config. The default is unchanged:
  `~/code/yeeya` ignores `/repos/` the same way, and its 29 clones must stay listed with no
  config.
- "Ignored" means what `git check-ignore` says about the clone's path in the umbrella:
  every ignore source git consults (`.gitignore` files at any level, `.git/info/exclude`, and
  the global excludes file).
- A skipped clone is not counted: not in the Magit heading, not in the CLI summary line.
- The Magit side needs no new option; it draws what the helper returns, as today.

## 不做的事

- No change to the default: ignored clones stay listed unless the repo opts in.
- No per-clone or pattern exclude list (such as a `nested.exclude <dir>` config).
- No new Lisp defcustom, and no change to what `fenrir/magit-nested-skip-directories` means.
- No change to the porcelain format: `# git-nested-status v1` stays; rows are only filtered.
- No edit to the finished spec's
  [`make-fixture.sh`](../120738-magit-nested-repos/make-fixture.sh); the new checks add to the
  fixture after it is built.
- Rejected alternatives, both already available: `git -C ~/.emacs.d config nested.depth 0`
  and adding `~/.emacs.d/` to `fenrir/magit-nested-skip-directories`. Each hides every clone
  of the repo, not only the ignored ones.

## 驗收條件

Fixture setup (not under test):
`bash sliced-spec/2026-10-14/120738-magit-nested-repos/make-fixture.sh /tmp/magit-nested-fixture`,
then `git -C /tmp/magit-nested-fixture clone -q .origins/clean.git keep`. The umbrella's
`.gitignore` holds `/.origins/`, `/repos/` and `/deep/` only, so `keep` is a clone it does
**not** ignore: `git -C /tmp/magit-nested-fixture check-ignore -q keep` exits 1, and the same
for `repos/clean` exits 0. Expected rows come from `git check-ignore`, never from the binary.
Rows are byte-sorted: `deep/x/y` < `keep` < `repos/*`.

1. `git-nested-status -C /tmp/magit-nested-fixture --porcelain`, no `nested.*` config → the
   header, then rows for exactly `keep`, `repos/clean`, `repos/detached`, `repos/dirty`, in
   that order — test: `rust/git-tools/git-nested-status/tests/skip-ignored.sh` — 副作用:
   writes `/tmp/magit-nested-fixture`
2. After `git -C /tmp/magit-nested-fixture config nested.skipIgnored true`, the command of 1
   → the header, then the `keep` row only; stderr empty — test: the same script — 副作用:
   edits `/tmp/magit-nested-fixture/.git/config`
3. With `nested.skipIgnored true` and `git -C /tmp/magit-nested-fixture config nested.depth 3`,
   the command of 1 → still the `keep` row only (`deep/x/y` is under the ignored `/deep/`);
   with the config still `true`, `git-nested-status -C /tmp/magit-nested-fixture --porcelain --no-skip-ignored`
   → rows `deep/x/y`, `keep`, `repos/clean`, `repos/detached`, `repos/dirty`; after
   `git -C /tmp/magit-nested-fixture config --unset nested.skipIgnored`, the command of 1 →
   the same five rows — test: the same script — 副作用: edits
   `/tmp/magit-nested-fixture/.git/config`
4. With no `nested.*` config, `git-nested-status -C /tmp/magit-nested-fixture --porcelain --skip-ignored`
   → the same output as 2 — test: the same script — 副作用: writes
   `/tmp/magit-nested-fixture`
5. For every clone the run of 1 lists, it is in the run of 4 iff
   `git -C /tmp/magit-nested-fixture check-ignore -q <path>` exits 1 — test: the same script —
   副作用: none
6. After `git -C ~/.emacs.d config nested.skipIgnored true`,
   `git-nested-status -C ~/.emacs.d --porcelain --all` → the header line only, exit 0, stderr
   empty — test: manual (one command; the config line is the intended end state) — 副作用:
   sets `nested.skipIgnored` in `~/.emacs.d/.git/config` (not tracked)
7. The test sets `nested.skipIgnored true` in `~/.emacs.d/.git/config`, remembering any prior
   value; then `magit-status` on `~/.emacs.d` (batch Emacs with the packages in `elpa/`) → no
   `Nested repos` section, no error in `*Messages*`, and the helper ran once; the prior value
   is restored afterwards, also on failure. It does not depend on 6 having run — test:
   `test/magit-nested-test.el::skip-ignored-emacs-d` — 副作用: edits
   `~/.emacs.d/.git/config` (not tracked) and restores the prior value
8. With the fixture of the setup and `git -C /tmp/magit-nested-fixture config nested.skipIgnored true`,
   `magit-status` on `/tmp/magit-nested-fixture` → no `Nested repos` section (`keep`, the only
   unignored clone, is clean); after `--unset nested.skipIgnored`, `M-x fenrir/magit-nested-forget`
   and a refresh → the heading `Nested repos (2 changed of 4)` — test:
   `test/magit-nested-test.el::skip-ignored-fixture` — 副作用: writes
   `/tmp/magit-nested-fixture`, edits its `.git/config`
9. `rust/git-tools/git-nested-status/tests/check-repo.sh ~/code/yeeya` → prints `ok 6` (the
   same 29 clones as `find`) and `ok 7` (10-run warm median ≤ 100 ms) — test: that script —
   副作用: none
10. `git-nested-status -C ~/code/yeeya --porcelain --skip-ignored` → the header line only
    (every `repos/*` is under the ignored `/repos/`), exit 0, stderr empty — test: manual (one
    command) — 副作用: none
11. `cargo test -p git-nested-status` run in `rust/git-tools` → every test passes, including
    one on how the flags and the config resolve; `make -C ~/.emacs.d/rust verify` → exit 0 —
    test: those two commands — 副作用: writes `rust/lib/git-nested-status` and
    `rust/git-tools/target/` (both gitignored)
12. `emacs -Q --batch -l test/magit-nested-test.el -f ert-run-tests-batch-and-exit` in
    `~/.emacs.d` → all pass, the existing 11 plus the new ones;
    `fdfind --no-ignore -e elc --exclude elpa --exclude eln-cache .` there lists nothing —
    test: those two commands — 副作用: none
13. `git-nested-status --help` → mentions `nested.skipIgnored`, `--skip-ignored` and
    `--no-skip-ignored`; `ug -n skipIgnored rust/git-tools/git-nested-status/README.md FEATURES.md`
    in `~/.emacs.d` → a hit in each file — test: manual (two commands) — 副作用: none

## 限制

- **Existing environment to reuse**: the [`rust/git-tools`](../../../rust/git-tools/README.md)
  cargo workspace (gix 0.89 from the local cargo registry, rustc with mold,
  `make -C rust/git-tools` deploying into `rust/lib/`); the one Emacs 30.1 daemon and Magit
  from `elpa/`; [`lisp/fenrir-magit-nested.el`](../../../lisp/fenrir-magit-nested.el) and
  [`test/magit-nested-test.el`](../../../test/magit-nested-test.el); the fixture builder
  [`make-fixture.sh`](../120738-magit-nested-repos/make-fixture.sh), used as is;
  `~/code/yeeya` and `~/.emacs.d` as the real repos. Nothing else is created; fixtures live
  under `/tmp`.
- The helper stays read-only and offline: it never runs `git` and never writes into any
  repo. The ignore decision is computed in-process; `git check-ignore` is only the
  acceptance oracle.
- Dependencies stay gix and the standard library.
- The ignore check judges the clone's own path as a directory, the way `git check-ignore`
  does: an ignored ancestor ignores it, and a negation re-includes it.
- A skipped clone is not opened, so the skip never costs more than the read it replaces;
  criterion 9's 100 ms bound stands.
- `--help`, the crate README and [`FEATURES.md`](../../../FEATURES.md) change in the same
  commit as the code they describe.
- No `.elc` is left behind by any check.

## 待決問題

- The config key is `nested.skipIgnored`, a git boolean — default if unanswered: yes.
- CLI flags: `--skip-ignored` turns the skip on, `--no-skip-ignored` turns off a `true`
  config, as `--depth` overrides `nested.depth` — default if unanswered: both flags.
- Are `.git/info/exclude` and the global excludes file consulted, not only `.gitignore`? —
  default if unanswered: yes, whatever `git check-ignore` consults.
- Does a `nested.path` scan honour the skip too? — default if unanswered: yes; the filter
  applies after discovery, whatever the scope.
