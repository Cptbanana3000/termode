#!/system/bin/sh
notes_file="${TERMODE_USR:-$HOME}/note-lite.txt"
cmd="${1:-list}"
case "$cmd" in
  add)
    shift
    if [ $# -eq 0 ]; then echo "Usage: note-lite add \"text\""; exit 1; fi
    mkdir -p "$(dirname "$notes_file")" 2>/dev/null
    printf "%s\n" "$*" >> "$notes_file"
    echo "Note added."
    ;;
  list)
    if [ ! -s "$notes_file" ]; then echo "No notes."; exit 0; fi
    n=1
    while IFS= read -r line; do
      printf "%s. %s\n" "$n" "$line"
      n=$((n + 1))
    done < "$notes_file"
    ;;
  clear)
    : > "$notes_file"
    echo "Notes cleared."
    ;;
  *) echo "Usage: note-lite add|list|clear"; exit 1 ;;
esac
