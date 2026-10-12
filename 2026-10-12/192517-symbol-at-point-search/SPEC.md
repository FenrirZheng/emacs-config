# Spec: C-u C-t / C-u C-z — search the symbol at point

Status: implemented
Date: 2026-10-12 (Asia/Taipei)
Handoff: [HANDOFF.md](HANDOFF.md)

## 目標

- `C-u C-z` opens the text search with the symbol at point already typed, so "where else
  is this used?" is one chord plus a prefix.
- `C-u C-t` does the same for the file search: the symbol at point seeds the file-name
  query (useful on a module name such as `fenrir-search`).
- Everything else about the two prompts stays as it is: the same key still changes the
  folder, the other key still changes the kind, and the seeded text is kept like any
  typed text.
- Without `C-u`, both commands behave exactly as today.

## 不做的事

- No change to dired `C-t`, `<f5> s`, or the in-prompt keys.
- No "region as seed" — only the symbol at point.
- No new key binding.

## 驗收條件

Run in a throwaway `emacs -nw` inside tmux, not the daemon. Each step starts from
`~/.emacs.d/lisp/fenrir-search.el`.

1. Point on `fenrir/search--run` in the line `(defun fenrir/search--run (kind dir initial
   &optional root origin)`, press `C-u C-z` → prompt `Ripgrep (Project .emacs.d):` whose
   input contains `fenrir/search--run`, with at least 2 matches listed.
2. Point on `fenrir-search` in the line `(provide 'fenrir-search)`, press `C-u C-t` →
   prompt `Fd (Project .emacs.d):` whose input contains `fenrir-search`, and
   `lisp/fenrir-search.el` is among the candidates.
3. Point on an empty line, press `C-u C-z` → prompt `Ripgrep (Project .emacs.d):` with
   empty input (only consult's own `#` if it adds one).
4. After step 1, press `C-z` again → the folder changes to `~/.emacs.d/lisp/` and the
   input still contains `fenrir/search--run`.
5. Point on `fenrir/search--run`, press `C-z` without `C-u` → empty input, as today.

## 限制

- None recorded in the original spec.

## 待決問題

- Regexp-quote the text seed? — default if unanswered: yes (literal match). Accepted
  2026-10-12: default.
- File seed: symbol at point, or `thing-at-point 'filename`? — default if unanswered:
  symbol at point. Accepted 2026-10-12: default.
