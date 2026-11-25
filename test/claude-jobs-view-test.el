;;; claude-jobs-view-test.el --- ERT suite for lisp/claude-jobs-view.el -*- lexical-binding: t; -*-

;; emacs -Q --batch -l test/claude-jobs-view-test.el -f ert-run-tests-batch-and-exit
;;
;; Core tests load only built-in Emacs libraries and `lisp/claude-jobs-view.el'
;; (no `package-initialize', no `.elc' files, all temp dirs cleaned via
;; `unwind-protect').

(require 'ert)
(require 'cl-lib)

(defconst cjv-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(add-to-list 'load-path (expand-file-name "lisp" cjv-test--root))
(require 'claude-jobs-view)

(defconst cjv-test--real-scan
  (expand-file-name "rust/lib/claude-jobs-scan" cjv-test--root))

(defvar cjv-test--wrapper-log nil
  "Log file recording invocations and arguments of `claude-jobs-scan'.")

(defun cjv-test--wrapper-runs ()
  "Return the list of logged invocations from `cjv-test--wrapper-log'."
  (if (and cjv-test--wrapper-log (file-exists-p cjv-test--wrapper-log))
      (with-temp-buffer
        (insert-file-contents cjv-test--wrapper-log)
        (split-string (buffer-string) "\n" t))
    nil))

(defmacro cjv-test--with-env (use-wrapper &rest body)
  "Run BODY with isolated state/jobs/projects dirs and clean caches.
When USE-WRAPPER is non-nil, require `rust/lib/claude-jobs-scan' and wrap
it in a counting script logging each call to `cjv-test--wrapper-log'."
  (declare (indent 1))
  `(let* ((tmp (make-temp-file "cjv-test-" t))
          (state-dir (expand-file-name "state" tmp))
          (jobs-dir (expand-file-name "jobs" tmp))
          (projects-dir (expand-file-name "projects" tmp))
          (cjv-test--wrapper-log (expand-file-name "scan.log" tmp))
          (wrapper (expand-file-name "scan-wrapper" tmp))
          (claude-jobs-view-state-dir state-dir)
          (claude-jobs-view-jobs-dir jobs-dir)
          (claude-jobs-view-projects-dir projects-dir)
          (claude-jobs-view-transcript-head-bytes 65536)
          (claude-jobs-view--scan-hinted nil)
          (claude-jobs-view-scan-program
           (if ,use-wrapper
               (progn
                 (skip-unless (file-executable-p cjv-test--real-scan))
                 (with-temp-file wrapper
                   (insert (format "#!/bin/sh\necho \"$*\" >> %s\nexec %s \"$@\"\n"
                                   (shell-quote-argument cjv-test--wrapper-log)
                                   (shell-quote-argument cjv-test--real-scan))))
                 (set-file-modes wrapper #o755)
                 wrapper)
             claude-jobs-view-scan-program)))
     (make-directory state-dir t)
     (make-directory jobs-dir t)
     (make-directory projects-dir t)
     (claude-jobs-view--clear-caches)
     (unwind-protect
         (progn ,@body)
       (claude-jobs-view--clear-caches)
       (delete-directory tmp t))))

(defun cjv-test--write-file (path content)
  (make-directory (file-name-directory path) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file path
      (insert content))))

;;;; 1. Pure Sexp Parsing & Malformed Output Rejection

(ert-deftest cjv-parse-scan-output-valid-and-malformed ()
  (let ((parsed (claude-jobs-view--parse-scan-output
                 "(:sessions ((:sid \"u1\" :pid 12 :live-pids (12) :state \"alive\" :resumed nil :agent \"-\" :started \"2026\" :cwd \"/tmp\" :transcript-path nil :first-user-text nil)) :daemons ())\n")))
    (should (plistp parsed))
    (should (= (length (plist-get parsed :sessions)) 1))
    (should (null (plist-get parsed :daemons))))
  (should (equal (claude-jobs-view--parse-scan-output "(:sessions () :daemons ())")
                 '(:sessions () :daemons ())))
  (should-not (claude-jobs-view--parse-scan-output ""))
  (should-not (claude-jobs-view--parse-scan-output "error: boom"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions () :daemons ()) trailing"))
  (should-not (claude-jobs-view--parse-scan-output "(1 2 3)"))
  ;; Corrupt inner session/daemon elements must be rejected.
  (should-not (claude-jobs-view--parse-scan-output "(:sessions (\"bad\") :daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions ((:sid 123)) :daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions ((:sid \"u1\" :pid \"bad\" :live-pids ())) :daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions ((:sid \"u1\" :pid 1 :live-pids (\"x\"))) :daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions ((:sid \"u1\" :pid 1 :live-pids (1 . 2))) :daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions ((:sid \"u1\" :pid 1 :live-pids () :state 99)) :daemons ())"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions () :daemons (\"bad\"))"))
  (should-not (claude-jobs-view--parse-scan-output "(:sessions () :daemons ((:short 123)))")))

(ert-deftest cjv-parse-uuid-output-valid-nil-and-corrupt ()
  (should (equal (claude-jobs-view--parse-uuid-output "nil\n") '(ok . nil)))
  (let ((hit (claude-jobs-view--parse-uuid-output
              "(:sid \"abc\" :pid 1 :live-pids () :state \"dead\" :resumed nil :agent \"-\" :started \"\" :cwd nil :transcript-path nil :first-user-text nil)\n")))
    (should (eq (car hit) 'ok))
    (should (equal (plist-get (cdr hit) :sid) "abc")))
  (should-not (claude-jobs-view--parse-uuid-output ""))
  (should-not (claude-jobs-view--parse-uuid-output "error: bad"))
  (should-not (claude-jobs-view--parse-uuid-output "(:pid 1)"))
  (should-not (claude-jobs-view--parse-uuid-output "(:sid \"u1\" :pid \"bad\" :live-pids ())"))
  (should-not (claude-jobs-view--parse-uuid-output "nil trailing")))

;;;; 2. Entry Building, Faces & Legacy `jobctl list' Regex Fix

(ert-deftest cjv-entries-from-scan-renders-resumed-and-daemons ()
  (cjv-test--with-env nil
    (let* ((scan
            '(:sessions
              ((:sid "11111111-2222-3333-4444-555555555555"
                :pid 100
                :live-pids (100 202)
                :state "alive"
                :resumed t
                :agent "my-agent"
                :started "2026-11-25T01:02:03+08:00"
                :cwd "/tmp/p"
                :transcript-path "/tmp/p/t.jsonl"
                :first-user-text "line1\n  line2"))
              :daemons
              ((:short "d1" :state "running" :updated "2026-11-25T00:00:00Z"
                :intent "hello\nworld" :raw-intent "hello\nworld full" :name "n1" :cwd "/tmp")
               (:short "d2" :state "done" :updated "2026-11-25T00:00:01Z"
                :intent "" :raw-intent "" :name "n2" :cwd nil))))
           (entries (claude-jobs-view--entries-from-scan scan)))
      (should (= (length entries) 3))
      (let* ((d1 (nth 0 entries))
             (d2 (nth 1 entries))
             (s1 (nth 2 entries))
             (v1 (cadr d1))
             (v2 (cadr d2))
             (vs (cadr s1)))
        (should (equal (car d1) '(daemon . "d1")))
        (should (eq (get-text-property 0 'face (aref v1 2)) 'claude-jobs-view-alive-face))
        (should (equal (substring-no-properties (aref v1 3)) "—"))
        (should (equal (substring-no-properties (aref v1 5)) "hello world"))
        (should (equal (get-text-property 0 'help-echo (aref v1 5)) "hello\nworld full"))
        (should (eq (get-text-property 0 'face (aref v2 2)) 'claude-jobs-view-dead-face))
        (should (equal (substring-no-properties (aref v2 5)) "—"))
        (should (equal (car s1) '(session . "11111111-2222-3333-4444-555555555555")))
        (should (equal (substring-no-properties (aref vs 2)) "alive,resumed"))
        (should (eq (get-text-property 0 'face (aref vs 2)) 'claude-jobs-view-alive-face))
        (should (equal (substring-no-properties (aref vs 3)) "100,202"))
        (should (equal (substring-no-properties (aref vs 4)) "2026-11-25T01:02:03+08:00"))
        (should (equal (substring-no-properties (aref vs 5)) "line1 line2"))
        (should (equal (get-text-property 0 'help-echo (aref vs 5)) "line1\n  line2"))))))

(ert-deftest cjv-entries-from-scan-resumed-requires-alive ()
  (cjv-test--with-env nil
    (let* ((scan
            '(:sessions
              ((:sid "dead-resumed-1111-2222-3333-444444444444"
                :pid 100
                :live-pids ()
                :state "dead"
                :resumed t
                :agent "-"
                :started "2026-11-25T01:02:03+08:00"
                :cwd "/tmp/p"
                :transcript-path nil
                :first-user-text nil))
              :daemons ()))
           (entries (claude-jobs-view--entries-from-scan scan))
           (vs (cadr (car entries))))
      (should (equal (substring-no-properties (aref vs 2)) "dead"))
      (should (eq (get-text-property 0 'face (aref vs 2)) 'claude-jobs-view-dead-face)))))

(ert-deftest cjv-legacy-parse-session-rx-handles-agent-and-resumed ()
  (cjv-test--with-env nil
    (let* ((raw (concat
                 "=== jobctl-dispatched sessions (/tmp/state) ===\n"
                 "SID  PID(STATE)  AGENT  STARTED\n"
                 "0a1c0e77-b1d7-47ac-b6d5-bff6a3d128db  pid=58855(dead)  style-test-default   2026-05-14T22:47:33+08:00\n"
                 "11111111-2222-3333-4444-555555555555  pid=101,202(alive,resumed)  -  2026-11-25T09:00:00+08:00\n"
                 "22222222-3333-4444-5555-666666666666  pid=77(alive)  2026-11-25T10:00:00+08:00\n"))
           (entries (claude-jobs-view--parse raw)))
      (should (= (length entries) 3))
      (let ((e0 (cadr (nth 0 entries)))
            (e1 (cadr (nth 1 entries)))
            (e2 (cadr (nth 2 entries))))
        (should (equal (substring-no-properties (aref e0 4)) "2026-05-14T22:47:33+08:00"))
        (should (equal (substring-no-properties (aref e1 2)) "alive,resumed"))
        (should (eq (get-text-property 0 'face (aref e1 2)) 'claude-jobs-view-alive-face))
        (should (equal (substring-no-properties (aref e1 3)) "101,202"))
        (should (equal (substring-no-properties (aref e1 4)) "2026-11-25T09:00:00+08:00"))
        (should (equal (substring-no-properties (aref e2 4)) "2026-11-25T10:00:00+08:00"))))))

;;;; 3. Full Scan Integration, Cache Hits, --uuid Miss & Delete Invalidation

(ert-deftest cjv-full-scan-cache-hit-and-delete ()
  (cjv-test--with-env t
    (let* ((sid1 "aaaaaaaa-1111-2222-3333-444444444444")
           (sid2 "bbbbbbbb-1111-2222-3333-444444444444")
           (proc1 (make-process
                   :name "cjv-dummy-live"
                   :command (list "python3" "-c" "import time; time.sleep(30)"
                                  "--session-id" sid1)
                   :noquery t))
           (pid1 (process-id proc1)))
      (unwind-protect
          (progn
            ;; Wait briefly for /proc/<pid>/cmdline to expose args.
            (let ((deadline (+ (float-time) 2.0))
                  (cmdline-file (format "/proc/%d/cmdline" pid1)))
              (while (and (< (float-time) deadline)
                          (not (and (file-readable-p cmdline-file)
                                    (with-temp-buffer
                                      (insert-file-contents-literally cmdline-file)
                                      (string-search sid1 (buffer-string))))))
                (sleep-for 0.01)))
            ;; Session 1: live, printf '%q' escaped cwd/agent, dotfile project dir.
            (cjv-test--write-file
             (expand-file-name (concat sid1 ".meta") state-dir)
             (format "sid=%s\npid=%d\ncwd=/tmp/my.dot\\ dir\nagent=my\\ agent\nstarted=2026-11-25T01:00:00+08:00\n"
                     sid1 pid1))
            (cjv-test--write-file
             (expand-file-name (format "-tmp-my-dot-dir/%s.jsonl" sid1) projects-dir)
             "{\"type\":\"user\",\"cwd\":\"/tmp/my.dot dir\",\"message\":{\"content\":\"first\\nsecond\"}}\r\n")
            ;; Session 2: dead, no cwd in meta, array content after tool_result in unrelated dir.
            (cjv-test--write-file
             (expand-file-name (concat sid2 ".meta") state-dir)
             (format "sid=%s\npid=99999999\nagent=''\nstarted=2026-11-25T02:00:00+08:00\n" sid2))
            (cjv-test--write-file
             (expand-file-name (format "-other-dir/%s.jsonl" sid2) projects-dir)
             (concat
              "{\"type\":\"user\",\"cwd\":\"/tmp/fallback-proj\",\"message\":{\"content\":[{\"type\":\"tool_result\"}]}}\n"
              "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"array prompt\"}]}}\n"))
            ;; Orphan .out/.err without .meta.
            (cjv-test--write-file (expand-file-name "cccccccc-0000-0000-0000-000000000000.out" state-dir) "out")
            ;; Daemons: valid CJK 65 chars + pins.json + dir without state.json.
            (cjv-test--write-file (expand-file-name "pins.json" jobs-dir) "{}")
            (make-directory (expand-file-name "empty_daemon" jobs-dir) t)
            (cjv-test--write-file
             (expand-file-name "daem1/state.json" jobs-dir)
             (format "{\"daemonShort\":\"daem1\",\"state\":\"running\",\"updatedAt\":\"2026-11-25T03:00:00Z\",\"intent\":\"%s\",\"name\":\"n1\",\"cwd\":\"/tmp/d\"}"
                     (concat (make-string 60 ?中) "EXTRA")))

            ;; Run full scan once.
            (let ((entries (claude-jobs-view--entries)))
              (should (= (length entries) 3))
              (should (= (length (cjv-test--wrapper-runs)) 1))
              (let ((s1-row (seq-find (lambda (e) (equal (car e) (cons 'session sid1))) entries))
                    (s2-row (seq-find (lambda (e) (equal (car e) (cons 'session sid2))) entries))
                    (d-row  (seq-find (lambda (e) (equal (car e) '(daemon . "daem1"))) entries)))
                (should s1-row)
                (should (equal (substring-no-properties (aref (cadr s1-row) 2)) "alive"))
                (should (equal (substring-no-properties (aref (cadr s1-row) 5)) "first second"))
                (should (equal (get-text-property 0 'help-echo (aref (cadr s1-row) 5)) "first\nsecond"))
                (should s2-row)
                (should (equal (substring-no-properties (aref (cadr s2-row) 2)) "dead"))
                (should (equal (substring-no-properties (aref (cadr s2-row) 5)) "array prompt"))
                (should d-row)
                (should (= (length (substring-no-properties (aref (cadr d-row) 5))) 60))
                (should (string-suffix-p "EXTRA" (get-text-property 0 'help-echo (aref (cadr d-row) 5))))))

            ;; Inspecting `i' on cached session and daemon must execute 0 extra subprocesses!
            (save-window-excursion
              (claude-jobs-view--render-session-info sid1)
              (with-current-buffer (format "*claude-jobs info %s*" (claude-jobs-view--short sid1))
                (let ((txt (buffer-string)))
                  (should (string-search sid1 txt))
                  (should (string-search "/tmp/my.dot dir" txt))
                  (should (string-search "first\nsecond" txt))))
              (claude-jobs-view--render-daemon-info "daem1")
              (with-current-buffer "*claude-jobs info daem1*"
                (let ((txt (buffer-string)))
                  (should (string-search "name:     n1" txt))
                  (should (string-search "EXTRA" txt)))))
            (should (equal (claude-jobs-view--resolve-cwd sid2) "/tmp/fallback-proj"))
            (should (equal (claude-jobs-view--transcript-first-user-text sid2) "array prompt"))
            (should (string-suffix-p (concat sid1 ".jsonl") (claude-jobs-view--transcript-path sid1)))
            (should (= (length (cjv-test--wrapper-runs)) 1))

            ;; Verify `p' and `c' and `o' use cached metadata with 0 extra subprocesses.
            (let ((buf (get-buffer-create "*cjv-test-list*")))
              (unwind-protect
                  (with-current-buffer buf
                    (claude-jobs-view-mode)
                    (setq tabulated-list-entries (claude-jobs-view--entries))
                    (tabulated-list-print)
                    ;; Still only 1 scan? Wait: calling --entries above ran scan a 2nd time.
                    ;; Check `p' and `c' on sid1 without any extra scan!
                    (let ((runs-before (length (cjv-test--wrapper-runs))))
                      (goto-char (point-min))
                      (while (and (not (eobp))
                                  (not (equal (tabulated-list-get-id) (cons 'session sid1))))
                        (forward-line 1))
                      (should (equal (tabulated-list-get-id) (cons 'session sid1)))
                      (claude-jobs-view-copy-path)
                      (should (string-suffix-p (concat sid1 ".jsonl") (car kill-ring)))
                      (claude-jobs-view-copy-cwd)
                      (should (equal (car kill-ring) "/tmp/my.dot dir"))
                      (should (= (length (cjv-test--wrapper-runs)) runs-before)))
                    ;; Delete session 2 via `claude-jobs-view-delete' invalidates cache.
                    (goto-char (point-min))
                    (while (and (not (eobp))
                                (not (equal (tabulated-list-get-id) (cons 'session sid2))))
                      (forward-line 1))
                    (should (equal (tabulated-list-get-id) (cons 'session sid2)))
                    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                              ((symbol-function 'claude-jobs-view--jobctl-string) (lambda (&rest _) "")))
                      (claude-jobs-view-delete))
                    (should-not (gethash sid2 claude-jobs-view--session-cache))
                    (should-not (file-exists-p (expand-file-name (concat sid2 ".meta") state-dir))))
                (when (buffer-live-p buf) (kill-buffer buf)))))
        (when (process-live-p proc1)
          (delete-process proc1))))))

(ert-deftest cjv-uuid-lookup-on-cache-miss ()
  (cjv-test--with-env t
    (let ((sid "dddddddd-1111-2222-3333-444444444444"))
      (cjv-test--write-file
       (expand-file-name (concat sid ".meta") state-dir)
       (format "sid=%s\npid=123\ncwd=/tmp/u\nstarted=2026-11-25T04:00:00+08:00\n" sid))
      (cjv-test--write-file
       (expand-file-name (format "-tmp-u/%s.jsonl" sid) projects-dir)
       "{\"type\":\"user\",\"message\":{\"content\":\"uuid lookup text\"}}\n")
      ;; Cache is empty: each helper resolves via --uuid, populating cache on first call.
      (should (equal (claude-jobs-view--resolve-cwd sid) "/tmp/u"))
      (let ((runs (cjv-test--wrapper-runs)))
        (should (= (length runs) 1))
        (should (string-search (concat "--uuid " sid) (car runs))))
      ;; Subsequent --transcript-first-user-text hits cache (still 1 run).
      (should (equal (claude-jobs-view--transcript-first-user-text sid) "uuid lookup text"))
      (should (= (length (cjv-test--wrapper-runs)) 1))
      ;; Missing UUID returns nil cleanly without throwing.
      (should-not (claude-jobs-view--resolve-cwd "00000000-0000-0000-0000-000000000000")))))

;;;; 4. Missing Binary Fallback & One-Time Build Hint

(ert-deftest cjv-missing-binary-logs-one-time-hint-and-falls-back ()
  (cjv-test--with-env nil
    (let* ((stub-dir (make-temp-file "cjv-stub-" t))
           (stub-jobctl (expand-file-name "jobctl" stub-dir))
           (claude-jobs-view-scan-program "/nonexistent/claude-jobs-scan")
           (claude-jobs-view-jobctl-program stub-jobctl)
           (claude-jobs-view--scan-hinted nil)
           (messages-captured '()))
      (unwind-protect
          (progn
            (cjv-test--write-file
             stub-jobctl
             "#!/bin/sh\necho '=== Daemon jobs ==='\necho 'SHORT STATE UPDATED INTENT'\necho 'ab12 done 2026-11-25T00:00:00Z stub intent'\n")
            (set-file-modes stub-jobctl #o755)
            (cl-letf (((symbol-function 'message)
                       (lambda (fmt &rest args)
                         (push (apply #'format fmt args) messages-captured))))
              (let ((entries1 (claude-jobs-view--entries))
                    (entries2 (claude-jobs-view--entries)))
                (should (= (length entries1) 1))
                (should (= (length entries2) 1))
                (should (equal (car (car entries1)) '(daemon . "ab12")))
                (let ((hints (seq-filter
                              (lambda (m) (string-search "make -C rust/claude-jobs-scan" m))
                              messages-captured)))
                  (should (= (length hints) 1))))))
        (delete-directory stub-dir t)))))

;;;; 5. `init-ai.el' / `gptel' Helper & Tool Compatibility

(ert-deftest cjv-init-ai-helpers-compatible ()
  (cjv-test--with-env t
    (let* ((sid "eeeeeeee-1111-2222-3333-444444444444")
           (stub-dir (make-temp-file "cjv-jobctl-" t))
           (stub-jobctl (expand-file-name "jobctl" stub-dir))
           (claude-jobs-view-jobctl-program stub-jobctl)
           (tpath (expand-file-name (format "-tmp-ai/%s.jsonl" sid) projects-dir)))
      (unwind-protect
          (progn
            (cjv-test--write-file
             stub-jobctl
             (format "#!/bin/sh\nif [ \"$1\" = list ]; then\n  echo '=== jobctl-dispatched sessions ==='\n  exit 0\nfi\nif [ \"$1\" = path ]; then\n  echo %s\n  exit 0\nfi\nexit 1\n"
                     (shell-quote-argument tpath)))
            (set-file-modes stub-jobctl #o755)
            (cjv-test--write-file
             (expand-file-name (concat sid ".meta") state-dir)
             (format "sid=%s\npid=1\ncwd=/tmp/ai\nstarted=2026-11-25T05:00:00+08:00\n" sid))
            (cjv-test--write-file
             tpath
             "{\"type\":\"user\",\"message\":{\"content\":\"ai prompt\"}}\n")
            (should (string-search "jobctl-dispatched sessions" (claude-jobs-view--run-list)))
            (should (equal (claude-jobs-view--resolve-cwd sid) "/tmp/ai"))
            (should (equal (claude-jobs-view--transcript-first-user-text sid) "ai prompt"))
            (should (equal (claude-jobs-view--jobctl-string "path" sid) tpath)))
        (delete-directory stub-dir t)))))

(ert-deftest cjv-optional-gptel-tools-smoke ()
  (let ((gptel-dirs (file-expand-wildcards (expand-file-name "elpa/gptel-*" cjv-test--root))))
    (skip-unless gptel-dirs)
    (cjv-test--with-env t
      (let* ((sid "ffffffff-1111-2222-3333-444444444444")
             (stub-dir (make-temp-file "cjv-gptel-" t))
             (stub-jobctl (expand-file-name "jobctl" stub-dir))
             (claude-jobs-view-jobctl-program stub-jobctl)
             (tpath (expand-file-name (format "-tmp-gptel/%s.jsonl" sid) projects-dir))
             (orig-ued user-emacs-directory)
             (orig-pud package-user-dir)
             (orig-ensure (and (boundp 'use-package-always-ensure)
                               use-package-always-ensure)))
        (unwind-protect
            (progn
              (setq user-emacs-directory (file-name-as-directory stub-dir)
                    package-user-dir (expand-file-name "elpa" cjv-test--root))
              (package-initialize)
              (require 'use-package)
              (setq use-package-always-ensure nil)
              (require 'init-ai)
              (require 'gptel)
              (cjv-test--write-file
               stub-jobctl
               (format "#!/bin/sh\nif [ \"$1\" = list ]; then echo 'OK-LIST'; exit 0; fi\nif [ \"$1\" = path ]; then echo %s; exit 0; fi\nexit 1\n"
                       (shell-quote-argument tpath)))
              (set-file-modes stub-jobctl #o755)
              (cjv-test--write-file
               (expand-file-name (concat sid ".meta") state-dir)
               (format "sid=%s\npid=1\ncwd=/tmp/gptel\nstarted=2026-11-25T06:00:00+08:00\n" sid))
              (cjv-test--write-file
               tpath
               "{\"type\":\"user\",\"message\":{\"content\":\"gptel hello\"}}\n")
              (let ((list-tool (gptel-get-tool '("fenrir" "claude_jobs_list")))
                    (info-tool (gptel-get-tool '("fenrir" "claude_job_info"))))
                (should list-tool)
                (should info-tool)
                (should (equal (funcall (gptel-tool-function list-tool)) "OK-LIST\n"))
                (let ((info (funcall (gptel-tool-function info-tool) sid)))
                  (should (string-search "/tmp/gptel" info))
                  (should (string-search tpath info))
                  (should (string-search "gptel hello" info)))))
          (setq user-emacs-directory orig-ued
                package-user-dir orig-pud
                use-package-always-ensure orig-ensure)
          (delete-directory stub-dir t))))))

(ert-deftest cjv-corrupt-inner-scan-falls-back-without-cache-pollution ()
  (cjv-test--with-env nil
    (let* ((stub-dir (make-temp-file "cjv-corrupt-" t))
           (bad-scan (expand-file-name "bad-scan" stub-dir))
           (stub-jobctl (expand-file-name "jobctl" stub-dir))
           (claude-jobs-view-scan-program bad-scan)
           (claude-jobs-view-jobctl-program stub-jobctl))
      (unwind-protect
          (progn
            (cjv-test--write-file
             stub-jobctl
             "#!/bin/sh\necho '=== Daemon jobs ==='\necho 'SHORT STATE UPDATED INTENT'\necho 'fb01 done 2026-11-25T00:00:00Z fallback ok'\n")
            (set-file-modes stub-jobctl #o755)
            (dolist (payload '("(:sessions (\"bad\") :daemons ())"
                               "(:sessions ((:sid 123)) :daemons ())"))
              (cjv-test--write-file
               bad-scan
               (format "#!/bin/sh\nprintf '%%s\\n' '%s'\n" payload))
              (set-file-modes bad-scan #o755)
              (let ((entries (claude-jobs-view--entries)))
                (should (= (length entries) 1))
                (should (equal (car (car entries)) '(daemon . "fb01")))
                (should (zerop (hash-table-count claude-jobs-view--session-cache)))
                (should (zerop (hash-table-count claude-jobs-view--daemon-cache))))))
        (delete-directory stub-dir t)))))

(ert-deftest cjv-entries-fallback-clears-stale-caches ()
  (cjv-test--with-env t
    (let* ((sid "12121212-1111-2222-3333-444444444444")
           (stub-dir (make-temp-file "cjv-fb-" t))
           (fail-scan (expand-file-name "fail-scan" stub-dir))
           (stub-jobctl (expand-file-name "jobctl" stub-dir))
           (claude-jobs-view-jobctl-program stub-jobctl))
      (unwind-protect
          (progn
            (cjv-test--write-file
             (expand-file-name (concat sid ".meta") state-dir)
             (format "sid=%s\npid=1\ncwd=/tmp/fb\nstarted=2026-11-25T01:00:00+08:00\n" sid))
            (cjv-test--write-file
             (expand-file-name "d99/state.json" jobs-dir)
             "{\"daemonShort\":\"d99\",\"state\":\"done\",\"updatedAt\":\"2026-11-25T01:00:00Z\",\"intent\":\"hi\"}")
            (should (= (length (claude-jobs-view--entries)) 2))
            (should (= (hash-table-count claude-jobs-view--session-cache) 1))
            (should (= (hash-table-count claude-jobs-view--daemon-cache) 1))
            ;; Delete files and force fallback to jobctl list.
            (delete-file (expand-file-name (concat sid ".meta") state-dir))
            (cjv-test--write-file fail-scan "#!/bin/sh\nexit 1\n")
            (set-file-modes fail-scan #o755)
            (cjv-test--write-file
             stub-jobctl
             "#!/bin/sh\necho '=== Daemon jobs ==='\necho 'SHORT STATE UPDATED INTENT'\n")
            (set-file-modes stub-jobctl #o755)
            (let ((claude-jobs-view-scan-program fail-scan))
              (should (null (claude-jobs-view--entries)))
              (should (zerop (hash-table-count claude-jobs-view--session-cache)))
              (should (zerop (hash-table-count claude-jobs-view--daemon-cache)))
              (should (null claude-jobs-view--cache-config))))
        (delete-directory stub-dir t)))))

(ert-deftest cjv-pruned-transcript-and-deleted-session-info ()
  (cjv-test--with-env t
    (let* ((sid-pruned "34343434-1111-2222-3333-444444444444")
           (sid-gone   "56565656-1111-2222-3333-444444444444")
           (tpath-pruned (expand-file-name (format "-tmp-pruned/%s.jsonl" sid-pruned) projects-dir))
           (tpath-gone   (expand-file-name (format "-tmp-gone/%s.jsonl" sid-gone) projects-dir)))
      (cjv-test--write-file
       (expand-file-name (concat sid-pruned ".meta") state-dir)
       (format "sid=%s\npid=99999991\ncwd=/tmp/pruned\nstarted=2026-11-25T01:00:00+08:00\n" sid-pruned))
      (cjv-test--write-file
       tpath-pruned
       "{\"type\":\"user\",\"message\":{\"content\":\"dead prompt\"}}\n")
      (cjv-test--write-file
       (expand-file-name (concat sid-gone ".meta") state-dir)
       (format "sid=%s\npid=99999992\ncwd=/tmp/gone\nstarted=2026-11-25T02:00:00+08:00\n" sid-gone))
      (cjv-test--write-file
       tpath-gone
       "{\"type\":\"user\",\"message\":{\"content\":\"gone prompt\"}}\n")
      ;; Populate cache via full scan.
      (should (= (length (claude-jobs-view--entries)) 2))
      (should (= (length (cjv-test--wrapper-runs)) 1))
      ;; Prune only the transcript on disk for sid-pruned, then inspect `i' BEFORE `o`/`p'.
      (delete-file tpath-pruned)
      (save-window-excursion
        (claude-jobs-view--render-session-info sid-pruned)
        (with-current-buffer (format "*claude-jobs info %s*" (claude-jobs-view--short sid-pruned))
          (let ((txt (buffer-string)))
            (should (string-search "/tmp/pruned" txt))
            (should (string-search "transcript:  (unresolved)" txt))
            (should (string-search "(none — transcript empty or unparseable)" txt)))))
      (should (= (length (cjv-test--wrapper-runs)) 2))
      (should-not (claude-jobs-view--transcript-path sid-pruned))
      (should-not (claude-jobs-view--transcript-first-user-text sid-pruned))
      ;; Delete both .meta and .jsonl for sid-gone -> `i' must evict cache and show (not resolved)/(unresolved).
      (delete-file (expand-file-name (concat sid-gone ".meta") state-dir))
      (delete-file tpath-gone)
      (save-window-excursion
        (claude-jobs-view--render-session-info sid-gone)
        (with-current-buffer (format "*claude-jobs info %s*" (claude-jobs-view--short sid-gone))
          (let ((txt (buffer-string)))
            (should (string-search "cwd:         (not resolved)" txt))
            (should (string-search "transcript:  (unresolved)" txt))
            (should (string-search "(none — transcript empty or unparseable)" txt)))))
      (should-not (gethash sid-gone claude-jobs-view--session-cache))
      (should-not (claude-jobs-view--resolve-cwd sid-gone)))))

(ert-deftest cjv-updated-column-sorts-chronologically-across-timezones ()
  (cjv-test--with-env nil
    (let ((buf (get-buffer-create "*cjv-sort-test*")))
      (unwind-protect
          (with-current-buffer buf
            (claude-jobs-view-mode)
            (setq tabulated-list-entries
                  (list
                   ;; 06:00:00Z in +08:00
                   (list '(session . "s-14plus08")
                         ["session" "s14" "dead" "1" "2026-11-25T14:00:00+08:00" "older"])
                   ;; 07:00:00Z (1 hour newer than 14:00+08:00!)
                   (list '(daemon . "d-07z")
                         ["daemon" "d07" "running" "—" "2026-11-25T07:00:00Z" "newest"])
                   ;; 05:30:00Z (oldest valid)
                   (list '(daemon . "d-0530z")
                         ["daemon" "d05" "done" "—" "2026-11-25T05:30:00Z" "oldest"])
                   ;; Unparseable / empty fallback
                   (list '(session . "s-dash")
                         ["session" "sdash" "dead" "2" "—" "no-ts"])))
            (tabulated-list-print)
            (let ((ids '()))
              (goto-char (point-min))
              (while (not (eobp))
                (when-let ((id (tabulated-list-get-id)))
                  (push id ids))
                (forward-line 1))
              (should (equal (nreverse ids)
                             '((daemon . "d-07z")
                               (session . "s-14plus08")
                               (daemon . "d-0530z")
                               (session . "s-dash")))))
            ;; Ascending order should reverse cleanly.
            (setq tabulated-list-sort-key '("UPDATED" . nil))
            (tabulated-list-print)
            (let ((ids '()))
              (goto-char (point-min))
              (while (not (eobp))
                (when-let ((id (tabulated-list-get-id)))
                  (push id ids))
                (forward-line 1))
              (should (equal (nreverse ids)
                             '((session . "s-dash")
                               (daemon . "d-0530z")
                               (session . "s-14plus08")
                               (daemon . "d-07z"))))))
        (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest cjv-tier5-octal-control-chars-and-unresolved-gt4 ()
  "Tier 5 (R1): Verify octal control escapes (\\0010, \\1777), = in cwd, and >4 unresolved transcripts."
  (cjv-test--with-env t
    (let ((sids (cl-loop for i from 1 to 6
                         collect (format "11111111-1111-4111-8111-00000000000%d" i))))
      (cl-loop for sid in sids for i from 1 do
               (cjv-test--write-file
                (expand-file-name (concat sid ".meta") state-dir)
                (if (= i 1)
                    (format "sid=%s\npid=bad\ncwd=$'/tmp/a=b\\0010\\1777'\nstarted=2026-11-25T01:00:00\n" sid)
                  (format "sid=%s\npid=9999%d\nstarted=2026-11-25T0%d:00:00Z\n" sid i i)))
               (let ((subdir (if (<= i 3) "sub1" "sub2")))
                 (cjv-test--write-file
                  (expand-file-name (format "%s/%s.jsonl" subdir sid) projects-dir)
                  (if (= i 1)
                      "{\"type\":\"user\",\"message\":{\"content\":\"ctrl:\\u00010:\\u007f7:ok\"}}\n"
                    (format "{\"type\":\"user\",\"cwd\":\"/tmp/p=%d\",\"message\":{\"content\":\"prompt %d\"}}\n" i i)))))
      ;; Orphan transcript without .meta resolved via --uuid
      (let ((orphan "99999999-9999-4999-8999-000000000099"))
        (cjv-test--write-file
         (expand-file-name (format "sub2/%s.jsonl" orphan) projects-dir)
         "{\"type\":\"user\",\"cwd\":\"/tmp/orphan\",\"message\":{\"content\":\"orphan prompt\"}}\n")
        (let ((entries (claude-jobs-view--entries)))
          (should (= (length entries) 6))
          (let ((s1 (gethash (car sids) claude-jobs-view--session-cache))
                (s6 (gethash (nth 5 sids) claude-jobs-view--session-cache)))
            (should s1)
            (should (equal (plist-get s1 :cwd) "/tmp/a=b\0010\1777"))
            (should (equal (plist-get s1 :first-user-text) "ctrl:\0010:\1777:ok"))
            (should (string-suffix-p ":ok" (plist-get s1 :first-user-text)))
            (should s6)
            (should (equal (plist-get s6 :cwd) "/tmp/p=6"))))
        (should (equal (claude-jobs-view--resolve-cwd orphan) "/tmp/orphan"))
        (should (equal (claude-jobs-view--transcript-first-user-text orphan) "orphan prompt"))))))

(ert-deftest cjv-tier5-compare-updated-no-tz-and-subsecond ()
  "Tier 5 (R1): Verify `claude-jobs-view--compare-updated' handles missing TZ and deterministic subsecond ties."
  (should (claude-jobs-view--compare-updated
           (list '(session . "a") ["session" "a" "dead" "1" "2026-11-25T10:00:00.100Z" ""])
           (list '(session . "b") ["session" "b" "dead" "2" "2026-11-25T10:00:00.500Z" ""])))
  (should-not (claude-jobs-view--compare-updated
               (list '(session . "b") ["session" "b" "dead" "2" "2026-11-25T10:00:00.500Z" ""])
               (list '(session . "a") ["session" "a" "dead" "1" "2026-11-25T10:00:00.100Z" ""])))
  ;; No-TZ ISO-8601 parses and sorts after empty/unparseable
  (should (claude-jobs-view--compare-updated
           (list '(session . "empty") ["session" "e" "dead" "1" "—" ""])
           (list '(session . "notz")  ["session" "n" "dead" "2" "2026-11-25T10:00:00" ""]))))

(provide 'claude-jobs-view-test)
;;; claude-jobs-view-test.el ends here
