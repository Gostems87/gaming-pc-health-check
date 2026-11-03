# The quiz

One round: four multiple-choice questions, then one free-text follow-up. Never ask what the scan can detect (the hardware, the monitor, desktop or laptop, what is installed).

## The four questions

**1. What do you mainly play?** (pick any)
- Competitive online shooters and esports (Counter-Strike 2, Valorant, Fortnite, Apex, Call of Duty, Overwatch, Rainbow Six)
- Big single-player games (Cyberpunk 2077, Elden Ring, Baldur's Gate 3, the latest big releases)
- MMOs, strategy and simulation (World of Warcraft, Factorio, Microsoft Flight Simulator, Total War, Tarkov)
- VR, or racing and flight sims with wheels, sticks or a headset

**2. What matters most to you?** (pick one)
- The highest frame rate and the lowest input lag
- Smooth play: no stutter and no screen tearing
- The best-looking picture
- Quiet and cool

**3. Is anything bugging you?** (pick any; "nothing, just a check-up" goes in Other)
- Crashes, freezes or random restarts
- Stutter or frame drops
- Screen tearing
- Running out of space, or slow loading

**4. How hands-on are you happy to be?** (pick one)
- Windows settings only, please: no BIOS
- I'll follow a step-by-step card in the BIOS
- I'm comfortable in the BIOS already

## The follow-up (one message)

> Which games are you playing most right now? Do you record or stream? Any wireless keyboard, mouse, headset or controller I should know about (so I don't switch off its app)? And anything you've tried before that went wrong, for example memory settings that wouldn't boot?

## How the answers change the plan

### What they play
| Profile | Prioritise | Matters less |
|---|---|---|
| Competitive shooters | Top refresh rate at native resolution; VRR with driver VSync and a frame cap (Reflex or Anti-Lag); mouse acceleration off; Game Mode; trim background apps and spare recorders; a wired connection; XMP/EXPO (smoother 1% lows in CPU-heavy games); Secure Boot and TPM for anti-cheat | Picture quality settings |
| Big single-player | Current graphics driver; GPU scheduling on (needed for NVIDIA Frame Generation); DLSS/FSR advice; Resizable BAR; SSD space for big installs; keep shader caches | Mouse acceleration, network |
| MMO, strategy, sims | These lean on the CPU and memory: XMP/EXPO and two-stick dual-channel matter most; X3D tips; 32 GB or more for big sims; background CPU hogs; space for sim scenery | Refresh-rate chasing |
| VR and sim rigs | Frame-time consistency; one overlay only; if headset or wheel drops out, USB selective suspend off for that device (targeted fix, not global); if VR stutters, test GPU scheduling off | Peak FPS |
| Records or streams | One capture tool; hardware encoder (NVENC, AMF or Quick Sync); a drive with room for recordings; Game Bar capture off if another tool records | |

### What matters most
- **Frame rate and input lag:** as for competitive shooters.
- **Smooth:** the VRR setup, background load, XMP/EXPO, dual-channel memory, a drive that is not full.
- **Best picture:** native resolution on every monitor, HDR set up with the Windows HDR Calibration app if they use HDR, DLSS/FSR quality modes, monitor colour settings.
- **Quiet and cool:** a frame cap at the refresh rate (less work, less heat, less fan noise); NVIDIA power management on Normal; suggest a dust check. Fan curves are hardware territory: mention, do not change.

### What is bugging them
- **Crashes:** event history first (WHEA hardware errors, blue screens, graphics driver resets, the crashing app and module), then memory stability (is XMP/EXPO too fast?), drivers, Intel 13th/14th-gen microcode, then power supply questions.
- **Stutter:** background load and duplicate recorders or RGB apps; XMP/EXPO off or single-channel memory; a nearly full drive; Memory Integrity (a trade-off); shader caches rebuilding after a driver update (normal for one session).
- **Tearing:** the VRR setup in `gpu-and-display.md`; refresh rate set correctly in Windows; the right cable and port.
- **Space or slow loading:** `disk-space.md`; games on a hard drive should move to an SSD.

### How hands-on
- **Windows only:** no BIOS cards. List BIOS opportunities under "When you're ready" in the report.
- **Will follow a card:** full cards, one BIOS change per session.
- **Comfortable in the BIOS:** the same cards, still one change at a time. The hard stops still apply.
