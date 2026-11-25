;;; init-org-roam.el --- org-roam Zettelkasten over ~/code/org-roam -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 14 of the pre-split monolithic init.el (see git log for the move).
;; ~/code/org-roam/ holds the .org notes converted from the Obsidian vault by
;; ~/code/obsidian-to-org-roam.py (re-runnable; see CONVERSION-REPORT.txt in
;; that directory).  org-roam adds an SQLite-backed link cache on top of plain
;; .org files: every note (a file with a top-level `:ID:' property) is a "node",
;; `[[id:...]]' links between them are bidirectional, and `org-roam-buffer'
;; shows the backlinks of whatever you're viewing.
;;
;; The original .md vault at ~/code/obsidian/ still exists on disk but is no
;; longer wired into Emacs -- init-obsidian.el / obsidian.el were removed, so
;; org-roam over the converted .org notes is now the only note system here.
;;
;; First run (the archive isn't refreshed at startup -- see init.el §1):
;;   M-x my/package-refresh  ->  restart Emacs  ->  M-x org-roam-db-sync
;; org-roam pulls in `emacsql'; Emacs 30's built-in SQLite covers it.
;;
;; `org-roam-graph' (M-x) renders a static link graph via Graphviz -- it needs
;; the `dot' binary (`apt install graphviz'); use `C-u M-x org-roam-graph' to
;; draw a local subgraph rather than all ~1400 nodes at once.  `org-roam-ui'
;; below is the nicer option for a vault this size: an interactive in-browser
;; D3 graph, no Graphviz required.

;;; Code:

(use-package org-roam
  :custom
  (org-roam-directory (file-truename "~/code/org-roam"))
  ;; What org-roam refuses to scan.  This deliberately REPLACES org-roam's
  ;; default rather than extending it.
  ;;
  ;; The default is `(list org-attach-id-dir)', i.e. "data/", meant to hide an
  ;; org-attach attachment store.  Matching is `string-match-p' against the path
  ;; RELATIVE to `org-roam-directory' and is UNANCHORED, so it drops every
  ;; `data/' segment anywhere in the tree.  In this vault `data/' is an ordinary
  ;; content directory name (a leftover of the Obsidian conversion), and that
  ;; default was silently hiding 138 .org files which all carry an :ID: -- 76
  ;; under codeVault/spring/data/, 40 under 日本/data/, plus 8 smaller dirs.
  ;; They existed on disk but were absent from `org-roam-node-find' and every DB
  ;; query, which is what made the node count trail kb_sweep's atom count by 9%.
  ;; Dropping the entry is safe here: verified 2026-08-20 that nothing in
  ;; ~/.emacs.d configures org-attach, no note carries :ATTACH_DIR: or an
  ;; `attachment:' link, and every */data/ dir holds ordinary titled notes
  ;; rather than a UUID-sharded attachment store.  Restore "data/" if org-attach
  ;; is ever adopted -- but anchor it as "\\`data/" so it hides only a
  ;; vault-root store.
  ;;
  ;; "\\`records/" IS anchored, so it matches only the vault's own top-level
  ;; records/ dir -- the wayfinder effort maps, grill snapshots and assets.
  ;; Those are project bookkeeping, not knowledge; and because that effort's
  ;; working repo IS this vault, leaving them scannable would register effort
  ;; files as roam nodes (the graph pollution the effort's destination grill
  ;; ruled out when it rejected an in-vault docs/adr/).
  (org-roam-file-exclude-regexp '("\\`records/"))
  ;; New note from `C-c r f' / `C-c r c': timestamp-${slug}.org with a #+title:
  ;; and a tag prompt.  `%(my/org-roam-prompt-filetags)' (defined in :config)
  ;; runs `completing-read-multiple' against the tags already in the roam DB --
  ;; so you pick from your existing vocabulary instead of inventing typo-variants;
  ;; entering nothing yields no #+filetags: line at all.  `%?' is where point
  ;; lands after capture; `:unnarrowed t' shows the whole file while capturing.
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
      :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                         "#+title: ${title}\n%(my/org-roam-prompt-filetags)")
      :unnarrowed t)))
  ;; The converted daily notes (2026-05-08.org, ...) sit at the vault root, not
  ;; in a `daily/' subdir, so point org-roam-dailies there with an empty subdir.
  (org-roam-dailies-directory "")
  ;; Fixed header for daily notes.  `file+head' inserts HEAD only when the day's
  ;; file doesn't exist yet; org-roam itself prepends the :ID: drawer above it,
  ;; so a brand-new daily ends up as:
  ;;   :PROPERTIES:  /  :ID: <auto>  /  :END:
  ;;   #+title: 2026-05-13 Tuesday
  ;;   #+filetags: :daily:
  ;;   * 14:32 <point>
  ;; The `entry' body "* %<%H:%M> %?" means every C-c r d capture adds a fresh
  ;; timestamped top-level heading (a running journal); `:unnarrowed t' keeps the
  ;; whole file visible while capturing.  `%A' is the locale's full weekday name.
  ;; For a fixed content skeleton instead, put the headings in HEAD and switch
  ;; the target to `(file+head+olp "%<%Y-%m-%d>.org" HEAD ("Log"))'.
  (org-roam-dailies-capture-templates
   '(("d" "default" entry
      "* %<%H:%M> %?"
      :target (file+head "%<%Y-%m-%d>.org"
                         "#+title: %<%Y-%m-%d %A>\n#+filetags: :daily:\n")
      :unnarrowed t)))
  (org-roam-completion-everywhere t)       ; complete [[ links from any buffer text
  :bind (("C-c r f" . org-roam-node-find)        ; open / create a note ("r" = roam)
         ("C-c r i" . org-roam-node-insert)      ; insert an [[id:...]] link to a note
         ("C-c r b" . org-roam-buffer-toggle)    ; backlinks side window
         ("C-c r c" . org-roam-capture)          ; capture a new note via a template
         ("C-c r d" . org-roam-dailies-goto-today))
  ;; Defer the cache-DB autosync (and therefore the whole org-roam load) until
  ;; init has finished -- on `after-init-hook' rather than in `:config'.  In
  ;; `:config' the mode hooks `find-file-hook' / `after-save-hook' eagerly, so
  ;; the very first file open would pull in emacsql + the entire org-roam
  ;; surface.  After-init runs once, before user interaction, late enough that
  ;; `emacs-init-time' is already snapped.
  ;;
  ;; (The DB itself must be built once first with `M-x org-roam-db-sync' --
  ;; see the first-run note in the header comment above.)
  :hook (after-init . org-roam-db-autosync-mode)
  :config
  ;; Tag prompt used by `org-roam-capture-templates' above.  Completes against
  ;; every tag currently in the roam DB; returns a "#+filetags: :a:b:" line, or
  ;; "" when no tags are entered (so empty input leaves no stray header line).
  (defun my/org-roam-prompt-filetags ()
    "Prompt for org-roam file tags and return a `#+filetags:' line (or \"\")."
    (let ((tags (seq-remove #'string-empty-p
                            (completing-read-multiple
                             "Tags (comma-separated, empty = none): "
                             (org-roam-tag-completions)))))
      (if tags (format "#+filetags: :%s:\n" (string-join tags ":")) ""))))

(defvar fenrir/org-roam-sync-program
  (expand-file-name "rust/lib/org-roam-sync" user-emacs-directory)
  "Path to the Rust `org-roam-sync' indexer binary.")

(defun fenrir/org-roam-sync--push-class-char (ch out)
  "Push CH to reversed char list OUT, escaping Rust regex class specials."
  (when (memq ch '(?\\ ?\[ ?\] ?- ?& ?~ ?^))
    (push ?\\ out))
  (push ch out)
  out)

(defun fenrir/org-roam-sync--translate-exclude (regexp)
  "Translate an Elisp `org-roam-file-exclude-regexp' REGEXP to Rust regex syntax.
Return nil if REGEXP uses Elisp-specific constructs that require Elisp fallback."
  (when (stringp regexp)
    (save-match-data
      (let ((i 0)
            (len (length regexp))
            (at-anchor-start t)
            (at-quantifier-start t)
            (after-interval nil)
            (out nil)
            (ok t))
        (while (and ok (< i len))
          (let ((ch (aref regexp i)))
            (cond
             ((= ch ?\\)
              (if (>= (1+ i) len)
                  (setq ok nil)
                (let ((next (aref regexp (1+ i))))
                  (cond
                   ((= next ?`)
                    (push ?^ out)
                    (setq at-anchor-start nil
                          at-quantifier-start t
                          after-interval nil
                          i (+ i 2)))
                   ((= next ?')
                    (push ?$ out)
                    (setq at-anchor-start nil
                          at-quantifier-start t
                          after-interval nil
                          i (+ i 2)))
                   ((= next ?\()
                    (cond
                     ((and (< (+ i 2) len)
                           (= (aref regexp (+ i 2)) ??))
                      (if (and (< (+ i 3) len)
                               (= (aref regexp (+ i 3)) ?:))
                          (progn
                            (push ?\( out)
                            (push ?? out)
                            (push ?: out)
                            (setq at-anchor-start t
                                  at-quantifier-start t
                                  after-interval nil
                                  i (+ i 4)))
                        (setq ok nil)))
                     (t
                      (push ?\( out)
                      (setq at-anchor-start t
                            at-quantifier-start t
                            after-interval nil
                            i (+ i 2)))))
                   ((= next ?|)
                    (push ?| out)
                    (setq at-anchor-start t
                          at-quantifier-start t
                          after-interval nil
                          i (+ i 2)))
                   ((= next ?{)
                    (if (not (string-match "\\\\}" regexp (+ i 2)))
                        (setq ok nil)
                      (let ((inner (substring regexp (+ i 2) (match-beginning 0)))
                            (next-i (match-end 0)))
                        (if (not (or (string-empty-p inner)
                                     (string-match-p "\\`[0-9]*,?[0-9]*\\'" inner)))
                            (setq ok nil)
                          (cond
                           (at-quantifier-start
                            (push ?\\ out)
                            (push ?{ out)
                            (dotimes (m (length inner))
                              (push (aref inner m) out))
                            (push ?\\ out)
                            (push ?} out)
                            (setq after-interval nil))
                           ((string-empty-p inner)
                            (push ?{ out)
                            (push ?0 out)
                            (push ?, out)
                            (push ?0 out)
                            (push ?} out)
                            (setq after-interval t))
                           ((string-match "\\`\\([0-9]*\\),\\([0-9]*\\)\\'" inner)
                            (let ((lo (match-string 1 inner))
                                  (hi (match-string 2 inner)))
                              (when (string-empty-p lo)
                                (setq lo "0"))
                              (push ?{ out)
                              (dotimes (m (length lo))
                                (push (aref lo m) out))
                              (push ?, out)
                              (dotimes (m (length hi))
                                (push (aref hi m) out))
                              (push ?} out)
                              (setq after-interval t)))
                           (t
                            (push ?{ out)
                            (dotimes (m (length inner))
                              (push (aref inner m) out))
                            (push ?} out)
                            (setq after-interval t)))
                          (setq at-anchor-start nil
                                at-quantifier-start nil
                                i next-i)))))
                   ((= next ?})
                    (push ?\\ out)
                    (push ?} out)
                    (setq at-anchor-start nil
                          at-quantifier-start nil
                          after-interval nil
                          i (+ i 2)))
                   ((= next ?\))
                    (push next out)
                    (setq at-anchor-start nil
                          at-quantifier-start nil
                          after-interval nil
                          i (+ i 2)))
                   ((memq next '(?= ?_ ?s ?S ?c ?C ?w ?W ?< ?> ?b ?B
                                    ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9))
                    (setq ok nil))
                   (t
                    (when (memq next '(?^ ?$ ?. ?* ?+ ?? ?\[ ?\] ?\\ ?\( ?\) ?| ?{ ?} ?- ?/))
                      (push ?\\ out))
                    (push next out)
                    (setq at-anchor-start nil
                          at-quantifier-start nil
                          after-interval nil
                          i (+ i 2)))))))
             ((= ch ?\[)
              (push ?\[ out)
              (setq i (1+ i))
              (when (and (< i len) (= (aref regexp i) ?^))
                (push ?^ out)
                (setq i (1+ i)))
              (let ((tokens nil)
                    (closed nil)
                    (first-in-class t))
                (while (and ok (< i len) (not closed))
                  (let ((c (aref regexp i)))
                    (cond
                     ((and (= c ?\]) (not first-in-class))
                      (setq closed t
                            i (1+ i)))
                     ((and (= c ?\[)
                           (< (1+ i) len)
                           (= (aref regexp (1+ i)) ?:))
                      (setq first-in-class nil)
                      (if (string-match ":\\]" regexp (+ i 2))
                          (let ((cls (substring regexp (+ i 2) (match-beginning 0))))
                            (if (member cls '("word" "unibyte" "multibyte" "nonascii"))
                                (setq ok nil)
                              (push (cons 'posix cls) tokens)
                              (setq i (match-end 0))))
                        (push (cons 'char c) tokens)
                        (setq i (1+ i))))
                     (t
                      (setq first-in-class nil)
                      (push (cons 'char c) tokens)
                      (setq i (1+ i))))))
                (if (not (and ok closed))
                    (setq ok nil)
                  (let* ((toks (vconcat (nreverse tokens)))
                         (n (length toks))
                         (k 0)
                         (emitted 0))
                    (while (and ok (< k n))
                      (let ((tok (aref toks k)))
                        (when (and (eq (car tok) 'char)
                                   (= (cdr tok) ?-)
                                   (or (and (> k 0) (eq (car (aref toks (1- k))) 'posix))
                                       (and (< (1+ k) n) (eq (car (aref toks (1+ k))) 'posix))))
                          (setq ok nil)))
                      (setq k (1+ k)))
                    (setq k 0)
                    (while (and ok (< k n))
                      (if (and (< (+ k 2) n)
                               (eq (car (aref toks k)) 'char)
                               (eq (car (aref toks (+ k 1))) 'char)
                               (= (cdr (aref toks (+ k 1))) ?-)
                               (eq (car (aref toks (+ k 2))) 'char))
                          (let ((s (cdr (aref toks k)))
                                (e (cdr (aref toks (+ k 2)))))
                            (when (<= s e)
                              (setq out (fenrir/org-roam-sync--push-class-char s out))
                              (push ?- out)
                              (setq out (fenrir/org-roam-sync--push-class-char e out))
                              (setq emitted (1+ emitted)))
                            (setq k (+ k 3)))
                        (let ((tok (aref toks k)))
                          (if (eq (car tok) 'posix)
                              (progn
                                (push ?\[ out)
                                (push ?: out)
                                (dotimes (m (length (cdr tok)))
                                  (push (aref (cdr tok) m) out))
                                (push ?: out)
                                (push ?\] out))
                            (setq out (fenrir/org-roam-sync--push-class-char (cdr tok) out)))
                          (setq emitted (1+ emitted)
                                k (1+ k)))))
                    (if (or (not ok) (= emitted 0))
                        (setq ok nil)
                      (push ?\] out)
                      (setq at-anchor-start nil
                            at-quantifier-start nil
                            after-interval nil))))))
             ((= ch ?^)
              (if at-anchor-start
                  (setq at-quantifier-start t)
                (push ?\\ out)
                (setq at-quantifier-start nil))
              (push ?^ out)
              (setq at-anchor-start nil
                    after-interval nil
                    i (1+ i)))
             ((= ch ?$)
              (let ((is-anchor
                     (or (= (1+ i) len)
                         (and (< (+ i 2) len)
                              (= (aref regexp (1+ i)) ?\\)
                              (memq (aref regexp (+ i 2)) '(?\) ?|))))))
                (if is-anchor
                    (setq at-quantifier-start t)
                  (push ?\\ out)
                  (setq at-quantifier-start nil))
                (push ?$ out)
                (setq at-anchor-start nil
                      after-interval nil
                      i (1+ i))))
             ((memq ch '(?* ?+ ??))
              (if (and after-interval (= ch ??))
                  (setq ok nil)
                (when at-quantifier-start
                  (push ?\\ out))
                (push ch out)
                (setq at-anchor-start nil
                      at-quantifier-start nil
                      after-interval nil
                      i (1+ i))))
             ((memq ch '(?\( ?\) ?| ?{ ?}))
              (push ?\\ out)
              (push ch out)
              (setq at-anchor-start nil
                    at-quantifier-start nil
                    after-interval nil
                    i (1+ i)))
             (t
              (push ch out)
              (setq at-anchor-start nil
                    at-quantifier-start nil
                    after-interval nil
                    i (1+ i))))))
        (when ok
          (concat (nreverse out)))))))

(defun fenrir/org-roam-sync--translate-excludes (exclude-regexp)
  "Translate `org-roam-file-exclude-regexp' EXCLUDE-REGEXP into a list of strings.
Returns a cons cell (OK . PATTERNS) where OK is nil on unsupported regexps."
  (cond
   ((null exclude-regexp) (cons t nil))
   ((stringp exclude-regexp)
    (let ((tr (fenrir/org-roam-sync--translate-exclude exclude-regexp)))
      (if tr (cons t (list tr)) (cons nil nil))))
   ((listp exclude-regexp)
    (let ((res nil)
          (ok t))
      (dolist (re exclude-regexp)
        (let ((tr (fenrir/org-roam-sync--translate-exclude re)))
          (if tr
              (push tr res)
            (setq ok nil))))
      (if ok (cons t (nreverse res)) (cons nil nil))))
   (t (cons nil nil))))

(defun fenrir/org-roam-sync--standard-value-equal-p (sym)
  "Return non-nil when SYM's current value equals its `standard-value'."
  (let ((std (get sym 'standard-value)))
    (and std
         (boundp sym)
         (equal (symbol-value sym) (eval (car std) t)))))

(defun fenrir/org-roam-sync--can-use-rust-p ()
  "Return non-nil if `org-roam-db-sync' can use `fenrir/org-roam-sync-program'."
  (and (stringp fenrir/org-roam-sync-program)
       (file-executable-p fenrir/org-roam-sync-program)
       (not (file-remote-p org-roam-directory))
       (not (file-remote-p org-roam-db-location))
       (fenrir/org-roam-sync--standard-value-equal-p 'org-roam-db-node-include-function)
       (fenrir/org-roam-sync--standard-value-equal-p 'org-roam-db-extra-links-elements)
       (fenrir/org-roam-sync--standard-value-equal-p 'org-roam-db-extra-links-exclude-keys)
       (not (and (boundp 'org-ref-cite-types) org-ref-cite-types))
       (not (bound-and-true-p org-enforce-todo-dependencies))
       (not (bound-and-true-p org-blocker-hook))
       (or (not (boundp 'org-todo-keywords))
           (fenrir/org-roam-sync--standard-value-equal-p 'org-todo-keywords))
       (car (fenrir/org-roam-sync--translate-excludes org-roam-file-exclude-regexp))))

(defun fenrir/org-roam-sync--build-args (&optional force)
  "Build CLI arguments for `fenrir/org-roam-sync-program'.
When FORCE is non-nil, pass `--force'."
  (let ((excludes (cdr (fenrir/org-roam-sync--translate-excludes
                        org-roam-file-exclude-regexp)))
        (args (list "--dir" (expand-file-name org-roam-directory)
                    "--db" (expand-file-name org-roam-db-location))))
    (dolist (re excludes)
      (setq args (append args (list "--exclude" re))))
    (dolist (ext org-roam-file-extensions)
      (setq args (append args (list "--ext" ext))))
    (when case-fold-search
      (setq args (append args (list "--ignore-case"))))
    (when force
      (setq args (append args (list "--force"))))
    args))

(defun fenrir/org-roam-db-sync-a (orig-fn &optional force)
  "Fast-path `org-roam-db-sync' via `fenrir/org-roam-sync-program'.
Falls back to ORIG-FN with FORCE when the Rust helper is unavailable,
customized hooks/predicates are active, encrypted files exist (exit 2),
or the subprocess fails."
  (if (not (fenrir/org-roam-sync--can-use-rust-p))
      (funcall orig-fn force)
    (org-roam-db--close)
    (let ((args (fenrir/org-roam-sync--build-args force))
          (status nil)
          (output nil))
      (with-temp-buffer
        (setq status
              (condition-case err
                  (apply #'call-process fenrir/org-roam-sync-program
                         nil (current-buffer) nil args)
                (error
                 (setq output (error-message-string err))
                 nil)))
        (unless output
          (setq output (string-trim (buffer-string)))))
      (cond
       ((eql status 0)
        (org-roam-db))
       ((eql status 2)
        ;; Encrypted .org.gpg / .org.age files detected before modifying DB.
        (funcall orig-fn force))
       (t
        (lwarn 'org-roam :warning
               "org-roam-sync failed (status %S): %s; falling back to Elisp"
               status (or output ""))
        (funcall orig-fn force))))))

(with-eval-after-load 'org-roam-db
  (advice-add 'org-roam-db-sync :around #'fenrir/org-roam-db-sync-a))

;; org-roam-ui: an interactive graph of the roam DB rendered in the browser
;; (D3 force-directed; click a node to jump to it, follows point in Emacs,
;; matches the Emacs theme).  Pulls in `websocket' + `simple-httpd' and runs a
;; local HTTP server while `org-roam-ui-mode' is on.  No Graphviz needed -- this
;; is the practical alternative to `org-roam-graph' for a large vault.
(use-package org-roam-ui
  :after org-roam
  :custom
  (org-roam-ui-sync-theme t)
  (org-roam-ui-follow t)                   ; the graph tracks the note you're in
  (org-roam-ui-update-on-save t)
  (org-roam-ui-open-on-start nil)          ; don't auto-launch a browser tab
  :bind ("C-c r g" . org-roam-ui-mode))    ; "g" = graph; toggles the server + tab

(provide 'init-org-roam)
;;; init-org-roam.el ends here
