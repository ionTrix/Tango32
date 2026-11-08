# Changelog
<!-- Updated: 2026-11-07 23:30 ET (v1.0) -->

Each version is a git tag (`v1.x`). Release notes on GitHub are copied from here.
No prebuilt modules are published — build from source (see README).

## v1.0 — 2026-11-07
First public release: 32-bit-only apps and games run on the OnePlus 12 NA (CPH2583, OxygenOS 16.0.10.601)
through OnePlus's own Tango 32→64-bit translator, which ships enabled only on the Chinese ROM.
- **How:** CN 32-bit libraries (pruned, ~141 MB zip) and APEX libs, a 32-bit zygote in a private mount
  namespace, a framework shim for the CN/US mismatch, and a graphics bridge so CN libgui talks to the US
  SurfaceFlinger. The 64-bit system is left alone.
- **Install:** most 32-bit APKs install normally from any file manager. Old apps Android refuses
  (targetSdk < 24 on Android 15+, < 23 on 14) install through the module's **Action** button.
- **Action:** volume-key APK picker for `sdcard/Tango32` (created at install, with a `README.txt`).
  Press = scroll, hold one key 1 s = install, hold Vol+ and Vol− 5 s = save bug report logs.
  Marks ⬛ available · ✅ installed · 🔼 update · 🔽 downgrade · 🔀 mismatched signatures · ✅+🩹 patched.
  Downgrades and signature mismatches ask first (hold Vol+ = Yes, Vol− = No; taps are ignored).
- **App patches** (`src/patches/`, list in `APPS.md`): small per-app fixes applied on the phone; nothing
  from the app is shipped. First: **Galcon Fusion GL fix**. Re-applied at boot if an app update removed it.
- **Safety:** `build.sh` refuses fw from other models or untested firmware (`ALLOW_UNTESTED=1` overrides);
  the installer changes nothing unless model and exact build fingerprint match. Every boot re-checks the
  fingerprint: after an OTA the module turns itself off (⛔ in Magisk, Action hidden) until rebuilt.
- **Logs:** `sdcard/Tango32/tango32_logs.zip` — boot report, error check with crash (tombstone) summaries;
  bug report logs add crash lines, the last 4000 log lines and Tango-related lines (not the full logcat).
- **Uninstall:** removes the module and its own files in `sdcard/Tango32` (your APKs stay).
- **Build:** source-only kit (`pull_fw.sh`, `build.sh`, Linux/WSL2) with a step-by-step guide for beginners
  (`docs/BUILD.md`). CN firmware from your own copy (`CN_LOCAL`), a mirror (`CN_MIRROR`) or the sources in
  `src/cn/mirrors.txt`, always checked against the SHA-256 pinned in `src/cn/cn.sha256`.
- **Supported:** OnePlus 12 NA (CPH2583), latest verified firmware (16.0.10.601), Magisk.
- **Repo:** GPL-3.0, issue forms (Bug, App report), `APPS.md` tested-app list, GitHub Sponsors + Ko-fi.
  Module versionCode = major×100 + minor (v1.0 = 100).
