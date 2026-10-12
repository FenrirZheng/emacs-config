;;; fenrir-search.el --- One search system: file / text search, WHERE and WHAT switchable in the prompt  -*- lexical-binding: t; -*-

;; Author: fenrir
;; Keywords: convenience, matching

;;; Commentary:

;; Spec: [2026-10-12/165758-one-search-system/SPEC.md](../2026-10-12/165758-one-search-system/SPEC.md).
;;
;; Two commands, `fenrir/search-files' (`consult-fd') and `fenrir/search-text'
;; (`consult-ripgrep'), both starting at the project root, or at
;; `default-directory' when there is no project.  Inside their prompt,
;; `fenrir/search-prompt-mode' binds three keys that keep the typed text:
;;
;;   C-t      on a file prompt: next WHERE; on a text prompt: switch to files
;;   C-z      on a text prompt: next WHERE; on a file prompt: switch to text
;;   C-x C-d  WHERE := any folder, picked with consult-dir
;;
;; WHERE cycles project root -> current folder -> parent -> ... -> `/' ->
;; project root (`fenrir/search--scopes').  A switch saves the minibuffer text,
;; schedules a rerun with `run-at-time 0' and `abort-recursive-edit's.
;;
;; The mode's keymap is a buffer-local minor mode in the minibuffer, so it
;; beats Vertico's local map -- that is what keeps consult-dir's `vertico-map'
;; `C-x C-d' (init-dired.el) from inserting a path into a ripgrep pattern.
;;
;; This file owns the feature; `init-completion.el' requires it, and the
;; global keys are routed in `init-keys.el'.  The pure helpers load in
;; `emacs -Q' for test/search-test.el.

;;; Code:

(declare-function consult-fd "consult")
(declare-function consult-ripgrep "consult")
(declare-function consult-dir--pick "consult-dir")
(declare-function consult-eglot-symbols "consult-eglot")
(declare-function eglot-current-server "eglot")
(declare-function project-root "project")

(defun fenrir/search--dir (dir)
  "DIR as an absolute directory name (trailing slash)."
  (file-name-as-directory (expand-file-name dir)))

(defun fenrir/search--parent (dir)
  "Parent directory of DIR, or nil when DIR is the file-system root."
  (let* ((dir (fenrir/search--dir dir))
         (parent (file-name-directory (directory-file-name dir))))
    (unless (or (null parent) (equal parent dir))
      parent)))

(defun fenrir/search--scopes (root origin)
  "The WHERE cycle: ROOT, ORIGIN, then ORIGIN's parents up to `/'.
Duplicates are dropped, first occurrence wins, so ROOT is visited once."
  (let ((dirs (list (fenrir/search--dir root)))
        (dir (fenrir/search--dir origin)))
    (while dir
      (push dir dirs)
      (setq dir (fenrir/search--parent dir)))
    (delete-dups (nreverse dirs))))

(defun fenrir/search--next-scope (dir root origin)
  "The WHERE after DIR in the cycle of ROOT and ORIGIN.
A DIR off the cycle (picked with consult-dir) climbs to its parent; at
`/' the cycle wraps to ROOT."
  (let* ((scopes (fenrir/search--scopes root origin))
         (dir (fenrir/search--dir dir))
         (tail (member dir scopes)))
    (cond ((cadr tail))
          (tail (car scopes))
          ((fenrir/search--parent dir))
          (t (car scopes)))))

(defun fenrir/search--next-state (key-kind kind dir root origin)
  "Where a KEY-KIND key (`files' / `text') leads from a KIND prompt in DIR.
Same kind: next WHERE in the ROOT / ORIGIN cycle.  Other kind: same DIR,
new WHAT.  Returns (KIND . DIR)."
  (if (eq key-kind kind)
      (cons kind (fenrir/search--next-scope dir root origin))
    (cons key-kind (fenrir/search--dir dir))))

(defun fenrir/search--root (dir)
  "Project root for DIR, or DIR itself when it is in no project."
  (let ((pr (and (fboundp 'project-current)
                 (let ((default-directory dir)) (project-current)))))
    (fenrir/search--dir (if pr (project-root pr) dir))))

;; --- the prompt ------------------------------------------------------------------

(defvar fenrir/search--state nil
  "Plist (:kind :dir :root :origin) of the active search prompt.
Bound dynamically around the consult call, so the prompt keys can read it.")

(defvar-keymap fenrir/search-prompt-mode-map
  :doc "Keys active only inside a `fenrir/search-files' / `-text' prompt."
  "C-t"     #'fenrir/search-prompt-files
  "C-z"     #'fenrir/search-prompt-text
  "C-x C-d" #'fenrir/search-prompt-pick-dir)

(define-minor-mode fenrir/search-prompt-mode
  "Minibuffer-local keys of the one-search prompts."
  :lighter nil
  :keymap fenrir/search-prompt-mode-map)

(defun fenrir/search--run (kind dir initial &optional root origin)
  "Run search KIND (`files' / `text') in DIR with INITIAL input.
ROOT and ORIGIN define the WHERE cycle; they default to DIR's project
root and DIR."
  (let* ((dir (fenrir/search--dir dir))
         (origin (or origin dir))
         (root (or root (fenrir/search--root origin)))
         (fenrir/search--state (list :kind kind :dir dir :root root :origin origin))
         (command (if (eq kind 'files) #'consult-fd #'consult-ripgrep))
         ;; `consult-customize' (the debounce) keys on `this-command', which a
         ;; rerun from a timer would not carry.
         (this-command command))
    (minibuffer-with-setup-hook
        (lambda () (fenrir/search-prompt-mode 1))
      (funcall command dir initial))))

(defun fenrir/search--rerun (kind dir)
  "Leave the current prompt and reopen it as KIND in DIR, keeping the text."
  (let ((initial (minibuffer-contents-no-properties))
        (root (plist-get fenrir/search--state :root))
        (origin (plist-get fenrir/search--state :origin)))
    (run-at-time 0 nil #'fenrir/search--run kind dir initial root origin)
    (abort-recursive-edit)))

(defun fenrir/search--switch (key-kind)
  "Act on a KEY-KIND key in the prompt, see `fenrir/search--next-state'."
  (let ((next (fenrir/search--next-state
               key-kind
               (plist-get fenrir/search--state :kind)
               (plist-get fenrir/search--state :dir)
               (plist-get fenrir/search--state :root)
               (plist-get fenrir/search--state :origin))))
    (fenrir/search--rerun (car next) (cdr next))))

(defun fenrir/search-prompt-files ()
  "In a search prompt: next folder for files, or switch text -> files."
  (interactive)
  (fenrir/search--switch 'files))

(defun fenrir/search-prompt-text ()
  "In a search prompt: next folder for text, or switch files -> text."
  (interactive)
  (fenrir/search--switch 'text))

(defun fenrir/search-prompt-pick-dir ()
  "In a search prompt: search the same text in a folder picked with consult-dir."
  (interactive)
  (let* ((enable-recursive-minibuffers t)
         (dir (if (require 'consult-dir nil t)
                  (consult-dir--pick "Search in: ")
                (read-directory-name "Search in: "))))
    (when dir
      (fenrir/search--rerun (plist-get fenrir/search--state :kind) dir))))

;; --- entry points ----------------------------------------------------------------

(defun fenrir/search--start-dir ()
  "Where a fresh search starts: the project root, else `default-directory'."
  (fenrir/search--root default-directory))

;;;###autoload
(defun fenrir/search-files (&optional dir)
  "Find a file by name under DIR (default: project root) with `consult-fd'.
In the prompt: `C-t' next folder, `C-z' search text instead, `C-x C-d'
pick a folder."
  (interactive)
  (fenrir/search--run 'files (or dir (fenrir/search--start-dir)) nil
                      nil (fenrir/search--dir default-directory)))

;;;###autoload
(defun fenrir/search-text (&optional dir)
  "Search text under DIR (default: project root) with `consult-ripgrep'.
In the prompt: `C-z' next folder, `C-t' find files instead, `C-x C-d'
pick a folder."
  (interactive)
  (fenrir/search--run 'text (or dir (fenrir/search--start-dir)) nil
                      nil (fenrir/search--dir default-directory)))

;;;###autoload
(defun fenrir/search-files-here ()
  "Find a file by name under `default-directory' (in dired: its folder).
Same prompt keys as `fenrir/search-files'; the WHERE cycle still offers
the project root."
  (interactive)
  (let ((here (fenrir/search--dir default-directory)))
    (fenrir/search--run 'files here nil nil here)))

;;;###autoload
(defun fenrir/search-lsp-symbols ()
  "Search workspace symbols with `consult-eglot-symbols'.
Says so instead of erroring when this buffer has no eglot server."
  (interactive)
  (if (and (fboundp 'eglot-current-server) (eglot-current-server))
      (call-interactively #'consult-eglot-symbols)
    (message "No eglot server in this buffer; LSP symbol search needs one (M-x eglot)")))

(provide 'fenrir-search)
;;; fenrir-search.el ends here
