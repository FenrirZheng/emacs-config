# Makefile — build & deploy the question-queue-core Emacs dynamic module.
#
# A cargo cdylib whose .so is loaded by lisp/question-queue.el via `module-load'.
# Unlike the treesit-grammar sibling (hand-rolled `cc'), this one delegates the
# build to cargo; the aggregator [../Makefile](../Makefile) stays build-agnostic
# and just forwards the standard phony targets here.
#
# Output: ../lib/question-queue-core.so  (Emacs wants the FEATURE name with no
# `lib' prefix, so we copy target/release/libquestion_queue_core.so onto it).
#
# Usage:
#   make            # cargo build --release + deploy to ../lib/ (default goal)
#   make install    # same as all (the .so in ../lib/ IS the deployment)
#   make verify     # build + load-check in a fresh `emacs -Q --batch'
#   make clean      # cargo clean + remove the deployed .so
#   make distclean  # also remove target/

# ---- config -------------------------------------------------------------
HERE       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR    := $(abspath $(HERE)/../lib)
CRATE_SO   := $(HERE)/target/release/libquestion_queue_core.so
DEPLOY_SO  := $(LIB_DIR)/question-queue-core.so
CARGO      ?= cargo
# -------------------------------------------------------------------------

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help

all install: $(DEPLOY_SO)

# Rebuild whenever any tracked source changes; cargo decides if work is needed.
$(DEPLOY_SO): $(wildcard $(HERE)/src/*.rs) $(HERE)/build.rs $(HERE)/wrapper.h $(HERE)/Cargo.toml | $(LIB_DIR)
	@echo ">> cargo build --release (question-queue-core)"
	$(CARGO) build --release --manifest-path "$(HERE)/Cargo.toml"
	@test -f "$(CRATE_SO)" || { echo "!! $(CRATE_SO) not produced" >&2; exit 1; }
	install -m 0755 "$(CRATE_SO)" "$(DEPLOY_SO)"
	@echo ">> installed -> $(DEPLOY_SO)"

$(LIB_DIR):
	@mkdir -p $@

# ---- verify: dlopen in a throwaway Emacs, call the version probe ---------
verify: install
	@if command -v emacs >/dev/null 2>&1; then \
	  echo ">> verifying in a fresh 'emacs -Q --batch' ..."; \
	  emacs -Q --batch --eval "(progn (module-load \"$(DEPLOY_SO)\") (unless (fboundp 'qq-core-submit) (error \"qq-core-submit missing\")) (princ (qq-core-version)) (terpri))" \
	    || { echo "!! module built but Emacs rejected it (see above)" >&2; exit 1; }; \
	  echo ">> OK: question-queue-core loads and registers its functions."; \
	else \
	  echo ">> emacs not on PATH; skipped load verification."; \
	fi

# ---- housekeeping -------------------------------------------------------
clean:
	$(CARGO) clean --release --manifest-path "$(HERE)/Cargo.toml" 2>/dev/null || true
	rm -f "$(DEPLOY_SO)"

distclean:
	$(CARGO) clean --manifest-path "$(HERE)/Cargo.toml" 2>/dev/null || true
	rm -rf "$(HERE)/target"
	rm -f "$(DEPLOY_SO)"

help:
	@echo "question-queue-core dynamic module"
	@echo "  targets: all (default) | install | verify | clean | distclean"
	@echo "  output:  $(DEPLOY_SO)"
