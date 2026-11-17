#!/system/bin/sh
# Tango32 post-fs-data (v1.0, 2026-11-07 23:10 ET)
# Boot check — phone fingerprint must match target.prop (the firmware this zip was built
#   for). Mismatch (e.g. an OTA taken with the module on) = set nothing up, create `disable` (Magisk shows it off),
#   mark `blocked`, put a ⛔ line in the module description, hide the Action button (action.sh -> action.sh.blocked;
#   installs can't work without Tango, boot logs are still saved). A match restores description + Action.
# 'allow zygote zygote capability' (magiskpolicy has no 'self'); crash_dump nosuid_transition
#   (tombstones for 32-bit crashes); /dev/tango32_ns.log for the wrapper; adbd in the namespace.
# Stages CN APEX trees under /dev/tango32_cn for the zygote wrapper's private
#   namespace (ns_apex.list); zygote rules for the wrapper; wipes dalvik-cache/arm.
#   Touch $MODDIR/ns_off to skip the namespace; $MODDIR/zygote_permissive to debug SELinux.
# ctx()/chcon use toybox by full path (Magisk's busybox stat -c %C returns "C").
# NO sepolicy.rule (Magisk's early-boot copy bootlooped; 'type tango32_device'
#   redefines a type the US policy already has). Rules applied live here instead.
# Final mount is rbind; guard unmounts if apex_manifest.pb comes out empty.
# APEX layering uses tmpfs + bind mounts (overlayfs rejects /data sources).
MODDIR=${0%/*}
LOG=$MODDIR/tango32.log
exec >"$LOG" 2>&1
echo "== post-fs-data $(date)"
echo "ro.zygote=$(getprop ro.zygote) (expect zygote64)"

# 00) Boot check: only run on the exact firmware this zip was built for
TP=$MODDIR/target.prop; TF=$(sed -n 's/^fingerprint=//p' "$TP" 2>/dev/null); FP=$(getprop ro.build.fingerprint)
if [ -z "$TF" ] || [ "$FP" != "$TF" ]; then
  TD=$(sed -n 's/^display=//p' "$TP" 2>/dev/null)
  echo "⛔ Firmware changed: built for ${TD:-unknown}, phone is $(getprop ro.build.display.id)"
  echo "   built fingerprint: ${TF:-missing}"
  echo "   phone fingerprint: $FP"
  echo "   Tango32 skipped and disabled. Rebuild it for this firmware (see README: OTA update)."
  resetprop -p --delete persist.sys.tango_zygote32.start 2>/dev/null
  touch "$MODDIR/disable" "$MODDIR/blocked"
  [ -f "$MODDIR/action.sh" ] && mv -f "$MODDIR/action.sh" "$MODDIR/action.sh.blocked"   # hides Magisk's Action button
  [ -f "$MODDIR/module.prop.ok" ] || cp "$MODDIR/module.prop" "$MODDIR/module.prop.ok"
  D="⛔ Disabled: phone firmware doesn't match the firmware Tango32 was built for. Rebuild Tango32 for this firmware."
  sed "s|^description=.*|description=$D|" "$MODDIR/module.prop.ok" > "$MODDIR/module.prop"
  exit 0
fi
echo "Firmware check OK: $(getprop ro.build.display.id)"
if [ -f "$MODDIR/module.prop.ok" ]; then cat "$MODDIR/module.prop.ok" > "$MODDIR/module.prop"; rm -f "$MODDIR/module.prop.ok"; fi
rm -f "$MODDIR/blocked"
[ -f "$MODDIR/action.sh.blocked" ] && mv -f "$MODDIR/action.sh.blocked" "$MODDIR/action.sh"

# 0) SELinux rules, live only (vanish on reboot; can't break early boot).
#    One type per rule: magiskpolicy rejects a whole rule if any type is unknown.
pol() { o=$(magiskpolicy --live "$1" 2>&1); echo "sepol rc=$? :: $1${o:+ -> $o}"; }
pol "typeattribute tango32_device dev_type"
pol "allow { appdomain zygote app_zygote webview_zygote crash_dump } tango32_device chr_file { ioctl read write getattr lock append map open }"
pol "allow { appdomain zygote app_zygote webview_zygote } system_lib_file file { execute execute_no_trans read open getattr map }"
# Wrapper: zygote runs sh/toybox, re-execs zygote_exec, mounts over /apex, appends its log
pol "allow zygote shell_exec file { read open getattr execute map }"
for t in toolbox_exec system_file zygote_exec; do
  pol "allow zygote $t file { read open getattr execute execute_no_trans map }"
done
for t in rootfs system_file system_lib_file apex_mnt_dir device tmpfs; do
  pol "allow zygote $t dir { mounton search getattr read open }"
done
pol "allow zygote zygote capability sys_admin"
pol "allow zygote device file { append write open getattr }"
# 32-bit crashes: crash_dump32 lives on a nosuid (/data) bind
pol "allow { zygote appdomain } crash_dump process2 nosuid_transition"
[ -e "$MODDIR/zygote_permissive" ] && pol "permissive zygote"

# 1) Props (ro.* via resetprop; must precede zygote-start)
resetprop ro.vendor.oplus.tango_allow32 true
resetprop ro.vendor.oplus.tango_binfmt_misc_support 1
resetprop ro.vendor.oplus.app32_boost_support 1
for p in ro.product.cpu.abilist ro.system.product.cpu.abilist ro.vendor.product.cpu.abilist; do
  resetprop $p arm64-v8a,armeabi-v7a,armeabi
done
for p in ro.product.cpu.abilist32 ro.system.product.cpu.abilist32 ro.vendor.product.cpu.abilist32; do
  resetprop $p armeabi-v7a,armeabi
done
resetprop dalvik.vm.isa.arm.variant cortex-a75
resetprop dalvik.vm.isa.arm.features default
resetprop tango.debug off
# v1.1: no "This app was built for an older version of Android" popup (stock 28; old apps are the point here)
resetprop ro.build.version.min_supported_target_sdk 0
resetprop persist.sys.tango_zygote32.start 1

# 2) Device label + wrapper log
chcon u:object_r:tango32_device:s0 /dev/tango32 && echo "dev label ok" || echo "WARN: dev label failed"
: > /dev/tango32_ns.log && chmod 0666 /dev/tango32_ns.log && chcon u:object_r:device:s0 /dev/tango32_ns.log

# 3) binfmt_misc registration (from CN tango-binfmt.rc; F flag opens translator now)
T=$MODDIR/system/system_ext/bin/tango_translator
[ -e /proc/sys/fs/binfmt_misc/register ] || mount -t binfmt_misc none /proc/sys/fs/binfmt_misc
if [ ! -e /proc/sys/fs/binfmt_misc/tango_translator ]; then
  # Literal backslash escapes; the kernel decodes \xNN itself. printf %s avoids shell escape processing.
  REG=':tango_translator:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfe\xff\xff\xff:'"$T"':POCF'
  printf '%s' "$REG" > /proc/sys/fs/binfmt_misc/register \
    && echo "binfmt registered" || echo "ERR: binfmt register failed"
fi
echo 1 > /proc/sys/fs/binfmt_misc/tango_translator 2>/dev/null
cat /proc/sys/fs/binfmt_misc/tango_translator 2>/dev/null | head -3

# 4) Wait for APEX activation, then layer 32-bit libs (additive: stock always wins)
i=0
while [ $i -lt 40 ]; do
  s=$(getprop apexd.status); [ "$s" = activated ] || [ "$s" = ready ] && break
  sleep 0.5; i=$((i+1))
done
echo "apexd.status=$(getprop apexd.status)"

# SELinux context of a path (no symlink follow)
# Magisk runs this under busybox (standalone); its stat prints a literal "C" for %C.
# Use toybox by full path and require a real "u:..." context.
ctx() {
  local c
  c=$(/system/bin/stat -c %C "$1" 2>/dev/null)
  case "$c" in u:*) ;; *) c=$(/system/bin/ls -dZ "$1" 2>/dev/null | awk '{print $1}');; esac
  echo "$c"
}

# Recreate SRC at DST: symlink copied, file/dir bind-mounted
place() {
  if [ -L "$1" ]; then
    ln -s "$(readlink "$1")" "$2" && /system/bin/chcon -h "$(ctx "$1")" "$2"
  elif [ -d "$1" ]; then
    mkdir "$2" && mount -o bind "$1" "$2"
  else
    touch "$2" && mount -o bind "$1" "$2"
  fi || { echo "  ERR place $1"; FAIL=1; }
}

# Build DST from ORIG (stock dir) + MOD (module dir). Dirs present in both are
# merged one level deeper (e.g. bin/); on any other name clash stock wins.
merge() {
  local o=$1 m=$2 t=$3 e n
  mkdir -p "$t" && chmod 0755 "$t" && /system/bin/chcon "$(ctx "$o")" "$t" || { echo "  ERR dir $t"; FAIL=1; return; }
  for e in "$o"/*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    n=${e##*/}
    if [ -d "$e" ] && [ ! -L "$e" ] && [ -d "$m/$n" ] && [ ! -L "$m/$n" ]; then
      merge "$e" "$m/$n" "$t/$n"
    else
      place "$e" "$t/$n"
    fi
  done
  for e in "$m"/*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    n=${e##*/}
    if [ ! -e "$t/$n" ] && [ ! -L "$t/$n" ]; then
      place "$e" "$t/$n" && echo "  + ${t#/dev/tango32_apex/}/$n"
    fi
  done
}

mkdir -p /dev/tango32_apex
for d in "$MODDIR"/apex/*; do
  n=${d##*/}; tgt=/apex/$n; S=/dev/tango32_apex/$n
  [ -d "$tgt" ] || { echo "skip $n (not active)"; continue; }
  [ -d "$tgt/lib" ] && { echo "skip $n (lib exists)"; continue; }
  mkdir -p "$S" && mount -t tmpfs -o mode=0755 tango32 "$S" || { echo "ERR tmpfs $n"; continue; }
  FAIL=0
  echo "merge $n"
  merge "$tgt" "$d" "$S"
  if [ $FAIL = 0 ] && mount -o rbind "$S" "$tgt"; then
    if [ -s "$tgt/apex_manifest.pb" ]; then
      echo "bind $n ok"
    else
      umount -l "$tgt"; echo "ERR bind $n empty after mount, reverted"
    fi
  else
    echo "ERR bind $n (left stock)"
  fi
done
ls -l /apex/com.android.runtime/lib/bionic/libc.so /apex/com.android.art/lib/libart.so 2>&1

# 4b) Stage full CN APEX trees for the zygote_tango namespace (global mounts under /dev only;
#     nothing here touches /apex). Each = apex_cn/<n>/* + apex/<n>/lib (adbd ships its own lib).
mkdir -p /dev/tango32_cn
if [ -e "$MODDIR/ns_off" ]; then
  echo "ns_off present: no CN staging"
else
  while read -r n; do
    case "$n" in ''|\#*) continue;; esac
    src=$MODDIR/apex_cn/$n; S=/dev/tango32_cn/$n
    [ -d "$src" ] && [ -d "/apex/$n" ] || { echo "ns skip $n"; continue; }
    mkdir -p "$S" && mount -t tmpfs -o mode=0755 tango32cn "$S" && chmod 0755 "$S" \
      && /system/bin/chcon "$(ctx /apex/$n)" "$S" || { echo "ERR ns tmpfs $n"; continue; }
    FAIL=0
    for e in "$src"/*; do place "$e" "$S/${e##*/}"; done
    [ -e "$S/lib" ] || { [ -d "$MODDIR/apex/$n/lib" ] && place "$MODDIR/apex/$n/lib" "$S/lib"; }
    if [ $FAIL = 0 ] && [ -s "$S/apex_manifest.pb" ] && [ -d "$S/lib" ]; then
      echo "ns stage $n ok"
    else
      umount -l "$S"; rmdir "$S"; echo "ERR ns stage $n (dropped)"
    fi
  done < "$MODDIR/ns_apex.list"
fi
ls -lZ /system/framework/tango-shim.jar 2>&1

# 5) Dirs Tango/ART expect (32-bit cache wiped each boot: its ART may have changed)
rm -rf /data/dalvik-cache/arm
mkdir -p /data/dalvik-cache/arm && chown root:system /data/dalvik-cache/arm && chmod 0771 /data/dalvik-cache/arm
chcon u:object_r:dalvikcache_data_file:s0 /data/dalvik-cache/arm
mkdir -p /data/tango/log /data/tango/pretrans_log && chmod 0755 /data/tango && chmod 0777 /data/tango/log /data/tango/pretrans_log
echo "post-fs-data done $(date)"
