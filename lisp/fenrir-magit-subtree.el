;;; fenrir-magit-subtree.el --- Which git subtrees changed, inside Magit -*- lexical-binding: t; -*-

;;; Commentary:
;; A front end for the `git-subtree-status' helper binary
;; ([rust/git-subtree-status](../rust/git-subtree-status/README.md), built by
;; `make -C rust/git-subtree-status' into rust/lib/),
;; for repositories built from `git subtree'.  Where the CLI finds no subtree
;; nothing here shows, so ordinary repos are unaffected.
;;
;; * Status buffer: a "Subtrees" section above Untracked, one line per subtree
;;   with a change -- U uncommitted paths, P files not yet on the branch's
;;   upstream (e.g. github/main), and drift from the subtree's own upstream ref.
;;   RET on a line opens that subtree's log.
;; * `fenrir/magit-subtree-log' (`l S' in the log menu): pick a subtree, log
;;   its own history.  Imported commits carry project-relative paths, so a log
;;   of the umbrella limited to `repos/<prefix>' cannot show them; the subtree's
;;   own ref can.
;; * `fenrir/magit-subtree-file-log': the same for the file being visited,
;;   with the prefix stripped from its path.
;;
;; The CLI is read-only and offline (gix, no fetch), ~0.13 s on a 55-subtree
;; repo.  A repo where it finds no subtree is remembered for the session and
;; not asked again; `M-x fenrir/magit-subtree-forget' clears that.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
;; Loaded after Magit (see init-git.el); `magit-insert-section' is a macro, so
;; Magit must be present when this file is read.
(require 'magit)

(declare-function magit-toplevel "magit-git")
(declare-function magit-get-upstream-branch "magit-git")
(declare-function magit-log-setup-buffer "magit-log")
(declare-function magit-log-arguments "magit-log")
(declare-function magit-current-section "magit-section")
(declare-function magit-insert-heading "magit-section")
(declare-function magit-add-section-hook "magit-section")
(declare-function transient-append-suffix "transient")
(declare-function transient-get-suffix "transient")
(defvar magit-insert-section--parent)

(defgroup fenrir/magit-subtree nil
  "Subtree change overview for Magit."
  :group 'magit)

(defcustom fenrir/magit-subtree-program
  (expand-file-name "rust/lib/git-subtree-status" user-emacs-directory)
  "The `git-subtree-status' helper binary.
Built by `make -C rust/git-subtree-status' into the workspace `rust/lib/'.
Until then the Subtrees section stays absent and the commands say so."
  :type 'file)

(defcustom fenrir/magit-subtree-show-in-status t
  "Whether Magit status buffers get the Subtrees section."
  :type 'boolean)

(defvar fenrir/magit-subtree--none (make-hash-table :test #'equal)
  "Toplevels where the CLI found no subtree this session.")

;;;; Parsing (pure)

(defconst fenrir/magit-subtree--fields
  '(:prefix :uncommitted :since :import :import-files
    :upstream-ref :upstream :upstream-files :project-rev)
  "Field names of a porcelain v1 line, in order.")

(defun fenrir/magit-subtree--parse (output)
  "Parse `git-subtree-status --porcelain' OUTPUT into a list of plists.
Return nil unless OUTPUT starts with the v1 header."
  (let ((lines (split-string output "\n" t)))
    (when (equal (car lines) "# git-subtree-status v1")
      (delq nil
            (mapcar
             (lambda (line)
               (let ((cols (split-string line "\t")))
                 (when (= (length cols) (length fenrir/magit-subtree--fields))
                   (let (plist)
                     (cl-loop for key in fenrir/magit-subtree--fields
                              for val in cols
                              do (setq plist
                                       (plist-put plist key
                                                  (cond ((equal val "-") nil)
                                                        ((memq key '(:uncommitted :since :import-files :upstream-files))
                                                         (string-to-number val))
                                                        (t val)))))
                     plist))))
             (cdr lines))))))

(defun fenrir/magit-subtree--drifted-p (row)
  "Non-nil if ROW drifted: from its upstream ref when set, else from its import."
  (if (plist-get row :upstream-ref)
      (member (plist-get row :upstream) '("differs" "missing"))
    (equal (plist-get row :import) "changed")))

(defun fenrir/magit-subtree--changed-p (row)
  "Non-nil if ROW has uncommitted paths, unpushed files or drift."
  (or (> (or (plist-get row :uncommitted) 0) 0)
      (> (or (plist-get row :since) 0) 0)
      (fenrir/magit-subtree--drifted-p row)))

(defun fenrir/magit-subtree--owner (path rows)
  "The row whose prefix is the longest one owning PATH, or nil."
  (let (best)
    (dolist (row rows best)
      (let ((p (plist-get row :prefix)))
        (when (and (or (equal path p) (string-prefix-p (concat p "/") path))
                   (or (null best) (> (length p) (length (plist-get best :prefix)))))
          (setq best row))))))

;;;; Running the CLI

(defun fenrir/magit-subtree--rows (&optional since)
  "Rows for every subtree of the current repo, or nil.
SINCE, when non-nil, is passed as --since (a revision or a date)."
  (when-let* ((top (magit-toplevel))
              ((not (gethash top fenrir/magit-subtree--none)))
              (program (executable-find fenrir/magit-subtree-program)))
    (with-temp-buffer
      (let* ((default-directory top)
             (args (append (list "-C" top "--porcelain" "--all")
                           (and since (list "--since" since))))
             (status (apply #'process-file program nil '(t nil) nil args))
             (rows (and (eq status 0)
                        (fenrir/magit-subtree--parse (buffer-string)))))
        (unless rows
          (puthash top t fenrir/magit-subtree--none))
        rows))))

(defun fenrir/magit-subtree-forget ()
  "Forget which repos had no subtree, so the next refresh asks the CLI again."
  (interactive)
  (clrhash fenrir/magit-subtree--none))

;;;; Status section

(defvar-keymap magit-fenrir-subtree-section-map
  :doc "Keymap for a subtree line in the Subtrees status section."
  "<remap> <magit-visit-thing>" #'fenrir/magit-subtree-log)

(defun fenrir/magit-subtree--line (row width)
  "A status line for ROW, its prefix padded to WIDTH."
  (let ((u (plist-get row :uncommitted))
        (p (plist-get row :since)))
    (concat
     (propertize (string-pad (plist-get row :prefix) width) 'font-lock-face 'magit-filename)
     (if (> u 0) (format "  U:%-3d" u) "       ")
     (if (and p (> p 0)) (format "  P:%-3d" p) "       ")
     (cond ((not (fenrir/magit-subtree--drifted-p row)) "")
           ((plist-get row :upstream-ref)
            (propertize (format "  %s %s (%d)" (plist-get row :upstream)
                                (plist-get row :upstream-ref) (plist-get row :upstream-files))
                        'font-lock-face 'warning))
           (t (propertize (format "  changed since import (%d)" (plist-get row :import-files))
                          'font-lock-face 'warning))))))

(defun fenrir/magit-subtree-insert-section ()
  "Insert the Subtrees section when the repo has subtrees with a change.
P counts files that differ from the current branch's upstream."
  (when fenrir/magit-subtree-show-in-status
    (when-let* ((rows (fenrir/magit-subtree--rows (magit-get-upstream-branch))))
      (let ((changed (seq-filter #'fenrir/magit-subtree--changed-p rows)))
        (when changed
          (magit-insert-section (fenrir-subtrees nil)
            (magit-insert-heading
              (format "Subtrees (%d changed of %d)" (length changed) (length rows)))
            (let ((width (apply #'max (mapcar (lambda (r) (length (plist-get r :prefix))) changed))))
              (dolist (row changed)
                (magit-insert-section (fenrir-subtree row)
                  (insert (fenrir/magit-subtree--line row width) "\n"))))
            (insert "\n")))))))

;;;; Log commands

(defun fenrir/magit-subtree--read (prompt rows &optional default)
  "Read a subtree prefix among ROWS with PROMPT; return its row."
  (let* ((names (mapcar (lambda (r) (plist-get r :prefix)) rows))
         (choice (completing-read prompt names nil t nil nil default)))
    (seq-find (lambda (r) (equal (plist-get r :prefix) choice)) rows)))

(defun fenrir/magit-subtree--at-point (rows)
  "The row for the subtree line at point, or the file being visited."
  (or (when-let* ((section (and (derived-mode-p 'magit-mode) (magit-current-section)))
                  ((eq (oref section type) 'fenrir-subtree)))
        (oref section value))
      (when-let* ((file buffer-file-name)
                  (top (magit-toplevel)))
        (fenrir/magit-subtree--owner (file-relative-name file top) rows))))

(defun fenrir/magit-subtree--log (row files)
  "Open a Magit log of ROW's own history, limited to FILES."
  (let ((rev (plist-get row :project-rev)))
    (unless rev
      (user-error "No ref holds %s's own history; set subtree.%s.upstream"
                  (plist-get row :prefix) (plist-get row :prefix)))
    (magit-log-setup-buffer (list rev) (car (magit-log-arguments)) files)))

;;;###autoload
(defun fenrir/magit-subtree-log ()
  "Log one subtree's own history.
Defaults to the subtree line at point or the file being visited."
  (interactive)
  (let ((rows (or (fenrir/magit-subtree--rows)
                  (user-error "No git subtree found in this repository"))))
    (fenrir/magit-subtree--log
     (or (and (not current-prefix-arg) (fenrir/magit-subtree--at-point rows))
         (fenrir/magit-subtree--read "Subtree log: " rows))
     nil)))

;;;###autoload
(defun fenrir/magit-subtree-file-log ()
  "Log the visited file inside its subtree's own history."
  (interactive)
  (let* ((file (or buffer-file-name (user-error "Not visiting a file")))
         (top (or (magit-toplevel) (user-error "Not in a git repository")))
         (rel (file-relative-name file top))
         (row (or (fenrir/magit-subtree--owner rel (fenrir/magit-subtree--rows))
                  (user-error "%s is not inside a git subtree" rel))))
    (fenrir/magit-subtree--log
     row (list (string-remove-prefix (concat (plist-get row :prefix) "/") rel)))))

;;;; Wiring

(defun fenrir/magit-subtree--install ()
  "Add the status section and `S' in the log menu, once."
  (magit-add-section-hook 'magit-status-sections-hook
                          #'fenrir/magit-subtree-insert-section
                          'magit-insert-untracked-files)
  (let ((existing (ignore-errors (transient-get-suffix 'magit-log "S"))))
    (unless existing
      (condition-case err
          (let ((transient-error-on-insert-failure t))
            (transient-append-suffix 'magit-log "u"
              '("S" "subtree" fenrir/magit-subtree-log)))
        (error (display-warning
                'fenrir (format "could not add `S' to magit-log: %s; use M-x fenrir/magit-subtree-log"
                                (error-message-string err))))))))

(with-eval-after-load 'magit
  (fenrir/magit-subtree--install))

(provide 'fenrir-magit-subtree)
;;; fenrir-magit-subtree.el ends here
