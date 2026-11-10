#!/usr/bin/env bash
# Fails when the iOS bundle has drifted from the canonical Android content.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/../scrolling-scripture-android/app/src/bible/assets}"

if [[ ! -f "$SOURCE/world_english_bible.json" ]]; then
  echo "Canonical edition not found at $SOURCE/world_english_bible.json" >&2
  echo "Usage: tools/check-content.sh [/path/to/android/bible/assets]" >&2
  exit 1
fi

status=0
for file in world_english_bible.json ATTRIBUTION.md; do
  if ! cmp -s "$SOURCE/$file" "$ROOT/App/Resources/$file"; then
    echo "DRIFT: App/Resources/$file differs from $SOURCE/$file" >&2
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "iOS scripture content matches $SOURCE"
else
  echo "Run tools/sync-content.sh to update the bundle." >&2
fi
exit $status
