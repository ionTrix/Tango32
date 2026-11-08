# shim_edit.py (Tango32 v1.0, 2026-11-07 23:10 ET)
# Edits baksmali'd US framework classes so the CN 32-bit native libs (16.0.3.500) work against them:
#  - US-only natives -> Java bodies (forward to a CN-signature native, or return a default)
#  - add CN-signature native declarations (registered by stock CN libandroid_runtime.so)
#  - add Java callbacks the CN libs look up by name
#  - ZygoteInit: HttpEngine preload catch widened; TangoFdFix.run() before runSelectLoop
# Usage: python3 -I shim_edit.py <smali_root>   (baksmali output of the target classes, one tree)
import sys, os, re
R = sys.argv[1]

def default_ret(ret):
    if ret == 'V': return '    return-void'
    if ret in 'JD': return '    const-wide/16 v0, 0x0\n    return-wide v0'
    if ret[0] in 'L[': return '    const/4 v0, 0x0\n    return-object v0'
    return '    const/4 v0, 0x0\n    return v0'

def body_forward(target, n, ret):  # pass p0..p(n-1) unchanged
    call = '    invoke-static/range {p0 .. p%d}, %s' % (n - 1, target)
    if ret == 'V': return call + '\n    return-void'
    if ret in 'JD': return call + '\n    move-result-wide v0\n    return-wide v0'
    if ret[0] in 'L[': return call + '\n    move-result-object v0\n    return-object v0'
    return call + '\n    move-result v0\n    return v0'

done = []
def edit(path, natives_to_java, add_natives=(), add_methods=()):
    p = os.path.join(R, path); s = open(p).read()
    cls = re.search(r'^\.class .*?(L[^;]+;)', s, re.M).group(1)
    for name, sig, body in natives_to_java:
        rx = re.compile(r'^\.method ([^\n]*?)native ([^\n]*?)%s%s\n(?:    \.annotation[^\n]*\n    \.end annotation\n)?\.end method' % (re.escape(name), re.escape(sig)), re.M)
        m = rx.search(s); assert m, '%s: native %s%s not found' % (path, name, sig)
        ret = sig[sig.index(')') + 1:]
        new = '.method %s%s%s%s\n    .locals 2\n%s\n.end method' % (m.group(1), m.group(2), name, sig, body(cls, ret))
        s = s[:m.start()] + new + s[m.end():]; done.append('%s.%s%s -> java' % (cls, name, sig))
    extra = ''
    for mods, name, sig in add_natives:
        assert not re.search(r'^\.method [^\n]* %s%s$' % (re.escape(name), re.escape(sig)), s, re.M), 'already has %s%s' % (name, sig)
        extra += '\n.method %s native %s%s\n.end method\n' % (mods, name, sig); done.append('%s.%s%s +native' % (cls, name, sig))
    for txt in add_methods:
        extra += '\n' + txt + '\n'; done.append('%s +%s' % (cls, txt.splitlines()[0]))
    open(p, 'w').write(s.rstrip('\n') + '\n' + extra)

SC = 'Landroid/view/SurfaceControl;'
noop = lambda cls, ret: default_ret(ret)
fwd = lambda tgt, n: (lambda cls, ret: body_forward(tgt, n, ret))

# --- framework.jar ---
edit('android/view/SurfaceControl.smali',
     [('nativeMirrorSurface', '(JJ)J', fwd(SC + '->nativeMirrorSurface(J)J', 2)),               # (mirrorOf, stopAt) -> (mirrorOf)
      ('nativeSetCornerRadiusExt', '(JJFFI)V', fwd(SC + '->nativeSetCornerRadiusExt(JJFF)V', 6)),
      ('nativeSetEdrSdrRatio', '(JJFZ)V', fwd(SC + '->nativeSetEdrSdrRatio(JJF)V', 5)),
      ('nativeSetFwOptMode', '(JJI)V', noop),
      ('nativeSetTransformMatrix4x4', '(JJ[F)V', noop),
      ('nativeAddOnColorPickedListener', '(JJLandroid/view/SurfaceControl$OnColorPickedListener;)V', noop)],
     add_natives=[('private static', 'nativeMirrorSurface', '(J)J'),
                  ('private static', 'nativeSetCornerRadiusExt', '(JJFF)V'),
                  ('private static', 'nativeSetEdrSdrRatio', '(JJF)V')])

edit('android/hardware/SystemSensorManager$BaseEventQueue.smali', [],
     add_methods=['''.method protected dispatchSensorEventWithType(I[FIJII)V
    .locals 0
    invoke-virtual/range {p0 .. p5}, Landroid/hardware/SystemSensorManager$BaseEventQueue;->dispatchSensorEvent(I[FIJ)V
    return-void
.end method'''])

edit('android/graphics/BaseCanvas.smali',
     [('nDrawSmoothRoundRect16', '(JFFFFFFJF)V', fwd('Landroid/graphics/BaseCanvas;->nDrawRoundRect(JFFFFFFJ)V', 10))])

edit('android/graphics/Bitmap.smali',
     [('nativeSetCallStackStr', '(JLjava/lang/String;)V', noop)])

edit('android/graphics/HardwareRenderer.smali',
     [('nAcquireLastQueuedBuffer', '(Landroid/view/Surface;Landroid/graphics/HardwareRenderer$CopyRequest;)V', noop),
      ('nPushStagingAndDrawForAnimator', '(JJJ[JI)V', noop)])

edit('android/graphics/RenderEffect.smali',
     [('nativeCreateKawaseBlurEffect', '(FJ)J', lambda cls, ret:
       '    const/4 v0, 0x3\n'                       # Shader.TileMode.DECAL
       '    invoke-static {p0, p0, p1, p2, v0}, Landroid/graphics/RenderEffect;->nativeCreateBlurEffect(FFJI)J\n'
       '    move-result-wide v0\n    return-wide v0')])

edit('com/android/internal/os/ApplicationSharedMemory.smali',
     [('nativeEnableOplusState', '(JZZ)V', noop),
      ('nativeGetOplusState', '(JZ)J', noop),
      ('nativeReadOplusFeaturesCache', '(JZ)[I', lambda cls, ret: '    const/4 v0, 0x0\n    new-array v0, v0, [I\n    return-object v0'),
      ('nativeWriteOplusFeaturesCache', '(J[IZ)V', noop)])

# --- oplus-framework.jar ---
edit('android/view/OplusRenderNodeAnimator.smali',
     [('nSetPulseByVsync', '(JZ)V', noop)],
     add_methods=['''.method private static invokeSendSkipFrame(Z)V
    .locals 0
    return-void
.end method'''])

edit('com/oplus/uifirst/OplusUIFirstManager.smali',
     [('nNotifyStartUpStage', '(IIILjava/lang/String;)V', noop),
      ('nativeBinderSetThreadUxFlagByIoctl', '(II)I', noop),
      ('nativeCtrlKpWindowChanged', '(II)I', noop),
      ('nativeLockBoostHint', '(Z)I', noop)])

# --- ZygoteInit: HttpEngine (Cronet) preload needs a 32-bit libhttpengine.so that no CN tethering APEX has.
#     The stock try/catch only catches NoSuchMethodError; widen it to Throwable (failure is just logged).
p = os.path.join(R, 'com/android/internal/os/ZygoteInit.smali'); s = open(p).read()
rx = re.compile(r'(invoke-static \{\}, Landroid/net/http/HttpEngine;->preload\(\)V\n    :try_end_\w+\n    \.catch )Ljava/lang/NoSuchMethodError;')
s, n = rx.subn(r'\1Ljava/lang/Throwable;', s); assert n == 1, 'HttpEngine.preload catch not found'
done.append('ZygoteInit.preload: HttpEngine catch -> Throwable')
# --- ZygoteInit.main: TangoFdFix.run() right before runSelectLoop (class added in [3c]). Register-free call.
rx = re.compile(r'(?m)^(    invoke-virtual \{[^}]*\}, Lcom/android/internal/os/ZygoteServer;->runSelectLoop\()')
s, n = rx.subn('    invoke-static {}, Lcom/android/internal/os/TangoFdFix;->run()V\n\n' + r'\1', s); assert n == 1, 'runSelectLoop call not found'
open(p, 'w').write(s); done.append('ZygoteInit.main: TangoFdFix.run() before runSelectLoop')

print(len(done), 'shim edits')
