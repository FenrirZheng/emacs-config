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
(require 'tabulated-list)
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

(defcustom fenrir/magit-nested-list-depth 4
  "Default directory scan depth for `fenrir/magit-nested-list'.
Can be adjusted interactively inside the `*git-projects*' buffer with
`D', `+', and `-'."
  :type 'natnum)

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

;;;; Interactive project list (`<f5> g W')

(defvar-local fenrir/magit-nested-list--dir nil
  "Root directory currently scanned in this `*git-projects*' buffer.")

(defvar-local fenrir/magit-nested-list--depth nil
  "Scan depth currently used in this `*git-projects*' buffer.")

(defvar-local fenrir/magit-nested-list--rows nil
  "All parsed row plists from the last `git-nested-status' run.")

(defvar-local fenrir/magit-nested-list--changed-only nil
  "When non-nil, show only projects with a change.")

(defvar-local fenrir/magit-nested-list--filter nil
  "Optional regexp filtering displayed projects by path or branch.")

(defun fenrir/magit-nested--rows-in-dir (dir &optional depth)
  "Scan DIR directly for nested git projects up to DEPTH levels down.
Uses `git-nested-status --dir' so DIR need not be a git repository."
  (let* ((expanded (file-name-as-directory (expand-file-name dir)))
         (depth (or depth fenrir/magit-nested-list-depth))
         (program (or (executable-find fenrir/magit-nested-program)
                      (user-error "Nested repos: %s is not built -- run: make -C %s"
                                  fenrir/magit-nested-program
                                  (expand-file-name "rust/git-tools" user-emacs-directory)))))
    (unless (file-directory-p expanded)
      (user-error "Not a directory: %s" expanded))
    (with-temp-buffer
      (let* ((default-directory expanded)
             (status (process-file program nil '(t t) nil
                                   "--dir" expanded
                                   "--depth" (number-to-string depth)
                                   "--porcelain")))
        (unless (eq status 0)
          (user-error "git-nested-status failed: %s" (string-trim (buffer-string))))
        (fenrir/magit-nested--parse (buffer-string))))))

(defun fenrir/magit-nested-list--state-label (row)
  "Compact, propertized state summary for ROW."
  (let* ((staged (or (plist-get row :staged) 0))
         (unstaged (or (plist-get row :unstaged) 0))
         (untracked (or (plist-get row :untracked) 0))
         (ahead (or (plist-get row :ahead) 0))
         (behind (or (plist-get row :behind) 0))
         (parts (delq nil
                      (list (when (> staged 0) (format "S:%d" staged))
                            (when (> unstaged 0) (format "U:%d" unstaged))
                            (when (> untracked 0) (format "?:%d" untracked))
                            (when (> ahead 0) (format "↑%d" ahead))
                            (when (> behind 0) (format "↓%d" behind))
                            (when (fenrir/magit-nested--detached-p row) "detached")))))
    (if parts
        (propertize (string-join parts " ")
                    'face (if (or (> staged 0) (> unstaged 0) (> untracked 0))
                              'warning
                            'font-lock-keyword-face))
      (propertize "clean" 'face 'success))))

(defun fenrir/magit-nested-list--upstream-label (row)
  "Upstream tracking ref for ROW, or a shadowed dash."
  (if-let* ((u (plist-get row :upstream)))
      u
    (propertize "-" 'face 'shadow)))

(defun fenrir/magit-nested-list--visible-rows (rows changed-only filter)
  "Filter ROWS according to CHANGED-ONLY and regexp FILTER."
  (seq-filter
   (lambda (row)
     (and (or (not changed-only) (fenrir/magit-nested--changed-p row))
          (or (null filter)
              (string-empty-p filter)
              (let ((case-fold-search t))
                (or (string-match-p filter (or (plist-get row :path) ""))
                    (string-match-p filter (or (plist-get row :branch) "")))))))
   rows))

(defun fenrir/magit-nested-list--to-entry (row)
  "Convert ROW plist into a `tabulated-list-entries' element."
  (let ((path (plist-get row :path)))
    (list path
          (vector (propertize path 'face 'magit-filename)
                  (fenrir/magit-nested--branch-label row)
                  (fenrir/magit-nested-list--state-label row)
                  (fenrir/magit-nested-list--upstream-label row)))))

(defun fenrir/magit-nested-list--update-mode-line (visible total changed)
  "Update mode-line metadata for the `*git-projects*' buffer."
  (let* ((dir-short (abbreviate-file-name fenrir/magit-nested-list--dir))
         (filt (concat (when fenrir/magit-nested-list--changed-only " changed")
                       (when (and fenrir/magit-nested-list--filter
                                  (not (string-empty-p fenrir/magit-nested-list--filter)))
                         (format " /%s/" fenrir/magit-nested-list--filter)))))
    (setq mode-line-process
          (format " [%s | depth:%d | %d/%d (%d chg)%s | D/+/-:depth d:dir c:chg /:filter RET:magit o:dired]"
                  dir-short fenrir/magit-nested-list--depth visible total changed filt))
    (force-mode-line-update)))

(defun fenrir/magit-nested-list--render ()
  "Render `fenrir/magit-nested-list--rows' into the current tabulated list."
  (let* ((all fenrir/magit-nested-list--rows)
         (changed (length (seq-filter #'fenrir/magit-nested--changed-p all)))
         (visible (fenrir/magit-nested-list--visible-rows
                   all
                   fenrir/magit-nested-list--changed-only
                   fenrir/magit-nested-list--filter))
         (pwidth (min 56 (max 28 (if visible
                                     (apply #'max (mapcar (lambda (r) (length (plist-get r :path))) visible))
                                   28))))
         (bwidth (min 32 (max 14 (if visible
                                     (apply #'max (mapcar (lambda (r) (length (fenrir/magit-nested--branch-label r))) visible))
                                   14)))))
    (setq tabulated-list-format
          (vector (list "Project" pwidth t)
                  (list "Branch" bwidth t)
                  (list "State" 20 t)
                  (list "Upstream" 28 t)))
    (tabulated-list-init-header)
    (setq tabulated-list-entries (mapcar #'fenrir/magit-nested-list--to-entry visible))
    (tabulated-list-print t)
    (fenrir/magit-nested-list--update-mode-line (length visible) (length all) changed)))

(defun fenrir/magit-nested-list--current-dir ()
  "Return the absolute directory of the project at point."
  (let ((rel (tabulated-list-get-id)))
    (unless rel
      (user-error "No git project at point"))
    (file-name-as-directory (expand-file-name rel fenrir/magit-nested-list--dir))))

(defun fenrir/magit-nested-list-open-magit ()
  "Open `magit-status' for the git project at point."
  (interactive)
  (magit-status-setup-buffer (fenrir/magit-nested-list--current-dir)))

(defun fenrir/magit-nested-list-open-dired ()
  "Open `dired' in the git project at point."
  (interactive)
  (dired (fenrir/magit-nested-list--current-dir)))

(defun fenrir/magit-nested-list-find-file ()
  "Find a file inside the git project at point."
  (interactive)
  (let ((default-directory (fenrir/magit-nested-list--current-dir)))
    (call-interactively #'find-file)))

(defun fenrir/magit-nested-list-refresh ()
  "Re-run `git-nested-status' for the current directory and depth."
  (interactive)
  (setq fenrir/magit-nested-list--rows
        (fenrir/magit-nested--rows-in-dir fenrir/magit-nested-list--dir
                                          fenrir/magit-nested-list--depth))
  (fenrir/magit-nested-list--render)
  (message "Git projects under %s (depth %d): %d found, %d changed"
           (abbreviate-file-name fenrir/magit-nested-list--dir)
           fenrir/magit-nested-list--depth
           (length fenrir/magit-nested-list--rows)
           (length (seq-filter #'fenrir/magit-nested--changed-p fenrir/magit-nested-list--rows))))

(defun fenrir/magit-nested-list-set-depth (depth)
  "Set scan DEPTH for this buffer and re-scan."
  (interactive
   (list (read-number (format "Scan depth (current %d): "
                              (or fenrir/magit-nested-list--depth
                                  fenrir/magit-nested-list-depth))
                      (or fenrir/magit-nested-list--depth
                          fenrir/magit-nested-list-depth))))
  (when (< depth 1)
    (user-error "Scan depth must be at least 1"))
  (setq fenrir/magit-nested-list--depth (truncate depth))
  (fenrir/magit-nested-list-refresh))

(defun fenrir/magit-nested-list-increase-depth ()
  "Increase scan depth by 1 and re-scan."
  (interactive)
  (setq fenrir/magit-nested-list--depth
        (1+ (or fenrir/magit-nested-list--depth fenrir/magit-nested-list-depth)))
  (fenrir/magit-nested-list-refresh))

(defun fenrir/magit-nested-list-decrease-depth ()
  "Decrease scan depth by 1 (minimum 1) and re-scan."
  (interactive)
  (let ((cur (or fenrir/magit-nested-list--depth fenrir/magit-nested-list-depth)))
    (when (<= cur 1)
      (user-error "Scan depth is already at minimum (1)"))
    (setq fenrir/magit-nested-list--depth (1- cur))
    (fenrir/magit-nested-list-refresh)))

(defun fenrir/magit-nested-list-set-dir (dir)
  "Change the scanned root DIR and re-scan."
  (interactive
   (list (read-directory-name "Scan git projects under: "
                              (or fenrir/magit-nested-list--dir default-directory))))
  (setq fenrir/magit-nested-list--dir (file-name-as-directory (expand-file-name dir))
        default-directory fenrir/magit-nested-list--dir)
  (fenrir/magit-nested-list-refresh))

(defun fenrir/magit-nested-list-toggle-changed ()
  "Toggle between showing all projects and changed projects only."
  (interactive)
  (setq fenrir/magit-nested-list--changed-only
        (not fenrir/magit-nested-list--changed-only))
  (fenrir/magit-nested-list--render))

(defun fenrir/magit-nested-list-filter (regexp)
  "Filter displayed projects by REGEXP (empty string clears the filter)."
  (interactive
   (list (read-string "Filter projects (regexp, empty clears): "
                      fenrir/magit-nested-list--filter)))
  (setq fenrir/magit-nested-list--filter (if (string-empty-p regexp) nil regexp))
  (fenrir/magit-nested-list--render))

(defvar-keymap fenrir/magit-nested-list-mode-map
  :doc "Keymap for `fenrir/magit-nested-list-mode'."
  :parent tabulated-list-mode-map
  "RET" #'fenrir/magit-nested-list-open-magit
  "o"   #'fenrir/magit-nested-list-open-dired
  "f"   #'fenrir/magit-nested-list-find-file
  "D"   #'fenrir/magit-nested-list-set-depth
  "+"   #'fenrir/magit-nested-list-increase-depth
  "="   #'fenrir/magit-nested-list-increase-depth
  "-"   #'fenrir/magit-nested-list-decrease-depth
  "d"   #'fenrir/magit-nested-list-set-dir
  "c"   #'fenrir/magit-nested-list-toggle-changed
  "/"   #'fenrir/magit-nested-list-filter
  "g"   #'fenrir/magit-nested-list-refresh)

(define-derived-mode fenrir/magit-nested-list-mode tabulated-list-mode "GitProjects"
  "Major mode for browsing nested git projects under a directory.

\\{fenrir/magit-nested-list-mode-map}"
  (setq tabulated-list-padding 2
        tabulated-list-sort-key '("Project" . nil))
  (hl-line-mode 1))

;;;###autoload
(defun fenrir/magit-nested-list (&optional dir depth)
  "List all git projects under DIR in an interactive `*git-projects*' buffer.
Without a prefix argument, scans the current git toplevel (or `default-directory'
when outside a git repository).  With `C-u', prompts for DIR.
DEPTH defaults to `fenrir/magit-nested-list-depth' (4) and can be adjusted
live inside the buffer with `D', `+', and `-'."
  (interactive
   (list (when current-prefix-arg
           (read-directory-name "Scan git projects under: " default-directory))))
  (let* ((root (file-name-as-directory
                (expand-file-name (or dir
                                      (ignore-errors (magit-toplevel))
                                      default-directory))))
         (buf (get-buffer-create "*git-projects*")))
    (pop-to-buffer-same-window buf)
    (unless (derived-mode-p 'fenrir/magit-nested-list-mode)
      (fenrir/magit-nested-list-mode))
    (setq fenrir/magit-nested-list--dir root
          default-directory root
          fenrir/magit-nested-list--depth (or depth
                                              fenrir/magit-nested-list--depth
                                              fenrir/magit-nested-list-depth)
          fenrir/magit-nested-list--changed-only nil
          fenrir/magit-nested-list--filter nil)
    (fenrir/magit-nested-list-refresh)))

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
