#!/usr/bin/env bash
# progress.sh: live status board for tonight's run. Watch it with:
#   watch -n 5 -c measure/progress.sh
# Milestones come from cache/status.txt ("done|now|todo <name>"), the live
# measurement series from the newest docs/results/*/*/run.log.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ST="$REPO/cache/status.txt"
bar() {  # bar <done> <total> <width>
  local d=$1 t=$2 w=${3:-40} f
  (( t > 0 )) || t=1; f=$(( d * w / t ))
  printf '[%s%s] %3d%%' "$(printf '%*s' "$f" '' | tr ' ' '#')" "$(printf '%*s' $((w - f)) '' | tr ' ' '.')" $(( d * 100 / t ))
}
echo "Track C - status at $(date +%H:%M:%S)"
echo
total=$(grep -c . "$ST"); done=$(grep -c '^done' "$ST")
printf 'Overall plan   '; bar "$done" "$total" 40; echo "  ($done/$total milestones)"
echo
while read -r s name; do
  case $s in done) m='[x]';; now) m='[>]';; *) m='[ ]';; esac
  echo "  $m $name"
done < "$ST"
log=$(ls -t "$REPO"/docs/results/*/*/run.log 2>/dev/null | head -1)
if [[ -n $log ]] && pgrep -f run-target.sh >/dev/null; then
  echo
  boots=$(grep -cE 'boot [0-9]+: Startup' "$log"); nb=$(grep -oE '[0-9]+ boots' "$log" | head -1 | cut -d' ' -f1)
  steps=$(( boots + $(grep -c 'ram idle done\|static done\|bench done' "$log") )); tot=$(( ${nb:-5} + 3 ))
  printf 'Measurement    '; bar "$steps" "$tot" 40; echo "  ($(basename "$(dirname "$log")"))"
  echo "  last: $(tail -1 "$log" | cut -c1-100)"
fi
