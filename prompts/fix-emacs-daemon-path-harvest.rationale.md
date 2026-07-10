# Rationale — fix-emacs-daemon-path-harvest

Companion to [the composed prompt](fix-emacs-daemon-path-harvest.md).
Composed 2026-07-10 via the agentic-prompt-composer skill.

## Task diagnosis

| Question | Answer |
|---|---|
| Oracle? | Yes, three layers — repro command exit code (A), guard semantics + one manual check (B), `emacsclient --eval` end-to-end (C) |
| Solution space | Narrow — single verified root cause |
| Failure fear | Plausible-but-wrong fix (two tempting wrong fixes were tested and rejected during recon) |
| Size / cost | One-off, fits one context |
| Irreversible edge | Restarting the live Emacs daemon (serves concurrent TTY + GUI frames) |

## Verified findings behind the prompt

All facts were tested live on 2026-07-10, not inferred:

- `env -u TMUX -u INSIDE_EMACS TERM=dumb bash -l -i -c 'echo PATH_OK' </dev/null`
  reproduced the exact failure: exit 1, `open terminal failed: not a terminal`
  (a **tmux** error — `.bashrc`'s auto-attach block `exec`s tmux from the
  tty-less shell that exec-path-from-shell spawns).
- `/home/fenrir/.cargo/bin/emacs-lsp-booster` exists (built 2026-05-18) — the
  second startup error is purely downstream of the failed PATH harvest.
- `bash -l -c 'echo $PATH'` (non-interactive login, the "drop `-i`" fix)
  loses `go/bin`, sdkman, pnpm, `.npm-global` — those exports live after
  `.bashrc`'s interactive guard, so that fix would silently regress LSP
  server discovery.

## Primitives selected and why

- **until-oracle-passes** (main line): objective oracles exist at every
  stage, so the loop is "apply fix → oracle green", capped at 3 rounds on
  Oracle A. No exploration loop needed — the red state was already
  reproduced during composition.
- **sandbox-verify-commit**: verify in a throwaway shell (Oracle A) before
  the only user-visible step; the daemon restart sits behind an explicit
  **confirm gate** because live frames make it effectively irreversible
  mid-session.
- **fail-closed**: mismatched inlined facts → STOP; missing oracle → line
  marked UNVERIFIED instead of claimed green.
- **reasoned prohibitions**: the two recon-rejected fixes (reinstall
  booster, drop `-i`) are written as prohibitions *with their tested
  reasons*, so a runner can't rationalize its way back into them.
- **No fan-out / debate / self-consistency**: solution space is a single
  proven root cause; multi-candidate machinery would be pure waste.

## Guardrail check (composition-guide anti-patterns)

1. Oracle > self-eval — every green claim requires pasted real output. ✔
2. No naive self-refine — the only loop is oracle-driven, 3-round cap. ✔
3. Workflow > agent — the path is fully predefined (7 numbered steps). ✔
4. Diversity > scale — n/a, no fan-out by design. ✔
5. No debate for its own sake — none used. ✔
