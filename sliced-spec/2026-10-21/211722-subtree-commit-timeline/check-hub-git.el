;;; check-hub-git.el --- 驗收條件 9 and 10: the git menu's commands  -*- lexical-binding: t; -*-

;; Run from ~/.emacs.d after a full init, before anything loads Magit:
;;   emacs --batch -l early-init.el -l init.el -l sliced-spec/2026-10-21/211722-subtree-commit-timeline/check-hub-git.el
;; Prints `magit loaded:', `missing:' (9) and `not callable:' (10).

(require 'transient)

(defun check-hub-git--commands (tree)
  "Every value of a `:command' key anywhere in TREE, a transient layout."
  (let (out)
    (cl-labels ((walk (x)
                  (cond ((vectorp x) (mapc #'walk x))
                        ((consp x)
                         (while (consp x)
                           (if (and (eq (car x) :command) (consp (cdr x)))
                               (progn (push (cadr x) out) (setq x (cddr x)))
                             (walk (car x))
                             (setq x (cdr x))))))))
      (walk tree))
    (delete-dups (nreverse out))))

(let* ((magit (featurep 'magit))
       (have (check-hub-git--commands (get 'fenrir/hub-git 'transient--layout)))
       (want (append
              '(fenrir/magit-subtree-commits fenrir/magit-subtree-log
                fenrir/magit-subtree-file-log fenrir/magit-status-overview)
              (let (vc) (map-keymap (lambda (_k c) (push c vc)) fenrir/magit-vc-map) vc)
              ;; `fenrir/hub-git' at 24361ac.
              '(magit-status magit-dispatch magit-file-dispatch difftastic-magit-diff
                magit-blame blamer-mode magit-log-buffer-file git-timemachine
                diff-hl-next-hunk diff-hl-previous-hunk diff-hl-show-hunk git-link
                smerge-next smerge-prev smerge-keep-upper smerge-keep-lower
                smerge-keep-all transient-quit-one)))
       (missing (seq-remove (lambda (c) (memq c have)) (delete-dups want)))
       (uncallable (seq-remove #'commandp have)))
  (princ (format "magit loaded: %s\n" magit))
  (princ (format "suffix commands: %d\n" (length have)))
  (princ (format "missing: %s\n" (if missing (mapconcat #'symbol-name missing " ") "none")))
  (princ (format "not callable: %s\n"
                 (if uncallable (mapconcat #'symbol-name uncallable " ") "none"))))

;;; check-hub-git.el ends here
