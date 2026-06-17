#!/system/bin/sh
seconds="${1:-}"
case "$seconds" in ""|*[!0-9]*) echo "Usage: timer-lite <seconds>"; exit 1 ;; esac
if [ "$seconds" -gt 3600 ]; then echo "Max timer is 3600 seconds."; exit 1; fi
echo "Timer: $seconds seconds"
remaining="$seconds"
while [ "$remaining" -gt 0 ]; do
  if [ "$remaining" -le 10 ] || [ $((remaining % 10)) -eq 0 ]; then echo "$remaining"; fi
  sleep 1
  remaining=$((remaining - 1))
done
echo "Done."
