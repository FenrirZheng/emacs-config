;;; bench.el --- 驗收條件 3: wall time of the class-index step on the fixture -*- lexical-binding: t; -*-

;; emacs -Q --batch -l sliced-spec/2026-10-13/215104-libsrc-rust-class-lister/bench.el
;;
;; Run from the repo root, with the helper built (make -C rust/libsrc-classes).
;; Input: the `:jars' of kjw-web's state file.  One warm-up, then 5 timed runs of
;;   helper  -- `call-process' of the helper with its output discarded (helper
;;              alone: no Emacs decoding of the 2.7 MB form);
;;   step    -- the engine's own async `fenrir/libsrc--run' of the helper, from
;;              process start to `fenrir/libsrc--parse-classes-output' returning
;;              the index (state-file writing and the build-file walk excluded).
;; Prints both medians and the 2026-10-13 baseline; exit 1 when a limit is missed.
;; Nothing is written outside a temp buffer.

(add-to-list 'load-path (expand-file-name "lisp/languages"))
(require 'fenrir-libsrc)

(defconst bench-state-file
  (expand-file-name "~/.cache/fenrir-libsrc/proj/0c3182fdef74a5edb107922b61083d9364653696.eld"))
(defconst bench-runs 5)
(defconst bench-step-limit 0.200)
(defconst bench-helper-limit 0.100)
(defconst bench-baseline "0.79 s (unzip loop 0.39 s + Elisp parse 0.40 s, measured 2026-10-13)")

(defun bench-median (xs)
  (nth (/ (length xs) 2) (sort (copy-sequence xs) #'<)))

(defun bench-helper (jars)
  "Seconds for one run of the helper alone, its output discarded."
  (let ((t0 (float-time))
        (exit (apply #'call-process fenrir/libsrc-classes-program nil nil nil jars)))
    (unless (eq exit 0) (error "helper exited %s" exit))
    (- (float-time) t0)))

(defun bench-step (root jars)
  "Seconds from process start to the parsed index, via the engine's runner.
Returns (SECONDS . CLASS-COUNT)."
  (let* ((t0 (float-time)) done (deadline (+ t0 60)))
    (fenrir/libsrc--run
     "classes" (cons fenrir/libsrc-classes-program jars) root
     (lambda (exit output)
       (let ((parsed (and (eq exit 0) (fenrir/libsrc--parse-classes-output output))))
         (unless parsed (error "helper output did not parse (exit %s)" exit))
         (setq done (cons (- (float-time) t0) (hash-table-count (car parsed))))))
     (lambda (msg) (error "step failed: %s" msg)))
    (while (and (not done) (< (float-time) deadline))
      (accept-process-output nil 0.005))
    (or done (error "step timed out"))))

(let* ((st (with-temp-buffer (insert-file-contents bench-state-file) (read (current-buffer))))
       (root (plist-get st :root))
       (jars (plist-get st :jars))
       (inhibit-message t)
       helper step classes)
  (unless (file-executable-p fenrir/libsrc-classes-program)
    (error "helper not built: make -C rust/libsrc-classes"))
  ;; warm-up: page cache, process start-up
  (bench-helper jars)
  (bench-step root jars)
  (dotimes (_ bench-runs)
    (push (bench-helper jars) helper)
    (let ((r (bench-step root jars)))
      (push (car r) step)
      (setq classes (cdr r))))
  (let ((inhibit-message nil)
        (mh (bench-median helper))
        (ms (bench-median step)))
    (message "input: %d jars, %d classes (%s)" (length jars) classes bench-state-file)
    (message "helper alone: median %.0f ms over %d runs %S (limit %.0f ms)"
             (* 1000 mh) bench-runs (mapcar (lambda (x) (round (* 1000 x))) (reverse helper))
             (* 1000 bench-helper-limit))
    (message "whole step:   median %.0f ms over %d runs %S (limit %.0f ms)"
             (* 1000 ms) bench-runs (mapcar (lambda (x) (round (* 1000 x))) (reverse step))
             (* 1000 bench-step-limit))
    (message "baseline:     %s" bench-baseline)
    (let ((ok (and (<= mh bench-helper-limit) (<= ms bench-step-limit))))
      (message (if ok "WITHIN LIMITS" "LIMIT MISSED"))
      (kill-emacs (if ok 0 1)))))

;;; bench.el ends here
