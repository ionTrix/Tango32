#!/system/bin/sh
# Tango32 action (v1.1, 2026-11-15 ET): opens straight on the install list.
#   v1.1: unreadable APKs show [?bit] + a hint (were [64bit]); failed installs show the real reason (not a stack-trace line).
#   v1.1: online app patches (patches.sh): every open asks whether to check GitHub for new app patches
#   (hold Vol+ Yes / Vol− No; nothing saved, No skips this time only); Yes checks (~10 s max) and applies
#   new patches for installed apps before the list. No check ever runs at boot.
#   v1.1: pre-flight check (apkinfo.jar Preflight, cached): each 32-bit APK's libs are checked for Android functions
#   this phone lacks (⚠ line) and matched to app patch families (🩹 Fix available / Fix to try). After the install a
#   certain match (type=symbol) is applied on its own. Then every install gets a quick test: the app opens and must
#   keep running 5 s (crash / closed / didn't start = failed), is force-stopped and Magisk comes back. On a failure
#   each matching behavior family is auto-patched in turn and tested again (removed if it still fails). Everything
#   goes to sdcard/Tango32/logs/install.log, with crash details for failed tests.
#   Hold Vol+ and Vol- together 5 s: save bug report logs (logs.sh: crash lines, recent + Tango-related logcat) from anywhere, then back
#   to the same entry. After installing an app that a Tango32 patch family lists (patches/<id>/), the patch is
#   applied (🩹 = installed and patched).
# Install old APKs from /sdcard/Tango32 that Android refuses (targetSdk < 23 on Android 14,
#   < 24 on 15+; picked from ro.build.version.sdk), with the volume keys. Newer APKs (32- or 64-bit) install normally
#   from any file manager, so they are not listed.
#   Vol+ / Vol-  scroll up / down (wraps)     hold Vol+ or Vol-  install the APK shown, then keep scrolling
#   Marks (emoji, 2 columns each): ⬛ available (not installed) · ✅ installed (same version) · 🔼 update (APK is newer) · 🔽 downgrade (installed is
#   newer; versionCode compare) · 🔀 mismatched signature (uninstall + install after a confirm) · ✅+🩹 installed and patched
#   Leave with Magisk's back arrow (key readers stop themselves). 5 min without a key press: timeout.
#   Magisk's log doesn't wrap: every line is wrapped here at 54 columns (55-57 let the log pan sideways a little; 54 tested OK).
#   Each run has its own temp dir: an old run (still alive after the back arrow) is killed at start, and its
#   cleanup can't delete the dir the new run is using (else: endless "can't open .../keys").
MODDIR=${0%/*}
ROOT=/storage/emulated/0
. $MODDIR/tango32_dir.sh   # TDEF / TSHOW / tmake (apps folder)
T=/data/local/tmp/tango32_action.$$
HOLD_MS=1000; IDLE=300; WIDTH=54; PIDF=/data/local/tmp/tango32_action.pids
killtree() { for p in "$@"; do
    for c in $(awk -v pp=$p '$4==pp{print $1}' /proc/[0-9]*/stat 2>/dev/null); do kill $c 2>/dev/null; done
    kill $p 2>/dev/null; done; }
# leftovers from an earlier run (main script + key readers; PIDF line 1 = its main pid)
#   (only pids that are still action.sh: a stale pid may belong to something else by now)
[ -f $PIDF ] && { killtree $(for p in $(cat $PIDF); do grep -q action.sh /proc/$p/cmdline 2>/dev/null && echo $p; done); rm -f $PIDF; }
#   (2>/dev/null: the killed run's own cleanup may be deleting the same files right now)
rm -rf /data/local/tmp/tango32_action /data/local/tmp/tango32_action.[0-9]* 2>/dev/null
mkdir -p $T; : > $T/keys
RPIDS=
cleanup() { killtree $RPIDS; rm -rf $T; [ "$(head -1 $PIDF 2>/dev/null | cut -d' ' -f1)" = "$$" ] && rm -f $PIDF; }
trap cleanup EXIT; trap 'exit 1' INT TERM   # killed: exit (runs cleanup) instead of carrying on
BACK="Tap back arrow to exit"
MAIN=$$
TAB=$(printf '\t'); SP=$(printf '\001')
# wr FIRST_INDENT NEXT_INDENT TEXT: print TEXT wrapped at $WIDTH (breaks at spaces; long words at "/" or hard;
#   \001 = a space that is kept, not a break point)
wr() {
  printf '%s\n' "$3" | awk -v w=$WIDTH -v i1="$1" -v i2="$2" 'function fx(x) { gsub(/\001/, " ", x); return x }
  {
    n = split($0, a, " "); line = i1; first = 1
    for (k = 1; k <= n; k++) {
      wd = a[k]
      while (1) {
        sep = first ? "" : " "
        if (length(line) + length(sep) + length(wd) <= w) { line = line sep wd; first = 0; break }
        if (!first) { print fx(line); line = i2; first = 1; continue }
        room = w - length(line); if (room < 8) room = 8
        cut = room; head = substr(wd, 1, room)
        for (j = room; j > 1; j--) if (substr(head, j, 1) == "/") { cut = j; break }
        print fx(line substr(wd, 1, cut)); wd = substr(wd, cut + 1); line = i2
        if (wd == "") { first = 1; break }
      }
    }
    if (line != "" && line != i2) print fx(line)
  }'
}

cat <<'EOF_HEADER'
          _____                      _________
         |_   _|_ _ _ __   __ _  ___|___ /___ \
           | |/ _` | '_ \ / _` |/ _ \ |_ \ __) |
           | | (_| | | | | (_| | (_) |__) / __/
           |_|\__,_|_| |_|\__, |\___/____/_____|
                          |___/
                                  by ionTrix



                32-bit App Support · @VER@
EOF_HEADER
box_install() { cat <<'EOF_BOX'
┌────────────────────────────────────────────────────┐
│     [Vol+] / [Vol−]  Press scrolls up/down         │
│     [Vol+] / [Vol−]  Hold 1 sec installs app       │
│     [Vol+] + [Vol−]  Hold 5 sec saves logs         │
│     [ ←  ]           Tap top-left arrow exits      │
│                                                    │
│         ⬛ Available    •   ✅ Installed           │
│         🔼 Update       •   🔽 Downgrade           │
│         🔀 Mismatched   •   ✅+🩹 Patched          │
└────────────────────────────────────────────────────┘
EOF_BOX
}
SDK=$(getprop ro.build.version.sdk); CUT=23; AV=6
[ "${SDK:-0}" -ge 35 ] 2>/dev/null && { CUT=24; AV=7; }
BELOW="below Android $AV (API $CUT)"
count() { case $N in 0) echo "No APKs found $BELOW";; 1) echo "1 APK found $BELOW";; *) echo "$N APKs found $BELOW";; esac; echo; }
none() { wr "  " "  " "Place older apps inside $TSHOW folder."; echo
  wr "  " "  " "Install normal apps with Android file manager."; echo; }

# --- volume-key reader: raw evdev events (no getevent buffering), kernel timestamps for hold time ---
reader() {  # $1 = /dev/input/eventN, $2 = tag
  exec 3<"$1"; E=$T/ev$2   # (set -- below overwrites $1/$2: keep the event file name here)
  while dd bs=24 count=1 <&3 of=$E 2>/dev/null; do
    [ -d /proc/$MAIN ] || exit 0   # main script gone (Magisk back arrow): stop
    [ "$(od -An -tu2 -j16 -N2 $E | tr -d ' ')" = 1 ] || continue
    co=$(od -An -tu2 -j18 -N2 $E | tr -d ' ')
    case $co in 114|115) ;; *) continue;; esac
    va=$(od -An -td4 -j20 -N4 $E | tr -d ' ')
    set -- $(od -An -tu8 -N16 $E)
    echo "$co $va $(( $1 * 1000 + $2 / 1000 ))" >> $T/keys
  done
}
k=0
for d in $(getevent -pl 2>/dev/null | awk '/^add device/{d=$4} /KEY_VOLUMEUP|KEY_VOLUMEDOWN/{print d}' | sort -u); do
  k=$((k+1)); reader "$d" $k </dev/null >/dev/null 2>&1 &
  RPIDS="$RPIDS $!"
done
echo $MAIN $RPIDS > $PIDF
[ -n "$RPIDS" ] || { echo "No volume keys found • $BACK"; exit 1; }

C=0; SW=0; CS=; S1=; dc=; D115=; D114=
# Key state: D115/D114 = key is down. S1 = uptime when a single key went down (hold timer).
#   CS = uptime when both keys were down (logs timer). SW = this press is used up, ignore keys until
#   both are released: 1 = both keys went down, 2 = a hold already fired (install).
#   Holds fire while the key is held (1 s install, 5 s logs); a short press scrolls on release.
up_cs() { read u _ < /proc/uptime; U=${u%.*}${u#*.}; U=${U#0}; }   # uptime in 1/100 s
drain() {  # after an action: read the key lines that came in meanwhile, keep only up/down state
  n=$(wc -l < $T/keys)
  while [ $C -lt $n ]; do
    C=$((C+1)); set -- $(sed -n "${C}p" $T/keys)
    case $2 in 1) eval D$1=1;; 0) eval D$1=;; esac
  done
  CS=; S1=; dc=
  if [ -z "$D115$D114" ]; then SW=0; elif [ $SW = 0 ]; then SW=1; fi
}
nextkey() {  # -> KEY (115 = Vol+, 114 = Vol-, 0 = both held 5 s), HOLD (0/1); returns 1 after IDLE s idle
  i=0
  while :; do
    [ -f $T/keys ] || { echo "Stopped (temp files removed) • $BACK"; exit 1; }
    n=$(wc -l < $T/keys)
    while [ $C -lt $n ]; do
      C=$((C+1)); set -- $(sed -n "${C}p" $T/keys)
      if [ "$2" = 1 ]; then
        eval D$1=1; up_cs
        if [ -n "$D115" ] && [ -n "$D114" ]; then
          S1=; [ $SW = 2 ] || { SW=1; CS=$U; }
        elif [ $SW = 0 ]; then S1=$U; dc=$1
        fi
      elif [ "$2" = 0 ]; then
        eval D$1=; CS=
        if [ $SW != 0 ]; then [ -z "$D115$D114" ] && SW=0; S1=; continue; fi
        if [ "$1" = "$dc" ] && [ -n "$S1" ]; then S1=; KEY=$1; HOLD=0; return 0; fi   # short press: scroll
      fi
    done
    if [ -n "$CS$S1" ]; then
      up_cs
      if [ -n "$CS" ] && [ $((U - CS)) -ge 500 ]; then CS=; KEY=0; HOLD=0; return 0; fi
      if [ -n "$S1" ] && [ $((U - S1)) -ge $((HOLD_MS / 10)) ]; then S1=; SW=2; KEY=$dc; HOLD=1; return 0; fi
    fi
    sleep 0.1; i=$((i+1))
    [ -z "$D115$D114" ] && [ $i -ge $((IDLE * 10)) ] && return 1
  done
}

save_logs() {   # logs.sh's own messages are for the manual Termux run; Action prints its own
  Z=$TLSHOW/tango32_logs.zip
  wr "" "  " "Saving logs to $Z"; echo
  wr "  " "  " "Attach logs along with your GitHub issue."   # shown first: read while logcat is collected
  wr "  " "  " "Logs may contain personal data, review first."; echo
  if sh $MODDIR/logs.sh >/dev/null 2>&1; then echo "Successfully saved logs"
  else echo "Failed save: can't write $TLSHOW"; fi
  echo
}
ask() {  # $1 = question, $2 = explanation -> 0 if Yes (hold Vol+), else No
  wr "" "  " "$1"; wr "  " "  " "$2"; echo
  echo "  [Vol+] / [Vol−]  Hold 1 sec confirms Yes/No"; echo
  # only a full 1 s hold answers (taps ignored); no answer before the idle timeout: exit as timed out (no "Canceled")
  while :; do nextkey || { echo "Timed out • $BACK"; exit 0; }; [ $HOLD = 1 ] && break; done
  [ $KEY = 115 ]
}
echo; box_install; echo

# --- online app patches: asked on every open, nothing saved (patches.sh: signed index from GitHub) ---
if ask "Check GitHub for new app patches?" \
  "Fixes for old apps can arrive without a module update. Nothing about you or your apps is sent."
then
  echo "Checking for app patches . . ."
  sh $MODDIR/patches.sh check action 2>/dev/null | while IFS= read -r l; do wr "" "  " "$l"; done; echo
fi
drain   # No: straight to the scan (ask's blank line already separates it)

# --- scan + APK info -------------------------------------------------------------------------------
# apps folder: only /sdcard/Tango32 (recreated with its README if missing)
tmake
echo "Scanning $TSHOW . . ."
find "$TDEF" -name '.*' -prune -o -type f -iname '*.apk' -print 2>/dev/null > $T/sorted
N=$(wc -l < $T/sorted)
[ $N = 0 ] && : > $T/list || CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin com.tango32.ApkInfo < $T/sorted > $T/list 2> $T/info.err
# fallback (helper missing/failed): file name only, ABIs from the zip listing, targetSdk unknown (listed)
if [ $N != 0 ] && [ ! -s $T/list ]; then
  while IFS= read -r f; do
    if unzip -l "$f" >/dev/null 2>&1; then
      a=$(unzip -l "$f" 2>/dev/null | grep -oE 'lib/[^/]+/[^ ]*\.so' | cut -d/ -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
    else a='?'; fi   # not a readable zip (damaged / incomplete download)
    printf '%s\t\t\t\t%s\t\t\t\n' "$f" "$a"
  done < $T/sorted > $T/list
fi
# pre-flight (cached in /data/adb/tango32/preflight.cache): path missing example symbol_ids behavior_ids
: > $T/pf; [ $N != 0 ] && [ -s $T/list ] && CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin com.tango32.Preflight \
  "$TDATA/preflight.cache" "$(getprop ro.build.fingerprint) $(sed -n 's/^versionCode=//p' $MODDIR/module.prop)" \
  "$MODDIR/patches" "$TDATA/patches" < $T/sorted > $T/pf 2>/dev/null
# alphabetical by app name (file name if no label), 0-9 then a-z, case-insensitive
awk -F'\t' '{n=$4; if (n=="") {n=$1; sub(/.*\//,"",n)} print tolower(n) "\t" $0}' $T/list | sort -t "$TAB" -k1,1 | cut -f2- > $T/list.s && mv $T/list.s $T/list

# all: path pkg ver label abis vcode tag mark tsdk  (tag 32 = 32-bit only; 64 = arm64 or no native code; ? = APK unreadable)
#   + pre-flight: miss example sym beh (columns 10-13)
refresh() {
  pm list packages --show-versioncode 2>/dev/null | sed -E 's/^package:([^ ]+)( versionCode:([0-9]+))?.*/\1 \3/' > $T/pkgs
  [ -s $T/pkgs ] || echo "_ 0" > $T/pkgs
  # signer of each installed app that is also in the list (its base.apk), to spot mismatched signatures
  : > $T/ipaths
  for p in $(cut -f2 $T/list | sort -u); do
    grep -q "^$p " $T/pkgs || continue
    b=$(pm path "$p" 2>/dev/null | grep -m1 base.apk); [ -n "$b" ] && echo "${b#package:}" >> $T/ipaths
  done
  : > $T/isig; [ -s $T/ipaths ] && CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin com.tango32.ApkInfo \
    < $T/ipaths 2>/dev/null | awk -F'\t' '$2 != "" { print $2 "\t" $8 }' > $T/isig
  [ -s $T/isig ] || echo "_	_" > $T/isig
  # marks: ✅ same version · 🔼 APK newer · 🔽 APK older · 🔀 signed by someone else (both signers known)
  awk -F'\t' -v OFS='\t' 'FILENAME == ARGV[1] { split($0, b, " "); v[b[1]] = b[2]; seen[b[1]] = 1; next }
    FILENAME == ARGV[2] { sg[$1] = $2; next }
    FILENAME == ARGV[3] { pf[$1] = $2 "\t" $3 "\t" $4 "\t" $5; next }
    { a = "," $5 ","; tag = ($5 == "?") ? "?" : ((a ~ /,arm64-v8a,/) ? 64 : ((a ~ /,armeabi/) ? 32 : 64)); m = ""
      if ($2 != "" && ($2 in seen)) { m = "✅"
        if ($6 != "" && v[$2] != "") { if ($6 + 0 > v[$2] + 0) m = "🔼"; else if ($6 + 0 < v[$2] + 0) m = "🔽" }
        if ($8 != "" && sg[$2] != "" && $8 != sg[$2]) m = "🔀" }
      x = ($1 in pf) ? pf[$1] : "\t\t\t"
      print $1, $2, $3, $4, $5, $6, tag, m, $7, x }' $T/pkgs $T/isig $T/pf $T/list > $T/all
}
# only APKs Android won't install normally (unknown targetSdk = listed, to be safe).
#   Android 14 (SDK 34) refuses targetSdk < 23; Android 15+ (SDK 35+) refuses < 24.
mklist() { awk -F'\t' -v c=$CUT '$9=="" || $9+0 < c' $T/all > $T/cur_list; N=$(wc -l < $T/cur_list); }
refresh; mklist
count; [ $N = 0 ] && none

haspatch() { KF=; [ -n "$pkg" ] && KF=$(sh $MODDIR/patches/apply.sh "$pkg" has 2>/dev/null); }   # KF = id<TAB>name of its family; no package (unreadable APK) = none
famname() { sed -n 's/^name=//p' "$TDATA/patches/$1/patch.prop" "$MODDIR/patches/$1/patch.prop" 2>/dev/null | head -1; }
field() { awk -F'\t' -v f=$1 '{print $f}' $T/cur; }
show() {
  if [ $N = 0 ]; then [ "$1" = again ] && none; return; fi
  sed -n "${IDX}p" $T/cur_list > $T/cur
  P=$(field 1); pkg=$(field 2); ver=$(field 3); lab=$(field 4); tag=$(field 7); mk=$(field 8)
  miss=$(field 10); mex=$(field 11); sym=$(field 12); beh=$(field 13); sym=${sym%%,*}; behs=$beh; beh=${beh%%,*}
  nm=${lab:-${P##*/}}
  case $ver in ""|[vV]*) ;; *) ver=v$ver;; esac   # "1.3" -> "v1.3"
  KF=; pt=; haspatch && [ -n "$mk" ] && sh $MODDIR/patches/apply.sh "$pkg" check >/dev/null 2>&1 && pt="+🩹"   # installed and patched: ✅+🩹
  tg="[${tag}bit]"   # unreadable APK = [?bit] (F12)
  wr "  " "    " "$IDX/$N ${mk:-⬛}$pt $nm${ver:+ $ver}$SP$tg"   # ⬛ = available (not installed; keeps names aligned)
  wr "  " "    " "${P#$SD/}"   # Tango32/... (no sdcard/: room for the file name)
  [ "$tag" = "?" ] && wr "  " "    " "Can't read damaged or corrupt APK"
  if [ -z "$pt" ]; then   # pre-flight: a fix this app will get / can try, functions this phone lacks
    if [ -n "$KF" ]; then wr "  " "    " "🩹 Fix available: ${KF#*$TAB}"
    elif [ -n "$sym" ]; then wr "  " "    " "🩹 Fix available: $(famname $sym)"
    elif [ -n "$beh" ]; then wr "  " "    " "🩹 Fix to try if it crashes: $(famname $beh)"; fi
  fi
  # missing functions only matter when no fix covers the app (AIR ships spare libs for old Android versions it never loads)
  [ -z "$pt$KF$sym" ] && [ "${miss:-0}" -gt 0 ] 2>/dev/null && wr "  " "    " "⚠ Missing Android functions: $miss ($mex)"
  echo
}

iver() {  # installed versionName -> IV ("v2.0"), "" if unknown
  IV=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 'versionName=' | sed 's/.*versionName=//; s/[[:space:]].*//')
  case $IV in ""|[vV]*) ;; *) IV=v$IV;; esac
}
confirm_down() {  # older APK than installed: pm install -d keeps the app data
  iver; ask "Downgrade $nm${IV:+ $IV} to ${ver:-this version}?" \
    "Installed version is newer. App data is kept but older version may not read it. Continue with downgrade?"
}
confirm_swap() {  # installed app has another signer: Android only allows uninstall + install
  iver; ask "Replace $nm${IV:+ $IV} with ${ver:-this version}?" \
    "App signatures mismatch. App will be uninstalled first and data will be deleted. Continue with replacement?"
}
report() { wr "  " "  " "Works? Please send an App report on GitHub so it can be listed for everyone"; }
# --- install.log (sdcard/Tango32/logs): one entry per Action install: pre-flight, install result, patches, quick
#   tests; crash details when a quick test fails. Kept under ~512 KB (oldest lines dropped).
ilog() { printf '%s\n' "$@" >> "$IRAW" 2>/dev/null; }
ilog_start() {  # $1 = what (Install / Update / …)
  mkdir -p "$TDATA" 2>/dev/null
  [ -f "$IRAW" ] && [ "$(wc -c < "$IRAW")" -gt 524288 ] && tail -n 3000 "$IRAW" > "$IRAW.n" && mv "$IRAW.n" "$IRAW"   # first entry: no file yet
  ilog "" "== $(date '+%Y-%m-%d %H:%M:%S') · $1 · $nm${ver:+ $ver} · ${pkg:-?} · ${P#$SD/} · [${tag}bit]" \
    "Tango32 $(sed -n 's/^version=//p' $MODDIR/module.prop) · $(getprop ro.build.display.id)" \
    "pre-flight: missing ${miss:-0}${mex:+ ($mex)}${KF:+ · fix: ${KF#*$TAB}}${sym:+ · match: $sym}${behs:+ · auto-patch candidates: $behs}"
}
capture() {  # crash details of $pkg since $since (this quick test) -> install.log
  {
    echo "-- crash buffer:"; logcat -d -b crash -T "$since" 2>/dev/null | grep -A40 -F "$pkg" | head -80
    echo "-- events:"; logcat -d -b events -T "$since" 2>/dev/null | grep -E 'am_crash|am_proc_died|am_anr|am_kill' | grep -F "$pkg" | tail -8
    echo "-- app lines + warnings/errors about it (pids:$PIDS):"
    # threadtime: date time pid tid level tag: app's own pids, or W/E/F lines naming it, or ActivityManager
    logcat -d -b main,system -T "$since" 2>/dev/null | awk -v ps=" $PIDS " -v pk="$pkg" \
      'index(ps, " " $3 " ") || (index($0, pk) && ($5 ~ /^[WEF]$/ || $6 ~ /^ActivityManager/))' | tail -60
    for tb in /data/tombstones/tombstone_*; do
      [ -f "$tb" ] && [ "$(/system/bin/stat -c %Y "$tb" 2>/dev/null || echo 0)" -ge "$t0" ] && grep -qF ">>> $pkg <<<" "$tb" || continue
      echo "-- tombstone ${tb##*/}:"; grep -m1 "^pid:" "$tb"; grep -m1 "^signal" "$tb"; grep -m1 "^Abort message" "$tb"
      grep -A12 -m1 "^backtrace:" "$tb"
    done
  } 2>/dev/null | cut -c1-300 >> "$IRAW"
}
crashed() {  # app $pkg crashed since $since / $t0: crash buffer, am_crash event, or a tombstone of its own (A5: not 64-bit ART)
  logcat -d -b crash,events -T "$since" 2>/dev/null | grep -E 'am_crash|FATAL|Process: |>>> ' | grep -qF "$pkg" && return 0
  for tb in /data/tombstones/tombstone_*; do
    [ -f "$tb" ] && [ "$(/system/bin/stat -c %Y "$tb" 2>/dev/null || echo 0)" -ge "$t0" ] && grep -qF ">>> $pkg <<<" "$tb" && return 0
  done; return 1
}
# Old apps (targetSdk < 23) show Android's "review permissions" screen before their first start. For the quick test
#   the review flag is cleared (permissions as Android pre-granted them), and put back afterwards; a fresh install
#   also gets its data cleared (pm clear), so your first real start is a clean one where you choose.
#   Updates / reinstalls keep their data: only the flags are put back.
revperms() { dumpsys package "$pkg" 2>/dev/null | grep -E '^ +[A-Za-z0-9_.]+: granted=.*REVIEW_REQUIRED' | sed -E 's/^ +//; s/:.*//' | sort -u; }
permsoff() { RP=$(revperms); for x in $RP; do pm clear-permission-flags "$pkg" "$x" review-required >/dev/null 2>&1; done
  [ -n "$RP" ] && ilog "permission review skipped for the test: $(echo $RP | wc -w) permission(s)"; }
qdone() {
  if [ -n "$FRESH" ]; then pm clear "$pkg" >/dev/null 2>&1 && ilog "app data cleared after the test (fresh install)"; fi
  for x in $RP; do pm set-permission-flags "$pkg" "$x" review-required >/dev/null 2>&1; done
}
TEST=5   # quick test: seconds the app must keep running, counted from its first process
toppkg() { dumpsys activity activities 2>/dev/null | grep -m1 -E 'topResumedActivity|mResumedActivity' | grep -oE '[A-Za-z0-9_.]+/' | head -1 | tr -d /; }
selftest() {  # open $pkg, wait up to 15 s for its process, then $TEST s; crash / close / no start -> RES ("" = ok)
  sleep 5   # time to read the line above before the app covers the screen (ionTrix, 11-17)
  home=$(toppkg); t0=$(date +%s); since=$(date '+%m-%d %H:%M:%S.000'); PIDS=
  act=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$pkg" 2>/dev/null | tail -1)
  case $act in */*) am start -n "$act" >/dev/null 2>&1;; *) monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1;; esac
  seen=; RES=; i=0; n=0
  while :; do
    sleep 1; i=$((i+1))
    pp=$(pidof "$pkg" 2>/dev/null)
    [ -n "$pp" ] && { seen=1; for x in $pp; do case " $PIDS " in *" $x "*) ;; *) PIDS="$PIDS $x";; esac; done; }
    crashed && { RES=crashed; break; }
    # Android's own app-warning popups (32-bit notice, "built for an older version"): close them for the test
    case $(dumpsys window 2>/dev/null | grep -m1 mCurrentFocus) in
      *DeprecatedAbiDialog*|*DeprecatedTargetSdkVersionDialog*)
        input keyevent KEYCODE_BACK 2>/dev/null; ilog "quick test: closed an Android compatibility popup";;
    esac
    if [ -n "$seen" ]; then
      [ -z "$pp" ] && { sleep 1; crashed && RES=crashed || RES="closed by itself"; break; }
      n=$((n+1)); [ $n -ge $TEST ] && break
    elif [ $i -ge 15 ]; then RES="didn't start"; [ "$(toppkg)" = com.android.permissioncontroller ] && RES="stopped at the permission screen"; break
    fi
  done
  am force-stop "$pkg" >/dev/null 2>&1; sleep 1
  # back to Magisk (launcher intent = its existing task, Action screen and all)
  [ -n "$home" ] && [ "$home" != "$pkg" ] && [ "$(toppkg)" != "$home" ] \
    && monkey -p "$home" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  ilog "quick test: ${RES:-passed} (${n}s running)"
}
testapp() {  # $1 = how it was patched ("" / known / auto): quick test; on a failure try each behavior family, re-test
  permsoff
  wr "" "  " "Quick testing $nm . . ."
  wr "  " "  " "App will open for a $TEST sec test, then close and return here"
  selftest
  if [ -z "$RES" ]; then echo "Quick test: Passed"; ilog "result: Quick test passed"; [ "$1" = auto ] && report; qdone; return; fi
  capture
  if [ -z "$1" ] && [ -n "$behs" ]; then   # behavior families matched by pre-flight: auto-patch, one after another
    k=
    for f in $(echo "$behs" | tr ',' ' '); do
      if [ -z "$k" ]; then wr "" "  " "Quick test: Failed, trying auto-patch . . ."
      else wr "" "  " "Quick test: Failed, trying another auto-patch . . ."; fi
      k=1
      pout=$(sh $MODDIR/patches/apply.sh "$pkg" "$f" tried 2>&1) || { ilog "auto-patch $f: not applied: $(echo "$pout" | tail -1)"; continue; }
      ilog "auto-patch: $(famname "$f") ($f)"
      selftest
      if [ -z "$RES" ]; then
        echo "Quick test: Passed"; wr "  " "  " "Auto-patched: $(famname "$f")"; ilog "result: Quick test passed with auto-patch $(famname "$f")"
        report; qdone; return
      fi
      capture; sh $MODDIR/patches/apply.sh "$pkg" undo >/dev/null 2>&1; ilog "auto-patch removed"
    done
  fi
  echo "Quick test: Failed"; ilog "result: Quick test failed ($RES)"
  QFAIL=1; wr "" "  " "Saving logs to $TLSHOW/install.log"   # F13: same wording as the logs combo; result after ilog_render
  qdone
}
install_cur() {  # wording: "<Doing> . . ." / "Successfully <done>" / "Failed <action>: <reason>"
  dg=
  case $mk in
    🔼) iver; o=update; ed=updated; msg="Updating $nm${IV:+ $IV} to $ver";;
    🔽) o=downgrade; ed=downgraded; dg=-d; msg="Downgrading $nm${IV:+ $IV} to $ver";;   # IV from confirm_down
    ✅) o=reinstall; ed=reinstalled; msg="Reinstalling $nm${ver:+ $ver}";;
    🔀) o=install; ed=replaced; msg="Installing $nm${ver:+ $ver}";;   # after the uninstall
    *)  o=install; ed=installed; msg="Installing $nm${ver:+ $ver}";;
  esac
  case $mk in 🔽|🔀) ;; *) wr "" "  " "$msg . . .";; esac   # confirmed actions: the question was the feedback
  FRESH=; RP=; case $mk in ""|⬛|🔀) FRESH=1;; esac   # nothing of the user's to keep: data cleared after the quick test
  ilog_start "$o"
  cp "$P" $T/i.apk && chmod 0644 $T/i.apk && chcon u:object_r:shell_data_file:s0 $T/i.apk 2>/dev/null
  # 32-bit APK: install with an explicit ABI (Android then skips its "This is a 32-bit app" popup for it)
  ab=; [ "$tag" = 32 ] && case ",$(field 5)," in *,armeabi-v7a,*) ab="--abi armeabi-v7a";; *,armeabi,*) ab="--abi armeabi";; esac
  out=$(pm install -r $dg $ab --bypass-low-target-sdk-block $T/i.apk 2>&1 | sed "s#$T/i\.apk#${P##*/}#g")   # reasons name the APK, not the temp copy
  case $out in *Success*) ;; *) [ -n "$ab" ] && out=$(pm install -r $dg --bypass-low-target-sdk-block $T/i.apk 2>&1 | sed "s#$T/i\.apk#${P##*/}#g");; esac   # --abi refused: plain install
  case "$out" in
    *Success*) echo "Successfully $ed"; ilog "install: Successfully $ed"
       how=
       if [ -z "$pkg" ]; then :
       elif haspatch; then   # family that lists this app (or applied before)
         pout=$(sh $MODDIR/patches/apply.sh "$pkg" 2>&1) \
           && { how=known; wr "" "  " "Successfully patched: $(echo "$pout" | tail -1 | sed 's/^Patched: //')"; } \
           || wr "" "  " "Failed patch: $(echo "$pout" | tail -1)"
         ilog "patch: $(echo "$pout" | tail -1)"
       elif [ -n "$sym" ]; then   # pre-flight: certain match
         pout=$(sh $MODDIR/patches/apply.sh "$pkg" "$sym" auto 2>&1) \
           && { how=auto; wr "" "  " "Successfully patched: $(echo "$pout" | tail -1 | sed 's/^Patched: //') (matched)"; } \
           || wr "" "  " "Failed patch: $(echo "$pout" | tail -1)"
         ilog "patch (pre-flight match $sym): $(echo "$pout" | tail -1)"
       fi
       [ -n "$pkg" ] && { echo; testapp "$how"; };;
    *) # reason: [INSTALL_…] from "Failure [...]", else the first "…Exception: msg" / "Error: msg" line of a
       #   Java stack trace, else the first line that isn't a stack frame ("at …", "... 12 more")
       why=$(echo "$out" | grep -oE '\[[^]]*\]' | tail -1 | tr -d '[]')
       [ -n "$why" ] || why=$(echo "$out" | grep -m1 -E 'Exception: |Error: ' | sed -E 's/^.*Exception: //; s/^Error: //')
       [ -n "$why" ] || why=$(echo "$out" | grep -vE '^[[:space:]]*($|at |\.\.\. [0-9]+ more)' | head -1)
       why=$(echo "$why" | cut -c1-160)
       case "$why$out" in
         *UPDATE_INCOMPATIBLE*|*INCONSISTENT_CERTIFICATES*) echo "Failed $o: mismatched signatures";;
         *VERSION_DOWNGRADE*) echo "Failed $o: Android refused the older version";;
         *) wr "" "  " "Failed $o: ${why:-unknown error}";;
       esac
       ilog "result: Failed $o: ${why:-unknown error}" "-- pm output:" "$(echo "$out" | head -20 | cut -c1-300)";;
  esac
  rm -f $T/i.apk
  if ilog_render; then [ -n "$QFAIL" ] && echo "Successfully saved logs"
  else [ -n "$QFAIL" ] && echo "Failed save: can't write $TLSHOW"; fi
  QFAIL=
  echo
  # refresh marks; stay on the same APK if it is still listed, else on the next one
  refresh; mklist
  k=$(awk -F'\t' -v p="$P" '$1==p{print NR; exit}' $T/cur_list)
  if [ -n "$k" ]; then IDX=$k; elif [ $IDX -gt $N ]; then IDX=1; fi
}

# --- menu ------------------------------------------------------------------------------------------
IDX=1
show
while nextkey; do
  if [ $KEY = 0 ]; then    # Vol+ and Vol- held together 5 s: save logs, then the same entry again
    save_logs; drain; show again
  elif [ $HOLD = 1 ]; then   # hold Vol+ or Vol-: install
    [ $N = 0 ] && continue
    if [ "$mk" = "🔽" ] && ! confirm_down; then echo "Canceled"; echo; drain; show; continue; fi
    if [ "$mk" = "🔀" ]; then
      confirm_swap || { echo "Canceled"; echo; drain; show; continue; }
      uo=$(pm uninstall "$pkg" 2>&1)
      case "$uo" in *Success*) ;; *) wr "" "  " "Failed uninstall: $(echo "$uo" | tail -1)"; echo; drain; show; continue;; esac
    fi
    install_cur; drain; show   # presses made during the install are dropped (state kept)
  elif [ $N = 0 ]; then continue
  elif [ $KEY = 115 ]; then IDX=$((IDX - 1)); [ $IDX -lt 1 ] && IDX=$N; show
  else IDX=$((IDX + 1)); [ $IDX -gt $N ] && IDX=1; show
  fi
done
echo "Timed out • $BACK"
