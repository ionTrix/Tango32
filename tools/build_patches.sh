#!/usr/bin/env bash
# Tango32 app patches build — 2026-11-15 ET (v1.1: pulled out of build.sh [3d2] so CI builds the same way;
#   batch 3: one folder per patch family, src/patches/<id>/)
# Builds every src/patches/<id>/ wrapper lib (armv7 Thumb, freestanding; stub libc/libdl/liblog + a stub of the
#   wrapped lib, for linking only — the real ones come from the phone at load time).
#   bash tools/build_patches.sh <outdir>      -> <outdir>/<id>/{patch.prop,<wrapper>.so}
# Needs: clang + ld.lld (any recent LLVM; CI uses 18). Called by build.sh [3d2] and .github/workflows/patches.yml.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); SRC=$HERE/src
OUT=${1:?usage: build_patches.sh <outdir>}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
ST=$OUT/.stubs; rm -rf "$ST"; mkdir -p "$ST"
CT="--target=armv7a-linux-androideabi -mthumb -fPIC -nostdlib -fuse-ld=lld -ffreestanding"
for s in libc libdl liblog; do clang $CT -shared -Wl,-soname,$s.so -o $ST/$s.so "$SRC/bridge/stubs.c"; done
for d in "$SRC"/patches/*/; do
  pk=$(basename "$d"); p() { sed -n "s/^$1=//p" "$d/patch.prop" | head -1; }
  w=$(p wrapper); n=$(p needed); c=$(p source)
  [[ $pk =~ ^[a-z0-9][a-z0-9-]{1,39}$ ]] || { echo "FATAL: $pk: family folder = lowercase letters, digits, - (2-40)"; exit 1; }
  case $(p type) in symbol|behavior) ;; *) echo "FATAL: $pk/patch.prop needs type=symbol or type=behavior"; exit 1;; esac
  [ -n "$w" ] && [ -n "$n" ] && [ -n "$c" ] || { echo "FATAL: $pk/patch.prop needs wrapper= needed= source="; exit 1; }
  [ ${#w} = ${#n} ] || { echo "FATAL: $pk: needed and wrapper names must be the same length"; exit 1; }
  rm -rf "$OUT/$pk"; mkdir -p "$OUT/$pk"
  echo 'void glDrawArrays(void){}' > $ST/need.c   # link-time stub for the wrapped lib
  clang $CT -shared -Wl,-soname,$n -o $ST/$n $ST/need.c
  clang $CT -O2 -shared -fno-stack-protector -Wl,-soname,$w -Wl,--hash-style=both -Wl,-z,max-page-size=4096 \
    -Wl,--build-id -Wl,--no-as-needed -Wl,-z,defs -L$ST -l:$n -llog -ldl -o "$OUT/$pk/$w" "$d/$c"
  cp "$d/patch.prop" "$OUT/$pk/"; rm -f $ST/need.c $ST/$n
  echo "patch $pk: $(sha256sum "$OUT/$pk/$w" | cut -d' ' -f1)"
done
rm -rf "$ST"
