;;; init-system-packages.el --- Thin wrapper over apt/brew/pacman/... -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 3 of the pre-split monolithic init.el (see git log for the move).
;; The `:ensure-system-package' use-package keyword was removed from MELPA, so
;; call `system-packages-ensure' directly when you need an OS package present.

;;; Code:

(use-package system-packages
  :defer t                               ; only used via M-x system-packages-...
  :custom (system-packages-use-sudo t))

(provide 'init-system-packages)
;;; init-system-packages.el ends here
