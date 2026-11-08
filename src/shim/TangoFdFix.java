// TangoFdFix.java (Tango32 v1.0, 2026-11-07 23:10 ET)
// Tango32 shim: runs in the 32-bit zygote right before runSelectLoop (after initNativeState's
// unshare). Safety net for fds whose /proc/self/fd path doesn't stat back to the same file
// (mount-relative paths like "/core-oj.jar" from a detached mount): reopen from the real path,
// matched by st_dev/st_ino, and dup2 into place. trace_marker fds always -> /dev/null (atrace
// writes become no-ops; avoids the fork-time "Not allowlisted (N): /trace_marker" abort).
// The main fix for detached mounts is the wrapper's namespace holder.
package com.android.internal.os;

import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import android.util.Log;
import java.io.File;
import java.io.FileDescriptor;
import java.util.ArrayList;
import java.util.List;

final class TangoFdFix {
    private static final String T = "tango32";
    private static List<String> cand;

    private static FileDescriptor fd(int n) throws Exception {
        FileDescriptor f = new FileDescriptor();
        FileDescriptor.class.getDeclaredMethod("setInt$", int.class).invoke(f, n);
        return f;
    }

    private static void addDir(List<String> c, String d) {
        String[] l = new File(d).list();
        if (l != null) for (String x : l) c.add(d + "/" + x);
    }

    private static List<String> candidates() {
        List<String> c = new ArrayList<String>();
        for (String v : new String[] {"BOOTCLASSPATH", "DEX2OATBOOTCLASSPATH", "SYSTEMSERVERCLASSPATH"}) {
            String e = System.getenv(v);
            if (e != null) for (String x : e.split(":")) if (x.length() > 0) c.add(x);
        }
        addDir(c, "/system/framework"); addDir(c, "/system_ext/framework"); addDir(c, "/product/framework");
        addDir(c, "/system/fonts"); addDir(c, "/product/fonts"); addDir(c, "/system/usr/icu");
        String[] ap = new File("/apex").list();
        if (ap != null) for (String a : ap) {
            if (a.indexOf('@') >= 0) continue;
            addDir(c, "/apex/" + a + "/javalib");
            addDir(c, "/apex/" + a + "/etc");
            addDir(c, "/apex/" + a + "/etc/icu");
            addDir(c, "/apex/" + a + "/etc/tz");
            addDir(c, "/apex/" + a + "/etc/fonts");
        }
        return c;
    }

    private static String find(StructStat st) {
        if (cand == null) cand = candidates();
        for (String c : cand) {
            try {
                StructStat p = Os.stat(c);
                if (p.st_dev == st.st_dev && p.st_ino == st.st_ino) return c;
            } catch (Throwable e) { }
        }
        return null;
    }

    static void run() {
        int fixed = 0, bad = 0;
        String[] fds = new File("/proc/self/fd").list();
        if (fds == null) { Log.w(T, "TangoFdFix: cannot list /proc/self/fd"); return; }
        for (String s : fds) {
            int n;
            try { n = Integer.parseInt(s); } catch (Throwable e) { continue; }
            String r;
            try { r = Os.readlink("/proc/self/fd/" + s); } catch (Throwable e) { continue; }
            if (!r.startsWith("/") || r.startsWith("/dev/") || r.startsWith("/memfd:") || r.startsWith("/proc/")) continue;
            try {
                FileDescriptor f = fd(n);
                StructStat st = Os.fstat(f);
                boolean reg = OsConstants.S_ISREG(st.st_mode);
                if (!reg && !OsConstants.S_ISCHR(st.st_mode)) continue;
                boolean ok = false;
                try { StructStat p = Os.stat(r); ok = p.st_dev == st.st_dev && p.st_ino == st.st_ino; } catch (Throwable e) { }
                if (ok && !r.endsWith("trace_marker")) continue;
                String real = r.endsWith("trace_marker") ? "/dev/null" : find(st);
                if (real == null) {
                    bad++;
                    Log.w(T, "fd " + n + " (" + r + ") unresolved dev=" + st.st_dev + " ino=" + st.st_ino);
                    continue;
                }
                boolean devnull = "/dev/null".equals(real);
                int fdfl = Os.fcntlInt(f, OsConstants.F_GETFD, 0);
                int acc = devnull ? OsConstants.O_WRONLY : (Os.fcntlInt(f, OsConstants.F_GETFL, 0) & OsConstants.O_ACCMODE);
                long off = (reg && !devnull) ? Os.lseek(f, 0, OsConstants.SEEK_CUR) : 0;
                FileDescriptor t = Os.open(real, acc | OsConstants.O_CLOEXEC, 0);
                Os.dup2(t, n);
                Os.close(t);
                Os.fcntlInt(f, OsConstants.F_SETFD, fdfl);
                if (off > 0) Os.lseek(f, off, OsConstants.SEEK_SET);
                fixed++;
                Log.i(T, "fd " + n + " (" + r + ") -> " + real);
            } catch (Throwable e) {
                bad++;
                Log.w(T, "fd " + n + " (" + r + "): " + e);
            }
        }
        Log.i(T, "TangoFdFix: fixed " + fixed + ", unresolved " + bad);
    }
}
