#!/bin/bash
# Alternate base (15cc6e1^ versions of init-completion.el / init-keys.el) and HEAD,
# measuring (emacs-init-time) in a real TTY emacs -nw inside tmux.
set -u
cd /home/fenrir/.emacs.d
SP=${TMPDIR:-/tmp}; LOG=$SP/inittime.log; : > $LOG
FILES="lisp/init-completion.el lisp/init-keys.el"
trap 'git checkout HEAD -- $FILES' EXIT
use() { if [ $1 = base ]; then for f in $FILES; do git show 15cc6e1^:$f > $f; done; else git checkout HEAD -- $FILES; fi; }
run() { # $1 label
  local n=$(wc -l < $LOG)
  tmux new-session -d -s inittime -x 160 -y 40 "emacs -nw --eval '(progn (append-to-file (format \"$1 %s\n\" (emacs-init-time \"%f\")) nil \"$LOG\") (let ((kill-emacs-hook nil)) (kill-emacs 0)))'"
  for i in $(seq 60); do [ $(wc -l < $LOG) -gt $n ] && break; sleep 0.5; done
  tmux kill-session -t inittime 2>/dev/null; sleep 1
}
for c in base head; do use $c; run warm-$c; run warm-$c; done
for i in 1 2 3 4 5 6; do for c in base head; do use $c; run $c; done; done
