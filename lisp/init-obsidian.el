;;; init-obsidian.el --- Obsidian note vault -- obsidian.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Section 13 of the pre-split monolithic init.el (see git log for the move).
;; The vault at ~/code/obsidian/ is plain Markdown, so `markdown-mode'
;; (init-languages.el) already opens its notes.  obsidian.el adds the
;; Obsidian-specific layer on top: `[[wikilink]]' following, `#tag' awareness,
;; YAML front-matter, daily notes and a quick "jump to any note" command.
;; It's a global minor mode that activates only inside files under
;; `obsidian-directory', so it never touches Markdown buffers elsewhere.
;;
;; First-run note: `use-package-always-ensure' is t but the archive is NOT
;; refreshed at startup (see init.el §1).  If obsidian isn't installed yet,
;; run `M-x my/package-refresh' then restart Emacs once.

;;; Code:

(use-package obsidian
  :custom
  (obsidian-directory "~/code/obsidian")
  ;; New notes from `obsidian-capture' land here (relative to the vault);
  ;; leave at the vault root by default -- adjust if you keep an "Inbox/" dir.
  (obsidian-inbox-directory nil)
  :config
  (global-obsidian-mode 1)
  :bind
  (;; vault-wide commands (available everywhere, "n" = notes)
   ("C-c n n" . obsidian-jump)            ; open / switch to any note
   ("C-c n c" . obsidian-capture)         ; create a new note
   ("C-c n s" . obsidian-search)          ; full-text search the vault
   ;; in-vault editing (obsidian-mode is a minor mode -> these win over
   ;; markdown-mode's own C-c C-o / C-c C-l while inside the vault)
   :map obsidian-mode-map
   ("C-c C-o" . obsidian-follow-link-at-point)
   ("C-c C-l" . obsidian-insert-wikilink)))
;; More via `M-x obsidian-' : obsidian-daily-note, obsidian-backlink-jump,
;; obsidian-move-file, obsidian-rename, obsidian-update, ...

(provide 'init-obsidian)
;;; init-obsidian.el ends here
