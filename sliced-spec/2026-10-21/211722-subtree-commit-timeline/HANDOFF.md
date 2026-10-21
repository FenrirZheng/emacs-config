# Handoff: Magit — one commit timeline across every git subtree

Updated: 2026-10-21 22:09 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- The whole timeline feature in one slice: parser, labeller, mode, command, `l A`, ERT and
  FEATURES.md. Commit `magit-subtree: add a cross-subtree commit timeline (l A)`.
- One git menu: `<f5> g` gains a second row with the subtree commands and every `C-x v`
  command, plus the approved SPEC change (goal "one git menu", 驗收條件 8 reworded, 9–11
  added, the `init-keys.el` limit changed). Commit
  `keys: make <f5> g the one git menu, subtree commands included`.
- Acceptance gate, 2026-10-21, verified at `9dbae8e`: 驗收條件 1–10 pass (verifier), 11 pass
  (the user, manually). `Status: implemented` in commit
  `spec: mark subtree-commit-timeline implemented`, whose body holds the full report.
  Measured there: 579 rows for 30 days, refresh 0.206 s.

## 決定與原因

- Elisp, not Rust. The refresh measured 0.206 s for 30 days at the gate, under 驗收條件 7's
  0.5 s bound. Rust is the follow-up if that bound is ever missed.
- The default revs are `--branches`. The `p/*` refs are remote-tracking refs
  (`refs/remotes/p/...`) in this repo, not local heads, so no `--exclude` is needed.
- Known label limit: a project commit imported by a subtree merge has project-relative
  paths, so it shows as `(umbrella)`. This is noted in FEATURES.md.
- The three subtree commands get plain `autoload` forms in `init-git.el`, not
  `fenrir/hub--defwrapper` wrappers: SPEC 限制 says no command is defined in
  `init-keys.el`.

## 下一步

None: the spec is `implemented`. Follow-ups named in SPEC 不做的事 (listing `p/*`
project-side commits with patch-id dedup; a Rust parser if 驗收條件 7 fails) would each be a
new spec. `/sliced-spec ship` can record where it went.

## 卡住・待確認

- Open question raised while explaining the UI, not a 驗收條件: the label column pads with
  `length`, not `string-width` (`lisp/fenrir-magit-subtree.el:486`), so a non-ASCII project
  name would misalign. All labels today are ASCII.
