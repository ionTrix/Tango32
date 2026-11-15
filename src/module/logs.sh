#!/system/bin/sh
# Tango32 logs (v1.1, 2026-11-14 23:40 ET). Bundles everything a bug report needs into one file:
#   sdcard/Tango32/tango32_logs.zip
#     tango32_boot.txt    boot report (post-fs-data + service.sh, rewritten every boot)
#     tango32_check.txt   module/phone version, app patches (+ online patch settings), known Tango32 error lines,
#                         newest crash (tombstone) summaries
#     tango32_logcat.txt  manual run only (reproduce the problem first). Not the full log, to keep
#                         less personal data: all crash lines, the last 5 minutes of main/system (at most
#                         150 lines per log tag, so a few chatty system tags can't push everything else
#                         out; v1.0 kept the last 4000 lines = only ~6 s on OxygenOS), and every
#                         Tango-related line (tango, zygote, linker, crash dumps, app crashes, SELinux) from all buffers
# Manual:  su -c sh /data/adb/modules/tango32/logs.sh       Boot (service.sh):  logs.sh boot
MODDIR=${0%/*}
. $MODDIR/tango32_dir.sh
W=/data/local/tmp/tango32_logs.$$
CAP=150   # max lines kept per log tag in the 5-minute window
rm -rf $W; mkdir -p $W
cp $MODDIR/tango32.log $W/tango32_boot.txt 2>/dev/null
{
  echo "Tango32 $(sed -n 's/^version=//p' $MODDIR/module.prop) · $(getprop ro.product.model) · $(getprop ro.build.display.id)"
  echo "zygote_tango=$(getprop init.svc.zygote_tango) · $(date)"
  echo "-- app patches:"; sh $MODDIR/patches/apply.sh 2>&1
  echo "-- online patches:"; sh $MODDIR/patches.sh 2>&1
  echo "-- known error lines:"
  logcat -d -b all 2>/dev/null | grep -E "System zygote died|dlopen failed|UnsatisfiedLink|NoSuchMethodError|Failed to call parcel|CANNOT LINK"
  echo "-- newest crashes (tombstones, last 3):"
  for t in $(ls -t /data/tombstones/tombstone_?? 2>/dev/null | head -3); do
    echo "# $(basename $t) $(/system/bin/stat -c %y $t 2>/dev/null | cut -c1-19)"
    grep -m1 "^Cmdline" $t; grep -m1 "^pid:" $t; grep -m1 "^signal" $t; grep -m1 "^Abort message" $t
    grep -A12 -m1 "^backtrace:" $t | cut -c1-200
  done
} > $W/tango32_check.txt
if [ "$1" != boot ]; then
  {
    echo "== crash buffer"; logcat -d -b crash 2>/dev/null
    # logcat -T wants "MM-DD hh:mm:ss.mmm" (local time); toybox date takes @epoch
    since=$(date -d "@$(( $(date +%s) - 300 ))" '+%m-%d %H:%M:%S.000' 2>/dev/null)
    echo "== last 5 minutes (main, system; since ${since:-?}; max $CAP lines per tag, newest kept)"
    if [ -n "$since" ]; then logcat -d -b main,system -T "$since" 2>/dev/null; else logcat -d -b main,system -t 20000 2>/dev/null; fi > $W/raw
    # threadtime lines: "MM-DD hh:mm:ss.mmm  pid  tid L Tag: msg" -> tag = text between the level letter and ':'
    awk -v cap=$CAP 'function tag(l,  t) { t = l; if (!sub(/^[^ ]+ +[^ ]+ +[0-9]+ +[0-9]+ +[VDIWEFS] +/, "", t)) return "-"
        sub(/ *:.*/, "", t); return t }
      NR == FNR { n[tag($0)]++; next }
      { k = tag($0); if (n[k] - (++s[k]) < cap) print; else d[k]++ }
      END { for (k in d) { c++; tot += d[k] }
            if (c) printf "== dropped %d older lines from %d chatty tags (each kept its newest %d)\n", tot, c, cap
            for (k in d) if (d[k] >= 1000) printf "   %s: %d dropped\n", k, d[k] }' $W/raw $W/raw
    rm -f $W/raw
    echo "== Tango-related lines (all buffers)"
    logcat -d -b all 2>/dev/null | grep -iE "tango|zygote|app_process|linker|DEBUG|AndroidRuntime|libc  |avc:|dlopen|UnsatisfiedLink"
  } > $W/tango32_logcat.txt
fi
tmake
CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin com.tango32.Zip $W/out.zip \
  $W/tango32_boot.txt $W/tango32_check.txt $W/tango32_logcat.txt 2>/dev/null \
  && cp $W/out.zip "$TDEF/tango32_logs.zip" && OK=1
rm -rf $W
[ "$1" = boot ] && exit 0
if [ -n "$OK" ]; then
  echo "Successfully saved logs: $TSHOW/tango32_logs.zip"
  echo "Attach logs along with your GitHub issue."
  echo "Logs may contain personal data, review first."
else
  echo "Failed save: can't write $TSHOW"; exit 1
fi
