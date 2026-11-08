# Building Tango32 — step by step
<!-- Updated: 2026-11-07 23:25 ET (v1.0) -->

This guide assumes you've never built anything before. It takes about 1–2 hours the first time, mostly waiting
for downloads. You need a **Windows 10/11 PC** (or a Linux PC) and your rooted **OnePlus 12 NA (CPH2583)**.

Why build it yourself? Tango32 is made from OnePlus files, which can't be shared. The build takes them from
the public Chinese firmware plus your own phone, then packs a Magisk module made just for your phone.

## Contents
- Before you start
- Step 1: Get your phone's files
- Step 2: Set up the PC (Windows)
- Step 3: Get Tango32
- Step 4: Build
- Step 5: Install on the phone
- If something goes wrong

<!-- §Before you start -->
## Before you start
| Check | How |
|---|---|
| Right phone | Settings → About device → model **CPH2583** |
| Right firmware | Settings → About device → version **16.0.10.601** (others are untested) |
| Rooted with Magisk | The Magisk app opens and shows "Installed" |
| A way back | Keep a copy of your **stock `init_boot.img`** on the PC (from the firmware you're on), and know how to boot to fastboot (Power + Vol−). See the README's *Disable and rescue* |
| PC space | **~25 GB free** on drive C: during the build (most is freed at the end) |
| Internet | ~8 GB to download |

<!-- §Step 1 -->
## Step 1: Get your phone's files
1. Install **Termux** from F-Droid (<https://f-droid.org/packages/com.termux/>). The Play Store version is outdated.
2. Open Termux and type these lines, pressing Enter after each:
   ```
   termux-setup-storage
   pkg install -y curl zip
   curl -LO https://raw.githubusercontent.com/ionTrix/Tango32/main/pull_fw.sh
   sh pull_fw.sh
   ```
   Tap **Allow** when it asks for storage access. Answer `y` if `pkg` asks anything.
3. **You should see:** `Copied NN jars to /sdcard/Download/tango32_fw/fw` and `Made /sdcard/Download/tango32_fw/fw.zip`.
4. Copy **`Download/tango32_fw/fw.zip`** to your PC's **Downloads** folder (USB cable → File transfer, or any way you like).

<!-- §Step 2 -->
## Step 2: Set up the PC (Windows)
Tango32 builds in Linux. Windows has Linux built in (WSL2). Linux PC users: skip to Step 3 (Ubuntu/Debian).

1. Right-click **Start** → **Terminal (Admin)** (or **PowerShell (Admin)**), then type:
   ```
   wsl --install -d Ubuntu
   ```
2. **Restart the PC** when asked. After the restart an **Ubuntu** window opens by itself (if not: Start → Ubuntu).
3. It asks you to make a **username** and **password** (for Linux only; the password doesn't show while you type).

**You should see** a prompt like `yourname@PC:~$`.

<!-- §Step 3 -->
## Step 3: Get Tango32
In the Ubuntu window, type each line and press Enter (the first one asks for your Linux password):
```
sudo -i
apt update && apt install -y git
git clone https://github.com/ionTrix/Tango32.git
cd Tango32
ls /mnt/c/Users/
```
The last line lists your Windows user folders. Find **yours** (not `Public`, `Default` or `All Users`), and
use it in place of `YourName` below:
```
DL=/mnt/c/Users/YourName/Downloads
cp $DL/fw.zip .
ls
```
**You should see** `fw.zip` in the list next to `build.sh`. If `cp` says "No such file", check the name
(capital letters matter) and that `fw.zip` is in that Downloads folder.

<!-- §Step 4 -->
## Step 4: Build
Still in the same window (the prompt should end in `Tango32#`; if you reopened it: `sudo -i`, then `cd Tango32`):
```
bash build.sh
```
- First it checks your files: **you should see** `fw: … 16.0.10.601 … (tested)`.
- Then it downloads ~7.7 GB of Chinese firmware. **It looks stuck while downloading — it isn't.** Leave it.
  Keep the PC awake.
- Then it builds (~5–10 min of text scrolling).
- **Done when you see** `Built /root/re-work/module/tango32-v1.0.zip`.

Copy the module to Windows:
```
cp /root/re-work/module/tango32-*.zip $DL/
```
(If you closed the window since Step 3, first run `sudo -i`, `cd Tango32` and the `DL=…` line again.)
Then copy `tango32-v1.0.zip` from the PC's Downloads to the phone (e.g. its Download folder).

<!-- §Step 5 -->
## Step 5: Install on the phone
1. Magisk → **Modules** → **Install from storage** → pick `tango32-v1.0.zip`.
2. **You should see** `Build check OK` in the install log. Tap **Reboot**.
3. After unlocking, wait ~30 seconds. Put an old 32-bit APK in the **Tango32** folder at the top of your storage,
   or just tap it in your file manager. See the README's *Using it (Action)*.

<!-- §If something goes wrong -->
## If something goes wrong
| You see | Do |
|---|---|
| `FATAL: no fw.zip or fw/ next to build.sh` | Step 3: copy `fw.zip` into the `Tango32` folder, then `bash build.sh` again |
| `FATAL: fw is from '…'` / `verified on 16.0.10.601 only` | Wrong phone or firmware. Other firmware: `ALLOW_UNTESTED=1 bash build.sh` (untested, may not work) |
| `curl: (56)` or the download stops | Run `bash build.sh` again (it starts the download over) |
| `FATAL: could not get the CN firmware images` | The download site is down. Find the files it lists (any source), put them in a folder, then `CN_LOCAL=/path/to/folder bash build.sh`. Files are checked, so a wrong copy is refused |
| `FATAL: CN image hash mismatch` | The download was damaged: `rm -rf /root/re-work/cnfw/img`, then `bash build.sh` again |
| `No space left on device` | Free ~25 GB on drive C:, then run again |
| Install log: `Build check` fails | The zip was built from another phone's or firmware's `fw.zip`. Redo Step 1 on *this* phone, then Step 4 |
| Phone has a problem after install | README → *Disable and rescue* |

Still stuck? Open an issue with the **Bug report** form and paste the last ~20 lines you saw.

Done with the build? You can free the space in Ubuntu: `rm -rf /root/re-work/cnfw` (keep it if you'll rebuild soon).
