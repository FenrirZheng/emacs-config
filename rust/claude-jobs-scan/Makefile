# Makefile — build & deploy the claude-jobs-scan helper binary.
#
# A cargo bin run by lisp/claude-jobs-view.el (`claude-jobs-view-scan-program')
# to scan jobctl sessions, /proc cmdlines, daemon state.json, and JSONL heads.
#
# Output: ../lib/claude-jobs-scan
#
# cargo runs with this directory as cwd so .cargo/config.toml (mold) applies;
# `cargo --manifest-path' from elsewhere would not read it.
#
# Usage:
#   make            # cargo build --release + deploy to ../lib/ (default goal)
#   make install    # same as all (the binary in ../lib/ IS the deployment)
#   make verify     # build + run against fixtures and `read' output in Emacs
#   make clean      # cargo clean --release + remove the deployed binary
#   make distclean  # also remove target/

# ---- config -------------------------------------------------------------
HERE       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR    := $(abspath $(HERE)/../lib)
CRATE_BIN  := $(HERE)/target/release/claude-jobs-scan
DEPLOY_BIN := $(LIB_DIR)/claude-jobs-scan
CARGO      ?= cargo
# -------------------------------------------------------------------------

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help

all install: $(DEPLOY_BIN)

# Rebuild whenever any tracked source changes; cargo decides if work is needed.
$(DEPLOY_BIN): $(wildcard $(HERE)/src/*.rs) $(HERE)/Cargo.toml $(HERE)/Cargo.lock $(HERE)/.cargo/config.toml | $(LIB_DIR)
	@echo ">> cargo build --release (claude-jobs-scan)"
	cd "$(HERE)" && $(CARGO) build --release --locked
	@test -f "$(CRATE_BIN)" || { echo "!! $(CRATE_BIN) not produced" >&2; exit 1; }
	install -m 0755 "$(CRATE_BIN)" "$(DEPLOY_BIN)"
	@echo ">> installed -> $(DEPLOY_BIN)"

$(LIB_DIR):
	@mkdir -p $@

# ---- verify: full scan + --uuid output must `read' cleanly in Emacs -----
verify: install
	@if command -v emacs >/dev/null 2>&1; then \
	  echo ">> verifying in a fresh 'emacs -Q --batch' ..."; \
	  tmp="$$(mktemp -d)" && trap 'rm -rf "$$tmp"' EXIT && \
	  mkdir -p "$$tmp/state" "$$tmp/jobs/aa11bb22" "$$tmp/jobs/empty_dir" "$$tmp/projects/-tmp-my--proj" && \
	  printf '%s\n' '{"pins":[]}' > "$$tmp/jobs/pins.json" && \
	  printf '%s\n' '{"daemonShort":"aa11bb22","state":"done","updatedAt":"2026-11-25T00:00:00Z","intent":"一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十Extra","name":"fallback","cwd":"/tmp/my.proj"}' > "$$tmp/jobs/aa11bb22/state.json" && \
	  printf 'sid=%s\npid=%d\ncwd=%s\nagent=%s\nstarted=%s\n' \
	    "11111111-2222-3333-4444-555555555555" 99999999 '/tmp/my.proj' 'test\ agent' '2026-11-25T00:00:00+08:00' \
	    > "$$tmp/state/11111111-2222-3333-4444-555555555555.meta" && \
	  printf '%s\n' '{"type":"user","cwd":"/tmp/my.proj","message":{"content":[{"type":"text","text":"hello from fixture"}]}}' \
	    > "$$tmp/projects/-tmp-my--proj/11111111-2222-3333-4444-555555555555.jsonl" && \
	  emacs -Q --batch --eval "\
(let* ((bin \"$(DEPLOY_BIN)\") \
       (empty-raw (shell-command-to-string (format \"%s --state-dir /nonexistent --jobs-dir /nonexistent --projects-dir /nonexistent\" (shell-quote-argument bin)))) \
       (empty-form (car (read-from-string empty-raw))) \
       (fix-raw (shell-command-to-string (format \"%s --state-dir %s --jobs-dir %s --projects-dir %s\" (shell-quote-argument bin) (shell-quote-argument \"$$tmp/state\") (shell-quote-argument \"$$tmp/jobs\") (shell-quote-argument \"$$tmp/projects\")))) \
       (fix-form (car (read-from-string fix-raw))) \
       (uuid-raw (shell-command-to-string (format \"%s --state-dir %s --jobs-dir %s --projects-dir %s --uuid 11111111-2222-3333-4444-555555555555\" (shell-quote-argument bin) (shell-quote-argument \"$$tmp/state\") (shell-quote-argument \"$$tmp/jobs\") (shell-quote-argument \"$$tmp/projects\")))) \
       (uuid-form (car (read-from-string uuid-raw))) \
       (miss-raw (shell-command-to-string (format \"%s --state-dir %s --jobs-dir %s --projects-dir %s --uuid 00000000-0000-0000-0000-000000000000\" (shell-quote-argument bin) (shell-quote-argument \"$$tmp/state\") (shell-quote-argument \"$$tmp/jobs\") (shell-quote-argument \"$$tmp/projects\")))) \
       (miss-form (car (read-from-string miss-raw)))) \
  (unless (equal empty-form '(:sessions nil :daemons nil)) \
    (error \"unexpected empty output: %S\" empty-form)) \
  (let ((s (car (plist-get fix-form :sessions))) \
        (d (car (plist-get fix-form :daemons)))) \
    (unless (and (= (length (plist-get fix-form :sessions)) 1) \
                 (= (length (plist-get fix-form :daemons)) 1) \
                 (equal (plist-get s :agent) \"test agent\") \
                 (equal (plist-get s :first-user-text) \"hello from fixture\") \
                 (= (length (plist-get d :intent)) 60) \
                 (string-suffix-p \"Extra\" (plist-get d :raw-intent)) \
                 (equal (plist-get uuid-form :sid) \"11111111-2222-3333-4444-555555555555\") \
                 (null miss-form)) \
      (error \"unexpected fixture output: %S\" fix-form))) \
  (princ \"ok\\n\"))" \
	    || { echo "!! claude-jobs-scan built but its output did not verify (see above)" >&2; exit 1; }; \
	  echo ">> OK: claude-jobs-scan runs and its output verifies."; \
	else \
	  echo ">> emacs not on PATH; skipped output verification."; \
	fi

# ---- housekeeping -------------------------------------------------------
clean:
	cd "$(HERE)" && $(CARGO) clean --release 2>/dev/null || true
	rm -f "$(DEPLOY_BIN)"

distclean:
	cd "$(HERE)" && $(CARGO) clean 2>/dev/null || true
	rm -rf "$(HERE)/target"
	rm -f "$(DEPLOY_BIN)"

help:
	@echo "claude-jobs-scan helper binary"
	@echo "  targets: all (default) | install | verify | clean | distclean"
	@echo "  output:  $(DEPLOY_BIN)"
