# Tango32 Test app
<!-- 2026-11-06 17:08 ET -->
Tiny 32-bit-only app (`com.tango32.testapp`, armeabi-v7a native lib, targetSdk 22) for testing Tango32:
it shows its version and the result of a native call ("Native code: 32-bit ARM … Tango32 works").
Key A: v1.0 (code 1), v2.0 (code 2) test install / update / downgrade. Key B (`testB.keystore`): v1.0-B (code 1), v3.0-B (code 3) test the signature-mismatch message.

Build (Linux, clang + lld + JDK): `bash build_testapp.sh <tools>` where `<tools>` holds `aapt2`
(Google Maven `com.android.tools.build:aapt2` linux jar), `android.jar` (platform-23) and `r8.jar`.
Output: `out/Tango32Test-v1.0.apk`, `out/Tango32Test-v2.0.apk` (v1 JAR signature; fine for targetSdk < 30).
`test.keystore` (password `tango32`) is a throwaway test key, kept so rebuilds stay installable over each other.
