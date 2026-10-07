;;; libsrc-test.el --- ERT for lisp/languages/init-libsrc.el's pure layer -*- lexical-binding: t; -*-

;; emacs -Q --batch -l test/libsrc-test.el -f ert-run-tests-batch-and-exit
;;
;; Loads only init-libsrc (no package system, no gtags-mode): the `:around'
;; method is registered `with-eval-after-load', so it stays dormant here.

(require 'ert)
(add-to-list 'load-path
             (expand-file-name "../lisp/languages" (file-name-directory
                                          (or load-file-name buffer-file-name))))
(require 'init-libsrc)

(defmacro libsrc-test--with-cache (&rest body)
  "Run BODY with `fenrir/libsrc-cache-dir' bound to a fresh temp dir."
  (declare (indent 0))
  `(let* ((fenrir/libsrc-cache-dir (file-name-as-directory (make-temp-file "libsrc" t)))
          (fenrir/libsrc--projects (make-hash-table :test #'equal)))
     (unwind-protect (progn ,@body)
       (fenrir/libsrc--remove-tree fenrir/libsrc-cache-dir))))

;; --- GAV from a jar path ---------------------------------------------------------

(ert-deftest libsrc-gav-m2 ()
  (should (equal (fenrir/libsrc--jar-gav
                  "/home/u/.m2/repository/org/springframework/boot/spring-boot/3.0.2/spring-boot-3.0.2.jar")
                 "org.springframework.boot:spring-boot:3.0.2")))

(ert-deftest libsrc-gav-gradle ()
  (should (equal (fenrir/libsrc--jar-gav
                  "/home/u/.gradle/caches/modules-2/files-2.1/org.springframework.boot/spring-boot/3.2.2/9f274d1bd822c4c57bb5b37ecae2380b980f567/spring-boot-3.2.2.jar")
                 "org.springframework.boot:spring-boot:3.2.2")))

(ert-deftest libsrc-gav-unparseable ()
  ;; classifier jar, project build output, random path
  (should-not (fenrir/libsrc--jar-gav
               "/home/u/.m2/repository/io/netty/netty-x/4.1/netty-x-4.1-linux-x86_64.jar"))
  (should-not (fenrir/libsrc--jar-gav "/work/app/build/libs/app-1.0.jar"))
  (should-not (fenrir/libsrc--jar-gav "/work/app/target/classes")))

(ert-deftest libsrc-gav-dir ()
  (let ((fenrir/libsrc-cache-dir "/c/"))
    (should (equal (fenrir/libsrc--gav-dir "org.x:a:1.0") "/c/lib/org.x/a/1.0/"))
    ;; the JDK pseudo-GAV goes through the same path
    (should (equal (fenrir/libsrc--gav-dir "jdk:jdk:21.0.9") "/c/lib/jdk/jdk/21.0.9/"))))

(ert-deftest libsrc-gav-parts-and-label ()
  (should (equal (fenrir/libsrc--gav-parts "org.x:a:1.0") '("org.x" "a" "1.0")))
  (should (equal (fenrir/libsrc--gav-label "org.springframework.boot:spring-boot:3.0.2")
                 "spring-boot-3.0.2"))
  (should (equal (fenrir/libsrc--gav-label "jdk:jdk:21.0.9") "jdk-21.0.9")))

;; --- Class index -----------------------------------------------------------------

(ert-deftest libsrc-class-entry-name ()
  (should (equal (fenrir/libsrc--class-entry-name
                  "org/springframework/boot/info/GitProperties.class")
                 "GitProperties"))
  (should (equal (fenrir/libsrc--class-entry-name
                  "org/springframework/boot/info/InfoProperties$Entry.class")
                 "InfoProperties"))
  (should (equal (fenrir/libsrc--class-entry-name "a/Outer$1.class") "Outer"))
  (should (equal (fenrir/libsrc--class-entry-name "Top.class") "Top"))
  (should-not (fenrir/libsrc--class-entry-name "module-info.class"))
  (should-not (fenrir/libsrc--class-entry-name "META-INF/versions/9/module-info.class"))
  (should-not (fenrir/libsrc--class-entry-name "org/x/package-info.class"))
  (should-not (fenrir/libsrc--class-entry-name "org/x/"))
  (should-not (fenrir/libsrc--class-entry-name "META-INF/MANIFEST.MF")))

(ert-deftest libsrc-listing-and-index ()
  (let* ((m2 "/h/.m2/repository/org/x/a/1.0/a-1.0.jar")
         (m2b "/h/.m2/repository/org/y/b/2.0/b-2.0.jar")
         (out (concat "@@" m2 "\n"
                      "org/x/Foo.class\norg/x/Foo$Inner.class\norg/x/\nmodule-info.class\n"
                      "@@" m2b "\n"
                      "org/y/Foo.class\norg/y/Bar.class\n"
                      "@@/work/target/classes\nWhatever.class\n"))
         (listing (fenrir/libsrc--parse-listing out))
         (index (fenrir/libsrc--build-class-index listing)))
    (should (equal (assoc m2 listing) (list m2 "Foo")))
    (should (= (length listing) 3))
    (should (equal (gethash "Foo" index) '("org.x:a:1.0" "org.y:b:2.0")))
    (should (equal (gethash "Bar" index) '("org.y:b:2.0")))
    (should-not (gethash "Inner" index))
    (should-not (gethash "Whatever" index))   ; no GAV -> skipped
    (should-not (gethash "module-info" index))))

;; --- Classpath output parsing ------------------------------------------------------

(ert-deftest libsrc-parse-maven-classpath ()
  (should (equal (fenrir/libsrc--parse-maven-classpath
                  "/r/a-1.jar:/r/b-1.jar:/work/target/classes\n/r/a-1.jar:/r/c-1.jar\n")
                 '("/r/a-1.jar" "/r/b-1.jar" "/r/c-1.jar"))))

(ert-deftest libsrc-parse-gradle-output ()
  (should (equal (fenrir/libsrc--parse-gradle-output
                  "Starting a Gradle Daemon\nFENRIR-LIBSRC-JAR /g/a-1.jar\nFENRIR-LIBSRC-JAR /work/sub/build/classes/java/main\nFENRIR-LIBSRC-JAR /g/b-1.jar\nFENRIR-LIBSRC-JAR /g/a-1.jar\n")
                 '("/g/a-1.jar" "/g/b-1.jar"))))

(ert-deftest libsrc-parse-hits ()
  (let ((items (fenrir/libsrc--parse-hits
                "/c/lib/org/x/a/1/org/x/GitProperties.java GitProperties 36 public class GitProperties extends InfoProperties {\n")))
    (should (= (length items) 1))
    (let ((loc (xref-item-location (car items))))
      (should (equal (xref-file-location-file loc) "/c/lib/org/x/a/1/org/x/GitProperties.java"))
      (should (= (xref-file-location-line loc) 36)))
    (should (equal (xref-item-summary (car items))
                   "public class GitProperties extends InfoProperties {"))))

;; --- GTAGSLIBPATH assembly -------------------------------------------------------

(ert-deftest libsrc-libpath-string ()
  (libsrc-test--with-cache
    (let ((a (fenrir/libsrc--gav-dir "g:a:1"))
          (b (fenrir/libsrc--gav-dir "g:b:1"))
          (c (fenrir/libsrc--gav-dir "g:c:1")))
      (dolist (d (list a b c)) (make-directory d t))
      (should-not (fenrir/libsrc--libpath-string (list a b c)))   ; none ready
      (with-temp-file (expand-file-name ".ok" a))
      (with-temp-file (expand-file-name ".ok" c))
      (should (equal (fenrir/libsrc--libpath-string (list a b c))
                     (concat (directory-file-name a) ":" (directory-file-name c)))))))

;; --- State round-trip --------------------------------------------------------------

(ert-deftest libsrc-state-roundtrip ()
  (libsrc-test--with-cache
    (let ((index (make-hash-table :test #'equal))
          (root "/work/proj/"))
      (puthash "GitProperties" '("org.springframework.boot:spring-boot:3.0.2") index)
      (fenrir/libsrc--state-update root :jars '("/r/a.jar") :class-index index
                                   :classpath-mtime 123.5)
      (clrhash fenrir/libsrc--projects)       ; force the disk path
      (let ((st (fenrir/libsrc--state root)))
        (should (equal (plist-get st :root) root))
        (should (equal (plist-get st :jars) '("/r/a.jar")))
        (should (equal (plist-get st :classpath-mtime) 123.5))
        (should (equal (gethash "GitProperties" (plist-get st :class-index))
                       '("org.springframework.boot:spring-boot:3.0.2")))))))

;; --- .tmp cleanup ----------------------------------------------------------------

(ert-deftest libsrc-tmp-cleanup ()
  (libsrc-test--with-cache
    (let* ((final (fenrir/libsrc--gav-dir "g:a:1"))
           (tmp (concat (directory-file-name final) ".tmp/"))
           (sub (expand-file-name "org/x/" tmp)))
      (make-directory sub t)
      (with-temp-file (expand-file-name "Foo.java" sub))
      ;; Read-only like a published tree: plain delete-directory would fail.
      (call-process "chmod" nil nil nil "-R" "a-w" (directory-file-name sub))
      (should (equal (fenrir/libsrc--stale-tmp-dirs) (list (directory-file-name tmp))))
      (fenrir/libsrc--remove-tree tmp)
      (should-not (file-exists-p tmp))
      (should-not (fenrir/libsrc--stale-tmp-dirs)))))

;; --- Build root ------------------------------------------------------------------

(ert-deftest libsrc-build-root-deepest ()
  (libsrc-test--with-cache
    (let* ((top fenrir/libsrc-cache-dir)
           (mod (expand-file-name "mod/" top))
           (src (expand-file-name "src/main/java/" mod)))
      (make-directory src t)
      (with-temp-file (expand-file-name "settings.gradle.kts" top))
      (should (equal (fenrir/libsrc--build-root src) top))
      (with-temp-file (expand-file-name "pom.xml" mod))
      (should (equal (fenrir/libsrc--build-root src) mod)))))

;; --- Opt-in: never resolve an unsynced root -------------------------------------
;; Resolving runs the project's own gradlew / build scripts, so a miss in a
;; root without state must refuse rather than start a resolution.

(ert-deftest libsrc-unsynced-root-does-not-resolve ()
  (libsrc-test--with-cache
    (let* ((proj (file-name-as-directory (expand-file-name "proj" fenrir/libsrc-cache-dir)))
           (default-directory proj)
           (resolved nil))
      (make-directory proj t)
      (with-temp-file (expand-file-name "pom.xml" proj))
      (cl-letf (((symbol-function 'fenrir/libsrc--resolve)
                 (lambda (&rest args) (push args resolved))))
        (let ((err (should-error (fenrir/libsrc-definitions "GitProperties")
                                 :type 'user-error)))
          (should (string-match-p "library sources are off" (cadr err))))
        (should-not resolved)
        ;; Once synced (state exists), the same miss no longer refuses.
        (fenrir/libsrc--state-update proj :class-index (make-hash-table :test #'equal)
                                     :classpath-mtime (float-time))
        (should-not (fenrir/libsrc-definitions "GitProperties"))
        (should-not resolved)))))

;; --- Failures release what they hold ------------------------------------------
;; A step that cannot start (program missing from the daemon's exec-path) or
;; a callback that signals must not leave a resolving entry or a build slot
;; behind -- otherwise every later lookup waits forever.

(defmacro libsrc-test--with-queue (&rest body)
  "Run BODY with fresh build-queue and resolution state."
  (declare (indent 0))
  `(let ((fenrir/libsrc--jobs (make-hash-table :test #'equal))
         (fenrir/libsrc--resolving (make-hash-table :test #'equal))
         (fenrir/libsrc--queue nil)
         (fenrir/libsrc--running 0)
         (inhibit-message t))
     ,@body))

(ert-deftest libsrc-resolve-missing-program-releases-entry ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let ((proj (file-name-as-directory (expand-file-name "proj" fenrir/libsrc-cache-dir)))
            (exec-path nil))                ; mvn cannot be found
        (make-directory proj t)
        (with-temp-file (expand-file-name "pom.xml" proj))
        (fenrir/libsrc--resolve proj)       ; must not signal
        (should (zerop (hash-table-count fenrir/libsrc--resolving)))))))

(ert-deftest libsrc-build-missing-program-releases-slot ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let ((exec-path nil) (got nil))      ; no local sources jar -> mvn fetch
        (cl-letf (((symbol-function 'fenrir/libsrc--find-sources-jar) #'ignore))
          (fenrir/libsrc-ensure "g:a:1" (lambda (r) (push r got))))
        (should (equal got '(error)))
        (should (zerop fenrir/libsrc--running))
        (should (zerop (hash-table-count fenrir/libsrc--jobs)))))))

(ert-deftest libsrc-build-sync-error-releases-slot-and-pumps ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let ((fenrir/libsrc-max-jobs 1) (got nil))
        (cl-letf (((symbol-function 'fenrir/libsrc--find-sources-jar) (lambda (_) "/x.jar"))
                  ((symbol-function 'fenrir/libsrc--extract)
                   (lambda (&rest _) (error "Disk full"))))
          ;; With one slot, the second build only starts if the first released it.
          (fenrir/libsrc-ensure "g:a:1" (lambda (r) (push (cons "a" r) got)))
          (fenrir/libsrc-ensure "g:b:1" (lambda (r) (push (cons "b" r) got))))
        (should (equal (reverse got) '(("a" . error) ("b" . error))))
        (should (zerop fenrir/libsrc--running))
        (should-not fenrir/libsrc--queue)))))

(ert-deftest libsrc-run-callback-error-goes-to-on-error ()
  (let ((msg nil) (inhibit-message t))
    (fenrir/libsrc--run "t" '("true") temporary-file-directory
                        (lambda (&rest _) (error "Boom"))
                        (lambda (m) (setq msg m)))
    (let ((end (+ (float-time) 10)))
      (while (and (not msg) (< (float-time) end))
        (accept-process-output nil 0.1)))
    (should (equal msg "Boom"))))

;; --- Re-jump only after a successful build ---------------------------------------
;; A failed build used to re-run M-., which re-queued the still-pending GAV,
;; failed again, and looped for as long as point stayed put.

(defun libsrc-test--definitions-with-result (result)
  "Run a lazy-path miss whose build ends with RESULT; return re-jump count."
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let* ((proj (file-name-as-directory (expand-file-name "proj" fenrir/libsrc-cache-dir)))
             (default-directory proj)
             (index (make-hash-table :test #'equal))
             (rejumps 0))
        (make-directory proj t)
        (with-temp-file (expand-file-name "pom.xml" proj))
        (puthash "GitProperties" '("org.x:a:1") index)
        (fenrir/libsrc--state-update proj :class-index index :classpath-mtime (float-time))
        (cl-letf (((symbol-function 'fenrir/libsrc-ensure)
                   (lambda (_gav cb) (funcall cb result)))   ; build "finishes" at once
                  ((symbol-function 'fenrir/libsrc--rejump)
                   (lambda (&rest _) (cl-incf rejumps))))
          (should-error (fenrir/libsrc-definitions "GitProperties") :type 'user-error))
        rejumps))))

(ert-deftest libsrc-no-rejump-after-failed-build ()
  (should (= 0 (libsrc-test--definitions-with-result 'error)))
  (should (= 0 (libsrc-test--definitions-with-result 'no-sources))))

(ert-deftest libsrc-rejump-after-successful-build ()
  (should (= 1 (libsrc-test--definitions-with-result 'ok))))

;; --- A3: an unzip that lists nothing must not store an empty index ------------

(ert-deftest libsrc-listing-failures ()
  (let ((out "@@/r/a-1.jar\norg/x/Foo.class\n@@/r/b-1.jar\n!!/r/b-1.jar\n"))
    (should (equal (fenrir/libsrc--listing-failures out) '("/r/b-1.jar")))
    ;; the failure marker is not a class entry
    (should (equal (fenrir/libsrc--parse-listing out)
                   '(("/r/a-1.jar" "Foo") ("/r/b-1.jar"))))))

(defun libsrc-test--index-with-output (jars output)
  "Run `--index-classes' for JARS with the listing process faked to OUTPUT.
Returns (STATE . STILL-RESOLVING-P)."
  (let ((proj (file-name-as-directory (expand-file-name "proj" fenrir/libsrc-cache-dir))))
    (make-directory proj t)
    (puthash proj nil fenrir/libsrc--resolving)
    (cl-letf (((symbol-function 'fenrir/libsrc--run)
               (lambda (_name _cmd _dir cb _on-error) (funcall cb 0 output))))
      (fenrir/libsrc--index-classes proj jars 100.0))
    (cons (fenrir/libsrc--state proj)
          (not (eq (gethash proj fenrir/libsrc--resolving 'none) 'none)))))

(ert-deftest libsrc-index-all-jars-unreadable-stores-nothing ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let* ((a "/h/.m2/repository/org/x/a/1/a-1.jar")
             (b "/h/.m2/repository/org/x/b/1/b-1.jar")
             (res (libsrc-test--index-with-output
                   (list a b) (concat "@@" a "\n!!" a "\n@@" b "\n!!" b "\n"))))
        (should-not (car res))          ; no state -> not "current (0 classes)"
        (should-not (cdr res))))))      ; resolving entry released

(ert-deftest libsrc-index-some-jars-unreadable-records-them ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let* ((a "/h/.m2/repository/org/x/a/1/a-1.jar")
             (b "/h/.m2/repository/org/x/b/1/b-1.jar")
             (st (car (libsrc-test--index-with-output
                       (list a b)
                       (concat "@@" a "\norg/x/Foo.class\n@@" b "\n!!" b "\n")))))
        (should (equal (plist-get st :unreadable) (list b)))
        (should (equal (gethash "Foo" (plist-get st :class-index)) '("org.x:a:1")))
        (should (equal (plist-get st :resolved-at) 100.0))))))

;; --- A5: staleness covers subproject build files and parent poms -----------------

(defun libsrc-test--touch (file &optional time)
  "Create FILE (and its directory) with mtime TIME (float, default now)."
  (make-directory (file-name-directory file) t)
  (with-temp-file file)
  (when time (set-file-times file (seconds-to-time time))))

(ert-deftest libsrc-build-files-gradle ()
  (libsrc-test--with-cache
    (let ((root (file-name-as-directory (expand-file-name "gr" fenrir/libsrc-cache-dir))))
      (dolist (f '("settings.gradle.kts" "build.gradle.kts" "sub/build.gradle.kts"
                   "gradle/libs.versions.toml" "build/tmp/build.gradle"
                   "sub/src/main/resources/pom.xml"))
        (libsrc-test--touch (expand-file-name f root)))
      (should (equal (sort (mapcar (lambda (f) (file-relative-name f root))
                                   (fenrir/libsrc--build-files root))
                           #'string<)
                     '("build.gradle.kts" "gradle/libs.versions.toml"
                       "settings.gradle.kts" "sub/build.gradle.kts"))))))

(ert-deftest libsrc-build-files-maven-parents ()
  (libsrc-test--with-cache
    (let* ((parent (file-name-as-directory (expand-file-name "rx" fenrir/libsrc-cache-dir)))
           (mod (file-name-as-directory (expand-file-name "mod" parent))))
      (libsrc-test--touch (expand-file-name "pom.xml" parent))
      (libsrc-test--touch (expand-file-name "pom.xml" mod))
      (let ((files (fenrir/libsrc--build-files mod)))
        (should (member (expand-file-name "pom.xml" mod) files))
        (should (member (expand-file-name "pom.xml" parent) files))))))

(ert-deftest libsrc-stale-on-subproject-edit ()
  (libsrc-test--with-cache
    (let* ((root (file-name-as-directory (expand-file-name "gr" fenrir/libsrc-cache-dir)))
           (sub (expand-file-name "sub/build.gradle.kts" root))
           (old (- (float-time) 1000)))
      (libsrc-test--touch (expand-file-name "settings.gradle.kts" root) old)
      (libsrc-test--touch sub old)
      (let ((st (list :resolved-at (- (float-time) 500)
                      :build-files (fenrir/libsrc--build-files root))))
        (should-not (fenrir/libsrc--stale-p root st))
        (set-file-times sub)                      ; edited now, after resolution
        (should (fenrir/libsrc--stale-p root st))))))

;; --- A6: the status buffer reports this root, with the real resolve time ---------

(ert-deftest libsrc-status-pending-and-resolved-time ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let* ((proj (file-name-as-directory (expand-file-name "proj" fenrir/libsrc-cache-dir)))
             (default-directory proj)
             (at (encode-time '(0 30 9 1 2 2026 nil nil 0))))
        (libsrc-test--touch (expand-file-name "pom.xml" proj))
        (fenrir/libsrc--state-update
         proj :resolved-at (float-time at) :class-index (make-hash-table :test #'equal)
         :jars '("/h/.m2/repository/org/x/a/1/a-1.jar" "/h/.m2/repository/org/x/b/1/b-1.jar"))
        (puthash "org.x:a:1" (list #'ignore) fenrir/libsrc--jobs)       ; this root
        (puthash "org.other:z:9" (list #'ignore) fenrir/libsrc--jobs)   ; another project
        (fenrir/libsrc-status)
        (with-current-buffer "*libsrc-status*"
          (should (string-match-p "Pending: 1 " (buffer-string)))
          (should (string-match-p "\\[pending\\] +org\\.x:a:1" (buffer-string)))
          (should (string-match-p (regexp-quote (format-time-string "resolved %F %T" at))
                                  (buffer-string))))))))

;; --- A4: a no-sources class says so instead of being overwritten -----------------

(ert-deftest libsrc-no-sources-is-a-user-error ()
  (libsrc-test--with-cache
    (libsrc-test--with-queue
      (let* ((proj (file-name-as-directory (expand-file-name "proj" fenrir/libsrc-cache-dir)))
             (default-directory proj)
             (index (make-hash-table :test #'equal)))
        (libsrc-test--touch (expand-file-name "pom.xml" proj) (- (float-time) 100))
        (puthash "Closed" '("org.x:closed:1") index)
        (fenrir/libsrc--state-update proj :class-index index :resolved-at (float-time))
        (libsrc-test--touch (fenrir/libsrc--no-sources-file "org.x:closed:1"))
        (let ((err (should-error (fenrir/libsrc-definitions "Closed") :type 'user-error)))
          (should (string-match-p "no sources published for org.x:closed:1" (cadr err))))))))

;; --- Callback errors are reported, not swallowed ---------------------------------

(ert-deftest libsrc-resolve-done-reports-callback-errors ()
  (libsrc-test--with-queue
    (let ((msgs nil) (ran nil))
      ;; Registration order: the failing callback first, then one that must still run.
      (puthash "/r/" (list (lambda () (push 'second ran))
                           (lambda () (error "Rejump broke")))
               fenrir/libsrc--resolving)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (fenrir/libsrc--resolve-done "/r/" t))
      (should (member "libsrc: Rejump broke" msgs))
      (should (equal ran '(second)))
      (should (eq (gethash "/r/" fenrir/libsrc--resolving 'none) 'none)))))

;; --- One Maven/Gradle decision: command and parser together -------------------

(ert-deftest libsrc-classpath-command-pairs-parser ()
  (libsrc-test--with-cache
    (let* ((mvn-root (file-name-as-directory (expand-file-name "m" fenrir/libsrc-cache-dir)))
           (gr-root (file-name-as-directory (expand-file-name "g" fenrir/libsrc-cache-dir)))
           (out (expand-file-name "cp.txt" fenrir/libsrc-cache-dir)))
      (libsrc-test--touch (expand-file-name "pom.xml" mvn-root))
      (libsrc-test--touch (expand-file-name "gradlew" gr-root))   ; no +x
      (let ((m (fenrir/libsrc--classpath-command mvn-root t out)))
        (should (equal (seq-take (car m) 4) '("mvn" "-q" "-B" "-o")))
        (with-temp-file out (insert "/r/a-1.jar:/r/b-1.jar"))
        ;; Maven's parser reads OUT-FILE, ignoring the process output
        (should (equal (funcall (cdr m) "noise") '("/r/a-1.jar" "/r/b-1.jar"))))
      (let ((g (fenrir/libsrc--classpath-command gr-root nil out)))
        (should (equal (seq-take (car g) 3) '("sh" "./gradlew" "-q")))
        (should-not (member "--offline" (car g)))
        (should (equal (funcall (cdr g) "chatter\nFENRIR-LIBSRC-JAR /g/a-1.jar\n")
                       '("/g/a-1.jar"))))
      (let ((exec-path nil))
        (should-not (fenrir/libsrc--classpath-command fenrir/libsrc-cache-dir t out))))))

;;; libsrc-test.el ends here
