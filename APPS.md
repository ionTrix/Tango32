# Tango32 app compatibility
<!-- Updated: 2026-11-15 (Solarmax 2) -->

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
| 🩹 | Solarmax 2 | 1.1.3 | Action | | Patch `Old Adobe AIR fix` (needs a module built from v1.1 or later): the 2015 Adobe AIR engine crashed on launch because Android 9 removed media functions it needs. Music and sound work |
| ✅ | Battle for Wesnoth | 1.14.5-53 | Action | F-Droid | Downloads game data on first start |
| ⏳ | Quake2 | 1.91 | Action | F-Droid | Needs `pak0.pak` (Quake 2 demo) |
| ❌ | Kwaak3 | 1.0 | Action | F-Droid | Sound on: crashes (its audio code passes a bad buffer offset to Java). Sound off: reaches the menu, but touch can't select anything |

## Patches
Some apps need a small fix to run under Tango. Each one lives in `src/patches/<package>/` (our code only: a wrapper
library + `patch.prop`); nothing from the app is shipped. The patch changes a few bytes in the installed app on
your phone so it loads the wrapper.

- **Automatic:** Action applies it right after installing the app (🩹 mark in the list); at every boot Tango32
  re-applies any patch an app update removed.
- **By hand** (Termux): `su -c sh /data/adb/modules/tango32/patches/apply.sh` lists patches and their state;
  add the package name to apply (`… apply.sh com.galcon.fusion`), or `… <package> undo` to remove.
