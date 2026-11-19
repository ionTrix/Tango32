# Tango32 apps folder + settings — sourced by customize.sh, action.sh, logs.sh, service.sh, patches.sh, patches/apply.sh (v1.1, 2026-11-14 23:40 ET)
# Old APKs go in one fixed folder: /sdcard/Tango32 (top of shared storage, out of the way of
#   Download clean-ups). Created at install; boot (service.sh) and Action recreate it (with README.txt) if missing.
#   Moved or renamed copies are not tracked on purpose: one location = nothing to troubleshoot.
SD=/storage/emulated/0
TDEF=$SD/Tango32
TSHOW=sdcard/Tango32
# v1.1: logs in their own subfolder: logs/tango32_logs.zip (bug report) + logs/install.log (Action installs + quick tests)
TLOGS=$TDEF/logs; TLSHOW=$TSHOW/logs; ILOG=$TLOGS/install.log

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
for 5 sec. Logs are saved in the logs folder: tango32_logs.zip
(bug report) and install.log (installs and quick tests from Action).
Logs may contain personal data, review first.

Max debug logging (for testers): create an empty file named debug.txt
in this folder and reboot. Every boot is then logged in full, and
debug.txt shows what was saved and how to send it. Delete debug.txt
and reboot to turn it off.
EOF_README
}

# v1.2 debug max: the user creates sdcard/Tango32/debug.txt (any content). post-fs-data can't read shared storage
#   (locked until the first unlock), so service.sh mirrors it into settings: debug=max | off (dbg_check).
#   Max = boot capture on every boot (15 min, last 3 boots kept) + 6_debug_* files in the logs zip (logs.sh).
#   After boot, debug.txt is rewritten with a summary: files written + how to submit (dbg_summary).
TDBG=$TDEF/debug.txt
dbg_check() {   # after shared storage is up. Echoes "on" when debug.txt was just found (capture starts late this boot)
  if [ -e "$TDBG" ]; then [ "$(sget debug)" = max ] || { sset debug max; echo on; }
  elif [ "$(sget debug)" = max ]; then sset debug off; fi
}
dbg_summary() {   # $1 = "late" when debug.txt was found this boot (capture started after unlock)
  [ -e "$TDBG" ] || return 0
  {
    echo "Tango32 MAX DEBUG LOGGING: ON"
    echo "This file turns it on. To turn it off: delete debug.txt and reboot."
    echo
    echo "Updated $(date '+%Y-%m-%d %H:%M:%S') · Tango32 $(sed -n 's/^version=//p' $MODDIR/module.prop) · $(getprop ro.product.model) · $(getprop ro.build.display.id)"
    [ "$1" = late ] && echo "First boot with debug.txt: capture started after unlock this time; from the next boot it starts early."
    echo
    echo "What is logged: every boot, the first 15 minutes (full logcat of all buffers, kernel log, boot reason,"
    echo "'last alive' time, and the previous boot's crash log if the kernel kept it). The 3 newest boots are kept."
    echo "The logs zip also gets the full current logcat, kernel log, system properties, processes and full crash"
    echo "reports (6_debug_*.txt)."
    echo
    echo "Files written (on the phone, root only: $TDATA/bootlog/):"
    ls -l $TDATA/bootlog/ 2>/dev/null | awk 'NR > 1 && $NF !~ /\.tmp$/ { printf "  %-26s %8.1f KB  %s %s\n", $NF, $5 / 1024, $(NF-2), $(NF-1) }'
    [ -f "$TLOGS/tango32_logs.zip" ] && echo "Logs zip: $TLSHOW/tango32_logs.zip ($(ls -l "$TLOGS/tango32_logs.zip" | awk '{ printf "%.1f KB, saved %s %s", $5 / 1024, $6, $7 }'))"
    echo
    echo "How to send it:"
    echo "  1. Reproduce the problem (or let the phone reboot by itself). For a reboot, wait for the phone to come back up."
    echo "  2. Save fresh logs: Magisk > Modules > Tango32 > Action, hold [Vol+] + [Vol-] for 5 sec"
    echo "     (or Termux: su -c sh /data/adb/modules/tango32/logs.sh). The zip saved after boot only has the"
    echo "     first moments of the capture; saving again 15 minutes after boot gets all of it."
    echo "  3. Attach $TLSHOW/tango32_logs.zip to your GitHub issue: https://github.com/ionTrix/Tango32/issues"
    echo
    echo "Logs may contain personal data (full logcat: account names, other apps), review first."
  } > "$TDBG.n" 2>/dev/null && mv -f "$TDBG.n" "$TDBG"
}

# Settings that survive module updates (v1.1): /data/adb/tango32/settings, key=value
#   last_check=<epoch> (patches.sh status) · last_seq=<index seq> (an older index is refused)
#   bootlog_left=<n> (v1.2: boots still to capture, see bootlog.sh; set to 2 at install)
#   Online patches go to /data/adb/tango32/patches/. uninstall.sh removes the whole folder.
TDATA=/data/adb/tango32; TSET=$TDATA/settings
sget() { sed -n "s/^$1=//p" "$TSET" 2>/dev/null | tail -1; }
sset() { mkdir -p "$TDATA" && { grep -v "^$1=" "$TSET" 2>/dev/null; echo "$1=$2"; } > "$TSET.$$" && mv "$TSET.$$" "$TSET"; }

# Install log: raw entries in $TDATA/install.raw (Action appends), rendered readable to logs/install.log (ilog_render).
IRAW=/data/adb/tango32/install.raw

# Readable files: title block, numbered Contents, banner headers. "== X" lines = sections (§1, §2 …), "-- X" lines =
#   subsections (§1.1 …; top level when a file has no "==" lines). Search a viewer for "§3" to jump there.
fmt() {  # $1 = file, $2 = title, $3 = 1: Contents lists sections only (install log: one per install)
  [ -s "$1" ] || return 0
  awk -v title="$2" -v top="${3:-0}" -v when="$(date '+%Y-%m-%d %H:%M:%S')" '
    function lv(l) { if (l ~ /^== /) return 1; if (l ~ /^-- /) return (has1 ? 2 : 1); return 0 }
    function nm(l) { sub(/^(==|--) +/, "", l); sub(/:$/, "", l); return l }
    function num(l,  v) { v = lv(l); if (v == 1) { a++; b = 0; return a } b++; return a "." b }
    function short(l,  f) { split(l, f, " · "); return substr(f[1], 6, 11) " · " f[2] " · " f[3] }   # W1: MM-DD HH:MM · what · app ver
    function brief(r,  f, k) { k = split(r, f, ": "); return (k > 2) ? f[1] ": " f[2] : r }   # W11: result up to its 2nd ": "
    function up(l) { return (l ~ /[·\/]/) ? l : toupper(l) }   # names with a package/path stay as they are
    NR == FNR { if ($0 ~ /^== /) { has1 = 1; k1++ } if ($0 ~ /^result: /) res[k1] = substr($0, 9); L[NR] = $0; n = NR; next }
    FNR == 1 {
      rule = "================================================================"
      print rule; print "  " title; print "  Tango32 · saved " when; print rule; print ""
      print "Contents (search for the § number to jump there)"
      for (i = 1; i <= n; i++) if (lv(L[i])) { s = num(L[i]); if (!(top && index(s, "."))) print (index(s, ".") ? "    " : "  ") "§" s "  " (top ? short(nm(L[i])) : nm(L[i])) ((s in res) ? "  →  " (top ? brief(res[s]) : res[s]) : "") }
      a = 0; b = 0; print ""; blank = 1
    }
    function out(x) { if (x == "" && blank) return; print x; blank = (x == "") }   # W3: never two blank lines in a row
    { v = lv($0)
      if (v == 1) { s = num($0); out(""); out(rule); out("§" s "  " up(nm($0))); out(rule) }
      else if (v == 2) { s = num($0); t = "--- §" s "  " nm($0) " "; while (length(t) < 64) t = t "-"; out(""); out(t) }
      else out($0) }' "$1" "$1" > "$1.f" && mv "$1.f" "$1"
}
ilog_render() { mkdir -p "$TLOGS" 2>/dev/null && cp "$IRAW" "$ILOG.n" 2>/dev/null \
  && fmt "$ILOG.n" "INSTALL LOG: Action installs and quick tests (newest last)" 1 && mv "$ILOG.n" "$ILOG"; }
