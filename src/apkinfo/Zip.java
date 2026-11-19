// Zip.java — Tango32 log bundler (v1.2, 2026-11-19 12:20 ET: -s split; v1.0 2026-11-07). Android has no zip tool; java.util.zip does.
// Run: CLASSPATH=apkinfo.jar app_process /system/bin com.tango32.Zip [-s BYTES] OUT.zip FILE...
// Each FILE is stored under its base name; missing files are skipped. Exit 1 if nothing was written.
// -s BYTES (v1.2, F15): a file starts a new part (OUT.zip, OUT_2.zip, OUT_3.zip …) when the part so far + the file's
//   uncompressed size would pass BYTES (compressed is never bigger -> every part stays under BYTES, unless one file
//   alone is bigger). Each part is a normal zip; logs.sh uses 23 MB (GitHub takes up to 25 MB per file).
//   Files are written in the order given, so put the most important first.
package com.tango32;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class Zip {
    static final class Counting extends FilterOutputStream {
        long n;
        Counting(OutputStream o) { super(o); }
        @Override public void write(int b) throws IOException { out.write(b); n++; }
        @Override public void write(byte[] b, int off, int len) throws IOException { out.write(b, off, len); n += len; }
    }

    static String partName(String out, int part) {
        if (part == 1) return out;
        int dot = out.endsWith(".zip") ? out.length() - 4 : out.length();
        return out.substring(0, dot) + "_" + part + out.substring(dot);
    }

    public static void main(String[] a) throws Exception {
        int i0 = 0; long split = 0;
        if (a.length > 1 && a[0].equals("-s")) { split = Long.parseLong(a[1]); i0 = 2; }
        if (a.length - i0 < 2) { System.err.println("usage: Zip [-s BYTES] OUT.zip FILE..."); System.exit(2); }
        String out = a[i0];
        int n = 0, part = 1, inPart = 0;
        byte[] buf = new byte[65536];
        Counting c = new Counting(new FileOutputStream(partName(out, part)));
        ZipOutputStream z = new ZipOutputStream(c);
        try {
            for (int i = i0 + 1; i < a.length; i++) {
                File f = new File(a[i]);
                if (!f.isFile()) continue;
                if (split > 0 && inPart > 0 && c.n + f.length() > split) {   // would pass the limit -> next part
                    z.close(); part++; inPart = 0;
                    c = new Counting(new FileOutputStream(partName(out, part)));
                    z = new ZipOutputStream(c);
                }
                ZipEntry e = new ZipEntry(f.getName());
                e.setTime(f.lastModified());
                z.putNextEntry(e);
                try (FileInputStream in = new FileInputStream(f)) {
                    for (int r; (r = in.read(buf)) > 0; ) z.write(buf, 0, r);
                }
                z.closeEntry(); z.flush();
                n++; inPart++;
            }
        } finally { z.close(); }
        if (n == 0) { new File(partName(out, 1)).delete(); System.exit(1); }
        if (inPart == 0 && part > 1) new File(partName(out, part)).delete();
    }
}
