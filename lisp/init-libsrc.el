;;; init-libsrc.el --- Java library sources for gtags M-. via GTAGSLIBPATH -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Java has no language server here (see init-java.el), and the project's GTAGS
;; index covers only the project tree -- so `M-.' on a library class such as
;; `org.springframework.boot.info.GitProperties' found nothing.  This module
;; gives `M-.' library SOURCES with no JVM inside Emacs, reusing GNU Global's
;; own library search path: `GTAGSLIBPATH' is a colon-separated list of
;; directories, each with its own GTAGS, that `global -d' searches.
;;
;; Moving parts (design: [TAGS.md](../_doc/TAGS.md#library-sources-fenrir-libsrc)):
;;
;;   1. Classpath, per build root, cached in `proj/<sha1>.eld':
;;      Maven `mvn -o dependency:build-classpath', Gradle via the bundled
;;      [init script](fenrir-libsrc/classpath.gradle).  Offline first, one
;;      online retry.  Both execute the project's own build code, so a root
;;      is first resolved only by an explicit `C-c g l'; after that, a
;;      changed build file re-resolves it automatically.
;;   2. Class index: `unzip -Z1' over every binary jar maps a simple class
;;      name to the artifact(s) defining it.  This is what makes indexing
;;      lazy -- a miss on `GitProperties' names the one jar to fetch.
;;   3. One shared, immutable tree per artifact version under
;;      `lib/<g>/<a>/<v>/': the extracted -sources.jar plus its own GTAGS,
;;      built in `<v>.tmp', made read-only, renamed, and only then marked
;;      ready with `.ok'.  A crash leaves a `.tmp' the next build removes.
;;   4. An `:around' method on the gtags xref backend's definitions: project
;;      hits win; otherwise query the ready trees; otherwise queue the build
;;      and re-jump when it lands.  `M-?' is untouched -- library hits would
;;      flood it.
;;
;; Name-level only, like project gtags: no types, overloads list every
;; same-named definition.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'xref)

;; From init-tags.el / gtags-mode, absent in a bare `emacs -Q --batch' test run.
(declare-function fenrir/gtags--index-valid-p "init-tags" (root))
(defvar fenrir/gtags-map)

(defgroup fenrir-libsrc nil
  "Java library sources on GTAGSLIBPATH."
  :group 'fenrir)

(defcustom fenrir/libsrc-cache-dir (expand-file-name "~/.cache/fenrir-libsrc/")
  "Root of the shared library-source cache.  Outside every repo on purpose."
  :type 'directory)

(defcustom fenrir/libsrc-m2-repository (expand-file-name "~/.m2/repository/")
  "Local Maven repository."
  :type 'directory)

(defcustom fenrir/libsrc-gradle-cache
  (expand-file-name "~/.gradle/caches/modules-2/files-2.1/")
  "Gradle's module cache (groupId stays dotted here, unlike ~/.m2)."
  :type 'directory)

(defcustom fenrir/libsrc-max-jobs 2
  "Concurrent artifact builds."
  :type 'natnum)

(defcustom fenrir/libsrc-gc-days 60
  "`fenrir/libsrc-gc' keeps an unreferenced tree younger than this."
  :type 'natnum)

(defconst fenrir/libsrc--gradle-script
  (expand-file-name "fenrir-libsrc/classpath.gradle"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Gradle init script printing the resolved classpath.")

(defconst fenrir/libsrc--cscope-regex
  "^\\(.+?\\) \\([^ ]+\\) \\([[:digit:]]+\\) \\(.*\\)"
  "One `global --result=cscope' line: file, name, line, code.
Same shape as `gtags-mode--output-format-regex'; copied, not referenced, so
the pure layer loads without gtags-mode.")

;; --- Pure layer (covered by test/libsrc-test.el) -----------------------------

(defun fenrir/libsrc--jar-gav (jar)
  "Return (GROUP ARTIFACT VERSION) for binary JAR, or nil.
Understands ~/.m2 layout (slashed groupId) and the Gradle module cache
\(dotted groupId, one hash directory).  Classifier jars return nil."
  (cond
   ((string-match "/files-2\\.1/\\([^/]+\\)/\\([^/]+\\)/\\([^/]+\\)/[^/]+/\\2-\\3\\.jar\\'"
                  jar)
    (list (match-string 1 jar) (match-string 2 jar) (match-string 3 jar)))
   ((string-match "/repository/\\(.+\\)/\\([^/]+\\)/\\([^/]+\\)/\\2-\\3\\.jar\\'" jar)
    (list (string-replace "/" "." (match-string 1 jar))
          (match-string 2 jar) (match-string 3 jar)))))

(defun fenrir/libsrc--gav-string (gav)
  "GAV list as \"g:a:v\"."
  (string-join gav ":"))

(defun fenrir/libsrc--gav-dir (gav)
  "Slash-terminated cache tree for GAV (list or \"g:a:v\" string)."
  (let ((gav (if (stringp gav) (split-string gav ":") gav)))
    (file-name-as-directory
     (expand-file-name (string-join gav "/")
                       (expand-file-name "lib" fenrir/libsrc-cache-dir)))))

(defun fenrir/libsrc--class-entry-name (entry)
  "Simple class name for jar ENTRY (a `unzip -Z1' line), or nil.
Strips the package and any `$Inner' suffix; skips module-info / package-info."
  (when (string-match "\\([^/$]+\\)\\(?:\\$[^/]*\\)?\\.class\\'" entry)
    (let ((name (match-string 1 entry)))
      (unless (member name '("module-info" "package-info"))
        name))))

(defun fenrir/libsrc--parse-maven-classpath (string)
  "Jar paths from a `dependency:build-classpath' output file STRING."
  (delete-dups
   (seq-filter (lambda (p) (string-suffix-p ".jar" p))
               (split-string (string-trim string) "[:\n]" t))))

(defun fenrir/libsrc--parse-gradle-output (string)
  "Jar paths from the init script's output STRING (prefixed lines only)."
  (let (acc)
    (dolist (line (string-lines string t))
      (when (and (string-prefix-p "FENRIR-LIBSRC-JAR " line)
                 (string-suffix-p ".jar" line))
        (push (substring line (length "FENRIR-LIBSRC-JAR ")) acc)))
    (delete-dups (nreverse acc))))

(defun fenrir/libsrc--parse-listing (string)
  "Parse the batched listing STRING into an alist (JAR . CLASS-NAMES).
Each jar starts with an `@@<jar>' line followed by its `unzip -Z1' lines."
  (let (acc cur)
    (dolist (line (string-lines string t))
      (if (string-prefix-p "@@" line)
          (push (setq cur (list (substring line 2))) acc)
        (when-let* ((cur) (name (fenrir/libsrc--class-entry-name line)))
          (setcdr cur (cons name (cdr cur))))))
    (mapcar (lambda (c) (cons (car c) (delete-dups (cdr c)))) (nreverse acc))))

(defun fenrir/libsrc--build-class-index (listing)
  "Hash table simple-name -> list of \"g:a:v\" from LISTING (see above).
Jars with no GAV are skipped -- there is no sources jar to ask for."
  (let ((index (make-hash-table :test #'equal)))
    (pcase-dolist (`(,jar . ,names) listing)
      (when-let* ((gav (fenrir/libsrc--jar-gav jar)))
        (let ((g (fenrir/libsrc--gav-string gav)))
          (dolist (n names)
            (unless (member g (gethash n index))
              (puthash n (append (gethash n index) (list g)) index))))))
    index))

(defun fenrir/libsrc--ready-p (dir)
  "Non-nil when tree DIR finished building."
  (file-exists-p (expand-file-name ".ok" dir)))

(defun fenrir/libsrc--libpath-string (dirs)
  "GTAGSLIBPATH value from the ready trees in DIRS, or nil when none."
  (when-let* ((ready (seq-filter #'fenrir/libsrc--ready-p dirs)))
    (mapconcat #'directory-file-name ready ":")))

(defun fenrir/libsrc--parse-hits (string)
  "xref items from `global --result=cscope --path-style=absolute' STRING."
  (let (acc)
    (dolist (line (string-lines string t))
      (when (string-match fenrir/libsrc--cscope-regex line)
        (push (xref-make (match-string 4 line)
                         (xref-make-file-location
                          (match-string 1 line)
                          (string-to-number (match-string 3 line)) 0))
              acc)))
    (nreverse acc)))

(defun fenrir/libsrc--state-file (root)
  "Persisted state file for build ROOT."
  (expand-file-name (concat "proj/" (sha1 (directory-file-name root)) ".eld")
                    fenrir/libsrc-cache-dir))

(defun fenrir/libsrc--write-state (root state)
  "Persist STATE (plist, with a hash table) for ROOT."
  (let ((file (fenrir/libsrc--state-file root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (let ((print-length nil) (print-level nil))
        (prin1 state (current-buffer))))))

(defun fenrir/libsrc--read-state (root)
  "Persisted state for ROOT, or nil."
  (let ((file (fenrir/libsrc--state-file root)))
    (when (file-readable-p file)
      (ignore-errors
        (with-temp-buffer
          (insert-file-contents file)
          (read (current-buffer)))))))

(defun fenrir/libsrc--remove-tree (dir)
  "Delete DIR recursively, first restoring owner write (trees are read-only)."
  (when (file-exists-p dir)
    (call-process "chmod" nil nil nil "-R" "u+w" (directory-file-name dir))
    (delete-directory dir t)))

(defun fenrir/libsrc--stale-tmp-dirs ()
  "Every `<v>.tmp' build directory under lib/."
  (let ((lib (expand-file-name "lib" fenrir/libsrc-cache-dir)))
    (when (file-directory-p lib)
      (seq-filter
       (lambda (d) (and (string-suffix-p ".tmp" d) (file-directory-p d)))
       (directory-files-recursively
        lib "\\.tmp\\'" t
        (lambda (d) (not (string-suffix-p ".tmp" d))))))))

(defun fenrir/libsrc--build-root (dir)
  "Directory whose build file defines DIR's classpath, or nil.
The deepest of: the nearest `pom.xml' (one Maven module), the nearest
Gradle settings root (the init script unions every subproject)."
  (let ((cands (delq nil
                     (list (locate-dominating-file dir "pom.xml")
                           (locate-dominating-file dir "settings.gradle.kts")
                           (locate-dominating-file dir "settings.gradle")
                           (locate-dominating-file dir "gradlew")))))
    (when cands
      (file-name-as-directory
       (expand-file-name
        (car (sort cands (lambda (a b) (> (length (expand-file-name a))
                                          (length (expand-file-name b)))))))))))

(defun fenrir/libsrc--build-mtime (root)
  "Newest mtime (float) of ROOT's build files."
  (apply #'max 0
         (mapcar (lambda (f)
                   (let ((p (expand-file-name f root)))
                     (if (file-exists-p p)
                         (float-time (file-attribute-modification-time
                                      (file-attributes p)))
                       0)))
                 '("pom.xml" "build.gradle" "build.gradle.kts"
                   "settings.gradle" "settings.gradle.kts"))))

;; --- Per-project state --------------------------------------------------------
;; Plist: :root :classpath-mtime :jars (list of jar paths) :unparsed (jars
;; with no GAV) :class-index (name -> "g:a:v" list) :libpath (trees used).

(defvar fenrir/libsrc--projects (make-hash-table :test #'equal)
  "Build root -> state plist, loaded lazily from `proj/*.eld'.")

(defvar fenrir/libsrc--resolving (make-hash-table :test #'equal)
  "Build root -> list of callbacks waiting for a classpath resolution.")

(defun fenrir/libsrc--state (root)
  "State plist for ROOT from memory or disk, or nil."
  (or (gethash root fenrir/libsrc--projects)
      (when-let* ((st (fenrir/libsrc--read-state root)))
        (puthash root st fenrir/libsrc--projects))))

(defun fenrir/libsrc--state-update (root &rest props)
  "Set PROPS (alternating keys and values) in ROOT's state and persist it."
  (let ((st (or (copy-sequence (fenrir/libsrc--state root)) (list :root root))))
    (while props
      (setq st (plist-put st (pop props) (pop props))))
    (puthash root st fenrir/libsrc--projects)
    (fenrir/libsrc--write-state root st)
    st))

(defun fenrir/libsrc--log-buffer ()
  "The shared `*libsrc*' log buffer."
  (let ((buf (get-buffer-create "*libsrc*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'special-mode) (special-mode)))
    buf))

(defun fenrir/libsrc--log (fmt &rest args)
  "Append FMT/ARGS to `*libsrc*'."
  (with-current-buffer (fenrir/libsrc--log-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format-time-string "%T ") (apply #'format fmt args) "\n"))))

(defun fenrir/libsrc--run (name command dir callback)
  "Run COMMAND asynchronously in DIR; call CALLBACK with (EXIT OUTPUT)."
  (let* ((default-directory dir)
         (buf (generate-new-buffer (format " *libsrc-%s*" name))))
    (fenrir/libsrc--log "$ (cd %s && %s)" (abbreviate-file-name dir)
                        (mapconcat #'shell-quote-argument command " "))
    (make-process
     :name (concat "libsrc-" name) :buffer buf :command command
     :connection-type 'pipe :noquery t
     :sentinel
     (lambda (proc _event)
       (unless (process-live-p proc)
         (let ((out (with-current-buffer buf (buffer-string)))
               (exit (process-exit-status proc)))
           (kill-buffer buf)
           (unless (eq exit 0)
             (fenrir/libsrc--log "exit %s: %s" exit
                                 (string-trim (truncate-string-to-width out 2000))))
           (funcall callback exit out)))))))

;; --- 1+2. Classpath resolution and class index --------------------------------

(defun fenrir/libsrc--classpath-command (root offline out-file)
  "Command resolving ROOT's classpath, or nil.  OUT-FILE is Maven's output."
  (cond
   ((file-exists-p (expand-file-name "pom.xml" root))
    `("mvn" "-q" "-B" ,@(and offline '("-o")) "dependency:build-classpath"
      ,(concat "-Dmdep.outputFile=" out-file) "-Dmdep.appendOutput=true"))
   ((let ((gradlew (expand-file-name "gradlew" root)))
      (when (or (file-exists-p gradlew) (executable-find "gradle"))
        `(,@(cond ((file-executable-p gradlew) '("./gradlew"))
                  ((file-exists-p gradlew) '("sh" "./gradlew"))   ; checked in without +x
                  (t '("gradle")))
          "-q" ,@(and offline '("--offline"))
          "-I" ,fenrir/libsrc--gradle-script "fenrirLibsrcClasspath"))))))

(defun fenrir/libsrc--resolve (root &optional callback)
  "Resolve ROOT's classpath and class index asynchronously.
CALLBACK, if given, runs with no arguments after success."
  (let ((waiting (gethash root fenrir/libsrc--resolving 'none)))
    (if (not (eq waiting 'none))
        (when callback (puthash root (cons callback waiting) fenrir/libsrc--resolving))
      (puthash root (and callback (list callback)) fenrir/libsrc--resolving)
      (fenrir/libsrc--resolve-attempt root t))))

(defun fenrir/libsrc--resolve-done (root ok)
  "Finish ROOT's resolution; run waiting callbacks when OK."
  (let ((cbs (gethash root fenrir/libsrc--resolving)))
    (remhash root fenrir/libsrc--resolving)
    (when ok (mapc (lambda (f) (ignore-errors (funcall f))) (reverse cbs)))))

(defun fenrir/libsrc--resolve-attempt (root offline)
  "One resolution attempt for ROOT; OFFLINE first, then one online retry."
  (let* ((out (make-temp-file "libsrc-cp"))
         (cmd (fenrir/libsrc--classpath-command root offline out)))
    (if (not cmd)
        (progn (delete-file out)
               (fenrir/libsrc--resolve-done root nil)
               (message "libsrc: no Maven/Gradle build in %s" root))
      (message "libsrc: resolving classpath for %s%s..."
               (abbreviate-file-name root) (if offline "" " (online)"))
      ;; appendOutput: a reactor run appends every module's classpath.
      (with-temp-file out)
      (fenrir/libsrc--run
       "classpath" cmd root
       (lambda (exit output)
         (let ((jars (when (eq exit 0)
                       (if (string= (car cmd) "mvn")
                           (fenrir/libsrc--parse-maven-classpath
                            (with-temp-buffer
                              (insert-file-contents out) (buffer-string)))
                         (fenrir/libsrc--parse-gradle-output output)))))
           (delete-file out)
           (cond
            (jars (fenrir/libsrc--index-classes root jars))
            (offline (fenrir/libsrc--resolve-attempt root nil))
            (t (fenrir/libsrc--resolve-done root nil)
               (message "libsrc: classpath resolution failed for %s -- see *libsrc*"
                        (abbreviate-file-name root))))))))))

(defun fenrir/libsrc--index-classes (root jars)
  "List JARS in one async process, then store ROOT's class index."
  (fenrir/libsrc--run
   "classes"
   `("sh" "-c" "for j; do printf '@@%s\\n' \"$j\"; unzip -Z1 \"$j\" 2>/dev/null; done"
     "sh" ,@jars)
   root
   (lambda (_exit output)
     (let* ((listing (fenrir/libsrc--parse-listing output))
            (index (fenrir/libsrc--build-class-index listing)))
       (fenrir/libsrc--state-update
        root
        :classpath-mtime (fenrir/libsrc--build-mtime root)
        :jars jars
        :unparsed (seq-remove #'fenrir/libsrc--jar-gav jars)
        :class-index index)
       (message "libsrc: %d jars, %d classes indexed for %s"
                (length jars) (hash-table-count index) (abbreviate-file-name root))
       (fenrir/libsrc--resolve-done root t)))))

;; --- 3. Fetch, extract and index one artifact ---------------------------------

(defvar fenrir/libsrc--jobs (make-hash-table :test #'equal)
  "\"g:a:v\" -> callbacks for a queued or running build.")
(defvar fenrir/libsrc--queue nil "GAVs waiting for a build slot.")
(defvar fenrir/libsrc--running 0 "Builds in flight.")

(defun fenrir/libsrc--no-sources-file (gav)
  "Marker recording that GAV publishes no sources jar."
  (concat (directory-file-name (fenrir/libsrc--gav-dir gav)) ".no-sources"))

(defvar fenrir/libsrc--local-sources (make-hash-table :test #'equal)
  "Pseudo-GAV -> source archive not in any Maven/Gradle cache (the JDK's src.zip).")

(defun fenrir/libsrc--find-sources-jar (gav)
  "Local -sources.jar for GAV, from ~/.m2 or the Gradle cache, or nil."
  (pcase-let* ((`(,g ,a ,v) (split-string gav ":"))
               (base (format "%s-%s-sources.jar" a v))
               (m2 (expand-file-name (format "%s/%s/%s/%s" (string-replace "." "/" g) a v base)
                                     fenrir/libsrc-m2-repository)))
    (cond
     ((gethash gav fenrir/libsrc--local-sources))
     ((file-exists-p m2) m2)
     (t (car (file-expand-wildcards
            (expand-file-name (format "%s/%s/%s/*/%s" g a v base)
                              fenrir/libsrc-gradle-cache)))))))

(defun fenrir/libsrc-ensure (gav &optional callback)
  "Make GAV's indexed source tree ready; CALLBACK gets `ok', `no-sources' or `error'."
  (cond
   ((fenrir/libsrc--ready-p (fenrir/libsrc--gav-dir gav))
    (when callback (funcall callback 'ok)))
   ((file-exists-p (fenrir/libsrc--no-sources-file gav))
    (when callback (funcall callback 'no-sources)))
   ((gethash gav fenrir/libsrc--jobs)
    (when callback (puthash gav (cons callback (gethash gav fenrir/libsrc--jobs))
                            fenrir/libsrc--jobs)))
   (t
    (puthash gav (list (or callback #'ignore)) fenrir/libsrc--jobs)
    (setq fenrir/libsrc--queue (append fenrir/libsrc--queue (list gav)))
    (fenrir/libsrc--pump))))

(defun fenrir/libsrc--pump ()
  "Start queued builds while slots are free."
  (while (and fenrir/libsrc--queue (< fenrir/libsrc--running fenrir/libsrc-max-jobs))
    (cl-incf fenrir/libsrc--running)
    (fenrir/libsrc--build (pop fenrir/libsrc--queue))))

(defun fenrir/libsrc--finish (gav result &optional detail)
  "End GAV's build with RESULT; DETAIL goes to the log."
  (cl-decf fenrir/libsrc--running)
  (fenrir/libsrc--log "%s: %s%s" gav result (if detail (concat " -- " detail) ""))
  (let ((cbs (gethash gav fenrir/libsrc--jobs)))
    (remhash gav fenrir/libsrc--jobs)
    (dolist (f (reverse cbs))
      (condition-case err (funcall f result)
        (error (message "libsrc: %s" (error-message-string err))))))
  (fenrir/libsrc--pump))

(defun fenrir/libsrc--build (gav)
  "Locate (or download) GAV's sources jar, then extract and index it."
  (let ((final (fenrir/libsrc--gav-dir gav)))
    (if (fenrir/libsrc--ready-p final)
        (fenrir/libsrc--finish gav 'ok)
      (if-let* ((src (fenrir/libsrc--find-sources-jar gav)))
          (fenrir/libsrc--extract gav src)
        (make-directory fenrir/libsrc-cache-dir t)
        (fenrir/libsrc--run
         "fetch"
         `("mvn" "-q" "-B" "dependency:get"
           ,(concat "-Dartifact=" gav ":jar:sources") "-Dtransitive=false")
         fenrir/libsrc-cache-dir        ; no pom here, no stray .mvn/ config
         (lambda (exit output)
           (let ((src (fenrir/libsrc--find-sources-jar gav)))
             (cond
              ((and (eq exit 0) src) (fenrir/libsrc--extract gav src))
              ;; Only a definite "not published" is remembered; a network
              ;; failure must stay retryable.
              ((string-match-p "Could not find artifact\\|was not found in" output)
               (make-directory (file-name-directory
                                (fenrir/libsrc--no-sources-file gav)) t)
               (with-temp-file (fenrir/libsrc--no-sources-file gav))
               (fenrir/libsrc--finish gav 'no-sources))
              (t (fenrir/libsrc--finish gav 'error "sources download failed"))))))))))

(defun fenrir/libsrc--extract (gav src)
  "Unzip SRC for GAV into `<v>.tmp', run gtags there, then publish it."
  (let* ((final (fenrir/libsrc--gav-dir gav))
         (tmp (concat (directory-file-name final) ".tmp/")))
    (fenrir/libsrc--remove-tree tmp)            ; a crashed earlier build
    (fenrir/libsrc--remove-tree final)          ; renamed but never marked .ok
    (make-directory tmp t)
    (fenrir/libsrc--run
     "unzip" (list "unzip" "-q" "-o" src "-d" tmp) tmp
     (lambda (exit _)
       (if (not (eq exit 0))
           (progn (fenrir/libsrc--remove-tree tmp)
                  (fenrir/libsrc--finish gav 'error "unzip failed"))
         ;; Inherits the daemon-wide GTAGSCONF / GTAGSLABEL=java-pygments.
         (fenrir/libsrc--run
          "gtags" '("gtags") tmp
          (lambda (exit _)
            (if (not (and (eq exit 0)
                          (if (fboundp 'fenrir/gtags--index-valid-p)
                              (fenrir/gtags--index-valid-p tmp)
                            (file-exists-p (expand-file-name "GTAGS" tmp)))))
                (progn (fenrir/libsrc--remove-tree tmp)
                       (fenrir/libsrc--finish gav 'error "gtags failed or empty index"))
              ;; Contents read-only, the top dir stays writable for `.ok'.
              (call-process "find" nil nil nil (directory-file-name tmp)
                            "-mindepth" "1" "-exec" "chmod" "a-w" "{}" "+")
              (rename-file (directory-file-name tmp) (directory-file-name final))
              (with-temp-file (expand-file-name ".ok" final))
              (fenrir/libsrc--finish gav 'ok)))))))))

;; --- 4. The M-. hook -------------------------------------------------------------

(defvar-local fenrir/libsrc-origin nil
  "Build root a library buffer was reached from; its classpath keeps applying.")

(defvar fenrir/libsrc--last-origin nil
  "Origin of the last library hit, handed to the buffer by `xref-after-jump-hook'.")

(defun fenrir/libsrc--origin-root ()
  "Build root whose classpath applies to the current buffer, or nil."
  (or fenrir/libsrc-origin
      (and default-directory (fenrir/libsrc--build-root default-directory))))

(defun fenrir/libsrc--query (dirs symbol)
  "Definitions of SYMBOL in the ready trees among DIRS."
  (when-let* ((ready (seq-filter #'fenrir/libsrc--ready-p dirs)))
    ;; Run from inside the first tree, the rest on GTAGSLIBPATH: the query
    ;; then needs no project index of its own.
    (let ((default-directory (car ready))
          (process-environment
           (cons (concat "GTAGSLIBPATH="
                         (or (fenrir/libsrc--libpath-string (cdr ready)) ""))
                 process-environment)))
      (with-temp-buffer
        (when (eq 0 (call-process "global" nil '(t nil) nil
                                  "-d" "--result=cscope" "--path-style=absolute"
                                  "--color=never" "--" symbol))
          (fenrir/libsrc--parse-hits (buffer-string)))))))

(defun fenrir/libsrc--rejump (buf pos symbol)
  "Re-run `xref-find-definitions' for SYMBOL if point is still at POS in BUF."
  (when (and (buffer-live-p buf)
             (eq (window-buffer (selected-window)) buf)
             (= (window-point (selected-window)) pos))
    (with-current-buffer buf
      (condition-case err (xref-find-definitions symbol)
        (user-error (message "%s" (error-message-string err)))))))

(defun fenrir/libsrc--add-libpath (root dir)
  "Record tree DIR as used by ROOT (keeps it out of `fenrir/libsrc-gc')."
  (let ((lp (plist-get (fenrir/libsrc--state root) :libpath)))
    (unless (member dir lp)
      (fenrir/libsrc--state-update root :libpath (cons dir lp)))))

(defun fenrir/libsrc-definitions (symbol)
  "Library definitions of SYMBOL for the current buffer's build root.
Ready trees answer directly.  A class whose artifact is not indexed yet is
queued and this signals a `user-error' (so the message is what the user
sees); when the build lands, `M-.' re-runs itself if point has not moved.
A symbol outside the class index (a method, a field) is a plain miss.
Only a root already synced with `fenrir/libsrc-sync' is ever resolved:
resolution executes the project's build code."
  (when-let* ((root (fenrir/libsrc--origin-root)))
    (let* ((st (fenrir/libsrc--state root))
           (gavs (and st (gethash symbol (plist-get st :class-index))))
           (ready (seq-filter #'fenrir/libsrc--ready-p
                              (mapcar #'fenrir/libsrc--gav-dir gavs)))
           (no-src-p (lambda (g) (file-exists-p (fenrir/libsrc--no-sources-file g))))
           (resume (let ((buf (current-buffer)) (pos (point)))
                     (lambda () (fenrir/libsrc--rejump buf pos symbol)))))
      (when (and st (> (fenrir/libsrc--build-mtime root)
                       (or (plist-get st :classpath-mtime) 0)))
        (fenrir/libsrc--resolve root))     ; build file changed: refresh quietly
      (if-let* ((hits (fenrir/libsrc--query
                       (append (or ready (plist-get st :libpath))
                               (fenrir/libsrc--jdk-dirs))
                       symbol)))
          (progn
            (dolist (d ready) (fenrir/libsrc--add-libpath root d))
            (setq fenrir/libsrc--last-origin root)
            hits)
        (if (null st)
            ;; Never resolve on our own in a root the user has not synced:
            ;; resolving runs the project's own gradlew / build scripts /
            ;; Maven plugins, i.e. the repo's code.  `C-c g l' is the opt-in;
            ;; once it has run, the state file marks the root as trusted and
            ;; later refreshes (the stale-mtime one above) are automatic.
            (user-error "No definitions for %s; library sources are off for %s -- \
%s runs its build tool once to enable them"
                        symbol (abbreviate-file-name root)
                        (substitute-command-keys "\\[fenrir/libsrc-sync]"))
          (let ((pending (seq-remove
                          (lambda (g) (or (fenrir/libsrc--ready-p (fenrir/libsrc--gav-dir g))
                                          (funcall no-src-p g)))
                          gavs)))
            (cond
             (pending
              (let ((left (length pending)))
                (dolist (g pending)
                  (fenrir/libsrc-ensure
                   g (lambda (result)
                       (if (eq result 'ok)
                           (fenrir/libsrc--add-libpath root (fenrir/libsrc--gav-dir g))
                         (message "libsrc: %s -- %s (see *libsrc*)" g result))
                       (when (zerop (cl-decf left))
                         (funcall resume))))))
              (user-error "libsrc: indexing %s for %s -- will jump when ready"
                          (mapconcat (lambda (g) (string-join (cdr (split-string g ":")) "-"))
                                     pending ", ")
                          symbol))
             ((seq-some no-src-p gavs)
              (message "libsrc: no sources published for %s (%s)"
                       symbol (string-join gavs ", "))
              nil))))))))

(with-eval-after-load 'gtags-mode
  (cl-defmethod xref-backend-definitions :around ((_backend (head :gtagsroot)) symbol)
    "After a project miss, look SYMBOL up in Java library sources."
    (or (cl-call-next-method)
        (and (stringp symbol)
             (derived-mode-p 'java-mode 'java-ts-mode)
             (fenrir/libsrc-definitions symbol)))))

;; --- 5. Library buffers ---------------------------------------------------------

(defun fenrir/libsrc--library-file-p (file)
  "Non-nil when FILE lives in the library-source cache."
  (and file (file-in-directory-p file (expand-file-name "lib" fenrir/libsrc-cache-dir))))

(defun fenrir/libsrc--find-file-hook ()
  "Library sources are references, not workspaces: open them read-only."
  (when (fenrir/libsrc--library-file-p buffer-file-name)
    (read-only-mode 1)))
(add-hook 'find-file-hook #'fenrir/libsrc--find-file-hook)

(defun fenrir/libsrc--after-jump ()
  "Remember which project's classpath brought us into this library buffer."
  (when (and fenrir/libsrc--last-origin
             (fenrir/libsrc--library-file-p buffer-file-name))
    (setq fenrir/libsrc-origin fenrir/libsrc--last-origin)))
(add-hook 'xref-after-jump-hook #'fenrir/libsrc--after-jump)

;; --- 6. Commands ------------------------------------------------------------------

(defun fenrir/libsrc-sync (&optional force)
  "Resolve the current build root's classpath and class index.
Reuses the cache unless the build file changed; FORCE (\\[universal-argument])
re-resolves."
  (interactive "P")
  (let ((root (or (fenrir/libsrc--origin-root)
                  (user-error "libsrc: no pom.xml / Gradle build above %s"
                              default-directory))))
    (let ((st (fenrir/libsrc--state root)))
      (if (and st (not force)
               (<= (fenrir/libsrc--build-mtime root)
                   (or (plist-get st :classpath-mtime) 0)))
          (message "libsrc: %s is current (%d classes); C-u to re-resolve"
                   (abbreviate-file-name root)
                   (hash-table-count (plist-get st :class-index)))
        (fenrir/libsrc--resolve root)))))

(defun fenrir/libsrc--dir-size (dir)
  "Human-readable disk usage of DIR."
  (if (file-directory-p dir)
      (with-temp-buffer
        (call-process "du" nil t nil "-sh" (directory-file-name dir))
        (car (split-string (buffer-string))))
    "0"))

(defun fenrir/libsrc-status ()
  "Show the library-source state of the current build root."
  (interactive)
  (let* ((root (fenrir/libsrc--origin-root))
         (st (and root (fenrir/libsrc--state root))))
    (with-current-buffer (get-buffer-create "*libsrc-status*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Build root: %s\n" (if root (abbreviate-file-name root) "none")))
        (if (not st)
            (insert "\nNo classpath yet -- C-c g l resolves it.\n")
          (let* ((jars (plist-get st :jars))
                 (gavs (delete-dups
                        (delq nil (mapcar (lambda (j) (when-let* ((g (fenrir/libsrc--jar-gav j)))
                                                        (fenrir/libsrc--gav-string g)))
                                          jars))))
                 (ready (seq-filter (lambda (g) (fenrir/libsrc--ready-p (fenrir/libsrc--gav-dir g))) gavs))
                 (nosrc (seq-filter (lambda (g) (file-exists-p (fenrir/libsrc--no-sources-file g))) gavs)))
            (insert (format "Classpath:  %d jars, %d classes (resolved %s)\n"
                            (length jars) (hash-table-count (plist-get st :class-index))
                            (format-time-string "%F %T" (plist-get st :classpath-mtime))))
            (insert (format "Indexed:    %d   Pending: %d   No sources: %d   Unparseable: %d\n"
                            (length ready) (hash-table-count fenrir/libsrc--jobs)
                            (length nosrc) (length (plist-get st :unparsed))))
            (insert (format "Cache:      %s in %s\n\n"
                            (fenrir/libsrc--dir-size fenrir/libsrc-cache-dir)
                            (abbreviate-file-name fenrir/libsrc-cache-dir)))
            (dolist (g ready) (insert "  [indexed]    " g "\n"))
            (dolist (g nosrc) (insert "  [no-sources] " g "\n"))
            (dolist (j (plist-get st :unparsed))
              (insert "  [no GAV]     " (abbreviate-file-name j) "\n"))))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

(defun fenrir/libsrc-gc ()
  "Delete library trees no project references and untouched for `fenrir/libsrc-gc-days'.
Also removes leftover `.tmp' build directories."
  (interactive)
  (let* ((proj (expand-file-name "proj" fenrir/libsrc-cache-dir))
         (used (cl-loop for f in (and (file-directory-p proj)
                                      (directory-files proj t "\\.eld\\'"))
                        append (plist-get (ignore-errors
                                            (with-temp-buffer
                                              (insert-file-contents f)
                                              (read (current-buffer))))
                                          :libpath)))
         (cutoff (- (float-time) (* 86400 fenrir/libsrc-gc-days)))
         (lib (expand-file-name "lib" fenrir/libsrc-cache-dir))
         (n 0))
    (dolist (tmp (fenrir/libsrc--stale-tmp-dirs))
      (unless (> (hash-table-count fenrir/libsrc--jobs) 0)
        (fenrir/libsrc--remove-tree tmp) (cl-incf n)))
    (when (file-directory-p lib)
      (dolist (ok (directory-files-recursively lib "\\`\\.ok\\'" nil nil t))
        (let ((dir (file-name-directory ok)))
          (unless (or (member dir used)
                      (string-prefix-p (expand-file-name "jdk/" lib) dir)
                      (> (float-time (file-attribute-modification-time (file-attributes ok)))
                         cutoff))
            (fenrir/libsrc--remove-tree dir) (cl-incf n)))))
    (message "libsrc: removed %d tree%s" n (if (= n 1) "" "s"))))

(defun fenrir/libsrc-index-jdk ()
  "Extract and index the JDK's lib/src.zip, for `java.*' / `javax.*' classes.
The tree is shared by every project using the same JDK version."
  (interactive)
  (let* ((home (or (getenv "JAVA_HOME")
                   (when-let* ((java (executable-find "java")))
                     (file-name-directory
                      (directory-file-name (file-name-directory (file-truename java)))))
                   (user-error "libsrc: no JDK found")))
         (src (expand-file-name "lib/src.zip" home))
         (release (expand-file-name "release" home))
         (version (or (and (file-readable-p release)
                           (with-temp-buffer
                             (insert-file-contents release)
                             (and (re-search-forward "^JAVA_VERSION=\"\\([^\"]+\\)\"" nil t)
                                  (match-string 1))))
                      (user-error "libsrc: no `release' file in %s" home))))
    (unless (file-exists-p src) (user-error "libsrc: %s has no src.zip" home))
    ;; Same pipeline as a Maven artifact, keyed under a pseudo-GAV; every
    ;; library query appends the ready JDK trees (`fenrir/libsrc--jdk-dirs').
    (puthash (concat "jdk:jdk:" version) src fenrir/libsrc--local-sources)
    (fenrir/libsrc-ensure (concat "jdk:jdk:" version)
                          (lambda (r) (message "libsrc: JDK %s -- %s" version r)))
    (message "libsrc: indexing JDK %s sources (a few minutes)..." version)))

(defun fenrir/libsrc--jdk-dirs ()
  "Ready JDK trees."
  (let ((dir (expand-file-name "lib/jdk/jdk/" fenrir/libsrc-cache-dir)))
    (when (file-directory-p dir)
      (seq-filter #'fenrir/libsrc--ready-p
                  (mapcar #'file-name-as-directory
                          (directory-files dir t "\\`[^.]" t))))))

(when (boundp 'fenrir/gtags-map)
  (keymap-set fenrir/gtags-map "l" #'fenrir/libsrc-sync)
  (keymap-set fenrir/gtags-map "L" #'fenrir/libsrc-status))

(provide 'init-libsrc)
;;; init-libsrc.el ends here
