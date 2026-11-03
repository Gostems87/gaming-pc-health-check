---
name: gaming-pc-health-check
description: Full health check and gaming tune-up for a Windows 10/11 PC, run by Claude from inside Claude Code. Asks what games the user plays, then scans hardware, drivers, BIOS age, RAM speed versus its rating (XMP/EXPO), Windows and graphics settings, monitor setup, conflicting software (VPNs, antivirus, recorders, RGB apps, "optimisers"), startup load, crash and hardware-error history and disk space. Writes a plain-English report, applies only the safe, reversible fixes the user approves (with an undo file), and writes step-by-step cards for BIOS updates, XMP/EXPO and Secure Boot. Use when the user asks to check, optimise, tune up, speed up, clean up or "MOT" their PC or gaming PC, or mentions stutter, low FPS, screen tearing, crashes, a full drive, a BIOS update, XMP, EXPO, or whether their RAM runs at full speed.
---

# Gaming PC Health Check

Think of this as an MOT for a gaming PC: inspect everything, explain what you found in plain English, fix only what the owner signs off, and hand them a printed card for anything that needs their own hands (the BIOS).

## Ground rules (never break these)

1. **Read-only until the user says yes.** The scan changes nothing. `apply-safe.ps1` previews by default; show the preview, then apply only what the user approved.
2. **Every setting change is recorded before it is made.** `apply-safe.ps1` writes an undo file; tell the user where it is and how to use it.
3. **Claude never flashes a BIOS or changes BIOS settings.** It researches, downloads from the maker's own site, verifies the file and writes a step card. The user does the BIOS part.
4. **One BIOS change at a time, then re-check.** After any BIOS change (a flash, loading defaults, XMP/EXPO), re-run the scan and confirm Secure Boot, TPM, Resizable BAR, memory speed and drivers. Loading BIOS defaults can switch Secure Boot off without saying so.
5. **No overclocking beyond the factory XMP/EXPO profile.** No voltages, no manual timings, no CPU or GPU overclocks. The memory ladder has a hard stop.
6. **Never delete the user's own files without naming each item and getting a yes for it**: games, recordings, downloads, documents, the Recycle Bin. Never delete shader caches. Remove games through their launcher.
7. **Never switch off a peripheral app** (Razer, Logitech, SteelSeries, Corsair and so on) because its device did not appear in the scan. Wireless and Bluetooth devices hide. Ask.
8. **Never leave the PC without antivirus.** Removing one of two is fine; removing the last is not.
9. **Evidence-based fixes only.** No registry "FPS packs", Nagle or network-throttling hacks, HPET or timer tweaks, core-parking hacks, disabling Windows Update, debloat scripts or third-party "optimiser" apps. If a tweak is not in these references, do not do it.
10. **Security trade-offs are the user's call** (Memory Integrity, virtualisation-based security, Secure Boot, TPM, UAC). Recommend keeping protections on and be honest about the cost.
11. **Do not install network drivers mid-session.** The connection drops and the session can lose its link. Leave them to the end, or to the user.
12. **Laptops are different:** keep hibernation, never suggest BIOS memory changes (the RAM is often soldered), check it is plugged in and on the best power mode when gaming.
13. **Admin rights only through the Windows prompt the user clicks.** Say why before it appears. Never restart the PC without a yes (there may be unsaved work).
14. **Privacy:** the scan collects no serial numbers, product keys, passwords, browser data or contents of personal files (it does read settings, game-launcher manifests, startup command lines and device names), and its results stay in the output folder on this PC.

## Setting up

- **Output folder:** inside an AIOS or any workspace with an `outputs/` folder, use `outputs/pc-health-check-YYYY-MM-DD/`. Otherwise `%USERPROFILE%\Documents\pc-health-check-YYYY-MM-DD\`.
- **Scripts** live in this skill's `scripts/` folder (usually `%USERPROFILE%\.claude\skills\gaming-pc-health-check\scripts\`). Run them with `powershell -NoProfile -ExecutionPolicy Bypass -File "<script>" <switches>`, which works on a fresh Windows install where scripts are blocked and changes no system policy.
- Open with two or three lines: what will happen, roughly how long (the scan takes from 30 seconds to a few minutes), and that nothing changes without their yes.

## The run

### 1. Quiz (one round)
Read `references/quiz.md`. Ask the four questions in one go (use AskUserQuestion if it is available), then one free-text follow-up. Do not ask anything the scan can detect.

### 2. Scan
Explain the admin prompt, then run `diagnose.ps1 -OutDir "<out>" -Elevate`. Read `diagnostic-summary.txt` first, then the sections of `diagnostic.json` you need. If the prompt is declined it falls back to the standard scan; say what was missed (Secure Boot confirmation, TPM, BitLocker detail, drive wear). `-Quick` skips folder sizing on very large drives.

The findings are tagged `fix`, `check`, `info` and `good`. They are leads, not verdicts: confirm each before it goes in the report (for example a RAM speed below its rating may be a deliberate step-down after the rated speed would not boot).

### 3. Research (current facts, with sources)
- **BIOS:** exact board model from the scan, then the maker's support page: latest version and date, what changed (memory, stability, security, CPU support), "cannot roll back" or "update X first" warnings. Priority triggers are in `references/bios-and-memory.md`.
- **RAM:** the part number's XMP/EXPO rating.
- **Drivers:** the chipset package for this board or platform, and whether the graphics driver is current.
- **Monitor:** refresh rate and VRR support, if unclear.
- **Anything flagged you do not recognise:** an app, a WHEA event ID, a crashing module, a game that may have shut down.

Prefer the manufacturer's own pages. Cite them in the report.

### 4. Report
Write `PC-HEALTH-REPORT.md` in the output folder using `references/report-template.md`. Lead with the verdict and the top three wins, tailored to the quiz answers. Sort everything into four buckets: **Already right**, **Safe fixes** (Claude can do them now, with a yes), **Needs you** (BIOS, cables, hardware) and **Your call** (trade-offs and the user's own files). Plain English, an everyday analogy where it helps, no jargon without a one-line explanation.

In chat, give a short summary and the safe fixes as a numbered menu, and ask which to apply.

### 5. Apply the approved safe fixes
- Map each approved item to its `apply-safe.ps1` switch (table in `references/windows-and-conflicts.md`). Run the preview, show it, then run again with `-Apply` (add `-Elevate` if any item needs admin). If the user declines the admin prompt, nothing is changed; ask before re-running the non-admin items on their own.
- Report what changed and the undo command. If GPU scheduling or hibernation changed, ask before restarting.
- **Uninstalls** (a spare VPN or antivirus, an "optimiser", games): only the ones the user names, with the app's own uninstaller, `winget uninstall` or the game launcher. Re-scan afterwards to check for leftovers (network adapters, filters, services).
- **Drivers:** only from the board maker, AMD, Intel or NVIDIA, one at a time, then re-check for problem devices. Network drivers last (rule 11).
- **Graphics driver settings** (VSync, low latency, power management): walk the user through the control panel with a short card from `references/gpu-and-display.md`.

### 6. "Needs you" cards
For each BIOS job, write a plain-text card in the output folder using the template in `references/bios-and-memory.md`: BIOS update, the XMP/EXPO ladder, Secure Boot / TPM / Resizable BAR switches. Use the menu names for the user's board maker. Every card covers: before you start, the steps, what normal looks like (a black screen during memory training), what to do if it goes wrong, and the hard stop. If BitLocker is on, the recovery key step comes first.

### 7. Verify
- **After any BIOS change:** re-run `diagnose.ps1` into a subfolder (for example `after-bios`) and compare BIOS version, memory speed, Secure Boot, TPM, Resizable BAR and problem devices with the first scan.
- **After XMP/EXPO:** a stress test (`references/bios-and-memory.md`), then a day of normal gaming, then `health-recheck.ps1 -Since "yyyy-MM-dd HH:mm"` (the time of the change, in that exact form).
- **Secure Boot cards:** only include a "restore default keys" step when the elevated scan shows the BIOS's default keys carry Microsoft's 2023 certificate (`references/bios-and-memory.md`, the key check).
- Add the outcome to the report's changes log.

## Reference files (open only what the task needs)

- `references/quiz.md`: the questions, and how the answers change the priorities.
- `references/windows-and-conflicts.md`: every Windows setting (what it does, the recommended value, the `apply-safe.ps1` switch, how to undo it) and how to resolve conflicting software.
- `references/gpu-and-display.md`: NVIDIA, AMD and Intel settings; the tear-free VRR setup; Resizable BAR; monitor checks.
- `references/bios-and-memory.md`: when a BIOS update matters, safe flashing by maker, what resets afterwards, the XMP/EXPO ladder, stress testing, the card template.
- `references/disk-space.md`: what is safe to clear, what to keep, where the big wins hide, removing games properly.
- `references/report-template.md`: the report's structure and tone.

## Scripts

| Script | What it does | Changes anything? |
|---|---|---|
| `scripts/diagnose.ps1` | Full scan; writes `diagnostic.json` and `diagnostic-summary.txt` | No |
| `scripts/apply-safe.ps1` | Applies approved fixes; preview by default; undo file; `-Undo <file> -Apply` reverses | Only with `-Apply` |
| `scripts/health-recheck.ps1` | After-care: hardware errors, crashes, power-offs since a time | No |

All three are Windows PowerShell 5.1 compatible and plain ASCII, so they run on any Windows 10 or 11 PC without installing anything.
