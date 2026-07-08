# Strengthen the C++ / Rust / Python / Org-mode Layers — Hunt → Verify → Implement

Target: /home/fenrir/.emacs.d (Emacs 30.1, TTY-first daemon + emacsclient -nw in tmux,
simultaneously serving a GUI frame). Scope is EXACTLY four areas — do not drift into
general config auditing (that hunt already exists as
[the 2026-07-03 prompt](202607030935-judge-emcas-config-and-optimize.md)):

  AREA-CPP    lisp/languages/init-c-cpp.el   (+ cpp/ native-module workspace)
  AREA-RUST   lisp/languages/init-rust.el    (+ rust/ workspace)
  AREA-PY     lisp/languages/init-python.el
  AREA-ORG    lisp/init-org.el + lisp/init-org-roam.el

CLAUDE.md in the repo is the constraint bible; FEATURES.md is the key-binding
ledger. Every finder and skeptic MUST read both first. If any of the four module
files above is missing or unreadable, STOP and report it — do not substitute guesses.

## Phase 0 — BASELINE (abort-on-red; don't build on a broken base)

1. `emacs --batch --eval '(setq debug-on-error t)' -l init.el` → must exit 0.
   Record output as the warning baseline.
2. Record `time emacs --batch -l init.el` (3× median).
3. Snapshot the C-c prefix map currently claimed per FEATURES.md (collisions are a
   known hazard: C-c t = vterm/tests, C-c o = combobulate, C-c r = eglot-rename
   inside eglot-mode-map while C-c r f/i/b/c/d/g are GLOBAL org-roam keys,
   C-c R = rust eglot-x cockpit, C-c % = c/c++ brace-hop, C-c q = question-queue).
If step 1 fails, ABORT the whole run and report — the target is already broken.

## Phase 1 — DISCOVER (map fan-out, one finder per named lens + loop-until-dry)

Fan out finders in parallel. Each lens is a STRATEGY, not a paraphrase of the
others; each finder states what it deliberately ignores. Angle hints below are
starting points, not conclusions — a finder may discover the hint is already
handled or wrong; verifying the hint against the actual file is part of the job.

  F1 cpp-workflow    : what does daily C/C++ work still lack vs Go/Java here?
                       No debugger wired (dape has no gdb/codelldb config; only
                       Go's dlv is on PATH per CLAUDE.md); no test/run story
                       (junit-core is Java-only — is there a C-c t analogue worth
                       having for cpp/'s CMake tree, e.g. compile wired to
                       cpp/build.sh?); apheleia↔clang-format coverage for
                       c-ts-mode/c++-ts-mode; cmake-ts-mode for cpp/*/CMakeLists.txt;
                       clangd flags vs ~/.config/clangd/config.yaml split;
                       the UNPINNED cpp grammar (init-c-cpp.el's own NB: a future
                       ABI-15 pull breaks c++-ts-mode — is a proactive pin due?).
  F2 rust-workflow   : Rust is the richest module (eglot-x cockpit) — find the
                       REMAINING gaps only: Cargo.toml editing (toml-ts-mode?
                       crate-version overlay à la `crates` packages — check what
                       actually exists on MELPA); dape+codelldb absent; cargo
                       test-at-point vs eglot-x-ask-runnables overlap (don't
                       duplicate — decide which owns C-c t if any); rustfmt: does
                       apheleia's default alist actually map rust-ts-mode?
  F3 python-workflow : thinnest language module (19 lines). Interpreter/venv
                       story beyond envrc (buffer-local pyright per venv?);
                       formatter — apheleia default for python-ts-mode (black?
                       ruff?) vs what's installed; dape+debugpy absent; no
                       pytest-at-point runner (Go/Java precedent: C-c t prefix
                       shadowing vterm in-mode only); pyright basic vs
                       basedpyright; REPL ergonomics (python-shell send keys).
  F4 org-workflow    : init-org.el says "minimal; expand later" — what's the
                       highest-value expansion NOW? org-agenda unwired (no
                       org-agenda-files, no C-c a); no general org-capture
                       (C-c c) — only roam capture exists; org-babel languages
                       beyond plantuml/mermaid (python/shell/elisp blocks +
                       confirm-babel-evaluate policy); image paste/attach flow
                       (org-download vs org-attach; TTY frame can't render —
                       any addition must degrade to a link, per the
                       org-startup-with-inline-images GUI-only note); CJK table
                       alignment (valign is GUI-leaning — verify TTY behaviour);
                       org-roam friction points in the existing C-c r flow.
  F5 cross-area-parity: build the parity matrix across the four areas + Go/Java
                       as reference rows: eglot server config entry / formatter /
                       debugger / test-at-point / structural editing / docs
                       lookup / grammar-ABI pin. Report CELLS where an area lacks
                       something a sibling has AND the lack is felt in daily use.
                       Ignore anything all areas lack equally.

Rules per finder:
  - Findings as: {id, area, file:line, lens, claim, expected-benefit, risk,
    evidence, new-packages-needed (name + archive: MELPA/ELPA/:vc — verify it
    exists and is maintained; "I think there's a package" is not evidence)}.
  - Maintain a shared SEEN set keyed by area:claim — report only NEW findings.
  - An empty area is a VALID result: if a finder concludes its area is already
    well-served, say so with reasons instead of inventing filler findings.
  - LOOP: after all finders return, one more round with fresh angle hints;
    STOP when 2 consecutive rounds add nothing new (loop-until-dry), hard cap 3
    rounds (scoped hunt — smaller cap than the general audit's 4).

## Phase 2 — ADVERSARIAL-VERIFY each finding (3 skeptics, default REFUTE)

  S1 claude-md-trap : read .emacs.d/CLAUDE.md end-to-end. Does the "improvement"
                      revert a documented deliberate decision? Area-specific
                      tripwires: apheleia owns format-on-save (never eglot-format
                      on save-hook); C-c o belongs to combobulate; never
                      globalize ggtags or semantic-tokens; new tree-sitter
                      grammars must respect the ABI-14 cap (pin or exclude);
                      new packages need the my/package-refresh + restart dance
                      (no archive refresh at startup) — a finding that assumes
                      install-at-startup works is broken; built-ins take
                      :ensure nil. If violated → REFUTE, cite the CLAUDE.md line.
  S2 tty-daemon     : must survive the TTY frame AND the coexisting GUI frame on
                      one daemon. Child-frame/fringe/stipple/image-only features
                      with no TTY fallback → REFUTE (or force the finding to add
                      an explicit Tier-A/B/C gate per init-gui.el's tiers).
  S3 value-evidence : is the benefit real for THIS user's daily flow (which
                      repos/langs do they actually open — check ~/code contents
                      cited in CLAUDE.md), and is the claimed package/tool real,
                      current, and compatible with Emacs 30.1 + Eglot 1.23?
                      "Nice in theory" with no concrete daily scenario → REFUTE.
Drop the finding if ≥2 skeptics refute. If a skeptic cannot decide, its vote is
REFUTE (uncertainty maps to refute — false positives are the fear here).
Survivors keep skeptic notes attached.

## Phase 3 — RANK (rubric judge; "is this a good config" has no oracle)

Score each survivor 0–5 on: impact (5 = felt every session in that language/mode;
1 = cosmetic), risk-inverse (5 = pure addition, no existing binding/behaviour
touched; 0 = touches load order or a shared map), effort-inverse, and
TTY-safety (5 = identical on TTY; 0 = GUI-only with no gate). Judge writes its
reasoning BEFORE each score. Take top-ranked with risk-inverse ≥ 2, capped at
**2 changes per area, 6 total** (fail-closed: ambiguity → take fewer). Report
the cut list explicitly — silent truncation reads as "nothing else was worth it".

## Phase 4 — IMPLEMENT (plan-then-execute + until-oracle-passes, per change)

For EACH selected change independently (one change = one commit-sized unit):
  1. PLAN: files to touch + acceptance criteria BEFORE editing.
  2. EDIT, then oracle chain — paste REAL output each round:
       O1 load-health : emacs --batch --eval '(setq debug-on-error t)' -l init.el
                        → exit 0, no NEW warnings vs Phase-0 baseline.
       O2 byte-compile: byte-compile touched lisp/**/*.el → no NEW warnings.
       O3 live-daemon : eval the new binding/feature via emacsclient on the live
                        TTY frame; confirm observable behaviour; re-scan the
                        Phase-0 C-c snapshot for introduced collisions.
       O4 startup-cost: if the change adds a package or eager code, re-run the
                        Phase-0 timing; >5% regression → make it lazier or revert.
  3. Fix only the first real failure; repeat until green. Max 3 fix attempts per
     change → REVERT that change fully and log why (never leave half-applied).
  4. New-package discipline: declare with correct :ensure/:vc form, note the
     my/package-refresh first-run requirement in a comment (house style — every
     module does this), and record :vc pins in custom.el as the existing ones do.

## Phase 5 — FINAL GATE (devil's-advocate + doc sync)

Red-team the accumulated diff: "give 2 concrete scenarios where this breaks the
daemon, the TTY frame, or a documented CLAUDE.md invariant" — address or dismiss
each with evidence, not reassurance. Then:
  - Update FEATURES.md for every new/changed key binding (mandatory ledger).
  - Update CLAUDE.md ONLY if a change introduces a new load-bearing quirk.
  - Report: per-area verdict (improved / already-well-served / found-but-cut),
    per-change before/after oracle output, reverted items with reasons.

Never claim done without pasted green oracle output (models report imagined
passes). Do not git push. Commit only when the whole batch is green.

---

## Why this composition (primitive ← diagnosis)

- map fan-out, 5 named lenses (4 areas + parity) ← wide solution space scoped to
  four areas; diversity > scale; F5 catches cross-area gaps no single-area finder sees
- loop-until-dry (2 dry, cap 3)                  ← fear "missed something"; fixed
  `find N` misses the tail; smaller cap than the general audit because scope is narrow
- adversarial-verify (3 lenses, ≥2 kill,
  uncertainty→refute)                            ← fear "plausible-but-wrong": this
  config's documented traps (S1), the dual TTY/GUI daemon (S2), and package-exists
  hallucination (S3) are three DIFFERENT failure modes → three different skeptic lenses
- rubric judge, reason-before-score, anchored    ← "better config" has no oracle;
  anchored rubric + consequences (cut at risk-inverse < 2) beats raw self-opinion
- plan-then-execute + until-oracle-passes        ← implementation HAS oracles (batch
  load / byte-compile / live-daemon eval / timing); every refine loop is
  oracle-grounded, no naive self-refine
- devil's-advocate final gate                    ← catches "all green but wrong design"
- fail-closed bounds                             ← abort on red baseline; ≤2/area,
  ≤6 total; ≤3 fix attempts then full revert; explicit cut-list (no silent truncation)
- escape hatch                                   ← "already well-served" is a valid
  per-area verdict; filler findings are worse than an honest empty result
