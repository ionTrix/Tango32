#!/system/bin/sh
# Tango32 status report after boot (v1.1, 2026-11-14 23:40 ET)
# Blocked (firmware mismatch, see post-fs-data) = report that, skip patches, still save the boot logs.
# Re-applies app patches (patches/apply.sh boot) that an app update removed; result in tango32.log.
# v1.1: no online check here: Action asks every time it opens (installing an old app always goes through Action).
# Recreates the apps folder /sdcard/Tango32 (+ README) if missing, once shared storage is up;
#   boot report + error check zipped to sdcard/Tango32/logs/tango32_logs.zip by logs.sh.
#   post-fs-data starts the module's tango32.log fresh each boot.
# Report: namespace (staged CN trees, zygote_tango's view of /apex, wrapper log), namespace holder,
#   TangoFdFix and TangoGui (parcel bridge) lines, tombstone summary, last abort lines.
# ps fields lowercase (toybox rejects PID,NAME); adds zygote/selinux context.
MODDIR=${0%/*}
LOG=$MODDIR/tango32.log
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 10
. $MODDIR/tango32_dir.sh
if [ -e "$MODDIR/blocked" ]; then
  echo; echo "== after boot $(date): blocked (firmware mismatch), nothing started" >>"$LOG"
  i=0; until [ -d "$SD/Android" ] || [ $i -ge 300 ]; do sleep 2; i=$((i+1)); done
  [ -d "$SD/Android" ] && sh $MODDIR/logs.sh boot
  exit 0
fi
{
  echo; echo "== after boot $(date)"
  echo "ro.zygote=$(getprop ro.zygote)"
  echo "abilist32=$(getprop ro.product.cpu.abilist32)"
  echo "zygote=$(getprop init.svc.zygote) zygote_tango=$(getprop init.svc.zygote_tango)"
  echo "tango_zygote32.start=$(getprop persist.sys.tango_zygote32.start)"
  ps -A -o pid,ppid,label,args | grep -iE "zygote|app_process|sleep 2147483647"
  echo "binfmt: $(head -1 /proc/sys/fs/binfmt_misc/tango_translator 2>&1)"
  ls -lZ /dev/tango32 2>&1
  echo "-- staged CN APEXes: $(ls /dev/tango32_cn 2>&1 | tr '\n' ' ')"
  P=$(getprop init.svc_debug_pid.zygote_tango)
  if [ -n "$P" ] && [ -d /proc/$P ]; then
    echo "-- zygote_tango pid $P: global mnt $(readlink /proc/1/ns/mnt) / its mnt $(readlink /proc/$P/ns/mnt)"
    grep -E " /apex/com\.android\.(art|i18n|conscrypt|adbd) " /proc/$P/mountinfo | tail -4
    ls /proc/$P/root/apex/com.android.art/javalib 2>&1 | tr '\n' ' '; echo
  else
    echo "-- zygote_tango not running at report time"
  fi
  echo "-- wrapper log (last 20):"
  tail -20 /dev/tango32_ns.log 2>&1
  echo "-- TangoFdFix:"
  logcat -d -b main 2>/dev/null | grep "TangoFdFix" | tail -3
  echo "-- TangoGui:"
  logcat -d -b main 2>/dev/null | grep "TangoGui" | tail -3
  echo "-- avc denials (tango/zygote):"
  dmesg 2>/dev/null | grep avc | grep -iE "tango|app_process|zygote" | tail -10
  logcat -d -b all 2>/dev/null | grep "avc:" | grep -E "u:r:zygote|tango" | grep -v usap_pool | tail -10
  echo "-- latest tombstone:"
  T=$(ls -t /data/tombstones/tombstone_?? 2>/dev/null | head -1)
  [ -n "$T" ] && { ls -l "$T"; grep -m1 "Cmdline" "$T"; grep -m1 "Abort message" "$T"; grep -m1 "^signal" "$T"; grep -A8 "^backtrace:" "$T" | head -9; }
  echo "-- zygote_tango fatal lines:"
  logcat -d -b all 2>/dev/null | grep app_process32_tango | grep -E " F |Exception|Error" | grep -v "runtime.cc:719\]" | cut -c1-300 | tail -15
} >>"$LOG" 2>&1
{ echo "-- app patches:"; sh $MODDIR/patches/apply.sh boot; } >>"$LOG" 2>&1
# apps folder + logs zip: shared storage appears after the first unlock -> wait up to 10 min
i=0; until [ -d "$SD/Android" ] || [ $i -ge 300 ]; do sleep 2; i=$((i+1)); done
[ -d "$SD/Android" ] && sh $MODDIR/logs.sh boot   # creates the folder too; zip = boot report + error check
