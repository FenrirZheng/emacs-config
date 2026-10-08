;;; init-libsrc.el --- Java library sources for gtags M-. via GTAGSLIBPATH -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `M-.' on a library class such as `org.springframework.boot.info.GitProperties'
;; lands read-only in its source, with no JVM inside Emacs.  The engine --
;; classpath resolution, class index, per-artifact source trees, the lookup
;; itself -- is [`fenrir-libsrc.el'](fenrir-libsrc.el); this file only wires it
;; in.  Design and usage: [TAGS.md](../../_doc/TAGS.md#library-sources-fenrir-libsrc).
;;
;; Lives in `lisp/languages/' because it is Java-only, but `init.el' requires
;; it right after `init-tags' rather than with the other language modules: it
;; extends the gtags backend, not Eglot, and needs nothing from `init-java'.

;;; Code:

(require 'fenrir-libsrc)

;; From init-tags.el, absent in a bare batch run.
(defvar fenrir/gtags-map)

;; --- The M-. hook ------------------------------------------------------------
;; xref asks only the FIRST backend whose identifier function answers, and
;; gtags-mode claims every buffer under an indexed tree -- so a separate,
;; later backend would never be consulted.  Extend the gtags backend instead,
;; the same `:around' pattern init-tags.el uses for the `@' annotation retry:
;; project hits win; only a Java miss falls through to the library lookup.
;; `M-?' is left alone -- library hits would flood it.
(with-eval-after-load 'gtags-mode
  (cl-defmethod xref-backend-definitions :around ((_backend (head :gtagsroot)) symbol)
    "After a project miss, look SYMBOL up in Java library sources."
    (or (cl-call-next-method)
        (and (stringp symbol)
             (derived-mode-p 'java-mode 'java-ts-mode)
             (fenrir/libsrc-definitions symbol)))))

;; --- Library buffers ---------------------------------------------------------
;; Opened read-only, and tagged with the project they were reached from so a
;; further `M-.' into another artifact keeps using that project's classpath.
(add-hook 'find-file-hook #'fenrir/libsrc--find-file-hook)
(add-hook 'xref-after-jump-hook #'fenrir/libsrc--after-jump)

;; --- Keys --------------------------------------------------------------------
;; On init-tags' `C-c g' map; `fenrir/libsrc-index-all', `fenrir/libsrc-index-jdk'
;; and `fenrir/libsrc-gc' stay M-x only.
(when (boundp 'fenrir/gtags-map)
  (keymap-set fenrir/gtags-map "l" #'fenrir/libsrc-sync)
  (keymap-set fenrir/gtags-map "L" #'fenrir/libsrc-status))

(provide 'init-libsrc)
;;; init-libsrc.el ends here
