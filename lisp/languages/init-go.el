;;; init-go.el --- Go: go-ts-mode + gopls -*- lexical-binding: t; -*-

;;; Commentary:
;; Go language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter / combobulate infrastructure lives
;; in [`lisp/init-languages.el'](../init-languages.el); this module only adds
;; the Go mode hooks and gopls' per-server workspace configuration.
;;
;; See also [`_doc/GO.md'](../../_doc/GO.md) for the full Go workflow.

;;; Code:

;; `eglot-ensure' (autoloaded from the eglot package in init-languages.el) and
;; `combobulate-mode' (`:commands' autoload from the combobulate block there)
;; attach on `go-ts-mode'.  treesit-auto remaps .go files to `go-ts-mode'.
(add-hook 'go-ts-mode-hook #'eglot-ensure)
(add-hook 'go-ts-mode-hook #'combobulate-mode)

;; ggtags: GTAGS xref backend for Go buffers without a live gopls (e.g. a repo
;; with no go.mod at the resolved project root, where gopls declines to attach
;; but a GNU Global index exists -- e.g. ~/code/coinsasia/GTAGS).  Mirrors the
;; C/C++ and Python hooks; `ggtags-mode' is autoloaded from the declaration in
;; init-languages.el, where its M-. / C-M-. keymap takeover is also neutralized
;; so this only adds an xref backend and gopls keeps winning M-. when attached.
(add-hook 'go-ts-mode-hook #'ggtags-mode)

;; gopls: extra static analyses + the full inlay-hint set VSCode's Go
;; extension enables by default.  `staticcheck' folds the standalone tool's
;; checks into LSP diagnostics; `gofumpt' is stricter `gofmt' (apheleia /
;; `M-x eglot-format-buffer' both pick this up automatically).  Registered via
;; `with-eval-after-load' so the key is present in the shared
;; `eglot-workspace-configuration' alist before gopls connects.
(with-eval-after-load 'eglot
  (setf (alist-get :gopls eglot-workspace-configuration)
        '(:staticcheck t
          :gofumpt t
          :analyses (:unusedparams t
                     :shadow t
                     :unusedwrite t
                     :nilness t)
          :hints (:assignVariableTypes t
                  :compositeLiteralFields t
                  :compositeLiteralTypes t
                  :constantValues t
                  :functionTypeParameters t
                  :parameterNames t
                  :rangeVariableTypes t))))

;; ---------------------------------------------------------------------------
;; Single-test run/debug at point -- the "minimal operation" surface, mirroring
;; VSCode's "run test | debug test" CodeLens and GoLand's gutter Run/Debug:
;; cursor anywhere inside `func TestXxx' -> one chord runs OR debugs exactly
;; that function with zero further prompts.  Two sibling keys (`C-c t t' run,
;; `C-c t d' debug) keep run and debug equal-cost like the IDE gutter icons --
;; a `C-u'-for-debug prefix-arg would make debug a chord longer and is
;; invisible to muscle memory.  Both bound buffer-locally in `go-ts-mode-map'.

(defconst fenrir/go-test-func-re
  "\\`\\(Test\\|Benchmark\\|Fuzz\\|Example\\)[[:upper:][:digit:]_]"
  "A Go func name is a runnable test/benchmark/fuzz/example iff it matches.
The char class after the prefix is Go's own rule: `Test' must be followed
by a non-lowercase rune (`TestFoo' yes, `Testfoo' no), so a helper named
`testHelper' or a type `TestingUtils' isn't misdetected as a test func.")

(defun fenrir/go-enclosing-test-name ()
  "Return the enclosing Test/Benchmark/Fuzz/Example func name, or nil.
treesit-primary with a regex fallback for when `go-ts-mode' degrades or
point sits on the signature line itself."
  (or
   ;; treesit: climb to the `function_declaration', read its `name' field.
   ;; `treesit-parent-until's 3rd arg t returns the node itself when it already
   ;; matches -- needed when point is on the func_declaration node directly.
   (when (and (treesit-available-p) (treesit-language-at (point)))
     (when-let* ((fn (treesit-parent-until
                      (treesit-node-at (point))
                      (lambda (n) (string= (treesit-node-type n)
                                           "function_declaration"))
                      t))
                 (name (treesit-node-text
                        (treesit-node-child-by-field-name fn "name") t)))
       (and (string-match-p fenrir/go-test-func-re name) name)))
   ;; Fallback: nearest preceding `func TestXxx('.  `end-of-line' first so a
   ;; cursor anywhere ON the signature line still resolves (re-search-backward
   ;; from mid-line would skip past the very func we're inside).
   (save-excursion
     (end-of-line)
     (when (re-search-backward
            "^func[ \t]+\\(\\(?:Test\\|Benchmark\\|Fuzz\\|Example\\)[[:alnum:]_]*\\)[ \t]*("
            nil t)
       (match-string-no-properties 1)))))

(defun fenrir/go-package-dir ()
  "Absolute dir of the current Go buffer's package -- the delve `:program'.
NOT `dape-cwd': that returns `(project-root ...)' = the MODULE root, which
builds the wrong package for any test under a subdir (e.g. ./internal/foo/)
and then `-test.run' matches nothing."
  (if-let* ((f (buffer-file-name))) (file-name-directory f) default-directory))

(defun fenrir/go-debug-test ()
  "Debug the enclosing Go test under delve -- no re-prompt.
Calling `dape' with a fully-resolved plist skips the interactive menu; the
plist still flows through `dape-default-config-functions', so `:autoport' is
substituted to a free port (no fixed-port collision between two sessions)."
  (interactive)
  (let* ((name (or (fenrir/go-enclosing-test-name)
                   (user-error "No enclosing Test/Benchmark/Fuzz/Example at point")))
         (pkg  (fenrir/go-package-dir)))
    (dape
     (list 'modes '(go-ts-mode)
           'ensure 'dape-ensure-command
           'command "dlv"
           'command-args '("dap" "--listen" "127.0.0.1::autoport")
           'command-cwd pkg
           'command-insert-stderr t
           'port :autoport
           :type "go"
           :request "launch"
           :mode "test"
           :cwd pkg
           :program pkg
           ;; VECTOR, not list: dape serializes `:args' through `json-serialize',
           ;; which reads a bare list as an alist and throws `symbolp'.
           ;; `^...$' anchors so TestFoo doesn't also match TestFooBar.
           :args (vector "-test.run" (format "^%s$" name) "-test.v")))))

(defun fenrir/go-run-test ()
  "Run the enclosing Go test (no debugger) in its package dir via `compile'.
`-count=1' defeats the test cache; `-v' surfaces per-test output in
`compilation-mode' (jump to results with M-g M-n -- the `go-test' matcher
below makes both `--- PASS:' and `--- FAIL:' lines navigable).
`compilation-skip-threshold' is forced to 0 buffer-locally so `next-error'
steps onto info-level PASS lines too, not just FAIL/SKIP."
  (interactive)
  (let* ((name (or (fenrir/go-enclosing-test-name)
                   (user-error "No enclosing Test/Benchmark/Fuzz/Example at point")))
         ;; let-bound `default-directory' is what `compile' inherits, so
         ;; `go test ... .' builds the package owning this file, not the module
         ;; root -- same package-dir rule as the debug path.
         (default-directory (fenrir/go-package-dir)))
    ;; `compile' returns the compilation buffer; `next-error' reads
    ;; `compilation-skip-threshold' there, so a buffer-local 0 makes PASS lines
    ;; (TYPE info) steppable without lowering the global default for every
    ;; other `M-x compile'.
    (with-current-buffer (compile (format "go test -run '^%s$' -count=1 -v ." name))
      (setq-local compilation-skip-threshold 0))))

;; ---------------------------------------------------------------------------
;; Jump from a `go test -v' result line to the test's `func' definition.
;;
;; PROBLEM: `go test -v' prints `--- PASS: TestFoo (0.00s)' / `--- FAIL: ...'
;; lines that carry the test NAME but no `file:line', so `compilation-mode's
;; stock matchers can't make them navigable -- only the indented
;; `    foo_test.go:42:' assertion lines under a FAIL are clickable, and a
;; PASS has none at all.  We add a `go-test' matcher that resolves the test
;; name back to `func TestFoo' on disk, so RET / mouse-1 on the `--- PASS/FAIL'
;; line (and `next-error') lands on the test's definition.
;;
;; HOW: `compilation-error-regexp-alist' lets the FILE and LINE slots be
;; functions of no args that run against the just-matched regexp (and must
;; preserve its match data).  Ours read the captured name (subexp 4) and grep
;; the package's `*_test.go' siblings for `^func NAME(' -- `default-directory'
;; of the compilation buffer is the package dir (see `fenrir/go-package-dir'
;; in `fenrir/go-run-test'), so the scan is local and cheap.

(defconst fenrir/go-test--regexp
  "^[ \t]*--- \\(?:\\(FAIL\\)\\|\\(PASS\\)\\|\\(SKIP\\)\\): \\([^ \t]+\\)"
  "Match a `go test -v' result line.
Subexp 1/2/3 capture FAIL/PASS/SKIP (for the TYPE face); subexp 4 is the
test name -- possibly a subtest like `TestFoo/case'.  Leading `[ \t]*'
catches the indentation `go test' adds to nested subtest lines.")

(defun fenrir/go-test--func-location (name)
  "Find the Go test `func NAME' under `default-directory'.
Return (ABS-FILE . LINE) or nil.  NAME may carry a subtest suffix
\"TestFoo/case\" -- only the part before the first slash is the Go func,
so the parent and every child `--- FAIL:' line jump to the same `func'.
Scans only `*_test.go' siblings via a temp buffer (no buffer-list churn);
the trailing `(' in the search regexp stops `TestFoo' from matching
`func TestFooBar('."
  (let* ((func (car (split-string name "/")))
         (dir  default-directory)
         (re   (concat "^func[ \t]+" (regexp-quote func) "[ \t]*(")))
    (when (and dir (file-directory-p dir))
      (catch 'hit
        (dolist (f (directory-files dir t "_test\\.go\\'"))
          (with-temp-buffer
            (insert-file-contents f)
            (goto-char (point-min))
            (when (re-search-forward re nil t)
              (throw 'hit (cons f (line-number-at-pos (match-beginning 0)))))))
        nil))))

(defvar fenrir/go-test--loc-cache nil
  "1-entry memo `((NAME . DIR) . (FILE . LINE))' for the FILE/LINE matchers.
`compilation-error-properties' computes FILE first, then LINE, for the
SAME match -- a single slot lets each `--- PASS/FAIL:' line hit disk once
instead of twice.  Keyed by DIR too so identically-named tests in two
packages never cross-resolve.")

(defun fenrir/go-test--locate ()
  "Resolve subexp 4 of the current match to (FILE . LINE), or nil.
Memoized via `fenrir/go-test--loc-cache'.  Reads the match name BEFORE
`save-match-data' so the on-disk grep can clobber and restore match data
without disturbing the caller (`compilation-error-properties')."
  (let ((key (cons (match-string 4) default-directory)))
    (if (equal (car fenrir/go-test--loc-cache) key)
        (cdr fenrir/go-test--loc-cache)
      (let ((loc (save-match-data
                   (fenrir/go-test--func-location (car key)))))
        (setq fenrir/go-test--loc-cache (cons key loc))
        loc))))

(defun fenrir/go-test--file ()
  "FILE matcher: `(FILENAME)' of the matched test's `func', or nil."
  (let ((loc (fenrir/go-test--locate)))
    (and loc (list (car loc)))))

(defun fenrir/go-test--line ()
  "LINE matcher: line number of the matched test's `func', or nil."
  (let ((loc (fenrir/go-test--locate)))
    (and loc (cdr loc))))

;; Register globally: the regexp is specific to `go test -v' output (`--- FAIL:'
;; etc.), so it's inert in non-Go compilation buffers.  `setf (alist-get ...)'
;; updates in place -- re-evaluating this file won't stack duplicates.  TYPE
;; `(3 . 2)': SKIP(subexp 3) -> warning, PASS(subexp 2) -> info, else FAIL ->
;; error; HYPERLINK 4 makes the test name itself the clickable region.
;;
;; NOTE: PASS lines are info-level, which the default `compilation-skip-threshold'
;; (1) would skip during `M-g M-n' / `next-error' (RET / mouse-1 jump from them
;; regardless).  `fenrir/go-run-test' sets the threshold to 0 buffer-locally so
;; its buffers step onto PASS lines too; a `*compilation*' produced some other
;; way keeps the global default unless you `(setq compilation-skip-threshold 0)'.
(with-eval-after-load 'compile
  (setf (alist-get 'go-test compilation-error-regexp-alist-alist)
        (list fenrir/go-test--regexp
              #'fenrir/go-test--file
              #'fenrir/go-test--line
              nil               ; COLUMN: none on a `--- PASS/FAIL:' line
              '(3 . 2)          ; TYPE: (SKIP . PASS) -> warning/info, else error
              4))               ; HYPERLINK: highlight + click the test name
  (add-to-list 'compilation-error-regexp-alist 'go-test))

(with-eval-after-load 'go-ts-mode
  ;; Buffer-local `C-c t' prefix (run/debug).  Bound in `go-ts-mode-map' so it
  ;; never shadows a `C-c t' another major mode might want; `C-c .'/`r'/`f'/`h'
  ;; belong to Eglot, `C-c o' to combobulate, `C-x C-a' to dape's full menu.
  (define-key go-ts-mode-map (kbd "C-c t t") #'fenrir/go-run-test)
  (define-key go-ts-mode-map (kbd "C-c t d") #'fenrir/go-debug-test))

;; `go-test' menu entry for `M-x dape' (manual pick).  Replaces the old recipe,
;; which used `dape-cwd' for both cwd and `:program' (the subpackage bug above)
;; and a hard-coded port 55878 that blocked concurrent sessions, with no
;; `-test.run' scope at all.  `setf (alist-get ...)' updates in place so
;; re-evaluating this file doesn't stack duplicate entries.  The bare function
;; symbols `fenrir/go-package-dir' are funcall'd by dape at launch (see
;; `dape--config-eval-value'), so cwd/program track the current buffer.
(with-eval-after-load 'dape
  (setf (alist-get 'go-test dape-configs)
        '(modes (go-ts-mode)
          ensure dape-ensure-command
          command "dlv"
          command-args ("dap" "--listen" "127.0.0.1::autoport")
          command-cwd fenrir/go-package-dir
          command-insert-stderr t
          port :autoport
          :type "go"
          :request "launch"
          :mode "test"
          :cwd fenrir/go-package-dir
          :program fenrir/go-package-dir)))

(provide 'init-go)
;;; init-go.el ends here
