;;; booster-bench.el --- opt-in benchmark of eglot-booster modes on a real server -*- lexical-binding: t; -*-

;; NOT part of any ERT suite run by default, same status as libsrc-e2e.el.
;; Loading this file starts nothing; only the commands below do.
;; The package has been removed from this config: before a smoke or benchmark run,
;; `M-x package-vc-install RET https://github.com/jdtsmith/eglot-booster'.
;;
;; Pure tests of the verdict rule (needs no server):
;;   emacs -Q --batch -l test/booster-bench.el -f ert-run-tests-batch-and-exit
;;
;; Proves the path under test: one child per mode, one hover each, three lines.
;; Unset BOOSTER_BENCH_DIR means a throwaway Go module in a temp directory.
;;   [BOOSTER_BENCH_DIR=DIR] emacs -Q --batch -l test/booster-bench.el -f booster-bench-smoke
;;
;; The measurement: 3 rotations of off, io-only and bytecode, one child per mode
;; and rotation, on a Go module of your choice:
;;   emacs -Q --batch -l test/booster-bench.el --eval '(booster-bench-run "gopls" "DIR")'
;;
;; Writes only under var/booster-bench/ (gitignored).  The module is read-only:
;; never didSave, never an applied edit.  Requests name files by URI, and the one
;; didChange stays in the server's overlay.  Printed and stored data is metadata
;; only (sizes, ids, first char, timings), never a response body.
;;
;; Go only: target picking and the connect call assume a Go module and gopls.
;;
;; Decision metric: median blocked ms, the time spent inside
;; `jsonrpc--process-filter' from just before a request is sent until
;; `jsonrpc-request' returns.  Summed over the window, since one reply spans many
;; 64 KiB chunks.  Parse, round trip, consing and GC are context only.  Batch has
;; no redisplay, so a verdict covers process-side blocking, not perceived latency.
;;
;; gopls's `completionBudget' is "0s" in the children (live default: 100ms), or a
;; time-budgeted reply could differ between modes and trip the result-count check.

;; End-to-end check of that path on a throwaway module, with few samples.  Not a
;; measurement: such a module has no large reply, so its verdict means nothing.
;;   emacs -Q --batch -l test/booster-bench.el -f booster-bench-fixture-check
;;
;; BOOSTER_BENCH_SAMPLES overrides the number of samples per action (default 30).

;;; Code:
(require 'cl-lib)
(require 'ert)

(defconst booster-bench--file (or load-file-name buffer-file-name))
(defconst booster-bench--root
  (expand-file-name ".." (file-name-directory booster-bench--file)))
(defconst booster-bench--out-dir
  (expand-file-name "var/booster-bench/" booster-bench--root))

(defconst booster-bench--samples 30 "Default samples per action, after readiness.")
(defconst booster-bench--l-bytes 102400 "At least this off-mode reply size is L.")
(defconst booster-bench--s-bytes 20480 "Under this off-mode reply size is S.")
(defconst booster-bench--ram-floor-kb 3145728
  "MemAvailable needed at run start and before each child.")
(defconst booster-bench--ram-abort-kb 1048576
  "MemAvailable under which a child aborts, between samples and polls.")
(defconst booster-bench--modes '(off io-only bytecode))
(defconst booster-bench--rotations
  '((1 off io-only bytecode) (2 io-only bytecode off) (3 bytecode off io-only))
  "Order of the modes in each rotation.")
(defconst booster-bench--symbol-query "New" "Fixed `workspace/symbol' query.")

;;; The pre-committed rule.  Pure; rows are (ROTATION MODE ACTION MEDIAN-MS OFF-BYTES).
;;
;; L = off-mode reply of at least 100 KiB, S = under 20 KiB, anything between is
;; reported only.  A mode qualifies if, in each rotation, every L action is at
;; least 25% and at least 5 ms below off, and no S action is worse than off by
;; both more than 25% and more than 1 ms.  With no S action that clause holds
;; vacuously.  First match wins:
;;   1. no L action: inconclusive
;;   2. neither mode qualifies: no-win
;;   3. one mode qualifies: that mode
;;   4. both qualify: bytecode if at least 25% better than io-only on every L
;;      action in every rotation, otherwise io-only.

(defun booster-bench--median (numbers)
  "Return the median of the non-empty list NUMBERS."
  (let* ((sorted (sort (copy-sequence numbers) #'<))
         (n (length sorted))
         (mid (/ n 2)))
    (if (cl-oddp n)
        (nth mid sorted)
      (/ (+ (nth (1- mid) sorted) (nth mid sorted)) 2.0))))

(defun booster-bench--class (off-bytes)
  "Return the class of an action with OFF-BYTES median off-mode reply size."
  (cond ((>= off-bytes booster-bench--l-bytes) 'L)
        ((< off-bytes booster-bench--s-bytes) 'S)))

(defun booster-bench--ms-at (rows rotation mode action)
  "Return the median in ROWS for ROTATION, MODE and ACTION."
  (let ((row (cl-find-if (lambda (r) (and (eql (nth 0 r) rotation)
                                          (eq (nth 1 r) mode)
                                          (eq (nth 2 r) action)))
                         rows)))
    (unless row (error "No row for rotation %s mode %s action %s" rotation mode action))
    (nth 3 row)))

(defun booster-bench--actions-in-class (rows class)
  "Return the distinct actions of ROWS whose off-mode size puts them in CLASS."
  (let (actions)
    (dolist (r rows)
      (when (eq (booster-bench--class (nth 4 r)) class)
        (cl-pushnew (nth 2 r) actions)))
    actions))

(defun booster-bench--l-win-p (ms off)
  "Non-nil if MS beats OFF on an L action: at least 25% and at least 5 ms."
  (let ((gain (- off ms)))
    (and (>= gain (* 0.25 off)) (>= gain 5))))

(defun booster-bench--s-worse-p (ms off)
  "Non-nil if MS loses to OFF on an S action: more than 25% and more than 1 ms."
  (let ((loss (- ms off)))
    (and (> loss (* 0.25 off)) (> loss 1))))

(defun booster-bench--qualifies-p (rows mode rotations l-actions s-actions)
  "Non-nil if MODE passes both clauses in every one of ROTATIONS, per ROWS."
  (cl-every
   (lambda (rot)
     (and (cl-every (lambda (a)
                      (booster-bench--l-win-p (booster-bench--ms-at rows rot mode a)
                                              (booster-bench--ms-at rows rot 'off a)))
                    l-actions)
          (cl-notany (lambda (a)
                       (booster-bench--s-worse-p (booster-bench--ms-at rows rot mode a)
                                                 (booster-bench--ms-at rows rot 'off a)))
                     s-actions)))
   rotations))

(defun booster-bench--bytecode-beats-io-only-p (rows rotations l-actions)
  "Non-nil if bytecode is 25% better than io-only on all L-ACTIONS in all ROTATIONS."
  (cl-every
   (lambda (rot)
     (cl-every (lambda (a)
                 (let ((io (booster-bench--ms-at rows rot 'io-only a))
                       (bc (booster-bench--ms-at rows rot 'bytecode a)))
                   (>= (- io bc) (* 0.25 io))))
               l-actions))
   rotations))

(defun booster-bench-verdict (rows)
  "Return the verdict for ROWS: `inconclusive', `no-win', `io-only' or `bytecode'.
Each row is (ROTATION MODE ACTION MEDIAN-BLOCKED-MS OFF-BYTES)."
  (let* ((rotations (cl-remove-duplicates (mapcar #'car rows)))
         (l-actions (booster-bench--actions-in-class rows 'L))
         (s-actions (booster-bench--actions-in-class rows 'S)))
    (if (null l-actions)
        'inconclusive
      (let ((io (booster-bench--qualifies-p rows 'io-only rotations l-actions s-actions))
            (bc (booster-bench--qualifies-p rows 'bytecode rotations l-actions s-actions)))
        (cond ((and (not io) (not bc)) 'no-win)
              ((and io (not bc)) 'io-only)
              ((and bc (not io)) 'bytecode)
              ((booster-bench--bytecode-beats-io-only-p rows rotations l-actions) 'bytecode)
              (t 'io-only))))))

;;; Tests of the rule

(defun booster-bench-test--rows (&rest actions)
  "Build rows from ACTIONS, each (NAME OFF-BYTES MEDIANS).
MEDIANS is one (OFF IO-ONLY BYTECODE) triple used in all three rotations, or a
list of three such triples."
  (let (rows)
    (pcase-dolist (`(,name ,bytes ,medians) actions)
      (let ((per-rot (if (consp (car medians)) medians (list medians medians medians))))
        (cl-loop for rot from 1 for triple in per-rot do
                 (cl-loop for mode in booster-bench--modes for ms in triple do
                          (push (list rot mode name ms bytes) rows)))))
    (nreverse rows)))

(defconst booster-bench-test--small '(hover 1000 (2 2 2)) "An S action that never moves.")

(ert-deftest booster-bench-median ()
  (should (= (booster-bench--median '(3 1 2)) 2))
  (should (= (booster-bench--median '(4 1 2 3)) 2.5)))

(ert-deftest booster-bench-class-boundaries ()
  (should (eq (booster-bench--class 102400) 'L))
  (should (null (booster-bench--class 102399)))
  (should (null (booster-bench--class 20480)))
  (should (eq (booster-bench--class 20479) 'S)))

(ert-deftest booster-bench-rule1-inconclusive-no-L ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows booster-bench-test--small
                                         '(symbol 50000 (100 10 10))))
              'inconclusive)))

(ert-deftest booster-bench-rule2-no-win ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 90))
                                         booster-bench-test--small))
              'no-win)))

(ert-deftest booster-bench-rule3-only-io-only ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 60 95))
                                         booster-bench-test--small))
              'io-only)))

(ert-deftest booster-bench-rule3-only-bytecode ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))
                                         booster-bench-test--small))
              'bytecode)))

(ert-deftest booster-bench-rule4-both-bytecode ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 70 40))
                                         booster-bench-test--small))
              'bytecode)))

(ert-deftest booster-bench-rule4-exactly-25-percent-is-bytecode ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 60 45))
                                         booster-bench-test--small))
              'bytecode)))

(ert-deftest booster-bench-rule4-both-io-only ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 70 60))
                                         booster-bench-test--small))
              'io-only)))

(ert-deftest booster-bench-rule4-must-hold-in-every-rotation ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows
                '(refs 300000 ((100 70 40) (100 70 40) (100 70 60)))
                booster-bench-test--small))
              'io-only)))

(ert-deftest booster-bench-win-2-of-3-does-not-qualify ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows
                '(refs 300000 ((100 95 60) (100 95 60) (100 95 90)))
                booster-bench-test--small))
              'no-win)))

(ert-deftest booster-bench-L-below-5ms-floor ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (10 7 7))
                                         booster-bench-test--small))
              'no-win)))

(ert-deftest booster-bench-L-below-25-percent-floor ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 80 80))
                                         booster-bench-test--small))
              'no-win)))

(ert-deftest booster-bench-io-only-qualifies-while-bytecode-better-on-L-fails-S ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 70 40))
                                         '(hover 1000 (10 10 14))))
              'io-only)))

(ert-deftest booster-bench-S-worse-on-one-measure-only-still-qualifies ()
  ;; +2 ms but only 20%.
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))
                                         '(hover 1000 (10 10 12))))
              'bytecode))
  ;; +90% but only 0.9 ms.
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))
                                         '(hover 1000 (1 1 1.9))))
              'bytecode)))

(ert-deftest booster-bench-every-L-action-must-win ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))
                                         '(symbols 200000 (100 95 95))
                                         booster-bench-test--small))
              'no-win)))

(ert-deftest booster-bench-every-S-action-must-hold ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))
                                         booster-bench-test--small
                                         '(completion 5000 (10 10 20))))
              'no-win)))

(ert-deftest booster-bench-middle-sized-action-is-report-only ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))
                                         booster-bench-test--small
                                         '(symbols 50000 (10 10 500))))
              'bytecode)))

(ert-deftest booster-bench-no-S-action-is-vacuous ()
  (should (eq (booster-bench-verdict
               (booster-bench-test--rows '(refs 300000 (100 95 60))))
              'bytecode)))

(ert-deftest booster-bench-every-input-gets-exactly-one-verdict ()
  (let ((grid '(1 7 50 75 100 140)) (bytes '(1000 50000 300000)))
    (dolist (b bytes)
      (dolist (io grid)
        (dolist (bc grid)
          (dolist (s grid)
            (should (memq (booster-bench-verdict
                           (booster-bench-test--rows
                            `(refs ,b (100 ,io ,bc))
                            `(hover 1000 (50 50 ,s))))
                          '(inconclusive no-win io-only bytecode)))))))))

;;; Memory guards

(defun booster-bench--mem-available-kb ()
  "Return MemAvailable from /proc/meminfo, in kB."
  (with-temp-buffer
    (insert-file-contents "/proc/meminfo")
    (unless (re-search-forward "^MemAvailable: *\\([0-9]+\\) kB" nil t)
      (error "No MemAvailable in /proc/meminfo"))
    (string-to-number (match-string 1))))

(defun booster-bench--ram-gate ()
  "Wait up to 10 min, checking every 30 s, for the MemAvailable floor; else signal."
  (let ((deadline (+ (float-time) 600)))
    (while (< (booster-bench--mem-available-kb) booster-bench--ram-floor-kb)
      (when (>= (float-time) deadline)
        (error "MemAvailable stayed under %d kB for 10 min (last %d kB)"
               booster-bench--ram-floor-kb (booster-bench--mem-available-kb)))
      (princ (format "waiting for RAM: MemAvailable %d kB\n"
                     (booster-bench--mem-available-kb)))
      (sleep-for 30))))

(defun booster-bench--ram-watchdog ()
  "Signal if MemAvailable has dropped under the abort line."
  (let ((kb (booster-bench--mem-available-kb)))
    (when (< kb booster-bench--ram-abort-kb)
      (error "MemAvailable %d kB under abort line %d kB" kb booster-bench--ram-abort-kb))))

;;; Child process: one mode, one server

(defvar booster-bench--filter-ms 0.0 "Blocked ms in the filter in this window.")
(defvar booster-bench--reads nil
  "Messages parsed in this window: (ID METHOD BYTES FIRST-CHAR PARSE-MS).")

(defun booster-bench--filter-advice (orig &rest args)
  "Add the time ORIG takes on ARGS to `booster-bench--filter-ms'."
  (let ((t0 (float-time)))
    (unwind-protect (apply orig args)
      (cl-incf booster-bench--filter-ms (* 1000.0 (- (float-time) t0))))))

(defun booster-bench--read-advice (orig)
  "Record size, encoding and parse time of the message ORIG reads.
The process buffer is unibyte and narrowed to the message, so positions are bytes."
  (let* ((bytes (- (point-max) (point-min)))
         (first-char (char-after (point)))
         (t0 (float-time))
         (msg (funcall orig)))
    (push (list (plist-get msg :id) (plist-get msg :method) bytes first-char
                (* 1000.0 (- (float-time) t0)))
          booster-bench--reads)
    msg))

(defun booster-bench--load-packages ()
  "Activate this repo's packages and load what a child needs."
  (setq package-user-dir (expand-file-name "elpa" booster-bench--root))
  (package-initialize)
  (add-to-list 'treesit-extra-load-path
               (expand-file-name "tree-sitter" booster-bench--root))
  (require 'project)
  (require 'jsonrpc)
  (require 'eglot)
  (require 'eglot-booster)
  (require 'go-ts-mode))

(defun booster-bench--bytes-consed ()
  "Return an estimate of the bytes consed so far, from `memory-use-counts'."
  (cl-loop for count in (memory-use-counts)
           for size in '(16 8 8 48 1 56 32)
           sum (* count size)))

(defun booster-bench--sample (server action &optional timeout)
  "Send ACTION, (NAME METHOD PARAMS), to SERVER once and return its measurements.
The reply is the parsed message with our id and no `:method': a server-initiated
request carries its own id, which can be numerically equal to ours."
  (pcase-let* ((`(,name ,method ,params) action)
               (id (1+ (jsonrpc--next-request-id server)))
               (consed0 (booster-bench--bytes-consed))
               (gc0 gc-elapsed)
               (t0 nil) (t1 nil) (result nil))
    (setq booster-bench--filter-ms 0.0
          booster-bench--reads nil
          t0 (float-time)
          result (jsonrpc-request server method params :timeout (or timeout 300))
          t1 (float-time))
    (let ((reply (cl-find-if (lambda (r) (and (eql (nth 0 r) id) (null (nth 1 r))))
                             booster-bench--reads)))
      (unless reply (error "No reply recorded for request id %d" id))
      (list :action name
            :blocked booster-bench--filter-ms
            :parse (nth 4 reply)
            :roundtrip (* 1000.0 (- t1 t0))
            :bytes (nth 2 reply)
            :first (char-to-string (nth 3 reply))
            :count (booster-bench--count name result)
            :multibyte (booster-bench--text-multibyte name result)
            :consed (- (booster-bench--bytes-consed) consed0)
            :gc (* 1000.0 (- gc-elapsed gc0))))))

(defun booster-bench--sample-count ()
  "Return the samples per action for this process."
  (let ((env (getenv "BOOSTER_BENCH_SAMPLES")))
    (if env (string-to-number env) booster-bench--samples)))

(defun booster-bench--count (name result)
  "Return how many results RESULT of action NAME holds."
  (pcase name
    ('completion (length (if (vectorp result) result (plist-get result :items))))
    ;; Bytes, not characters: in bytecode mode the text reaches Lisp as an
    ;; undecoded unibyte string, so `length' differs for the very same reply.
    ((or 'hover 'hover-small) (string-bytes (booster-bench--hover-text result)))
    (_ (length result))))

(defun booster-bench--hover-text (result)
  "Return the text of the hover RESULT, or an empty string."
  (let ((contents (plist-get result :contents)))
    (or (cond ((stringp contents) contents)
              ((vectorp contents)
               (mapconcat (lambda (c) (if (stringp c) c (plist-get c :value))) contents "\n"))
              (t (plist-get contents :value)))
        "")))

(defun booster-bench--text-multibyte (name result)
  "Return \"t\" or \"nil\" for the reply text of a hover NAME, else \"-\"."
  (if (memq name '(hover hover-small))
      (if (multibyte-string-p (booster-bench--hover-text result)) "t" "nil")
    "-"))

(defun booster-bench--position-params (target &rest extra)
  "Return LSP params for TARGET, (FILE LINE CHARACTER), plus EXTRA."
  (append (list :textDocument (list :uri (eglot-path-to-uri (nth 0 target)))
                :position (list :line (nth 1 target) :character (nth 2 target)))
          extra))

(defun booster-bench--hover-action (targets)
  (list 'hover :textDocument/hover
        (booster-bench--position-params (alist-get 'hover targets))))

(defun booster-bench--hover-small-action (targets)
  "Hover at the references target: a function, so a small reply is expected."
  (list 'hover-small :textDocument/hover
        (booster-bench--position-params (alist-get 'references targets))))

(defun booster-bench--references-action (targets)
  (list 'references :textDocument/references
        (booster-bench--position-params (alist-get 'references targets)
                                        :context '(:includeDeclaration t))))

(defun booster-bench--mode-command-ok-p (mode command)
  "Non-nil if process COMMAND, a list of strings, is what MODE must run."
  (let ((has (lambda (s) (member s command))))
    (pcase mode
      ('off (not (funcall has "emacs-lsp-booster")))
      ('io-only (and (funcall has "emacs-lsp-booster") (funcall has "--disable-bytecode")))
      ('bytecode (and (funcall has "emacs-lsp-booster") (funcall has "--json-false-value"))))))

(defun booster-bench--encoding-ok-p (mode first-char)
  "Non-nil if a reply starting with the string FIRST-CHAR is right for MODE."
  (equal first-char (if (eq mode 'bytecode) "#" "{")))

(defun booster-bench--wait (seconds)
  "Service process output and timers for SECONDS."
  (let ((deadline (+ (float-time) seconds)))
    (while (< (float-time) deadline)
      (accept-process-output nil (max 0.01 (- deadline (float-time)))))))

(defun booster-bench--wait-until-ready (server action)
  "Poll ACTION on SERVER until its reply size holds for 3 polls; return the last sample.
Signal after 10 min.  Polls are never samples."
  (let ((deadline (+ (float-time) 600)) (stable 0) last-bytes sample)
    (while (< stable 3)
      (when (> (float-time) deadline)
        (error "Server did not settle within 10 min"))
      (booster-bench--ram-watchdog)
      (setq sample (condition-case nil
                       (booster-bench--sample server action
                                              (max 1 (- deadline (float-time))))
                     (jsonrpc-error nil)))
      (cond ((or (null sample) (zerop (plist-get sample :count)))
             (setq stable 0 last-bytes nil))
            ((eql (plist-get sample :bytes) last-bytes) (cl-incf stable))
            (t (setq stable 1 last-bytes (plist-get sample :bytes))))
      (when (< stable 3) (booster-bench--wait 5)))
    sample))

(defun booster-bench--append (csv line)
  "Append LINE to the file CSV."
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region (concat line "\n") nil csv 'append 'silent)))

(defun booster-bench--meta (csv rotation mode key value)
  "Append one metadata row to CSV."
  (booster-bench--append
   csv (format "#meta,%s,%s,%s,%s" rotation mode key
               (replace-regexp-in-string "[,\n]" ";" (format "%s" value)))))

(defun booster-bench--write-sample (csv rotation mode n s)
  "Append sample number N, the plist S, to CSV."
  (booster-bench--append
   csv (format "%s,%s,%s,%d,%.3f,%.3f,%.3f,%d,%s,%d,%d,%.3f,%s"
               rotation mode (plist-get s :action) n
               (plist-get s :blocked) (plist-get s :parse) (plist-get s :roundtrip)
               (plist-get s :bytes) (plist-get s :first) (plist-get s :count)
               (plist-get s :consed) (plist-get s :gc) (plist-get s :multibyte))))

(defun booster-bench--did-change (server csv rotation mode)
  "Send one large didChange to SERVER, in the overlay only; report its send time.
Report only: this row never reaches the verdict."
  (unless (eglot-managed-p) (error "didChange: current buffer is not managed"))
  (let* ((text (concat (buffer-substring-no-properties (point-min) (point-max))
                       (apply #'concat (make-list 2560 (concat "// " (make-string 77 ?x) "\n")))))
         (send-ms nil)
         (timer (lambda (orig &rest args)
                  (let ((t0 (float-time)))
                    (prog1 (apply orig args)
                      (setq send-ms (* 1000.0 (- (float-time) t0))))))))
    (advice-add 'jsonrpc-connection-send :around timer)
    (unwind-protect
        (jsonrpc-notify
         server :textDocument/didChange
         (list :textDocument (list :uri (eglot-path-to-uri buffer-file-name)
                                   :version (1+ eglot--docver))
               :contentChanges (vector (list :text text))))
      (advice-remove 'jsonrpc-connection-send timer))
    (booster-bench--write-sample
     csv rotation mode 1
     (list :action 'did-change :blocked 0.0 :parse 0.0 :roundtrip send-ms
           :bytes (string-bytes text) :first "-" :count 0 :consed 0 :gc 0.0
           :multibyte "-"))))

(defun booster-bench--measure (server mode rotation csv targets)
  "Wait for SERVER to settle, then sample every action N times into CSV."
  (let* ((probe (booster-bench--references-action targets))
         (ready (booster-bench--wait-until-ready server probe))
         (completion (alist-get 'completion targets))
         (actions
          (list probe
                (booster-bench--hover-action targets)
                (booster-bench--hover-small-action targets)
                (list 'completion :textDocument/completion
                      (booster-bench--position-params completion
                                                      :context '(:triggerKind 1)))
                (list 'workspace-symbol :workspace/symbol
                      (list :query booster-bench--symbol-query)))))
    (unless (booster-bench--encoding-ok-p mode (plist-get ready :first))
      (error "Mode %s: probe reply starts with %s" mode (plist-get ready :first)))
    (dolist (action actions)
      (garbage-collect)
      (dotimes (i (booster-bench--sample-count))
        (booster-bench--ram-watchdog)
        (booster-bench--write-sample csv rotation mode (1+ i)
                                     (booster-bench--sample server action))
        (booster-bench--wait 0.05)))
    (booster-bench--did-change server csv rotation mode)))

(defun booster-bench--smoke (server mode targets command)
  "Send one hover to SERVER, retrying while it loads, and print the MODE line.
COMMAND is the server process's command.  Signal if anything is not as required."
  (let ((action (booster-bench--hover-action targets))
        (deadline (+ (float-time) 600))
        sample)
    (while (not (and sample (> (plist-get sample :count) 0)))
      (when (> (float-time) deadline) (error "Hover never got a non-nil reply"))
      (when sample (booster-bench--wait 1))
      (setq sample (or (condition-case nil
                           (booster-bench--sample server action 300)
                         (jsonrpc-error nil))
                       '(:count 0))))
    (princ (format "%s: managed=%s reply=non-nil first=%s bytes=%d command=%s\n"
                   mode (eglot-managed-p) (plist-get sample :first)
                   (plist-get sample :bytes) (string-join command " ")))
    (unless (booster-bench--encoding-ok-p mode (plist-get sample :first))
      (error "Mode %s: probe reply starts with %s" mode (plist-get sample :first)))))

(defun booster-bench--descendants (pid)
  "Return the live descendants of PID, itself included."
  (let ((parents (mapcar (lambda (p) (cons p (alist-get 'ppid (process-attributes p))))
                         (list-system-processes)))
        (found (list pid)) (grew t))
    (while grew
      (setq grew nil)
      (pcase-dolist (`(,p . ,ppid) parents)
        (when (and (memq ppid found) (not (memq p found)))
          (push p found)
          (setq grew t))))
    found))

(defun booster-bench--teardown (server)
  "Shut SERVER down and wait for its whole process tree to go.
Servers must never overlap.  Signals only descendants of this child's server."
  (let* ((proc (jsonrpc--process server))
         (pids (and (process-live-p proc) (booster-bench--descendants (process-id proc))))
         (gone-p (lambda (p)
                   (let ((attrs (process-attributes p)))
                     (or (null attrs) (equal (alist-get 'state attrs) "Z")))))
         (deadline (+ (float-time) 30)))
    (with-demoted-errors "booster-bench: shutdown: %S"
      (eglot-shutdown server nil 10))
    (while (and (< (float-time) deadline) (not (cl-every gone-p pids)))
      (sleep-for 0.2))
    (dolist (p pids)
      (unless (funcall gone-p p)
        (signal-process p 'SIGTERM)))))

(defun booster-bench--child-1 (kind mode server-name dir rotation csv targets)
  "Run one child of KIND, `smoke' or `run'.  See `booster-bench--child'."
  (booster-bench--load-packages)
  (let ((dir (file-name-as-directory (expand-file-name dir)))
        (native (subr-native-elisp-p (symbol-function 'jsonrpc--process-filter)))
        server)
    (setq gc-cons-threshold (* 1024 1024 1024)
          enable-local-variables :safe
          eglot-events-buffer-config '(:size 0 :format full)
          eglot-sync-connect t
          eglot-connect-timeout 300)
    (setq-default eglot-workspace-configuration '(:gopls (:completionBudget "0s")))
    (unless (eq mode 'off)
      (setq eglot-booster-io-only (eq mode 'io-only))
      (eglot-booster-mode 1))
    (advice-add 'jsonrpc--process-filter :around #'booster-bench--filter-advice)
    (advice-add 'jsonrpc--json-read :around #'booster-bench--read-advice)
    (setq project-find-functions (list (lambda (_dir) (cons 'transient dir))))
    (with-current-buffer (find-file-noselect (alist-get 'visit targets))
      (go-ts-mode)
      (read-only-mode 1)
      (unwind-protect
          (progn
            (setq server (eglot--connect '(go-ts-mode) (cons 'transient dir)
                                         'eglot-lsp-server (list server-name) '("go")))
            (unless server (error "`eglot--connect' returned no server"))
            (unless (eglot-managed-p) (error "Mode %s: buffer is not managed" mode))
            (let ((command (process-command (jsonrpc--process server))))
              (unless (booster-bench--mode-command-ok-p mode command)
                (error "Mode %s: wrong command %s" mode (string-join command " ")))
              (pcase kind
                ('smoke (booster-bench--smoke server mode targets command))
                ('run
                 (dolist (kv `((emacs . ,emacs-version)
                               (eglot . ,(symbol-file 'eglot--connect))
                               (jsonrpc . ,(symbol-file 'jsonrpc--process-filter))
                               (server . ,(car (process-lines-ignore-status server-name "version")))
                               (filter-native . ,native)
                               (command . ,(string-join command " "))
                               (read-process-output-max . ,read-process-output-max)
                               (gc-cons-threshold . ,gc-cons-threshold)
                               (workspace-configuration
                                . ,(eglot--workspace-configuration-plist server))
                               (mem-available-kb . ,(booster-bench--mem-available-kb))
                               (targets . ,targets)))
                   (booster-bench--meta csv rotation mode (car kv) (cdr kv)))
                 (booster-bench--measure server mode rotation csv targets)))))
        (when server (booster-bench--teardown server))))))

(defun booster-bench--child (kind mode server-name dir rotation csv targets)
  "Entry point of a child Emacs.  Exit 0 only if nothing went wrong.
KIND is `smoke' or `run', MODE one of `booster-bench--modes', DIR the Go module,
CSV the output file and TARGETS the alist from `booster-bench--pick-targets'."
  (condition-case err
      (booster-bench--child-1 kind mode server-name dir rotation csv targets)
    (error
     (princ (format "booster-bench-error: %s (MemAvailable %d kB)\n"
                    (error-message-string err) (booster-bench--mem-available-kb)))
     (kill-emacs 1)))
  (kill-emacs 0))

;;; Picking targets, generically, once per run

(defun booster-bench--rg (dir &rest args)
  "Return the output lines of rg ARGS run in DIR."
  (let ((default-directory dir)
        (coding-system-for-read 'utf-8))
    (apply #'process-lines-ignore-status "rg" args)))

(defun booster-bench--pick-selector (dir)
  "Return (QUALIFIER NAME) of the most used `q.Name(' declared in DIR's package q."
  (let ((uses (make-hash-table :test 'equal))
        (declared (make-hash-table :test 'equal))
        candidates)
    (dolist (line (booster-bench--rg
                   dir "--no-filename" "-o" "-t" "go"
                   "\\b[A-Za-z_][A-Za-z0-9_]*\\.[A-Z][A-Za-z0-9_]*\\("))
      (cl-incf (gethash (substring line 0 -1) uses 0)))
    (dolist (line (booster-bench--rg
                   dir "-o" "-H" "--no-heading" "--no-line-number" "-t" "go"
                   "^func [A-Z][A-Za-z0-9_]*\\("))
      (when (string-match "\\`\\(.*\\):func \\([A-Za-z0-9_]+\\)(" line)
        (let* ((path (match-string 1 line))
               (name (match-string 2 line))
               (parent (file-name-directory path)))
          (when parent
            (puthash (format "%s.%s"
                             (file-name-nondirectory (directory-file-name parent)) name)
                     t declared)))))
    (maphash (lambda (token count)
               (when (gethash token declared) (push (cons token count) candidates)))
             uses)
    (unless candidates (error "No selector declared in a package of its own name"))
    (setq candidates
          (sort candidates (lambda (a b)
                             (or (> (cdr a) (cdr b))
                                 (and (= (cdr a) (cdr b)) (string< (car a) (car b)))))))
    (split-string (caar candidates) "\\.")))

(defun booster-bench--first-use (dir qualifier name)
  "Return (FILE LINE CHARACTER-OF-NAME) of the first use of QUALIFIER.NAME outside a comment."
  (let* ((token (format "%s.%s(" qualifier name))
         (pattern (format "\\b%s\\.%s\\(" qualifier name)))
    (cl-loop
     for line in (booster-bench--rg dir "-n" "--sort" "path" "-t" "go" pattern)
     when (string-match "\\`\\([^:]+\\):\\([0-9]+\\):\\(.*\\)\\'" line)
     do (let* ((file (match-string 1 line))
               (lnum (string-to-number (match-string 2 line)))
               (text (match-string 3 line))
               (idx (string-search token text)))
          (when (and idx (not (string-search "//" (substring text 0 idx))))
            (cl-return (list (expand-file-name file dir) (1- lnum)
                             (+ idx (length qualifier) 1)))))
     finally (error "No use of the selector outside a comment"))))

(defun booster-bench--largest-struct (dir)
  "Return (FILE LINE CHARACTER) of the longest `type X struct {' block under DIR."
  (let ((best nil) (best-size -1) (buffered nil))
    (with-temp-buffer
      (dolist (line (booster-bench--rg dir "-n" "--sort" "path" "-t" "go"
                                       "^type [A-Za-z0-9_]+ struct \\{"))
        (when (string-match "\\`\\([^:]+\\):\\([0-9]+\\):" line)
          (let ((file (expand-file-name (match-string 1 line) dir))
                (lnum (string-to-number (match-string 2 line))))
            (unless (equal file buffered)
              (erase-buffer)
              (insert-file-contents file)
              (setq buffered file))
            (goto-char (point-min))
            (forward-line (1- lnum))
            (let* ((start (point))
                   (end (or (re-search-forward "^}" nil t) (point-max)))
                   (size (count-lines start end)))
              (when (> size best-size)
                (setq best-size size
                      best (list file (1- lnum) (length "type ")))))))))
    (or best (error "No struct type found"))))

(defun booster-bench--pick-targets (dir)
  "Return the full target alist for DIR."
  (pcase-let* ((`(,qualifier ,name) (booster-bench--pick-selector dir))
               (use (booster-bench--first-use dir qualifier name)))
    `((visit . ,(car use))
      (references . ,use)
      (completion . ,use)
      (hover . ,(booster-bench--largest-struct dir)))))

;;; Parents

(defun booster-bench--spawn (kind mode server-name dir rotation csv targets stem)
  "Run one child and wait for it.  Return (EXIT-CODE . STDOUT).
Its stderr, where batch `message' goes, lands in a file named from STEM."
  (booster-bench--ram-gate)
  (with-temp-buffer
    (let ((code (call-process
                 (expand-file-name invocation-name invocation-directory)
                 nil (list t (format "%s-r%s-%s.stderr" stem rotation mode)) nil
                 "-Q" "--batch" "-l" booster-bench--file "--eval"
                 (prin1-to-string
                  `(booster-bench--child ',kind ',mode ,server-name ,dir ,rotation ,csv ',targets)))))
      (cons code (buffer-string)))))

(defconst booster-bench--fixture-go
  "package main

import (
\t\"fmt\"

\t\"fixture/helper\"
)

// Thing exists to be hovered.
type Thing struct {
\tA int
\tB string
}

func main() { fmt.Println(Thing{}, helper.Do()) }
")

(defconst booster-bench--fixture-helper-go
  "package helper

// Do exists to be referenced.
func Do() string { return \"done\" }
")

(defun booster-bench--make-fixture ()
  "Create a throwaway Go module and return its directory."
  (let ((dir (file-name-as-directory (make-temp-file "booster-bench-" t))))
    (write-region "module fixture\n\ngo 1.21\n" nil (expand-file-name "go.mod" dir) nil 'silent)
    (write-region booster-bench--fixture-go nil (expand-file-name "main.go" dir) nil 'silent)
    (make-directory (expand-file-name "helper" dir))
    (write-region booster-bench--fixture-helper-go nil
                  (expand-file-name "helper/helper.go" dir) nil 'silent)
    dir))

(defun booster-bench--stem ()
  "Return the path prefix for this run's output files."
  (make-directory booster-bench--out-dir t)
  (expand-file-name (format-time-string "%Y%m%dT%H%M%S") booster-bench--out-dir))

(defun booster-bench-smoke ()
  "Print one line per mode; exit non-zero unless all three are as required."
  (let* ((env-dir (getenv "BOOSTER_BENCH_DIR"))
         (dir (file-name-as-directory
               (expand-file-name (or env-dir (booster-bench--make-fixture)))))
         (stem (concat (booster-bench--stem) "-smoke"))
         (failed nil))
    (unwind-protect
        (let* ((hover (booster-bench--largest-struct dir))
               (targets `((visit . ,(car hover)) (hover . ,hover))))
          (dolist (mode booster-bench--modes)
            (pcase-let ((`(,code . ,out)
                         (booster-bench--spawn 'smoke mode "gopls" dir 0 nil targets stem)))
              (princ out)
              (unless (zerop code) (setq failed t)))))
      (unless env-dir (delete-directory dir t)))
    (kill-emacs (if failed 1 0))))

(defun booster-bench--read-csv (csv)
  "Return the sample rows of CSV as plists."
  (with-temp-buffer
    (insert-file-contents csv)
    (cl-loop for line in (split-string (buffer-string) "\n" t)
             unless (string-prefix-p "#" line)
             collect
             (pcase-let ((`(,rot ,mode ,action ,_n ,blocked ,parse ,rt ,bytes ,first ,count ,consed ,gc ,multibyte)
                          (split-string line ",")))
               (list :rotation (string-to-number rot)
                     :mode (intern mode) :action (intern action)
                     :blocked (string-to-number blocked)
                     :parse (string-to-number parse)
                     :roundtrip (string-to-number rt)
                     :bytes (string-to-number bytes)
                     :first first
                     :count (string-to-number count)
                     :consed (string-to-number consed)
                     :gc (string-to-number gc)
                     :multibyte multibyte)))))

(defun booster-bench--check-counts (rows)
  "Signal if any action in ROWS returned more than one result count."
  (let ((seen (make-hash-table)))
    (dolist (r rows)
      (unless (eq (plist-get r :action) 'did-change)
        (cl-pushnew (plist-get r :count) (gethash (plist-get r :action) seen))))
    (maphash (lambda (action counts)
               (when (cdr counts)
                 (error "Result count mismatch on %s: %S" action counts)))
             seen)))

(defun booster-bench--select (rows &rest props)
  "Return ROWS whose plists match PROPS."
  (cl-loop for r in rows
           when (cl-loop for (k v) on props by #'cddr always (eql (plist-get r k) v))
           collect r))

(defun booster-bench--median-of (rows prop)
  "Return the median of PROP over ROWS."
  (booster-bench--median (mapcar (lambda (r) (plist-get r prop)) rows)))

(defun booster-bench--actions (rows)
  "Return the actions in ROWS that the verdict sees, in first-seen order."
  (let (actions)
    (dolist (r rows) (cl-pushnew (plist-get r :action) actions))
    (reverse (remq 'did-change actions))))

(defun booster-bench--off-bytes (rows action)
  "Return ACTION's median off-mode reply size over all rotations in ROWS."
  (booster-bench--median-of (booster-bench--select rows :mode 'off :action action) :bytes))

(defun booster-bench--verdict-rows (rows)
  "Reduce the samples ROWS to the input of `booster-bench-verdict'."
  (cl-loop
   for action in (booster-bench--actions rows)
   for off-bytes = (booster-bench--off-bytes rows action)
   nconc
   (cl-loop
    for (rotation) in booster-bench--rotations
    nconc
    (cl-loop for mode in booster-bench--modes
             collect (list rotation mode action
                           (booster-bench--median-of
                            (booster-bench--select rows :rotation rotation :mode mode
                                                   :action action)
                            :blocked)
                           off-bytes)))))

(defun booster-bench--report (rows verdict)
  "Return the text report for the samples ROWS and VERDICT."
  (with-temp-buffer
    (pcase-dolist (`(,rotation . ,_order) booster-bench--rotations)
      (insert (format "Rotation %d\n" rotation)
              "| mode | action | class | blocked ms | parse ms | round trip ms | bytes | count | first | text multibyte | consed KiB | gc ms |\n")
      (dolist (mode booster-bench--modes)
        (dolist (action (booster-bench--actions rows))
          (let ((sel (booster-bench--select rows :rotation rotation :mode mode :action action)))
            (insert (format "| %s | %s | %s | %.3f | %.3f | %.1f | %d | %d | %s | %s | %.0f | %.1f |\n"
                            mode action
                            (or (booster-bench--class (booster-bench--off-bytes rows action)) 'report-only)
                            (booster-bench--median-of sel :blocked)
                            (booster-bench--median-of sel :parse)
                            (booster-bench--median-of sel :roundtrip)
                            (booster-bench--median-of sel :bytes)
                            (booster-bench--median-of sel :count)
                            (mapconcat #'identity
                                       (cl-remove-duplicates
                                        (mapcar (lambda (r) (plist-get r :first)) sel)
                                        :test #'equal)
                                       "")
                            (mapconcat #'identity
                                       (cl-remove-duplicates
                                        (mapcar (lambda (r) (plist-get r :multibyte)) sel)
                                        :test #'equal)
                                       "/")
                            (/ (booster-bench--median-of sel :consed) 1024.0)
                            (booster-bench--median-of sel :gc)))))))
    (insert "Report only, large didChange send ms by mode:")
    (dolist (mode booster-bench--modes)
      (insert (format " %s=%.3f" mode
                      (booster-bench--median-of
                       (booster-bench--select rows :mode mode :action 'did-change)
                       :roundtrip))))
    (insert "\n")
    (unless (booster-bench--actions-in-class (booster-bench--verdict-rows rows) 'S)
      (insert "Warning: no S action, so the S clause held vacuously\n"))
    (insert (format "Verdict: %s (gopls only; process-side blocking in batch, not perceived latency)\n"
                    verdict))
    (buffer-string)))

(defun booster-bench--run-1 (server-name dir stem)
  "Run every rotation of SERVER-NAME on DIR, print the report, and signal on failure."
  (let ((dir (file-name-as-directory (expand-file-name dir)))
        (csv (concat stem ".csv"))
        (targets nil))
    (booster-bench--ram-gate)
    (setq targets (booster-bench--pick-targets dir))
    (pcase-dolist (`(,rotation . ,order) booster-bench--rotations)
      (dolist (mode order)
        (pcase-let ((`(,code . ,out)
                     (booster-bench--spawn 'run mode server-name dir rotation csv targets stem)))
          (princ (format "rotation %d %s exit %d\n" rotation mode code))
          (unless (zerop code) (error "Child failed: %s" (string-trim out)))
          (booster-bench--check-counts (booster-bench--read-csv csv)))))
    (let* ((rows (booster-bench--read-csv csv))
           (report (booster-bench--report
                    rows (booster-bench-verdict (booster-bench--verdict-rows rows)))))
      (write-region report nil (concat stem "-summary.txt") nil 'silent)
      (princ report))))

(defun booster-bench--print-abort (err)
  "Print the abort line for ERR."
  (princ (format "booster-bench-abort: %s (last MemAvailable %d kB)\n"
                 (error-message-string err) (booster-bench--mem-available-kb))))

(defun booster-bench-run (server-name dir)
  "Measure SERVER-NAME on the Go module DIR and print the verdict.
Exit non-zero with no verdict if anything goes wrong."
  (condition-case err
      (booster-bench--run-1 server-name dir (booster-bench--stem))
    (error
     (booster-bench--print-abort err)
     (kill-emacs 1))))

(defun booster-bench-fixture-check ()
  "Run the whole measuring path on a throwaway module with 2 samples per action.
Proves the path through didChange, teardown and the report; measures nothing."
  (let ((dir (booster-bench--make-fixture))
        (failed nil))
    (unless (getenv "BOOSTER_BENCH_SAMPLES") (setenv "BOOSTER_BENCH_SAMPLES" "2"))
    (princ "Fixture check: not a measurement, ignore the verdict line below\n")
    (unwind-protect
        (condition-case err
            (booster-bench--run-1 "gopls" dir (concat (booster-bench--stem) "-fixture"))
          (error
           (booster-bench--print-abort err)
           (setq failed t)))
      (delete-directory dir t))
    (kill-emacs (if failed 1 0))))

(provide 'booster-bench)
;;; booster-bench.el ends here
