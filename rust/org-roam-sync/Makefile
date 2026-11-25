# Makefile — build & deploy the org-roam-sync indexer binary.
#
# Output: ../lib/org-roam-sync
#
# cargo runs with this directory as cwd so .cargo/config.toml (mold) applies;
# `cargo --manifest-path' from elsewhere would not read it.

HERE       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR    := $(abspath $(HERE)/../lib)
CRATE_BIN  := $(HERE)/target/release/org-roam-sync
DEPLOY_BIN := $(LIB_DIR)/org-roam-sync
CARGO      ?= cargo

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help

all install: $(DEPLOY_BIN)

$(DEPLOY_BIN): $(wildcard $(HERE)/src/*.rs) $(HERE)/Cargo.toml $(HERE)/Cargo.lock $(HERE)/.cargo/config.toml | $(LIB_DIR)
	@echo ">> cargo build --release (org-roam-sync)"
	cd "$(HERE)" && $(CARGO) build --release --locked --offline
	@test -f "$(CRATE_BIN)" || { echo "!! $(CRATE_BIN) not produced" >&2; exit 1; }
	install -m 0755 "$(CRATE_BIN)" "$(DEPLOY_BIN)"
	@echo ">> installed -> $(DEPLOY_BIN)"

$(LIB_DIR):
	@mkdir -p $@

# ---- verify: index a throwaway /tmp note and query it via org-roam in Emacs
verify: install
	@if command -v emacs >/dev/null 2>&1; then \
	  echo ">> verifying in a fresh 'emacs -Q --batch' ..."; \
	  tmp="$$(mktemp -d /tmp/org-roam-sync-verify-XXXXXX)"; \
	  trap 'rm -rf "$$tmp"' EXIT; \
	  printf ':PROPERTIES:\n:ID: 00000000-0000-0000-0000-000000000001\n:END:\n#+title: Verify Note\n#+filetags: :verify:\n' > "$$tmp/note.org"; \
	  "$(DEPLOY_BIN)" --dir "$$tmp" --db "$$tmp/org-roam.db" --org-id-out "$$tmp/id-locations.el" || exit 1; \
	  emacs -Q --batch --eval "\
	    (progn \
	      (setq package-user-dir (expand-file-name \"elpa\" \"$(abspath $(HERE)/../..)/\") \
	            use-package-always-ensure nil) \
	      (package-initialize) \
	      (require 'org-roam) \
	      (setq org-roam-directory (file-truename \"$$tmp\") \
	            org-roam-db-location \"$$tmp/org-roam.db\") \
	      (let ((nodes (org-roam-node-list))) \
	        (unless (and (= (length nodes) 1) \
	                     (equal (org-roam-node-id (car nodes)) \"00000000-0000-0000-0000-000000000001\") \
	                     (equal (org-roam-node-title (car nodes)) \"Verify Note\") \
	                     (equal (org-roam-node-tags (car nodes)) '(\"verify\"))) \
	          (error \"unexpected nodes: %S\" nodes)) \
	        (org-roam-db--close-all) \
	        (princ \"ok\n\")))" \
	    || { echo "!! org-roam-sync built but Emacs verification failed" >&2; exit 1; }; \
	  echo ">> OK: org-roam-sync runs and org-roam-node-list reads its DB."; \
	else \
	  echo ">> emacs not on PATH; skipped Emacs verification."; \
	fi

clean:
	cd "$(HERE)" && $(CARGO) clean --release 2>/dev/null || true
	rm -f "$(DEPLOY_BIN)"

distclean:
	cd "$(HERE)" && $(CARGO) clean 2>/dev/null || true
	rm -rf "$(HERE)/target"
	rm -f "$(DEPLOY_BIN)"

help:
	@echo "org-roam-sync helper binary"
	@echo "  targets: all (default) | install | verify | clean | distclean"
	@echo "  output:  $(DEPLOY_BIN)"
