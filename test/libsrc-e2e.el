;;; libsrc-e2e.el --- opt-in end-to-end check for lisp/init-libsrc.el -*- lexical-binding: t; -*-

;; NOT part of the ERT suite.  Needs network (Maven downloads -sources.jars
;; into the REAL ~/.m2) and a project copy that already has a GTAGS index --
;; run it on a scratch copy so no GTAGS lands in the real repo:
;;
;;   rsync -a --exclude target --exclude build --exclude .git <project> $TMP/
;;   (cd $TMP/<project> && GTAGSCONF=~/.emacs.d/gtags.conf GTAGSLABEL=java-pygments gtags)
;;   LIBSRC_CACHE=$TMP/cache/ JAVA_FILE=$TMP/<project>/src/.../GitInfoLogger.java \
;;     emacs -Q --batch -l test/libsrc-e2e.el
;;
;; LIBSRC_CACHE keeps the real ~/.cache/fenrir-libsrc untouched.  Prints each
;; step; a working run shows: 0th = "library sources are off" user-error
;; (no auto-resolve in an unsynced root), then after `fenrir/libsrc-sync':
;; 1st/2nd = "indexing <artifact>" user-error, 3rd = absolute paths into the cache,
;; a read-only library buffer with its origin set, a same-artifact hit, and a
;; cross-artifact class (spring-core's RuntimeHints) indexed via the origin.
;;
;; 2026-10-07 (Asia/Taipei), Emacs 30.1, GNU Global 6.6.13, mvn 3.9.12, JDK 21:
;; passed on copies of ig_lottery repos/ig/gfc-login-api (Maven, 131 jars,
;; 21,622 classes, spring-boot 3.0.2) and repos/lottery/kjw-web (Gradle via
;; `sh ./gradlew', 103 jars, 35,212 classes, spring-boot 3.2.2).

(setq package-user-dir (expand-file-name "~/.emacs.d/elpa/"))
(package-initialize)
(add-to-list 'load-path (expand-file-name "~/.emacs.d/lisp"))
(require 'use-package)
(require 'init-tags)
(require 'init-libsrc)
(setq fenrir/libsrc-cache-dir (getenv "LIBSRC_CACHE"))

(defun libsrc-e2e--wait (pred secs)
  "Pump process output until PRED holds or SECS pass."
  (let ((end (+ (float-time) secs)))
    (while (and (not (funcall pred)) (< (float-time) end))
      (accept-process-output nil 0.2))))

(defun libsrc-e2e--defs (sym)
  "Definition files for SYM in the current buffer, or the user-error."
  (condition-case err
      (mapcar (lambda (x) (xref-location-group (xref-item-location x)))
              (xref-backend-definitions (xref-find-backend) sym))
    (user-error (list 'user-error (error-message-string err)))))

(defun libsrc-e2e--drain ()
  "Wait for every resolution and artifact build to finish."
  (libsrc-e2e--wait (lambda () (and (zerop (hash-table-count fenrir/libsrc--resolving))
                                    (zerop (hash-table-count fenrir/libsrc--jobs))))
                    600))

(find-file (getenv "JAVA_FILE"))
(java-ts-mode)
(message "backend=%S" (car-safe (xref-find-backend)))
(message "0th (unsynced): %S" (libsrc-e2e--defs "GitProperties"))
(message "0th started a resolution? %S"
         (> (hash-table-count fenrir/libsrc--resolving) 0))
(fenrir/libsrc-sync)
(libsrc-e2e--drain)
(message "1st: %S" (libsrc-e2e--defs "GitProperties"))
(libsrc-e2e--drain)
(message "2nd: %S" (libsrc-e2e--defs "GitProperties"))
(libsrc-e2e--drain)
(message "3rd: %S" (libsrc-e2e--defs "GitProperties"))
(message "project class: %S" (libsrc-e2e--defs "GitInfoLogger"))
(message "unknown: %S" (libsrc-e2e--defs "noSuchThingAnywhere"))
(let ((lib (car (libsrc-e2e--defs "GitProperties"))))
  (with-current-buffer (find-file-noselect lib)
    (java-ts-mode)
    (setq fenrir/libsrc-origin fenrir/libsrc--last-origin)   ; what xref-after-jump-hook does
    (message "lib buffer read-only=%s origin=%s" buffer-read-only fenrir/libsrc-origin)
    (message "same artifact InfoProperties: %S" (libsrc-e2e--defs "InfoProperties"))
    (message "cross artifact RuntimeHints, 1st: %S" (libsrc-e2e--defs "RuntimeHints"))
    (libsrc-e2e--drain)
    (message "cross artifact RuntimeHints, 2nd: %S" (libsrc-e2e--defs "RuntimeHints"))))
(princ (with-current-buffer "*libsrc*" (buffer-string)))

;;; libsrc-e2e.el ends here
