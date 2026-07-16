;;; init-org.el --- Org-mode (light touch) -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 12 of the pre-split monolithic init.el (see git log for the move).
;; Minimal; org-agenda is wired at inbox-only scope below -- expand as needed.

;;; Code:

(use-package org
  :ensure nil
  ;; `C-c c' -- global `org-capture': jot a TODO / note from ANY buffer without
  ;; leaving what you're doing (the org quick-inbox gesture).  Verified free:
  ;; `C-c a' is aidermacs, `C-c r c' is org-roam-capture (a DIFFERENT flow --
  ;; roam creates a linked Zettelkasten node; this drops an unlinked line into a
  ;; flat inbox for later refiling).  Global bind (not `:map org-mode-map') so it
  ;; fires from code buffers too.
  ;; `C-c A' -- global `org-agenda' (verified free: `lookup-key' returned nil;
  ;; lowercase `C-c a' is aidermacs, per the capture comment above).
  :bind (("C-c c" . org-capture)
         ("C-c A" . org-agenda))
  :custom
  (org-startup-indented t)               ; visually indent by outline level
  (org-hide-emphasis-markers t)          ; show *bold* as bold, hide the stars
  (org-src-fontify-natively t)           ; syntax-highlight inside #+begin_src
  (org-fontify-whole-heading-line t)     ; extend heading face across the line, not just the text
  (org-fontify-done-headline t)          ; visually distinguish DONE headlines' title text too
  (org-ellipsis " ▾")                    ; single unambiguous fold glyph -- "..." reads as literal text on a dense TTY
  ;; Auto-render inline images on file open (GUI frames only; TTY can't display
  ;; them).  Without this an [[file:...]] image link shows as raw text until you
  ;; `C-c C-x C-v', which reads as a "broken" link -- see the org-roam vault's
  ;; image-link notes.  Global: applies to every org file, not just the vault.
  (org-startup-with-inline-images t)
  ;; org home = the roam vault dir (org-roam already points here, see
  ;; [`init-org-roam.el'](init-org-roam.el)).  Gives `org-capture' / refile /
  ;; a future agenda a sane default root instead of the built-in "~/org" that
  ;; doesn't exist on this box.
  (org-directory (file-truename "~/code/org-roam"))
  ;; Agenda scope is DELIBERATELY `inbox.org' only, not the whole vault -- the
  ;; vault holds ~1500 notes and (checked, not assumed) almost none carry a
  ;; TODO headline, so pointing `org-agenda-files' at the root would buy scan
  ;; cost and noise for nothing.  `inbox.org' is created by the first
  ;; `org-capture' below; until then the agenda is legitimately empty.
  ;; Expanding this list to more of the vault later is a deliberate future
  ;; choice, not an oversight.
  (org-agenda-files (list (expand-file-name "inbox.org" org-directory)))
  ;; Capture targets an `inbox.org' at the vault root.  It has NO `:ID:', so
  ;; org-roam treats it as a plain file, not a node -- captured TODOs stay out
  ;; of the graph until you deliberately refile them into a real note.  `%?'
  ;; is where point lands; `%U' an inactive timestamp; `%a' a back-link to the
  ;; buffer you captured from (so a code-side TODO remembers its origin).
  (org-capture-templates
   '(("t" "Todo"  entry (file+headline "inbox.org" "Tasks")
      "* TODO %?\n  %U\n  %a" :empty-lines 1)
     ("n" "Note"  entry (file+headline "inbox.org" "Notes")
      "* %?\n  %U" :empty-lines 1))))

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
  (org-modern-table nil)
  ;; The default `org-modern-star' is 'fold (fold indicators only), which
  ;; leaves heading depth legible only via indentation -- give each level a
  ;; distinct bullet glyph instead.
  (org-modern-star '("◉" "○" "✸" "✿" "◆"))
  ;; The default (2) draws the #+begin_src side bar in the FRINGE -- TTY
  ;; frames have no fringe, so in the daily `emacsclient -nw' session it
  ;; silently rendered nothing.  Off, honestly.
  (org-modern-block-fringe nil))

;; valign: overlay-based visual column realignment for tables -- pure display,
;; never touches buffer text.  org-modern-table is OFF above (Unicode box-
;; drawing reads too heavy with CJK), but that leaves the ASCII `|' pipes with
;; no per-glyph-width awareness, so CJK rows look ragged against ASCII ones.
;; valign measures actual display width (CJK glyphs count as 2 columns) and
;; pads with overlays -- fixes that independently of org-modern-table's
;; on/off state.  TTY-safe: no child frames.
(use-package valign
  :hook (org-mode . valign-mode)
  :custom
  (valign-fancy-bar nil))   ; keep ASCII `|' bars, matching org-modern-table's choice

;; org-appear: temporarily reveal the *bold* / =verbatim= / [[link]] markup of
;; whichever element point is on -- the complement to `org-hide-emphasis-markers'
;; above, so you can still edit the markers without globally un-hiding them.
(use-package org-appear
  :hook (org-mode . org-appear-mode))

;; org-babel: enable evaluation of `#+begin_src' blocks in the languages this
;; user actually writes in org notes -- `emacs-lisp' (already on by default),
;; `python' (python3, present), and `shell' (ob-shell, built-in).  The diagram
;; languages `plantuml' / `mermaid' are wired separately in
;; [`init-diagrams.el'](init-diagrams.el) -- both use the same additive
;; `org-babel-do-load-languages' append, so the two forms compose regardless of
;; load order.  `org-confirm-babel-evaluate' is deliberately LEFT at its default
;; `t': every block execution prompts for confirmation, so a maliciously-crafted
;; org file can't silently run code on open -- the safe posture for a vault that
;; also ingests notes converted from elsewhere.
(with-eval-after-load 'org
  (org-babel-do-load-languages
   'org-babel-load-languages
   (append org-babel-load-languages
           '((emacs-lisp . t)
             (python . t)
             (shell . t)))))

;; org-download: paste/drag images into org buffers.  Drag-and-drop
;; (`org-download-dnd') is wired automatically -- the package's own top-level
;; `(org-download-enable)' call (unconditional, end of org-download.el)
;; prepends it into `dnd-protocol-alist' the moment the package loads.  It
;; takes required (uri action) args and has NO `(interactive)' spec, so it's
;; a DND protocol handler, not a bindable command -- nothing to put on a key,
;; and it only ever fires from a real GUI drag event anyway (inert on a TTY
;; frame).  The one command that belongs on a keybinding is
;; `org-download-clipboard' (paste whatever image is on the system
;; clipboard).  Verified free in plain `org-mode-map' (`lookup-key' returned
;; nil); does not collide with eglot's `C-c i' organize-imports (that's
;; `eglot-mode-map', a minor mode never active in .org buffers -- no
;; `eglot-ensure' hook anywhere targets `org-mode-hook').  On a TTY-only
;; session `org-download-clipboard' degrades gracefully: it signals a
;; catchable `user-error' if xclip/wl-paste is missing, or silently no-ops if
;; the clipboard tool can't reach a display -- verified from upstream source,
;; no crash risk.
(use-package org-download
  :ensure t
  :after org
  :bind (:map org-mode-map
         ("C-c i" . org-download-clipboard)))

(provide 'init-org)
;;; init-org.el ends here
