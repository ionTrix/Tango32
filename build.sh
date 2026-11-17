#!/usr/bin/env bash
# build.sh — build the Tango32 Magisk module from the src/ tree
# Updated: 2026-11-14 23:40 ET (v1.1: online app patches — build_patches.sh, Patches in apkinfo.jar, patches.sh)
# Source: ColorOS PJD110 16.0.3.500 (CN01) from github.com/spike0en/oneplus_archive (SHA-256 verified)
# Needs:  fw.zip or fw/ next to this script, made by pull_fw.sh from YOUR phone (US boot framework jars,
#         bcp.txt, build.txt). Used for the framework shim, the prune scan and the install guard.
# Run:    bash build.sh        (Linux/WSL2 x86-64, root, ~25 GB free disk transiently)
#         ALLOW_UNTESTED=1 bash build.sh   build for a firmware other than 16.0.10.601 (unverified)
# Output: /root/re-work/module/tango32-<ver>.zip
#
# Contents
#   [0] Your phone's firmware (fw) + build guard
#   [1] Tools
#   [2] Download + verify CN firmware
#   [3] Extract partitions + APEXes
#   [3b] Framework shim (tango-shim.jar)        src/shim/shim_edit.py
#   [3c] TangoFdFix shim class                  src/shim/TangoFdFix.java, src/shim/stubs/
#   [3d] libtango_gui.so parcel bridge          src/bridge/
#   [3d2] App patches                          tools/build_patches.sh, src/patches/
#   [3e] apkinfo.jar action helper + Patches    src/apkinfo/
#   [4] Assemble module tree
#   [4b] Prune unreachable libs                 src/tools/prune.py
#   [5] SELinux contexts                        src/tools/contexts.py
#   [6] Module scripts                          src/module/
#   [7] ART report + zip                        src/tools/art_report.py
set -euo pipefail
VER=${VER:-v1.0}
_v=${VER#v}; VC=$(( ${_v%%.*} * 100 + ${_v#*.} ))   # versionCode = major*100 + minor (v1.0 = 100, v1.10 = 110, v2.0 = 200)
HERE=$(cd "$(dirname "$0")" && pwd); SRC=$HERE/src
W=/root/re-work/cnfw; FS=$W/fs; AP=$W/apex; MODROOT=/root/re-work/module; MOD=$MODROOT/tango32
USFW=/root/re-work/usfw/fw; O=/root/re-work/v1.0; SH=/root/re-work/shim; SM3=/root/re-work/tools/smali3; R8=/root/re-work/tools/r8.jar
F='PJD110_16.0.3.500-CN01_CN'   # CN firmware file prefix; sources in [2] + src/cn/mirrors.txt
IMGS="system system_ext vendor product"
# APEXes copied whole (minus lib64/apps; lib/ too except adbd) for the private namespace; ns_apex.list picks which are used
NS_ALL="com.android.art com.android.i18n com.android.conscrypt com.android.adbd com.android.os.statsd com.android.media com.android.tethering com.android.mediaprovider com.android.neuralnetworks"
NS_DEFAULT="com.android.art com.android.i18n com.android.conscrypt com.android.adbd"

### [0] Your phone's firmware: fw.zip or fw/ (pull_fw.sh) -> $USFW, then the build guard (fails fast, before the download)
TESTED=16.0.10.601
MODELS="CPH2583 CPH2581"   # CPH2583 = NA (ionTrix's phone); CPH2581 = Global, community-tested on 16.0.10.601(EX01)
rm -rf "$USFW"; mkdir -p "$(dirname "$USFW")"
if [ -f "$HERE/fw.zip" ]; then unzip -oq "$HERE/fw.zip" -d "$(dirname "$USFW")"   # fw.zip holds fw/<jars>
elif [ -f "$HERE/fw/framework.jar" ]; then cp -r "$HERE/fw" "$USFW"
else echo "FATAL: no fw.zip or fw/ next to build.sh. Run pull_fw.sh (Termux on the phone, or adb) first."; exit 1; fi
[ -f $USFW/framework.jar ] && [ -f $USFW/oplus-framework.jar ] || { echo "FATAL: framework jars missing in fw (re-run pull_fw.sh)"; exit 1; }
[ -f $USFW/build.txt ] || { echo "FATAL: fw has no build.txt (old fw.zip?). Re-run pull_fw.sh."; exit 1; }
bget() { sed -n "s/^$1=//p" $USFW/build.txt | head -1; }
case " $MODELS " in *" $(bget model) "*) ;; *) echo "FATAL: fw is from '$(bget model)'. Tango32 supports the OnePlus 12 CPH2583 (NA) and CPH2581 only."; exit 1;; esac
[ -n "$(bget fingerprint)" ] || { echo "FATAL: build.txt has no fingerprint. Re-run pull_fw.sh."; exit 1; }
case "$(bget display)" in
  *"$TESTED"*) echo "fw: $(bget display) (tested)";;
  *) if [ "${ALLOW_UNTESTED:-0}" = 1 ]; then echo "WARN: fw $(bget display) is untested (shim/bridge verified on $TESTED only)"
     else echo "FATAL: fw is $(bget display); Tango32 is verified on $TESTED only. The framework shim and parcel bridge"
          echo "       may not match other builds. ALLOW_UNTESTED=1 bash build.sh to try anyway."; exit 1; fi;;
esac

### [1] Tools
# Testing shortcut: tango32_cn_cache.zip next to build.sh (private; only the CN files the build reads + Maven tools)
# skips the ~7.7 GB download. Make one with tools/make_cn_cache.sh after a full build.
if [ -f "$HERE/tango32_cn_cache.zip" ] && [ ! -d $FS/system ]; then
  echo "CN cache: $HERE/tango32_cn_cache.zip"; unzip -oq "$HERE/tango32_cn_cache.zip" -d /root/re-work; fi
command -v 7z >/dev/null && command -v fsck.erofs >/dev/null && command -v zip >/dev/null && command -v javac >/dev/null \
  && command -v clang >/dev/null && command -v ld.lld >/dev/null || { apt-get update -qq; apt-get install -y -qq p7zip-full erofs-utils zip unzip default-jdk-headless clang lld; }
mkdir -p $SM3
# fetch with retries (repo1.maven.org rate-limits with HTTP 429)
fetch() { local t; for t in 1 2 3 4 5 6; do curl -sSf -o "$1" "$2" && return 0; rm -f "$1"; sleep $((t*5)); done; echo "FATAL: fetch $2"; exit 1; }
G=https://dl.google.com/dl/android/maven2/com/android/tools; M=https://repo1.maven.org/maven2
for a in smali smali-baksmali smali-dexlib2 smali-util; do [ -s $SM3/$a.jar ] || fetch $SM3/$a.jar $G/smali/$a/3.0.9/$a-3.0.9.jar; done
for p in com/beust/jcommander/1.64/jcommander-1.64 com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2 \
         com/google/guava/guava/31.1-android/guava-31.1-android com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1 \
         org/antlr/antlr/3.5.2/antlr-3.5.2 org/antlr/antlr-runtime/3.5.2/antlr-runtime-3.5.2 \
         org/antlr/stringtemplate/3.2.1/stringtemplate-3.2.1 antlr/antlr/2.7.7/antlr-2.7.7; do
  [ -s $SM3/$(basename $p).jar ] || fetch $SM3/$(basename $p).jar $M/$p.jar; done
[ -s $R8 ] || fetch $R8 $G/r8/8.5.35/r8-8.5.35.jar   # d8 for the TangoFdFix class
SCP=$(ls $SM3/*.jar | tr '\n' :)

### [2] Get + verify CN firmware (images deleted after extraction to save disk)
# Sources, in order: CN_LOCAL (your own copy), CN_MIRROR, then every URL in src/cn/mirrors.txt.
#   CN_LOCAL=/path/folder   holds system.img system_ext.img vendor.img product.img, or the 4 parts
#                           PJD110_16.0.3.500-CN01_CN-image-logical.7z.001 … .004
#   CN_LOCAL=/path/<…>.7z.001 (the other parts next to it)
#   CN_MIRROR=https://…     a folder URL serving the same 4 .7z parts
# Whatever the source, every image must match the SHA-256 pinned in src/cn/cn.sha256, so any copy is safe to use.
mkdir -p $W/dl $W/img
cp "$SRC/cn/cn.sha256" $W/hash.sha256
need() { for i in $IMGS; do [ -d $FS/$i ] || [ -f $W/img/$i.img ] || return 0; done; return 1; }
unpack() {  # $1 = first .7z part
  (cd $W/img && 7z e -y "$1" $(for i in $IMGS; do [ -d $FS/$i ] || printf '%s.img ' $i; done) >/dev/null) || return 1; }
cn_fail() {
  echo "FATAL: could not get the CN firmware images."
  echo "  Needed: PJD110 (OnePlus 12 China) ColorOS 16.0.3.500 (CN01), logical images (4 parts):"
  echo "    $F-image-logical.7z.001 … .004"
  echo "  Must match (src/cn/cn.sha256):"; sed -n 's/^\([0-9a-f]\{64\}\) \*\(.*\)/    \2  \1/p' "$SRC/cn/cn.sha256"
  echo "  Get the parts (or the 4 .img files) from any source, then: CN_LOCAL=/path/to/them bash build.sh"
  exit 1; }
if need && [ -n "${CN_LOCAL:-}" ]; then
  echo "CN firmware: local $CN_LOCAL"
  if [ -d "$CN_LOCAL" ] && ls "$CN_LOCAL"/system.img >/dev/null 2>&1; then
    for i in $IMGS; do [ -d $FS/$i ] || cp "$CN_LOCAL/$i.img" $W/img/ || cn_fail; done
  elif [ -d "$CN_LOCAL" ]; then unpack "$CN_LOCAL/$F-image-logical.7z.001" || cn_fail
  else unpack "$CN_LOCAL" || cn_fail; fi
fi
if need; then
  for base in ${CN_MIRROR:-} $(grep -v '^#' "$SRC/cn/mirrors.txt" | sed '/^$/d'); do
    echo "CN firmware: downloading from $base"
    for p in 001 002 003 004; do curl -sSL --fail --retry 5 -C - -o "$W/dl/$F-image-logical.7z.$p" "$base/$F-image-logical.7z.$p" & done
    ok=1; for j in $(jobs -p); do wait $j || ok=0; done
    if [ $ok = 1 ] && unpack "$W/dl/$F-image-logical.7z.001"; then rm -rf $W/dl; break; fi
    echo "WARN: $base failed, trying the next source"; rm -rf $W/dl; mkdir -p $W/dl
  done
  need && cn_fail
fi
if ls $W/img/*.img >/dev/null 2>&1; then
  (cd $W/img && for i in $IMGS; do [ -f $i.img ] && grep -E "\*$i\.img$" $W/hash.sha256 | sed 's/ \*/  /'; done | sha256sum -c -) \
    || { echo "FATAL: CN image hash mismatch (wrong or damaged firmware). Delete $W/img and retry."; exit 1; }
fi

### [3] Extract partitions + APEXes
for i in $IMGS; do [ -d $FS/$i ] || { mkdir -p $FS/$i; fsck.erofs --extract=$FS/$i --no-preserve $W/img/$i.img >/dev/null; rm -f $W/img/$i.img; }; done
mkdir -p $AP
# system_ext/apex holds com.android.vndk.v34 (32-bit VNDK lib/ needed by vendor EGL/HALs)
# (with the CN cache there are no .apex files: an unmatched glob stays literal -> skip it)
for a in $FS/system/system/apex/*.apex $FS/system_ext/apex/*.apex; do [ -f "$a" ] || continue
  n=$(basename "$a" .apex); d=$AP/$n; [ -d "$d/root" ] && continue
  mkdir -p $d/root; unzip -oq -d $d $a apex_payload.img 2>/dev/null || continue
  fsck.erofs --extract=$d/root --no-preserve $d/apex_payload.img >/dev/null 2>&1 || true; rm -f $d/apex_payload.img; done

### [3b] Framework shim: patched copies of 10 US framework classes, put in front of framework.jar
#     on the 32-bit BOOTCLASSPATH only. Closes the CN-native vs US-Java gaps found by the JNI audit:
#     CN-signature natives added, US-only natives turned into Java, CN-expected callbacks added.
SHIM_CLASSES='Landroid/view/SurfaceControl;,Landroid/hardware/SystemSensorManager$BaseEventQueue;,Landroid/graphics/BaseCanvas;,Landroid/graphics/Bitmap;,Landroid/graphics/HardwareRenderer;,Landroid/graphics/RenderEffect;,Lcom/android/internal/os/ApplicationSharedMemory;,Landroid/view/OplusRenderNodeAnimator;,Lcom/oplus/uifirst/OplusUIFirstManager;,Lcom/android/internal/os/ZygoteInit;'
rm -rf $SH/build && mkdir -p $SH/build/dex $SH/build/sm $SH/build/jar
unzip -oq $USFW/framework.jar 'classes*.dex' -d $SH/build/dex/fw
unzip -oq $USFW/oplus-framework.jar 'classes*.dex' -d $SH/build/dex/ofw
for d in $SH/build/dex/*/classes*.dex; do
  java -cp "$SCP" com.android.tools.smali.baksmali.Main d -a 35 --classes "$SHIM_CLASSES" -o $SH/build/sm $d 2>&1 | grep -v JAVA_TOOL || true; done
[ $(find $SH/build/sm -name '*.smali' | wc -l) = 10 ] || { echo "FATAL: shim classes not all found"; exit 1; }
cp "$SRC/shim/shim_edit.py" $SH/shim_edit.py
python3 -I $SH/shim_edit.py $SH/build/sm

### [3c] TangoFdFix: new class in the shim (compiled against minimal stubs, d8 -> baksmali -> merged)
J=$SH/build/java; rm -rf $J; mkdir -p $J/stub/android/system $J/stub/android/util $J/src/com/android/internal/os $J/cls $J/dex
cp -r "$SRC/shim/stubs/." $J/stub/
# Non-constant fields so javac emits getstatic (real values come from the device's OsConstants)
cp "$SRC/shim/TangoFdFix.java" $J/src/com/android/internal/os/TangoFdFix.java
javac --release 11 -XDstringConcat=inline -cp $J/stub -d $J/cls $J/src/com/android/internal/os/TangoFdFix.java
java -cp $R8 com.android.tools.r8.D8 --release --min-api 29 --output $J/dex $J/cls/com/android/internal/os/TangoFdFix.class
java -cp "$SCP" com.android.tools.smali.baksmali.Main d -a 29 -o $SH/build/sm $J/dex/classes.dex 2>&1 | grep -v JAVA_TOOL || true
[ -f $SH/build/sm/com/android/internal/os/TangoFdFix.smali ] || { echo "FATAL: TangoFdFix not built"; exit 1; }

java -cp "$SCP" com.android.tools.smali.smali.Main a -a 29 -o $SH/build/jar/classes.dex $SH/build/sm 2>&1 | grep -v JAVA_TOOL || true
# Stored + 4-byte aligned (ART mmaps the dex directly instead of extracting it on every zygote start)
rm -f $SH/tango-shim.jar
python3 -I "$SRC/tools/align_jar.py" "$SH/build/jar/classes.dex" "$SH/tango-shim.jar"
echo "shim: $(sha256sum $SH/tango-shim.jar)"

### [3d] libtango_gui.so — parcel bridge (armv7 Thumb, freestanding; stub libc/libdl/liblog for linking only)
rm -rf $O; mkdir -p $O
cp "$SRC/bridge/tango_gui.c" $O/tango_gui.c
cp "$SRC/bridge/stubs.c" $O/stubs.c
CT="--target=armv7a-linux-androideabi -mthumb -fPIC -nostdlib -fuse-ld=lld -ffreestanding"
for s in libc libdl liblog; do clang $CT -shared -Wl,-soname,$s.so -o $O/$s.so $O/stubs.c; done
clang $CT -O2 -shared -fno-stack-protector -fvisibility=hidden -Wl,-soname,libtango_gui.so -Wl,--hash-style=both \
  -Wl,-z,max-page-size=4096 -Wl,--build-id -Wl,--no-as-needed -Wl,-z,defs -L$O -lc -ldl -llog -o $O/libtango_gui.so $O/tango_gui.c
echo "libtango_gui: $(sha256sum $O/libtango_gui.so)"
# [3d2] app patches (src/patches/<family id>/): wrapper libs, same toolchain (tools/build_patches.sh; CI uses it too)
bash "$HERE/tools/build_patches.sh" $O/patches

### [3e] apkinfo.jar — action helper (APK label/version/package/ABIs/versionCode/targetSdk via app_process),
#     logs zip (Zip), online app patches (Patches: signed index from PATCH_URL, checked with the key in PATCH_PUB)
#     and the pre-flight check (Preflight: missing Android functions + patch family matches)
#     PATCH_URL / PATCH_PUB override the release defaults for test builds (own server + throwaway key).
PATCH_URL=${PATCH_URL:-https://github.com/ionTrix/Tango32/releases/download/patches}
PATCH_PUB=${PATCH_PUB:-$SRC/patches/patches_pub.pem}
grep -q -- '-----BEGIN PUBLIC KEY-----' "$PATCH_PUB" 2>/dev/null || { echo "FATAL: no public key at $PATCH_PUB"; exit 1; }
case "$PATCH_URL" in https://*) ;; *) echo "FATAL: PATCH_URL must be https"; exit 1;; esac
mkdir -p $O/aj/src/com/tango32 $O/aj/cls $O/aj/dex
cp "$SRC"/apkinfo/*.java $O/aj/src/com/tango32/
printf 'package com.tango32;\nfinal class PatchConfig {\n    static final String URL = "%s";\n    static final String PUB = "%s";\n}\n' \
  "$PATCH_URL" "$(grep -v -- ----- "$PATCH_PUB" | tr -d '\r\n')" > $O/aj/src/com/tango32/PatchConfig.java
javac --release 11 -XDstringConcat=inline -d $O/aj/cls $O/aj/src/com/tango32/*.java
java -cp $R8 com.android.tools.r8.D8 --release --min-api 26 --output $O/aj/dex $O/aj/cls/com/tango32/*.class
(cd $O/aj/dex && rm -f $O/apkinfo.jar && zip -qX $O/apkinfo.jar classes.dex)
echo "patches: $PATCH_URL (key $(grep -v -- ----- "$PATCH_PUB" | tr -d '\r\n' | base64 -d | sha256sum | cut -c1-16))"

### [3f] touchgrab — blocks touch during the Action quick test (F11; aarch64 static, freestanding, ~2 KB)
clang --target=aarch64-linux-gnu -Os -ffreestanding -fno-stack-protector -fno-builtin -nostdlib -static -fuse-ld=lld \
  -Wl,--build-id=none -Wl,-z,norelro -Wall -Werror -o $O/touchgrab "$SRC/touchgrab/touchgrab.c"
echo "touchgrab: $(sha256sum $O/touchgrab)"

### [4] Assemble module tree
rm -rf $MOD; mkdir -p $MOD
cp_dir() { mkdir -p "$2"; (cd "$1" && tar cf - --exclude=./modules --exclude=./rfsa .) | (cd "$2" && tar xf - ${3:-}); }
cp_dir $FS/system/system/lib $MOD/system/lib
# Magic mount can't create /system_ext/lib (new dir on US ROM): merge it into /system/lib, existing names win
cp_dir $FS/system_ext/lib    $MOD/system/lib --skip-old-files
cp_dir $FS/product/lib       $MOD/system/product/lib
cp_dir $FS/vendor/lib        $MOD/system/vendor/lib
mkdir -p $MOD/system/bin/bootstrap $MOD/system/system_ext/bin
cp -a $FS/system/system/bin/app_process32 $MOD/system/bin/app_process32_tango   # real binary; wrapper goes at app_process32
ln -sf /apex/com.android.runtime/bin/linker $MOD/system/bin/linker
[ -L $FS/system/system/bin/linker_asan ] && ln -sf "$(readlink $FS/system/system/bin/linker_asan)" $MOD/system/bin/linker_asan
cp -a $FS/system/system/bin/bootstrap/linker $FS/system/system/bin/bootstrap/linker_asan $MOD/system/bin/bootstrap/
cp -a $FS/system_ext/bin/tango_translator $MOD/system/system_ext/bin/
# Global lib layering (adbd excluded: it only goes into the namespace)
for d in $AP/*; do n=$(basename $d); [ -d $d/root/lib ] || continue; [ $n = com.android.adbd ] && continue
  mkdir -p $MOD/apex/$n; cp -a $d/root/lib $MOD/apex/$n/; done
mkdir -p $MOD/apex/com.android.runtime/bin $MOD/apex/com.android.art/bin
cp -a $AP/com.android.runtime/root/bin/{linker,linker_asan,crash_dump32} $MOD/apex/com.android.runtime/bin/
cp -a $AP/com.android.art/root/bin/{dalvikvm32,dex2oat32} $MOD/apex/com.android.art/bin/
# Full CN APEX trees for the private namespace (lib/ comes from apex/<n>/lib at staging time; adbd brings its own)
for n in $NS_ALL; do [ -d $AP/$n/root ] || { echo "WARN: no CN APEX $n"; continue; }
  mkdir -p $MOD/apex_cn/$n; xl=--exclude=./lib; [ $n = com.android.adbd ] && xl=
  (cd $AP/$n/root && tar cf - $xl --exclude=./lib64 --exclude=./app --exclude=./priv-app --exclude=./lost+found .) | (cd $MOD/apex_cn/$n && tar xf -)
done
# Shim lives in /system/framework (magic mount adds the file): nativeloader picks the linker namespace
# from the caller's jar path, and a jar under /apex/com.android.art would get the ART namespace (no libandroid.so).
mkdir -p $MOD/system/framework && cp $SH/tango-shim.jar $MOD/system/framework/tango-shim.jar
cp $O/libtango_gui.so $MOD/system/lib/libtango_gui.so   # parcel bridge, LD_PRELOADed by the wrapper
cp $O/apkinfo.jar $MOD/apkinfo.jar                      # action helper
cp $O/touchgrab $MOD/touchgrab                          # F11: touch off during the quick test
printf '%s\n' "# APEXes swapped to the CN build inside zygote_tango's private mount namespace." \
  "# One name per line; '#' disables. Edit on device, then reboot." $NS_DEFAULT \
  $(for n in $NS_ALL; do case " $NS_DEFAULT " in *" $n "*) ;; *) echo "#$n";; esac; done) > $MOD/ns_apex.list

### [4b] Prune unreachable 32-bit libs (size cut; PRUNE=0 keeps everything)
#     Keeps: public/LLNDK libs, framework-JNI libs (every name in US fw + CN APEX dex strings), GPU/gralloc/
#     Vulkan/RS vendor drivers, all apex/ + apex_cn/ + product/lib, binary deps — then their DT_NEEDED closure
#     plus any lib*.so named as a string inside a kept lib (dlopen). Drops the rest of system/lib + vendor/lib
#     (daemon-side camera/audio/radio/NFC/RIL/location libs) and libclang_rt.asan (nothing NEEDs it; ubsan stays:
#     libinput/liboplusutils/libstagefright_omx NEED it). Edit list: put prune.list next to this script (one
#     module-relative path per line) to use it instead of the computed one. Computed list -> $MODROOT/prune.list.
#     On device a missed lib shows as 'dlopen failed' / 'library "…" not found' in logcat for that app only.
PRUNE=${PRUNE:-1}
if [ "$PRUNE" = 1 ]; then
python3 -c 'import elftools' 2>/dev/null || pip install -q --break-system-packages pyelftools
python3 -I "$SRC/tools/prune.py" "$FS" "$MOD" "$USFW" "$HERE" "$MODROOT"
fi

### [5] SELinux contexts (last-match over CN plat + system_ext + vendor file_contexts)
python3 -I "$SRC/tools/contexts.py" "$FS" "$MOD"

### [6] Module scripts (src/module/)
cp "$SRC/module/module.prop" "$MOD/module.prop"
cp "$SRC/module/customize.sh" "$MOD/customize.sh"
cp "$SRC/module/system/bin/app_process32" "$MOD/system/bin/app_process32"
cp "$SRC/module/post-fs-data.sh" "$MOD/post-fs-data.sh"
cp "$SRC/module/service.sh" "$MOD/service.sh"
cp "$SRC/module/action.sh" "$MOD/action.sh"
cp "$SRC/module/tango32_dir.sh" "$MOD/tango32_dir.sh"
cp "$SRC/module/logs.sh" "$MOD/logs.sh"
cp "$SRC/module/uninstall.sh" "$MOD/uninstall.sh"
cp "$SRC/module/patches.sh" "$MOD/patches.sh"
rm -rf "$MOD/patches"; cp -a $O/patches "$MOD/patches"; cp "$SRC/patches/apply.sh" "$MOD/patches/apply.sh"   # app patches
mkdir -p "$MOD/META-INF/com/google/android"
cp "$SRC/module/META-INF/com/google/android/update-binary" "$MOD/META-INF/com/google/android/update-binary"
echo '#MAGISK' > "$MOD/META-INF/com/google/android/updater-script"
# Version stamp + install guard target (customize.sh refuses any other model/fingerprint)
sed -i "s/@VER@/$VER/g; s/@VC@/$VC/g" "$MOD/module.prop" "$MOD/customize.sh" "$MOD/action.sh"
grep -q "@V" "$MOD/module.prop" "$MOD/customize.sh" "$MOD/action.sh" && { echo "FATAL: version placeholder left"; exit 1; } || true
grep -E "^(model|display|fingerprint|ota|pulled)=" $USFW/build.txt > "$MOD/target.prop"
chmod 0755 "$MOD"/*.sh "$MOD/system/bin/app_process32" "$MOD/touchgrab"
# Wrapper is written after [5]; label it here (init must transition to zygote on it)
echo "system/bin/app_process32 u:object_r:zygote_exec:s0" >> "$MOD/contexts.txt" && sort -o "$MOD/contexts.txt" "$MOD/contexts.txt"
[ -e "$MOD/sepolicy.rule" ] && { echo "FATAL: sepolicy.rule present"; exit 1; }
grep -lc "$(printf '\r')" "$MOD"/*.sh "$MOD/patches/apply.sh" "$MOD/system/bin/app_process32" 2>/dev/null && { echo "FATAL: CR in scripts"; exit 1; } || true
for s in "$MOD"/*.sh "$MOD/patches/apply.sh" "$MOD/system/bin/app_process32"; do sh -n "$s" || { echo "FATAL: syntax $s"; exit 1; }; done

### [7] ART report + zip
python3 -I "$SRC/tools/art_report.py" "$AP"
cd $MOD && rm -f $MODROOT/tango32-$VER.zip && zip -qry9 $MODROOT/tango32-$VER.zip .
sha256sum $MODROOT/tango32-$VER.zip | tee $MODROOT/tango32-$VER.zip.sha256
du -sh $MODROOT/tango32-$VER.zip
echo "Built $MODROOT/tango32-$VER.zip"
