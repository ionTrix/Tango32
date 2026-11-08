# Tango32 installer (v1.0, 2026-11-07 23:10 ET). Own extraction, so the header + build check come first;
#   chown -h (no errors on symlinks into /system/lib).
# SKIPUNZIP=1: Magisk only extracts this script; we check the phone first, then extract.
SKIPUNZIP=1

ui_print "- Installing Tango32 @VER@"
# Hard guard: the module (framework shim + parcel bridge) is built from the firmware of ONE phone build.
# target.prop is written by build.sh from that phone's build.txt (pull_fw.sh). Any mismatch = no install.
stop() { ui_print "$1"; ui_print "! Not installed. Nothing on the phone was changed."; rm -rf "$MODPATH"; abort "! Aborting."; }
unzip -oq "$ZIPFILE" target.prop -d "$MODPATH" >/dev/null 2>&1
T="$MODPATH/target.prop"
[ -f "$T" ] || stop "! target.prop missing: this zip wasn't made by the Tango32 build."
TM=$(sed -n 's/^model=//p' "$T"); TF=$(sed -n 's/^fingerprint=//p' "$T"); TD=$(sed -n 's/^display=//p' "$T")
MODEL=$(getprop ro.product.model); FP=$(getprop ro.build.fingerprint); DISP=$(getprop ro.build.display.id)
[ "$MODEL" = "CPH2583" ] && [ "$MODEL" = "$TM" ] \
  || stop "! Wrong phone: this is $MODEL. Tango32 is for the OnePlus 12 NA (CPH2583) only."
[ "$FP" = "$TF" ] || {
  ui_print "! Wrong build. Module was built for:"; ui_print "!   $TD"; ui_print "! This phone runs:"; ui_print "!   $DISP"
  stop "! Rebuild with pull_fw.sh + build.sh on this firmware."; }
ui_print "- Build check OK: $DISP"
[ -e /dev/tango32 ] || stop "! /dev/tango32 missing: kernel has no Tango driver."
grep -q binfmt_misc /proc/filesystems || stop "! Kernel lacks binfmt_misc."

ui_print "- Extracting module files"
unzip -oq "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >/dev/null 2>&1 || stop "! Unable to extract the zip."

ui_print "- Setting permissions"
# = set_perm_recursive $MODPATH 0 0 0755 0644, but -h: never follow symlinks (some point into /system/lib,
#   which only exists once the module is mounted -> chown errors)
find "$MODPATH" -type d -exec chmod 0755 {} +
find "$MODPATH" -type f -exec chmod 0644 {} +
chown -hR 0:0 "$MODPATH"
chcon -hR u:object_r:system_file:s0 "$MODPATH" 2>/dev/null
for f in system/bin/app_process32 system/bin/app_process32_tango system/bin/bootstrap/linker system/system_ext/bin/tango_translator \
         apex/com.android.runtime/bin/linker apex/com.android.runtime/bin/crash_dump32 \
         apex/com.android.art/bin/dex2oat32 apex/com.android.art/bin/dalvikvm32 \
         post-fs-data.sh service.sh uninstall.sh action.sh tango32_dir.sh logs.sh; do
  [ -e "$MODPATH/$f" ] && chmod 0755 "$MODPATH/$f"
done
for f in "$MODPATH"/apex_cn/*/bin/*; do [ -f "$f" ] && chmod 0755 "$f"; done
chmod 0755 "$MODPATH/system/vendor/lib" 2>/dev/null

ui_print "- Applying SELinux labels"
n=0
while read -r p c; do
  [ -n "$p" ] || continue
  chcon -h "$c" "$MODPATH/$p" 2>/dev/null && n=$((n+1))
done < "$MODPATH/contexts.txt"
ui_print "- Labeled $n paths"
# apps folder for Action: /sdcard/Tango32 (Action recreates it too if missing)
. "$MODPATH/tango32_dir.sh"
if [ -d "$TDEF" ]; then tmake; ui_print "- Apps folder: $TSHOW"
elif tmake; then ui_print "- Created apps folder: $TSHOW"
else ui_print "- Apps folder: Action will create $TSHOW"; fi
ui_print "- Tango32 module installed"
ui_print "- Reboot to start the 32-bit zygote"
