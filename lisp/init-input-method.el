;;; init-input-method.el --- Emacs-native Chinese input (emacs-rime) -*- lexical-binding: t; -*-

;;; Commentary:
;; Chinese input inside Emacs goes through emacs-rime, an Emacs input method
;; over the system librime -- the same engine fcitx5 runs -- so the `bopomofo_tw'
;; 注音 schema works here too.  fcitx5 is expected to stay in English while the
;; focus is in Emacs: with fcitx5 composing, the terminal swallows `C-x' / `M-x'
;; chords, while an Emacs input method is per-buffer and keeps every chord.
;; Toggle with the built-in `C-\' (`toggle-input-method'); RightAlt is keyd's
;; global fcitx5 toggle and never reaches Emacs.
;;
;; Native module: `librime-emacs.so', compiled into the package dir from
;; `lib.c'.  Needs `librime-dev' (apt) for the header and `-lrime'.
;; `rime-activate' compiles it on first use when missing, and recompiles after a
;; package upgrade changes `rime-version'; by hand: `make lib' in elpa/rime-*/.

;;; Code:

(defvar fenrir/rime-fcitx5-dir (expand-file-name "~/.local/share/fcitx5/rime/")
  "The fcitx5 Rime user dir whose `*.custom.yaml' patches Emacs reuses.")

(defun fenrir/rime-link-fcitx5-patches ()
  "Symlink fcitx5's Rime `*.custom.yaml' patches into `rime-user-data-dir'.
The user dirs stay separate -- two processes opening one userdb (leveldb)
fight over its lock -- so each side keeps its own word frequencies, but the
schema list, page size and select keys are maintained once, on the fcitx5 side.
Creating the dir also skips emacs-rime's first-deploy `yes-or-no-p'."
  (make-directory rime-user-data-dir t)
  (when (file-directory-p fenrir/rime-fcitx5-dir)
    (dolist (src (directory-files fenrir/rime-fcitx5-dir t "\\.custom\\.yaml\\'"))
      (let ((dst (expand-file-name (file-name-nondirectory src) rime-user-data-dir)))
        (unless (file-exists-p dst)
          (make-symbolic-link src dst))))))

(defun fenrir/rime-candidate-letter (num select-labels)
  "Label candidate NUM with a letter: A for 1, B for 2, ...
The fcitx5 patches set `menu/alternative_select_keys' to A-O because 注音
uses the digit keys for tones, but librime reports no SELECT-LABELS for that
setting, so the default formatter shows digits that select nothing.  Real
SELECT-LABELS, when a schema has them, still win."
  (if select-labels
      (format "%s. " (nth (1- num) select-labels))
    (format "%c. " (+ ?A (1- num)))))

(use-package rime
  :defer t
  :init
  (setq default-input-method "rime")
  :custom
  ;; no-littering has no rule for rime; the default would be ~/.emacs.d/rime/.
  (rime-user-data-dir (no-littering-expand-var-file-name "rime/"))
  ;; posframe in a GUI frame; `rime--posframe-display-content' falls back to
  ;; the minibuffer when `posframe-workable-p' is nil, i.e. in a TTY frame.
  (rime-show-candidate 'posframe)
  ;; RET commits the converted text, as in fcitx5.  The default t commits the
  ;; raw keys: `su3cl3 RET' inserts "su3cl3" instead of 你好.  S-RET still
  ;; commits the preedit (the 注音 symbols).
  (rime-return-insert-raw nil)
  (rime-candidate-num-format-function #'fenrir/rime-candidate-letter)
  ;; Auto-English: in code outside strings/comments, and right after a Latin
  ;; letter (so `foo中' needs no toggle).  org / text buffers never switch.
  (rime-disable-predicates '(rime-predicate-prog-in-code-p
                             rime-predicate-after-alphabet-char-p))
  :config
  (fenrir/rime-link-fcitx5-patches))

(provide 'init-input-method)
;;; init-input-method.el ends here
