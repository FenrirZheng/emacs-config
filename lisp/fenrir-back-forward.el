;;; fenrir-back-forward.el --- Merged jump history: one back/forward pair  -*- lexical-binding: t; -*-

;; Author: fenrir
;; Keywords: convenience

;;; Commentary:

;; Extracted from `init-keys.el' (2026-08) so that the routing layer stays
;; feature-free, as CLAUDE.md requires: this file OWNS the merged-jump-history
;; feature, `init-keys.el' only `require's it and binds `<f6>' / `<f7>'.
;;
;; "Go back to where I was" is a TIER-1-frequency intent that TIER 1 cannot
;; hold, because Emacs keeps FOUR unrelated histories and you must classify
;; which one you mean BEFORE any key is correct: the buffer-local `mark-ring'
;; (`C-u C-SPC'), the `global-mark-ring' (`C-x C-SPC', one slot per BUFFER),
;; the xref marker STACK (`M-,'), and `goto-last-change' (`C-c ;', undo
;; records).  Nine keys, five mental models, one intent.  See
;; [tasks/back-navigation-strategy.md](../tasks/back-navigation-strategy.md).
;;
;; The fix is not a nicer key -- it is deleting the DECISION.  One linear
;; back/forward pair over a SINGLE merged history of far jumps, browser /
;; IDE / vim-`C-o' semantics.  The four mechanisms stay reachable by intent
;; from `<f5> b' (layer 2) for the ~10% where the first press lands wrong.
;;
;; Mechanism: one `:after' advice on `push-mark'.  Almost every far jump in
;; Emacs funnels through it (isearch, xref, `M-<'/`M->', the `consult-*'
;; family), so ONE advice captures everything with no per-command wiring.
;; `push-mark' is natively compiled here, which normally raises the "callers
;; in the same compilation unit direct-call past symbol advice" hazard -- but
;; the strategy doc records a live probe on this Emacs 30.1 where an
;; intra-`simple.el' caller (`mark-whole-buffer') DID hit the advice, so the
;; hazard does not bite for this function.
;;
;; Why local code instead of the `backward-forward' package (the strategy
;; doc's step 3): its source was read at the pinned MELPA commit
;; (58489957, 2016-12-29) and it is not safe to adopt as-is --
;;   * its keymap binds `<C-left>'/`<C-right>', which are `left-word' /
;;     `right-word' here AND what keyd's Left-Win `opt' layer emits;
;;   * `backward-forward-previous-location' calls `(elt RING 0)' before
;;     checking the ring is non-empty -> `wrong-type-argument markerp nil' on
;;     the first press of a fresh session;
;;   * disabling the mode calls `(advice-remove 'ggtags-find-tag-dwim #'push-mark)'
;;     -- the wrong symbol, so that advice leaks and never comes off.
;; The doc's own fallback (step 6) is exactly this: the same ~40 lines locally,
;; no unmaintained dependency, no keymap to fight.  Its `switch-to-buffer'
;; advice is deliberately NOT copied -- it fires on internal calls too, and
;; buffer-level "back" is already `pop-global-mark' (`<f5> b f').

;;; Code:

(defvar fenrir/back-forward-enable t
  "Non-nil means enable `fenrir/back-forward-mode' when this file loads.
Set to nil (one line) to keep the four native histories only.")

(defvar fenrir/back-forward-ring nil
  "Merged jump history: markers, newest first.
Fed by every `push-mark', so it spans buffers and mechanisms.")

(defvar fenrir/back-forward-ring-max 32
  "How many jump positions to remember.")

(defvar fenrir/back-forward-position 0
  "Index into `fenrir/back-forward-ring' of the entry point is standing on.
0 = the newest entry.  Any newly recorded jump resets it to 0, which is
what makes a new jump truncate the forward branch, browser-style.")

(defvar fenrir/back-forward--traversing nil
  "Non-nil while this module is moving point; suppresses recording.")

(defun fenrir/back-forward--record (&rest _args)
  "Record the mark `push-mark' has just set.  Advice: `:after' `push-mark'."
  (unless (or fenrir/back-forward--traversing (minibufferp) (null (mark t)))
    (let ((marker (mark-marker))
          (head   (car fenrir/back-forward-ring)))
      ;; Skip a mark identical to the newest entry -- several commands push
      ;; the same spot twice and that would make one `<f6>' a no-op.
      (unless (and head
                   (eq  (marker-buffer   head) (marker-buffer   marker))
                   (eql (marker-position head) (marker-position marker)))
        (push (copy-marker marker) fenrir/back-forward-ring)
        ;; Trim the tail, releasing the markers so they stop costing edits.
        (let ((tail (nthcdr (1- fenrir/back-forward-ring-max)
                            fenrir/back-forward-ring)))
          (when (cdr tail)
            (dolist (m (cdr tail)) (set-marker m nil))
            (setcdr tail nil)))))
    (setq fenrir/back-forward-position 0)))

(defun fenrir/back-forward--goto (marker)
  "Move point to MARKER.  Return nil if its buffer is gone."
  (let ((buffer (marker-buffer marker)))
    (when (buffer-live-p buffer)
      (let ((fenrir/back-forward--traversing t)
            (position (marker-position marker)))
        (unless (eq buffer (current-buffer))
          (switch-to-buffer buffer))
        (when (or (< position (point-min)) (> position (point-max)))
          (widen))                      ; the mark predates a narrowing
        (goto-char position))
      t)))

(defun fenrir/back-forward--anchor ()
  "Before the first step back, remember where we are standing.
Without this, `fenrir/forward' has nowhere to return to."
  (when (= fenrir/back-forward-position 0)
    (let ((head (car fenrir/back-forward-ring)))
      (unless (and head
                   (eq  (marker-buffer   head) (current-buffer))
                   (eql (marker-position head) (point)))
        ;; NOMSG: this push is bookkeeping, not a user action -- without it
        ;; every first `<f6>' echoes a misleading "Mark set".
        (push-mark nil t)))))           ; recorded by the advice above

(defun fenrir/back-forward--move (delta)
  "Walk DELTA steps along `fenrir/back-forward-ring' (+1 back, -1 forward)."
  (unless fenrir/back-forward-ring
    (user-error "No jump history recorded yet"))
  (when (> delta 0) (fenrir/back-forward--anchor))
  (let ((target (+ fenrir/back-forward-position delta))
        (oldest (1- (length fenrir/back-forward-ring))))
    (cond
     ((< target 0)      (message "Already at the newest position"))
     ((> target oldest) (message "No older position in the jump history"))
     (t
      (let ((marker (nth target fenrir/back-forward-ring)))
        (if (fenrir/back-forward--goto marker)
            (setq fenrir/back-forward-position target)
          ;; Buffer was killed: drop the entry and retry the same step.
          (setq fenrir/back-forward-ring (delq marker fenrir/back-forward-ring))
          (set-marker marker nil)
          (fenrir/back-forward--move delta)))))))

;;;###autoload
(defun fenrir/back ()
  "Go back one position in the merged jump history (`<f6>').
One gesture for all four of Emacs' back-histories: no ring-vs-stack
choice, no prefix.  `fenrir/forward' (`<f7>') undoes it."
  (interactive)
  (fenrir/back-forward--move 1))

;;;###autoload
(defun fenrir/forward ()
  "Go forward one position in the merged jump history (`<f7>').
Undoes `fenrir/back'.  A new jump truncates the forward branch."
  (interactive)
  (fenrir/back-forward--move -1))

;;;###autoload
(define-minor-mode fenrir/back-forward-mode
  "Record every `push-mark' into one merged jump history.
`fenrir/back' / `fenrir/forward' walk it.  Turning the mode off removes
the advice and releases the markers."
  :global t
  :init-value nil
  :group 'convenience
  (if fenrir/back-forward-mode
      (advice-add 'push-mark :after #'fenrir/back-forward--record)
    (advice-remove 'push-mark #'fenrir/back-forward--record)
    (dolist (m fenrir/back-forward-ring) (set-marker m nil))
    (setq fenrir/back-forward-ring nil
          fenrir/back-forward-position 0)))

(when fenrir/back-forward-enable
  (fenrir/back-forward-mode 1))

(provide 'fenrir-back-forward)
;;; fenrir-back-forward.el ends here
