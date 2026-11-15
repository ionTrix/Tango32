/* Tango32 app patch: old Adobe AIR fix (v1.1): provides the pre-Android-9 media/ui symbols that old Adobe AIR libCore.so
   imports. Loaded instead of libstagefright.so (same-length NEEDED rename in libCore.so by patches/apply.sh). Exempt-listed libs only expose their OWN symbols to the app, so everything
   that now lives in libstagefright_foundation (MetaData, MediaBuffer, MIME constants) is provided here.
   Hardware AAC (OMX) is disabled, so AIR uses its software path and these objects are never really used.
   Constructors trap on purpose: if AIR ever does use them, the tombstone points straight here. */
typedef unsigned int u32; typedef long long s64;
#define EXP __attribute__((visibility("default")))
#define F(ret, sym, params, body) EXP ret sym##_ params __asm__(#sym); ret sym##_ params body

/* --- libstagefright_foundation: MIME constant --- */
EXP const char *mime_aac __asm__("_ZN7android24MEDIA_MIMETYPE_AUDIO_AACE") = "audio/mp4a-latm";

/* --- MetaData (foundation): ctor traps, accessors report "not set" --- */
F(void,  _ZN7android8MetaDataC1Ev,              (void*t), { (void)t; __builtin_trap(); })
F(int,   _ZN7android8MetaData7setDataEjjPKvj,   (void*t,u32 k,u32 ty,const void*d,u32 n), { (void)t;(void)k;(void)ty;(void)d;(void)n; return 0; })
F(int,   _ZN7android8MetaData10setCStringEjPKc, (void*t,u32 k,const char*v), { (void)t;(void)k;(void)v; return 0; })
F(int,   _ZN7android8MetaData8setInt32Eji,      (void*t,u32 k,int v), { (void)t;(void)k;(void)v; return 0; })
F(int,   _ZN7android8MetaData8setInt64Ejx,      (void*t,u32 k,s64 v), { (void)t;(void)k;(void)v; return 0; })
F(int,   _ZN7android8MetaData11findCStringEjPPKc,(void*t,u32 k,const char**v), { (void)t;(void)k;(void)v; return 0; })
F(int,   _ZN7android8MetaData9findInt32EjPi,    (void*t,u32 k,int*v), { (void)t;(void)k;(void)v; return 0; })
F(int,   _ZN7android8MetaData9findInt64EjPx,    (void*t,u32 k,s64*v), { (void)t;(void)k;(void)v; return 0; })

/* --- MediaBuffer (foundation): ctor traps, accessors empty --- */
F(void,  _ZN7android11MediaBufferC1Ej,          (void*t,u32 n), { (void)t;(void)n; __builtin_trap(); })
F(void,  _ZN7android11MediaBuffer7releaseEv,    (void*t), { (void)t; })
F(void,  _ZN7android11MediaBuffer9set_rangeEjj, (void*t,u32 o,u32 l), { (void)t;(void)o;(void)l; })
F(void*, _ZNK7android11MediaBuffer4dataEv,      (const void*t), { (void)t; return 0; })
F(u32,   _ZNK7android11MediaBuffer4sizeEv,      (const void*t), { (void)t; return 0; })
F(u32,   _ZNK7android11MediaBuffer12range_offsetEv,(const void*t), { (void)t; return 0; })
F(u32,   _ZNK7android11MediaBuffer12range_lengthEv,(const void*t), { (void)t; return 0; })
/* sp<MetaData> meta_data(): non-trivial return -> hidden result pointer in r0, this in r1 */
F(void,  _ZN7android11MediaBuffer9meta_dataEv,  (void**ret,void*t), { (void)t; *ret = 0; })

/* --- MediaSource / OMXClient (libstagefright): provided here too, so libCore no longer needs libstagefright --- */
F(void,  _ZN7android11MediaSourceC2Ev,          (void*t), { (void)t; __builtin_trap(); })
F(void,  _ZN7android11MediaSourceD2Ev,          (void*t), { (void)t; })
/* OMXClient { sp<IOMX> mOMX; } : ctor just nulls the sp; connect fails -> no hardware AAC */
F(void,  _ZN7android9OMXClientC1Ev,             (void*t), { *(void**)t = 0; })
F(int,   _ZN7android9OMXClient7connectEv,       (void*t), { (void)t; return -19; })

/* --- libui: removed in newer Android --- */
F(int,   _ZN7android12bitsPerPixelEi,           (int f), { switch(f){case 1:case 2:case 5:return 32; case 3:return 24; case 4:case 6:case 7:return 16; default:return 0;} })
F(void,  _ZN7android13GraphicBufferC1Ejjij,     (void*t,u32 w,u32 h,int f,u32 u), { (void)t;(void)w;(void)h;(void)f;(void)u; __builtin_trap(); })
F(int,   _ZNK7android13GraphicBuffer9initCheckEv,(const void*t), { (void)t; return -19; })
F(void*, _ZNK7android13GraphicBuffer15getNativeBufferEv,(const void*t), { (void)t; return 0; })
F(int,   _ZN7android13GraphicBuffer6unlockEv,   (void*t), { (void)t; return 0; })
