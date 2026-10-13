;;; check-equivalence.el --- 驗收條件 2: helper index == the old unzip pipeline -*- lexical-binding: t; -*-

;; emacs -Q --batch -l sliced-spec/2026-10-13/215104-libsrc-rust-class-lister/check-equivalence.el
;;
;; Run from the repo root.  Input: the `:jars' of kjw-web's state file (below).
;; Old side: a FROZEN copy of the engine's listing code as of commit ddf3059
;; (`sh' + `unzip -Z1' per jar, then the Elisp parse and index) -- frozen here
;; so deleting it from the engine does not delete the oracle.
;; New side: the engine's own class-index step, run against a throwaway cache
;; dir, so the real `~/.cache/fenrir-libsrc' state is never written.
;; Approved exception (SPEC 驗收條件 2, 2026-10-13): Debian `unzip -Z1' prints a
;; non-ASCII entry name with one `+' per UTF-8 byte (`λ.class' -> `++.class'),
;; so the old index holds that mangled key and the new one the real name.  Such
;; a pair -- same GAVs -- is accepted and listed; every other key must match.
;; Exit status 0 and "EQUIVALENT" on success; 1 and the first differences otherwise.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst eqv-state-file
  (expand-file-name "~/.cache/fenrir-libsrc/proj/0c3182fdef74a5edb107922b61083d9364653696.eld"))

;; --- Frozen copy (fenrir-libsrc.el @ ddf3059) ------------------------------------

(defun eqv-old-jar-gav (jar)
  (cond
   ((string-match "/files-2\\.1/\\([^/]+\\)/\\([^/]+\\)/\\([^/]+\\)/[^/]+/\\2-\\3\\.jar\\'"
                  jar)
    (string-join (list (match-string 1 jar) (match-string 2 jar) (match-string 3 jar)) ":"))
   ((string-match "/repository/\\(.+\\)/\\([^/]+\\)/\\([^/]+\\)/\\2-\\3\\.jar\\'" jar)
    (string-join (list (string-replace "/" "." (match-string 1 jar))
                       (match-string 2 jar) (match-string 3 jar))
                 ":"))))

(defun eqv-old-class-entry-name (entry)
  (when (string-match "\\([^/$]+\\)\\(?:\\$[^/]*\\)?\\.class\\'" entry)
    (let ((name (match-string 1 entry)))
      (unless (member name '("module-info" "package-info"))
        name))))

(defun eqv-old-parse-listing (string)
  (let (acc cur)
    (dolist (line (string-lines string t))
      (if (string-prefix-p "@@" line)
          (push (setq cur (list (substring line 2))) acc)
        (when-let* ((cur) (name (eqv-old-class-entry-name line)))
          (setcdr cur (cons name (cdr cur))))))
    (mapcar (lambda (c) (cons (car c) (delete-dups (cdr c)))) (nreverse acc))))

(defun eqv-old-listing-failures (string)
  (let (acc)
    (dolist (line (string-lines string t))
      (when (string-prefix-p "!!" line)
        (push (substring line 2) acc)))
    (nreverse acc)))

(defun eqv-old-build-class-index (listing)
  (let ((index (make-hash-table :test #'equal)))
    (pcase-dolist (`(,jar . ,names) listing)
      (when-let* ((g (eqv-old-jar-gav jar)))
        (dolist (n names)
          (unless (member g (gethash n index))
            (puthash n (append (gethash n index) (list g)) index)))))
    index))

(defun eqv-old (jars)
  "(INDEX UNREADABLE UNPARSED) the way the engine computed them at ddf3059."
  (let ((out (with-temp-buffer
               (apply #'call-process "sh" nil t nil "-c"
                      "for j; do printf '@@%s\\n' \"$j\"; unzip -Z1 \"$j\" 2>/dev/null || printf '!!%s\\n' \"$j\"; done"
                      "sh" jars)
               (buffer-string))))
    (list (eqv-old-build-class-index (eqv-old-parse-listing out))
          (eqv-old-listing-failures out)
          (seq-remove #'eqv-old-jar-gav jars))))

;; --- New side: the engine's own step ---------------------------------------------

(add-to-list 'load-path (expand-file-name "lisp/languages"))
(require 'fenrir-libsrc)

(defun eqv-new (root jars)
  "(INDEX UNREADABLE UNPARSED) from the engine's class-index step for ROOT."
  (let* ((fenrir/libsrc-cache-dir (file-name-as-directory (make-temp-file "eqv-libsrc" t)))
         (fenrir/libsrc--projects (make-hash-table :test #'equal))
         (fenrir/libsrc--resolving (make-hash-table :test #'equal))
         (deadline (+ (float-time) 60)))
    (unwind-protect
        (progn
          (puthash root nil fenrir/libsrc--resolving)
          (fenrir/libsrc--index-classes root jars (float-time))
          (while (and (not (eq (gethash root fenrir/libsrc--resolving 'none) 'none))
                      (< (float-time) deadline))
            (accept-process-output nil 0.05))
          (let ((st (fenrir/libsrc--state root)))
            (unless st (error "new step stored no state (see *libsrc*):\n%s"
                              (with-current-buffer (fenrir/libsrc--log-buffer)
                                (buffer-string))))
            (list (plist-get st :class-index) (plist-get st :unreadable)
                  (plist-get st :unparsed))))
      (fenrir/libsrc--remove-tree fenrir/libsrc-cache-dir))))

;; --- Compare ---------------------------------------------------------------------

(defun eqv-unzip-mangle (name)
  "NAME as Debian `unzip -Z1' prints it: one `+' per byte of each non-ASCII char."
  (mapconcat (lambda (c)
               (if (< c 128) (string c)
                 (make-string (length (encode-coding-string (string c) 'utf-8)) ?+)))
             name ""))

(defun eqv-compare (old new)
  "(DIFFS . RENAMED) between OLD and NEW hash tables.
RENAMED lists (OLD-KEY NEW-KEY GAVS) pairs explained by `eqv-unzip-mangle';
DIFFS up to 10 unexplained (KEY OLD-VALUE NEW-VALUE) differences."
  (let (diffs renamed explained)
    (maphash
     (lambda (k v)
       (let ((ov (gethash k old 'missing)))
         (cond
          ((equal v ov))
          ((and (eq ov 'missing) (string-match-p "[^[:ascii:]]" k))
           (let ((m (eqv-unzip-mangle k)))
             (if (and (equal (gethash m old) v) (eq (gethash m new 'missing) 'missing))
                 (progn (push (list m k v) renamed) (push m explained))
               (push (list k ov v) diffs))))
          (t (push (list k ov v) diffs)))))
     new)
    (maphash (lambda (k v) (when (and (eq (gethash k new 'missing) 'missing)
                                      (not (member k explained)))
                             (push (list k v 'missing) diffs)))
             old)
    (cons (seq-take diffs 10) renamed)))

(let* ((st (with-temp-buffer (insert-file-contents eqv-state-file) (read (current-buffer))))
       (root (plist-get st :root))
       (jars (plist-get st :jars))
       (old (eqv-old jars))
       (new (eqv-new root jars))
       (ok t))
  (message "input: %d jars from %s (root %s)" (length jars) eqv-state-file root)
  (message "old: %d classes, %d unreadable, %d unparsed"
           (hash-table-count (nth 0 old)) (length (nth 1 old)) (length (nth 2 old)))
  (message "new: %d classes, %d unreadable, %d unparsed"
           (hash-table-count (nth 0 new)) (length (nth 1 new)) (length (nth 2 new)))
  (unless (= (hash-table-count (nth 0 old)) (hash-table-count (nth 0 new)))
    (setq ok nil) (message "class counts differ"))
  (let ((cmp (eqv-compare (nth 0 old) (nth 0 new))))
    (dolist (r (cdr cmp))
      (message "accepted: unzip key %S is %S in the helper index (%s)"
               (nth 0 r) (nth 1 r) (string-join (nth 2 r) " ")))
    (when (car cmp)
      (setq ok nil)
      (message "class-index differs (name old new): %S" (car cmp))))
  (unless (equal (nth 1 old) (nth 1 new))
    (setq ok nil) (message ":unreadable differs: %S vs %S" (nth 1 old) (nth 1 new)))
  (unless (equal (nth 2 old) (nth 2 new))
    (setq ok nil) (message ":unparsed differs: %S vs %S" (nth 2 old) (nth 2 new)))
  (message (if ok "EQUIVALENT" "NOT EQUIVALENT"))
  (kill-emacs (if ok 0 1)))

;;; check-equivalence.el ends here
