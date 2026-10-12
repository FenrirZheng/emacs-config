;;; Throwaway GUI acceptance harness: inject key events into THIS Emacs only.
;; Run: DISPLAY=:0 emacs -l <this file>  (from ~/.emacs.d/lisp), then drive it with
;; `emacsclient -s srchgui -e (gh-keys "C-t")`, `(gh-type "init")`, `(gh-state (quote tag))`.
;; Send `C-g` in its own call: a quit discards the events queued behind it.
;; Exit with `(let ((kill-emacs-hook nil)) (kill-emacs 0))`, then rm the srchgui socket.
(setq server-name "srchgui")
(server-start)
(defvar gh-log (expand-file-name "gui-harness-log.txt" temporary-file-directory))
(defun gh-keys (&rest keys)
  "Queue KEYS (kbd strings) as real input events for the selected GUI frame."
  (setq unread-command-events
        (append unread-command-events
                (mapcan (lambda (k) (listify-key-sequence (kbd k))) keys)))
  'queued)
(defun gh-type (s) (setq unread-command-events (append unread-command-events (string-to-list s))) 'queued)
(defun gh-state (&optional tag)
  (let* ((mb (active-minibuffer-window))
         (line (format "%S\n"
                       (list tag
                             :gui (display-graphic-p) :frame-type (framep (selected-frame))
                             :prompt (and mb (with-current-buffer (window-buffer mb) (minibuffer-prompt)))
                             :input (and mb (with-current-buffer (window-buffer mb) (minibuffer-contents-no-properties)))
                             :search (and (boundp 'fenrir/search--state) fenrir/search--state)
                             :buffer (buffer-name (window-buffer (selected-window)))
                             :mode (with-current-buffer (window-buffer (selected-window)) major-mode)
                             :cands (and mb (boundp 'vertico--total) (with-current-buffer (window-buffer mb) vertico--total))))))
    (with-temp-buffer (insert line) (append-to-file (point-min) (point-max) gh-log))
    line))
(add-hook 'minibuffer-setup-hook
          (lambda () (gh-state (list 'setup this-command (key-binding (kbd "C-t")) (key-binding (kbd "C-.")) fenrir/search-prompt-mode))) 90)
