# Tango32 app compatibility
<!-- Updated: 2026-11-17 18:05 ET (Solarmax 2 APK SHA-256) -->

Apps tested on the OnePlus 12 NA (CPH2583) with Tango32. Report yours with the **App report** issue form.

**Install via:** *Action* = Magisk → Tango32 → Action (old apps Android refuses), *File manager* = tap the APK.
**Status:** ✅ Works · 🩹 Works with a Tango32 patch (applied automatically by Action; shows as ✅+🩹 in Action) · ⏳ Testing · ❌ Doesn't work

| Status | App | Version tested | Install via | Source | Notes |
|---|---|---|---|---|---|
| ✅ | Flappy Bird | 1.3 | Action | | |
| ✅ | Galcon 2 | 1.9.5 | Action | | |
| ✅ | opsu! | 0.16.1a | Action | F-Droid | Rhythm game |
| ✅ | Tanks of Freedom | 0.6.3-beta | Action | F-Droid | |
| ✅ | Heriswap | 2.2.0 | Action | F-Droid | |
| ✅ | Recursive Runner | 3.0.0 | Action | F-Droid | |
| ✅ | Taps Of Fire | 1.0.5 | Action | F-Droid | |
| ✅ | Pyroman: Jaws of Fire | 1.1 | Action | F-Droid | |
| ✅ | TowerJumper | 1.0.8 | File manager | F-Droid | |
| ✅ | Cow's Revenge | 1.0.5 | File manager | F-Droid | |
| 🩹 | Galcon Fusion | 1.0.16.1 | Action | | Patch `Galcon Fusion GL fix`: the game crashed on its first frame (GL texture array left enabled with a NULL pointer) |
| 🩹 | Solarmax 2 | 1.1.3 | Action | | Patch `Old Adobe AIR fix` (needs a module built from v1.1 or later): the 2015 Adobe AIR engine crashed on launch because Android 9 removed media functions it needs. Music and sound work. Tested APK SHA-256 `92e0524ac3c718ea3ba88f79149dda0671bf8b9b82c0962ff07b35dd6057470c` (38,504,960 bytes); avoid repacks such as `Solarmax_2_1.1.3.9.apk` (malware) |
| ✅ | Battle for Wesnoth | 1.14.5-53 | Action | F-Droid | Downloads game data on first start |
| ⏳ | Quake2 | 1.91 | Action | F-Droid | Needs `pak0.pak` (Quake 2 demo) |
| ❌ | Kwaak3 | 1.0 | Action | F-Droid | Sound on: crashes (its audio code passes a bad buffer offset to Java). Sound off: reaches the menu, but touch can't select anything |

## Patches
Some apps need a small fix to run under Tango. Fixes are grouped in **families** (`src/patches/<id>/`: a wrapper
library + `patch.prop`; our code only, nothing from any app is shipped). A family fixes one kind of break, so it
can fix apps nobody has tested yet. The patch changes a few bytes in the installed app on your phone so it loads
the wrapper.

| Family | Type | Known apps | Fixes |
|---|---|---|---|
| `air-old` Old Adobe AIR fix | symbol | Solarmax 2 | Adobe AIR (2015) apps that crash on launch on Android 9+ |
| `gl-null-array` Galcon Fusion GL fix | behavior | Galcon Fusion | Crash on the first frame: GL array left enabled with a NULL pointer |

- **Known apps** (`pkgs=` in `patch.prop`): Action applies the fix right after installing the app (🩹).
- **symbol** families: Action's pre-flight check reads the APK's libraries; when one needs exactly the missing
  Android functions the wrapper provides, the fix is applied on its own (`Successfully patched: … (matched)`).
- **behavior** families: a runtime bug no check can see. If an app with the same libraries fails Action's
  quick test, Action auto-patches it and tests again (removed if it still fails).
- Every app is re-patched at boot if an app update removed the fix. **Online** (v1.1+, when you say Yes in Action):
  new families arrive from GitHub without a module update; a change only reaches phones when `rev=` goes up.
- **By hand** (Termux): `su -c sh /data/adb/modules/tango32/patches/apply.sh` lists patched apps and their state;
  `… apply.sh <package>` applies, `… <package> undo` removes, `… <package> <family> auto` applies a family to
  another app.
- Worked through a match or a try? Please send an **App report** so the app joins the known list.
