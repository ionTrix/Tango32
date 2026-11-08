#!/usr/bin/env sh
# pull_fw.sh — collect your phone's framework jars + build info for the Tango32 build
# Updated: 2026-11-07 23:10 ET (v1.0)
#
# The build needs the US framework jars from YOUR phone (they are OnePlus code, so they are not shipped here).
# It also records your model + build fingerprint; the module refuses to install on any other build.
#
# Two ways to run it:
#   On the phone (Termux):  sh pull_fw.sh
#       -> /sdcard/Download/tango32_fw/fw/   (+ tango32_fw/fw.zip if Termux has `zip`: pkg install zip)
#       Copy fw.zip (or the fw/ folder) next to build.sh on your Linux/WSL machine.
#   On Linux/WSL with adb (USB debugging on, phone authorized):  sh pull_fw.sh
#       -> ./fw/ and ./fw.zip next to this script. No root needed either way.
set -eu

info() {   # $1 = getprop runner
  echo "model=$($1 ro.product.model)"
  echo "display=$($1 ro.build.display.id)"
  echo "fingerprint=$($1 ro.build.fingerprint)"
  echo "ota=$($1 ro.build.version.ota)"
  echo "pulled=$(date '+%Y-%m-%d %H:%M %Z')"
}

if command -v getprop >/dev/null 2>&1; then
  # --- on the phone ---
  OUT=/sdcard/Download/tango32_fw
  [ -w /sdcard/Download ] || { echo "Can't write /sdcard/Download. In Termux run: termux-setup-storage"; exit 1; }
  rm -rf "$OUT"; mkdir -p "$OUT/fw"
  BCP=${BOOTCLASSPATH:-}
  [ -n "$BCP" ] || BCP=$(sh -c 'echo $BOOTCLASSPATH' 2>/dev/null || true)
  [ -n "$BCP" ] || { echo "BOOTCLASSPATH is empty"; exit 1; }
  n=0
  for j in $(echo "$BCP" | tr ':' ' '); do
    case $j in /system/*) cp "$j" "$OUT/fw/" && n=$((n+1));; esac
  done
  echo "$BCP" > "$OUT/fw/bcp.txt"
  INFO=$OUT/fw/build.txt; info getprop > "$INFO"
  echo "Copied $n jars to $OUT/fw"
  if command -v zip >/dev/null 2>&1; then (cd "$OUT" && zip -qr fw.zip fw) && echo "Made $OUT/fw.zip"
  else echo "No zip command (pkg install zip) — copy the whole fw/ folder instead."; fi
else
  # --- on a PC with adb ---
  command -v adb >/dev/null 2>&1 || { echo "Run this in Termux on the phone, or install adb on this PC"; exit 1; }
  [ "$(adb get-state 2>/dev/null)" = device ] || { echo "No phone on adb (enable USB debugging, accept the prompt)"; exit 1; }
  HERE=$(cd "$(dirname "$0")" && pwd); OUT=$HERE/fw
  rm -rf "$OUT" "$HERE/fw.zip"; mkdir -p "$OUT"
  BCP=$(adb shell 'echo $BOOTCLASSPATH' | tr -d '\r')
  [ -n "$BCP" ] || { echo "BOOTCLASSPATH is empty"; exit 1; }
  n=0
  for j in $(echo "$BCP" | tr ':' ' '); do
    case $j in /system/*) adb pull "$j" "$OUT/" >/dev/null && n=$((n+1));; esac
  done
  echo "$BCP" > "$OUT/bcp.txt"
  INFO=$OUT/build.txt; info 'adb shell getprop' | tr -d '\r' > "$INFO"
  echo "Pulled $n jars to $OUT"
  command -v zip >/dev/null 2>&1 && (cd "$HERE" && zip -qr fw.zip fw) && echo "Made $HERE/fw.zip" || true
fi
cat "$INFO"
