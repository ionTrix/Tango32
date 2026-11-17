/* tango32_touchgrab — F11: block touch during the Action quick test.
 * Updated: 2026-11-17 15:25 ET
 * Usage: touchgrab <seconds>
 * Grabs every direct-touch evdev (ABS_MT_POSITION_X + INPUT_PROP_DIRECT)
 * with EVIOCGRAB, prints "grabbed /dev/input/eventN" per device, holds for
 * <seconds> (max 60), exits. The kernel drops the grab on exit/kill/crash.
 * Exit: 0 = at least one grabbed, 2 = no touchscreen found, 1 = bad args.
 * Freestanding aarch64 (raw syscalls, no libc): built by build.sh [3f], clang + lld, static. */
typedef unsigned long u64; typedef long s64;

#define SYS_ioctl 29
#define SYS_openat 56
#define SYS_close 57
#define SYS_getdents64 61
#define SYS_write 64
#define SYS_exit_group 94
#define SYS_nanosleep 101
#define AT_FDCWD -100
#define O_RDONLY 0
#define O_DIRECTORY 040000
#define O_CLOEXEC 02000000

#define IOC(d,t,n,s) (((u64)(d)<<30)|((u64)(s)<<16)|((u64)(t)<<8)|(u64)(n))
#define EVIOCGPROP(l)   IOC(2,'E',0x09,l)
#define EVIOCGBIT(e,l)  IOC(2,'E',0x20+(e),l)
#define EVIOCGRAB       IOC(1,'E',0x90,sizeof(int))
#define EV_ABS 3
#define ABS_MT_POSITION_X 0x35
#define INPUT_PROP_DIRECT 1

static s64 sc(s64 n,s64 a,s64 b,s64 c,s64 d){
  register s64 x8 __asm__("x8")=n; register s64 x0 __asm__("x0")=a;
  register s64 x1 __asm__("x1")=b; register s64 x2 __asm__("x2")=c;
  register s64 x3 __asm__("x3")=d;
  __asm__ volatile("svc 0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3):"memory");
  return x0;
}
static int slen(const char*s){int n=0;while(s[n])n++;return n;}
static void out(const char*s){sc(SYS_write,1,(s64)s,slen(s),0);}
static int bit(const unsigned char*b,int i){return (b[i>>3]>>(i&7))&1;}

void _start_c(s64 *sp){
  int argc=(int)sp[0]; char**argv=(char**)(sp+1);
  if(argc<2){out("usage: touchgrab <seconds>\n");sc(SYS_exit_group,1,0,0,0);}
  s64 secs=0; for(const char*p=argv[1];*p;p++){
    if(*p<'0'||*p>'9'){out("bad seconds\n");sc(SYS_exit_group,1,0,0,0);}
    secs=secs*10+(*p-'0'); if(secs>60)secs=60; }

  int grabbed=0; char buf[2048];
  s64 dfd=sc(SYS_openat,AT_FDCWD,(s64)"/dev/input",O_RDONLY|O_DIRECTORY|O_CLOEXEC,0);
  if(dfd>=0){
    for(;;){
      s64 n=sc(SYS_getdents64,dfd,(s64)buf,sizeof buf,0); if(n<=0)break;
      for(s64 off=0;off<n;){
        unsigned short reclen=*(unsigned short*)(buf+off+16);
        const char*name=buf+off+19; off+=reclen;
        if(name[0]!='e'||name[1]!='v'||name[2]!='e'||name[3]!='n'||name[4]!='t')continue;
        char path[64]="/dev/input/"; int k=11; for(int i=0;name[i]&&k<62;i++)path[k++]=name[i]; path[k]=0;
        s64 fd=sc(SYS_openat,AT_FDCWD,(s64)path,O_RDONLY|O_CLOEXEC,0); if(fd<0)continue;
        unsigned char abs[8]={0},prop[8]={0};
        int ok=sc(SYS_ioctl,fd,EVIOCGBIT(EV_ABS,sizeof abs),(s64)abs,0)>=0 && bit(abs,ABS_MT_POSITION_X)
             && sc(SYS_ioctl,fd,EVIOCGPROP(sizeof prop),(s64)prop,0)>=0 && bit(prop,INPUT_PROP_DIRECT);
        if(ok && sc(SYS_ioctl,fd,EVIOCGRAB,1,0)==0){out("grabbed ");out(path);out("\n");grabbed++;}
        else sc(SYS_close,fd,0,0,0);   /* keep grabbed fds open until exit */
      }
    }
    sc(SYS_close,dfd,0,0,0);
  }
  if(!grabbed){out("no touchscreen found\n");sc(SYS_exit_group,2,0,0,0);}
  s64 ts[2]={secs,0}; sc(SYS_nanosleep,(s64)ts,0,0,0);  /* SIGTERM/SIGKILL ends it early */
  sc(SYS_exit_group,0,0,0,0);
}
__asm__(".globl _start\n_start:\n mov x0, sp\n b _start_c\n");
