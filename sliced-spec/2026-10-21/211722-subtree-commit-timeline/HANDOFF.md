# Handoff: Magit — one commit timeline across every git subtree

Updated: 2026-10-21 21:26 (Asia/Taipei)
Spec: [SPEC.md](SPEC.md)

## 已完成

- The whole feature in one slice: parser, labeller, mode, command, `l A`, ERT and FEATURES.md.
  Commit `magit-subtree: add a cross-subtree commit timeline (l A)`.
  - Self-checks on 2026-10-21 (not yet the acceptance gate):
    - ERT: 16/16 pass.
    - Daemon, on `ig_lottery_hotfix` over 30 days: 578 rows, equal to the `git log` count;
      times are non-increasing.
    - Labels: `78e0443ed` → `odds-web-ag`, `fdf134a7e` → `clawer`,
      `29b40f061` → `clawer,(umbrella)`; `c8098f07b` is absent.
    - `RET` opens the revision buffer with `Subtree: repos/lottery/odds/odds-web-ag`.
    - Narrowing to `odds-server` leaves 1 row.
    - `l A` is present; a refresh takes 0.188 s.

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

## 下一步

Run the acceptance gate (`/sliced-spec next`). 驗收條件 4–7 use the live daemon and the real
repo.

## 卡住・待確認

(none)
