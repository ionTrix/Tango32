#!/system/bin/sh
# Tango32 cleanup (v1.2, 2026-11-19 09:40 ET: + debug.txt; v1.1 2026-11-14)
# v1.1: also removes /data/adb/tango32 (settings + online app patches).
# Also removes our own files from sdcard/Tango32 (README.txt, debug.txt, logs/tango32_logs.zip, logs/install.log, v1.0's tango32_logs.zip);
#   the user's APKs stay. The folder itself goes only if nothing else is left in it. Magisk runs this early in the
#   next boot, before shared storage is unlocked -> done in the background once it appears (up to 10 min).
resetprop -p --delete persist.sys.tango_zygote32.start 2>/dev/null
rm -rf /data/tango /data/dalvik-cache/arm /data/adb/tango32
(
  T=/storage/emulated/0/Tango32; i=0
  until [ -d /storage/emulated/0/Android ] || [ $i -ge 300 ]; do sleep 2; i=$((i+1)); done
  rm -f "$T/tango32_logs.zip" "$T/README.txt" "$T/debug.txt" "$T/logs/tango32_logs.zip" "$T/logs/install.log" 2>/dev/null
  rmdir "$T/logs" 2>/dev/null; rmdir "$T" 2>/dev/null
) </dev/null >/dev/null 2>&1 &
exit 0
