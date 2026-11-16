#!/system/bin/sh
# Tango32 online app patches (v1.1, 2026-11-15 ET)
# New app patch families are published on GitHub (Release "patches", built + signed by CI), so a new game fix needs
#   no new module. The phone fetches the signed index, checks the signature + each file's SHA-256 (apkinfo.jar
#   com.tango32.Patches), keeps every family (Action's pre-flight check matches them to APKs), and re-applies a
#   newer copy to apps that already use that family (patches/apply.sh).
#   Nothing about the phone or its apps is sent: plain downloads of public files, matching happens here.
#   Checks run only when you say Yes in Action (asked every time it opens) or by hand; never at boot.
#   su -c sh /data/adb/modules/tango32/patches.sh          status: last check, source, downloaded families
#   su -c sh /data/adb/modules/tango32/patches.sh check    check now and apply new patches
#   patches.sh check action   Action (short time limit)
#   Exit codes (check): 0 ok, 1 couldn't check, 2 couldn't check: no network
MODDIR=${0%/*}
. $MODDIR/tango32_dir.sh
OD=$TDATA/patches
VC=$(sed -n 's/^versionCode=//p' $MODDIR/module.prop)
J() { CLASSPATH=$MODDIR/apkinfo.jar /system/bin/app_process /system/bin "$@"; }
# apps that use family $1: a record in /data/adb/tango32/applied, or listed in its pkgs= (bundled or online copy)
users() { { grep -l "^id=$1\$" $TDATA/applied/* 2>/dev/null | sed 's#.*/##'
  sed -n 's/^pkgs=//p' "$MODDIR/patches/$1/patch.prop" "$OD/$1/patch.prop" 2>/dev/null | tr ',' '\n'; } | grep -E '^[A-Za-z]' | sort -u; }
label() { b=$(ls /data/app/*/"$1"-*/base.apk /data/app/"$1"-*/base.apk 2>/dev/null | head -1)
  [ -n "$b" ] && echo "$b" | J com.tango32.ApkInfo 2>/dev/null | cut -f4; }

check() {  # $1 = action | "" (manual)
  case $1 in action) dl=12;; *) dl=60;; esac
  R=/data/local/tmp/tango32_patches.$$
  J com.tango32.Patches fetch "$OD" "${VC:-0}" "$(sget last_seq)" "$MODDIR/patches" $dl < /dev/null > $R 2>/dev/null
  TAB=$(printf '\t'); res=$(grep -E "^(OK|ERR)$TAB" $R | tail -1); why=${res#ERR$TAB}
  [ -n "$res" ] || { res="ERR${TAB}x"; why="helper failed"; }
  case $res in OK*) sset last_seq "${res#OK$TAB}"; sset last_check "$(date +%s)";; esac
  msgs=
  while IFS="$TAB" read -r k fid name rev w; do
    case $k in
      NEW) msgs="$msgs
New patch: $name"
           # apps already on this family (record or pkgs=): bring them to the new copy
           for pkg in $(users "$fid"); do
             o=$(sh $MODDIR/patches/apply.sh "$pkg" 2>&1); r=$?; lb=$(label "$pkg")
             case $r in
               0) msgs="$msgs
Successfully patched: ${lb:-$pkg}";;
               3) ;;   # not installed
               *) msgs="$msgs
Failed patch: ${lb:-$pkg}: $(echo "$o" | tail -1)";;
             esac
           done;;
      SKIP) case $w in *newer*) msgs="$msgs
Patch $name needs a newer Tango32";; *) msgs="$msgs
Couldn't get patch $name: $w";; esac;;
    esac
  done < $R
  rm -f $R
  case $res in
    OK*) if [ -n "$msgs" ]; then printf '%s\n' "$msgs" | sed '1d'; else echo "App patches up to date"; fi;;
    *)   echo "Couldn't check for patches: $why";;
  esac
  case $res in OK*) return 0;; esac
  case $why in "no network"|"timed out") return 2;; esac
  return 1
}

case "$1" in
  check) check "$2"; exit $?;;
  "")
    lc=$(sget last_check)
    if [ -z "$lc" ]; then echo "Last check: never (Action asks every time it opens)"; else echo "Last check: $(date -d "@$lc" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$lc") · index $(sget last_seq)"; fi
    J com.tango32.Patches info 2>/dev/null | { IFS="$(printf '\t')" read -r u k; [ -n "$u" ] && echo "Source: $u (key $k)"; }
    n=0; for f in "$OD"/*/patch.prop; do [ -f "$f" ] || continue; d=${f%/patch.prop}; n=$((n+1))
      echo "  $(sed -n 's/^name=//p' "$f") · ${d##*/} · rev $(sed -n 's/^rev=//p' "$f")"; done
    [ $n = 0 ] && echo "  No online patches downloaded";;
  *) echo "Usage: patches.sh [check]"; exit 1;;
esac
