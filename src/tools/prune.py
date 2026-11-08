import os,re,sys,zipfile
from elftools.elf.elffile import ELFFile
FS,M,USFW,HERE,OUT=sys.argv[1:6]
def needed(p):
  try:
    with open(p,'rb') as fh:
      d=ELFFile(fh).get_section_by_name('.dynamic')
      return [t.needed for t in d.iter_tags() if t.entry.d_tag=='DT_NEEDED'] if d else []
  except Exception: return []
def strs(p):
  try: b=open(p,'rb').read()
  except Exception: return set()
  return {s if s.endswith('.so') else s+'.so' for s in (m.group(1).decode() for m in re.finditer(rb'(lib[A-Za-z0-9_.@+\-]{2,80})',b))}
idx={}; files=[]
for r,_,fs in os.walk(M):
  for f in fs:
    p=os.path.join(r,f)
    if f.endswith('.so') and not os.path.islink(p): files.append(p); idx.setdefault(f,[]).append(p)
rel=lambda p: os.path.relpath(p,M)
ASAN='system/lib/libclang_rt.asan-arm-android.so'
user=os.path.join(HERE,'prune.list')
if os.path.exists(user):
  drop=[l.strip() for l in open(user) if l.strip() and not l.startswith('#')]; src='prune.list (kit)'
else:
  roots=set()
  def add(n): roots.update(idx.get(n,[]))
  for t in ['system/system/etc/public.libraries.txt','system/system/etc/public.libraries-qti.txt','system_ext/etc/public.libraries-oplus.txt',
            'system_ext/etc/public.libraries-qti.txt','product/etc/public.libraries-qti.txt','vendor/etc/public.libraries.txt','system/system/etc/llndk.libraries.txt']:
    p=os.path.join(FS,t)
    if os.path.exists(p):
      for l in open(p,errors='ignore'):
        l=l.split('#')[0].split()
        if l: add(l[0])
  for n in ['libandroid_runtime.so','libhwui.so','libtango_gui.so','libvulkan.so','libgui.so','libjnigraphics.so','libRS.so','libRS_internal.so','libRSDriver.so','libRSCpuRef.so',
            'libEGL_angle.so','libGLESv1_CM_angle.so','libGLESv2_angle.so','libfeature_support_angle.so']: add(n)   # EGL loader builds ANGLE names at runtime
  for d in [USFW,os.path.join(M,'apex_cn')]:
    for r,_,fs in os.walk(d):
      for f in fs:
        if not f.endswith('.jar'): continue
        try:
          z=zipfile.ZipFile(os.path.join(r,f))
          for n in z.namelist():
            if n.endswith('.dex'):
              b=z.read(n)   # loadLibrary("X") names (any case: OPlus uses UahPerf_Jni etc.) + literal lib*.so paths
              for m in re.finditer(rb'[\x01-\x7f]([A-Za-z][A-Za-z0-9_\-]{1,60})\x00',b): add('lib'+m.group(1).decode()+'.so')
              for m in re.finditer(rb'(lib[A-Za-z0-9_.@+\-]{2,80}\.so)',b): add(m.group(1).decode())
        except Exception: pass
  for p in files:
    r=rel(p)
    if r.startswith(('apex/','apex_cn/','system/product/lib/','system/vendor/lib/egl/')) \
       or re.match(r'system/vendor/lib/hw/(.*mapper.*|gralloc.*|vulkan.*|android\.hardware\.renderscript.*)',r) \
       or re.match(r'system/vendor/lib/(libRSDriver.*|librs_adreno.*|libOpenCL.*|libadreno_utils.*|libgsl.*|libllvm-.*|libCB.*|libVkLayer.*|libq3dtools.*|libEGL_.*|libGLES.*)',r):
      roots.add(p)
  for b in ['system/bin/app_process32_tango','system/system_ext/bin/tango_translator','apex/com.android.art/bin/dalvikvm32','apex/com.android.art/bin/dex2oat32','apex/com.android.runtime/bin/crash_dump32']:
    for n in needed(os.path.join(M,b)): add(n)
  roots.discard(os.path.join(M,ASAN))   # string-referenced only (bionic asan mode)
  keep=set(); st=list(roots)
  while st:
    p=st.pop()
    if p in keep: continue
    keep.add(p)
    for n in set(needed(p))|strs(p): st.extend(idx.get(n,[]))
  drop=sorted(rel(p) for p in files if p not in keep and rel(p).startswith(('system/lib/','system/vendor/lib/')))
  if any(ASAN in needed(os.path.join(M,k)) for k in map(rel,keep)): drop=[d for d in drop if d!=ASAN]
  src='computed'
  with open(os.path.join(OUT,'prune.list'),'w') as f:
    f.write('# Tango32 prune list (computed by build.sh). Remove a line to keep that lib;\n# place this file next to the script to use it.\n'+'\n'.join(drop)+'\n')
n=b=0
for d in drop:
  p=os.path.join(M,d)
  if os.path.isfile(p) and not os.path.islink(p): b+=os.path.getsize(p); os.remove(p); n+=1
for r,ds,fs in os.walk(M,topdown=False):
  if not ds and not fs and rel(r).startswith(('system/lib/','system/vendor/lib/')): os.rmdir(r)
# dangling symlinks into pruned libs
for r,_,fs in os.walk(M):
  for f in fs:
    p=os.path.join(r,f)
    if os.path.islink(p) and not os.readlink(p).startswith('/') and not os.path.exists(p): print('WARN dangling',rel(p))
print(f'prune ({src}): removed {n} libs, {b/1e6:.0f} MB')
