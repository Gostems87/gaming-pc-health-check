# Graphics card and display settings

## The monitor comes first
- **Native resolution and the top refresh rate.** The scan reads each monitor's native resolution from its own data (EDID) and the best refresh rate on offer. A 144, 165 or 240 Hz monitor left at 60 Hz is the most common free win there is. Fix: Settings > System > Display > pick the monitor > Advanced display > Choose a refresh rate.
- **A second monitor at a non-native resolution** looks soft. Set it to native and use Windows scaling (for example 150% on a 28-inch 4K) to keep text the same size.
- **The cable goes into the graphics card,** never the motherboard's own video ports when a graphics card is fitted. DisplayPort is the safe choice for high refresh; HDMI needs 2.1 for 4K above 60 Hz.
- **HDR** is the user's call. If they use it, the Windows HDR Calibration app (free, Microsoft Store) sets it up properly.

## The tear-free, low-lag setup (G-Sync or FreeSync monitors)
1. Variable refresh rate on in the driver, and in the monitor's own menu (FreeSync or Adaptive-Sync).
2. Vertical sync ON in the driver's global settings, OFF inside games.
3. A frame cap a few frames under the refresh rate: NVIDIA Reflex in games that have it, or Low Latency Mode Ultra (both cap automatically when VRR and VSync are on); on AMD, Anti-Lag plus Radeon Chill with minimum and maximum both set to refresh minus 3, or the game's own limiter.

Why it works, in one line for the user: variable refresh only works below the monitor's top speed, like lane assist that switches off above its speed limit. The cap keeps the game inside that range, so there is no tearing and no added lag.

## NVIDIA
NVIDIA Control Panel > Manage 3D settings > Global settings:
- **Vertical sync:** On (with G-Sync).
- **Low Latency Mode:** Ultra (Reflex inside a game takes over from this).
- **Power management mode:** Normal. "Prefer maximum performance" only holds the card at full clocks on the desktop; it adds nothing in games.
- **Image Scaling:** Off, unless the user chose it on purpose (DLSS is better where a game offers it).
- **Shader Cache Size:** Driver default or 10 GB and up. Never Disabled.
- **DSR:** off unless they use it.

Display > Set up G-SYNC: enable for windowed and full-screen mode, and tick the monitor.

The scan's `gpu.nvidia` block shows the driver, temperature, power draw, PCIe link and Resizable BAR. NVIDIA has no official command line for driver settings, so walk the user through the Control Panel with a short card. NVIDIA Profile Inspector (open source, github.com/Orbmu2k/nvidiaProfileInspector) can export the settings for a read-only check if needed.

Drivers come from the NVIDIA app or nvidia.com. A clean reinstall (DDU in Safe Mode) is a last resort for driver corruption, not routine maintenance.

## AMD Radeon
AMD Software: Adrenalin Edition > Gaming > Graphics (global):
- **AMD FreeSync:** On.
- **Enhanced Sync:** Off (it can cause stutter alongside FreeSync).
- **Wait for Vertical Refresh:** Always on, with the frame cap above.
- **Anti-Lag:** On (Anti-Lag 2 where a game supports it).
- **Radeon Super Resolution, Radeon Boost:** off unless wanted.
- **Smart Access Memory** (AMD's name for Resizable BAR): on.
- Performance > Tuning: leave at the defaults. No automatic overclocking.

## Intel Arc
- **Resizable BAR is essential.** Arc cards lose a large share of their performance without it.
- Drivers and settings through Intel Graphics Software (formerly Arc Control), from intel.com.

## Resizable BAR
Lets the processor send data to all of the graphics card's memory at once instead of through a 256 MB hatch. BIOS: Above 4G Decoding Enabled, Re-Size BAR Enabled (or Auto), CSM Disabled. It needs Windows installed in UEFI mode (the scan's `system.firmwareMode`). Afterwards: the scan shows "Resizable BAR on" for NVIDIA; Adrenalin shows Smart Access Memory; Arc's software shows ReBAR.

## PCIe link
A graphics card running at x8 or x4 instead of x16 is usually in the wrong slot, on a riser cable, or affected by a BIOS lane-sharing setting. The PCIe generation reads lower at idle to save power, so check it while a game runs.

## Temperatures
The scripts do not read CPU temperatures (Windows has no reliable built-in sensor). If the user reports heat, throttling or noise, suggest HWiNFO in sensors-only mode and read the maximum values back during a game. Dust, airflow and fan curves are hardware topics for the user.
