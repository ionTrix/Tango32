package android.system; import java.io.FileDescriptor; public final class Os {
 public static String readlink(String p) throws ErrnoException { return null; }
 public static StructStat fstat(FileDescriptor f) throws ErrnoException { return null; }
 public static StructStat stat(String p) throws ErrnoException { return null; }
 public static int fcntlInt(FileDescriptor f, int c, int a) throws ErrnoException { return 0; }
 public static long lseek(FileDescriptor f, long o, int w) throws ErrnoException { return 0; }
 public static FileDescriptor open(String p, int fl, int m) throws ErrnoException { return null; }
 public static FileDescriptor dup2(FileDescriptor o, int n) throws ErrnoException { return null; }
 public static void close(FileDescriptor f) throws ErrnoException {} }
