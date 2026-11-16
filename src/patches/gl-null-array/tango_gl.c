/* libGLESv1_TG.so — GLES1 interposer for Galcon Fusion under Tango.
 * Tango32 v1.0, 2026-11-07 23:10 ET. Wraps glDrawArrays: any enabled client array with a
 * NULL pointer and no buffer bound is disabled for that draw only (newer
 * Adreno drivers memcpy from it). Everything else resolves to libGLESv1_CM.so. */
typedef unsigned int GLenum; typedef int GLint; typedef int GLsizei;
typedef unsigned char GLboolean;
#define RTLD_NOW 2
void *dlopen(const char *, int); void *dlsym(void *, const char *);
int __android_log_print(int, const char *, const char *, ...);
#define TAG "TangoGL"

static void (*r_draw)(GLenum, GLint, GLsizei);
static GLboolean (*r_isen)(GLenum);
static void (*r_getp)(GLenum, void **);
static void (*r_geti)(GLenum, GLint *);
static void (*r_en)(GLenum), (*r_dis)(GLenum);

static const struct { GLenum cap, ptr, buf; const char *n; } A[] = {
  {0x8074, 0x808E, 0x8896, "VERTEX"},
  {0x8075, 0x808F, 0x8897, "NORMAL"},
  {0x8076, 0x8090, 0x8898, "COLOR"},
  {0x8078, 0x8092, 0x889A, "TEXCOORD"},
  {0x8B9C, 0x898C, 0x8B9F, "POINT_SIZE"},
};
#define NA (sizeof A / sizeof A[0])
static unsigned logged[NA]; static unsigned calls;

static int init(void) {
  if (r_draw) return 1;
  void *h = dlopen("libGLESv1_CM.so", RTLD_NOW);
  if (!h) { __android_log_print(6, TAG, "dlopen libGLESv1_CM.so failed"); return 0; }
  r_isen = dlsym(h, "glIsEnabled"); r_getp = dlsym(h, "glGetPointerv");
  r_geti = dlsym(h, "glGetIntegerv"); r_en = dlsym(h, "glEnableClientState");
  r_dis = dlsym(h, "glDisableClientState");
  r_draw = dlsym(h, "glDrawArrays");
  if (!r_draw || !r_isen || !r_getp || !r_geti || !r_en || !r_dis) {
    __android_log_print(6, TAG, "dlsym failed"); r_draw = 0; return 0; }
  __android_log_print(4, TAG, "wrapper active (real glDrawArrays=%p)", r_draw);
  return 1;
}

__attribute__((visibility("default")))
void glDrawArrays(GLenum mode, GLint first, GLsizei count) {
  if (!init()) return;
  unsigned off = 0; calls++;
  for (unsigned i = 0; i < NA; i++) {
    if (!r_isen(A[i].cap)) continue;
    void *p = (void *)1; r_getp(A[i].ptr, &p);
    if (p) continue;
    GLint b = 0; r_geti(A[i].buf, &b);
    if (b) continue;
    r_dis(A[i].cap); off |= 1u << i;
    if (logged[i] < 5) { logged[i]++;
      __android_log_print(5, TAG, "draw #%u mode=%u first=%d count=%d: %s array enabled with NULL pointer -> disabled for this draw",
                          calls, mode, first, count, A[i].n); }
  }
  r_draw(mode, first, count);
  for (unsigned i = 0; i < NA; i++) if (off & (1u << i)) r_en(A[i].cap);
}

__attribute__((constructor)) static void ctor(void) {
  __android_log_print(4, TAG, "libGLESv1_TG.so loaded (Tango32 v1.0)");
}
