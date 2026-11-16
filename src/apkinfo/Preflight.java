// Preflight.java — Tango32 pre-flight check (v1.1, 2026-11-15 ET)
// Reads each 32-bit APK's native libs (lib/armeabi-v7a, else lib/armeabi), lists the Android functions they import
// that this phone doesn't have, and matches app patch families:
//   type=symbol    certain match: the lib (lib=, or any with lib=*) has needed= as NEEDED, imports one of
//                  match_symbol= that is missing here, and the family's wrapper exports every function missing
//                  from that lib -> Action applies it on its own after the install.
//   type=behavior  weak match: lib + needed (+ one match_symbol, if set) -> Action offers to try it.
// Run (root, app_process like ApkInfo):
//   CLASSPATH=apkinfo.jar app_process /system/bin com.tango32.Preflight <cache> <extra> <famdir>...  < apk paths
//   famdir = a folder of families (<id>/patch.prop + wrapper .so): bundled first, online second (higher rev wins).
//   extra  = anything that changes the answers (firmware fingerprint + module versionCode): part of the cache key.
// Output, one line per APK (TSV): path  missing  example  symbol_ids  behavior_ids
//   missing = functions/libs still missing after the symbol matches ("" = not a 32-bit APK or unreadable),
//   example = "<lib>: <first missing name>", ids = comma lists.
// Missing = imported GLOBAL (not weak) undefined symbol found in none of: the app's own libs, the NEEDED closure of
//   that lib in the phone's 32-bit system dirs (TANGO32_SYSLIB = colon list overrides them, for desktop tests).
// Cache: one line per APK keyed by path|size|mtime|families+extra hash; only current APKs are written back.
package com.tango32;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public final class Preflight {
    static final String[] SYS = {
        "/system/lib", "/apex/com.android.runtime/lib/bionic", "/apex/com.android.runtime/lib",
        "/apex/com.android.i18n/lib", "/dev/tango32_cn/com.android.art/lib", "/apex/com.android.art/lib",
        "/system_ext/lib", "/product/lib" };
    static final int MAX_LIB = 64 * 1024 * 1024;

    // --- ELF32 little-endian: NEEDED, defined exports, undefined GLOBAL imports ---
    static final class Elf {
        final List<String> needed = new ArrayList<String>();
        final Set<String> exports = new HashSet<String>(), imports = new TreeSet<String>();
        boolean ok;
    }
    static int u16(byte[] b, long o) { int i = (int) o; return (b[i] & 0xff) | (b[i + 1] & 0xff) << 8; }
    static long u32(byte[] b, long o) { int i = (int) o; return (b[i] & 0xffL) | (b[i + 1] & 0xffL) << 8 | (b[i + 2] & 0xffL) << 16 | (b[i + 3] & 0xffL) << 24; }
    static String cstr(byte[] b, long o) {
        int i = (int) o, e = i; while (e < b.length && b[e] != 0) e++;
        return new String(b, i, e - i, java.nio.charset.StandardCharsets.ISO_8859_1);
    }

    static Elf parse(byte[] b) {
        Elf r = new Elf();
        try {
            if (b.length < 52 || b[0] != 0x7f || b[1] != 'E' || b[2] != 'L' || b[3] != 'F' || b[4] != 1 || b[5] != 1) return r;
            // program headers: vaddr -> file offset (PT_LOAD), PT_DYNAMIC
            long phoff = u32(b, 0x1c); int phes = u16(b, 0x2a), phn = u16(b, 0x2c);
            List<long[]> loads = new ArrayList<long[]>(); long dynOff = -1, dynSz = 0;
            for (int i = 0; i < phn; i++) {
                long p = phoff + (long) i * phes; long t = u32(b, p);
                if (t == 1) loads.add(new long[] { u32(b, p + 8), u32(b, p + 4), u32(b, p + 16) });   // vaddr, off, filesz
                else if (t == 2) { dynOff = u32(b, p + 4); dynSz = u32(b, p + 16); }
            }
            if (dynOff < 0) return r;
            long strtab = 0, symtab = 0, hash = 0, gnuhash = 0, strsz = 0; List<Long> need = new ArrayList<Long>();
            for (long p = dynOff; p + 8 <= dynOff + dynSz; p += 8) {
                long tag = u32(b, p), val = u32(b, p + 4);
                if (tag == 0) break;
                if (tag == 1) need.add(val); else if (tag == 5) strtab = val; else if (tag == 6) symtab = val;
                else if (tag == 4) hash = val; else if (tag == 0x6ffffef5L) gnuhash = val; else if (tag == 10) strsz = val;
            }
            long str = v2o(loads, strtab), sym = v2o(loads, symtab);
            if (str < 0 || sym < 0) return r;
            for (long n : need) {   // old NDK builds wrote full paths; the linker uses the base name (targetSdk < 23)
                String nn = cstr(b, str + n); int sl = nn.lastIndexOf('/'); r.needed.add(sl >= 0 ? nn.substring(sl + 1) : nn); }
            long nsym = -1;
            // section headers give the exact .dynsym size; else DT_HASH nchain; else count from DT_GNU_HASH
            long shoff = u32(b, 0x20); int shes = u16(b, 0x2e), shn = u16(b, 0x30);
            if (shoff > 0 && shes == 40 && shoff + (long) shn * 40 <= b.length)
                for (int i = 0; i < shn; i++) { long s = shoff + (long) i * 40; if (u32(b, s + 4) == 11 && u32(b, s + 16) == sym) nsym = u32(b, s + 20) / 16; }
            if (nsym < 0 && hash != 0) { long h = v2o(loads, hash); if (h >= 0) nsym = u32(b, h + 4); }
            if (nsym < 0 && gnuhash != 0) nsym = gnuCount(b, v2o(loads, gnuhash));
            if (nsym < 0) return r;
            for (long i = 1; i < nsym; i++) {
                long s = sym + i * 16; if (s + 16 > b.length) break;
                long nm = u32(b, s); int info = b[(int) s + 12] & 0xff, other = b[(int) s + 13] & 3, shndx = u16(b, s + 14);
                if (nm == 0) continue;
                String name = cstr(b, str + nm); int bind = info >> 4;
                if (shndx == 0) { if (bind == 1) r.imports.add(name); }
                else if ((bind == 1 || bind == 2) && (other == 0 || other == 3)) r.exports.add(name);
            }
            r.ok = true;
        } catch (RuntimeException e) { r.ok = false; }
        return r;
    }
    static long v2o(List<long[]> loads, long va) {
        for (long[] l : loads) if (va >= l[0] && va < l[0] + l[2]) return va - l[0] + l[1];
        return -1;
    }
    static long gnuCount(byte[] b, long h) {
        if (h < 0) return -1;
        long nb = u32(b, h), symoff = u32(b, h + 4), bloom = u32(b, h + 8);
        long buckets = h + 16 + bloom * 4, chains = buckets + nb * 4, max = 0;
        for (long i = 0; i < nb; i++) max = Math.max(max, u32(b, buckets + i * 4));
        if (max < symoff) return symoff;
        while ((u32(b, chains + (max - symoff) * 4) & 1) == 0) max++;
        return max + 1;
    }

    static byte[] read(InputStream in, long hint) throws Exception {
        ByteArrayOutputStream o = new ByteArrayOutputStream(hint > 0 && hint < MAX_LIB ? (int) hint : 65536);
        byte[] buf = new byte[65536]; int n;
        while ((n = in.read(buf)) > 0) { o.write(buf, 0, n); if (o.size() > MAX_LIB) throw new Exception("too big"); }
        return o.toByteArray();
    }

    // --- phone's 32-bit system libs (exports per lib, NEEDED closure) ---
    static String[] sysDirs() { String e = System.getenv("TANGO32_SYSLIB"); return e != null && !e.isEmpty() ? e.split(":") : SYS; }
    static final Map<String, Elf> sysCache = new HashMap<String, Elf>();
    static Elf sys(String name) {
        if (sysCache.containsKey(name)) return sysCache.get(name);
        Elf r = null;
        for (String d : sysDirs()) {
            File f = new File(d, name);
            if (!f.isFile()) continue;
            try (InputStream in = new FileInputStream(f)) { r = parse(read(in, f.length())); } catch (Exception e) { r = null; }
            if (r != null && r.ok) break;
        }
        if (r != null && !r.ok) r = null;
        sysCache.put(name, r);
        return r;
    }

    // --- patch families (bundled + online; higher rev wins) ---
    static final class Fam {
        String id, name, type, lib, needed, wrapper; int rev; Set<String> syms = new HashSet<String>(); Set<String> wexp = new HashSet<String>();
        String sig() { return id + ":" + rev + ":" + type + ":" + lib + ":" + needed + ":" + new TreeSet<String>(syms) + ":" + wexp.size(); }
    }
    static Map<String, String> props(File f) {
        Map<String, String> m = new HashMap<String, String>();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"))) {
            for (String l; (l = r.readLine()) != null; ) { int i = l.indexOf('='); if (!l.startsWith("#") && i > 0 && !m.containsKey(l.substring(0, i))) m.put(l.substring(0, i), l.substring(i + 1)); }
        } catch (Exception e) { }
        return m;
    }
    static Map<String, Fam> families(String[] dirs) {
        Map<String, Fam> fams = new TreeMap<String, Fam>();
        for (String d : dirs) {
            File[] k = new File(d).listFiles(); if (k == null) continue;
            Arrays.sort(k);
            for (File fd : k) {
                File pp = new File(fd, "patch.prop"); if (!pp.isFile() || fd.getName().startsWith(".")) continue;
                Map<String, String> p = props(pp);
                Fam f = new Fam(); f.id = fd.getName(); f.name = p.getOrDefault("name", f.id); f.type = p.getOrDefault("type", "");
                f.lib = p.getOrDefault("lib", ""); f.needed = p.getOrDefault("needed", ""); f.wrapper = p.getOrDefault("wrapper", "");
                try { f.rev = Integer.parseInt(p.getOrDefault("rev", "0").trim()); } catch (Exception e) { f.rev = 0; }
                String ms = p.getOrDefault("match_symbol", "").trim();
                if (!ms.isEmpty()) f.syms.addAll(Arrays.asList(ms.split(" +")));
                if (!(f.type.equals("symbol") || f.type.equals("behavior")) || f.needed.isEmpty() || f.wrapper.isEmpty()) continue;
                Fam old = fams.get(f.id);
                if (old != null && old.rev >= f.rev) continue;
                File w = new File(fd, f.wrapper);
                try (InputStream in = new FileInputStream(w)) { Elf e = parse(read(in, w.length())); if (e.ok) f.wexp.addAll(e.exports); } catch (Exception e) { }
                if (f.type.equals("symbol") && f.wexp.isEmpty()) continue;   // can't prove coverage without the wrapper
                fams.put(f.id, f);
            }
        }
        return fams;
    }

    static String hex(byte[] d, int n) { StringBuilder b = new StringBuilder(); for (int i = 0; i < n; i++) b.append(String.format("%02x", d[i])); return b.toString(); }

    // --- one APK ---
    static String check(String path, Map<String, Fam> fams) {
        Map<String, Elf> libs = new TreeMap<String, Elf>();
        try (ZipFile z = new ZipFile(path)) {
            String dir = null; Set<String> abis = new HashSet<String>();
            for (Enumeration<? extends ZipEntry> e = z.entries(); e.hasMoreElements(); ) {
                String n = e.nextElement().getName();
                if (n.startsWith("lib/") && n.endsWith(".so")) { int i = n.indexOf('/', 4); if (i > 4) abis.add(n.substring(4, i)); }
            }
            if (abis.contains("arm64-v8a")) return "";   // installs as 64-bit: not ours
            if (abis.contains("armeabi-v7a")) dir = "lib/armeabi-v7a/"; else if (abis.contains("armeabi")) dir = "lib/armeabi/";
            if (dir == null) return "";
            for (Enumeration<? extends ZipEntry> e = z.entries(); e.hasMoreElements(); ) {
                ZipEntry en = e.nextElement(); String n = en.getName();
                if (!n.startsWith(dir) || !n.endsWith(".so") || n.indexOf('/', dir.length()) >= 0) continue;
                try (InputStream in = z.getInputStream(en)) { Elf el = parse(read(in, en.getSize())); if (el.ok) libs.put(n.substring(dir.length()), el); }
                catch (Exception x) { }
            }
        } catch (Exception e) { return ""; }
        if (libs.isEmpty()) return "";
        Set<String> appExp = new HashSet<String>(); for (Elf e : libs.values()) appExp.addAll(e.exports);

        Set<String> symIds = new TreeSet<String>(), behIds = new TreeSet<String>();
        String example = ""; int residual = 0;
        for (Map.Entry<String, Elf> le : libs.entrySet()) {
            String ln = le.getKey(); Elf el = le.getValue();
            // exports reachable from this lib: app libs + NEEDED closure in the system dirs
            Set<String> have = new HashSet<String>(appExp), missLibs = new LinkedHashSet<String>();
            ArrayList<String> q = new ArrayList<String>(el.needed); Set<String> seen = new HashSet<String>();
            for (int i = 0; i < q.size(); i++) {
                String n = q.get(i); if (!seen.add(n)) continue;
                if (libs.containsKey(n)) { q.addAll(libs.get(n).needed); continue; }
                Elf s = sys(n);
                if (s == null) { if (el.needed.contains(n)) missLibs.add(n); continue; }
                have.addAll(s.exports); q.addAll(s.needed);
            }
            Set<String> miss = new TreeSet<String>();
            for (String s : el.imports) if (!have.contains(s)) miss.add(s);
            // families for this lib
            boolean covered = false;
            for (Fam f : fams.values()) {
                if (!(f.lib.equals("*") || f.lib.equals(ln)) || !el.needed.contains(f.needed)) continue;
                boolean symHit = false; for (String s : f.syms) if (el.imports.contains(s)) { symHit = true; break; }
                if (f.type.equals("behavior")) { if (f.syms.isEmpty() || symHit) behIds.add(f.id); continue; }
                boolean missHit = false; for (String s : f.syms) if (miss.contains(s)) { missHit = true; break; }
                if (missHit && f.wexp.containsAll(miss)) {
                    symIds.add(f.id); covered = true;
                    missLibs.remove(f.needed);   // the wrapper takes its place
                }
            }
            int left = (covered ? 0 : miss.size()) + missLibs.size();
            if (left > 0 && example.isEmpty())
                example = ln + ": " + (!missLibs.isEmpty() ? missLibs.iterator().next() : miss.iterator().next());
            residual += left;
        }
        return residual + "\t" + example + "\t" + String.join(",", symIds) + "\t" + String.join(",", behIds);
    }

    public static void main(String[] a) {
        int rc = 0;
        try {
            if (a.length < 2) { System.out.println("usage: Preflight <cache> <extra> <famdir>... < apk paths"); Runtime.getRuntime().halt(1); }
            File cf = new File(a[0]);
            Map<String, Fam> fams = families(Arrays.copyOfRange(a, 2, a.length));
            StringBuilder sb = new StringBuilder(a[1]); for (Fam f : fams.values()) sb.append('|').append(f.sig());
            for (String d : sysDirs()) sb.append('|').append(d);
            String sig = hex(MessageDigest.getInstance("SHA-256").digest(sb.toString().getBytes("UTF-8")), 8);
            Map<String, String> cache = new HashMap<String, String>(), keep = new TreeMap<String, String>();
            if (cf.isFile()) try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(cf), "UTF-8"))) {
                for (String l; (l = r.readLine()) != null; ) { int i = l.indexOf('\t'); if (i > 0) cache.put(l.substring(0, i), l.substring(i + 1)); }
            } catch (Exception e) { }
            BufferedReader r = new BufferedReader(new InputStreamReader(System.in, "UTF-8"));
            for (String path; (path = r.readLine()) != null; ) {
                path = path.trim(); if (path.isEmpty()) continue;
                File f = new File(path);
                String key = path + "|" + f.length() + "|" + f.lastModified() + "|" + sig;
                String res = cache.get(key);
                if (res == null) res = check(path, fams);
                keep.put(key, res);
                System.out.println(path + "\t" + (res.isEmpty() ? "\t\t\t" : res));
                System.out.flush();
            }
            File tmp = new File(cf.getPath() + ".tmp");
            if (cf.getParentFile() != null) cf.getParentFile().mkdirs();
            try (Writer w = new OutputStreamWriter(new FileOutputStream(tmp), "UTF-8")) {
                for (Map.Entry<String, String> e : keep.entrySet())
                    if (e.getKey().indexOf('\n') < 0 && e.getKey().indexOf('\t') < 0) w.write(e.getKey() + "\t" + e.getValue() + "\n");
            }
            tmp.renameTo(cf);
        } catch (Throwable t) { rc = 1; }
        System.out.flush();
        Runtime.getRuntime().halt(rc);
    }
}
