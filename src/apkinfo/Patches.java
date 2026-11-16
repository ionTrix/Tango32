// Patches.java — Tango32 online app patches (v1.1, 2026-11-15 ET; batch 3: patch families)
// Fetches the signed patch index from GitHub and downloads new patch families. Run as root via
// app_process (like ApkInfo), by patches.sh:
//   Patches fetch <outdir> <module_vcode> <last_seq> <bundled_dir> <deadline_s>
//   Patches info                                                                  (source URL + key id)
// All families are downloaded (a few small libs), not only ones for installed apps: Action's pre-flight check
//   matches them against APKs that aren't installed yet. Which family goes with which app is decided on the phone.
// fetch:
//   1. GET index.json + index.json.sig over HTTPS (HttpsURLConnection: system CAs, real TLS), max 256 KB.
//   2. Verify the ECDSA P-256 signature with the public key built into this jar (PatchConfig). Bad = change nothing.
//   3. seq lower than last_seq = an old index replayed -> refuse.
//   4. For each family (max 64) with min_module <= module and rev > the local rev (online copy in
//      <outdir>/<id> or bundled copy in <bundled_dir>/<id>, missing rev = 0): download the .so (max 2 MB),
//      check size + SHA-256 + 32-bit ARM ELF, write <outdir>/.<id>.tmp/{patch.prop,<wrapper>}, swap it in.
//   Output (TSV, one line each): NEW|SAME|SKIP  id  name  rev  [why]   then   OK  seq  or   ERR  why
//   Exit 0 = OK, 1 = ERR. Nothing about the phone is sent (plain GETs; filtering happens here).
// Every index field is checked before use (names, lengths, no control characters), so a bad index can't
// write outside <outdir> or inject lines into patch.prop.
package com.tango32;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.net.UnknownHostException;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import javax.net.ssl.SSLException;

public final class Patches {
    static final int MAX_INDEX = 256 * 1024, MAX_SIG = 1024, MAX_SO = 2 * 1024 * 1024, TIMEOUT_MS = 6000;
    static final Pattern PKG = Pattern.compile("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    static final Pattern SO = Pattern.compile("[A-Za-z0-9_.+-]{1,64}\\.so");
    static final Pattern FILE = Pattern.compile("[A-Za-z0-9_.+-]{1,200}\\.so");
    static final Pattern HEX64 = Pattern.compile("[0-9a-f]{64}");
    static final Pattern ID = Pattern.compile("[a-z0-9][a-z0-9-]{1,39}");
    static final Pattern PKGS = Pattern.compile("([A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+)(,[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+)*");
    static final Pattern SYMS = Pattern.compile("[A-Za-z0-9_.$@]{1,200}( [A-Za-z0-9_.$@]{1,200})*");
    static final int MAX_FAMILIES = 64;

    static final class Fail extends Exception { Fail(String m) { super(m); } }

    // --- tiny JSON reader (objects, arrays, strings, integers, true/false/null): enough for index.json ---
    static final class Json {
        final String s; int i;
        Json(String s) { this.s = s; }
        static Object parse(String s) throws Fail {
            Json j = new Json(s); Object v = j.value(0); j.ws();
            if (j.i != s.length()) throw new Fail("bad index (trailing data)");
            return v;
        }
        void ws() { while (i < s.length() && " \t\r\n".indexOf(s.charAt(i)) >= 0) i++; }
        Object value(int depth) throws Fail {
            if (depth > 8) throw new Fail("bad index (too deep)");
            ws(); if (i >= s.length()) throw new Fail("bad index (truncated)");
            char c = s.charAt(i);
            if (c == '{') {
                Map<String, Object> m = new LinkedHashMap<String, Object>(); i++; ws();
                if (peek('}')) { i++; return m; }
                while (true) {
                    ws(); if (!peek('"')) throw new Fail("bad index (key)");
                    String k = str(); ws(); expect(':'); m.put(k, value(depth + 1)); ws();
                    if (peek(',')) { i++; continue; } expect('}'); return m;
                }
            }
            if (c == '[') {
                List<Object> l = new ArrayList<Object>(); i++; ws();
                if (peek(']')) { i++; return l; }
                while (true) { l.add(value(depth + 1)); ws(); if (peek(',')) { i++; continue; } expect(']'); return l; }
            }
            if (c == '"') return str();
            if (s.startsWith("true", i)) { i += 4; return Boolean.TRUE; }
            if (s.startsWith("false", i)) { i += 5; return Boolean.FALSE; }
            if (s.startsWith("null", i)) { i += 4; return null; }
            int b = i; if (peek('-')) i++;
            while (i < s.length() && Character.isDigit(s.charAt(i))) i++;
            if (i == b || (i - b) > 18) throw new Fail("bad index (value)");
            return Long.parseLong(s.substring(b, i));
        }
        boolean peek(char c) { return i < s.length() && s.charAt(i) == c; }
        void expect(char c) throws Fail { if (!peek(c)) throw new Fail("bad index (expected " + c + ")"); i++; }
        String str() throws Fail {
            StringBuilder b = new StringBuilder(); i++;
            while (true) {
                if (i >= s.length()) throw new Fail("bad index (string)");
                char c = s.charAt(i++);
                if (c == '"') return b.toString();
                if (c != '\\') { b.append(c); continue; }
                if (i >= s.length()) throw new Fail("bad index (escape)");
                char e = s.charAt(i++);
                switch (e) {
                    case '"': case '\\': case '/': b.append(e); break;
                    case 'n': b.append('\n'); break; case 't': b.append('\t'); break;
                    case 'r': b.append('\r'); break; case 'b': b.append('\b'); break; case 'f': b.append('\f'); break;
                    case 'u': if (i + 4 > s.length()) throw new Fail("bad index (escape)");
                        b.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; break;
                    default: throw new Fail("bad index (escape)");
                }
            }
        }
    }

    // --- HTTPS GET with a size limit ---
    static byte[] get(String url, int max) throws Fail {
        if (!url.startsWith("https://")) throw new Fail("not an https URL");
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();   // https -> HttpsURLConnection (system CAs)
            c.setConnectTimeout(TIMEOUT_MS); c.setReadTimeout(TIMEOUT_MS);
            c.setInstanceFollowRedirects(true);   // GitHub release files redirect (https -> https only)
            c.setRequestProperty("User-Agent", "Tango32");
            c.setRequestProperty("Cache-Control", "no-cache");
            int code = c.getResponseCode();
            if (code == 404) throw new Fail("not found on the server");
            if (code != 200) throw new Fail("server said " + code);
            if (!c.getURL().getProtocol().equals("https")) throw new Fail("redirected away from https");
            long len = c.getContentLengthLong();
            if (len > max) throw new Fail("file too big");
            try (InputStream in = c.getInputStream()) {
                ByteArrayOutputStream o = new ByteArrayOutputStream();
                byte[] buf = new byte[16384]; int n;
                while ((n = in.read(buf)) > 0) { o.write(buf, 0, n); if (o.size() > max) throw new Fail("file too big"); }
                return o.toByteArray();
            }
        } catch (Fail f) { throw f;
        } catch (UnknownHostException e) { throw new Fail("no network");
        } catch (SocketTimeoutException e) { throw new Fail("timed out");
        } catch (SSLException e) { throw new Fail("secure connection failed");
        } catch (java.net.ConnectException | java.net.NoRouteToHostException e) { throw new Fail("no network");
        } catch (Exception e) { throw new Fail("download failed (" + e.getClass().getSimpleName() + ")");
        } finally { if (c != null) c.disconnect(); }
    }

    static PublicKey key() throws Exception {
        return KeyFactory.getInstance("EC").generatePublic(new X509EncodedKeySpec(Base64.getDecoder().decode(PatchConfig.PUB)));
    }
    static String hex(byte[] d, int n) { StringBuilder b = new StringBuilder(); for (int i = 0; i < n; i++) b.append(String.format("%02x", d[i])); return b.toString(); }
    static String keyId() throws Exception { return hex(MessageDigest.getInstance("SHA-256").digest(Base64.getDecoder().decode(PatchConfig.PUB)), 8); }

    static String str(Map<?, ?> m, String k, int max, boolean need) throws Fail {
        Object v = m.get(k);
        if (v == null) { if (need) throw new Fail("missing " + k); return ""; }
        if (!(v instanceof String)) throw new Fail("bad " + k);
        String s = (String) v;
        if (s.length() > max) throw new Fail("bad " + k);
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) < 32 || s.charAt(i) == 127) throw new Fail("bad " + k);
        return s;
    }
    static long num(Map<?, ?> m, String k) throws Fail {
        Object v = m.get(k); if (!(v instanceof Long)) throw new Fail("bad " + k); return (Long) v;
    }
    static int localRev(File dir) {   // rev= in dir/patch.prop, 0 if none
        File p = new File(dir, "patch.prop");
        if (!p.isFile()) return -1;
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new java.io.FileInputStream(p), "UTF-8"))) {
            String l; while ((l = r.readLine()) != null) if (l.startsWith("rev=")) return Integer.parseInt(l.substring(4).trim());
        } catch (Exception e) { }
        return 0;
    }
    static void rmrf(File f) { File[] k = f.listFiles(); if (k != null) for (File c : k) rmrf(c); f.delete(); }
    static void out(String... f) { System.out.println(String.join("\t", f)); }

    static int fetch(String[] a) throws Exception {
        File outDir = new File(a[1]); long vc = Long.parseLong(a[2]);
        long lastSeq = a[3].isEmpty() ? 0 : Long.parseLong(a[3]); File bundled = new File(a[4]);
        int deadline = Integer.parseInt(a[5]);
        Thread t = new Thread(() -> {   // hard stop: Action never waits long; half-done downloads stay in .tmp dirs
            try { Thread.sleep(deadline * 1000L); } catch (InterruptedException e) { return; }
            out("ERR", "timed out"); System.out.flush(); Runtime.getRuntime().halt(1);
        });
        t.setDaemon(true); t.start();
        outDir.mkdirs();
        File[] old = outDir.listFiles();   // leftovers of an interrupted run
        if (old != null) for (File f : old) if (f.getName().startsWith(".")) rmrf(f);

        String base = PatchConfig.URL.endsWith("/") ? PatchConfig.URL : PatchConfig.URL + "/";
        byte[] idx, sig;
        try { idx = get(base + "index.json", MAX_INDEX); sig = get(base + "index.json.sig", MAX_SIG); }
        catch (Fail f) { out("ERR", f.getMessage()); return 1; }
        Signature v = Signature.getInstance("SHA256withECDSA");
        v.initVerify(key()); v.update(idx);
        boolean good; try { good = v.verify(sig); } catch (Exception e) { good = false; }
        if (!good) { out("ERR", "signature check failed"); return 1; }

        long seq; List<?> list;
        try {
            Object o = Json.parse(new String(idx, "UTF-8"));
            if (!(o instanceof Map)) throw new Fail("bad index");
            Map<?, ?> m = (Map<?, ?>) o;
            if (num(m, "format") != 1) throw new Fail("index format not supported (update Tango32)");
            seq = num(m, "seq");
            Object p = m.get("patches"); if (!(p instanceof List)) throw new Fail("bad index");
            list = (List<?>) p;
        } catch (Fail f) { out("ERR", f.getMessage()); return 1; }
        if (seq < lastSeq) { out("ERR", "old index (seq " + seq + " < " + lastSeq + ")"); return 1; }

        Set<String> seen = new HashSet<String>();
        for (Object po : list) {
            if (!(po instanceof Map)) continue;
            Map<?, ?> p = (Map<?, ?>) po;
            String id, name = "?"; long rev = 0;
            try { id = str(p, "id", 40, true); } catch (Fail f) { continue; }
            if (!ID.matcher(id).matches() || !seen.add(id) || seen.size() > MAX_FAMILIES) continue;
            try {
                name = str(p, "name", 80, true); rev = num(p, "rev");
                String type = str(p, "type", 16, true), pkgs = str(p, "pkgs", 600, false), syms = str(p, "match_symbol", 2000, false);
                long mm = num(p, "min_module"); long size = num(p, "size");
                String lib = str(p, "lib", 64, true), need = str(p, "needed", 64, true), wrap = str(p, "wrapper", 64, true);
                String file = str(p, "file", 200, true), sha = str(p, "sha256", 64, true);
                String tested = str(p, "tested", 80, false), fixes = str(p, "fixes", 600, false);
                if (!(type.equals("symbol") || type.equals("behavior")) || (!pkgs.isEmpty() && !PKGS.matcher(pkgs).matches())
                    || (!syms.isEmpty() && !SYMS.matcher(syms).matches()) || (type.equals("symbol") && syms.isEmpty())
                    || !(lib.equals("*") || SO.matcher(lib).matches()) || !SO.matcher(need).matches() || !SO.matcher(wrap).matches()
                    || need.length() != wrap.length() || !FILE.matcher(file).matches() || !HEX64.matcher(sha).matches()
                    || rev < 1 || rev > 1000000 || size < 52 || size > MAX_SO) throw new Fail("bad entry");
                int local = Math.max(localRev(new File(outDir, id)), localRev(new File(bundled, id)));
                if (rev <= local) { out("SAME", id, name, "" + rev); continue; }
                if (mm > vc) { out("SKIP", id, name, "" + rev, "needs a newer Tango32"); continue; }
                byte[] so = get(base + file, MAX_SO);
                if (so.length != size) throw new Fail("size mismatch");
                if (!hex(MessageDigest.getInstance("SHA-256").digest(so), 32).equals(sha)) throw new Fail("checksum mismatch");
                if (so[0] != 0x7f || so[1] != 'E' || so[2] != 'L' || so[3] != 'F' || so[4] != 1 || so[18] != 40 || so[19] != 0)
                    throw new Fail("not a 32-bit ARM library");
                File tmp = new File(outDir, "." + id + ".tmp"); rmrf(tmp);
                if (!tmp.mkdirs()) throw new Fail("can't write " + outDir);
                try (FileOutputStream f = new FileOutputStream(new File(tmp, wrap))) { f.write(so); }
                try (Writer w = new OutputStreamWriter(new FileOutputStream(new File(tmp, "patch.prop")), "UTF-8")) {
                    w.write("# Tango32 app patch family (online, rev " + rev + ", index seq " + seq + ")\n"
                        + "name=" + name + "\ntype=" + type + "\npkgs=" + pkgs + "\ntested=" + tested + "\nfixes=" + fixes
                        + "\nlib=" + lib + "\nneeded=" + need + "\nwrapper=" + wrap + "\nmatch_symbol=" + syms
                        + "\nrev=" + rev + "\nmin_module=" + mm + "\nsha256=" + sha + "\norigin=online\n");
                }
                File dst = new File(outDir, id), bak = new File(outDir, "." + id + ".old");
                if (dst.exists() && !dst.renameTo(bak)) throw new Fail("can't replace the old copy");
                if (!tmp.renameTo(dst)) { bak.renameTo(dst); throw new Fail("can't save"); }
                rmrf(bak);
                out("NEW", id, name, "" + rev);
            } catch (Fail f) { out("SKIP", id, name, "" + rev, f.getMessage()); }
        }
        out("OK", "" + seq);
        return 0;
    }

    public static void main(String[] a) {
        int rc = 1;
        try {
            if (a.length == 6 && a[0].equals("fetch")) rc = fetch(a);
            else if (a.length == 1 && a[0].equals("info")) { out(PatchConfig.URL, keyId()); rc = 0; }
            else out("ERR", "usage: Patches fetch <outdir> <vcode> <last_seq> <bundled_dir> <deadline_s> | info");
        } catch (Throwable t) { out("ERR", "internal error (" + t.getClass().getSimpleName() + ")"); }
        System.out.flush();
        Runtime.getRuntime().halt(rc);   // app_process: don't wait for runtime threads
    }
}
