# Makefile — build & deploy the libsrc-classes helper binary.
#
# A cargo bin run by lisp/languages/fenrir-libsrc.el (`fenrir/libsrc-classes-program')
# to list jar classes.  The aggregator [../Makefile](../Makefile) just forwards
# the standard phony targets here.
#
# Output: ../lib/libsrc-classes
#
# cargo runs with this directory as cwd so .cargo/config.toml (mold) applies;
# `cargo --manifest-path' from elsewhere would not read it.
#
# Usage:
#   make            # cargo build --release + deploy to ../lib/ (default goal)
#   make install    # same as all (the binary in ../lib/ IS the deployment)
#   make verify     # build + run it with no jars and `read' its form in Emacs
#   make clean      # cargo clean --release + remove the deployed binary
#   make distclean  # also remove target/

# ---- config -------------------------------------------------------------
HERE       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR    := $(abspath $(HERE)/../lib)
CRATE_BIN  := $(HERE)/target/release/libsrc-classes
DEPLOY_BIN := $(LIB_DIR)/libsrc-classes
CARGO      ?= cargo
# -------------------------------------------------------------------------

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help

all install: $(DEPLOY_BIN)

# Rebuild whenever any tracked source changes; cargo decides if work is needed.
$(DEPLOY_BIN): $(wildcard $(HERE)/src/*.rs) $(HERE)/Cargo.toml $(HERE)/Cargo.lock $(HERE)/.cargo/config.toml | $(LIB_DIR)
	@echo ">> cargo build --release (libsrc-classes)"
	cd "$(HERE)" && $(CARGO) build --release --locked
	@test -f "$(CRATE_BIN)" || { echo "!! $(CRATE_BIN) not produced" >&2; exit 1; }
	install -m 0755 "$(CRATE_BIN)" "$(DEPLOY_BIN)"
	@echo ">> installed -> $(DEPLOY_BIN)"

$(LIB_DIR):
	@mkdir -p $@

# ---- verify: the form it prints for no jars must `read' as the engine expects
verify: install
	@if command -v emacs >/dev/null 2>&1; then \
	  echo ">> verifying in a fresh 'emacs -Q --batch' ..."; \
	  emacs -Q --batch -L "$(HERE)/../../lisp/languages" --eval "(progn (require 'fenrir-libsrc) (let ((p (fenrir/libsrc--parse-classes-output (shell-command-to-string \"$(DEPLOY_BIN)\")))) (unless (and p (hash-table-p (car p)) (null (cdr p))) (error \"unexpected output\")) (princ \"ok\n\")))" \
	    || { echo "!! libsrc-classes built but its output did not parse (see above)" >&2; exit 1; }; \
	  echo ">> OK: libsrc-classes runs and its output parses."; \
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
	@echo "libsrc-classes helper binary"
	@echo "  targets: all (default) | install | verify | clean | distclean"
	@echo "  output:  $(DEPLOY_BIN)"
