#!/usr/bin/env bash
# Copies the reviewed edition from the Android repo into the iOS bundle.
# The canonical text still lives in one place; this keeps the iOS repo
# buildable offline without hand-editing the JSON.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/../scrolling-scripture-android/app/src/bible/assets}"
DESTINATION="$ROOT/App/Resources"

if [[ ! -f "$SOURCE/world_english_bible.json" ]]; then
  echo "Edition not found at $SOURCE/world_english_bible.json" >&2
  echo "Usage: tools/sync-content.sh [/path/to/android/bible/assets]" >&2
  exit 1
fi

cp "$SOURCE/world_english_bible.json" "$DESTINATION/world_english_bible.json"
cp "$SOURCE/ATTRIBUTION.md" "$DESTINATION/ATTRIBUTION.md"
echo "Synced $SOURCE -> $DESTINATION"
