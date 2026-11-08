#!/bin/bash
# make_cn_cache.sh — build tango32_cn_cache.zip (testing shortcut; PRIVATE, contains OnePlus files — never publish)
# Run after a full `bash build.sh`. Resets access times, rebuilds once, then zips only the CN files that build read
# (+ dirs, symlinks, hash.sha256, Maven tools). Put the zip next to build.sh to skip the ~7.7 GB download.
# Usage: bash tools/make_cn_cache.sh [out.zip]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); OUT=$(realpath -m "${1:-$HERE/tango32_cn_cache.zip}")
R=/root/re-work; [ -d $R/cnfw/fs/system ] || { echo "FATAL: run a full build.sh first"; exit 1; }
(cd $R/cnfw && find fs apex -exec touch -a -h -d 2000-01-01 {} +)
bash "$HERE/build.sh" > "$R/cache_build.log" 2>&1 || { echo "FATAL: build failed, see $R/cache_build.log"; exit 1; }
L=$(mktemp); cd $R
{ find cnfw/fs cnfw/apex -type d; find cnfw/fs cnfw/apex -type l; find cnfw/fs cnfw/apex -type f -newerat 2001-01-01
  echo cnfw/hash.sha256; find tools -type f; } > "$L"
rm -f "$OUT"; zip -q -y -9 "$OUT" -@ < "$L"; rm -f "$L"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
