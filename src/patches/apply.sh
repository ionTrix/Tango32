#!/system/bin/sh
# Tango32 app patches (v1.1, 2026-11-15 ET). One folder per patch family: patches/<id>/patch.prop + wrapper .so.
#   Online families (patches.sh) live in /data/adb/tango32/patches/<id>/; per family the copy with the higher rev=
#   wins (a tie keeps the bundled one). Which family an app gets: its record in /data/adb/tango32/applied/<package>
#   (written when a family is applied: id, lib, how = known | auto (pre-flight match) | tried (Action's try fix)),
#   else the family whose pkgs= lists the package.
#   su -c sh /data/adb/modules/tango32/patches/apply.sh                  list installed apps with a patch + state
#   su -c sh /data/adb/modules/tango32/patches/apply.sh <package>        apply (again after an app update)
#   su -c sh /data/adb/modules/tango32/patches/apply.sh <package> undo   remove
#   apply.sh boot   (service.sh) re-apply any patch an app update removed; one line per installed app (boot log)
#   apply.sh <package> check   exit 0 if patched (Action's 🩹 mark)     apply.sh <package> has   family id + name, exit 0 if one is known
#   apply.sh <package> <id> auto|tried   apply family <id> to an app it isn't listed for (Action)
#   Exit codes: 0 ok / patched, 1 error, 2 no patch for that package, 3 app not installed, 4 not patched (check)
# Works from Termux su (no pm/am: the app folder is found under /data/app, the app is stopped with kill).
PD=${0%/*}; TD=/data/adb/tango32; OD=$TD/patches; AP=$TD/applied; BK=/data/local/tmp/tango32_patch_backup
rev() { r=$(sed -n 's/^rev=//p' "$1/patch.prop" 2>/dev/null | head -1); case $r in ""|*[!0-9]*) echo 0;; *) echo $r;; esac; }
okid() { case $1 in ""|*[!a-z0-9-]*) return 1;; esac; }
pick() {  # FID -> DIR: the copy with the higher rev ("" = no such family)
  DIR=; okid "$FID" || return; [ -f "$PD/$FID/patch.prop" ] && DIR=$PD/$FID
  if [ -f "$OD/$FID/patch.prop" ] && { [ -z "$DIR" ] || [ "$(rev "$OD/$FID")" -gt "$(rev "$DIR")" ]; }; then DIR=$OD/$FID; fi
}
ids() { for f in "$PD"/*/patch.prop "$OD"/*/patch.prop; do [ -f "$f" ] && { p=${f%/patch.prop}; echo "${p##*/}"; }; done | sort -u; }
rec() { sed -n "s/^$1=//p" "$AP/$PKG" 2>/dev/null | head -1; }   # this app's record
famfor() {  # PKG -> FID ("" = none): its record, else a family that lists it in pkgs=
  FID=$(rec id); pick; [ -n "$DIR" ] && return 0
  for FID in $(ids); do pick
    case ",$(sed -n 's/^pkgs=//p' "$DIR/patch.prop" | head -1)," in *",$PKG,"*) return 0;; esac
  done; FID=; DIR=; return 1
}
pkgs() {  # every package with a record or listed in some family's pkgs=
  { ls "$AP" 2>/dev/null
    for FID in $(ids); do pick; sed -n 's/^pkgs=//p' "$DIR/patch.prop" | head -1 | tr ',' '\n'; done; } | grep -E '^[A-Za-z]' | sort -u
}
prop() { sed -n "s/^$1=//p" "$DIR/patch.prop" | head -1; }
load() {  # PKG [FID] -> DIR NAME LIB NEED WRAP REV L (app lib dir) M (app lib file)
  if [ -n "$1" ]; then FID=$1; pick; else famfor; fi
  [ -n "$DIR" ] || return 2
  NAME=$(prop name); LIB=$(prop lib); NEED=$(prop needed); WRAP=$(prop wrapper); REV=$(rev "$DIR")
  L=$(ls -d /data/app/*/$PKG-*/lib/arm /data/app/$PKG-*/lib/arm 2>/dev/null | head -1)
  [ -n "$L" ] || return 3
  if [ "$LIB" = "*" ]; then   # any lib that needs $NEED: the one recorded, else the first that has the name
    LIB=$(rec lib); [ "$(rec id)" = "$FID" ] && [ -f "$L/$LIB" ] || LIB=
    [ -n "$LIB" ] || for f in "$L"/*.so; do M=$f; [ "${f##*/}" != "$WRAP" ] && { has "$NEED" || has "$WRAP"; } && { LIB=${f##*/}; break; }; done
  fi
  M=$L/$LIB; [ -n "$LIB" ] && [ -f "$M" ] || return 3
}
at() { dd if="$M" bs=1 skip=$1 count=${#2} 2>/dev/null; }   # the ${#2} bytes at offset $1
off() {  # byte offset of $1 in $M (Android's toybox grep; busybox grep has no -b), checked by reading it back
  for g in "/system/bin/toybox grep" "/system/bin/grep"; do
    o=$($g -obaF "$1" "$M" 2>/dev/null | head -1 | cut -d: -f1)
    [ -n "$o" ] && [ "$(at $o "$1")" = "$1" ] && { echo $o; return; }
  done
}
has() { [ -n "$(off "$1")" ]; }   # string present (checked read-back)
stop_app() { for p in $(pidof $PKG 2>/dev/null); do kill $p 2>/dev/null; done; }
src() {  # list/boot lines: where the patch came from, how it was matched
  [ "$DIR" = "$OD/$FID" ] && printf ' · online rev %s' "$REV"
  case $(rec how) in auto) printf ' · matched';; tried) printf ' · tried';; esac; }
state() {  # -> patched / outdated (older copy of the wrapper in the app) / not patched / not patchable
  if [ -f "$L/$WRAP" ] && has "$WRAP"; then cmp -s "$DIR/$WRAP" "$L/$WRAP" && echo patched || echo outdated
  elif has "$NEED"; then echo "not patched"; else echo "not patchable (unknown $LIB)"; fi
}
apply() {
  [ ${#NEED} = ${#WRAP} ] || { echo "Bad patch.prop: needed/wrapper lengths differ"; return 1; }
  [ -f "$DIR/$WRAP" ] || { echo "Missing $WRAP in $DIR"; return 1; }
  stop_app
  if ! has "$WRAP"; then
    o=$(off "$NEED")
    mkdir -p $BK && cp "$M" "$BK/$PKG.$LIB"
    if [ -n "$o" ]; then
      printf %s "$WRAP" | dd of="$M" bs=1 seek=$o conv=notrunc 2>/dev/null
    elif has "$NEED"; then   # fallback: Magisk's own byte patcher
      /data/adb/magisk/magiskboot hexpatch "$M" $(printf %s "$NEED" | od -An -tx1 | tr -d ' \n') \
        $(printf %s "$WRAP" | od -An -tx1 | tr -d ' \n') >/dev/null 2>&1
    else echo "$LIB has no $NEED: unknown app version, nothing changed"; return 1; fi
    has "$WRAP" || { cat "$BK/$PKG.$LIB" > "$M"; echo "Patch check failed: $LIB restored"; return 1; }
  fi
  cp "$DIR/$WRAP" "$L/$WRAP" && chown $(/system/bin/stat -c %u:%g "$M") "$L/$WRAP" \
    && chmod $(/system/bin/stat -c %a "$M") "$L/$WRAP" && chcon $(/system/bin/stat -c %C "$M") "$L/$WRAP" \
    || { echo "Could not copy $WRAP into the app"; return 1; }
  h=$HOW; [ -n "$h" ] || { [ "$(rec id)" = "$FID" ] && h=$(rec how); }
  mkdir -p "$AP" && printf 'id=%s\nlib=%s\nhow=%s\n' "$FID" "$LIB" "${h:-known}" > "$AP/$PKG"
  echo "Patched: $NAME"
}
undo() {
  stop_app
  if has "$WRAP" && [ -f "$BK/$PKG.$LIB" ]; then cat "$BK/$PKG.$LIB" > "$M"
  elif has "$WRAP"; then o=$(off "$WRAP"); [ -n "$o" ] && printf %s "$NEED" | dd of="$M" bs=1 seek=$o conv=notrunc 2>/dev/null; fi
  rm -f "$L/$WRAP" "$AP/$PKG"; echo "Removed: $NAME"
}

case "$1" in
  "")  n=0; for PKG in $(pkgs); do
         load; r=$?; NAME=${NAME:-$PKG}
         [ $r = 0 ] && { echo "$NAME · $PKG · $(state)$(src)"; n=$((n+1)); }   # apps not installed: skipped
       done; [ $n = 0 ] && echo "None installed"; exit 0;;
  boot) n=0; for PKG in $(pkgs); do
          load || continue; n=$((n+1)); st=$(state)
          case $st in
            "not patched")   # an app update replaced the patched lib
              o=$(apply 2>&1) && st="re-applied (app was updated)" || st="re-apply failed: $(echo "$o" | tail -1)";;
            outdated)        # a newer copy of the patch arrived (online) since it was applied
              o=$(apply 2>&1) && st="updated" || st="update failed: $(echo "$o" | tail -1)";;
          esac
          echo "$NAME · $PKG · $st$(src)"
        done; [ $n = 0 ] && echo "None installed"; exit 0;;
esac
PKG=$1; HOW=
case $PKG in ""|*[!A-Za-z0-9_.]*) echo "Bad package name"; exit 1;; esac
if [ "$2" = has ]; then famfor || exit 2; printf '%s\t%s\n' "$FID" "$(prop name)"; exit 0; fi   # id + name
case $3 in auto|tried) okid "$2" && HOW=$3 || { echo "Bad family id"; exit 1; }; load "$2";; *) load;; esac; r=$?
[ $r = 2 ] && { echo "No patch for $PKG"; exit 2; }
[ $r = 3 ] && { echo "$PKG is not installed"; exit 3; }
case "$2" in
  undo)  undo;;
  check) case $(state) in patched|outdated) exit 0;; *) exit 4;; esac;;
  *)     apply || exit 1;;
esac
