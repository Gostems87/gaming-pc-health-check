# Disk space

## Safe to clear (with a yes; `apply-safe.ps1`)
- **Your own temporary files** older than 7 days: `-CleanTemp`. Windows' machine-wide temp folder is left to Windows' own tool (Settings > System > Storage > Temporary files). Claude Code's own working folder (`%TEMP%\claude`) is always skipped, links are never followed (and every delete re-checks its path), a temp folder that points anywhere unusual (a drive root, the user profile) is refused, and nothing runs while Windows has a restart pending.
- **NVIDIA downloaded installers and app crash dumps:** `-CleanInstallerLeftovers`. If crashes are being investigated, read the dumps first.
- **The Windows component store:** `-CleanComponentStore` (admin, several minutes). It does not use /ResetBase, so recent updates can still be uninstalled.
- **hiberfil.sys:** `-HibernateOff` on desktops only.
- **The Recycle Bin:** `-EmptyRecycleBin`, only after the user says yes. It holds their deleted files.
- **For the user to click:** Windows Update downloads, Delivery Optimization files and, after ten trouble-free days, Windows.old, all under Settings > System > Storage > Temporary files.
- **Steam's** `steamapps\downloading` and `steamapps\temp` folders, when Steam is closed and nothing is downloading.

## Keep
- **Shader caches:** NVIDIA DXCache and GLCache, D3DSCache, AMD DxCache, Steam's shadercache. Deleting them causes stutter while every game rebuilds them. A large NVIDIA cache is by design (the driver sets a size cap).
- **The pagefile** (leave it system-managed), **WinSxS** (only the component clean-up touches it safely), **Program Files**, **ProgramData\Package Cache** (needed to repair and uninstall software), and the **chipset driver folder** (for example `C:\AMD`) until after any BIOS update.
- **Game saves:** Documents\My Games, Saved Games, and AppData folders for individual games.
- **Anything in Documents, Desktop, Pictures or Music** unless the user names it.

## Where the big wins hide (the user's own files: ask item by item)
- **Old recordings and clips.** The scan's `space.biggestFolders` lists the video gigabytes in every top-level folder, including Downloads and the roots of other drives, with the date of the newest file. Recording tools often save somewhere unexpected. Films and family videos are not clutter: always ask.
- **Games not played for a year or more** (Steam's last-played date is in the scan), **games that have shut down and betas that have ended** (check each title), and **the same game installed twice** through two launchers (for example Call of Duty in Battle.net and in the Xbox app).
- **Old installers** sitting in Downloads.

## Removing games properly
Use the launcher, so its records stay straight:
- **Steam:** `start steam://uninstall/<appid>` opens Steam's own confirmation box (the appid is in the scan) and the user clicks Uninstall. Or Library > right-click the game > Manage > Uninstall.
- **Epic, EA app, Ubisoft Connect, Battle.net, Xbox app:** from the launcher's library (Manage or Uninstall).
- **Anything else:** Settings > Apps > Installed apps, or `winget uninstall --name "<name>"`.

Only delete a game folder directly when no launcher knows about it any more (an orphan), and only after the user confirms.

## How much free space
Keep at least 15 to 20 percent free on every SSD. Game patches often need room for a second copy of the game while they install.
