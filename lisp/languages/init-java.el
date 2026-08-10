;;; init-java.el --- Java: tree-sitter + gtags, no LSP -*- lexical-binding: t; -*-

;;; Commentary:
;; Java language support.  **There is no language server.**  Java is the one
;; language in this config deliberately left without LSP; everything else with
;; a `lisp/languages/init-X.el' module attaches Eglot on its mode hook.
;;
;; What Java gets instead:
;;
;;   * `java-ts-mode' (tree-sitter) for fontification, imenu, structural
;;     navigation and `treesit'-driven indentation -- all in-process, all
;;     zero-latency, all purely local to the buffer.
;;   * gtags / GNU Global for cross-file `M-.' / `M-?' via the global xref
;;     backend that [`lisp/init-tags.el'](../init-tags.el) installs.  The tag
;;     database is built by `C-c g g'; `.java' is parsed by the pygments
;;     plug-in (the `java-pygments' label in [`gtags.conf'](../../gtags.conf))
;;     rather than the built-in parser, because
;;     gtags' built-in Java parser indexes no fields.  Annotations are indexed
;;     WITH their sigil (`@Autowired'); [`init-tags.el'](../init-tags.el) adds
;;     the `M-?' retry that hides that.
;;   * The two-tier project-root finder below, which decides where that index
;;     is rooted.
;;   * The JUnit runner (`C-c t ...'), a tree-sitter + `compile' front-end that
;;     never needed a language server.
;;
;; What Java therefore does NOT get -- accept these or put jdtls back, there is
;; no middle position: type-aware completion, hover javadoc, live diagnostics,
;; rename/extract refactors, find-implementations, and navigation into JDK or
;; third-party jar sources.  gtags answers at the NAME level only: `M-.' on an
;; overloaded name offers every same-named definition in the project with no
;; type to discriminate them (measured on ~/code/camhr/camhr: `getId' has 75).
;;
;; See [`_doc/JAVA.md'](../../_doc/JAVA.md) for the workflow and
;; [`_doc/TAGS.md'](../../_doc/TAGS.md) for the index mechanics.

;;; Code:

;; ----- LSP tombstone --------------------------------------------------------
;; Two stacks are INTENTIONALLY NOT INSTALLED here, in this order historically:
;;
;;   1. `lsp-mode' / `lsp-java' / `dap-mode' / `lsp-treemacs' / `lsp-docker' /
;;      `consult-lsp' -- dropped when Java migrated to Eglot.
;;   2. eclipse.jdt.ls (jdtls) itself, launched from this module via Eglot --
;;      dropped 2026-08-10.  Removed with it: the `eglot-server-programs' entry
;;      and `fenrir/jdtls-launch-command', the `:java'
;;      `eglot-workspace-configuration', the whole `jdt://' file-name-handler
;;      (plus the five `:before-while' / `:around' advices on
;;      `turn-on-diff-hl-mode', `org-roam-file-p', `breadcrumb-project-crumbs',
;;      `vc-refresh-state' and `consult-eglot--transformer' that existed ONLY
;;      to stop those packages choking on synthetic non-`file://' URIs), and
;;      `fenrir/eglot-java-add-roots-under'.
;;
;; WHY jdtls went: it is an Eclipse OSGi application on the JVM.  This module
;; launched it with `-Xmx3G' on a 15 GB machine and attached it unconditionally
;; from BOTH `java-mode-hook' and `java-ts-mode-hook', so merely opening a
;; `.java' file triggered a full Maven/Gradle workspace import -- the stall and
;; the memory spike that motivated the removal.  Its on-disk footprint was
;; another 453 MB (`var/lsp-java/': a 127 MB server bundle plus 325 MB of
;; workspace metadata).
;;
;; If you ever reinstate it, the deleted code is in git history at the commit
;; that removed it -- recover it from there rather than rewriting the `jdt://'
;; plumbing from scratch; it took several rounds to get the URI handler,
;; read-only timing and `normal-mode' interaction right.
;;
;; Do NOT reintroduce `dap-mode' either: Java debugging is unsupported here
;; (dape has no Java adapter, and dap-mode's fringe-bitmap breakpoints are
;; invisible on a TTY frame).  Use IntelliJ / VSCode for real Java debugging.

;; ----- Java/Maven project-root finder ---------------------------------------
;; Originally written to give jdtls one Eclipse workspace per reactor; it
;; outlives jdtls because project.el's root is what decides WHERE THE GTAGS
;; INDEX GETS BUILT.  `fenrir/gtags-build' (`C-c g g') defaults its directory
;; to the covering index root, falling back to the project.el root -- and GNU
;; Global resolves every lookup to the NEAREST ancestor `GTAGS', so an index
;; accidentally rooted at a single Maven module silently shadows the reactor
;; index for every file beneath it (see the nested-index-shadowing section of
;; [`_doc/TAGS.md'](../../_doc/TAGS.md)).  Rooting at the reactor is the whole
;; point.
;;
;; The default `project-try-vc' + `project-vc-extra-root-markers' approach
;; picks the FIRST (= deepest) ancestor holding `.project'.  Eclipse m2e leaves
;; a `.project' inside every Maven module it ever imported, so those markers
;; are still on disk in any repo jdtls once touched -- which is exactly the
;; too-deep root this finder exists to override.  It ignores `.project'
;; entirely and resolves in two tiers:
;;
;;   Tier 1 (container marker): if any ancestor holds
;;     `fenrir/java-workspace-marker' (default `.eglot-java-workspace'), that
;;     ancestor is THE root for every Java file beneath it.  Use this to fuse
;;     several independent Maven/Gradle reactors sitting under one container
;;     dir into a SINGLE gtags index, so cross-reactor `M-.' / `M-?' resolve.
;;
;;   Tier 2 (topmost-pom): otherwise return the TOPMOST consecutive ancestor
;;     with `pom.xml' / `build.gradle*' -- the multi-module reactor root.
;;
;; Non-Java files return nil so `project-try-vc' still owns them.
;;
;; Return shape matches `project-try-vc's `(list 'vc BACKEND ROOT)' so every
;; consumer keyed on the project object sees the SAME key regardless of which
;; `project-find-functions' entry resolved a given buffer.
(defcustom fenrir/java-workspace-marker ".eglot-java-workspace"
  "Filename that fuses every Maven/Gradle reactor beneath it into one project.
When present in an ancestor of a Java file, that ancestor becomes the
project root for ALL Java files below it -- which in practice means one
gtags index covering several reactors, so cross-reactor xref resolves.
Takes precedence over the topmost-pom heuristic.

The name is a fossil of the jdtls era (it once fused Eclipse workspaces);
kept as-is so existing marker files on disk keep working."
  :type 'string
  :group 'fenrir)

(defun fenrir/project-find-java-build-root (dir)
  "Resolve DIR's Java project root as a project object (a (vc BACKEND ROOT) list).
Tier 1: the nearest ancestor containing `fenrir/java-workspace-marker'.
Tier 2: the topmost consecutive ancestor with a Maven/Gradle build file.
Returns nil if neither applies, deferring to other `project-find-functions'.
Only claims a root for Java buffers: this sits on the GLOBAL
`project-find-functions' and runs for every buffer, so an un-gated Tier-1
`fenrir/java-workspace-marker' container would hijack the project root of any
NON-Java file nested beneath it (e.g. a Python submodule under the same
container), forcing that file's tooling to root at the container and miss its
project-local `.venv'.  The reactor-fusing container is meant for \"every Java
file beneath it\", not every file."
  (when (derived-mode-p 'java-mode 'java-ts-mode)
    (let* ((d (file-name-as-directory (expand-file-name (or dir default-directory))))
           ;; `abbreviate-file-name' so the project path matches what
           ;; `project-try-vc' produces elsewhere -- otherwise sibling buffers
           ;; resolve to different project objects because `equal' on the
           ;; struct compares "~/..." vs "/home/..." paths byte-for-byte.
           (as-project
            (lambda (root)
              (let ((r (file-name-as-directory (expand-file-name root))))
                (list 'vc (ignore-errors (vc-responsible-backend r))
                      (abbreviate-file-name r)))))
           (container (locate-dominating-file d fenrir/java-workspace-marker)))
      (if container
          (funcall as-project container)
        (let* ((markers '("pom.xml" "build.gradle" "build.gradle.kts"
                          "settings.gradle" "settings.gradle.kts"))
               (has-marker
                (lambda (dd)
                  (and dd (seq-some (lambda (m) (file-exists-p (expand-file-name m dd)))
                                    markers))))
               (cur d)
               (root nil))
          (while (and cur (not (string-equal cur "/")) (not (funcall has-marker cur)))
            (let ((up (file-name-directory (directory-file-name cur))))
              (setq cur (and (not (string-equal up cur)) up))))
          (when (and cur (funcall has-marker cur))
            (setq root cur)
            (let ((up (file-name-directory (directory-file-name cur))))
              (while (and up (not (string-equal up "/")) (funcall has-marker up))
                (setq root up
                      up (file-name-directory (directory-file-name up))))))
          (when root (funcall as-project root)))))))

;; Place AHEAD of `project-try-vc' so Maven/Gradle roots win the `.project'
;; race.  `project-find-functions' is run in order, first non-nil wins.
(add-to-list 'project-find-functions #'fenrir/project-find-java-build-root)

;; ----- Container workspace marker -------------------------------------------
;; Tier 1 above fuses every Java reactor beneath a dir holding
;; `fenrir/java-workspace-marker' into one project root.  The marker is managed
;; by hand -- create it with
;;   touch <container-dir>/.eglot-java-workspace
;; and remove it with `rm', then `M-x fenrir/project-reset-cache' so project.el
;; re-resolves.  After adding or removing one, rebuild the index with `C-c g g'
;; from the newly-correct root and run `C-c g d' to delete any sub-index the
;; old root left behind.

;; ----- JUnit test runner (junit-core C++ module) ----------------------------
;; tree-sitter-based JUnit discovery + Maven/Gradle command construction lives
;; in the `junit-core' dynamic module (cpp/); `junit-runner' is the elisp
;; front-end that loads it on demand and runs the test via `compile'.  Source
;; and build: cpp/junit-core/src/junit-core.cpp, cpp/build.sh.  The require is
;; cheap (no .so load until the first command); build the module once with
;; `M-x junit-runner-build'.  Never depended on a language server.
(require 'junit-runner nil t)

;; `C-c t' test prefix.  The Eglot refactor keys this used to avoid (`C-c .' /
;; `r' / `i' / `x' / `f' / `h ...') are no longer live in Java buffers, but
;; `C-c o' still belongs to combobulate -- keep off it.
(defun fenrir/junit-bind-keys (map)
  "Bind the JUnit runner commands under `C-c t' in MAP."
  (define-key map (kbd "C-c t t") #'junit-run-dwim)
  (define-key map (kbd "C-c t m") #'junit-run-method-at-point)
  (define-key map (kbd "C-c t f") #'junit-run-file)
  (define-key map (kbd "C-c t b") #'junit-runner-build))
(with-eval-after-load 'cc-mode
  (fenrir/junit-bind-keys java-mode-map))
(with-eval-after-load 'java-ts-mode
  (fenrir/junit-bind-keys java-ts-mode-map))

(provide 'init-java)
;;; init-java.el ends here
