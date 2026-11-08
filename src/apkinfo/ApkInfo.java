// ApkInfo.java — Tango32 action helper (v1.0, 2026-11-07 23:10 ET)
// Reads APK paths on stdin, prints one line per APK:
//   path \t package \t versionName \t label \t abis \t versionCode \t targetSdk \t signer
// signer = first 16 hex of SHA-256 of the v1 (JAR) signing certificate ("" = no v1 signature / unreadable).
// targetSdk = uses-sdk targetSdkVersion, else minSdkVersion, else 1 ("" = manifest unreadable).
// abis = comma list of lib/<abi>/ dirs that contain .so files ("" = no native code).
// Run: CLASSPATH=apkinfo.jar app_process /system/bin com.tango32.ApkInfo < list
// Pure reflection (AssetManager.addAssetPath is @hide) so it compiles with a plain JDK.
package com.tango32;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.util.Enumeration;
import java.util.TreeSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public final class ApkInfo {
    static final String NS = "http://schemas.android.com/apk/res/android";

    static String abis(String path) {
        TreeSet<String> s = new TreeSet<String>();
        try (ZipFile z = new ZipFile(path)) {
            Enumeration<? extends ZipEntry> e = z.entries();
            while (e.hasMoreElements()) {
                String n = e.nextElement().getName();
                if (n.startsWith("lib/") && n.endsWith(".so")) {
                    int i = n.indexOf('/', 4);
                    if (i > 4) s.add(n.substring(4, i));
                }
            }
        } catch (Throwable t) { return "?"; }
        return String.join(",", s);
    }

    static String signer(String path) {   // v1 signature block META-INF/*.RSA|DSA|EC (PKCS#7) -> first cert
        try (ZipFile z = new ZipFile(path)) {
            Enumeration<? extends ZipEntry> e = z.entries();
            while (e.hasMoreElements()) {
                ZipEntry en = e.nextElement(); String n = en.getName().toUpperCase();
                if (!n.startsWith("META-INF/") || n.indexOf('/', 9) >= 0) continue;
                if (!(n.endsWith(".RSA") || n.endsWith(".DSA") || n.endsWith(".EC"))) continue;
                try (InputStream in = z.getInputStream(en)) {
                    for (Certificate c : CertificateFactory.getInstance("X.509").generateCertificates(in)) {
                        byte[] d = MessageDigest.getInstance("SHA-256").digest(c.getEncoded());
                        StringBuilder b = new StringBuilder();
                        for (int i = 0; i < 8; i++) b.append(String.format("%02x", d[i]));
                        return b.toString();
                    }
                }
            }
        } catch (Throwable t) { }
        return "";
    }

    static String clean(Object o) {
        if (o == null) return "";
        return o.toString().replace('\t', ' ').replace('\n', ' ').trim();
    }

    static String[] manifest(String path) {
        String pkg = "", ver = "", label = "", code = "", tgt = "";
        try {
            Class<?> amC = Class.forName("android.content.res.AssetManager");
            Object am = amC.getDeclaredConstructor().newInstance();
            Method add = amC.getMethod("addAssetPath", String.class);
            int cookie = (Integer) add.invoke(am, path);
            if (cookie == 0) return new String[] {pkg, ver, label, code, tgt};
            Object p = amC.getMethod("openXmlResourceParser", int.class, String.class).invoke(am, cookie, "AndroidManifest.xml");
            Class<?> pc = Class.forName("android.content.res.XmlResourceParser");
            Class<?> xp = Class.forName("org.xmlpull.v1.XmlPullParser");
            Method next = xp.getMethod("next"), name = xp.getMethod("getName");
            Method val = xp.getMethod("getAttributeValue", String.class, String.class);
            Class<?> as = Class.forName("android.util.AttributeSet");
            Method resv = as.getMethod("getAttributeResourceValue", String.class, String.class, int.class);
            Method intv = as.getMethod("getAttributeIntValue", String.class, String.class, int.class);
            int labelId = 0; String labelRaw = null; int ts = -1, ms = -1; boolean ok = false;
            for (int ev = (Integer) next.invoke(p); ev != 1; ev = (Integer) next.invoke(p)) {
                if (ev != 2) continue;
                String n = (String) name.invoke(p);
                if ("manifest".equals(n)) {
                    ok = true;
                    pkg = clean(val.invoke(p, null, "package"));
                    ver = clean(val.invoke(p, NS, "versionName"));
                    long vc = ((Integer) intv.invoke(p, NS, "versionCode", -1)) & 0xffffffffL;
                    long vm = ((Integer) intv.invoke(p, NS, "versionCodeMajor", 0)) & 0xffffffffL;
                    if (vc != 0xffffffffL) code = Long.toString((vm << 32) | vc);
                } else if ("uses-sdk".equals(n)) {
                    ts = (Integer) intv.invoke(p, NS, "targetSdkVersion", -1);
                    ms = (Integer) intv.invoke(p, NS, "minSdkVersion", -1);
                } else if ("application".equals(n)) {
                    labelId = (Integer) resv.invoke(p, NS, "label", 0);
                    labelRaw = (String) val.invoke(p, NS, "label");
                    break;
                }
            }
            if (ok) tgt = Integer.toString(ts > 0 ? ts : (ms > 0 ? ms : 1));
            if (labelId != 0) {
                Class<?> dm = Class.forName("android.util.DisplayMetrics"), cf = Class.forName("android.content.res.Configuration");
                Class<?> rc = Class.forName("android.content.res.Resources");
                Constructor<?> c = rc.getConstructor(amC, dm, cf);
                Object res = c.newInstance(am, dm.getDeclaredConstructor().newInstance(), cf.getDeclaredConstructor().newInstance());
                label = clean(rc.getMethod("getText", int.class).invoke(res, labelId));
                if (ver.startsWith("@")) ver = "";
            } else if (labelRaw != null && !labelRaw.startsWith("@")) {
                label = clean(labelRaw);
            }
            try { amC.getMethod("close").invoke(am); } catch (Throwable t) { }
        } catch (Throwable t) { }
        return new String[] {pkg, ver, label, code, tgt};
    }

    public static void main(String[] a) throws Exception {
        BufferedReader r = new BufferedReader(new InputStreamReader(System.in, "UTF-8"));
        String path;
        while ((path = r.readLine()) != null) {
            path = path.trim();
            if (path.isEmpty()) continue;
            String[] m = manifest(path);
            System.out.println(path + "\t" + m[0] + "\t" + m[1] + "\t" + m[2] + "\t" + abis(path) + "\t" + m[3] + "\t" + m[4] + "\t" + signer(path));
            System.out.flush();
        }
    }
}
