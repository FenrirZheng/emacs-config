;;; init-git.el --- Git -- Magit + diff-hl -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 9 of the pre-split monolithic init.el (see git log for the move).
;; Magit, diff-hl, magit-todos, magit-delta, difftastic.

;;; Code:

;; Magit: the reason a lot of people use Emacs at all.
(use-package magit
  :bind (("C-x g" . magit-status)
         ("C-x M-g" . magit-dispatch))
  :custom
  ;; Refine only the hunk at point, not 'all -- 'all turns large diffs into a
  ;; font-lock circus.
  (magit-diff-refine-hunk t)
  ;; Flip to t when investigating slow refreshes -- each section logs its
  ;; elapsed time to *Messages*. M-x magit-toggle-verbose-refresh does the same.
  ;; (magit-refresh-verbose t)
  :config
  ;; diff-hl computes its gutter through vc.el (`vc-backend'), so vc.el needs a
  ;; backend enabled -- keep ONLY Git, since the stock list also probes
  ;; CVS/SVN/Hg/Bzr/... once per file for nothing. Interactive VC still goes
  ;; exclusively through Magit (see the `C-x v' remap below).
  (setq vc-handled-backends '(Git)))

;; Persistent, context-sensitive help.  Keep rendering free of Git subprocesses;
;; `magit-diff-type' can resolve revisions, so cache it at refresh time.
(defcustom fenrir/magit-hints-default t
  "Whether new Magit status, log, revision and diff buffers show hints."
  :type 'boolean :group 'magit)

(defcustom fenrir/magit-hints-alist
  '((unstaged ("s" "stage" magit-stage) ("k" "discard" magit-discard)
              ("RET" "diff" magit-diff-unstaged))
    (staged ("u" "unstage" magit-unstage) ("k" "discard" magit-discard)
            ("RET" "diff" magit-diff-staged) ("c" "commit menu" magit-commit))
    (untracked ("s" "track" magit-stage) ("k" "delete" magit-discard)
               ("i" "ignore menu" magit-gitignore))
    ((file unstaged) ("s" "stage file" magit-stage) ("k" "discard file" magit-discard)
                     ("RET" "visit" magit-diff-visit-file))
    ((hunk unstaged) ("s" "stage hunk/region" magit-stage)
                     ("k" "discard hunk/region" magit-discard)
                     ("RET" "visit" magit-diff-visit-file))
    ((file staged) ("u" "unstage file" magit-unstage) ("k" "discard file" magit-discard)
                   ("c" "commit menu" magit-commit) ("RET" "visit" magit-diff-visit-file))
    ((hunk staged) ("u" "unstage hunk/region" magit-unstage)
                   ("k" "discard hunk/region" magit-discard)
                   ("RET" "visit" magit-diff-visit-file))
    ((file untracked) ("s" "track" magit-stage) ("k" "delete" magit-discard)
                      ("i" "ignore menu" magit-gitignore)
                      ("RET" "visit" magit-diff-visit-file))
    (file ("RET" "visit" magit-diff-visit-file) ("d" "diff menu" magit-diff))
    (hunk ("RET" "visit" magit-diff-visit-file) ("d" "diff menu" magit-diff))
    (commit ("RET" "show" magit-show-commit) ("b" "branch menu" magit-branch)
            ("r" "rebase menu" magit-rebase) ("A" "cherry-pick menu" magit-cherry-pick)
            ("y" "refs" magit-show-refs))
    (branch ("RET" "visit ref" magit-visit-ref) ("b" "branch menu" magit-branch)
            ("l" "log menu" magit-log) ("y" "refs" magit-show-refs))
    (stash ("RET" "show" magit-stash-show) ("a" "apply" magit-stash-apply)
           ("A" "pop" magit-stash-pop) ("k" "drop" magit-stash-drop))
    (stashes ("RET" "list" magit-stash-list) ("z" "stash menu" magit-stash))
    (default ("c" "commit menu" magit-commit) ("P" "push menu" magit-push)
             ("F" "pull menu" magit-pull) ("b" "branch menu" magit-branch)
             ("l" "log menu" magit-log) ("z" "stash menu" magit-stash)))
  "Hints keyed by section TYPE or (TYPE DIFF-TYPE), with a default fallback.
Each entry contains (KEY LABEL COMMAND) triples.  A hint is shown only
when KEY actually invokes COMMAND at point, including command remapping.
Diff type distinguishes staged, unstaged and untracked files/hunks.
Unknown sections use default; TAB and help are added independently.
These are command reminders, not a guarantee that Git will accept an action."
  :type '(alist :key-type sexp
                :value-type (repeat (list string string function)))
  :group 'magit)

(defvar-local fenrir/magit-hints--saved-header nil)
(defvar-local fenrir/magit-hints--diff-type nil)
(defconst fenrir/magit-hints--header
  '((:eval (fenrir/magit-hints--render))))

(defface fenrir/magit-hints-key
  '((t :inherit (font-lock-keyword-face fixed-pitch) :weight bold))
  "Keys in the Magit hint toolbar."
  :group 'magit)

(defface fenrir/magit-hints-context
  '((t :inherit (shadow fixed-pitch)))
  "Context and repository titles in the Magit hint toolbar."
  :group 'magit)

(defface fenrir/magit-hints-label
  '((t :inherit (header-line fixed-pitch)))
  "Action labels and spacing in the Magit hint toolbar."
  :group 'magit)

(defun fenrir/magit-hints--item (entry)
  "Format ENTRY only if its key actually invokes its command at point."
  (when (eq (key-binding (kbd (car entry))) (nth 2 entry))
    (let* ((label (replace-regexp-in-string
                   "\\(?: file\\| hunk/region\\)\\'" "" (nth 1 entry)))
           (label (replace-regexp-in-string "[\n\r]" " " label)))
      (concat (propertize (car entry) 'face 'fenrir/magit-hints-key)
              " " (if (string-empty-p label) label
                    (concat (upcase (substring label 0 1))
                            (substring label 1)))))))

(defun fenrir/magit-hints--layout (width context actions title fold help)
  "Fit complete toolbar items into WIDTH columns, with HELP on the right.
Prefer HELP and the first action.  Drop TITLE, trailing ACTIONS, CONTEXT,
then FOLD as space shrinks.  Never truncate an action or a key."
  (let* ((width (max 0 width))
         (left (lambda () (string-join (delq nil (append (list context)
                                                        actions (list title)))
                                       "   ")))
         (right (lambda () (string-join (delq nil (list fold help)) "   ")))
         (fits (lambda ()
                 (<= (+ 2 (string-width (funcall left))
                        (string-width (funcall right))
                        (if (and (not (string-empty-p (funcall left)))
                                 (not (string-empty-p (funcall right)))) 3 0))
                     width))))
    (unless (funcall fits) (setq title nil))
    (while (and (cdr actions) (not (funcall fits)))
      (setq actions (butlast actions)))
    (unless (funcall fits) (setq context nil))
    (unless (funcall fits) (setq fold nil))
    (unless (funcall fits) (setq actions nil))
    ;; Even exceptionally small windows retain the help key if it fits.
    (unless (funcall fits)
      (setq help (and help (>= width 3)
                      (propertize "?" 'face 'fenrir/magit-hints-key))))
    (let* ((lhs (funcall left))
           (rhs (funcall right))
           (padding (max 0 (- width 2 (string-width lhs) (string-width rhs)))))
      (if (< width 2) ""
        (let ((text (concat " " lhs (make-string padding ?\s) rhs " ")))
          (add-face-text-property 0 (length text) 'fenrir/magit-hints-label t text)
          text)))))

(defvar-local fenrir/magit-hints--cache nil
  "(KEY . RESULT) of the last render; cleared on every Magit refresh.")

(defun fenrir/magit-hints--render ()
  "Return the toolbar for the window being redisplayed, cached per state.
The header `:eval' runs on every redisplay, so recompute only when point,
window, width, region or the saved title changed."
  (let* ((win (selected-window))
         (pt (if (eq (window-buffer win) (current-buffer))
                 (window-point win)
               (point)))
         (key (list win pt (window-body-width) (use-region-p)
                    (and (use-region-p) (cons (region-beginning) (region-end)))
                    fenrir/magit-hints--saved-header
                    (buffer-modified-tick))))
    (if (equal key (car fenrir/magit-hints--cache))
        (cdr fenrir/magit-hints--cache)
      (let ((result (fenrir/magit-hints--compute)))
        (setq fenrir/magit-hints--cache (cons key result))
        result))))

(defun fenrir/magit-hints--compute ()
  "Render a toolbar for the window being redisplayed, without running Git."
  (save-excursion
    ;; Redisplay and format-mode-line select the window being formatted.
    (when (eq (window-buffer (selected-window)) (current-buffer))
      (goto-char (window-point (selected-window))))
    (let* ((section (magit-section-at))
           (type (and section (oref section type)))
           (diff-type (if (derived-mode-p 'magit-status-mode)
                          (let ((ancestor section) result)
                            (while ancestor
                              (when (memq (oref ancestor type)
                                          '(staged unstaged untracked))
                                (setq result (oref ancestor type)))
                              (setq ancestor (oref ancestor parent)))
                            result)
                        fenrir/magit-hints--diff-type))
           (entries (or (alist-get (list type diff-type) fenrir/magit-hints-alist
                                   nil nil #'equal)
                        (alist-get type fenrir/magit-hints-alist)
                        (alist-get 'default fenrir/magit-hints-alist)))
           (scope (if (use-region-p) "Region"
                    (pcase type
                      ((or 'file 'hunk) (symbol-name type))
                      (_ nil))))
           (context (if scope
                        (string-join
                         (delq nil (list (and (memq diff-type '(staged unstaged untracked))
                                              (capitalize (symbol-name diff-type)))
                                         (if (memq diff-type '(staged unstaged untracked))
                                             scope
                                           (capitalize scope)))) " ")
                      (if type (capitalize (replace-regexp-in-string
                                            "-" " " (symbol-name type)))
                        "Magit")))
           ;; Magit's alignment properties would draw its title over our hints.
           (title (string-trim (replace-regexp-in-string
                                "[\n\r]" " "
                                (substring-no-properties
                                 (format-mode-line fenrir/magit-hints--saved-header)))))
           (text (fenrir/magit-hints--layout
                  (max 0 (1- (window-body-width)))
                  (propertize context 'face 'fenrir/magit-hints-context)
                  ;; The Jump menu goes LAST: `--layout' drops trailing actions
                  ;; first, so a narrow window sheds the menu before it sheds a
                  ;; stage/unstage action.  `j o' is a transient sequence, not a
                  ;; keymap chord, so only `j' itself is offered to `--item'.
                  (delq nil (append
                             (mapcar #'fenrir/magit-hints--item entries)
                             (and (derived-mode-p 'magit-status-mode)
                                  (list (fenrir/magit-hints--item
                                         '("j" "Jump menu" magit-status-jump))))))
                  (unless (string-empty-p title)
                    (propertize title 'face 'fenrir/magit-hints-context))
                  (fenrir/magit-hints--item '("TAB" "Fold" magit-section-toggle))
                  (fenrir/magit-hints--item '("?" "Help" magit-dispatch)))))
      ;; Keep literal percent signs in labels and revision titles intact.
      (list "" text))))

(defun fenrir/magit-hints--install ()
  "Preserve the current title and install the hint header after refresh."
  (when fenrir/magit-hints-mode
    (setq fenrir/magit-hints--cache nil)
    (unless (equal header-line-format fenrir/magit-hints--header)
      (setq fenrir/magit-hints--saved-header header-line-format))
    (setq fenrir/magit-hints--diff-type
          (when (derived-mode-p 'magit-diff-mode)
            (magit-diff-type)))
    (setq-local header-line-format fenrir/magit-hints--header)))

(define-minor-mode fenrir/magit-hints-mode
  "Toggle persistent context hints in this Magit buffer.
New status, log, revision and diff buffers enable this by default.
The previous header is retained after the hints, and restored on disable."
  :lighter nil
  (if fenrir/magit-hints-mode
      (progn
        (require 'magit)
        (unless (memq major-mode '(magit-status-mode magit-log-mode
                                  magit-revision-mode magit-diff-mode))
          (setq fenrir/magit-hints-mode nil)
          (user-error "Hints support Magit status, log, revision and diff buffers"))
        (add-hook 'magit-refresh-buffer-hook #'fenrir/magit-hints--install nil t)
        (fenrir/magit-hints--install))
    (remove-hook 'magit-refresh-buffer-hook #'fenrir/magit-hints--install t)
    (when (equal header-line-format fenrir/magit-hints--header)
      (setq-local header-line-format fenrir/magit-hints--saved-header)))
  (force-mode-line-update))

(defun fenrir/magit-hints--maybe-enable ()
  "Enable hints according to the default, excluding selection modes."
  (when (and fenrir/magit-hints-default
             (memq major-mode '(magit-status-mode magit-log-mode
                                magit-revision-mode magit-diff-mode)))
    (fenrir/magit-hints-mode 1)))

(with-eval-after-load 'magit
  ;; Magit refreshes its title through this function, including outside refresh.
  (advice-add 'magit-set-header-line-format :after #'fenrir/magit-hints--title-changed)
  (dolist (hook '(magit-status-mode-hook magit-log-mode-hook
                  magit-revision-mode-hook magit-diff-mode-hook))
    (add-hook hook #'fenrir/magit-hints--maybe-enable))
  ;; Also cover already-open buffers when reloading this module.
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (unless (local-variable-p 'fenrir/magit-hints-mode)
        (fenrir/magit-hints--maybe-enable)))))

(defun fenrir/magit-hints--title-changed (&rest _)
  "Reinstall hints when Magit changes the underlying title."
  (when fenrir/magit-hints-mode
    (fenrir/magit-hints--install)))

;; Status overview: get back to a file-level view of the working tree.
;;
;; The native FRESH defaults are already close to that: `staged'/`unstaged'
;; groups are created shown (`magit-insert-unstaged-changes' passes no HIDE
;; argument), tracked file bodies are created hidden in status mode
;; (`magit-diff-insert-file-section' hides on `derived-mode-p'), and only
;; `untracked' is created hidden (`magit-insert-files' passes HIDE=t).  What
;; drifts away from it is the VISIBILITY CACHE -- after a session of folding,
;; whole groups are collapsed and not one filename is on screen.
;;
;; Native `M-2' (`magit-section-show-level-2-all') gets a level-2 view back, but
;; it rewrites the WHOLE root tree: stashes, unpushed, unpulled, everything.
;; This command touches the three change groups and nothing else -- no other
;; section, no Git diff filter, no Magit option, and no Git subprocess.
;;
;; It is a one-way fold, NOT a toggle: `magit-section-show'/`-hide' update the
;; native visibility cache exactly as a manual fold does, so a later `g' keeps
;; the overview rather than restoring the diffs that happened to be open before.

(defcustom fenrir/magit-status-overview-untracked-threshold nil
  "Untracked file count above which the overview asks before expanding.
nil means follow `magit-status-file-list-limit' (Magit's own default is
100).  Expanding the untracked group runs its lazy washer, which inserts
up to that many file lines; in a repository whose working tree is mostly
untracked -- `$HOME' is the local example, with a few hundred entries --
that is a wall of text nobody asked for, so `fenrir/magit-status-overview'
asks first.  A prefix argument answers yes without prompting."
  :type '(choice (const :tag "Follow magit-status-file-list-limit" nil)
                 natnum)
  :group 'magit)

(defconst fenrir/magit-status-overview--groups '(staged unstaged untracked)
  "Root-level status sections `fenrir/magit-status-overview' operates on.")

(defun fenrir/magit-status-overview--threshold ()
  "Resolve `fenrir/magit-status-overview-untracked-threshold'."
  (or fenrir/magit-status-overview-untracked-threshold
      magit-status-file-list-limit))

(defun fenrir/magit-status-overview--child-count (section)
  "Return the child count Magit rendered into SECTION's heading, or nil.
`magit-insert-files' hands `magit-insert-heading' the FULL file count, so
this reads the real total even when the list itself is truncated at
`magit-status-file-list-limit' -- and reads it off the buffer, without
asking Git anything."
  (and magit-section-show-child-count
       (save-excursion
         (goto-char (oref section start))
         (and (re-search-forward " (\\([0-9]+\\))[ \t]*$" (line-end-position) t)
              (string-to-number (match-string 1))))))

(defun fenrir/magit-status-overview--expand-untracked-p (section force)
  "Return non-nil when the untracked SECTION should be expanded.
Ask first when it is still collapsed and holds more files than
`fenrir/magit-status-overview--threshold'.  FORCE (the command's prefix
argument) and a batch Emacs answer yes without prompting; an unreadable
count also answers yes, since the point of the overview is to show files."
  (let ((count (fenrir/magit-status-overview--child-count section))
        (limit (fenrir/magit-status-overview--threshold)))
    (or force
        noninteractive
        (not (oref section hidden))
        (null count)
        (<= count limit)
        (y-or-n-p (format "Untracked files (%d) exceeds %d -- expand anyway? "
                          count limit)))))

(defun fenrir/magit-status-overview--ident-at (pos)
  "Return the section identity at POS, or nil."
  (let ((section (save-excursion (goto-char pos) (magit-section-at))))
    (and section (magit-section-ident section))))

(defun fenrir/magit-status-overview--save-points ()
  "Record where point sits, in this buffer and in every window showing it.
Positions are markers: expanding the untracked group inserts text, which
would invalidate raw integers.  Each is paired with the section identity
there, so a position that the fold hides can climb to its parent heading.
`get-buffer-window-list' with ALL-FRAMES covers the other frames of a
shared daemon -- folding is buffer state, but point is per window."
  (cons (cons (copy-marker (point))
              (fenrir/magit-status-overview--ident-at (point)))
        (mapcar (lambda (window)
                  (list window
                        (copy-marker (window-point window))
                        (fenrir/magit-status-overview--ident-at
                         (window-point window))))
                (get-buffer-window-list nil nil t))))

(defun fenrir/magit-status-overview--visible-position (marker ident)
  "Return a visible position for MARKER, or the nearest visible ancestor of IDENT.
A position the fold did not hide is kept as it is -- only a point that the
overview made invisible has to move.  Returns nil when nothing in IDENT's
lineage survived."
  (let ((pos (and marker (marker-position marker))))
    (if (and pos (not (invisible-p pos)))
        pos
      (let (found)
        (while (and ident (not found))
          (let ((section (magit-get-section ident)))
            (when (and section (not (invisible-p (oref section start))))
              (setq found (oref section start))))
          (unless found (setq ident (cdr ident))))
        found))))

(defun fenrir/magit-status-overview--restore-points (saved)
  "Put point back on a visible line for SAVED, then release its markers."
  (pcase-let ((`(,marker . ,ident) (car saved)))
    (when-let* ((pos (fenrir/magit-status-overview--visible-position marker ident)))
      (goto-char pos))
    (set-marker marker nil))
  (pcase-dolist (`(,window ,marker ,ident) (cdr saved))
    (when (and (window-live-p window)
               (eq (window-buffer window) (current-buffer)))
      (when-let* ((pos (fenrir/magit-status-overview--visible-position
                        marker ident)))
        (set-window-point window pos)))
    (set-marker marker nil)))

(defun fenrir/magit-status-overview (&optional force)
  "Fold the status buffer back to a file-level overview.
Expand the `staged', `unstaged' and `untracked' groups so every file
heading is visible, and collapse the file bodies under `staged' and
`unstaged' so a thousand-line diff does not bury the list.  Untracked
entries have no body and are left as Magit rendered them, truncation
notice included.

Nothing else is touched: other root sections, the diff filters and every
Magit option keep their state, no file is staged, unstaged or discarded,
and no Git command is run.  Unrecognised sections are left alone.

With a prefix argument FORCE, expand a large untracked group without
asking -- see `fenrir/magit-status-overview-untracked-threshold'.

This is a one-way fold, not a toggle: it updates the native visibility
cache, so a later `g' keeps the overview instead of reopening the diffs
that were expanded before.  Running it twice changes nothing the second
time.  `TAB' and the usual navigation still work on the result."
  (interactive "P")
  (unless (derived-mode-p 'magit-status-mode)
    (user-error "The status overview only works in a Magit status buffer"))
  (when-let* ((groups (seq-filter
                       (lambda (section)
                         (memq (oref section type)
                               fenrir/magit-status-overview--groups))
                       (and magit-root-section
                            (oref magit-root-section children)))))
    (let ((saved (fenrir/magit-status-overview--save-points))
          (failure nil))
      (condition-case err
          (dolist (group groups)
            (let ((type (oref group type)))
              (when (or (not (eq type 'untracked))
                        (fenrir/magit-status-overview--expand-untracked-p
                         group force))
                ;; Showing the group drains its lazy washer, so the file
                ;; sections exist only after this call -- never before it.
                (magit-section-show group)
                (unless (eq type 'untracked)
                  ;; One level only: file headings stay, file bodies go.
                  (magit-section-hide-children group)))))
        (error (setq failure err)))
      (fenrir/magit-status-overview--restore-points saved)
      ;; A stale section selection would still name sections the fold hid.
      (deactivate-mark)
      (magit-section-update-highlight t)
      (when failure
        ;; Partial folding is kept -- this reports what happened, it does not
        ;; claim a transaction.  Magit's own Git errors are not routed here.
        (user-error "Status overview incomplete: %s"
                    (error-message-string failure))))))

(defvar fenrir/magit-status-overview--entry-warned nil
  "Non-nil once a `magit-status-jump' entry-point problem has been reported.")

(defun fenrir/magit-status-overview--suffix-command (suffix)
  "Return the command SUFFIX runs, or nil.
`transient-get-suffix' hands back the raw LAYOUT ELEMENT, and in this
Transient a suffix element is an unevaluated spec list --
\(transient-suffix :key \"o\" ... :command CMD) -- not an EIEIO object, so
`oref' on it signals `wrong-type-argument'.  Transient's own edit code
reads it as a plist behind the `cdr' alias `transient--suffix-props'; that
alias is internal, so the plist is read directly here.  A group element is
a vector and has no command."
  (and (consp suffix) (plist-get (cdr suffix) :command)))

(defun fenrir/magit-status-overview--install-entry ()
  "Add `o' to `magit-status-jump', unless something else already owns it.
Three hazards, all handled here.  `transient-get-suffix' signals a plain
`error' when the key is absent, so \"free\" has to be read out of a failed
lookup.  `transient-append-suffix' only `message's on failure by default
\(`transient-error-on-insert-failure' is nil), so it is bound to t to make
the fallback reachable.  And appending twice is exactly what reloading this
module does -- hence the already-installed branch.  `M-x
fenrir/magit-status-overview' stays available whatever happens here."
  (let* ((existing (ignore-errors (transient-get-suffix 'magit-status-jump "o")))
         (command (fenrir/magit-status-overview--suffix-command existing)))
    (cond
     ((eq command 'fenrir/magit-status-overview))       ; already installed
     (existing
      (fenrir/magit-status-overview--warn-entry
       (format "`o' in magit-status-jump is taken by %s -- left alone" command)))
     (t
      (condition-case err
          ;; (0 2) is the "Jump using" COLUMN, so the addition has to be a
          ;; group vector; a bare suffix there is refused as a sibling.
          (let ((transient-error-on-insert-failure t))
            (transient-append-suffix 'magit-status-jump '(0 2)
              ["View" ("o" "Overview (fold diffs)" fenrir/magit-status-overview)]))
        (error
         (fenrir/magit-status-overview--warn-entry
          (format "could not add `o' to magit-status-jump: %s"
                  (error-message-string err)))))))))

(defun fenrir/magit-status-overview--warn-entry (detail)
  "Report DETAIL once, pointing at the entry point that always works."
  (unless fenrir/magit-status-overview--entry-warned
    (setq fenrir/magit-status-overview--entry-warned t)
    (display-warning 'fenrir
                     (concat detail "; use M-x fenrir/magit-status-overview")
                     :warning)))

(with-eval-after-load 'magit
  (fenrir/magit-status-overview--install-entry))

;; C-x v : retire vc.el's prefix, hand it to Magit.
;; vc.el's stock `C-x v ...' commands work again (the Git backend is enabled
;; in the magit block above) -- but every interactive VC task here goes
;; through Magit by preference, so replace the whole prefix map: each Magit
;; command keeps the slot vc.el used, so vc muscle memory carries straight
;; over. Six targets are transient prefixes (diff/blame/pull/push/merge/tag)
;; -- the key opens that menu, as in any Magit buffer. vc keys with no crisp
;; Magit counterpart (vc-register, vc-log-incoming/outgoing, vc-region-history,
;; vc-edit-next-command, vc-update-change-log) are dropped -- those `C-x v'
;; slots become undefined.
;;
;; One slot is an addition vc.el never had: `E' pairs with lowercase `e'
;; (magit-ediff-dwim) -- `e' is the quick dwim, `E' compares the visited
;; file against a revision you pick.  It runs the custom command
;; `fenrir/ediff-buffer-vs-revision' (defined below), NOT `ediff-revision'.
(defvar-keymap fenrir/magit-vc-map
  :doc "Magit replacements bound on the retired `C-x v' (vc.el) prefix."
  "e" #'magit-ediff-dwim          ; vc-ediff
  "E" #'fenrir/ediff-buffer-vs-revision  ; addition (see below)
  "=" #'magit-diff-buffer-file    ; vc-diff
  "D" #'magit-diff                ; vc-root-diff
  "l" #'magit-log-buffer-file     ; vc-print-log
  "L" #'magit-log-current         ; vc-print-root-log
  "g" #'magit-blame               ; vc-annotate
  "d" #'magit-status              ; vc-dir
  "v" #'magit-file-stage          ; vc-next-action (magit-stage-buffer-file was
                                  ; renamed in Magit 4.3.2)
  "u" #'magit-file-checkout       ; vc-revert
  "+" #'magit-pull                ; vc-update
  "P" #'magit-push                ; vc-push
  "m" #'magit-merge               ; vc-merge
  "s" #'magit-tag                 ; vc-create-tag
  "r" #'magit-branch-checkout     ; vc-retrieve-tag
  "G" #'magit-gitignore           ; vc-ignore
  "~" #'magit-find-file           ; vc-revision-other-window
  "x" #'magit-file-delete)        ; vc-delete-file
(keymap-set ctl-x-map "v" fenrir/magit-vc-map)

;; The `E' key of `fenrir/magit-vc-map' (C-x v E).  A Magit-native take on
;; Emacs' `ediff-revision': a two-step branch->revision picker (no hash to
;; type) that also works from a Magit revision buffer, not just a working-
;; tree file.  `magit-find-file-noselect' fetches the chosen blob via git.
(defun fenrir/ediff-buffer-vs-revision (rev file)
  "Ediff the current buffer against REV's version of FILE.
Works whether the current buffer is a working-tree file or a Magit
revision buffer (a \"FILE.~REV~\" blob from `magit-find-file'): pick a
branch, then a revision from that branch's commit history of the file,
and that revision is Ediff'd against the current buffer.  A working-
tree buffer is compared as-is, so unsaved edits are part of the diff;
from a revision buffer it is a plain revision-vs-revision comparison."
  (interactive
   ;; `magit-*' helpers are not autoloaded, and an `interactive' form runs
   ;; before the body -- so the require has to happen right here.
   (progn
     (require 'magit)
     ;; A Magit revision buffer has no `buffer-file-name' -- the path it
     ;; shows lives in `magit-buffer-file-name'. Falling back to it lets
     ;; `C-x v E' work while reading a blob, not only the working file.
     (let* ((file   (or buffer-file-name
                        (bound-and-true-p magit-buffer-file-name)
                        (user-error
                         "Buffer %s visits neither a file nor a revision"
                         (buffer-name))))
            (branch (magit-read-branch "Compare against a revision on branch"))
            ;; Step 2's candidates: the file's modification history reachable
            ;; from BRANCH (newest first) -- the revisions on that branch
            ;; where an ediff against this file is meaningful.
            (log    (magit-git-lines "log" branch "--max-count=200"
                                     "--format=%h  %cs  %s"
                                     "--" file)))
       (unless log
         (user-error "%s has no history on branch %s"
                     (file-name-nondirectory file) branch))
       ;; A candidate is "<hash>  <date>  <subject>" -- keep the first token
       ;; (a hash typed by hand passes straight through too).
       (list (car (split-string
                   (magit-completing-read
                    (format "Revision on %s" branch)
                    log nil nil nil 'magit-revision-history)))
             file))))
  (unless rev
    (user-error "No revision selected"))
  (let ((rev-buffer (magit-find-file-noselect rev file)))
    ;; From a revision buffer, picking the very revision it shows would feed
    ;; the same buffer to both sides of the ediff.
    (when (eq rev-buffer (current-buffer))
      (user-error "Pick a revision other than the one this buffer shows"))
    (ediff-buffers rev-buffer (current-buffer))))

;; diff-hl: show added/changed/removed lines in the window margin, live.
;;
;; Chosen over git-gutter: diff-hl integrates cleanly with Magit (the
;; pre/post-refresh hooks below keep the margin in sync after a stage/commit)
;; and is actively maintained. The price is a vc.el dependency -- diff-hl
;; computes its diff via `vc-backend', which is why `vc-handled-backends' has
;; to keep the Git backend (see the Magit block above).
;;
;; `diff-hl-dired-mode' is intentionally NOT hooked: in $HOME (which is itself
;; a git repo with ~1500 tracked files), opening dired triggered a `git status'
;; + `git ls-files' sweep through the vc framework on every revert -- the
;; `emacs ./' in $HOME CPU spike. magit covers dired-side git status anyway.
(use-package diff-hl
  :hook
  ;; Redraw the margin after a Magit refresh (commit/stage/unstage/...).
  ;; The old `diff-hl-magit-pre-refresh' half of the pair was obsoleted in
  ;; diff-hl 1.11.0 (aliased to `ignore') -- `post' alone does the job now.
  (magit-post-refresh . diff-hl-magit-post-refresh)
  ;; Hunk-level gutter actions on a `C-c v' prefix ("VCS changes") -- the modern
  ;; IDE "jump between changes / preview / revert / stage this hunk" the gutter
  ;; offers, without opening a full Magit buffer.  (The `C-x v' prefix is taken
  ;; by `fenrir/magit-vc-map' above, so diff-hl's own command map is unreachable
  ;; -- hence these explicit binds.)  `diff-hl-show-hunk' previews inline on TTY;
  ;; `diff-hl-stage-current-hunk' stages just the hunk at point.
  :bind (("C-c v n" . diff-hl-next-hunk)
         ("C-c v p" . diff-hl-previous-hunk)
         ("C-c v s" . diff-hl-show-hunk)
         ("C-c v r" . diff-hl-revert-hunk)
         ("C-c v S" . diff-hl-stage-current-hunk))
  :init
  ;; Enable in every file buffer, not just `prog-mode': org notes, config
  ;; files and prose are version-controlled too.
  (global-diff-hl-mode 1)
  :config
  ;; Draw indicators in the margin, not the fringe: this config is TTY-only
  ;; (emacsclient -nw in tmux) and TTY frames have no fringe -- without this
  ;; diff-hl-mode is enabled but renders into nothing.
  (diff-hl-margin-mode 1)
  ;; Refresh as you type, not only on save / VC op / Magit refresh -- flydiff
  ;; diffs the buffer against its committed blob, per-buffer, cheap in $HOME.
  (diff-hl-flydiff-mode 1))

;; Make hunk-hopping repeatable: after the first `C-c v n' (or `p'/`s'/`r'),
;; bare `n'/`p'/`s'/`r' continue without the `C-c v' prefix until any other
;; key.  `repeat-mode' is already on (init-defaults.el); `:repeat t' stamps the
;; `repeat-map' property on each command so it joins that machinery.  Stepping
;; through every change in a file is the canonical repeat case.
(defvar-keymap fenrir/diff-hl-hunk-repeat-map
  :doc "Repeat map for diff-hl hunk navigation (see `repeat-mode')."
  :repeat t
  "n" #'diff-hl-next-hunk
  "p" #'diff-hl-previous-hunk
  "s" #'diff-hl-show-hunk
  "r" #'diff-hl-revert-hunk)

;; forge: Magit-native GitHub PR / Issue browsing.  Adds two sections to the
;; magit-status buffer ("Pull requests" and "Issues") and a `@' transient
;; (e.g. `@ p l' to fetch PRs, `@ p p' to act on the PR at point) that lives
;; alongside Magit's other transients.  Same keybindings + UI as the rest of
;; Magit, no second tool to learn.
;;
;; First-time setup (per machine, NOT in this repo):
;;   1.  Mint a GitHub PAT with scopes `repo' + `read:org' --
;;       `gh auth token' already prints one if `gh' is logged in; otherwise
;;       create a fine-grained token under
;;       https://github.com/settings/tokens.
;;   2.  Store it in `~/.authinfo.gpg' as:
;;          machine api.github.com login <user>^forge password <token>
;;       The `^forge' suffix is how forge namespaces the credential apart
;;       from any other api.github.com entry (e.g. `gh' / glab / hub).
;;   3.  In the target repo: `M-x forge-add-repository' (or `@ a').  Forge
;;       clones the issue/PR metadata into a local sqlite DB under
;;       `forge-database-file' (no-littering parks it in `var/').
;;
;; Intentionally NOT enabled: `forge-pull-notifications' -- it polls
;; api.github.com periodically and surfaces results via `message', which
;; dirties the minibuffer in a TTY workflow where every echo-area line is
;; precious.  Reach for `M-x forge-pull' on demand instead.
;;
;; First-run note: not in elpa/ on a fresh clone -- `M-x my/package-refresh'
;; then restart the daemon once so the install runs.  The first
;; `forge-add-repository' will also run a sqlite schema migration; let it.
(use-package forge
  :after magit)

;; magit-todos: add a "TODOs" section to the Magit status buffer listing the
;; hl-todo keywords found across the repo, jumpable like any other section.  It
;; auto-picks a scanner -- `rg' if present (it is here), else `git grep'.
(use-package magit-todos
  :after magit
  :custom
  ;; Don't re-scan TODOs on every status refresh -- in a $HOME-sized repo that
  ;; single section dominates the refresh budget. Press `j T' inside the status
  ;; buffer to update on demand.
  (magit-todos-update nil)
  ;; `:config' (runs after magit-todos is loaded, which `:after magit' gates)
  ;; -- using `:init' here would force magit-todos (and therefore magit) to
  ;; load eagerly at startup, defeating the whole point of `:after magit'.
  :config (magit-todos-mode 1))

;; magit-delta: pipe Magit's diff buffers through git-delta for syntax-
;; highlighted, side-by-side-capable diffs.  `magit-delta-mode' scopes the
;; integration to Magit buffers only -- your CLI `git diff' keeps whatever
;; pager you have configured (or none); it does NOT clobber `[core] pager'
;; globally.
;;
;; Requires the `delta' binary on PATH (Debian: `apt install git-delta',
;; provides /usr/bin/delta).  Without it, the mode loads but Magit just shows
;; the plain diff -- no error.
(use-package magit-delta
  :after magit
  :hook (magit-mode . magit-delta-mode))

;; difftastic: an AST-aware "structural" differ -- compares parse trees, not
;; lines.  Use it when a traditional diff shows "whole function deleted and
;; re-added" but the only real change was a rename, an indent tweak, or moving
;; a block by 20 lines.  Complements (does not replace) magit-delta: delta
;; renders every status-buffer diff cheaply on every refresh; difft is the
;; slower, on-demand option you reach for during code review on a specific
;; commit.
;;
;; Requires the `difft' binary on PATH (no apt package on Debian 13; install
;; via `cargo install --locked difftastic', lands in ~/.cargo/bin/difft).
;;
;; Integration: appends two suffixes to Magit's diff dispatch (press `d' in
;; any Magit buffer to open the transient):
;;     d D  -> difftastic-magit-diff   (dwim on the section / range at point)
;;     d S  -> difftastic-magit-show   (full diff of the commit at point)
;;
;; First-run note: as with every use-package block here, the archive isn't
;; refreshed at startup (see section 1).  After adding magit-delta and this
;; one: `M-x my/package-refresh' then restart Emacs once so both install.
(use-package difftastic
  :after magit
  :config
  (transient-append-suffix 'magit-diff '(-1 -1)
    [("D" "Difftastic diff (dwim)" difftastic-magit-diff)
     ("S" "Difftastic show"        difftastic-magit-show)]))

;; smerge (built-in): the merge-conflict resolver -- the IDE "accept current /
;; incoming / both" UI for `<<<<<<< ======= >>>>>>>' markers.  Two ergonomics
;; fixes over the bare built-in:
;;   1. AUTO-ENABLE: `smerge-mode' is normally off until you `M-x' it, so a
;;      freshly-merged file with conflicts looks like plain broken text.  The
;;      `find-file' / revert hook scans for a conflict marker and turns it on
;;      automatically -- conflicts light up the moment you open the file.
;;   2. MEMORABLE PREFIX: the native prefix is `C-c ^' (awkward, like hideshow's
;;      old chords).  Move it to `C-c m' ("merge"); which-key then lists the
;;      single-letter actions (`n'/`p' next/prev, `RET' keep-current,
;;      `a' keep-all, `u'/`l' keep-upper/lower, `b' keep-base, `R' refine,
;;      `E' ediff) after the prefix.
;; `smerge-command-prefix' is read when the keymap is constructed, so set it via
;; `:custom' (before the mode's map is built) rather than after the fact.
(defun fenrir/smerge-maybe-enable ()
  "Turn on `smerge-mode' if the buffer contains a git conflict marker.
Top-level (not inside the `use-package' `:init') so the byte-compiler sees
the definition before the `add-hook' references it."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^<<<<<<< " nil t)
      (smerge-mode 1))))

(use-package smerge-mode
  :ensure nil
  :custom (smerge-command-prefix (kbd "C-c m"))
  :init
  (add-hook 'find-file-hook #'fenrir/smerge-maybe-enable)
  (add-hook 'after-revert-hook #'fenrir/smerge-maybe-enable))

;; Make conflict-hopping repeatable, same shape as the diff-hl hunk repeat-map
;; above: after the first `C-c m n' (or `p'), bare `n'/`p' keep stepping
;; through every remaining conflict in the file until any other key.
(defvar-keymap fenrir/smerge-repeat-map
  :doc "Repeat map for smerge conflict navigation (see `repeat-mode')."
  :repeat t
  "n" #'smerge-next
  "p" #'smerge-prev)

;; consult-todo: jump to any hl-todo keyword (TODO / FIXME / HACK / BUG / ...)
;; via a consult minibuffer with live preview -- the "navigate to TODO" picker.
;; Complements magit-todos above (which lists them statically in the Magit
;; status buffer): this is the interactive jump-to-one, reusing the same
;; `hl-todo-keyword-faces' set (init-editing.el) so what's coloured in the
;; buffer is exactly what's listed.  `M-g t' = this buffer, `M-g T' = every
;; open buffer (the `M-g' "goto" prefix already holds consult-imenu / -flymake).
(use-package consult-todo
  :after (consult hl-todo)
  :bind (("M-g t" . consult-todo)
         ("M-g T" . consult-todo-all)))

(provide 'init-git)
;;; init-git.el ends here
