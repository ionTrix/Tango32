#!/bin/bash
# Build Tango32 Test v1.0 + v2.0 (key A) and v1.0-B + v3.0-B (key B, for signature-mismatch tests): bash build_testapp.sh <toolsdir>
set -e; A=$(cd "$(dirname "$0")" && pwd); T=$1; O=$A/out; rm -rf $O; mkdir -p $O/cls $O/dex $O/lib/armeabi-v7a
clang --target=armv7a-linux-androideabi21 -mthumb -fPIC -nostdlib -ffreestanding -fuse-ld=lld -O2 -shared \
  -Wl,-soname,libtango32test.so -Wl,--hash-style=both -Wl,-z,max-page-size=4096 -o $O/lib/armeabi-v7a/libtango32test.so $A/src/jni/tango32test.c
javac -source 8 -target 8 -bootclasspath $T/android.jar -classpath $T/android.jar -d $O/cls $A/src/java/com/tango32/testapp/Main.java 2>&1 | grep -v "^warning\|^Note\|^1 warning" || true
java -cp $T/r8.jar com.android.tools.r8.D8 --release --min-api 21 --lib $T/android.jar --output $O/dex $O/cls/com/tango32/testapp/*.class
[ -f $A/test.keystore ] || keytool -genkeypair -keystore $A/test.keystore -storepass tango32 -keypass tango32 -alias test \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Tango32 Test" >/dev/null 2>&1
[ -f $A/testB.keystore ] || keytool -genkeypair -keystore $A/testB.keystore -storepass tango32 -keypass tango32 -alias test \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Tango32 Test B" >/dev/null 2>&1
for vk in 1:A:1.0 2:A:2.0 1:B:1.0-B 3:B:3.0-B; do
  v=${vk%%:*}; k=${vk#*:}; n=${k#*:}; k=${k%%:*}; ks=$A/test.keystore; [ $k = B ] && ks=$A/testB.keystore
  cat > $O/AndroidManifest.xml <<M
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.tango32.testapp">
  <application android:label="Tango32 Test" android:extractNativeLibs="true">
    <activity android:name=".Main" android:exported="true">
      <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
  </application>
</manifest>
M
  $T/aapt2 link -o $O/v$v.apk -I $T/android.jar --manifest $O/AndroidManifest.xml \
    --min-sdk-version 21 --target-sdk-version 22 --version-code $v --version-name $n
  (cd $O/dex && zip -qX $O/v$v.apk classes.dex) && (cd $O && zip -qX $O/v$v.apk lib/armeabi-v7a/libtango32test.so)
  jarsigner -keystore $ks -storepass tango32 -keypass tango32 -sigalg SHA256withRSA -digestalg SHA-256 \
    -signedjar $O/Tango32Test-v$n.apk $O/v$v.apk test >/dev/null
done
ls -l $O/*.apk
