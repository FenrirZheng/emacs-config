# Review context

Date: 2026-09-10, Asia/Taipei (UTC+08:00).
Purpose: one Claude design discussion, two independent Claude spec reviews, and a separate Codex review, requested by the user for `sdlc next magit-status-overview`.
Repository: `/home/fenrir/.emacs.d`, main at `d65ffc852c29fdb2c0c5600074f7181b6ffc0001`.
Input: `spec-v1.snapshot`, SHA-256 `46802f5e951552106798c768f332374caa4881a8303cc092cb43dc8590229e2a`.
Tracked code clean at dispatch; unrelated untracked `AGENTS.md` and `records/` excluded. New spec and evidence owned by Codex.

## Peer transport and ownership

Authorized tmux socket `/tmp/tmux-1000/default`; Codex pane `%57`; discussion `%60`; review A `%59`; review B `%56`. Each receiver enrolled itself, ACKed its exact envelope, and reported running in `/tmp/magit-spec-peers/mailbox.sqlite`. Runtime/model identities are cooperative self-reports, with pane metadata cross-checks. All three declared Claude Code / `claude-opus-5[1m]`.

Peers were forbidden from project writes, live Emacs mutations, Git staging/commits, and spawning agents. Each owned only its distinct result Markdown under `/tmp/magit-spec-peers`. Codex preserves copies here after digest verification. The SQLite store is a task coordination record, not an artifact acceptance mechanism.

## Reading historical reviews

Reviews address their named immutable snapshot. Later dispositions belong in the consolidated review; they do not overwrite historical findings. In particular, `claude-discussion.md` contains withdrawn recommendations followed by a superseding addendum. Its statement that no status-capable cache-preserve hook exists is not accepted: `magit-section.el:521–522` supplies another source registration path. Runtime observation still found no direct hook entry in the current buffer; see `../baseline.md` for precise limits. The recommendation to leave a folded untracked group untouched was also not adopted: the overview opens existing change groups, allowing native bounded lazy display.

No UI implementation or interactive acceptance testing is claimed. Snapshot files were not staged by the reviewers. The coordinator intentionally includes the relevant snapshots and handoffs with the completed SDLC draft-spec deliverable to preserve the exact review lineage under the project's artifact-preservation instruction. Resolve relative links inside snapshots against the original spec directory, not the snapshot directory.

Final source identity, peer-delta findings, timestamp limits, rejected historical claims and verification are consolidated in [review-summary.md](../review-summary.md). In particular, the apparent cache-hook mismatch mentioned above was resolved by checking the global hook inherited through a local `t` entry; it is not an outstanding source/runtime contradiction.
