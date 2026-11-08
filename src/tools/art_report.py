import sys,hashlib,os
ap=sys.argv[1]
def manifest(p):
  b=open(p,'rb').read(); i=0; out={}
  def var():
    nonlocal i; r=s=0
    while True:
      c=b[i]; i+=1; r|=(c&0x7f)<<s; s+=7
      if c<0x80: return r
  while i<len(b):
    k=var(); f,t=k>>3,k&7
    if t==0: out[f]=var()
    elif t==2: l=var(); out.setdefault(f,b[i:i+l]); i+=l
    else: break
  return out.get(1,b'').decode(errors='replace'),out.get(2)
for n in ['com.android.art','com.android.i18n','com.android.conscrypt','com.android.adbd']:
  m=os.path.join(ap,n,'root','apex_manifest.pb')
  if os.path.exists(m): print('CN',n,'%s v%s'%manifest(m))
