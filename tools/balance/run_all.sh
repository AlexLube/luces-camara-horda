#!/bin/bash
# Balance sweep: every given stage × character × clause setting, 4 in parallel. Output: one JSON line per run.
#   tools/balance/run_all.sh OUT.txt "stage1 stage2" "char1 char2" "0 max" [mods]
G=${GODOT:-/tmp/claude-0/godot/Godot_v4.3-stable_linux.x86_64}
OUT=$1; STAGES=$2; CHARS=$3; CLAUSES=$4; MODS=$5
: > "$OUT"
for st in $STAGES; do for ch in $CHARS; do for cl in $CLAUSES; do echo "$st $ch $cl"; done; done; done |
  xargs -P 4 -L 1 bash -c "timeout 900 $G --headless --path . res://tools/balance/sim.tscn -- --stage=\$0 --char=\$1 --clauses=\$2 --mods=$MODS 2>/dev/null | grep BAL >> $OUT"
echo "done $(wc -l < $OUT)"
