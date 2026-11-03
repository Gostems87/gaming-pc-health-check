# Windows settings and conflicting software

## Windows gaming settings

| Setting | What it does, in plain English | Recommend | `apply-safe.ps1` switch | How the user undoes it |
|---|---|---|---|---|
| Game Mode | Tells Windows the game comes first: Windows Update installs and notifications wait | On | `-GameMode` | Settings > Gaming > Game Mode |
| Hardware-accelerated GPU scheduling | Lets the graphics card manage its own work queue; NVIDIA Frame Generation needs it | On for RTX 20-series and newer, Radeon RX 6000 and newer, Intel Arc. Test off only if VR stutters | `-GpuScheduling` (admin, restart) | Settings > System > Display > Graphics > Change default graphics settings |
| Optimizations for windowed games | Gives borderless-window games the same low-latency path as full-screen ones, and makes VRR work in them | On (the Windows 11 default) | `-WindowedOptimisations` | Same page. One misbehaving game can be excluded under that game's Options |
| Variable refresh rate | Lets G-Sync/FreeSync work in older DirectX 11 games | On with a VRR monitor | `-VariableRefreshRate` | Same page |
| Xbox Game Bar background capture | Windows quietly records the last few minutes of play | Off when another recorder is used (NVIDIA app, AMD, OBS, Medal). Keep Game Bar itself installed: two-die AMD X3D chips rely on it | `-GameBarCaptureOff` | Settings > Gaming > Captures |
| Mouse acceleration ("Enhance pointer precision") | Moves the pointer further when the mouse moves faster, which makes aim inconsistent | Off for shooters; personal taste otherwise | `-MouseAccelerationOff` (live after signing out) | Control Panel > Mouse > Pointer Options |
| Power plan | How eagerly the CPU speeds up and parks cores | Balanced. Essential on two-die X3D chips (7900X3D, 7950X3D, 9900X3D, 9950X3D) | `-BalancedPowerPlan` | Control Panel > Power Options |
| Hibernation and Fast Startup | Fast Startup is half a hibernation: it can carry stale driver state between sessions, and hiberfil.sys takes up to 40% of the RAM size on disk | Off on desktops (a cold boot from an NVMe drive takes seconds). Keep on laptops | `-HibernateOff` (admin) | `powercfg /hibernate on` as admin |
| Startup apps | What launches every time Windows starts | Off for anything not needed every session. Ask about peripherals first (ground rule 7) | `-DisableStartup "Name;Name"` | Task Manager > Startup apps > Enable |
| Memory Integrity (Core isolation) | A security layer that uses the Windows hypervisor; costs a few percent in some CPU-heavy games | The user's call; recommend keeping it on. FACEIT players may need it on: check FACEIT's requirements page | None: the user does it in Windows Security > Device security > Core isolation | Same place |
| User Account Control | The "do you want to allow this app to make changes" prompt | The default level | None: Control Panel > User Accounts > Change User Account Control settings | Same place |
| Display resolution and refresh rate | See `gpu-and-display.md` | Native resolution, top refresh rate | None: the user picks in Settings > System > Display | Same place |

### Clean-up switches (cannot be undone; see `disk-space.md`)
`-CleanTemp`, `-CleanInstallerLeftovers`, `-CleanComponentStore` (admin, takes minutes), `-EmptyRecycleBin` (only on an explicit yes: it holds the user's deleted files).

### Running it
```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\apply-safe.ps1" -OutDir "<out>" -GameMode -WindowedOptimisations -VariableRefreshRate -GameBarCaptureOff
```
That previews. Add `-Apply` to make the changes and `-Elevate` if any item needs admin. Reverse everything with `-Undo "<out>\undo-<stamp>.json" -Apply -Elevate`.

### Leave alone
- **Windows Update:** never disable it. Pause it for a week if a tournament or a long session needs quiet.
- **The pagefile:** leave it system-managed.
- **Microsoft Defender:** keep it unless another antivirus replaces it.
- **Visual effects, Nagle, network throttling, HPET, timer resolution, core parking, "Ultimate Performance":** placebo or harmful on a modern gaming PC. Ultimate Performance also stops two-die X3D chips picking the right cores.

## Conflicting software

- **More than one VPN.** Each installs a network driver and often a packet filter on the real network adapter, even when disconnected. Keep the one in use. Uninstall the rest (Settings > Apps, or `winget uninstall --name "<name>"`), then re-scan: `network.vpnAndTunnelAdapters` and `network.thirdPartyFiltersOnActiveAdapters` should no longer list them. Leftover virtual adapters can be removed in Device Manager > Network adapters (View > Show hidden devices).
- **More than one antivirus.** Two real-time scanners check every file twice and can lock each other up. Keep one. Judge this from Windows Security Center's list (`security.antivirus` in the scan), not from installed app names: suites install companion apps (secure browsers, password managers, web advisers) that are not second antivirus products. If an uninstall leaves services behind, use that vendor's own removal tool. Microsoft Defender switches itself back on when the last third-party antivirus goes; confirm in Windows Security.
- **More than one recorder.** NVIDIA app, AMD Adrenalin, OBS replay buffer, Medal, Outplayed and Game Bar capture can all record at once. Pick one. Overlays (Discord, Steam, NVIDIA, RivaTuner) are usually fine; crosshair and injection overlays are a common crash cause and some anti-cheats block them.
- **Several RGB or peripheral suites.** Armoury Crate, iCUE, G HUB, Synapse, SignalRGB and others can fight over the same devices, and some cause stutter. Keep the apps for devices in use. Many mice and keyboards store their settings on the device once configured, so the app can come out of startup. Ask first.
- **"Optimisers", boosters, driver updaters and registry cleaners.** Recommend removing them: they change the same settings this check does, driver updaters install the wrong drivers, and several bundle adware.
- **Emulators, virtual machines, WSL, Docker.** They keep the Windows hypervisor running, which costs a few percent in CPU-heavy games. Fine if used. If not, uninstalling them and turning off Virtual Machine Platform (Windows Features) gives that back. The user's call.
- **Several game launchers.** Fine to have. Few need to start with Windows.

## Launcher and game fixes
- **Steam crashes at start:** Steam > Settings > Downloads > Clear Download Cache; Settings > In Game > Delete web browser data. If it continues, reinstall the Steam client (installed games stay).
- **One game crashes:** verify its files (Steam: Properties > Installed Files > Verify integrity), check its crashing module in the scan, look up known issues for that game and driver.
