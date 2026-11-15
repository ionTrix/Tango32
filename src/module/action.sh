#!/system/bin/sh
# Tango32 action (v1.1, 2026-11-14 23:40 ET): opens straight on the install list.
#   v1.1: unreadable APKs show [?] + a hint (were [64bit]); failed installs show the real reason (not a stack-trace line).
#   v1.1: online app patches (patches.sh): first open asks once whether to check GitHub for new app patches
#   (hold Vol+ Yes / Vol− No, saved in /data/adb/tango32/settings); when on, every open checks (~10 s max)
#   and applies new patches for installed apps before the list.
#   Hold Vol+ and Vol- together 5 s: save bug report logs (logs.sh: crash lines, recent + Tango-related logcat) from anywhere, then back
#   to the same entry. After installing an app that has a Tango32 patch (patches/<pkg>/), the patch is
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
  Z=$TSHOW/tango32_logs.zip
  wr "" "  " "Saving logs to $Z . . ."; echo
  wr "  " "  " "Attach logs along with your GitHub issue."   # shown first: read while logcat is collected
  wr "  " "  " "Logs may contain personal data, review first."; echo
  if sh $MODDIR/logs.sh >/dev/null 2>&1; then echo "Successfully saved logs"
  else echo "Failed save: can't write $TSHOW"; fi
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

# --- online app patches: ask once, then check on every open (patches.sh: signed index from GitHub) ---
if [ -z "$(sget online_patches)" ]; then
  if ask "Check GitHub for new app patches?" \
    "Fixes for your installed apps can arrive without a module update. Nothing about you or your apps is sent. Change it later: see README (Online app patches)."
  then sh $MODDIR/patches.sh on; else sh $MODDIR/patches.sh off; fi; echo; drain
fi
if [ "$(sget online_patches)" = 1 ]; then
  echo "Checking for app patches . . ."
  sh $MODDIR/patches.sh check action 2>/dev/null | while IFS= read -r l; do wr "" "  " "$l"; done; echo
fi

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
# alphabetical by app name (file name if no label), 0-9 then a-z, case-insensitive
awk -F'\t' '{n=$4; if (n=="") {n=$1; sub(/.*\//,"",n)} print tolower(n) "\t" $0}' $T/list | sort -t "$TAB" -k1,1 | cut -f2- > $T/list.s && mv $T/list.s $T/list

# all: path pkg ver label abis vcode tag mark tsdk  (tag 32 = 32-bit only; 64 = arm64 or no native code; ? = APK unreadable)
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
    { a = "," $5 ","; tag = ($5 == "?") ? "?" : ((a ~ /,arm64-v8a,/) ? 64 : ((a ~ /,armeabi/) ? 32 : 64)); m = ""
      if ($2 != "" && ($2 in seen)) { m = "✅"
        if ($6 != "" && v[$2] != "") { if ($6 + 0 > v[$2] + 0) m = "🔼"; else if ($6 + 0 < v[$2] + 0) m = "🔽" }
        if ($8 != "" && sg[$2] != "" && $8 != sg[$2]) m = "🔀" }
      print $1, $2, $3, $4, $5, $6, tag, m, $7 }' $T/pkgs $T/isig $T/list > $T/all
}
# only APKs Android won't install normally (unknown targetSdk = listed, to be safe).
#   Android 14 (SDK 34) refuses targetSdk < 23; Android 15+ (SDK 35+) refuses < 24.
mklist() { awk -F'\t' -v c=$CUT '$9=="" || $9+0 < c' $T/all > $T/cur_list; N=$(wc -l < $T/cur_list); }
refresh; mklist
count; [ $N = 0 ] && none

haspatch() { [ -f "$MODDIR/patches/$pkg/patch.prop" ] || [ -f "$TDATA/patches/$pkg/patch.prop" ]; }   # cheap pre-check
field() { awk -F'\t' -v f=$1 '{print $f}' $T/cur; }
show() {
  if [ $N = 0 ]; then [ "$1" = again ] && none; return; fi
  sed -n "${IDX}p" $T/cur_list > $T/cur
  P=$(field 1); pkg=$(field 2); ver=$(field 3); lab=$(field 4); tag=$(field 7); mk=$(field 8)
  nm=${lab:-${P##*/}}
  case $ver in ""|[vV]*) ;; *) ver=v$ver;; esac   # "1.3" -> "v1.3"
  pt=; [ -n "$mk" ] && haspatch && sh $MODDIR/patches/apply.sh "$pkg" check >/dev/null 2>&1 && pt="+🩹"   # installed and patched: ✅+🩹
  tg="[${tag}bit]"; [ "$tag" = "?" ] && tg="[?]"
  wr "  " "    " "$IDX/$N ${mk:-⬛}$pt $nm${ver:+ $ver}$SP$tg"   # ⬛ = available (not installed; keeps names aligned)
  wr "  " "    " "${P#$SD/}"   # Tango32/... (no sdcard/: room for the file name)
  [ "$tag" = "?" ] && wr "  " "    " "Can't read damaged or corrupt APK"
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
  cp "$P" $T/i.apk && chmod 0644 $T/i.apk && chcon u:object_r:shell_data_file:s0 $T/i.apk 2>/dev/null
  out=$(pm install -r $dg --bypass-low-target-sdk-block $T/i.apk 2>&1)
  case "$out" in
    *Success*) echo "Successfully $ed"
       if [ -n "$pkg" ] && haspatch; then   # app patch (bundled or online)
         pout=$(sh $MODDIR/patches/apply.sh "$pkg" 2>&1) \
           && wr "" "  " "Successfully patched: $(echo "$pout" | tail -1 | sed 's/^Patched: //')" \
           || wr "" "  " "Failed patch: $(echo "$pout" | tail -1)"
       fi;;
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
       esac;;
  esac
  rm -f $T/i.apk
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
