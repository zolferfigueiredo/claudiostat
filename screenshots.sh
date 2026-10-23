#!/bin/bash
# Draws every look of the menu bar (Tests/ClaudioStatTests/BarScreenshots.swift) into a folder, with a README.md gallery.
#   ./screenshots.sh [folder] [earlier]   folder defaults to /tmp/claudiostat-screenshots. With an earlier gallery it also
#                                         writes changes.tsv: changed, new or removed, the file and the look, in gallery order.
#   ./screenshots.sh table folder [url]   prints its changes.tsv as a before and after table, the pictures under url
#                                         (url/before/ for the earlier ones).
set -euo pipefail
cd "$(dirname "$0")"

# The gallery's looks in order, "file<TAB>name", from its rows "| name | ![name](file) |".
looks() {
  awk 'match($0, /\]\([^)]*\.png\)/) {
         file = substr($0, RSTART + 2, RLENGTH - 3); split($0, cells, " \\| "); sub(/^\| /, "", cells[1]); print file "\t" cells[1]
       }' "$1"
}

if [ "${1:-}" = table ]; then
  awk -F '\t' -v url="${3:-}" '
    BEGIN { print "| Look | Before | After |"; print "|---|---|---|" }
    { before = $1 == "new" ? "" : "![](" url "before/" $2 ")"; after = $1 == "removed" ? "" : "![](" url $2 ")"
      note = $1 == "changed" ? "" : " (" $1 ")"
      printf "| %s%s | %s | %s |\n", $3, note, before, after }' "$2/changes.tsv"
  exit
fi

OUT=${1:-/tmp/claudiostat-screenshots}
EARLIER=${2:-}
WORK=/tmp/claudiostat-run
export TMPDIR="$WORK/tmp" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/modules" CLANG_MODULE_CACHE_PATH="$WORK/modules"
mkdir -p "$TMPDIR" "$OUT"
rm -f "$OUT"/*.png "$OUT/README.md" "$OUT/changes.tsv"
SCREENSHOTS=$(cd "$OUT" && pwd) swift test --scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config" \
  --security-path "$WORK/security" --manifest-cache none --filter barScreenshots

if [ -n "$EARLIER" ]; then
  looks "$OUT/README.md" | while IFS=$'\t' read -r file name; do
    if [ ! -f "$EARLIER/$file" ]; then printf 'new\t%s\t%s\n' "$file" "$name"
    elif ! cmp -s "$OUT/$file" "$EARLIER/$file"; then printf 'changed\t%s\t%s\n' "$file" "$name"; fi
  done > "$OUT/changes.tsv"
  if [ -f "$EARLIER/README.md" ]; then
    looks "$EARLIER/README.md" | while IFS=$'\t' read -r file name; do
      [ -f "$OUT/$file" ] || printf 'removed\t%s\t%s\n' "$file" "$name"
    done >> "$OUT/changes.tsv"
  fi
  echo "$(grep -c . "$OUT/changes.tsv" || true) looks changed"
fi
echo "Gallery: $OUT/README.md"
