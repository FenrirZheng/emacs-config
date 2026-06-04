;;; init-java.el --- Java: Eglot + jdtls -*- lexical-binding: t; -*-

;;; Commentary:
;; Java language support, split out of the monolithic init-languages.el.
;; Java migrated from lsp-mode to Eglot on the `try/java-on-eglot' branch.
;; This module owns everything Java-specific:
;;
;;   * Two-tier project-root resolution (`fenrir/project-find-java-build-root')
;;     prepended to `project-find-functions', plus the `.eglot-java-workspace'
;;     container marker that fuses several Maven/Gradle reactors into one jdtls
;;     workspace.
;;   * The jdtls launcher (`fenrir/jdtls-launch-command') registered as an
;;     `eglot-server-programs' entry, and the `:java' workspace configuration.
;;   * The `jdt://' URI scheme handler (relays to jdtls' `java/classFileContents'
;;     extension) so M-. into JDK / third-party-jar classes works, plus the set
;;     of `:before-while' advices that keep diff-hl / org-roam / breadcrumb /
;;     vc-refresh / consult-eglot from choking on the synthetic non-`file://'
;;     URIs.
;;   * `fenrir/eglot-java-add-roots-under' + the set/unset workspace-root
;;     commands.
;;   * The `java-mode' / `java-ts-mode' -> `eglot-ensure' hooks.
;;
;; The language-agnostic Eglot core (settings, eglot-booster, consult-eglot,
;; project.el ignore-$HOME advice, `fenrir/project-reset-cache', ...) lives in
;; [`lisp/init-languages.el'](../init-languages.el).  This module assumes it has
;; already loaded -- `fenrir/project-reset-cache' and the eglot use-package are
;; referenced here.
;;
;; dap-java is gone with lsp-mode; Java debug is unsupported in this config
;; until either dape grows a Java adapter or a manual java-debug bridge is
;; added.  Use IntelliJ / VSCode for real Java debugging until then.

;;; Code:

;; ----- LSP-stack tombstone (post-Eglot migration) ---------------------------
;; The whole `lsp-mode' / `lsp-java' / `dap-mode' / `lsp-treemacs' / `lsp-docker'
;; / `consult-lsp' stack is INTENTIONALLY NOT INSTALLED.  Java was migrated off
;; lsp-java onto Eglot + jdtls (this module); the launcher
;; (`fenrir/jdtls-launch-command' below) reads the jdtls binary tree directly
;; from [`var/lsp-java/eclipse.jdt.ls/server/'](../../var/lsp-java/eclipse.jdt.ls/)
;; -- a directory ONCE downloaded by the old lsp-java, now used standalone.  The
;; `lsp-java' / `var/lsp-java/' name is historical only; nothing requires the
;; package.  The dead stack + its orphan deps (treemacs, hydra, posframe, ...)
;; were removed via `M-x package-autoremove' (none are in
;; `package-selected-packages').  If `package-autoremove' ever lists any `lsp-*'
;; again, something re-added them -- investigate and uninstall, do NOT reinstall
;; the package believing the launcher needs it (it does not).

(require 'cl-lib)        ; cl-letf* (jdt:// consult-eglot guard), cl-remove-if-not

;; ----- Java/Maven workspace-root finder -------------------------------------
;; The default `project-try-vc' + `project-vc-extra-root-markers' approach picks
;; the FIRST (= deepest) ancestor that has `.project' walking up from the file.
;; Eclipse m2e (which jdtls bundles) auto-generates `.project' inside every
;; Maven module on import, so even if a developer drops a single `.project' at
;; the monorepo root, the import re-creates deeper ones and the next
;; `project-current' call snaps back to the wrong (too-deep) module.
;;
;; This finder resolves a Java buffer's project in two tiers:
;;
;;   Tier 1 (container marker): if any ancestor holds
;;     `fenrir/java-workspace-marker' (default `.eglot-java-workspace'), that
;;     ancestor is THE root for every Java file beneath it.  Use this to fuse
;;     several independent Maven/Gradle reactors sitting under one container
;;     dir (e.g. ~/code/hitok2/ holding im-combined-hitok + im-combined-api +
;;     hitok-java-backend) into a SINGLE Eglot server -> SINGLE jdtls Eclipse
;;     workspace, so cross-project find-references / navigation work and you
;;     never spawn a second jdtls (which would fight over the shared `-data').
;;     Pair with `java.import.exclusions' (see the :java workspace config) to
;;     keep jdtls from importing non-Java subtrees under the container.
;;
;;   Tier 2 (topmost-pom): otherwise return the TOPMOST consecutive ancestor
;;     with `pom.xml' / `build.gradle*' -- the multi-module reactor root for a
;;     standalone Maven/Gradle project.  Ignores `.project' markers entirely.
;;
;; Non-Java files (no marker in either tier) return nil so `project-try-vc'
;; still owns them.
;;
;; Return shape matches `project-try-vc's `(list 'vc BACKEND ROOT)' so that
;; eglot's session hash (keyed on the project object) sees the SAME key
;; regardless of which `project-find-functions' entry resolved a given
;; buffer.  Otherwise sibling buffers in the same workspace would spawn
;; separate jdtls sessions.
(defcustom fenrir/java-workspace-marker ".eglot-java-workspace"
  "Filename that pins a directory as a unified jdtls workspace root.
When present in an ancestor of a Java file, that ancestor becomes the
project root for ALL Java files beneath it, fusing multiple independent
Maven/Gradle reactors under one container into a single Eglot server.
Takes precedence over the topmost-pom heuristic."
  :type 'string
  :group 'fenrir)

(defun fenrir/project-find-java-build-root (dir)
  "Resolve DIR's Java project root as a project object (a (vc BACKEND ROOT) list).
Tier 1: the nearest ancestor containing `fenrir/java-workspace-marker'.
Tier 2: the topmost consecutive ancestor with a Maven/Gradle build file.
Returns nil if neither applies, deferring to other `project-find-functions'."
  (let* ((d (file-name-as-directory (expand-file-name (or dir default-directory))))
         ;; `abbreviate-file-name' so the project path matches what
         ;; `project-try-vc' produces elsewhere -- otherwise sibling buffers
         ;; spawn separate eglot sessions because `equal' on the project
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
        (when root (funcall as-project root))))))

;; Place AHEAD of `project-try-vc' so Java/Maven roots win the `.project'
;; race.  `project-find-functions' is run in order, first non-nil wins.
(add-to-list 'project-find-functions #'fenrir/project-find-java-build-root)

;; ----- jdtls launcher -------------------------------------------------------
;; jdtls is launched directly from this config rather than via lsp-java's
;; `lsp-install-server' machinery.  The bundle still lives at the historic path
;; `var/lsp-java/eclipse.jdt.ls/server/' (~150 MB, originally downloaded by
;; lsp-java) so no re-install is needed -- only the workspace metadata at
;; `var/lsp-java/workspace/' may be wiped out-of-band to force re-import from
;; scratch.  eglot-booster (init-languages.el) wraps the new connection
;; automatically -- its `eglot--connect' advice is generic, no Java-specific
;; wiring needed.

(defcustom fenrir/jdtls-bundle-dir
  (expand-file-name "var/lsp-java/eclipse.jdt.ls/server/" user-emacs-directory)
  "Root of the eclipse.jdt.ls server bundle.
Inherited from lsp-java's install location."
  :type 'directory
  :group 'fenrir)

(defcustom fenrir/jdtls-workspace-dir
  (expand-file-name "var/lsp-java/workspace/" user-emacs-directory)
  "Per-project workspace metadata directory for jdtls.
Re-created on first launch.  Delete this directory out-of-band to force
jdtls to re-import all projects from scratch."
  :type 'directory
  :group 'fenrir)

(defun fenrir/jdtls--equinox-launcher ()
  "Resolve the absolute path of org.eclipse.equinox.launcher_*.jar.
The version suffix changes per jdtls release, so we wildcard-glob."
  (car (file-expand-wildcards
        (expand-file-name "plugins/org.eclipse.equinox.launcher_*.jar"
                          fenrir/jdtls-bundle-dir))))

(defun fenrir/jdtls--config-dir ()
  "Resolve the platform-specific Equinox config directory."
  (expand-file-name
   (pcase system-type
     ('gnu/linux  (if (string-match-p "aarch64" system-configuration)
                      "config_linux_arm" "config_linux"))
     ('darwin     (if (string-match-p "aarch64" system-configuration)
                      "config_mac_arm" "config_mac"))
     ('windows-nt "config_win")
     (_ "config_linux"))
   fenrir/jdtls-bundle-dir))

(defun fenrir/jdtls--java-settings ()
  "Build the jdtls `:java' settings plist for the connecting buffer.
Starts from the global `:java' entry of `eglot-workspace-configuration',
then -- when the buffer sits inside a fused container workspace (see
`fenrir/java-workspace-marker') -- DISABLES the Gradle importer.

Why: jdtls' `import.exclusions' does NOT stop Buildship (its Gradle
importer) from descending into excluded subtrees.  A container like
~/code/hitok2/ holds a React Native app (im-pay) whose `android/' Gradle
build references an absent `@react-native/gradle-plugin'; Buildship's
sync of it fails and stalls jdtls' whole init.  The container's real
Java projects are all Maven, so turning Gradle off there loses nothing.
Standalone Gradle projects (no container marker -> their own server)
keep Gradle enabled."
  (let ((base (alist-get :java eglot-workspace-configuration)))
    (if (locate-dominating-file default-directory fenrir/java-workspace-marker)
        (let ((s (copy-tree base)))
          (setf (plist-get s :import)
                (plist-put (plist-get s :import) :gradle '(:enabled :json-false)))
          s)
      base)))

(defun fenrir/jdtls-launch-command (&optional _interactive)
  "Return the argv list to launch jdtls.
Used as the function-form value of an `eglot-server-programs' entry.
JVM args mirror the lsp-java preset: ParallelGC + GCTimeRatio +
AdaptiveSizePolicyWeight (throughput-oriented, beats G1 for index
build), 3G heap (jdtls' 1G default stalls hover/references on any
non-trivial Maven project).

The trailing `:initializationOptions' is Eglot's documented mechanism
for feeding a server its config at the `initialize' request (vs the
later `workspace/didChangeConfiguration').  jdtls reads
`initializationOptions.settings.java' DURING its initial project scan,
so `import.exclusions' there actually keeps Buildship from descending
into excluded subtrees -- pushing the same keys only via
didChangeConfiguration is too late (the Gradle/Maven scan already
started).  `classFileContentsSupport' enables the `jdt://' URI flow the
handler below relies on.  eglot-booster prepends its wrapper to the
PROGRAM part only; the trailing keyword survives untouched."
  (let* ((launcher (fenrir/jdtls--equinox-launcher))
         (config (fenrir/jdtls--config-dir))
         (workspace fenrir/jdtls-workspace-dir)
         (java-settings (fenrir/jdtls--java-settings)))
    (unless launcher
      (user-error
       "jdtls equinox launcher not found under %s -- check `fenrir/jdtls-bundle-dir' or reinstall jdtls"
       fenrir/jdtls-bundle-dir))
    (make-directory workspace t)
    `("java"
      "-Declipse.application=org.eclipse.jdt.ls.core.id1"
      "-Dosgi.bundles.defaultStartLevel=4"
      "-Declipse.product=org.eclipse.jdt.ls.core.product"
      "-Dlog.level=ALL"
      "-Xmx3G" "-Xms200m"
      "-XX:+UseParallelGC" "-XX:GCTimeRatio=4"
      "-XX:AdaptiveSizePolicyWeight=90"
      "-Dsun.zip.disableMemoryMapping=true"
      "--add-modules=ALL-SYSTEM"
      "--add-opens" "java.base/java.util=ALL-UNNAMED"
      "--add-opens" "java.base/java.lang=ALL-UNNAMED"
      "-jar" ,launcher
      "-configuration" ,config
      "-data" ,workspace
      :initializationOptions
      (:settings (:java ,java-settings)
       :extendedClientCapabilities (:classFileContentsSupport t)))))

;; Wire jdtls into Eglot.  The :hook entries that fire `eglot-ensure' for
;; java-mode / java-ts-mode live at the bottom of this module -- this block
;; only adds the per-server launcher + workspace config.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((java-mode java-ts-mode) . ,#'fenrir/jdtls-launch-command))
  ;; Per-server settings (pushed via `workspace/didChangeConfiguration').
  ;; Keys mirror VSCode's Red Hat Java extension `settings.json' schema.
  ;; `:json-false' is Eglot's sentinel for JSON `false' -- bare `nil' would
  ;; serialize to JSON `null'.  Mirror of the lsp-java tuning:
  ;;   * references.includeDecompiledSources / includeAccessors -> false:
  ;;     speeds up find-references on dep-heavy projects.
  ;;   * referencesCodeLens / implementationsCodeLens -> false: removes
  ;;     the overlay that triggers continuous background references queries.
  ;;   * format.onType.enabled -> false: matches Eglot's general policy of
  ;;     not formatting per keystroke (apheleia / format-on-save covers it).
  ;;   * import.maven / import.gradle -> true: jdtls auto-detects which
  ;;     applies per project root.
  ;;   * configuration.maven.userSettings -> ~/.m2/settings-public.xml:
  ;;     the corp ~/.m2/settings.xml has a `mirrorOf=!nexus' HTTP blocker plus
  ;;     an active profile pointing at the internal Nexus at
  ;;     nexus.mosainet.com:8081 / 192.168.130.170:8081 -- both unreachable
  ;;     from the open net, and they make Maven import hang on TCP timeouts
  ;;     (75s+ per missing dep) which then blocks every LSP request through
  ;;     jdtls' main thread.  This points jdtls at a minimal settings.xml
  ;;     that shares ~/.m2/repository but skips the corp profile; CLI `mvn'
  ;;     still uses the default settings.xml unless explicitly given `-s'.
  ;;   * import.exclusions: when a container marker fuses several reactors
  ;;     under one root (see `fenrir/java-workspace-marker'), jdtls scans the
  ;;     WHOLE container.  The defaults skip node_modules / .metadata / etc.;
  ;;     `**/im-pay/**' is added because that subtree is a React Native app
  ;;     whose `android/` Gradle build references an absent
  ;;     `@react-native/gradle-plugin' and hangs/crashes the import.  Add more
  ;;     globs here for any other non-Java subtree under a fused container.
  ;;   * inlayHints.parameterNames.enabled -> "all": jdtls defaults to
  ;;     "literals" (parameter-name hints only for literal arguments).  "all"
  ;;     shows them for every argument, matching the richer inlay-hint posture
  ;;     of the Go / Rust / TS modules.  Rendered by the global
  ;;     `eglot-inlay-hints-mode' (init-languages.el); toggle off per-buffer
  ;;     with `C-c h i'.  Values: none | literals | all.
  (setf (alist-get :java eglot-workspace-configuration)
        `(:references (:includeDecompiledSources :json-false
                       :includeAccessors :json-false)
          :referencesCodeLens (:enabled :json-false)
          :implementationsCodeLens (:enabled :json-false)
          :format (:onType (:enabled :json-false))
          :import (:maven (:enabled t)
                   :gradle (:enabled t)
                   :exclusions ["**/node_modules/**"
                                "**/.metadata/**"
                                "**/archetype-resources/**"
                                "**/META-INF/maven/**"
                                "**/im-pay/**"])
          :configuration (:maven (:userSettings ,(expand-file-name "~/.m2/settings-public.xml")))
          :inlayHints (:parameterNames (:enabled "all")))))

;; ----- jdt:// URI scheme handler --------------------------------------------
;; When M-. lands on a JDK or third-party-jar class, jdtls returns a URI
;; like `jdt://contents/java.base/java.lang/String.class?...'.  Eglot leaves
;; non-`file://' schemes as-is; the returned "path" then routes through
;; `file-name-handler-alist'.  Our handler intercepts `jdt://', finds the
;; live jdtls server, requests source via `java/classFileContents', and
;; inserts the result into the visiting buffer.

(defun fenrir/eglot--jdtls-servers ()
  "Return the list of live Eglot servers backing a jdtls process.
Matches by checking each server's process command line for our bundle path."
  (cl-remove-if-not
   (lambda (server)
     (let ((cmd (mapconcat #'identity
                           (process-command (jsonrpc--process server))
                           " ")))
       (string-match-p (regexp-quote
                        (directory-file-name fenrir/jdtls-bundle-dir))
                       cmd)))
   ;; `eglot--servers-by-project' is a hash-table (project-key -> server list);
   ;; iterating it with `cl-loop for ... in' errors "Wrong type argument: sequencep".
   (let ((all '()))
     (maphash (lambda (_k v) (setq all (append v all)))
              eglot--servers-by-project)
     all)))

(defun fenrir/eglot--find-jdtls-server ()
  "Return any one live Eglot server backing a jdtls process, or nil."
  (car (fenrir/eglot--jdtls-servers)))

(defun fenrir/eglot--jdt-uri-directory ()
  "Return a REAL existing directory to stand in for a `jdt://' URI's dir part.
A `jdt://' URI has no real directory; returning the empty string (the
naive choice) makes `find-file-noselect' set the visiting buffer's
`default-directory' to \"\", which then poisons every path helper that
runs on display / idle -- project.el, breadcrumb, doom-modeline -- with
`(file-name-directory nil)' / `(file-relative-name nil ...)' crashes
(\"Wrong type argument: stringp, nil\"), and only on the FIRST visit
before their caches populate.  Returning the originating jdtls server's
project root instead keeps those helpers on real directories AND lets
`eglot-ensure' in the jdt:// buffer attach to the SAME server (rather
than guessing a transient project).  Falls back to the jdtls bundle dir,
then HOME, so it is never empty or nil."
  (file-name-as-directory
   (expand-file-name
    (or (ignore-errors
          (when-let* ((server (fenrir/eglot--find-jdtls-server)))
            (project-root (eglot--project server))))
        (and (file-directory-p fenrir/jdtls-bundle-dir) fenrir/jdtls-bundle-dir)
        "~/"))))

(defun fenrir/eglot--jdt-uri-handler (operation &rest args)
  "File-name handler for `jdt://' URIs -- relays to `java/classFileContents'."
  (cond
   ((eq operation 'expand-file-name) (car args))
   ((memq operation '(file-exists-p file-readable-p)) t)
   ((memq operation '(file-attributes file-symlink-p file-directory-p)) nil)
   ;; A real directory, NOT "" -- see `fenrir/eglot--jdt-uri-directory'.
   ((eq operation 'file-name-directory) (fenrir/eglot--jdt-uri-directory))
   ((eq operation 'file-name-nondirectory) (car args))
   ((eq operation 'insert-file-contents)
    (let* ((uri (car args))
           (visit (cadr args))
           (server (fenrir/eglot--find-jdtls-server))
           (content (if server
                        (jsonrpc-request server :java/classFileContents
                                         `(:uri ,uri))
                      "// No jdtls Eglot session active. Open a project Java\n// file first so jdtls can serve this class.\n")))
      (insert (or content ""))
      ;; Record the URI as the buffer's file name (re-navigation + eglot need
      ;; it), but do NOT set `buffer-read-only' here.  `insert-file-contents'
      ;; runs BEFORE find-file's `normal-mode'; a read-only buffer makes
      ;; `java-ts-mode' setup (and its hooks) signal "Buffer is read-only",
      ;; which `normal-mode' catches and then leaves the buffer in
      ;; `fundamental-mode' -- the classic "first visit errors, second visit
      ;; (buffer already exists, no re-setup) works".  Read-only is applied
      ;; afterwards by `fenrir/jdt--make-buffer-read-only' on `find-file-hook'.
      (when visit (setq buffer-file-name uri))
      (list uri (length (or content "")))))
   (t
    ;; Fall through for any operation we don't handle: temporarily disable
    ;; ourselves and re-dispatch.
    (let ((inhibit-file-name-handlers
           (cons #'fenrir/eglot--jdt-uri-handler
                 (and (eq inhibit-file-name-operation operation)
                      inhibit-file-name-handlers)))
          (inhibit-file-name-operation operation))
      (apply operation args)))))

(add-to-list 'file-name-handler-alist
             '("\\`jdt://" . fenrir/eglot--jdt-uri-handler))

;; Route jdt:// "files" into java-ts-mode (or java-mode if the tree-sitter
;; grammar isn't available) so eldoc / xref / breadcrumb work in the
;; synthesized buffer.
(add-to-list 'auto-mode-alist
             `("\\`jdt://" . ,(if (treesit-language-available-p 'java)
                                  'java-ts-mode
                                'java-mode)))

;; Make jdt:// buffers read-only AFTER find-file has fully set them up (major
;; mode + mode hooks).  Setting read-only earlier (in the `insert-file-contents'
;; handler) breaks `normal-mode'; see the note there.  Appended (`t') so it runs
;; last on `find-file-hook', after any other hook that might still modify the
;; freshly-loaded buffer.
(defun fenrir/jdt--make-buffer-read-only ()
  "Mark the current buffer read-only if it visits a `jdt://' URI."
  (when (and buffer-file-name (string-prefix-p "jdt://" buffer-file-name))
    (setq buffer-read-only t)))
(add-hook 'find-file-hook #'fenrir/jdt--make-buffer-read-only t)

;; Keep diff-hl OUT of jdt:// buffers.  `global-diff-hl-mode' (init-git.el)
;; turns `diff-hl-mode' on in every buffer that merely HAS a `buffer-file-name'
;; -- and our jdt:// buffers do (the URI).  diff-hl then runs its flydiff timer,
;; whose only "skip" guard is `(file-exists-p buffer-file-name)' -- which our
;; handler answers `t' to.  So flydiff proceeds into `diff-hl-update', calls
;; `vc-backend' on the synthetic URI (-> nil), and the timer dies with
;; "Wrong type argument: stringp, nil" (intermittently, since it is a timer,
;; only on the FIRST visit before the buffer is reused).  A decompiled
;; read-only class has nothing to diff against VCS, so just don't activate.
;; `:before-while' so a nil return skips the real `turn-on-diff-hl-mode';
;; order-independent vs whenever global-diff-hl-mode's find-file-hook fires.
(advice-add 'turn-on-diff-hl-mode :before-while
            (lambda ()
              (not (and buffer-file-name
                        (string-prefix-p "jdt://" buffer-file-name))))
            '((name . fenrir/jdt-no-diff-hl)))

;; Keep org-roam OUT of jdt:// buffers.  `org-roam-db-autosync-mode'
;; (init-org-roam.el) puts `org-roam-db-autosync--setup-file-h' on
;; `find-file-hook'; it runs `org-roam-file-p' on EVERY opened file, which does
;; `(file-relative-name path org-roam-directory)'.  On a jdt:// URI that
;; signals "Wrong type argument: stringp, nil", and because it runs on
;; find-file-hook the error aborts the visit -> the buffer is left in
;; `fundamental-mode' and the user sees `file-relative-name: ... nil'
;; ("first visit errors, second reuses the buffer and works").  A decompiled
;; jar class is never an Org-roam note, so short-circuit `org-roam-file-p' to
;; nil for jdt:// buffers.  `with-eval-after-load' because org-roam loads after
;; this module; `:before-while' returning nil skips org-roam-file-p's body.
(with-eval-after-load 'org-roam
  (advice-add 'org-roam-file-p :before-while
              (lambda (&optional file)
                (let ((f (or file (buffer-file-name (buffer-base-buffer)))))
                  (not (and f (string-prefix-p "jdt://" f)))))
              '((name . fenrir/jdt-no-org-roam))))

;; Skip breadcrumb's PROJECT crumbs in jdt:// buffers.  `breadcrumb-mode'
;; (global) enables in the jdt:// buffer during `normal-mode' and immediately
;; builds its header line; `breadcrumb-project-crumbs' -> `file-relative-name'
;; chokes on the synthetic URI.  Root cause shared by the diff-hl and org-roam
;; cases: our `expand-file-name' handler returns the jdt:// URI verbatim (it
;; must, to keep the URI navigable), but it is NOT an absolute path, so
;; `file-relative-name's internal path split feeds `string-prefix-p' a nil ->
;; "Wrong type argument: stringp, nil".  Because this fires during normal-mode
;; the visit aborts (fundamental-mode + the error the user sees).  Returning nil
;; for jdt:// skips only the project crumbs; the imenu/symbol crumbs (the useful
;; part inside a decompiled class) still render.  `with-eval-after-load' for
;; load order; `:before-while' nil-return skips the crumbs body.
(with-eval-after-load 'breadcrumb
  (advice-add 'breadcrumb-project-crumbs :before-while
              (lambda (&rest _)
                (not (and buffer-file-name
                          (string-prefix-p "jdt://" buffer-file-name))))
              '((name . fenrir/jdt-no-breadcrumb-project))))

;; Skip `vc-refresh-state' in jdt:// buffers.  It runs on `find-file-hook' and
;; calls `(vc-backend buffer-file-name)', which on the non-absolute jdt:// URI
;; hits the same `string-prefix-p' nil (see the breadcrumb note above).  Here
;; the error is non-fatal -- vc-refresh-state wraps it in `with-demoted-errors
;; "VC refresh error: %S"' so the visit still succeeds -- but it spams that
;; message on every first visit.  A decompiled jar class is never under VC, so
;; short-circuit.  vc-hooks is preloaded, so a plain `advice-add' is fine.
(advice-add 'vc-refresh-state :before-while
            (lambda ()
              (not (and buffer-file-name
                        (string-prefix-p "jdt://" buffer-file-name))))
            '((name . fenrir/jdt-no-vc-refresh)))

;; Make `consult-eglot-symbols' (M-g s) survive jdt:// results.  jdtls returns
;; JDK / jar types as `jdt://contents/...' URIs.  consult-eglot's
;; `consult-eglot--transformer' builds each candidate's display label with
;; `(file-relative-name (eglot-uri-to-path uri))'; `eglot-uri-to-path' leaves a
;; jdt:// URI unchanged (it is not a `file://' URI), and `file-relative-name'
;; then signals "Wrong type argument: stringp, nil" on the non-absolute jdt://
;; path -- the SAME class of bug guarded for diff-hl / breadcrumb / org-roam /
;; vc-refresh above.  It bites harder here: the transformer runs per candidate
;; inside `consult--async-map', and one throwing candidate aborts the WHOLE
;; refresh, so any Java `workspace/symbol' search that returns a jar/JDK type
;; (i.e. nearly every type search -- even `Event' pulls in java.util.* etc.)
;; errors out before showing anything.  Scope a jdt://-safe `file-relative-name'
;; to the transformer via `cl-letf' (no global override, no per-call overhead
;; elsewhere): for a jdt:// URI return the URI minus its giant `?...' query
;; string as the display label (e.g. "jdt://contents/rt.jar/java.awt.event/
;; PaintEvent.java").  The JUMP path is untouched -- selecting a candidate goes
;; through `consult-eglot--symbol-information-to-grep-params' ->
;; `eglot-uri-to-path' -> `find-file' -> our jdt:// handler, none of which calls
;; `file-relative-name'.  `with-eval-after-load' because consult-eglot loads
;; lazily (`:after (consult eglot)').
(with-eval-after-load 'consult-eglot
  (advice-add 'consult-eglot--transformer :around
              (lambda (orig sym)
                (cl-letf* ((frn (symbol-function 'file-relative-name))
                           ((symbol-function 'file-relative-name)
                            (lambda (file &optional dir)
                              (if (and (stringp file) (string-prefix-p "jdt://" file))
                                  (car (split-string file "?"))
                                (funcall frn file dir)))))
                  (funcall orig sym)))
              '((name . fenrir/jdt-consult-eglot-transformer))))

;; ----- Workspace folder bulk-add (Maven / Gradle scan) ----------------------
;; Mirror of the old `fenrir/lsp-java-add-roots-under'.  For a single
;; monorepo, project.el's root detection is usually enough -- drop a
;; `.project' marker at the monorepo root and jdtls auto-imports every
;; pom.xml / build.gradle underneath.  This helper is for the rarer case
;; where one container dir holds multiple unrelated Java projects
;; (e.g. ~/code/ with sibling repos at varying depths).

(defvar fenrir/eglot-java-scan-skip-dirs
  '("target" "build" "node_modules" "out" "dist" "vendor"
    ".gradle" ".idea" ".mvn" ".m2")
  "Directory basenames never descended into during the Maven / Gradle scan.")

(defun fenrir/eglot-java--scan-roots (dir markers)
  "Return absolute paths of Java build roots reachable from DIR (inclusive).
A directory counts as a root if any of MARKERS exists at its top level;
once matched, descent into that directory stops."
  (let ((results '())
        (queue (list (expand-file-name dir))))
    (while queue
      (let ((d (pop queue)))
        (when (file-directory-p d)
          (if (seq-some (lambda (m) (file-exists-p (expand-file-name m d))) markers)
              (push d results)
            (dolist (child (directory-files d t "\\`[^.]"))
              (when (and (file-directory-p child)
                         (not (file-symlink-p child))
                         (not (member (file-name-nondirectory child)
                                      fenrir/eglot-java-scan-skip-dirs)))
                (push child queue)))))))
    (nreverse results)))

(defun fenrir/eglot-java-add-roots-under (dir)
  "Register every Maven / Gradle root under DIR as a jdtls workspace folder.
Sends `workspace/didChangeWorkspaceFolders' to the live jdtls Eglot
session.  Interactive call prompts for DIR (default ~/code/)."
  (interactive (list (read-directory-name "Container dir: " "~/code/")))
  (require 'eglot)
  (let* ((markers '("pom.xml"
                    "build.gradle" "build.gradle.kts"
                    "settings.gradle" "settings.gradle.kts"))
         (roots (fenrir/eglot-java--scan-roots dir markers))
         (server (fenrir/eglot--find-jdtls-server)))
    (unless server
      (user-error "No jdtls Eglot session active; open a Java file first"))
    (when roots
      (jsonrpc-notify
       server :workspace/didChangeWorkspaceFolders
       `(:event (:added
                 ,(apply #'vector
                         (mapcar (lambda (r)
                                   `(:uri ,(eglot-path-to-uri r)
                                     :name ,(file-name-nondirectory
                                             (directory-file-name r))))
                                 roots))
                 :removed []))))
    (message "eglot-java: registered %d root(s) under %s: %s"
             (length roots)
             (abbreviate-file-name (expand-file-name dir))
             roots)))

;; ----- Container workspace marker: set / unset ------------------------------
;; The durable counterpart to `fenrir/eglot-java-add-roots-under'.  Dropping a
;; `fenrir/java-workspace-marker' file makes `fenrir/project-find-java-build-root'
;; Tier 1 fuse every Java reactor beneath that dir into one jdtls workspace --
;; surviving restarts, with no per-session didChangeWorkspaceFolders dance.

(defun fenrir/eglot-java--restart-jdtls ()
  "Shut down all live jdtls sessions so buffers reconnect afresh.
Returns the count shut down.  jdtls re-reads the project layout on the
next connect, so toggling a workspace marker takes effect after this."
  (let ((servers (fenrir/eglot--jdtls-servers)))
    (dolist (s servers) (ignore-errors (eglot-shutdown s 1 nil t)))
    (length servers)))

(defun fenrir/eglot-java-set-workspace-root (dir)
  "Mark DIR as a unified jdtls workspace root.
Creates `fenrir/java-workspace-marker' in DIR so every Java file beneath
it resolves to DIR (Tier 1 of `fenrir/project-find-java-build-root'),
fusing independent Maven/Gradle reactors under DIR into one Eglot server
+ one jdtls Eclipse workspace -- the basis for cross-project
find-references / navigation.  Resets the project cache and offers to
restart any running jdtls session so the new root takes effect.

Interactive default is the current project root, else `default-directory'."
  (interactive
   (list (read-directory-name
          "Java workspace root (drop marker here): "
          (or (ignore-errors (project-root (project-current)))
              default-directory))))
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (marker (expand-file-name fenrir/java-workspace-marker dir)))
    (unless (file-directory-p dir)
      (user-error "Not a directory: %s" dir))
    (unless (file-exists-p marker)
      (with-temp-file marker
        (insert "Marks " (abbreviate-file-name dir) " as a unified jdtls/Eglot\n"
                "workspace root -- read by fenrir/project-find-java-build-root in\n"
                "~/.emacs.d/lisp/languages/init-java.el.  Every Java file beneath\n"
                "this dir resolves to THIS dir as its project root, so independent\n"
                "Maven/Gradle reactors here share one Eglot server + one jdtls\n"
                "Eclipse workspace (cross-project find-references).  See\n"
                "~/.emacs.d/_doc/JAVA.md.  Created by M-x "
                "fenrir/eglot-java-set-workspace-root.\n")))
    (fenrir/project-reset-cache)
    (let ((n (when (and (fenrir/eglot--jdtls-servers)
                        (y-or-n-p "Marker set.  Restart running jdtls session(s) now? "))
               (fenrir/eglot-java--restart-jdtls))))
      (message "Java workspace root: %s%s"
               (abbreviate-file-name dir)
               (cond ((and n (> n 0))
                      (format " (%d session(s) shut down; reopen a .java file to reconnect)" n))
                     (t " (reopen .java files or M-x eglot to apply)"))))))

(defun fenrir/eglot-java-unset-workspace-root (dir)
  "Remove `fenrir/java-workspace-marker' from DIR (inverse of
`fenrir/eglot-java-set-workspace-root').  Java files beneath DIR then
fall back to the topmost-pom heuristic (Tier 2).  Interactive default is
the nearest ancestor that currently holds the marker."
  (interactive
   (list (read-directory-name
          "Remove Java workspace marker from: "
          (or (locate-dominating-file default-directory fenrir/java-workspace-marker)
              default-directory))))
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (marker (expand-file-name fenrir/java-workspace-marker dir)))
    (unless (file-exists-p marker)
      (user-error "No %s in %s" fenrir/java-workspace-marker (abbreviate-file-name dir)))
    (delete-file marker)
    (fenrir/project-reset-cache)
    (let ((n (when (and (fenrir/eglot--jdtls-servers)
                        (y-or-n-p "Marker removed.  Restart running jdtls session(s) now? "))
               (fenrir/eglot-java--restart-jdtls))))
      (message "Removed Java workspace marker from %s%s"
               (abbreviate-file-name dir)
               (if (and n (> n 0))
                   (format " (%d session(s) shut down)" n) "")))))

;; ----- eglot-ensure hooks ---------------------------------------------------
;; Java attaches on BOTH `java-mode' (built-in regex) and `java-ts-mode'
;; (tree-sitter) -- treesit-auto remaps .java files to the ts variant when the
;; grammar is installed, but the non-ts hook is kept for safety on machines
;; that haven't grabbed the grammar yet.  `eglot-ensure' is autoloaded from the
;; eglot package declared in init-languages.el, so no `:after' wiring is needed.
(add-hook 'java-mode-hook    #'eglot-ensure)
(add-hook 'java-ts-mode-hook #'eglot-ensure)

;; ----- JUnit test runner (junit-core C++ module) ----------------------------
;; tree-sitter-based JUnit discovery + Maven/Gradle command construction lives
;; in the `junit-core' dynamic module (cpp/); `junit-runner' is the elisp
;; front-end that loads it on demand and runs the test via `compile'.  Source
;; and build: cpp/junit-core/src/junit-core.cpp, cpp/build.sh.  The require is cheap (no
;; .so load until the first command); build the module once with
;; `M-x junit-runner-build'.
(require 'junit-runner nil t)

;; `C-c t' test prefix -- deliberately NOT under `C-c o' (combobulate) or the
;; Eglot refactor keys (`C-c .' / `r' / `i' / `x' / `f' / `h ...').
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
