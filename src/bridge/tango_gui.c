/* libtango_gui.so — Tango32 parcel-format bridge (CN 16.0.3.500 32-bit libgui -> US 16.0.10.601 SurfaceFlinger)
 * Tango32 v1.0, 2026-11-07 23:10 ET. Removes itself from LD_PRELOAD in the constructor (64-bit children of 32-bit apps);
 * LP32 RTLD_NEXT + libbinder fallback and self-check; libgui lookup only in the constructor (no loader calls
 * on the hot path). LD_PRELOADed into the 32-bit zygote by the app_process32 wrapper.
 * Interposes a few android::Parcel::write* methods. When the caller is one of the CN libgui call sites
 * below (matched by return address, verified against the expected instruction bytes), it writes the
 * fields that the US 601 readers expect and the CN 500 writers lack, with US default values:
 *   layer_state_t::write       + fwOptMode (u32)                after dropInputMode
 *                              + surfaceUpdateListener          before currentHdrSdrRatio
 *   OplusBlurParams::write     + smoothCornerType (i32)         after smoothCornerWeight
 *   oplus_layer_state_t::write + type (i32)                     after weight
 *                              + inheritEdrSdrRatio (bool)      after edrSdrRatio
 *                              + hasOnColorPickedListener (bool) before vfxAnimationType
 *                              + transformMatrix4x4 (identity)  after shadowOn
 * Found by emulating the CN32 writers and US64 readers (unicorn) and diffing the parcel streams. */
typedef unsigned int uint32_t; typedef int int32_t; typedef unsigned short uint16_t; typedef unsigned int uintptr_t;
typedef unsigned int size_t;
typedef int status_t;
#define RTLD_NEXT ((void *)0xfffffffe)   /* bionic LP32 (0xffffffff is RTLD_DEFAULT -> resolved to ourselves: v1/v2 infinite loop) */
#define RTLD_NOLOAD 4
void *dlopen(const char *, int);
void *dlsym(void *, const char *);
int __android_log_print(int, const char *, const char *, ...);
struct dl_phdr_info { uintptr_t dlpi_addr; const char *dlpi_name; const void *dlpi_phdr; uint16_t dlpi_phnum; };
int access(const char *, int);
char *getenv(const char *);
int setenv(const char *, const char *, int);
int unsetenv(const char *);
int dl_iterate_phdr(int (*)(struct dl_phdr_info *, size_t, void *), void *);
#define TAG "TangoGui"

typedef status_t (*f_i32)(void *, int32_t);
typedef status_t (*f_u32)(void *, uint32_t);
typedef status_t (*f_flt)(void *, float);
typedef status_t (*f_bool)(void *, int);
typedef status_t (*f_bin)(void *, const void *);
typedef status_t (*f_blob)(void *, const void *, size_t);
static f_i32 r_i32; static f_u32 r_u32; static f_flt r_flt; static f_bool r_bool; static f_bin r_bin; static f_blob r_blob;

static uintptr_t gui;            /* libgui load bias; 0 = not found yet, 1 = disabled */
static unsigned hits[8];

enum { S_FWOPT, S_BLURSCT, S_TYPE, S_INHERIT, S_MATRIX, S_SUL, S_COLORPICK, NS };
static const struct { uint32_t ret; uint32_t insn; const char *what; } SITE[NS] = {
  {0xad5ac, 0xeebaf06f, "fwOptMode"},
  {0xe7704, 0xe996f037, "smoothCornerType"},
  {0xe30f0, 0xeca0f03b, "type"},
  {0xe31da, 0xec2cf03b, "inheritEdrSdrRatio"},
  {0xe34b6, 0xef26f039, "transformMatrix4x4"},
  {0xadf24, 0xed86f070, "surfaceUpdateListener"},
  {0xe3238, 0xeb0cf039, "hasOnColorPickedListener"},
};

status_t _ZN7android6Parcel10writeInt32Ei(void *, int32_t);
status_t _ZN7android6Parcel11writeUint32Ej(void *, uint32_t);
status_t _ZN7android6Parcel10writeFloatEf(void *, float);
status_t _ZN7android6Parcel9writeBoolEb(void *, int);

static void resolve(void) {
  if (!r_i32) {
    r_i32 = (f_i32)dlsym(RTLD_NEXT, "_ZN7android6Parcel10writeInt32Ei");
    r_u32 = (f_u32)dlsym(RTLD_NEXT, "_ZN7android6Parcel11writeUint32Ej");
    r_flt = (f_flt)dlsym(RTLD_NEXT, "_ZN7android6Parcel10writeFloatEf");
    r_bool = (f_bool)dlsym(RTLD_NEXT, "_ZN7android6Parcel9writeBoolEb");
    r_bin = (f_bin)dlsym(RTLD_NEXT, "_ZN7android6Parcel17writeStrongBinderERKNS_2spINS_7IBinderEEE");
    r_blob = (f_blob)dlsym(RTLD_NEXT, "_ZN7android6Parcel5writeEPKvj");
    if ((void *)r_i32 == (void *)_ZN7android6Parcel10writeInt32Ei || (void *)r_u32 == (void *)_ZN7android6Parcel11writeUint32Ej ||
        (void *)r_flt == (void *)_ZN7android6Parcel10writeFloatEf || (void *)r_bool == (void *)_ZN7android6Parcel9writeBoolEb || !r_i32) {
      void *h = dlopen("libbinder.so", RTLD_NOLOAD);
      r_i32 = h ? (f_i32)dlsym(h, "_ZN7android6Parcel10writeInt32Ei") : 0;
      r_u32 = h ? (f_u32)dlsym(h, "_ZN7android6Parcel11writeUint32Ej") : 0;
      r_flt = h ? (f_flt)dlsym(h, "_ZN7android6Parcel10writeFloatEf") : 0;
      r_bool = h ? (f_bool)dlsym(h, "_ZN7android6Parcel9writeBoolEb") : 0;
      r_bin = h ? (f_bin)dlsym(h, "_ZN7android6Parcel17writeStrongBinderERKNS_2spINS_7IBinderEEE") : 0;
      r_blob = h ? (f_blob)dlsym(h, "_ZN7android6Parcel5writeEPKvj") : 0;
      __android_log_print(5, TAG, "RTLD_NEXT gave self/null; libbinder handle %p -> writeInt32=%p", h, (void *)r_i32);
    }
  }
}

static int eq10(const char *a) { const char *b = "/libgui.so"; for (int i = 0; i < 10; i++) if (a[i] != b[i]) return 0; return 1; }

static int cb(struct dl_phdr_info *i, size_t s, void *d) {
  const char *n = i->dlpi_name; size_t l = 0;
  if (!n) return 0;
  while (n[l]) l++;
  if (l >= 10 && eq10(n + l - 10)) { *(uintptr_t *)d = i->dlpi_addr; return 1; }
  return 0;
}

static void find_gui(void) {
  uintptr_t b = 0;
  dl_iterate_phdr(cb, &b);
  if (!b) { gui = 1; __android_log_print(5, TAG, "libgui not loaded at init - bridge OFF"); return; }
  for (int k = 0; k < NS; k++) {
    const uint16_t *p = (const uint16_t *)(b + SITE[k].ret - 4);
    uint32_t w = p[0] | ((uint32_t)p[1] << 16);
    if (w != SITE[k].insn) {
      __android_log_print(6, TAG, "libgui@%p: site %s mismatch (%08x != %08x) - not the CN 16.0.3.500 build, bridge OFF",
                          (void *)b, SITE[k].what, w, SITE[k].insn);
      gui = 1; return;
    }
  }
  gui = b;
  __android_log_print(4, TAG, "libgui@%p verified, parcel bridge ON (%d sites)", (void *)b, NS);
}

static inline int site(void *ra) {
  if (gui <= 1) return -1;   /* resolved once in the constructor; never touch the loader lock here */
  uint32_t o = (uint32_t)(((uintptr_t)ra & ~(uintptr_t)1) - gui);
  for (int k = 0; k < NS; k++) if (o == SITE[k].ret) {
    if (hits[k]++ == 0) __android_log_print(4, TAG, "first %s insert", SITE[k].what);
    return k;
  }
  return -1;
}

static const float IDENT[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};

#define EXPORT __attribute__((visibility("default"), noinline))

EXPORT status_t _ZN7android6Parcel11writeUint32Ej(void *p, uint32_t v) {
  void *ra = __builtin_return_address(0); resolve();
  status_t e = r_u32(p, v);
  if (e == 0 && site(ra) == S_FWOPT) e = r_u32(p, 0);
  return e;
}

EXPORT status_t _ZN7android6Parcel10writeFloatEf(void *p, float v) {
  void *ra = __builtin_return_address(0); resolve();
  int k = site(ra);
  if (k == S_SUL) {          /* US default SurfaceUpdateListener parcelable: marker, null binder, -1, true */
    void *nullsp = 0; status_t e;
    if ((e = r_i32(p, 1)) || (e = r_bin(p, &nullsp)) || (e = r_i32(p, -1)) || (e = r_bool(p, 1))) return e;
  }
  status_t e = r_flt(p, v);
  if (e) return e;
  if (k == S_BLURSCT || k == S_TYPE) e = r_i32(p, 0);
  else if (k == S_INHERIT) e = r_bool(p, 0);
  return e;
}

EXPORT status_t _ZN7android6Parcel9writeBoolEb(void *p, int v) {
  void *ra = __builtin_return_address(0); resolve();
  status_t e = r_bool(p, v & 0xff);
  if (e == 0 && site(ra) == S_MATRIX) e = r_blob(p, IDENT, sizeof IDENT);
  return e;
}

EXPORT status_t _ZN7android6Parcel10writeInt32Ei(void *p, int32_t v) {
  void *ra = __builtin_return_address(0); resolve();
  if (site(ra) == S_COLORPICK) { status_t e = r_bool(p, 0); if (e) return e; }
  return r_i32(p, v);
}

/* Drop ourselves from LD_PRELOAD once loaded. The zygote keeps us in memory and its apps inherit that,
   but anything an app execs (sh, su, logcat: 64-bit) must not get a 32-bit preload: its linker refuses to start
   ("CANNOT LINK EXECUTABLE ... libtango_gui.so ... not accessible"). Other LD_PRELOAD entries are kept. */
static void drop_preload(void) {
  const char *v = getenv("LD_PRELOAD"), *p = v;
  static const char me[] = "libtango_gui.so";
  char out[512]; unsigned o = 0, k;
  if (!v) return;
  while (*p) {
    const char *s = p, *b;
    while (*p && *p != ':' && *p != ' ') p++;
    unsigned n = (unsigned)(p - s);
    for (b = p; b > s && b[-1] != '/'; b--) ;
    int mine = (unsigned)(p - b) == sizeof me - 1;
    for (k = 0; mine && k < sizeof me - 1; k++) if (b[k] != me[k]) mine = 0;
    if (n && !mine && o + n + 2 < sizeof out) { if (o) out[o++] = ':'; for (k = 0; k < n; k++) out[o++] = s[k]; }
    if (*p) p++;
  }
  out[o] = 0;
  if (o) setenv("LD_PRELOAD", out, 1); else unsetenv("LD_PRELOAD");
  __android_log_print(4, TAG, "LD_PRELOAD for child processes: %s", o ? out : "(removed)");
}

__attribute__((constructor)) static void ctor(void) {
  drop_preload();
  resolve();
  __android_log_print(4, TAG, "libtango_gui.so loaded (Tango32 v1.0) real writeInt32=%p (self %p)", (void *)r_i32, (void *)_ZN7android6Parcel10writeInt32Ei);
  if (access("/dev/tango_gui_off", 0) == 0) { gui = 1; __android_log_print(5, TAG, "/dev/tango_gui_off present - bridge OFF (pass-through)"); return; }
  find_gui();
}
