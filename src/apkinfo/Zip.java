// Zip.java — Tango32 log bundler (v1.0, 2026-11-07 23:10 ET). Android has no zip tool; java.util.zip does.
// Run: CLASSPATH=apkinfo.jar app_process /system/bin com.tango32.Zip OUT.zip FILE...
// Each FILE is stored under its base name; missing files are skipped. Exit 1 if nothing was written.
package com.tango32;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class Zip {
    public static void main(String[] a) throws Exception {
        if (a.length < 2) { System.err.println("usage: Zip OUT.zip FILE..."); System.exit(2); }
        int n = 0;
        byte[] buf = new byte[65536];
        try (ZipOutputStream z = new ZipOutputStream(new FileOutputStream(a[0]))) {
            for (int i = 1; i < a.length; i++) {
                File f = new File(a[i]);
                if (!f.isFile()) continue;
                ZipEntry e = new ZipEntry(f.getName());
                e.setTime(f.lastModified());
                z.putNextEntry(e);
                try (FileInputStream in = new FileInputStream(f)) {
                    for (int r; (r = in.read(buf)) > 0; ) z.write(buf, 0, r);
                }
                z.closeEntry();
                n++;
            }
        }
        if (n == 0) { new File(a[0]).delete(); System.exit(1); }
    }
}
