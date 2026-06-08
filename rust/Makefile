# Aggregator for the rust/ workspace.
#
# Each Rust subproject that supports this Emacs config lives in its own
# subdirectory with its own self-contained Makefile; this top-level file just
# forwards the standard targets to every one of them (recursive make).  It is
# the Make analogue of [cpp/CMakeLists.txt](../cpp/CMakeLists.txt)'s
# `add_subdirectory` aggregation.
#
#   make            # build everything (default goal)
#   make install    # install every subproject's artefact, no verify
#   make verify     # build + load-check each subproject
#   make clean      # drop each subproject's build/
#   make distclean  # also drop each checkout + deployed artefact
#   make GRAMMAR_TAG=v0.23.4   # command-line vars propagate to sub-makes
#                              # NB: this now hits ALL THREE grammar subprojects
#                              # (rust/c/lua), each of which has a different
#                              # correct tag — so a global override is rarely
#                              # what you want.  Override one grammar's pin with
#                              # `make -C treesit-grammar-c GRAMMAR_TAG=...`.
#
# To add a subproject: create rust/<name>/ with a Makefile that exposes the
# phony targets below (all / install / verify / clean / distclean), then add
# <name> to SUBPROJECTS.  The build is deliberately delegated, not centralised:
# a future cargo crate's "build" is just `cargo build --release`, nothing like
# the grammar's hand-rolled `cc` — so each subproject owns its own recipe and
# this file stays build-agnostic.  Workspace overview: [README.md](README.md).

SUBPROJECTS := treesit-grammar treesit-grammar-c treesit-grammar-lua question-queue-core

# Targets that fan out to every subproject, each forwarded verbatim via $@.
FORWARDED := all install verify clean distclean

.DEFAULT_GOAL := all
.PHONY: $(FORWARDED) help

$(FORWARDED):
	@for d in $(SUBPROJECTS); do \
	  echo ">> make $@ -C rust/$$d"; \
	  $(MAKE) -C "$$d" $@ || exit $$?; \
	done

help:
	@echo "rust/ workspace aggregator"
	@echo "  subprojects: $(SUBPROJECTS)"
	@echo "  targets:     all (default) | install | verify | clean | distclean"
	@echo "  per-subproject help: make -C <subproject> help"
