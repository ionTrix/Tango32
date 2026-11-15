#!/usr/bin/env python3
# Tango32 online patch index — 2026-11-14 23:40 ET (v1.1)
# Turns the output of tools/build_patches.sh into the files of the rolling GitHub Release "patches":
#   python3 tools/patch_index.py <built_patches_dir> <release_dir> [seq]
#   -> <release_dir>/index.json + <pkg>__r<rev>__<wrapper>.so (one per patch)
# seq = UTC YYYYMMDDHHMM (default: now). Phones refuse an index whose seq is lower than the last one they
#   accepted (replay guard), so it must only go up. index.json is then signed by CI (index.json.sig).
# Every patch.prop needs rev= (integer >= 1, bump on every change). Optional: min_module= (versionCode, default
#   101 = v1.1, the first module that reads online patches), tested_vcode= (info only).
# Field rules mirror the phone-side checks in src/apkinfo/Patches.java (a bad patch.prop fails here, not on phones).
import hashlib, json, os, re, shutil, sys, time

NAME_SO = re.compile(r'^[A-Za-z0-9_.+-]{1,64}\.so$')
PKG = re.compile(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$')

def die(m):
    sys.exit('FATAL: ' + m)

def props(path):
    d = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            d.setdefault(k, v)
    return d

def text(p, k, pkg, limit, need=True):
    v = p.get(k, '')
    if need and not v:
        die(f'{pkg}: patch.prop has no {k}=')
    if len(v) > limit or any(ord(c) < 32 for c in v):
        die(f'{pkg}: {k}= too long (max {limit}) or has control characters')
    return v

def main():
    if len(sys.argv) < 3:
        die('usage: patch_index.py <built_patches_dir> <release_dir> [seq]')
    src, out = sys.argv[1], sys.argv[2]
    seq = int(sys.argv[3]) if len(sys.argv) > 3 else int(time.strftime('%Y%m%d%H%M', time.gmtime()))
    os.makedirs(out, exist_ok=True)
    patches = []
    for pkg in sorted(os.listdir(src)):
        pp = os.path.join(src, pkg, 'patch.prop')
        if pkg.startswith('.') or not os.path.isfile(pp):
            continue
        if not PKG.match(pkg) or len(pkg) > 128:
            die(f'bad package folder name: {pkg}')
        p = props(pp)
        rev = p.get('rev', '')
        if not rev.isdigit() or int(rev) < 1:
            die(f'{pkg}: patch.prop needs rev= (integer >= 1; bump it on every change)')
        mm = p.get('min_module', '101')
        if not mm.isdigit():
            die(f'{pkg}: min_module= must be a versionCode (e.g. 101)')
        lib, need, wrap = (text(p, k, pkg, 64) for k in ('lib', 'needed', 'wrapper'))
        for v in (lib, need, wrap):
            if not NAME_SO.match(v):
                die(f'{pkg}: bad library name {v!r}')
        if len(need) != len(wrap):
            die(f'{pkg}: needed and wrapper names must be the same length')
        so = os.path.join(src, pkg, wrap)
        data = open(so, 'rb').read()
        if len(data) > 2 * 1024 * 1024:
            die(f'{pkg}: {wrap} is over 2 MB')
        if data[:4] != b'\x7fELF' or data[4] != 1 or int.from_bytes(data[18:20], 'little') != 40:
            die(f'{pkg}: {wrap} is not a 32-bit ARM ELF')
        fname = f'{pkg}__r{rev}__{wrap}'
        shutil.copyfile(so, os.path.join(out, fname))
        e = {'pkg': pkg, 'name': text(p, 'name', pkg, 80), 'rev': int(rev), 'min_module': int(mm),
             'tested': text(p, 'tested', pkg, 80, False), 'fixes': text(p, 'fixes', pkg, 600, False),
             'lib': lib, 'needed': need, 'wrapper': wrap, 'file': fname,
             'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        if p.get('tested_vcode'):
            e['tested_vcode'] = text(p, 'tested_vcode', pkg, 80)
        patches.append(e)
    if not patches:
        die(f'no patches in {src}')
    idx = json.dumps({'format': 1, 'seq': seq, 'patches': patches}, indent=1, ensure_ascii=False) + '\n'
    if len(idx.encode()) > 256 * 1024:
        die('index.json is over 256 KB')
    with open(os.path.join(out, 'index.json'), 'w', encoding='utf-8') as f:
        f.write(idx)
    print(f'index.json: seq {seq}, {len(patches)} patches: ' + ', '.join(f"{e['pkg']} r{e['rev']}" for e in patches))

main()
