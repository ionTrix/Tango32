#!/system/bin/sh
# Tango32 boot capture (v1.2, 2026-11-19 12:10 ET: + logcat_start head F16, heartbeat last W12; 09:40: early start, sync, lastboot, debug max)
# A reboot during early boot wipes logcat and the kernel log, so a "phone rebooted by itself" left no evidence
#   (arcinin1, KernelSU-Next, 11-18/19). Runs on the first 2 boots after an install or update (customize.sh sets
#   bootlog_left=2, post-fs-data counts down), and on EVERY boot while debug max is on (sdcard/Tango32/debug.txt
#   exists; service.sh mirrors that into settings as debug=max, since shared storage isn't readable this early).
#   post-fs-data starts it in the background (early = more of the boot covered); service.sh starts it too as a
#   fallback (lock dir: one run per boot). Everything goes to /data/adb/tango32/bootlog/ (survives reboots):
#     <B>_info.txt      boot reason props, boot_completed time, "last alive" heartbeat every 5 s (kept as the last line)
#                       (= roughly when this boot ended, if it rebooted)
#     <B>_logcat_start.txt  F16: logcat of the first 2 min of the boot, never rotated (max 8 MB) = the boot's start
#                       survives even when the rotating log below fills up (OxygenOS logs ~2 MB/min)
#     <B>_logcat.txt    logcat, all buffers, rotating (normal: 5 min, 2 x 4 MB; max: 15 min, 2 x 16 MB) = the boot's end
#     <B>_kernel.txt    kernel log (dmesg), refreshed every 5 s
#     <B>_lastboot.txt  the PREVIOUS boot's end, if the kernel kept it: /sys/fs/pstore (panic / console log)
#                       and logcat -L (its last log lines). This is the evidence when a boot died before logging.
#   <B> = boot1, boot2 (after install; next install clears them) · debug max: dboot0 (this boot), dboot1, dboot2 (older)
#   Files are synced every 5 s: a panic or watchdog reset skips the normal flush to storage.
#   logs.sh adds them to tango32_logs.zip as 5_<B>_*.txt. Full logcat = may contain personal data (same warning).
# Usage: bootlog.sh <boot number | debug>
MODDIR=${0%/*}
. $MODDIR/tango32_dir.sh
N=${1:-1}; D=$TDATA/bootlog
mkdir /dev/tango32_bootlog.run 2>/dev/null || exit 0
mkdir -p $D || exit 1
rm -f $D/*.tmp   # dmesg temp left by a boot that ended mid-write
if [ "$N" = debug ]; then
  SECS=900; RK=16384; B=dboot0; WHAT="debug max (every boot, debug.txt)"
  for s in info logcat logcat.txt.1 logcat_start kernel lastboot; do   # keep the 3 newest boots: dboot1 -> dboot2, dboot0 -> dboot1
    e=.txt; [ $s = logcat.txt.1 ] && { s=logcat; e=.txt.1; }
    rm -f $D/dboot2_$s$e; [ -f $D/dboot1_$s$e ] && mv -f $D/dboot1_$s$e $D/dboot2_$s$e
    [ -f $D/dboot0_$s$e ] && mv -f $D/dboot0_$s$e $D/dboot1_$s$e
  done
else
  SECS=300; RK=4096; B=boot$N; WHAT="boot $N after install"
fi
I=$D/${B}_info.txt; L=$D/${B}_logcat.txt; K=$D/${B}_kernel.txt; P=$D/${B}_lastboot.txt; H=$D/${B}_logcat_start.txt
rm -f $I $L $L.1 $K $P $H
reasons() {
  echo "ro.boot.bootreason=$(getprop ro.boot.bootreason)"
  echo "sys.boot.reason=$(getprop sys.boot.reason)"
  echo "sys.boot.reason.last=$(getprop sys.boot.reason.last)"
  echo "persist.sys.boot.reason.history:"; getprop persist.sys.boot.reason.history
}
{
  echo "Boot capture: $WHAT · Tango32 $(sed -n 's/^version=//p' $MODDIR/module.prop) · $(date)"
  echo "uptime at start: $(cut -d' ' -f1 /proc/uptime) s · capture: $SECS s"
  echo "-- boot reason (at start)"; reasons
} > $I 2>&1
# Previous boot's end (pstore survives a warm reset; empty after a cold power-off)
{
  echo "Previous boot's end, as kept by the kernel (pstore). Empty = nothing kept (e.g. normal shutdown or power-off)."
  echo "-- /sys/fs/pstore"; ls -la /sys/fs/pstore 2>&1
  for f in /sys/fs/pstore/*; do
    [ -f "$f" ] || continue; echo "--- $f (last 512 KB)"; tail -c 524288 "$f" 2>&1; echo
  done
  [ -f /proc/last_kmsg ] && { echo "-- /proc/last_kmsg (last 512 KB)"; tail -c 524288 /proc/last_kmsg 2>&1; }
  echo "-- logcat -L (previous boot's log, if kept)"; logcat -L -b all -d -v threadtime 2>&1 | tail -20000
} > $P 2>&1
sync
i=0; until [ "$(getprop init.svc.logd)" = running ] || [ $i -ge 60 ]; do sleep 1; i=$((i+1)); done
logcat -b all -v threadtime -f $L -r $RK -n 1 </dev/null >/dev/null 2>&1 &
LP=$!
# F16 head: own logcat into head -c (stops at 8 MB by itself; killed at 2 min). Both read logd's buffer from the boot's start.
logcat -b all -v threadtime </dev/null 2>/dev/null | head -c 8388608 > $H &
HP=$!
t=0; done_bc=
while [ $t -lt $SECS ]; do
  dmesg > $K.tmp 2>&1 && mv -f $K.tmp $K
  if [ -z "$done_bc" ] && [ "$(getprop sys.boot_completed)" = 1 ]; then
    done_bc=1   # W12: insert before the heartbeat line (rebuilt + renamed: the heartbeat is never missing)
    { grep -v '^last alive: ' $I; echo "-- boot_completed at uptime $(cut -d' ' -f1 /proc/uptime) s"; echo "-- boot reason (after boot)"
      reasons; grep '^last alive: ' $I; true; } > $I.tmp 2>&1 && mv -f $I.tmp $I
  fi
  [ -n "$HP" ] && [ $t -ge 120 ] && { kill $HP 2>/dev/null; HP=; }   # head gone -> its logcat dies on the next write (SIGPIPE)
  # heartbeat: build the line first, then swap it in with one sed -i (temp file + rename: never missing)
  hb="last alive: uptime $(cut -d' ' -f1 /proc/uptime) s · $(date '+%H:%M:%S') · zygote_tango=$(getprop init.svc.zygote_tango)"
  if grep -q '^last alive: ' $I; then sed -i "s|^last alive: .*|$hb|" $I; else echo "$hb" >> $I; fi
  sync   # a panic or watchdog reset doesn't flush: without this the files can come back empty
  sleep 5; t=$((t+5))
done
kill $LP $HP 2>/dev/null
echo "-- capture finished normally after $SECS s (no reboot during this boot's first $((SECS/60)) min)" >> $I
sync
