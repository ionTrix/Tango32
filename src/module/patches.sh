#!/system/bin/sh
# Tango32 online app patches (v1.1, 2026-11-14 23:40 ET)
# New app patches are published on GitHub (Release "patches", built + signed by CI), so a new game fix needs no
#   new module. The phone fetches the signed index, checks the signature + each file's SHA-256 (apkinfo.jar
#   com.tango32.Patches), keeps only patches for apps that are installed, and applies new ones (patches/apply.sh).
#   Nothing about the phone or its apps is sent: plain downloads of public files, filtering happens here.
#   su -c sh /data/adb/modules/tango32/patches.sh          status: on/off, last check, online patches on this phone
#   su -c sh /data/adb/modules/tango32/patches.sh on|off   turn the check on/off (Action asks once)
#   su -c sh /data/adb/modules/tango32/patches.sh check    check now (even when off) and apply new patches
#   patches.sh check action   Action (short time limit)      patches.sh check boot   service.sh (one log line)
#   Exit codes (check): 0 ok, 1 couldn't check, 2 couldn't check: no network (service.sh retries later)
MODDIR=${0%/*}
. $MODDIR/tango32_dir.sh
OD=$TDATA/patches
VC=$(sed -n 's/^versionCode=//p' $MODDIR/module.prop)
J() { CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin "$@"; }
# installed apps = /data/app folder names (no pm: works from Termux su too). Layouts: /data/app/~~<rnd>/<pkg>-<rnd>/
#   and the older /data/app/<pkg>-<n>/. Package names can't contain "-".
installed() { for d in /data/app/*/*/ /data/app/*/; do n=${d%/}; n=${n##*/}
    case $n in "~~"*) ;; *-*) echo "${n%%-*}";; esac; done 2>/dev/null | sort -u; }
label() { b=$(ls /data/app/*/"$1"-*/base.apk /data/app/"$1"-*/base.apk 2>/dev/null | head -1)
  [ -n "$b" ] && echo "$b" | J com.tango32.ApkInfo 2>/dev/null | cut -f4; }

check() {  # $1 = action | boot | "" (manual)
  case $1 in action) dl=12;; boot) dl=120;; *) dl=60;; esac
  R=/data/local/tmp/tango32_patches.$$
  installed | J com.tango32.Patches fetch "$OD" "${VC:-0}" "$(sget last_seq)" "$MODDIR/patches" $dl > $R 2>/dev/null
  TAB=$(printf '\t'); res=$(grep -E "^(OK|ERR)$TAB" $R | tail -1); why=${res#ERR$TAB}
  [ -n "$res" ] || { res="ERR${TAB}x"; why="helper failed"; }
  case $res in OK*) sset last_seq "${res#OK$TAB}"; sset last_check "$(date +%s)";; esac
  new=; nn=0; msgs=
  while IFS="$TAB" read -r k pkg name rev w; do
    case $k in
      NEW) nn=$((nn+1)); lb=$(label "$pkg")
           o=$(sh $MODDIR/patches/apply.sh "$pkg" 2>&1); r=$?
           case $r in 0) st=patched;; 3) st="app not installed";; *) st="not applied: $(echo "$o" | tail -1)";; esac
           new="$new${new:+, }$name${lb:+ ($lb)} · $st"
           msgs="$msgs
New patch: $name${lb:+ ($lb)}"
           [ $r = 0 ] || msgs="$msgs
Failed patch: $(echo "$o" | tail -1)";;
      SKIP) case $w in *newer*) msgs="$msgs
Patch $name needs a newer Tango32";; *) msgs="$msgs
Couldn't get patch $name: $w";; esac;;
    esac
  done < $R
  rm -f $R
  if [ "$1" = boot ]; then
    case $res in
      OK*) echo "-- online patches: checked $(date '+%m-%d %H:%M'), $nn new${new:+ ($new)}";;
      *)   echo "-- online patches: couldn't check: $why";;
    esac
  else
    case $res in
      OK*) if [ -n "$msgs" ]; then printf '%s\n' "$msgs" | sed '1d'; else echo "App patches up to date"; fi;;
      *)   echo "Couldn't check for patches: $why";;
    esac
  fi
  case $res in OK*) return 0;; esac
  case $why in "no network"|"timed out") return 2;; esac
  return 1
}

case "$1" in
  on)  sset online_patches 1 && echo "Online app patches: on";;
  off) sset online_patches 0 && echo "Online app patches: off";;
  check) check "$2"; exit $?;;
  "")
    case $(sget online_patches) in 1) s=on;; 0) s=off;; *) s="not set (Action asks)";; esac
    echo "Online app patches: $s"
    lc=$(sget last_check)
    [ -n "$lc" ] && echo "Last check: $(date -d "@$lc" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$lc") · index $(sget last_seq)"
    J com.tango32.Patches info 2>/dev/null | { IFS="$(printf '\t')" read -r u k; [ -n "$u" ] && echo "Source: $u (key $k)"; }
    n=0; for f in "$OD"/*/patch.prop; do [ -f "$f" ] || continue; d=${f%/patch.prop}; n=$((n+1))
      echo "  $(sed -n 's/^name=//p' "$f") · ${d##*/} · rev $(sed -n 's/^rev=//p' "$f")"; done
    [ $n = 0 ] && echo "  No online patches downloaded";;
  *) echo "Usage: patches.sh [on|off|check]"; exit 1;;
esac
