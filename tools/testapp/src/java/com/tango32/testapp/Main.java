// Tango32 Test — 2026-11-06 17:00 ET. Minimal 32-bit-only app to test Tango32 (Action install / upgrade / downgrade).
package com.tango32.testapp;

import android.app.Activity;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

public class Main extends Activity {
  static native int bits();     // libtango32test.so: pointer size in bits (32 under Tango)
  static native int answer();   // simple native call that returns 42

  @Override protected void onCreate(Bundle b) {
    super.onCreate(b);
    String ver = "?";
    try { ver = getPackageManager().getPackageInfo(getPackageName(), 0).versionName; } catch (Exception e) { }
    String nat;
    try {
      System.loadLibrary("tango32test");
      nat = "Native code: " + bits() + "-bit ARM, call result " + answer() + "\n\nTango32 works.";
    } catch (Throwable t) {
      nat = "Native code failed to load:\n" + t;
    }
    TextView v = new TextView(this);
    v.setGravity(Gravity.CENTER);
    v.setTextSize(22);
    v.setPadding(40, 40, 40, 40);
    v.setText("Tango32 Test\nversion " + ver + "\n\n" + nat);
    setContentView(v);
  }
}
