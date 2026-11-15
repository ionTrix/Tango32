#!/bin/sh
# Tango32 release notes — 2026-11-14 21:58 ET (v1.1: unwraps hard-wrapped CHANGELOG lines)
# Prints the GitHub Release text for one tag, taken from its CHANGELOG.md section.
#   sh tools/release_notes.sh v1.0            -> stdout
#   sh tools/release_notes.sh all [outdir]    -> outdir/v1.x.md for every tag (default: release-notes/)
# Releases are source-only: no prebuilt module zip is attached.
# GitHub Releases turn every single newline into a line break, so wrapped CHANGELOG lines are joined:
#   a line continues the one above unless it is blank, a heading, a table row or starts a bullet.
set -eu
cd "$(dirname "$0")/.."

unwrap() {
  awk 'function flush() { if (buf != "") print buf; buf = "" }
    /^[[:space:]]*$/ { flush(); print; next }
    /^(#|\||[[:space:]]*[-*+] |[[:space:]]*[0-9]+\. )/ { flush(); buf = $0; next }
    { line = $0; sub(/^[[:space:]]+/, "", line); buf = (buf == "") ? line : buf " " line }
    END { flush() }'
}

notes() {
  tag=$1
  body=$(awk -v t="$tag" '
    /^## / { on = ($2 == t); next }
    on' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' | unwrap)
  [ -n "$body" ] || { echo "no CHANGELOG section for $tag" >&2; return 1; }
  date=$(awk -v t="$tag" '/^## / && $2 == t { print $4 }' CHANGELOG.md)
  printf '%s\n\n' "$body"
  printf -- '---\n'
  printf '**Source only** — no prebuilt module is published. Build it for your phone: see the README (Build section).\n'
  printf 'Tested on: OnePlus 12 NA (CPH2583), OxygenOS 16.0.10.601. Released %s.\n\n' "$date"
  printf 'Like it? A tip for the porting work: [Ko-fi](https://ko-fi.com/iontrix) · [GitHub Sponsors](https://github.com/sponsors/ionTrix)\n'
}

if [ "${1:-}" = all ]; then
  out=${2:-release-notes}
  mkdir -p "$out"
  for t in $(git tag -l 'v*' --sort=v:refname); do
    notes "$t" > "$out/$t.md" && echo "$out/$t.md"
  done
else
  notes "${1:?usage: release_notes.sh <tag>|all [outdir]}"
fi
