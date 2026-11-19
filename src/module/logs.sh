#!/system/bin/sh
# Tango32 logs (v1.2, 2026-11-19 13:20 ET: F18 boot run saves tango32_boot.zip, never overwrites a manual save; 12:20: split into parts under 23 MB F15, per-boot order W14; 09:40: boot capture, debug max 6_debug_*; v1.1 2026-11-15). Bundles everything a bug report needs into one file:
#   sdcard/Tango32/logs/tango32_logs.zip (v1.1: logs/ subfolder; files numbered in reading order)
#     1_summary.txt       module/phone version, app patches (+ online patches), known Tango32 error lines,
#                         newest crash (tombstone) summaries (the stock ART crash is skipped, A5)
#     2_boot_report.txt   boot report (post-fs-data + service.sh, rewritten every boot)
#     3_logcat.txt        manual run only (reproduce the problem first). Not the full log, to keep
#                         less personal data: all crash lines, the last 5 minutes of main/system (at most
#                         150 lines per log tag, so a few chatty system tags can't push everything else
#                         out; v1.0 kept the last 4000 lines = only ~6 s on OxygenOS), and every
#                         Tango-related line (tango, zygote, linker, crash dumps, app crashes, SELinux) from all buffers
#     4_install.log       sdcard/Tango32/logs/install.log (Action installs + quick tests), if there is one
#     5_bootN_*.txt       v1.2: boot capture of the first 2 boots after install (bootlog.sh), if there is one:
#                         info (boot reasons, last-alive time), full logcat (first 5 min), kernel log, lastboot
#                         (previous boot's pstore + logcat -L). Debug max: 5_dboot0..2_* (every boot, 15 min)
#     (F15: too big for one 25 MB GitHub upload = split: tango32_logs.zip, tango32_logs_2.zip … — attach all parts)
#     6_debug_*.txt       v1.2 debug max only (sdcard/Tango32/debug.txt): full logcat (all buffers), kernel log,
#                         all props, processes + module/zygote_tango state, last 3 full tombstones
# Manual:  su -c sh /data/adb/modules/tango32/logs.sh       Boot (service.sh):  logs.sh boot
# F18 (11-19): the boot run saves logs/tango32_boot.zip (no 3_logcat.txt), the manual run logs/tango32_logs.zip.
#   Before, the boot run overwrote tango32_logs.zip, so a reboot after saving (e.g. the crash reboot itself)
#   replaced the full bug report (KSU run 1: newest zip had no 3_logcat.txt).
MODDIR=${0%/*}
. $MODDIR/tango32_dir.sh
W=/data/local/tmp/tango32_logs.$$
CAP=150   # max lines kept per log tag in the 5-minute window
rm -rf $W; mkdir -p $W
cp $MODDIR/tango32.log $W/2_boot_report.txt 2>/dev/null
cp "$IRAW" $W/4_install.log 2>/dev/null
# v1.2 boot capture (bootN_*, debug max: dbootN_*). W14: grouped per boot, newest boot first, so each boot's files
#   stay together and a split (F15) puts the newest boots in the first part. cp -p keeps the capture times in the zip.
B=""; for b in dboot0 dboot1 dboot2 boot2 boot1; do
  for s in info.txt lastboot.txt logcat_start.txt logcat.txt logcat.txt.1 kernel.txt; do
    f=$TDATA/bootlog/${b}_$s; [ -f "$f" ] || continue
    n=5_${b}_$s; [ "$s" = logcat.txt.1 ] && n=5_${b}_logcat_older.txt
    cp -p "$f" "$W/$n" 2>/dev/null && B="$B $W/$n"
  done
done
{
  echo "== Phone and module"
  echo "Tango32 $(sed -n 's/^version=//p' $MODDIR/module.prop) · $(getprop ro.product.model) · $(getprop ro.build.display.id)"
  echo "zygote_tango=$(getprop init.svc.zygote_tango) · $(date)"
  echo "Debug max: $([ -e "$TDBG" ] && echo "on (sdcard/Tango32/debug.txt)" || echo off) · boot capture left: $(sget bootlog_left)"
  echo "Saved by: $([ "$1" = boot ] && echo "boot (automatic, no 3_logcat)" || echo "manual (Action / Termux)")"
  echo "== App patches"; sh $MODDIR/patches/apply.sh 2>&1
  echo "== Online patches"; sh $MODDIR/patches.sh 2>&1
  echo "== Pre-flight check (cached APK results)"
  awk -F'\t' '{ split($1, k, "|"); n = k[1]; sub(/.*\//, "", n); if (n != "") print n ": " ($2 == "" ? "not 32-bit" : "missing " $2 ($3 != "" ? " (" $3 ")" : "") ($4 != "" ? " · fix " $4 : "") ($5 != "" ? " · auto-patch " $5 : "")) }' \
    "$TDATA/preflight.cache" 2>/dev/null | tail -30
  echo "== Known error lines"
  logcat -d -b all 2>/dev/null | grep -E "System zygote died|dlopen failed|UnsatisfiedLink|NoSuchMethodError|Failed to call parcel|CANNOT LINK"
  echo "== Newest crashes (tombstones, last 3; stock ART crash skipped)"
  # Stock OxygenOS crash seen in any 64-bit process (<pre-initialized>, zygote64, usap64), Tango32 on or off:
  #   fault addr 0x...0d + #00 in 64-bit libart.so art::FaultManager::HandleFault -> counted, not listed
  n=0; sk=0
  for t in $(ls -t /data/tombstones/tombstone_?? 2>/dev/null); do
    if grep -m1 "^signal" $t | grep -q "fault addr 0x0*d\$" \
      && grep -m1 "^ *#00 pc" $t | grep -q "/lib64/libart.so (art::FaultManager::HandleFault"; then sk=$((sk+1)); continue; fi
    [ $n -ge 3 ] && continue; n=$((n+1))
    echo "# $(basename $t) $(/system/bin/stat -c %y $t 2>/dev/null | cut -c1-19)"
    grep -m1 "^Cmdline" $t; grep -m1 "^pid:" $t; grep -m1 "^signal" $t; grep -m1 "^Abort message" $t
    grep -A12 -m1 "^backtrace:" $t | cut -c1-200
  done
  [ $n = 0 ] && echo "none"
  [ $sk = 0 ] || echo "($sk stock ART crash(es) ignored: FaultManager::HandleFault, fault addr 0xd)"
} > $W/1_summary.txt
if [ "$1" != boot ]; then
  {
    echo "== Crash buffer"; logcat -d -b crash 2>/dev/null
    # logcat -T wants "MM-DD hh:mm:ss.mmm" (local time); toybox date takes @epoch
    since=$(date -d "@$(( $(date +%s) - 300 ))" '+%m-%d %H:%M:%S.000' 2>/dev/null)
    echo "== Last 5 minutes (main, system; since ${since:-?}; max $CAP lines per tag, newest kept)"
    if [ -n "$since" ]; then logcat -d -b main,system -T "$since" 2>/dev/null; else logcat -d -b main,system -t 20000 2>/dev/null; fi > $W/raw
    # threadtime lines: "MM-DD hh:mm:ss.mmm  pid  tid L Tag: msg" -> tag = text between the level letter and ':'
    awk -v cap=$CAP 'function tag(l,  t) { t = l; if (!sub(/^[^ ]+ +[^ ]+ +[0-9]+ +[0-9]+ +[VDIWEFS] +/, "", t)) return "-"
        sub(/ *:.*/, "", t); return t }
      NR == FNR { n[tag($0)]++; next }
      { k = tag($0); if (n[k] - (++s[k]) < cap) print; else d[k]++ }
      END { for (k in d) { c++; tot += d[k] }
            if (c) printf "(dropped %d older lines from %d chatty tags (each kept its newest %d))\n", tot, c, cap
            for (k in d) if (d[k] >= 1000) printf "   %s: %d dropped\n", k, d[k] }' $W/raw $W/raw
    rm -f $W/raw
    echo "== Tango-related lines (all buffers)"
    logcat -d -b all 2>/dev/null | grep -iE "tango|zygote|app_process|linker|DEBUG|AndroidRuntime|libc  |avc:|dlopen|UnsatisfiedLink"
  } > $W/3_logcat.txt
fi
# v1.2 debug max (sdcard/Tango32/debug.txt): everything, unfiltered
D6=""
if [ "$(sget debug)" = max ] || [ -e "$TDBG" ]; then
  logcat -d -b all -v threadtime > $W/6_debug_logcat_all.txt 2>&1
  dmesg > $W/6_debug_kernel.txt 2>&1
  getprop > $W/6_debug_props.txt 2>&1
  { echo "== Processes"; ps -A -o pid,ppid,user,label,stat,rss,args
    echo "== Module files"; ls -laZR $MODDIR 2>&1 | head -400
    echo "== /dev/tango32*"; ls -laZ /dev/tango32* 2>&1
    echo "== Wrapper log (/dev/tango32_ns.log, full)"; cat /dev/tango32_ns.log 2>&1
    P=$(getprop init.svc_debug_pid.zygote_tango)
    if [ -n "$P" ] && [ -d /proc/$P ]; then echo "== zygote_tango pid $P mountinfo"; cat /proc/$P/mountinfo; echo "== zygote_tango maps"; cat /proc/$P/maps | head -600; fi
    echo "== Settings ($TSET)"; cat $TSET 2>&1
    echo "== SELinux"; getenforce 2>&1; cat /proc/self/attr/current 2>&1; echo
  } > $W/6_debug_system.txt 2>&1
  { for t in $(ls -t /data/tombstones/tombstone_?? 2>/dev/null | head -3); do echo "== $t"; head -c 524288 $t; echo; done; } > $W/6_debug_tombstones.txt 2>&1
  D6="$W/6_debug_logcat_all.txt $W/6_debug_kernel.txt $W/6_debug_props.txt $W/6_debug_system.txt $W/6_debug_tombstones.txt"
fi
fmt $W/1_summary.txt "1. SUMMARY: versions, patches, known errors, crashes"
fmt $W/2_boot_report.txt "2. BOOT REPORT: last boot (post-fs-data + after boot)"
fmt $W/3_logcat.txt "3. LOGCAT: crash buffer, last 5 minutes, Tango-related lines"
fmt $W/4_install.log "4. INSTALL LOG: Action installs and quick tests (newest last)" 1
tmake
# F15: split so each part stays under 23 MB -> tango32_logs.zip, tango32_logs_2.zip … (each a normal zip under GitHub's 25 MB). Order =
#   importance: summary/reports/install log, debug extras, then the boots (newest first).
ZN=tango32_logs; [ "$1" = boot ] && ZN=tango32_boot   # F18
CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin com.tango32.Zip -s 24117248 $W/out.zip \
  $W/1_summary.txt $W/2_boot_report.txt $W/3_logcat.txt $W/4_install.log $D6 $B 2>/dev/null \
  && mkdir -p "$TLOGS" && rm -f "$TLOGS"/${ZN}_*.zip && cp $W/out.zip "$TLOGS/$ZN.zip" && OK=1
if [ -n "$OK" ]; then
  for z in $W/out_*.zip; do [ -f "$z" ] && cp "$z" "$TLOGS/${ZN}_${z##*/out_}"; done
  rm -f "$TDEF/tango32_logs.zip"   # v1.0 location
fi
PARTS=$(ls "$TLOGS"/$ZN.zip "$TLOGS"/${ZN}_*.zip 2>/dev/null | wc -l)
rm -rf $W
[ "$1" = boot ] && exit 0
if [ -n "$OK" ]; then
  if [ "$PARTS" -gt 1 ]; then echo "Successfully saved logs in $PARTS parts: $TLSHOW/tango32_logs.zip, tango32_logs_2.zip …"
    echo "Attach all $PARTS parts along with your GitHub issue."
  else echo "Successfully saved logs: $TLSHOW/tango32_logs.zip"
    echo "Attach logs along with your GitHub issue."; fi
  echo "Logs may contain personal data, review first."
else
  echo "Failed to save logs: can't write $TLSHOW"; exit 1
fi
