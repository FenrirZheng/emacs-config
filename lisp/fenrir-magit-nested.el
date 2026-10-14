;;; fenrir-magit-nested.el --- Which nested clones changed, inside Magit -*- lexical-binding: t; -*-

;;; Commentary:
;; A front end for the `git-nested-status' helper binary
;; ([rust/git-tools/git-nested-status](../rust/git-tools/git-nested-status/README.md),
;; built by `make -C rust/git-tools' into rust/lib/), for repositories that
;; hold independent clones -- subdirectories with their own `.git', such as
;; ~/code/yeeya's repos/*.  Magit says nothing about them on its own (they are
;; usually gitignored), and they are not `git subtree's, so the Subtrees
;; section does not apply.
;;
;; * Status buffer: a "Nested repos" section after Subtrees (or Staged changes),
;;   one line per clone with something to act on -- uncommitted paths, commits
;;   ahead of or behind its upstream, or a detached HEAD.  The heading counts
;;   every clone found.  TAB unfolds a line's uncommitted files; RET on a line
;;   opens that clone's own Magit status, RET on a file visits it.
;;
;; Which subdirectories are scanned is the helper's business: two levels deep
;; by default, `git config nested.depth N' (0 = off) or
;; `git config --add nested.path <dir>' in the umbrella repo override it.
;; The helper is read-only and offline (gix, no fetch), so ahead/behind is as of
;; each clone's last fetch.  A repo where it finds no clone is remembered for
;; the session and not asked again; `M-x fenrir/magit-nested-forget' clears
;; that.  `fenrir/magit-nested-skip-directories' (default: ~/) are never
;; scanned.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
;; Loaded after Magit (see init-git.el); `magit-insert-section' is a macro, so
;; Magit must be present when this file is read.
(require 'magit)

(declare-function magit-toplevel "magit-git")
(declare-function magit-status-setup-buffer "magit-status")
(declare-function magit-current-section "magit-section")
(declare-function magit-insert-heading "magit-section")
(declare-function magit-add-section-hook "magit-section")
(declare-function fenrir/magit-subtree-insert-section "fenrir-magit-subtree")

(defgroup fenrir/magit-nested nil
  "Nested clone overview for Magit."
  :group 'magit)

(defcustom fenrir/magit-nested-program
  (expand-file-name "rust/lib/git-nested-status" user-emacs-directory)
  "The `git-nested-status' helper binary.
Built by `make -C rust/git-tools' into the workspace `rust/lib/'.
Until then the Nested repos section stays absent, with a one-time hint."
  :type 'file)

(defcustom fenrir/magit-nested-show-in-status t
  "Whether Magit status buffers get the Nested repos section."
  :type 'boolean)

(defcustom fenrir/magit-nested-skip-directories '("~/")
  "Repository toplevels never scanned for nested clones.
$HOME is one: the dotfiles repo's working tree holds about 100 clones."
  :type '(repeat directory))

(defvar fenrir/magit-nested--none (make-hash-table :test #'equal)
  "Toplevels where the helper found no nested clone this session.")

(defvar fenrir/magit-nested--hinted nil
  "Non-nil once the not-built hint was shown this session.")

;;;; Parsing (pure)

(defconst fenrir/magit-nested--header "# git-nested-status v1"
  "First line of `git-nested-status --porcelain' output.")

(defconst fenrir/magit-nested--fields
  '(:path :branch :head :upstream :ahead :behind :staged :unstaged :untracked)
  "Field names of an `R' line after its tag, in order.")

(defun fenrir/magit-nested--parse (output)
  "Parse `git-nested-status --porcelain [--files]' OUTPUT into row plists.
Each `F' line becomes a (KIND . FILE) pair in the preceding row's :files,
KIND a symbol.  Return nil unless OUTPUT starts with the v1 header."
  (let ((lines (split-string output "\n" t))
        rows)
    (when (equal (car lines) fenrir/magit-nested--header)
      (dolist (line (cdr lines))
        (let ((cols (split-string line "\t")))
          (pcase (car cols)
            ("R"
             (when (= (length (cdr cols)) (length fenrir/magit-nested--fields))
               (let (plist)
                 (cl-loop for key in fenrir/magit-nested--fields
                          for val in (cdr cols)
                          do (setq plist
                                   (plist-put plist key
                                              (cond ((equal val "-") nil)
                                                    ((memq key '(:ahead :behind :staged :unstaged :untracked))
                                                     (string-to-number val))
                                                    (t val)))))
                 (push plist rows))))
            ("F"
             (when (and rows (= (length cols) 3))
               (plist-put (car rows) :files
                          (append (plist-get (car rows) :files)
                                  (list (cons (intern (nth 1 cols)) (nth 2 cols))))))))))
      (nreverse rows))))

(defun fenrir/magit-nested--detached-p (row)
  "Non-nil if ROW's HEAD is detached (a commit but no branch)."
  (and (null (plist-get row :branch)) (plist-get row :head)))

(defun fenrir/magit-nested--uncommitted (row)
  "Number of uncommitted paths in ROW; a path both staged and unstaged counts once."
  (if (plist-get row :files)
      (length (delete-dups (mapcar #'cdr (plist-get row :files))))
    (+ (or (plist-get row :staged) 0)
       (or (plist-get row :unstaged) 0)
       (or (plist-get row :untracked) 0))))

(defun fenrir/magit-nested--changed-p (row)
  "Non-nil if ROW has uncommitted paths, is ahead or behind, or is detached.
A clone without an upstream is not changed for that alone."
  (or (> (fenrir/magit-nested--uncommitted row) 0)
      (> (or (plist-get row :ahead) 0) 0)
      (> (or (plist-get row :behind) 0) 0)
      (fenrir/magit-nested--detached-p row)))

;;;; Running the helper

(defun fenrir/magit-nested--skipped-p (top)
  "Non-nil if TOP is one of `fenrir/magit-nested-skip-directories'."
  (let ((top (file-name-as-directory (expand-file-name top))))
    (seq-some (lambda (d) (equal top (file-name-as-directory (expand-file-name d))))
              fenrir/magit-nested-skip-directories)))

(defun fenrir/magit-nested--rows ()
  "Rows for every nested clone of the current repo, or nil."
  (when-let* ((top (magit-toplevel))
              ((not (fenrir/magit-nested--skipped-p top)))
              ((not (gethash top fenrir/magit-nested--none)))
              (program (or (executable-find fenrir/magit-nested-program)
                           (progn
                             (unless fenrir/magit-nested--hinted
                               (setq fenrir/magit-nested--hinted t)
                               (message "Nested repos: %s is not built -- run: make -C %s"
                                        fenrir/magit-nested-program
                                        (expand-file-name "rust/git-tools" user-emacs-directory)))
                             nil))))
    (with-temp-buffer
      (let* ((default-directory top)
             (status (process-file program nil '(t nil) nil
                                   "-C" top "--porcelain" "--files"))
             (rows (and (eq status 0)
                        (fenrir/magit-nested--parse (buffer-string)))))
        (unless rows
          (puthash top t fenrir/magit-nested--none))
        rows))))

(defun fenrir/magit-nested-forget ()
  "Forget which repos had no nested clone, so the next refresh asks again."
  (interactive)
  (clrhash fenrir/magit-nested--none))

;;;; Status section

(defvar-keymap magit-fenrir-nested-section-map
  :doc "Keymap for a clone line in the Nested repos status section.
TAB (Magit's own) folds the list of its uncommitted files."
  "<remap> <magit-visit-thing>" #'fenrir/magit-nested-status)

(defvar-keymap magit-fenrir-nested-file-section-map
  :doc "Keymap for an uncommitted file listed under a clone line.
Its own section type, not Magit's `file': the file belongs to another
repository, so Magit's stage/unstage commands must not act on it."
  "<remap> <magit-visit-thing>" #'fenrir/magit-nested-visit-file)

(defun fenrir/magit-nested-status ()
  "Open the Magit status of the nested clone at point."
  (interactive)
  (let ((section (magit-current-section)))
    (unless (eq (oref section type) 'fenrir-nested)
      (user-error "No nested clone at point"))
    (magit-status-setup-buffer
     (file-name-as-directory (expand-file-name (oref section value) (magit-toplevel))))))

(defun fenrir/magit-nested-visit-file ()
  "Visit the uncommitted file at point, listed under a Nested repos line."
  (interactive)
  (let ((section (magit-current-section)))
    (unless (eq (oref section type) 'fenrir-nested-file)
      (user-error "No nested clone file at point"))
    (find-file (expand-file-name (oref section value) (magit-toplevel)))))

(defun fenrir/magit-nested--line (row width bwidth)
  "A status line for ROW, its path padded to WIDTH and branch to BWIDTH."
  (let ((ahead (or (plist-get row :ahead) 0))
        (behind (or (plist-get row :behind) 0))
        (u (fenrir/magit-nested--uncommitted row)))
    (concat
     (propertize (string-pad (plist-get row :path) width) 'font-lock-face 'magit-filename)
     "  "
     (string-pad (fenrir/magit-nested--branch-label row) bwidth)
     (cond ((fenrir/magit-nested--detached-p row) "")
           ((null (plist-get row :upstream))
            (propertize "  no upstream" 'font-lock-face 'shadow))
           (t (concat (if (> ahead 0) (format "  ↑%d" ahead) "")
                      (if (> behind 0) (format "  ↓%d" behind) ""))))
     (if (> u 0) (format "  U:%d" u) ""))))

(defun fenrir/magit-nested--branch-label (row)
  "ROW's branch, or `detached <head>'."
  (cond ((plist-get row :branch))
        ((fenrir/magit-nested--detached-p row)
         (propertize (format "detached %s" (plist-get row :head)) 'font-lock-face 'warning))
        (t "-")))

(defun fenrir/magit-nested-insert-section ()
  "Insert the Nested repos section when the repo has clones with a change."
  (when fenrir/magit-nested-show-in-status
    (when-let* ((rows (fenrir/magit-nested--rows))
                (changed (seq-filter #'fenrir/magit-nested--changed-p rows)))
      (magit-insert-section (fenrir-nested-repos nil)
        (magit-insert-heading
          (format "Nested repos (%d changed of %d)" (length changed) (length rows)))
        (let ((width (apply #'max (mapcar (lambda (r) (length (plist-get r :path))) changed)))
              (bwidth (apply #'max (mapcar (lambda (r) (length (fenrir/magit-nested--branch-label r)))
                                           changed))))
          (dolist (row changed)
            ;; The value is the path, not the row: Magit keeps a section's
            ;; folded/expanded state across refreshes by type and value.
            (magit-insert-section (fenrir-nested (plist-get row :path) t)
              (magit-insert-heading (fenrir/magit-nested--line row width bwidth))
              (dolist (f (plist-get row :files))
                (magit-insert-section (fenrir-nested-file
                                       (concat (plist-get row :path) "/" (cdr f)))
                  (insert (format "  %-9s  " (car f))
                          (propertize (cdr f) 'font-lock-face 'magit-filename)
                          "\n"))))))
        (insert "\n")))))

;;;; Wiring

(defun fenrir/magit-nested--install ()
  "Add the status section after Subtrees, or after Staged changes without it."
  ;; Anchored after the Subtrees hook, not after Staged changes: two hooks
  ;; appended after the same anchor end up in reverse order.
  (magit-add-section-hook 'magit-status-sections-hook
                          #'fenrir/magit-nested-insert-section
                          (if (memq #'fenrir/magit-subtree-insert-section
                                    (default-value 'magit-status-sections-hook))
                              #'fenrir/magit-subtree-insert-section
                            'magit-insert-staged-changes)
                          t))

(with-eval-after-load 'magit
  (fenrir/magit-nested--install))

(provide 'fenrir-magit-nested)
;;; fenrir-magit-nested.el ends here
