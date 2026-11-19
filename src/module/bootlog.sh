#!/system/bin/sh
# Tango32 boot capture (v1.2, 2026-11-19 09:05 ET)
# A reboot during early boot wipes logcat and the kernel log, so a "phone rebooted by itself" left no evidence
#   (arcinin1, KernelSU-Next, 11-18/19). On the first 2 boots after an install or update (customize.sh sets
#   bootlog_left=2, post-fs-data counts down and leaves /dev/tango32_bootlog = boot number), service.sh starts this
#   in the background. Everything goes to /data/adb/tango32/bootlog/ (survives reboots; next install clears it):
#     bootN_info.txt     boot reason props (the previous boot's end shows up here), boot_completed time,
#                        "last alive" heartbeat every 5 s (= roughly when this boot ended, if it rebooted)
#     bootN_logcat.txt   logcat, all buffers from the start of the boot, first 5 min (max 2 x 4 MB)
#     bootN_kernel.txt   kernel log (dmesg), refreshed every 5 s for 5 min
#   logs.sh adds them to tango32_logs.zip as 5_bootN_*.txt. Full logcat = may contain personal data (same warning).
# Usage: bootlog.sh <boot number>   (lock dir: one run per boot)
MODDIR=${0%/*}
. $MODDIR/tango32_dir.sh
N=${1:-1}; D=$TDATA/bootlog; SECS=300
mkdir /dev/tango32_bootlog.run 2>/dev/null || exit 0
mkdir -p $D || exit 1
I=$D/boot${N}_info.txt; L=$D/boot${N}_logcat.txt; K=$D/boot${N}_kernel.txt
rm -f $I $L $L.1 $K
reasons() {
  echo "ro.boot.bootreason=$(getprop ro.boot.bootreason)"
  echo "sys.boot.reason=$(getprop sys.boot.reason)"
  echo "sys.boot.reason.last=$(getprop sys.boot.reason.last)"
  echo "persist.sys.boot.reason.history:"; getprop persist.sys.boot.reason.history
}
{
  echo "Boot capture: boot $N after install · Tango32 $(sed -n 's/^version=//p' $MODDIR/module.prop) · $(date)"
  echo "uptime at start: $(cut -d' ' -f1 /proc/uptime) s"
  echo "-- boot reason (at start)"; reasons
} > $I 2>&1
i=0; until [ "$(getprop init.svc.logd)" = running ] || [ $i -ge 60 ]; do sleep 1; i=$((i+1)); done
logcat -b all -v threadtime -f $L -r 4096 -n 1 </dev/null >/dev/null 2>&1 &
LP=$!
t=0; done_bc=
while [ $t -lt $SECS ]; do
  dmesg > $K.tmp 2>&1 && mv -f $K.tmp $K
  if [ -z "$done_bc" ] && [ "$(getprop sys.boot_completed)" = 1 ]; then
    done_bc=1; { echo "-- boot_completed at uptime $(cut -d' ' -f1 /proc/uptime) s"; echo "-- boot reason (after boot)"; reasons; } >> $I 2>&1
  fi
  # heartbeat: rewrite the last line (sed -i keeps the file small)
  sed -i '/^last alive: /d' $I 2>/dev/null
  echo "last alive: uptime $(cut -d' ' -f1 /proc/uptime) s · $(date '+%H:%M:%S') · zygote_tango=$(getprop init.svc.zygote_tango)" >> $I
  sleep 5; t=$((t+5))
done
kill $LP 2>/dev/null
echo "-- capture finished normally after $SECS s (no reboot during this boot's first 5 min)" >> $I
