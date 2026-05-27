#!/usr/bin/env bash
# Fetch the self-hosted web fonts into priv/static/assets/fonts.
#
# GDPR: the liveboard never loads fonts from a CDN at runtime. They are fetched
# here at build/setup time and served same-origin. Both families are SIL OFL
# (see priv/static/assets/fonts/NOTICE). Source: the fontsource project mirror.
set -euo pipefail

DEST="$(cd "$(dirname "$0")/.." && pwd)/priv/static/assets/fonts"
BASE="https://cdn.jsdelivr.net/fontsource/fonts"
mkdir -p "$DEST"

files=(
  "ibm-plex-mono@latest/latin-400-normal.woff2"
  "ibm-plex-mono@latest/latin-500-normal.woff2"
  "ibm-plex-mono@latest/latin-600-normal.woff2"
  "ibm-plex-mono@latest/latin-400-italic.woff2"
  "instrument-serif@latest/latin-400-normal.woff2"
  "instrument-serif@latest/latin-400-italic.woff2"
)

for f in "${files[@]}"; do
  out="$DEST/$(echo "$f" | sed 's#@latest/#-#; s#/#-#g')"
  curl -fsSL --max-time 30 "$BASE/$f" -o "$out"
  echo "fetched $(basename "$out") ($(stat -c%s "$out" 2>/dev/null || stat -f%z "$out") bytes)"
done

echo "fonts in $DEST"
