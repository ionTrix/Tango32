import re,os,sys
FS,M=sys.argv[1],sys.argv[2]
specs=[]
for f in [FS+'/system/system/etc/selinux/plat_file_contexts',FS+'/system_ext/etc/selinux/system_ext_file_contexts',FS+'/vendor/etc/selinux/vendor_file_contexts']:
  for line in open(f,errors='ignore'):
    p=line.split()
    if len(p)<2 or p[0].startswith('#'): continue
    if len(p)==3 and p[1]!='--': continue
    try: specs.append((re.compile(p[0]),p[-1]))
    except re.error: pass
fix={'system/system_ext/bin/tango_translator':'u:object_r:system_lib_file:s0',
 'system/bin/app_process32':'u:object_r:zygote_exec:s0','system/bin/app_process32_tango':'u:object_r:zygote_exec:s0',
 'apex/com.android.runtime/bin/linker':'u:object_r:system_linker_exec:s0','apex/com.android.runtime/bin/linker_asan':'u:object_r:system_linker_exec:s0',
 'apex/com.android.runtime/bin/crash_dump32':'u:object_r:crash_dump_exec:s0','apex/com.android.art/bin/dex2oat32':'u:object_r:dex2oat_exec:s0',
 'apex/com.android.art/bin/dalvikvm32':'u:object_r:system_file:s0'}
out=[]
for root,dirs,fs in os.walk(M):
  for n in fs+dirs:
    rel=os.path.relpath(os.path.join(root,n),M)
    if rel.startswith('META-INF'): continue
    if rel.startswith('system/vendor/'): dev='/vendor/'+rel[14:]
    elif rel.startswith('system/system_ext/'): dev='/system_ext/'+rel[18:]
    elif rel.startswith('system/product/'): dev='/product/'+rel[15:]
    elif rel.startswith(('system/','apex/')): dev='/'+rel
    elif rel.startswith('apex_cn/'): dev='/apex/'+rel[8:]
    else: continue
    c=None
    for r,x in specs:
      if r.fullmatch(dev): c=x
    top=rel.split('/')[0]
    if rel in fix: c=fix[rel]
    elif top=='apex_cn' and rel.count('/')<=1: c='u:object_r:system_file:s0'
    elif top=='apex_cn' and rel.split('/')[2]=='lib' and rel.count('/')>2: c='u:object_r:system_lib_file:s0'
    elif top=='apex' and (rel.count('/')<=1 or rel.endswith('/bin')): c='u:object_r:system_file:s0'
    elif c is None: c='u:object_r:system_lib_file:s0' if top=='apex' else 'u:object_r:system_file:s0'
    out.append(f'{rel} {c}\n')
open(M+'/contexts.txt','w').write(''.join(sorted(out)))
print(len(out),'contexts')
