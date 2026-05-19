;;; init-org.el --- Org-mode (light touch) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 12 of the pre-split monolithic init.el (see git log for the move).
;; Minimal; expand later (org-roam, org-agenda, ...) as needed.

;;; Code:

(use-package org
  :ensure nil
  :custom
  (org-startup-indented t)               ; visually indent by outline level
  (org-hide-emphasis-markers t)          ; show *bold* as bold, hide the stars
  (org-src-fontify-natively t))          ; syntax-highlight inside #+begin_src

;; org-modern: restyle headings, lists, checkboxes, tables, blocks and
;; timestamps for a cleaner look.  Pure display -- it never edits your files.
(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :custom
  ;; Keep tables as plain ASCII `|' separators -- the default Unicode box-
  ;; drawing replacements (│ / ┃) read as visually heavy column dividers,
  ;; especially with CJK content.  Other restyling (headings, lists, blocks)
  ;; stays on.
  (org-modern-table nil))

;; org-appear: temporarily reveal the *bold* / =verbatim= / [[link]] markup of
;; whichever element point is on -- the complement to `org-hide-emphasis-markers'
;; above, so you can still edit the markers without globally un-hiding them.
(use-package org-appear
  :hook (org-mode . org-appear-mode))

(provide 'init-org)
;;; init-org.el ends here
