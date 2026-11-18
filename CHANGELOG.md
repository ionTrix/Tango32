# Changelog
<!-- Updated: 2026-11-18 00:19 ET (v1.2 Unreleased entry) -->

Each version is a git tag (`v1.x`). Release notes on GitHub are copied from here.
No prebuilt modules are published — build from source (see README).

## Unreleased (v1.2)
- **KernelSU / KernelSU Next and APatch support:** the SELinux rules now go through the root manager's own tool,
  live at boot: `magiskpolicy` (Magisk), `ksud sepolicy patch` (KernelSU), `apd sepolicy patch` (APatch).
  `tango32.log` names the tool used. If any rule still fails, the v1.1 guard turns Tango32 off as before; its
  message now reads *⛔ Root manager not supported: SELinux rules failed (see tango32.log)*. No early-boot
  `sepolicy.rule` (it bootlooped in testing). KernelSU: community testing (@arcinin1); APatch: untested.

## v1.1 — 2026-11-17
- **Root-manager guard:** on a root manager other than Magisk (e.g. KernelSU, where `magiskpolicy` is missing)
  Tango32 now turns itself off at boot, hides its Action button and shows *⛔ Root manager not supported yet
  (Magisk only for now)*, instead of starting the 32-bit zygote half set up (crash loop, frozen phone). The boot
  logs are still saved. The zygote wrapper no longer falls back to a "plain start" when its private namespace
  can't be set up. Override at your own risk: `allow_any_root` (README).
- **CPH2581 community-tested:** the build and install guards accept the OnePlus 12 CPH2581 on 16.0.10.601(EX01).
  Big thanks to @arcinin1 for community testing on the CPH2581 and for the KernelSU logs that led to the
  root-manager guard above.
- **Online app patches:** new app patches arrive from GitHub without a new module. Action asks every time it
  opens; it checks only when you say Yes (never at boot). The patch list is signed by CI and checked against a
  key built into the module, plus a SHA-256 per file; nothing about the phone or its apps is sent. Check by hand
  with `patches.sh` (see README). Downloads live in `/data/adb/tango32/` (kept across updates).
- **Patch families:** a patch now fixes a kind of break, not one app. Action's new **pre-flight check** reads
  each 32-bit APK's libraries: `⚠️ Missing Android functions` when the phone lacks some, `🩹 Fix available` when
  a family fits (applied on its own after the install when it covers every missing function).
- **Quick test after install:** after a 5 second pause the app opens and must keep running for 5 seconds, then
  Magisk comes back with the result. The touchscreen is locked while the app is open (unlocks right after,
  40 seconds at most), so a stray tap can't close it. Old apps skip the permission review screen for the test (it comes back afterwards; fresh installs
  get their data cleared). On a failure, matching fixes are auto-patched and tested one after another.
- **No compatibility popups for Action installs:** Android's "built for an older version" and "32-bit app"
  warnings no longer show for apps installed through Action. Apps installed from a file manager still show the
  32-bit warning once (tap OK).
- **Logs folder:** `sdcard/Tango32/logs/` — `tango32_logs.zip` (bug report, files now `1_summary.txt`,
  `2_boot_report.txt`, `3_logcat.txt`, `4_install.log`, each with a numbered Contents list) and `install.log`
  (every Action install and quick test, crash details for failures).
- **New app patch: Old Adobe AIR fix** (Solarmax 2 1.1.3). Adobe AIR games from around 2015 crashed on launch:
  their engine (`libCore.so`) needs Android media functions that Android 9 removed or hid (`MetaData`,
  `MediaBuffer`, `OMXClient`, the old `GraphicBuffer` constructor). The wrapper provides them and turns off
  hardware AAC, so AIR uses its own audio decoder. Thanks to @arcinin1 for suggesting Solarmax on XDA.
- **Action:** an APK that can't be read (damaged or incomplete download) shows `[?bit]` and a hint instead of
  `[64bit]`. A failed install shows Android's real reason (with the APK's file name) instead of the last line
  of a stack trace.
- **Bug report logs:** the last 5 minutes of log instead of the last 4000 lines (only a few seconds on
  OxygenOS), at most 150 lines per log tag so chatty system tags can't push everything else out. The crash
  summary skips a stock OxygenOS ART crash (`FaultManager::HandleFault`, fault addr 0xd) that shows up in
  64-bit processes with or without Tango32.
- **Fix:** one `CANNOT LINK EXECUTABLE "/system/bin/toybox"` error at every boot (the zygote wrapper logged
  after setting `LD_PRELOAD`). Harmless, but it showed up in every bug report.
- **Build:** no more `[: too many arguments` with the CN cache. Release notes: wrapped CHANGELOG lines are
  joined (GitHub shows every newline as a line break).

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
