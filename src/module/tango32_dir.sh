# Tango32 apps folder — sourced by customize.sh and action.sh (v1.0, 2026-11-07 23:10 ET)
# Old APKs go in one fixed folder: /sdcard/Tango32 (top of shared storage, out of the way of
#   Download clean-ups). Created at install; boot (service.sh) and Action recreate it (with README.txt) if missing.
#   Moved or renamed copies are not tracked on purpose: one location = nothing to troubleshoot.
SD=/storage/emulated/0
TDEF=$SD/Tango32
TSHOW=sdcard/Tango32

# tmake: create the folder + (re)write README.txt (ours: rewritten so wording updates arrive)
tmake() {
  mkdir -p "$TDEF" 2>/dev/null || return 1
  cat > "$TDEF/README.txt" 2>/dev/null <<'EOF_README'
Tango32 apps folder

Place older apps (APKs) here that Android refuses to install,
then open Magisk > Modules > Tango32 > Action.

Only this sdcard/Tango32 folder location is scanned for apps.
This folder will be recreated if it is missing after a reboot.

All other apps are installed normally using Android file manager.

To save logs for a bug report, open Action and hold [Vol+] + [Vol−]
for 5 sec. Logs may contain personal data, review first.
EOF_README
}
