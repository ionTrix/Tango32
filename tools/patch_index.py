#!/usr/bin/env python3
# Tango32 online patch index — 2026-11-15 ET (v1.1; batch 3: one entry per patch family)
# Turns the output of tools/build_patches.sh into the files of the rolling GitHub Release "patches":
#   python3 tools/patch_index.py <built_patches_dir> <release_dir> [seq]
#   -> <release_dir>/index.json + <id>__r<rev>__<wrapper>.so (one per patch family)
# seq = UTC YYYYMMDDHHMM (default: now). Phones refuse an index whose seq is lower than the last one they
#   accepted (replay guard), so it must only go up. index.json is then signed by CI (index.json.sig).
# Every patch.prop needs rev= (integer >= 1, bump on every change). Optional: min_module= (versionCode, default
#   101 = v1.1, the first module that reads online patches), tested_vcode= (info only).
# Field rules mirror the phone-side checks in src/apkinfo/Patches.java (a bad patch.prop fails here, not on phones).
import hashlib, json, os, re, shutil, sys, time

NAME_SO = re.compile(r'^[A-Za-z0-9_.+-]{1,64}\.so$')
PKG = re.compile(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$')
ID = re.compile(r'^[a-z0-9][a-z0-9-]{1,39}$')
SYM = re.compile(r'^[A-Za-z0-9_.$@]{1,200}$')

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

def text(p, k, fid, limit, need=True):
    v = p.get(k, '')
    if need and not v:
        die(f'{fid}: patch.prop has no {k}=')
    if len(v) > limit or any(ord(c) < 32 for c in v):
        die(f'{fid}: {k}= too long (max {limit}) or has control characters')
    return v

def main():
    if len(sys.argv) < 3:
        die('usage: patch_index.py <built_patches_dir> <release_dir> [seq]')
    src, out = sys.argv[1], sys.argv[2]
    seq = int(sys.argv[3]) if len(sys.argv) > 3 else int(time.strftime('%Y%m%d%H%M', time.gmtime()))
    os.makedirs(out, exist_ok=True)
    patches = []
    for fid in sorted(os.listdir(src)):   # family id = folder name
        pp = os.path.join(src, fid, 'patch.prop')
        if fid.startswith('.') or not os.path.isfile(pp):
            continue
        if not ID.match(fid):
            die(f'bad family folder name: {fid} (lowercase letters, digits, -)')
        p = props(pp)
        typ = p.get('type', '')
        if typ not in ('symbol', 'behavior'):
            die(f'{fid}: patch.prop needs type=symbol or type=behavior')
        pkgs = text(p, 'pkgs', fid, 600, False)
        if pkgs and not all(PKG.match(x) and len(x) <= 128 for x in pkgs.split(',')):
            die(f'{fid}: pkgs= must be package names separated by commas (no spaces)')
        syms = text(p, 'match_symbol', fid, 2000, False)
        if syms and not all(SYM.match(x) for x in syms.split(' ')):
            die(f'{fid}: match_symbol= must be symbol names separated by single spaces')
        if typ == 'symbol' and not syms:
            die(f'{fid}: type=symbol needs match_symbol=')
        rev = p.get('rev', '')
        if not rev.isdigit() or int(rev) < 1:
            die(f'{fid}: patch.prop needs rev= (integer >= 1; bump it on every change)')
        mm = p.get('min_module', '101')
        if not mm.isdigit():
            die(f'{fid}: min_module= must be a versionCode (e.g. 101)')
        lib, need, wrap = (text(p, k, fid, 64) for k in ('lib', 'needed', 'wrapper'))
        for v in (need, wrap) if lib == '*' else (lib, need, wrap):
            if not NAME_SO.match(v):
                die(f'{fid}: bad library name {v!r}')
        if len(need) != len(wrap):
            die(f'{fid}: needed and wrapper names must be the same length')
        so = os.path.join(src, fid, wrap)
        data = open(so, 'rb').read()
        if len(data) > 2 * 1024 * 1024:
            die(f'{fid}: {wrap} is over 2 MB')
        if data[:4] != b'\x7fELF' or data[4] != 1 or int.from_bytes(data[18:20], 'little') != 40:
            die(f'{fid}: {wrap} is not a 32-bit ARM ELF')
        fname = f'{fid}__r{rev}__{wrap}'
        shutil.copyfile(so, os.path.join(out, fname))
        e = {'id': fid, 'name': text(p, 'name', fid, 80), 'type': typ, 'pkgs': pkgs, 'match_symbol': syms,
             'rev': int(rev), 'min_module': int(mm),
             'tested': text(p, 'tested', fid, 80, False), 'fixes': text(p, 'fixes', fid, 600, False),
             'lib': lib, 'needed': need, 'wrapper': wrap, 'file': fname,
             'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        if p.get('tested_vcode'):
            e['tested_vcode'] = text(p, 'tested_vcode', fid, 80)
        patches.append(e)
    if not patches:
        die(f'no patches in {src}')
    idx = json.dumps({'format': 1, 'seq': seq, 'patches': patches}, indent=1, ensure_ascii=False) + '\n'
    if len(idx.encode()) > 256 * 1024:
        die('index.json is over 256 KB')
    with open(os.path.join(out, 'index.json'), 'w', encoding='utf-8') as f:
        f.write(idx)
    print(f'index.json: seq {seq}, {len(patches)} patches: ' + ', '.join(f"{e['id']} r{e['rev']}" for e in patches))

main()
