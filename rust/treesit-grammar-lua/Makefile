# Makefile — build & deploy the Lua tree-sitter grammar, pinned to an ABI-14
# tag, for this Emacs.  Sibling of [rust/treesit-grammar/Makefile](../treesit-grammar/Makefile)
# (the original Rust one); same mechanism, different grammar.
#
# WHY this exists (short version): Emacs 30.1 on Debian trixie is linked against
# libtree-sitter 0.22.6, which caps the grammar ABI at 14 (`M-:
# (treesit-library-abi-version)` => 14).  tree-sitter-grammars/tree-sitter-lua
# jumped to ABI 15 at v0.4.0, so a grammar built from a recent tag/HEAD loads as
# `(nil version-mismatch 15)` and `lua-ts-mode` can't start.  An earlier note
# (2026-05-19) wrongly concluded "no ABI-14 tag exists upstream" and fell back
# to the regex `lua-mode`; re-verified 2026-06-08, v0.3.0 IS the newest ABI-14
# tag (v0.4.0 is the first ABI-15 tag), so we pin + rebuild and promote Lua back
# to `lua-ts-mode`.  Full rationale + layout: see the companion README
# ([rust/treesit-grammar-lua/README.md](README.md)) and the workspace overview
# ([rust/README.md](../README.md)).  The matching `treesit-auto` pin lives in
# [lisp/languages/init-lua.el](../../lisp/languages/init-lua.el) — keep
# GRAMMAR_TAG below in sync with its `abi14-revision`.
#
# Like the Rust deployer this is standalone: it does NOT need a running Emacs
# daemon.  It mirrors `M-x treesit-install-language-grammar` (clone -> cc -fPIC
# -> link a shared object), then verifies in a throwaway `emacs -Q --batch` so a
# broken build fails loudly here, not at first `.lua` visit.
#
# Usage:
#   make            # fetch + build + install + verify  (default goal)
#   make install    # fetch + build + install, no verify
#   make verify     # install then load-check in `emacs -Q --batch`
#   make clean      # remove build/ (objects + .so)
#   make distclean  # also remove the grammar checkout and the deployed .so
#   make GRAMMAR_TAG=v0.2.0   # override the pin on the command line

# ---- config (single source of truth) ------------------------------------
LANG_NAME  := lua
REPO_URL   := https://github.com/tree-sitter-grammars/tree-sitter-lua
# v0.3.0 is the newest tag still at tree-sitter LANGUAGE_VERSION 14
# (v0.4.0 is the first ABI-15 tag).  MUST match `abi14-revision` in
# ../../lisp/languages/init-lua.el.
GRAMMAR_TAG := v0.3.0
# SRC_SUBDIR: where parser.c / scanner.c live inside the grammar repo.
SRC_SUBDIR  := src

CC  ?= cc
# -------------------------------------------------------------------------

# Directory of THIS Makefile, regardless of the caller's cwd.  This subproject
# sits at rust/treesit-grammar-lua/, so the Emacs config root is two levels up.
HERE        := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
EMACS_DIR   := $(abspath $(HERE)/../..)
# TREESIT_DIR: where Emacs looks (treesit-extra-load-path).
TREESIT_DIR := $(EMACS_DIR)/tree-sitter
# REPO_DIR: persistent source checkout (gitignored).
REPO_DIR    := $(HERE)/tree-sitter-$(LANG_NAME)
# BUILD_DIR: objects + .so (gitignored).
BUILD_DIR   := $(HERE)/build
SRC         := $(REPO_DIR)/$(SRC_SUBDIR)
SO_NAME     := libtree-sitter-$(LANG_NAME).so

# tree-sitter-lua ships parser.c AND scanner.c (external scanner for long
# strings / long comments) — both are compiled and linked below.  The recipe
# detects scanner.c at build time, so it also works for parser-only grammars
# (see the c sibling).
STAMP := $(BUILD_DIR)/.fetched-$(LANG_NAME)-$(GRAMMAR_TAG)

.DEFAULT_GOAL := all
.PHONY: all install verify clean distclean help

all: note

# ---- 1. fetch the pinned grammar source ---------------------------------
$(STAMP): | $(BUILD_DIR)
	@if [ -d "$(REPO_DIR)/.git" ]; then \
	  echo ">> updating $(notdir $(REPO_DIR)) -> $(GRAMMAR_TAG)"; \
	  git -C "$(REPO_DIR)" fetch --tags --depth 1 origin "$(GRAMMAR_TAG)"; \
	  git -C "$(REPO_DIR)" checkout -q "$(GRAMMAR_TAG)"; \
	else \
	  echo ">> cloning $(REPO_URL) @ $(GRAMMAR_TAG)"; \
	  git clone --depth 1 --branch "$(GRAMMAR_TAG)" "$(REPO_URL)" "$(REPO_DIR)"; \
	fi
	@test -f "$(SRC)/parser.c" || { echo "!! $(SRC)/parser.c not found (wrong SRC_SUBDIR or tag?)" >&2; exit 1; }
	@touch $@

# ---- 2+3a. compile parser.c (+ scanner.c if present) and link -----------
# Single recipe so the conditional scanner is decided AFTER the fetch, at shell
# time (a parse-time $(wildcard) would run before the clone exists).
$(BUILD_DIR)/$(SO_NAME): $(STAMP)
	@echo ">> compiling parser.c"
	$(CC) -fPIC -c -I"$(SRC)" "$(SRC)/parser.c" -o "$(BUILD_DIR)/parser.o"
	@if [ -f "$(SRC)/scanner.c" ]; then \
	  echo ">> compiling scanner.c"; \
	  $(CC) -fPIC -c -I"$(SRC)" "$(SRC)/scanner.c" -o "$(BUILD_DIR)/scanner.o"; \
	else \
	  echo ">> no scanner.c (parser-only grammar)"; \
	  rm -f "$(BUILD_DIR)/scanner.o"; \
	fi
	@echo ">> linking $(SO_NAME)"
	@OBJS="$(BUILD_DIR)/parser.o"; \
	 [ -f "$(BUILD_DIR)/scanner.o" ] && OBJS="$$OBJS $(BUILD_DIR)/scanner.o"; \
	 set -x; $(CC) -shared $$OBJS -o $@

# ---- 3b. deploy into Emacs' tree-sitter dir -----------------------------
install: $(TREESIT_DIR)/$(SO_NAME)

$(TREESIT_DIR)/$(SO_NAME): $(BUILD_DIR)/$(SO_NAME) | $(TREESIT_DIR)
	install -m 0755 $< $@
	@echo ">> installed -> $@"

# ---- 4. verify ABI in a clean Emacs (no daemon dlopen-cache to fool us) --
verify: install
	@if command -v emacs >/dev/null 2>&1; then \
	  echo ">> verifying in a fresh 'emacs -Q --batch' ..."; \
	  emacs -Q --batch --eval "(progn (add-to-list 'treesit-extra-load-path \"$(TREESIT_DIR)\") (let ((r (treesit-language-available-p '$(LANG_NAME) t))) (princ (format \"   $(LANG_NAME) grammar: %S\n\" r)) (unless (car r) (kill-emacs 1))))" \
	    || { echo "!! grammar built but Emacs rejected it (see status above)" >&2; exit 1; }; \
	  echo ">> OK: $(LANG_NAME) grammar loads (ABI <= 14)."; \
	else \
	  echo ">> emacs not on PATH; skipped load verification."; \
	fi

# ---- 5. remind about the running-daemon dlopen cache --------------------
note: verify
	@echo ""
	@echo "Done."
	@echo ""
	@echo "NOTE: a RUNNING Emacs daemon has the previous grammar dlopen'd and will NOT"
	@echo "pick up the new .so until restarted (same path, cached handle):"
	@echo ""
	@echo "    # confirm nothing unsaved first:"
	@echo "    emacsclient -e '(length (seq-filter (lambda (b) (and (buffer-file-name b) (buffer-modified-p b))) (buffer-list)))'"
	@echo "    systemctl --user restart emacs"
	@echo ""
	@echo "A fresh Emacs / the next daemon start uses the new grammar automatically."

# ---- dir helpers --------------------------------------------------------
$(BUILD_DIR) $(TREESIT_DIR):
	@mkdir -p $@

# ---- housekeeping -------------------------------------------------------
clean:
	rm -rf "$(BUILD_DIR)"

distclean: clean
	rm -rf "$(REPO_DIR)"
	rm -f "$(TREESIT_DIR)/$(SO_NAME)"

help:
	@echo "targets: all (default) | install | verify | clean | distclean"
	@echo "vars:    GRAMMAR_TAG=$(GRAMMAR_TAG)  CC=$(CC)"
