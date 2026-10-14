# Makefile — build & deploy the git-subtree-status helper binary.
#
# A cargo bin (gix) run by lisp/fenrir-magit-subtree.el (`fenrir/magit-subtree-program')
# for the Magit Subtrees section and `l S'.  It is also a plain CLI: symlinked
# into ~/.local/bin it runs as `git subtree-status'.  The aggregator
# [../Makefile](../Makefile) just forwards the standard phony targets here.
#
# Output: ../lib/git-subtree-status
#
# cargo runs with this directory as cwd so .cargo/config.toml (mold) applies;
# `cargo --manifest-path' from elsewhere would not read it.
#
# Usage:
#   make            # cargo build --release + deploy to ../lib/ (default goal)
#   make install    # same as all (the binary in ../lib/ IS the deployment)
#   make verify     # build + check its porcelain output parses in Emacs
#   make clean      # cargo clean --release + remove the deployed binary
#   make distclean  # also remove target/

# ---- config -------------------------------------------------------------
HERE       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR    := $(abspath $(HERE)/../lib)
CRATE_BIN  := $(HERE)/target/release/git-subtree-status
DEPLOY_BIN := $(LIB_DIR)/git-subtree-status
CARGO      ?= cargo
# -------------------------------------------------------------------------

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help

all install: $(DEPLOY_BIN)

# Rebuild whenever any tracked source changes; cargo decides if work is needed.
$(DEPLOY_BIN): $(wildcard $(HERE)/src/*.rs) $(HERE)/Cargo.toml $(HERE)/Cargo.lock $(HERE)/.cargo/config.toml | $(LIB_DIR)
	@echo ">> cargo build --release (git-subtree-status)"
	cd "$(HERE)" && $(CARGO) build --release --locked
	@test -f "$(CRATE_BIN)" || { echo "!! $(CRATE_BIN) not produced" >&2; exit 1; }
	install -m 0755 "$(CRATE_BIN)" "$(DEPLOY_BIN)"
	@echo ">> installed -> $(DEPLOY_BIN)"

$(LIB_DIR):
	@mkdir -p $@

# ---- verify: run it on this config repo and parse the porcelain in Emacs.
# The config repo has no subtree, so the expected result is the v1 header and
# no rows -- which still proves the binary runs and the format is the one the
# front end reads.
verify: install
	@out="$$("$(DEPLOY_BIN)" -C "$(HERE)" --porcelain --all)" || { echo "!! git-subtree-status failed" >&2; exit 1; }; \
	test "$$(printf '%s\n' "$$out" | head -1)" = "# git-subtree-status v1" \
	  || { echo "!! unexpected porcelain header: $$out" >&2; exit 1; }; \
	echo ">> OK: git-subtree-status runs and prints porcelain v1."

# ---- housekeeping -------------------------------------------------------
clean:
	cd "$(HERE)" && $(CARGO) clean --release 2>/dev/null || true
	rm -f "$(DEPLOY_BIN)"

distclean:
	cd "$(HERE)" && $(CARGO) clean 2>/dev/null || true
	rm -rf "$(HERE)/target"
	rm -f "$(DEPLOY_BIN)"

help:
	@echo "git-subtree-status helper binary"
	@echo "  targets: all (default) | install | verify | clean | distclean"
	@echo "  output:  $(DEPLOY_BIN)"
