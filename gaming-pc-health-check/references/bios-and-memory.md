# BIOS updates and memory (XMP / EXPO)

## Does this PC need a BIOS update?

**Prioritise it if any of these apply:**
- **Intel Core 13th or 14th generation desktop** (the i5-13600K and up are the main concern) with microcode below 0x12F. 0x12B was Intel's main fix for the "Vmin shift" instability that crashed and slowly damaged these chips; 0x12F (2025) covers the remaining idle and long-running cases. The scan reports the microcode. Update to the newest BIOS carrying 0x12F or later and use the board's "Intel Default Settings" profile. Below 0x12B is urgent.
- **AMD Ryzen 7000X3D on an early AM5 BIOS** (AGESA before 1.0.0.7, roughly April 2023), which lacks the SoC voltage cap. More generally, any AM5 board still on a 2023 BIOS has missed a lot of memory-training work.
- **XMP/EXPO will not boot, or four sticks will not train,** and the BIOS is more than a year old.
- **A security fix in the changelog** (for example LogoFAIL or Sinkclose), or support for a CPU the user plans to fit.

**Otherwise:** if the PC is stable and the BIOS is under a year old, leave it. "There's a newer version" is not a reason on its own.

**Research:** take the exact board name from the scan to the maker's support page (ASUS, MSI, Gigabyte, ASRock, or the PC maker for OEM machines). Read the version list for dates, notes, "cannot roll back" warnings and "update to X first" chains. Prefer non-beta releases unless the beta carries a fix this PC needs.

## Before a flash (the card covers this)
- **BitLocker or Device Encryption on?** Make sure the recovery key is saved (aka.ms/myrecoverykey) before anything else. With the user's yes, Claude can suspend protection for one restart just before they go into the BIOS: `manage-bde -protectors -disable C: -RebootCount 1` (admin).
- **Photograph any custom BIOS settings** (fan curves, boot order, virtualisation). The flash resets everything.
- **Power:** laptops on the charger with the battery above 50%; desktops on steady mains (not during a thunderstorm).
- **The file:** only from the maker's own site. Claude can download it to the Desktop and check its SHA-256 with `Get-FileHash` if the maker publishes one.
- **A USB stick formatted FAT32** for in-BIOS flashing.
- **Keep the chipset driver folder** (for example `C:\AMD`). A new BIOS can expose new devices whose drivers are in that package.

## How each maker flashes
Use the in-BIOS tool for desktops: it is the safest route.
- **ASUS:** EZ Flash 3 (F7 for Advanced Mode > Tool). Recovery: USB BIOS FlashBack (renamed file plus the button on the back panel).
- **MSI:** M-Flash. Recovery: the Flash BIOS button.
- **Gigabyte:** Q-Flash (F8). Recovery: Q-Flash Plus.
- **ASRock:** Instant Flash (Tool menu). Recovery: BIOS Flashback where fitted.
- **Laptops and branded desktops** (Dell, HP, Lenovo, Acer and others): the maker's own updater in Windows (Dell Command Update or SupportAssist, HP Support Assistant, Lenovo Vantage), on mains power.

Never interrupt a flash. It takes a few minutes and may restart more than once.

## After a flash: what resets
- **XMP/EXPO** is off again: re-enable with the ladder below.
- **Secure Boot** can come back off. On ASUS: Boot > Secure Boot > OS Type "Windows UEFI mode". Other makers: Secure Boot > Enabled. Only restore default keys if the BIOS says it is in Setup Mode, and only after the key check below.
- **The TPM** (fTPM on AMD, PTT on Intel) may be reset, so Windows can ask to set up the Windows Hello PIN again. Normal.
- **Resizable BAR and Above 4G Decoding** may go back to off.
- **Boot order:** the Windows drive first.
- Re-run `diagnose.ps1` into an `after-bios` subfolder and compare. Install drivers for any new problem devices (often from the chipset package already on disk).

## XMP and EXPO
**What it is:** memory is sold with a rated speed (say DDR5-6000) but every PC starts it at a slow universal default (DDR5-4800, DDR4-2133). XMP (Intel) and EXPO (AMD) are factory-tested profiles stored on the sticks: one switch in the BIOS runs them at their rating. Like a car delivered in eco mode with sport mode one button away.

**How to tell:** the scan's memory verdict. CPU-Z's SPD tab shows the exact profiles.

**Menu names:**
- ASUS: Ai Tweaker > Ai Overclock Tuner > XMP I or EXPO I (press F7 for Advanced Mode).
- MSI: the XMP / EXPO button on the EZ Mode screen (Profile 1).
- Gigabyte: Tweaker > Extreme Memory Profile (X.M.P.) or EXPO.
- ASRock: OC Tweaker > DRAM Configuration > Load XMP Setting or EXPO.

**Before:** a matched kit (same part number, ideally bought as one kit) in the slots the manual gives for two sticks (usually A2 and B2: the second and fourth from the CPU).

### The ladder: one card, one change per boot
0. **Load optimised defaults** first, to clear half-trained leftovers. This can switch Secure Boot off on some boards, so it is re-checked at the end.
1. **The profile on its own.** Everything else stays on Auto: no Memory Context Restore, no power-down options, no voltages. Save and restart. **Wait up to ten minutes.** The first boot after a memory change trains the RAM: black screen, fans running, a DRAM light on the board, and it may restart itself two or three times. That is normal. Do not touch the power button.
   - Windows loads: done. Verify.
   - A message like "Overclocking failed", a safe-mode screen, or still black after ten minutes (hold power for ten seconds, start again, go into the BIOS, load defaults): go to step 2.
2. **The profile plus one speed notch down** (DDR5 6000 to 5600, 6400 to 6000, 7200 to 6800; DDR4 3600 to 3200, 3200 to 3000). Same wait.
   - Windows loads: done. That is most of the gain.
   - It fails: set the memory back to Auto and **stop**.
3. **The hard stop.** No third attempt, no voltages, no manual timings. If even one notch down fails, the limit is the memory chips, the processor's memory controller (silicon lottery), or a mixed or four-stick setup. The fix is hardware (a two-stick kit known to suit the platform), not more BIOS work.

**Later, optional:** Memory Context Restore (AM5, for faster boots) only after a week without errors, on its own.
**Four DDR5 sticks** usually cannot run the full rated speed (often 5200 or below on AM5). Two larger sticks is the better shape.

### Verifying a memory change
1. Re-run `diagnose.ps1`: the memory speed has changed and there are no WHEA hardware errors.
2. **Stress test, 30 to 60 minutes:**
   - Easiest: OCCT (free for personal use), Memory test.
   - Thorough: TestMem5 (github.com/CoolCmd/TestMem5) with anta777's DDR5 or DDR4 config. On X3D processors use the "Ryzen3D" config: their large cache hides memory faults from ordinary tests. Run it elevated. It may raise "To enable AWE, you must run with Administrator privileges!" boxes, several per launch. Each freezes a test worker until OK is clicked, and boxes left by a killed run stay queued and block the next launch, so click them all OK. It then tests normally without AWE. Do not judge whether a worker is alive by its memory use.
   - Windows Memory Diagnostic is too gentle to count.
3. **A day of normal gaming,** then `health-recheck.ps1 -Since "<time of the change>"`. Any WHEA event 19 or 47, or a blue screen, means one notch down.

## Secure Boot and TPM
- **Secure Boot:** ASUS: Boot > Secure Boot > OS Type "Windows UEFI mode". MSI, Gigabyte, ASRock: Secure Boot > Enabled. Needs Windows in UEFI mode and CSM off.
- **The key check (important in 2026):** Microsoft has moved Windows to boot files signed with its 2023 certificate. On a BIOS whose built-in default keys predate that certificate, "Install default Secure Boot keys" / "Restore factory keys" can leave Windows unable to start. The elevated scan reads the key databases (`adminExtras.secureBootKeys`, read-only):
  - `dbDefault.windowsUefiCa2023` is true: restoring default keys is safe on this BIOS.
  - It is false or unavailable: do NOT put a key-restore step on the card. Update the BIOS first (newer BIOSes ship the 2023 keys), and follow the maker's own Secure Boot certificate FAQ.
  - Every Secure Boot card carries the recovery line: if Windows will not start afterwards, go back into the BIOS, switch Secure Boot off again to get back in, and tell Claude.
- **TPM:** AMD fTPM (Advanced > AMD fTPM configuration) or Intel PTT.
- **Who needs them:** Valorant (Vanguard), Battlefield 6 (Javelin) and recent Call of Duty need Secure Boot, TPM 2.0 or both. FACEIT has required TPM 2.0 and Secure Boot since late 2025, and is reported to want virtualisation-based security (Memory Integrity) on too: check FACEIT's own requirements page for FACEIT players. Windows 11 needs TPM 2.0.

## Card template
Write each card as a plain `.txt` file in the output folder, in the user's own words where possible.

```
<WHAT THIS CARD DOES, IN CAPS>
(written <date> for <board maker and model>, BIOS <version>)

WHAT THIS DOES
  One or two plain lines, and why it is worth doing.

BEFORE YOU START
  - Save your work and close everything.
  - <BitLocker step if needed>
  - Have a clock handy: the waits are real.

STEPS
  1. Restart. Tap <Delete or F2> as the <maker> logo appears.
  2. ...

WHAT NORMAL LOOKS LIKE
  <black screen for up to ten minutes during memory training, etc.>

IF IT GOES WRONG
  <the recovery: hold power 10 seconds, start, BIOS, load defaults, save>
  Nothing is damaged by a failed memory training attempt.

THE HARD STOP
  <when to stop and leave it>

WHEN YOU'RE BACK IN WINDOWS
  Tell Claude "<a phrase>" and it will check everything from here.
```
