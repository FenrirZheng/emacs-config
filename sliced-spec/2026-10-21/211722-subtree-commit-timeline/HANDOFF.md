# Handoff: Magit — one commit timeline across every git subtree

Updated: 2026-10-21 21:50 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- The whole timeline feature in one slice: parser, labeller, mode, command, `l A`, ERT and
  FEATURES.md. Commit `magit-subtree: add a cross-subtree commit timeline (l A)`.
- One git menu: `<f5> g` gains a second row with the subtree commands and every `C-x v`
  command, plus the approved SPEC change (goal "one git menu", 驗收條件 8 reworded, 9–11
  added, the `init-keys.el` limit changed). Commit
  `keys: make <f5> g the one git menu, subtree commands included`.
  - Self-checks on 2026-10-21 (not yet the acceptance gate):
    - ERT: 16/16 pass.
    - `check-hub-git.el` after a full batch init: `magit loaded: nil`, 37 suffix commands,
      `missing: none`, `not callable: none`. With `fenrir/magit-subtree-log` unbound first
      it prints `not callable: fenrir/magit-subtree-log`, so the check is not vacuous.
    - Daemon, after reloading `init-git.el` and `init-keys.el`: `fenrir/hub-git` key `A`
      is `fenrir/magit-subtree-commits`; magit-log `A` is still present.
    - No `.elc` left.

## 決定與原因

- Elisp, not Rust. The refresh measured 0.19 s for 30 days, under 驗收條件 7's 0.5 s bound.
- The default revs are `--branches`. The `p/*` refs are remote-tracking refs
  (`refs/remotes/p/...`) in this repo, not local heads, so no `--exclude` is needed.
- git is run with `process-file`, not `magit-git-insert`: the latter turned the `%x00`
  separators into spaces.
- The timeline's buffer-locals are read before entering `with-temp-buffer`. Inside it they
  read as nil, which once made the list empty.
- Known label limit: a project commit imported by a subtree merge has project-relative
  paths, so it shows as `(umbrella)`. This is noted in FEATURES.md.
- The three subtree commands get plain `autoload` forms in `init-git.el`, not
  `fenrir/hub--defwrapper` wrappers: SPEC 限制 says no command is defined in
  `init-keys.el`. Loading the module before Magit was tested in batch; no recursive-require
  error.
- Menu letters: `C-x v` letters are kept where free in `fenrir/hub-git`; the clashes took
  `U` (revert file), `i` (diff menu), `C` (log current), `j` (merge), `T` (tag).
- The previous gate run (2026-10-21 21:37, `24361ac`) failed 驗收條件 8 only on the old
  "`l A` next to `l S`" wording, which the approved SPEC change replaced. It is superseded;
  the next gate is a whole new run.

## 下一步

Run the acceptance gate (`/sliced-spec next`), a whole run over 驗收條件 1–11. 4–7 use the
live daemon and the real repo; 11 is the user pressing `<f5> g` and the timeline key.

## 卡住・待確認

(none)
