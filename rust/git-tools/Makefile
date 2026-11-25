# Makefile — build & deploy the git helper binaries (one cargo workspace).
#
# Each member crate is a bin run by a lisp/ module: git-subtree-status by
# lisp/fenrir-magit-subtree.el, git-nested-status by lisp/fenrir-magit-nested.el.
# They are also plain CLIs: symlinked into
# ~/.local/bin they run as `git subtree-status' and so on.  The aggregator
# [../Makefile](../Makefile) just forwards the standard phony targets here.
#
# Output: ../lib/<bin> for every bin in BINS
#
# cargo runs with this directory as cwd so .cargo/config.toml (mold) applies;
# `cargo --manifest-path' from elsewhere would not read it.
#
# Usage:
#   make            # cargo build --release (whole workspace) + deploy to ../lib/
#   make install    # same as all (the binaries in ../lib/ ARE the deployment)
#   make verify     # build + check each bin's porcelain header
#   make clean      # cargo clean --release + remove the deployed binaries
#   make distclean  # also remove target/

# ---- config -------------------------------------------------------------
HERE       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR    := $(abspath $(HERE)/../lib)
BINS       := git-subtree-status git-nested-status git-diff-hl
DEPLOYED   := $(addprefix $(LIB_DIR)/,$(BINS))
SOURCES    := $(wildcard $(HERE)/*/src/*.rs) $(wildcard $(HERE)/*/Cargo.toml) \
              $(HERE)/Cargo.toml $(HERE)/Cargo.lock $(HERE)/.cargo/config.toml
CARGO      ?= cargo
# -------------------------------------------------------------------------

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help build

all install: $(DEPLOYED)

# One cargo invocation builds every member; cargo decides if work is needed.
# The stamp file lets each deployed binary depend on that single build.
$(HERE)/target/release/.built: $(SOURCES)
	@echo ">> cargo build --release (git-tools workspace: $(BINS))"
	cd "$(HERE)" && $(CARGO) build --release --locked
	@touch $@

$(LIB_DIR)/%: $(HERE)/target/release/.built | $(LIB_DIR)
	@test -f "$(HERE)/target/release/$*" || { echo "!! $(HERE)/target/release/$* not produced" >&2; exit 1; }
	install -m 0755 "$(HERE)/target/release/$*" "$@"
	@echo ">> installed -> $@"

$(LIB_DIR):
	@mkdir -p $@

# ---- verify: run each bin on this config repo and check its porcelain header.
# The header line is `# <bin> v1'; the Emacs front ends read that format, so a
# matching header proves the binary runs and speaks the version they parse.
verify: install
	@for b in $(BINS); do \
	  out="$$("$(LIB_DIR)/$$b" -C "$(HERE)/../.." --porcelain --all)" || { echo "!! $$b failed" >&2; exit 1; }; \
	  test "$$(printf '%s\n' "$$out" | head -1)" = "# $$b v1" \
	    || { echo "!! $$b: unexpected porcelain header: $$out" >&2; exit 1; }; \
	  echo ">> OK: $$b runs and prints porcelain v1."; \
	done

# ---- housekeeping -------------------------------------------------------
clean:
	cd "$(HERE)" && $(CARGO) clean --release 2>/dev/null || true
	rm -f $(DEPLOYED)

distclean:
	cd "$(HERE)" && $(CARGO) clean 2>/dev/null || true
	rm -rf "$(HERE)/target"
	rm -f $(DEPLOYED)

help:
	@echo "git-tools: git helper binaries (cargo workspace)"
	@echo "  bins:    $(BINS)"
	@echo "  targets: all (default) | install | verify | clean | distclean"
	@echo "  output:  $(DEPLOYED)"
