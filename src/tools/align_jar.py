import sys, zipfile
src, dst = sys.argv[1:]
zi = zipfile.ZipInfo('classes.dex', (2026, 1, 1, 0, 0, 0)); zi.compress_type = zipfile.ZIP_STORED
pad = (-(30 + len(zi.filename))) % 4
if pad: pad += 4 if pad < 4 else 0; zi.extra = b'\xfe\xca' + (pad - 4).to_bytes(2, 'little') + b'\0' * (pad - 4)
with zipfile.ZipFile(dst, 'w') as z: z.writestr(zi, open(src, 'rb').read())
z = zipfile.ZipFile(dst); i = z.getinfo('classes.dex')
off = i.header_offset + 30 + len(i.filename) + len(i.extra)
assert off % 4 == 0, off; print('shim dex offset', off)
