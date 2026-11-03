<#
.SYNOPSIS
    Gaming PC Health Check: read-only diagnostic scan.

.DESCRIPTION
    Collects the facts a gaming tune-up needs: hardware (CPU, GPU, motherboard, BIOS,
    RAM speed versus its rating), drives and free space, drivers, Windows gaming settings,
    security state, displays (resolution and refresh rate versus what the monitor
    supports), conflicting software (VPNs, antivirus, capture tools, RGB suites,
    "optimiser" apps), startup load, crash and hardware-error history, game libraries
    and the biggest space users.

    It changes NOTHING on the PC. It does not collect serial numbers, product keys,
    passwords, browser data or the contents of personal files. It does read system
    settings, game-launcher manifests (game names, sizes, last-played dates), startup
    command lines and the names of connected devices. Results stay on this PC.

    Run it normally for most checks. Add -Elevate to accept one Windows admin prompt,
    which adds Secure Boot, TPM, BitLocker, drive wear and Windows feature checks.

.PARAMETER OutDir
    Folder for the results (created if missing). Default: .\pc-health-check-YYYY-MM-DD

.PARAMETER Elevate
    Relaunch as administrator (one UAC prompt) for the full scan. Falls back to the
    standard scan if the prompt is declined.

.PARAMETER Quick
    Skip the folder-size scan (faster; no recordings or big-folder list).

.PARAMETER EventDays
    How many days of crash and hardware-error history to read. Default 30.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -OutDir "C:\Temp\pc-check" -Elevate
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [switch]$Elevate,
    [switch]$Quick,
    [int]$EventDays = 30,
    [string]$LaunchedBy
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$ScriptVersion = '1.0.0'

if (-not $OutDir) { $OutDir = Join-Path (Get-Location).Path ('pc-health-check-' + (Get-Date -Format 'yyyy-MM-dd')) }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
if ($OutDir.Length -gt 3) { $OutDir = $OutDir.TrimEnd('\') }
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$mySid = $me.User.Value
if ($OutDir.Contains('"')) { Write-Host 'Refusing to run: the output folder name contains a double quote.'; exit 2 }

# ---------------------------------------------------------------------------------------
# Optional self-elevation (one UAC prompt). The elevated copy writes the same files.
# ---------------------------------------------------------------------------------------
if ($Elevate -and -not $isAdmin) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $launched = Get-Date
    $outArg = $OutDir
    if ($outArg.EndsWith('\')) { $outArg += '.' }
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -OutDir "' + $outArg + '" -EventDays ' + $EventDays + ' -LaunchedBy ' + $mySid
    if ($Quick) { $argLine += ' -Quick' }
    try {
        Write-Host 'Asking Windows for admin rights. Click Yes on the prompt to run the full scan.'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs -Wait -WindowStyle Minimized | Out-Null
        $out = Join-Path $OutDir 'diagnostic.json'
        if ((Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).LastWriteTime -ge $launched)) {
            Write-Host ('Done. Results in ' + $OutDir)
            exit 0
        }
        Write-Warning 'The admin scan did not finish; running the standard scan instead.'
    } catch {
        Write-Warning 'The admin prompt was declined or failed; running the standard scan instead.'
    }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$started = Get-Date
Write-Host ('Gaming PC Health Check scan v' + $ScriptVersion + ' (read-only). Admin: ' + $isAdmin)

# ---------------------------------------------------------------------------------------
# Native helpers: fast folder sizing and display-mode enumeration
# ---------------------------------------------------------------------------------------
if (-not ('PhcNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class PhcNative
{
    static readonly HashSet<string> VideoExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".mp4", ".mkv", ".mov", ".avi", ".flv", ".webm" };

    // Returns { bytes, files, newestTicksUtc, videoBytes, timedOut (0/1) }.
    // Skips junctions/symlinks and cloud-only (not downloaded) files.
    public static long[] MeasureFolder(string root, int maxSeconds)
    {
        long bytes = 0, files = 0, newest = 0, video = 0;
        bool timedOut = false;
        DateTime deadline = DateTime.UtcNow.AddSeconds(maxSeconds);
        Stack<string> stack = new Stack<string>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            if (DateTime.UtcNow > deadline) { timedOut = true; break; }
            string dir = stack.Pop();
            DirectoryInfo di;
            try { di = new DirectoryInfo(dir); } catch { continue; }
            try
            {
                foreach (FileInfo fi in di.EnumerateFiles())
                {
                    long len = 0;
                    try
                    {
                        int attr = (int)fi.Attributes;
                        if ((attr & 0x441000) != 0) continue;
                        len = fi.Length;
                        long t = fi.LastWriteTimeUtc.Ticks;
                        if (t > newest) newest = t;
                    }
                    catch { }
                    bytes += len; files++;
                    if (VideoExt.Contains(fi.Extension)) video += len;
                }
            }
            catch { }
            try
            {
                foreach (DirectoryInfo sub in di.EnumerateDirectories())
                {
                    if ((sub.Attributes & FileAttributes.ReparsePoint) == 0) stack.Push(sub.FullName);
                }
            }
            catch { }
        }
        return new long[] { bytes, files, newest, video, timedOut ? 1 : 0 };
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency;
        public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
        public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    // One row per active display:
    // { adapterDevice, adapterName, primary, monitorName, monitorId, curW, curH, curHz, maxW, maxH, maxHzAtMax, maxHzAtCur }
    public static List<string[]> Displays()
    {
        List<string[]> rows = new List<string[]>();
        for (uint i = 0; i < 64; i++)
        {
            DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
            if ((dd.StateFlags & 0x1) == 0) continue;
            bool primary = (dd.StateFlags & 0x4) != 0;
            DISPLAY_DEVICE mon = new DISPLAY_DEVICE();
            mon.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            string monName = "", monId = "";
            if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0)) { monName = mon.DeviceString ?? ""; monId = mon.DeviceID ?? ""; }
            DEVMODE cur = new DEVMODE();
            cur.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            EnumDisplaySettings(dd.DeviceName, -1, ref cur);
            int maxW = 0, maxH = 0, maxHzAtMax = 0, maxHzAtCur = 0;
            DEVMODE m = new DEVMODE();
            m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            for (int k = 0; k < 5000 && EnumDisplaySettings(dd.DeviceName, k, ref m); k++)
            {
                long area = (long)m.dmPelsWidth * m.dmPelsHeight;
                if (area > (long)maxW * maxH) { maxW = m.dmPelsWidth; maxH = m.dmPelsHeight; maxHzAtMax = 0; }
                if (m.dmPelsWidth == maxW && m.dmPelsHeight == maxH && m.dmDisplayFrequency > maxHzAtMax) maxHzAtMax = m.dmDisplayFrequency;
                if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmDisplayFrequency > maxHzAtCur) maxHzAtCur = m.dmDisplayFrequency;
            }
            rows.Add(new string[] { dd.DeviceName, dd.DeviceString, primary ? "1" : "0", monName, monId,
                cur.dmPelsWidth.ToString(), cur.dmPelsHeight.ToString(), cur.dmDisplayFrequency.ToString(),
                maxW.ToString(), maxH.ToString(), maxHzAtMax.ToString(), maxHzAtCur.ToString() });
        }
        return rows;
    }

    public static int MaxHzAt(string deviceName, int w, int h)
    {
        int best = 0;
        DEVMODE m = new DEVMODE();
        m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        for (int k = 0; k < 5000 && EnumDisplaySettings(deviceName, k, ref m); k++)
        {
            if (m.dmPelsWidth == w && m.dmPelsHeight == h && m.dmDisplayFrequency > best) best = m.dmDisplayFrequency;
        }
        return best;
    }
}
'@
}

# ---------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------
$R = [ordered]@{}
$R['meta'] = [ordered]@{
    tool = 'gaming-pc-health-check'; version = $ScriptVersion
    started = $started.ToString('yyyy-MM-dd HH:mm'); elevated = $isAdmin
    quick = [bool]$Quick; eventDays = $EventDays
}
$Flags = New-Object System.Collections.ArrayList
$UserMismatch = [bool]($LaunchedBy -and $LaunchedBy -ne $mySid)
$R.meta['elevatedAsDifferentAccount'] = $UserMismatch

function Add-Flag {
    param([string]$Area, [string]$Level, [string]$Text)
    # Levels: fix (likely wrong, worth fixing), check (needs a look or a decision), info, good (already right)
    [void]$Flags.Add([ordered]@{ area = $Area; level = $Level; text = $Text })
}

function Invoke-Section {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ('  scanning: ' + $Name)
    try { $R[$Name] = & $Body }
    catch { $R[$Name] = [ordered]@{ error = $_.Exception.Message } }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { $k = Get-Item -LiteralPath $Path -ErrorAction Stop; $v = $k.GetValue($Name, $null) } catch { return $null }
    # The comma stops PowerShell unrolling byte[] / string[] values into loose items.
    if ($v -is [array]) { return , $v }
    return $v
}

function Format-ShortDate($d) {
    if ($null -eq $d -or '' -eq $d) { return $null }
    try { return ([datetime]$d).ToString('yyyy-MM-dd') } catch { return [string]$d }
}

function ConvertTo-GB($bytes) {
    if ($null -eq $bytes) { return $null }
    return [math]::Round([double]$bytes / 1GB, 1)
}

$script:SizeBudgetEnds = (Get-Date).AddSeconds(300)
function Measure-Folder {
    param([string]$Path, [int]$MaxSeconds = 45)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $left = [int](($script:SizeBudgetEnds - (Get-Date)).TotalSeconds)
    if ($left -le 0) { return [ordered]@{ path = $Path; skipped = 'time budget used up' } }
    $m = [PhcNative]::MeasureFolder($Path, [math]::Min($MaxSeconds, $left))
    $newest = $null
    if ($m[2] -gt 0) { $newest = (New-Object DateTime ($m[2], [DateTimeKind]::Utc)).ToLocalTime().ToString('yyyy-MM-dd') }
    return [ordered]@{
        path = $Path; sizeGB = (ConvertTo-GB $m[0]); files = $m[1]; newestFile = $newest
        videoGB = (ConvertTo-GB $m[3]); partial = [bool]$m[4]
    }
}

function Get-FromUnixTime($s) {
    if (-not $s -or $s -eq '0') { return $null }
    try { return ([DateTimeOffset]::FromUnixTimeSeconds([int64]$s)).LocalDateTime } catch { return $null }
}

# Installed programs (used by several sections)
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$Apps = @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName } |
    ForEach-Object {
        [pscustomobject]@{
            name = ([string]$_.DisplayName).Trim(); publisher = [string]$_.Publisher; version = [string]$_.DisplayVersion
            installDate = [string]$_.InstallDate; sizeGB = $(if ($_.EstimatedSize) { [math]::Round([double]$_.EstimatedSize / 1MB, 1) } else { $null })
            location = [string]$_.InstallLocation
        }
    } | Sort-Object name -Unique)
$AppxNames = @()
try { $AppxNames = @(Get-AppxPackage -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }

function Find-Apps {
    param([string]$Pattern)
    return @($Apps | Where-Object { $_.name -match $Pattern } | ForEach-Object { $_.name })
}

# ---------------------------------------------------------------------------------------
# 1. System
# ---------------------------------------------------------------------------------------
Invoke-Section 'system' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $enc = Get-CimInstance Win32_SystemEnclosure
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    $types = @($enc.ChassisTypes | ForEach-Object { [int]$_ })
    # Trust the chassis type first; a battery alone only counts when the chassis is unknown,
    # because a USB-connected UPS also shows up as a battery on desktops.
    $chassisUnknown = ($types.Count -eq 0) -or (@($types | Where-Object { $_ -gt 2 }).Count -eq 0)
    $isLaptop = (@($types | Where-Object { $laptopTypes -contains $_ }).Count -gt 0) -or ($chassisUnknown -and $bat.Count -gt 0)
    if ($UserMismatch) { Add-Flag 'system' 'check' 'Admin rights came from a different Windows account, so the per-user settings in this scan (Game Mode, mouse, startup apps, temp folder) belong to that account. Re-run without -Elevate to see this user''s own settings.' }
    $ver = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
               (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    $lastFix = $null
    try { $lastFix = Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1 } catch { }
    $uptime = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
    $firmware = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' 'PEFirmwareType'

    if ($pending) { Add-Flag 'system' 'check' 'Windows has a restart waiting. Restart before testing anything, then re-run the scan.' }
    if ($uptime -gt 168) { Add-Flag 'system' 'info' ('The PC has not restarted for ' + [math]::Round($uptime / 24) + ' days. A restart clears stuck drivers and finishes updates.') }
    if ($firmware -eq 1) { Add-Flag 'system' 'check' 'Windows is booting in old Legacy/CSM mode, not UEFI. Secure Boot and Resizable BAR need UEFI. Converting is possible but is a planned job, not a quick fix.' }

    [ordered]@{
        os = $os.Caption; displayVersion = $ver.DisplayVersion; build = ([string]$ver.CurrentBuild + '.' + [string]$ver.UBR)
        manufacturer = $cs.Manufacturer; model = $cs.Model
        formFactor = $(if ($isLaptop) { 'laptop' } else { 'desktop' })
        installedRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        lastBoot = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm'); uptimeHours = $uptime
        firmwareMode = $(switch ($firmware) { 1 { 'Legacy BIOS' } 2 { 'UEFI' } default { 'unknown' } })
        hypervisorPresent = $cs.HypervisorPresent
        pendingRestart = $pending
        lastUpdateInstalled = $(if ($lastFix) { Format-ShortDate $lastFix.InstalledOn } else { $null })
    }
}
$IsLaptop = ($R.system.formFactor -eq 'laptop')

# ---------------------------------------------------------------------------------------
# 2. CPU
# ---------------------------------------------------------------------------------------
Invoke-Section 'cpu' {
    $c = Get-CimInstance Win32_Processor | Select-Object -First 1
    $name = ([string]$c.Name).Trim()
    $rev = Get-RegValue 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' 'Update Revision'
    $microcode = $null
    if ($rev -is [byte[]]) {
        # Intel stores the revision in the upper four bytes of an 8-byte value; AMD uses a 4-byte value.
        if ($rev.Length -ge 8 -and $c.Manufacturer -match 'Intel') { $microcode = '0x{0:X}' -f [BitConverter]::ToUInt32($rev, 4) }
        elseif ($rev.Length -ge 4) { $microcode = '0x{0:X}' -f [BitConverter]::ToUInt32($rev, 0) }
    }
    if ($name -match 'Core\(TM\) i[579]-1[34]\d{3}(K|KF|KS|F|T)?\s' -or $name -match 'Core\(TM\) i[579]-1[34]\d{3}(K|KF|KS|F|T)?$') {
        $rev = $null
        if ($microcode) { try { $rev = [Convert]::ToUInt32($microcode.Substring(2), 16) } catch { } }
        if ($rev -and $rev -ge 0x12F) { Add-Flag 'cpu' 'good' ('Intel 13th/14th-gen desktop CPU with microcode ' + $microcode + ' (Intel''s stability fixes: 0x12B, then 0x12F).') }
        elseif ($rev -and $rev -ge 0x12B) { Add-Flag 'cpu' 'check' ('Intel 13th/14th-gen desktop CPU with microcode ' + $microcode + '. The main instability fix (0x12B) is in; Intel''s later 0x12F covers remaining idle and long-running cases. Check for a BIOS that carries it.') }
        else { Add-Flag 'cpu' 'fix' ('Intel 13th/14th-gen desktop CPU with microcode ' + $microcode + '. Intel''s stability fix needs microcode 0x12B or newer (0x12F is current), which arrives in a BIOS update. High priority.') }
    }
    if ($name -match 'X3D') {
        $dual = $name -match '(7900X3D|7950X3D|9900X3D|9950X3D)'
        $t = 'AMD X3D chip: keep the Balanced power plan and the AMD chipset driver installed.'
        if ($dual) { $t += ' This is a two-die X3D: keep Xbox Game Bar installed, because the chipset driver uses it to send games to the cache cores.' }
        Add-Flag 'cpu' 'info' $t
    }
    [ordered]@{
        name = $name; manufacturer = $c.Manufacturer; cores = $c.NumberOfCores; threads = $c.NumberOfLogicalProcessors
        maxClockMHz = $c.MaxClockSpeed; microcode = $microcode
        virtualisationEnabledInFirmware = $c.VirtualizationFirmwareEnabled
    }
}

# ---------------------------------------------------------------------------------------
# 3. GPU (plus nvidia-smi when present: temperature, power, PCIe link, Resizable BAR)
# ---------------------------------------------------------------------------------------
Invoke-Section 'gpu' {
    $list = @(Get-CimInstance Win32_VideoController | ForEach-Object {
        $age = $null
        if ($_.DriverDate) { $age = [int]((Get-Date) - $_.DriverDate).TotalDays }
        [ordered]@{
            name = $_.Name; driverVersion = $_.DriverVersion; driverDate = Format-ShortDate $_.DriverDate; driverAgeDays = $age
            status = $_.Status; videoProcessor = $_.VideoProcessor
        }
    })
    $smiPath = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (-not (Test-Path $smiPath)) { $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue; if ($cmd) { $smiPath = $cmd.Source } else { $smiPath = $null } }
    $nv = $null
    if ($smiPath) {
        $q = 'name,driver_version,temperature.gpu,power.draw,power.limit,clocks.gr,pstate,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,memory.total'
        $line = (& $smiPath "--query-gpu=$q" '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
        $memQ = (& $smiPath -q -d MEMORY 2>$null) -join "`n"
        $bar1 = $null
        if ($memQ -match 'BAR1 Memory Usage\s*\r?\n\s*Total\s*:\s*(\d+)\s*MiB') { $bar1 = [int]$matches[1] }
        if ($line) {
            $p = $line -split ',\s*'
            $nv = [ordered]@{
                name = $p[0]; driver = $p[1]; tempC = $p[2]; powerW = $p[3]; powerLimitW = $p[4]; coreClockMHz = $p[5]; pstate = $p[6]
                pcieGenNow = $p[7]; pcieGenMax = $p[8]; pcieWidthNow = $p[9]; pcieWidthMax = $p[10]; vramMiB = $p[11]; bar1TotalMiB = $bar1
                resizableBar = $(if ($null -eq $bar1) { 'unknown' } elseif ($bar1 -gt 1024) { 'on' } else { 'off' })
            }
            if ($bar1 -and $bar1 -le 1024) { Add-Flag 'gpu' 'fix' 'Resizable BAR looks OFF (the GPU can only see 256 MB of system memory at once). Turn on "Above 4G Decoding" and "Re-Size BAR" in the BIOS; needs UEFI boot with CSM off.' }
            elseif ($bar1) { Add-Flag 'gpu' 'good' 'Resizable BAR is on.' }
            try { if ([int]$p[9] -lt [int]$p[10]) { Add-Flag 'gpu' 'check' ('The graphics card is running at PCIe x' + $p[9] + ' instead of x' + $p[10] + '. Check it is in the top full-length slot (and any riser cable). Re-check while a game runs.') } } catch { }
            try { if ([double]$p[3] -gt 80 -and [int]$p[5] -gt 1500 -and $p[6] -eq 'P0') { Add-Flag 'gpu' 'info' ('The GPU is drawing ' + [math]::Round([double]$p[3]) + ' W at full clocks right now. If nothing heavy is running, check NVIDIA "Power management mode" is Normal, not "Prefer maximum performance".') } } catch { }
        }
    }
    foreach ($g in $list) {
        if ($g.driverAgeDays -and $g.driverAgeDays -gt 180 -and $g.name -match 'NVIDIA|Radeon RX|Radeon Pro|Arc') {
            Add-Flag 'gpu' 'check' ($g.name + ' driver is ' + [math]::Round($g.driverAgeDays / 30) + ' months old. Newer games often need a recent driver.')
        }
    }
    [ordered]@{ adapters = $list; nvidia = $nv }
}

# ---------------------------------------------------------------------------------------
# 4. Motherboard and BIOS
# ---------------------------------------------------------------------------------------
Invoke-Section 'motherboard' {
    $b = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $age = $null
    if ($bios.ReleaseDate) { $age = [int]((Get-Date) - $bios.ReleaseDate).TotalDays }
    if ($age -and $age -gt 365) {
        Add-Flag 'bios' 'check' ('BIOS ' + $bios.SMBIOSBIOSVersion + ' is dated ' + (Format-ShortDate $bios.ReleaseDate) + ' (' + [math]::Round($age / 30) + ' months old). Look up newer versions for this exact board and read what they fix (memory, stability, security).')
    }
    [ordered]@{
        manufacturer = $b.Manufacturer; product = $b.Product
        biosVendor = $bios.Manufacturer; biosVersion = $bios.SMBIOSBIOSVersion
        biosDate = Format-ShortDate $bios.ReleaseDate; biosAgeDays = $age
    }
}

# ---------------------------------------------------------------------------------------
# 5. Memory: speed now versus what the sticks are rated for (XMP / EXPO check)
# ---------------------------------------------------------------------------------------
Invoke-Section 'memory' {
    $sticks = @(Get-CimInstance Win32_PhysicalMemory)
    $slots = (Get-CimInstance Win32_PhysicalMemoryArray | Where-Object { $_.Use -eq 3 } | Measure-Object -Property MemoryDevices -Sum).Sum
    $typeMap = @{ 24 = 'DDR3'; 26 = 'DDR4'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $common = @(2133, 2400, 2666, 2933, 3000, 3200, 3333, 3466, 3600, 3733, 3800, 3866, 4000, 4133, 4266, 4400, 4600, 4800, 5000, 5200, 5400, 5600, 5800, 6000, 6200, 6400, 6600, 6800, 7000, 7200, 7400, 7600, 7800, 8000, 8200, 8400, 8600, 8800, 9000)
    $mods = @(foreach ($s in $sticks) {
        $pn = ([string]$s.PartNumber).Trim()
        $rated = $null
        foreach ($mt in [regex]::Matches($pn, '(?<!\d)(\d{4})(?!\d)')) { $v = [int]$mt.Groups[1].Value; if ($common -contains $v) { $rated = $v; break } }
        [ordered]@{
            slot = $s.DeviceLocator; bank = $s.BankLabel; sizeGB = [math]::Round($s.Capacity / 1GB)
            maker = $s.Manufacturer; partNumber = $pn
            type = $(if ($typeMap.ContainsKey([int]$s.SMBIOSMemoryType)) { $typeMap[[int]$s.SMBIOSMemoryType] } else { 'type ' + $s.SMBIOSMemoryType })
            baseSpeed = $s.Speed; runningSpeed = $s.ConfiguredClockSpeed; ratedSpeedGuessFromPartNumber = $rated
        }
    })
    $running = @($mods | ForEach-Object { $_.runningSpeed } | Where-Object { $_ } | Sort-Object -Unique)
    $ratedAll = @($mods | ForEach-Object { $_.ratedSpeedGuessFromPartNumber } | Where-Object { $_ } | Sort-Object -Unique)
    $parts = @($mods | ForEach-Object { $_.partNumber } | Sort-Object -Unique)
    $bases = @($mods | ForEach-Object { $_.baseSpeed } | Where-Object { $_ } | Sort-Object -Unique)
    $verdict = 'unknown: look up the part number to find the rated speed'
    if ($ratedAll.Count -eq 1 -and $running.Count -ge 1) {
        $r = $ratedAll[0]; $now = $running[0]; $base = $(if ($bases.Count -ge 1) { $bases[0] } else { $null })
        if ($now -ge ($r - 100)) { $verdict = 'running at its rated speed (XMP/EXPO on)'; Add-Flag 'memory' 'good' ('RAM is running at ' + $now + ' MT/s, its rated speed. XMP/EXPO is on.') }
        elseif ($base -and $now -gt ($base + 100)) {
            $verdict = 'profile or manual speed set, but below the rated speed'
            Add-Flag 'memory' 'check' ('RAM is running at ' + $now + ' MT/s: above the plain default (' + $base + ') but below the kit''s rated ' + $r + '. Either it was stepped down on purpose (the rated speed would not boot) or the speed was set by hand. Ask before suggesting changes.')
        }
        else {
            $verdict = 'running at the plain default speed (XMP/EXPO off)'
            Add-Flag 'memory' 'fix' ('RAM is rated ' + $r + ' MT/s (from the part number) but running at the default ' + $now + ' MT/s. XMP/EXPO is off: free performance, especially smoother 1% lows. Enabling it is a BIOS step for the user, using the retry ladder.')
        }
    }
    if (-not $IsLaptop) {
        if ($sticks.Count -eq 1) { Add-Flag 'memory' 'fix' 'Only one memory stick: the CPU is running single-channel, which costs a lot of performance in CPU-heavy games. A matched pair of sticks fixes it.' }
        if ($sticks.Count -eq 3) { Add-Flag 'memory' 'check' 'Three memory sticks: an odd number means uneven channels. Two matched sticks (or four) is the right shape.' }
        if ($sticks.Count -eq 4 -and ($mods | Where-Object { $_.type -eq 'DDR5' })) { Add-Flag 'memory' 'info' 'Four DDR5 sticks: most platforms cannot run four at the full rated speed. If XMP/EXPO will not hold, that is why; two larger sticks is the fix.' }
        if ($parts.Count -gt 1) { Add-Flag 'memory' 'check' ('Mixed memory part numbers (' + ($parts -join ', ') + '). Mixed kits are a common reason XMP/EXPO will not boot.') }
    }
    [ordered]@{
        totalSlots = $slots; sticksFitted = $sticks.Count; modules = $mods
        runningSpeeds = $running; verdict = $verdict
        note = 'baseSpeed is what Windows reports from the stick and is often the plain JEDEC default; the rated speed comes from the part number (a guess) or the maker''s page. CPU-Z (SPD tab) shows the XMP/EXPO profiles exactly.'
    }
}

# ---------------------------------------------------------------------------------------
# 6. Storage
# ---------------------------------------------------------------------------------------
Invoke-Section 'storage' {
    $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $disks = @(foreach ($d in $pd) {
        $row = [ordered]@{
            number = $d.DeviceId; name = $d.FriendlyName; media = [string]$d.MediaType; bus = [string]$d.BusType
            sizeGB = [math]::Round($d.Size / 1GB); health = [string]$d.HealthStatus; status = ([string[]]$d.OperationalStatus -join ',')
        }
        if ($isAdmin) {
            try {
                $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop
                $row['tempC'] = $rc.Temperature; $row['wearPercentUsed'] = $rc.Wear; $row['powerOnHours'] = $rc.PowerOnHours
                $row['readErrorsUncorrected'] = $rc.ReadErrorsUncorrected
                if ($rc.Wear -and $rc.Wear -ge 80) { Add-Flag 'storage' 'check' ($d.FriendlyName + ' has used ' + $rc.Wear + '% of its rated write life. Keep backups current.') }
            } catch { }
        }
        if ($row.health -and $row.health -ne 'Healthy') { Add-Flag 'storage' 'fix' ($d.FriendlyName + ' reports health "' + $row.health + '". Back up anything important on it now.') }
        $row
    })
    $diskMedia = @{}
    foreach ($d in $pd) { $diskMedia[[string]$d.DeviceId] = [string]$d.MediaType }
    $vols = @(foreach ($v in (Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter)) {
        $media = $null
        try { $dn = (Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop | Select-Object -First 1).DiskNumber; $media = $diskMedia[[string]$dn] } catch { }
        $freePct = $null
        if ($v.Size -gt 0) { $freePct = [math]::Round(100 * $v.SizeRemaining / $v.Size) }
        $letter = [string]$v.DriveLetter + ':'
        if ($null -ne $freePct) {
            if ($freePct -lt 10) { Add-Flag 'storage' 'fix' ($letter + ' is ' + (100 - $freePct) + '% full (' + (ConvertTo-GB $v.SizeRemaining) + ' GB free). Game updates and Windows updates need room; SSDs also slow down when nearly full.') }
            elseif ($freePct -lt 20) { Add-Flag 'storage' 'check' ($letter + ' has ' + $freePct + '% free. Aim for at least 15-20% free.') }
        }
        if ($letter -eq ($env:SystemDrive) -and $media -eq 'HDD') { Add-Flag 'storage' 'fix' 'Windows is on a spinning hard drive. Moving Windows to an SSD is the biggest single speed-up for loading and stutter.' }
        [ordered]@{ drive = $letter; label = $v.FileSystemLabel; fileSystem = $v.FileSystem; sizeGB = (ConvertTo-GB $v.Size); freeGB = (ConvertTo-GB $v.SizeRemaining); freePercent = $freePct; media = $media }
    })
    $trim = $null
    try { $trim = ((& fsutil behavior query DisableDeleteNotify 2>$null) -join ' ').Trim() } catch { }
    if ($trim -match 'NTFS DisableDeleteNotify = 1') { Add-Flag 'storage' 'fix' 'TRIM is switched off for NTFS. SSDs need TRIM to stay fast.' }
    [ordered]@{ disks = $disks; volumes = $vols; trim = $trim }
}

# ---------------------------------------------------------------------------------------
# 7. Windows gaming settings
# ---------------------------------------------------------------------------------------
Invoke-Section 'windowsSettings' {
    $dx = Get-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings'
    $tok = @{}
    if ($dx) { foreach ($t in ($dx -split ';')) { if ($t -match '^(\w+)=(.*)$') { $tok[$matches[1]] = $matches[2] } } }
    $schemeLine = ((& powercfg /getactivescheme 2>$null) -join ' ')
    $schemeGuid = $null; $schemeName = $null
    if ($schemeLine -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $schemeGuid = $matches[1].ToLower() }
    if ($schemeLine -match '\(([^)]+)\)\s*$') { $schemeName = $matches[1] }
    $overlay = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActiveOverlayAcPowerScheme'
    $hiber = $null
    try { $hf = Get-Item -LiteralPath ($env:SystemDrive + '\hiberfil.sys') -Force -ErrorAction Stop; $hiber = ConvertTo-GB $hf.Length } catch { }
    $gameMode = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    $hags = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    $capture = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    $dvr = Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    $mouse = Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed'
    $hvci = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    $vbs = $null
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $vbs = [ordered]@{ vbsStatus = $(switch ($dg.VirtualizationBasedSecurityStatus) { 0 { 'off' } 1 { 'enabled, not running' } 2 { 'running' } default { 'unknown' } }); memoryIntegrityRunning = (@($dg.SecurityServicesRunning) -contains 2) }
    } catch { }
    $lua = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    $consent = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    $hibEnabled = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
    $fastStart = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'

    if ($gameMode -eq 0) { Add-Flag 'windows' 'fix' 'Game Mode is OFF. On stops Windows Update and notifications from interrupting games.' }
    if ($hags -eq 1) { Add-Flag 'windows' 'check' 'Hardware-accelerated GPU scheduling is OFF. On is recommended for RTX 20-series and newer and Radeon RX 6000 and newer, and NVIDIA Frame Generation needs it.' }
    if ($tok['SwapEffectUpgradeEnable'] -eq '0') { Add-Flag 'windows' 'check' '"Optimizations for windowed games" is OFF. On gives lower latency and working G-Sync/FreeSync in borderless-window games.' }
    $known = @{ '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Balanced'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'High performance'; 'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Power saver'; 'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Ultimate Performance' }
    $planKind = $known[$schemeGuid]
    if ($planKind -eq 'Power saver') { Add-Flag 'windows' 'fix' 'The power plan is Power saver, which holds the CPU back. Balanced is right for gaming on modern CPUs.' }
    if (($planKind -eq 'High performance' -or $planKind -eq 'Ultimate Performance') -and $R.cpu.name -match '(7900X3D|7950X3D|9900X3D|9950X3D)') { Add-Flag 'windows' 'fix' ('The power plan is ' + $planKind + '. Two-die AMD X3D chips need Balanced for the cache cores to be chosen correctly.') }
    elseif ($planKind -eq 'High performance' -or $planKind -eq 'Ultimate Performance') { Add-Flag 'windows' 'info' ('The power plan is ' + $planKind + '. On modern CPUs Balanced games just as well and idles cooler; not urgent.') }
    if (-not $IsLaptop -and $hiber -and $hiber -gt 1) { Add-Flag 'windows' 'check' ('Hibernation is on: hiberfil.sys takes ' + $hiber + ' GB. On a desktop it can go (and Fast Startup with it, which also clears stale-driver issues).') }
    if ($mouse -eq '1') { Add-Flag 'windows' 'check' '"Enhance pointer precision" (mouse acceleration) is ON. Most players of shooters want it off for consistent aim.' }
    if ($lua -eq 0) { Add-Flag 'windows' 'fix' 'User Account Control is completely disabled (EnableLUA = 0). That weakens security and breaks some apps. Put it back to the default level.' }
    elseif ($consent -eq 0) { Add-Flag 'windows' 'check' 'User Account Control is set to "Never notify": programs get admin rights silently. The default level is safer and costs nothing in games.' }
    if ($vbs -and $vbs.memoryIntegrityRunning) { Add-Flag 'windows' 'info' 'Memory Integrity (Core isolation) is on. It costs a few percent in some CPU-heavy games; recommended to keep on for security. The user''s call.' }

    [ordered]@{
        gameMode = $(if ($null -eq $gameMode) { 'default (on)' } elseif ($gameMode -eq 1) { 'on' } else { 'off' })
        gpuScheduling = $(switch ($hags) { 2 { 'on' } 1 { 'off' } default { 'not set (Windows default)' } })
        windowedGameOptimisations = $(if ($tok.ContainsKey('SwapEffectUpgradeEnable')) { $(if ($tok['SwapEffectUpgradeEnable'] -eq '1') { 'on' } else { 'off' }) } else { 'not set (Windows default)' })
        variableRefreshRateOptimisation = $(if ($tok.ContainsKey('VRROptimizeEnable')) { $(if ($tok['VRROptimizeEnable'] -eq '1') { 'on' } else { 'off' }) } else { 'not set' })
        gameBarBackgroundCapture = $(if ($capture -eq 1 -or $dvr -eq 1) { 'on' } elseif ($null -eq $capture -and $null -eq $dvr) { 'not set' } else { 'off' })
        powerPlan = $(if ($planKind) { $planKind } else { $schemeName }); powerPlanGuid = $schemeGuid; powerModeOverlay = $overlay
        hibernation = $(if ($hibEnabled -eq 0) { 'off' } else { 'on' }); hiberfilGB = $hiber
        fastStartup = $(if ($fastStart -eq 1) { 'on' } elseif ($fastStart -eq 0) { 'off' } else { 'unknown' })
        mouseAcceleration = $(if ($mouse -eq '1') { 'on' } elseif ($mouse -eq '0') { 'off' } else { 'unknown' })
        memoryIntegritySetting = $(if ($hvci -eq 1) { 'on' } elseif ($hvci -eq 0) { 'off' } else { 'not set' })
        virtualisationSecurity = $vbs
        uac = [ordered]@{ enabled = ($lua -ne 0); consentPromptBehaviorAdmin = $consent }
    }
}

# ---------------------------------------------------------------------------------------
# 8. Security
# ---------------------------------------------------------------------------------------
Invoke-Section 'security' {
    $sb = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
    $av = @()
    try { $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $_.displayName } | Sort-Object -Unique) } catch { }
    $shell = New-Object -ComObject Shell.Application
    $bl = @(foreach ($v in $R.storage.volumes) {
        $code = $null
        try { $code = $shell.NameSpace($v.drive + '\').Self.ExtendedProperty('System.Volume.BitLockerProtection') } catch { }
        [ordered]@{ drive = $v.drive; bitlocker = $(switch ($code) { 1 { 'on' } 2 { 'off' } 3 { 'encrypting' } 4 { 'decrypting' } 5 { 'suspended' } 6 { 'on (locked)' } default { 'not encryptable or unknown' } }) }
    })
    $res = [ordered]@{ secureBoot = $(if ($sb -eq 1) { 'on' } elseif ($sb -eq 0) { 'off' } else { 'unknown' }); antivirus = $av; bitlockerQuick = $bl }
    if ($isAdmin) {
        try { $sbc = Confirm-SecureBootUEFI -ErrorAction Stop; $res['secureBootConfirmed'] = $sbc; $res.secureBoot = $(if ($sbc) { 'on' } else { 'off' }) } catch { $res['secureBootConfirmed'] = 'unavailable' }
        try { $t = Get-Tpm -ErrorAction Stop; $res['tpm'] = [ordered]@{ present = $t.TpmPresent; ready = $t.TpmReady; enabled = $t.TpmEnabled; maker = ([string]$t.ManufacturerIdTxt).Trim([char]0).Trim(); version = ([string]$t.ManufacturerVersion).Trim([char]0).Trim() } } catch { $res['tpm'] = 'unavailable' }
        try { $res['bitlocker'] = @(Get-BitLockerVolume -ErrorAction Stop | ForEach-Object { [ordered]@{ drive = $_.MountPoint; status = [string]$_.VolumeStatus; protection = [string]$_.ProtectionStatus; percent = $_.EncryptionPercentage } }) } catch { }
    }
    if ($res.secureBoot -eq 'off') { Add-Flag 'security' 'fix' 'Secure Boot is off. Several anti-cheat systems (for example Valorant, Battlefield 6 and recent Call of Duty) will not run without it. Loading BIOS defaults can switch it off silently, so re-check it after any BIOS change. Turning it back on is a BIOS step for the user.' }
    elseif ($res.secureBoot -eq 'on') { Add-Flag 'security' 'good' 'Secure Boot is on.' }
    if ($res.tpm -is [System.Collections.IDictionary] -and -not $res.tpm.ready) { Add-Flag 'security' 'check' 'The TPM security chip is not ready. Windows 11 and some anti-cheat systems need it (it is a BIOS switch: fTPM on AMD, PTT on Intel).' }
    $thirdParty = @($av | Where-Object { $_ -notmatch 'Windows Defender|Microsoft Defender' })
    if ($thirdParty.Count -ge 2) { Add-Flag 'security' 'fix' ('More than one antivirus is registered (' + ($thirdParty -join ', ') + '). Two real-time scanners fight each other and cause stutter. Keep one.') }
    $anyBl = @($bl | Where-Object { $_.bitlocker -match '^on|encrypting|suspended' })
    if ($anyBl.Count -gt 0) { Add-Flag 'security' 'check' ('BitLocker/Device Encryption is on (' + (($anyBl | ForEach-Object { $_.drive }) -join ' ') + '). Before any BIOS update, make sure the recovery key is saved (aka.ms/myrecoverykey) or the PC may ask for it after the flash.') }
    elseif ($bl.Count -gt 0) { Add-Flag 'security' 'good' 'BitLocker is off, so a BIOS update cannot trigger a recovery-key prompt.' }
    $res
}

# ---------------------------------------------------------------------------------------
# 9. Displays: current mode versus the monitor's native resolution and best refresh rate
# ---------------------------------------------------------------------------------------
Invoke-Section 'displays' {
    $rows = [PhcNative]::Displays()
    $dGpu = @($R.gpu.adapters | Where-Object { $_.name -match 'NVIDIA|Radeon RX|Radeon Pro|Arc' })
    $out = @(foreach ($r in $rows) {
        $native = $null
        $parts = $r[4] -split '\\'
        if ($parts.Count -ge 4) {
            $hw = $parts[1]; $drv = $parts[2] + '\' + $parts[3]
            foreach ($inst in (Get-ChildItem -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\' + $hw) -ErrorAction SilentlyContinue)) {
                $d = Get-RegValue $inst.PSPath 'Driver'
                if ($d -ne $drv) { continue }
                $edid = Get-RegValue (Join-Path $inst.PSPath 'Device Parameters') 'EDID'
                if ($edid -is [byte[]] -and $edid.Length -ge 128) {
                    $w = [int]$edid[56] + (([int]$edid[58] -band 0xF0) -shl 4)
                    $h = [int]$edid[59] + (([int]$edid[61] -band 0xF0) -shl 4)
                    $nm = $null
                    foreach ($off in 54, 72, 90, 108) { if ($edid[$off] -eq 0 -and $edid[$off + 1] -eq 0 -and $edid[$off + 3] -eq 0xFC) { $nm = ([Text.Encoding]::ASCII.GetString($edid, $off + 5, 13)).Trim() } }
                    $native = [ordered]@{ width = $w; height = $h; name = $nm }
                }
                break
            }
        }
        $curW = [int]$r[5]; $curH = [int]$r[6]; $curHz = [int]$r[7]
        $natW = $(if ($native -and $native.width -gt 0) { $native.width } else { [int]$r[8] })
        $natH = $(if ($native -and $native.height -gt 0) { $native.height } else { [int]$r[9] })
        $maxHzNative = [PhcNative]::MaxHzAt($r[0], $natW, $natH)
        $label = $(if ($native -and $native.name) { $native.name } else { $r[3] })
        if ($curW -gt 0 -and ($curW -ne $natW -or $curH -ne $natH)) { Add-Flag 'displays' 'fix' ($label + ' is running at ' + $curW + 'x' + $curH + ' but its native resolution is ' + $natW + 'x' + $natH + '. Everything on it is slightly blurry. Set native resolution and use Windows scaling (e.g. 150%) for size.') }
        if ([int]$r[11] -gt ($curHz + 1)) { Add-Flag 'displays' 'fix' ($label + ' is running at ' + $curHz + ' Hz but supports ' + $r[11] + ' Hz at this resolution. Settings > System > Display > Advanced display > refresh rate.') }
        elseif ($curHz -ge 100) { Add-Flag 'displays' 'good' ($label + ' is at its top refresh rate (' + $curHz + ' Hz).') }
        if (-not $IsLaptop -and $dGpu.Count -gt 0 -and $r[1] -notmatch 'NVIDIA|Radeon RX|Radeon Pro|Arc' -and $r[1] -match 'Intel|AMD Radeon\(TM\) Graphics|Radeon Graphics|UHD|Iris') { Add-Flag 'displays' 'fix' ($label + ' is plugged into the motherboard (' + $r[1] + '), not the graphics card. Move the cable to a port on the graphics card.') }
        [ordered]@{
            adapter = $r[1]; primary = ($r[2] -eq '1'); monitor = $label
            current = ([string]$curW + 'x' + $curH + ' @ ' + $curHz + ' Hz'); native = ([string]$natW + 'x' + $natH)
            bestHzAtCurrent = [int]$r[11]; bestHzAtNative = $maxHzNative
            largestModeOffered = ($r[8] + 'x' + $r[9]); nativeFrom = $(if ($native) { 'EDID' } else { 'largest mode offered (may include DSR/VSR)' })
        }
    })
    , $out
}

# ---------------------------------------------------------------------------------------
# 10. Drivers: devices with problems, chipset package, key driver dates
# ---------------------------------------------------------------------------------------
Invoke-Section 'drivers' {
    $problems = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 -and $_.ConfigManagerErrorCode -ne 45 } | ForEach-Object {
        $idParts = ([string]$_.PNPDeviceID) -split '\\'
        [ordered]@{ name = $_.Name; errorCode = $_.ConfigManagerErrorCode; class = $_.PNPClass; hardwareId = (($idParts | Select-Object -First 2) -join '\') }
    })
    if ($problems.Count -gt 0) { Add-Flag 'drivers' 'fix' ([string]$problems.Count + ' device(s) have no working driver (Device Manager yellow triangles). Usually the motherboard chipset, Wi-Fi or Bluetooth package is missing. Get them from the motherboard maker''s support page for this exact board.') }
    else { Add-Flag 'drivers' 'good' 'No devices with missing or failed drivers.' }
    $chipset = @(Find-Apps 'AMD Chipset Software|Intel\(R\) Chipset Device Software|Intel Chipset')
    if ($R.cpu.manufacturer -match 'AMD' -and $chipset.Count -eq 0 -and -not $IsLaptop) { Add-Flag 'drivers' 'fix' 'The AMD chipset driver package does not appear to be installed. It controls power management and core scheduling (essential on X3D chips). Install it from the motherboard maker or amd.com.' }
    $signed = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)
    $pick = {
        param($cls, $exclude)
        @($signed | Where-Object { $_.DeviceClass -eq $cls -and $_.DeviceName -and $_.DeviceName -notmatch $exclude } | ForEach-Object {
            [ordered]@{ device = $_.DeviceName; maker = $_.Manufacturer; version = $_.DriverVersion; date = Format-ShortDate $_.DriverDate }
        } | Select-Object -First 12)
    }
    [ordered]@{
        problemDevices = $problems
        chipsetPackage = $chipset
        network = @(& $pick 'NET' 'WAN Miniport|Virtual|Kernel Debug|Personal Area|Wi-Fi Direct|Teredo|isatap|6to4|Loopback')
        audio = @(& $pick 'MEDIA' 'Virtual|Remote|Streaming')
        oldestSystemDrivers = @($signed | Where-Object { $_.DeviceClass -eq 'SYSTEM' -and $_.Manufacturer -match 'AMD|Advanced Micro|Intel' -and $_.DriverDate } | Sort-Object DriverDate | Select-Object -First 6 | ForEach-Object { [ordered]@{ device = $_.DeviceName; version = $_.DriverVersion; date = Format-ShortDate $_.DriverDate } })
    }
}

# ---------------------------------------------------------------------------------------
# 11. Software that commonly conflicts
# ---------------------------------------------------------------------------------------
Invoke-Section 'software' {
    $cats = [ordered]@{
        vpn        = 'NordVPN|ExpressVPN|Private Internet Access|Surfshark|ProtonVPN|Proton VPN|CyberGhost|Windscribe|Mullvad|IPVanish|Hotspot Shield|TunnelBear|PureVPN|Atlas VPN|hide\.me|VyprVPN'
        antivirus  = 'Norton|McAfee|Avast|AVG |AVG Antivirus|Bitdefender|Kaspersky|ESET|Avira|TotalAV|Total AV|Webroot|Sophos|Panda Dome|Trend Micro|F-Secure|BullGuard|Malwarebytes'
        captureAndOverlay = 'OBS Studio|Medal|Outplayed|Overwolf|Streamlabs|XSplit|Bandicam|Action!|NVIDIA App|GeForce Experience|ShareX|MSI Afterburner|RivaTuner|HudSight|Crosshair|FPS Monitor|Plays\.tv'
        rgbAndPeripheral  = 'Razer Synapse|Razer Central|Logitech G HUB|LGHUB|Corsair iCUE|iCUE|SteelSeries GG|Armoury Crate|AURA|MSI Center|Mystic Light|Dragon Center|RGB Fusion|GIGABYTE Control Center|NZXT CAM|Glorious Core|NGENUITY|Alienware Command Center|OpenRGB|SignalRGB|Wooting|ROCCAT Swarm|Cooler Master MasterPlus|Lian Li L-Connect|ASUS AI Suite'
        optimisers = 'CCleaner|Driver Booster|Advanced SystemCare|IObit|Razer Cortex|Game Booster|Wise Game Booster|Driver Easy|Reimage|Restoro|PC Cleaner|System Mechanic|Avast Cleanup|AVG TuneUp|Auslogics|Glary|WinOptimizer|Smart Game Booster|DriverPack'
        torrent    = 'qBittorrent|uTorrent|BitTorrent|Deluge|Transmission|Vuze|Tixati'
        emulatorsAndVMs = 'BlueStacks|MuMu|LDPlayer|Nox|MEmu|Docker Desktop|VirtualBox|VMware|Windows Subsystem for Android'
        launchers  = 'Steam|Epic Games Launcher|EA app|EA Desktop|Origin|Ubisoft Connect|Battle\.net|GOG GALAXY|Riot Client|Rockstar Games Launcher|Xbox|Amazon Games|Battlestate Games Launcher|itch\.io|^itch$'
    }
    $found = [ordered]@{}
    foreach ($k in $cats.Keys) { $found[$k] = @(Find-Apps $cats[$k]) }
    if ($AppxNames -contains 'Microsoft.GamingApp') { $found['launchers'] += 'Xbox app (Store)' }
    # Antivirus conflicts are judged from Windows Security Center's own list (security
    # section), not from app names: suites ship companion apps (browsers, password managers).
    if ($found.vpn.Count -ge 2) { Add-Flag 'conflicts' 'fix' ('More than one VPN is installed (' + ($found.vpn -join ', ') + '). Each adds its own network driver and filter, even when not connected. Keep the one in use.') }
    $recorders = @($found.captureAndOverlay | Where-Object { $_ -match 'OBS|Medal|Outplayed|Streamlabs|XSplit|Bandicam|Action!|NVIDIA App|GeForce Experience|ShareX|Plays\.tv' })
    $gbOn = ($R.windowsSettings.gameBarBackgroundCapture -eq 'on')
    if (($recorders.Count + [int]$gbOn) -ge 2) { Add-Flag 'conflicts' 'check' ('More than one recording/clip tool is set up (' + (@($recorders + $(if ($gbOn) { 'Xbox Game Bar capture' })) -join ', ') + '). Two recorders running at once waste performance. Pick one.') }
    if ($found.rgbAndPeripheral.Count -ge 3) { Add-Flag 'conflicts' 'check' ('Several RGB/peripheral apps are installed (' + ($found.rgbAndPeripheral -join ', ') + '). They can fight over the same devices and some poll hard enough to cause stutter. Keep the ones for devices actually in use (ask: wireless devices may not show up in the scan).') }
    if ($found.optimisers.Count -ge 1) { Add-Flag 'conflicts' 'check' ('"Optimiser"/booster/cleaner apps are installed (' + ($found.optimisers -join ', ') + '). They change the same settings this check does, and some are known for bundled junk. Usually best removed.') }
    if ($found.torrent.Count -ge 2) { Add-Flag 'conflicts' 'info' ('Two or more torrent clients (' + ($found.torrent -join ', ') + '). Keep one.') }
    if ($found.emulatorsAndVMs.Count -ge 1) { Add-Flag 'software' 'info' ('Virtualisation software is installed (' + ($found.emulatorsAndVMs -join ', ') + '). It keeps the Windows hypervisor running, which costs a little in CPU-heavy games. Fine if used; if not, removing it can give a few percent back.') }
    $big = @($Apps | Where-Object { $_.sizeGB -and $_.sizeGB -ge 5 } | Sort-Object sizeGB -Descending | ForEach-Object { [ordered]@{ name = $_.name; sizeGB = $_.sizeGB; installed = $_.installDate; location = $_.location } })
    [ordered]@{ categories = $found; bigInstalls = $big; installedCount = $Apps.Count; installedNames = @($Apps | ForEach-Object { $_.name }) }
}

# ---------------------------------------------------------------------------------------
# 12. Startup load: Run keys, Startup folders, logon tasks and third-party services
# ---------------------------------------------------------------------------------------
Invoke-Section 'startup' {
    $approvedRoots = @{
        'HKCU|Run'           = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        'HKLM|Run'           = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        'HKLM|Run32'         = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
        'HKCU|StartupFolder' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        'HKLM|StartupFolder' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    }
    function Get-StartupState($key, $name) {
        $v = Get-RegValue $approvedRoots[$key] $name
        if ($v -is [byte[]] -and $v.Length -gt 0) { if (($v[0] -band 1) -eq 1) { return 'disabled' } else { return 'enabled' } }
        return 'enabled'
    }
    $items = New-Object System.Collections.ArrayList
    $runKeys = @(
        @{ key = 'HKCU|Run'; path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ key = 'HKLM|Run'; path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ key = 'HKLM|Run32'; path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
    )
    foreach ($rk in $runKeys) {
        $k = Get-Item -LiteralPath $rk.path -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            [void]$items.Add([ordered]@{ name = $n; source = $rk.key; state = (Get-StartupState $rk.key $n); command = [string]$k.GetValue($n) })
        }
    }
    $folders = @(@{ key = 'HKCU|StartupFolder'; path = [Environment]::GetFolderPath('Startup') }, @{ key = 'HKLM|StartupFolder'; path = [Environment]::GetFolderPath('CommonStartup') })
    foreach ($f in $folders) {
        if (-not $f.path -or -not (Test-Path -LiteralPath $f.path)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $f.path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
            [void]$items.Add([ordered]@{ name = $file.Name; source = $f.key; state = (Get-StartupState $f.key $file.Name); command = $file.FullName })
        }
    }
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' -and (@($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }).Count -gt 0) } | ForEach-Object {
            [ordered]@{ name = $_.TaskName; path = $_.TaskPath; runs = (@($_.Actions | ForEach-Object { $_.Execute }) -join '; ') }
        })
    } catch { }
    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -and $_.PathName -notmatch '\\Windows\\|svchost' } | ForEach-Object {
        [ordered]@{ name = $_.DisplayName; state = $_.State }
    } | Sort-Object { $_.name })
    $enabled = @($items | Where-Object { $_.state -eq 'enabled' })
    if ($enabled.Count -gt 15) { Add-Flag 'startup' 'check' ([string]$enabled.Count + ' apps start with Windows. Trimming the ones not needed every session frees memory and speeds up boot.') }
    [ordered]@{ enabledCount = $enabled.Count; items = @($items); logonTasks = $tasks; thirdPartyAutoServices = $services }
}

# ---------------------------------------------------------------------------------------
# 13. What is using memory right now
# ---------------------------------------------------------------------------------------
Invoke-Section 'background' {
    $os = Get-CimInstance Win32_OperatingSystem
    $usedPct = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
    $top = @(Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; processes = $_.Count; ramMB = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB) }
    } | Sort-Object ramMB -Descending | Select-Object -First 25)
    if ($usedPct -ge 60) { Add-Flag 'background' 'check' ('About ' + $usedPct + '% of memory is in use right now. If no game is running, the background apps list shows where it goes.') }
    [ordered]@{ memoryInUsePercent = $usedPct; topByMemory = @($top | ForEach-Object { [ordered]@{ name = $_.name; processes = $_.processes; ramMB = $_.ramMB } }) }
}

# ---------------------------------------------------------------------------------------
# 14. Crash and hardware-error history
# ---------------------------------------------------------------------------------------
Invoke-Section 'events' {
    $since = (Get-Date).AddDays(-$EventDays)
    function Get-Events($filter) { try { return @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) } catch { return @() } }
    $whea = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since })
    $kp41 = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since })
    $bsod = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since })
    $tdr = @(Get-Events @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $since })
    $appErr = @(Get-Events @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since })
    $hangs = @(Get-Events @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $since })

    $wheaById = @($whea | Group-Object Id | ForEach-Object { [ordered]@{ id = [int]$_.Name; count = $_.Count; last = $_.Group[0].TimeCreated.ToString('yyyy-MM-dd HH:mm') } })
    $powerLoss = @($kp41 | ForEach-Object {
        $bug = $null; $btn = $null
        try {
            $data = ([xml]$_.ToXml()).Event.EventData.Data
            $bug = [string](@($data | Where-Object { $_.Name -eq 'BugcheckCode' })[0].'#text')
            $btn = [string](@($data | Where-Object { $_.Name -eq 'PowerButtonTimestamp' })[0].'#text')
        } catch { }
        # Logged when Windows next starts, so the real power-off was earlier (event 6008 has the exact time).
        [ordered]@{ when = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'); loggedAt = 'next start-up'; bugcheckCode = $bug; powerButtonPressed = ($btn -and $btn -ne '0') }
    })
    $crashApps = @($appErr | ForEach-Object {
        $app = $null; $mod = $null
        try { $app = [string]$_.Properties[0].Value; $mod = [string]$_.Properties[3].Value } catch { }
        [pscustomobject]@{ app = $app; module = $mod; when = $_.TimeCreated }
    } | Group-Object app | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        [ordered]@{ app = $_.Name; crashes = $_.Count; last = ($_.Group | Sort-Object when -Descending | Select-Object -First 1).when.ToString('yyyy-MM-dd'); commonModule = ($_.Group | Group-Object module | Sort-Object Count -Descending | Select-Object -First 1).Name }
    })
    if ($whea.Count -gt 0) { Add-Flag 'events' 'fix' ([string]$whea.Count + ' hardware error report(s) (WHEA) in the last ' + $EventDays + ' days, event IDs ' + (($wheaById | ForEach-Object { $_.id }) -join ', ') + '. IDs 19 and 47 often point at memory or CPU-fabric instability (for example XMP/EXPO too fast); 17 is usually harmless PCIe chatter. Worth a closer look before any overclock.') }
    else { Add-Flag 'events' 'good' ('No hardware errors (WHEA) in the last ' + $EventDays + ' days.') }
    $silent = @($powerLoss | Where-Object { -not $_.bugcheckCode -or $_.bugcheckCode -eq '0' })
    $buttoned = @($silent | Where-Object { $_.powerButtonPressed })
    $unexplained = @($silent | Where-Object { -not $_.powerButtonPressed })
    if ($buttoned.Count -gt 0) { Add-Flag 'events' 'info' ([string]$buttoned.Count + ' forced power-off(s) where Windows recorded the power button being pressed (' + (($buttoned | ForEach-Object { $_.when }) -join ', ') + '). Probably someone held the button; confirm with the user.') }
    if ($unexplained.Count -gt 0) { Add-Flag 'events' 'check' ([string]$unexplained.Count + ' sudden power-off(s) with no error logged (noticed at the next start-up: ' + (($unexplained | ForEach-Object { $_.when }) -join ', ') + '). Ask before assuming hardware: holding the power button can log the same thing. If it really switched itself off mid-game, suspect the power supply or a hard freeze.') }
    if ($bsod.Count -gt 0) { Add-Flag 'events' 'fix' ([string]$bsod.Count + ' blue-screen crash(es) in the last ' + $EventDays + ' days. The bugcheck codes and minidumps (C:\Windows\Minidump) say why.') }
    if ($tdr.Count -gt 0) { Add-Flag 'events' 'check' ('The graphics driver stopped responding and recovered ' + $tdr.Count + ' time(s). Common causes: an unstable GPU overclock, an old driver, or power delivery.') }
    [ordered]@{
        days = $EventDays
        hardwareErrorsWHEA = [ordered]@{ total = $whea.Count; byId = $wheaById }
        suddenPowerOffs = $powerLoss
        blueScreens = @($bsod | Select-Object -First 10 | ForEach-Object { [ordered]@{ when = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'); message = (([string]$_.Message) -split "`n")[0] } })
        graphicsDriverResets = $tdr.Count
        appCrashes = $crashApps
        appHangs = @($hangs | ForEach-Object { try { [string]$_.Properties[0].Value } catch { $null } } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { [ordered]@{ app = $_.Name; hangs = $_.Count } })
    }
}

# ---------------------------------------------------------------------------------------
# 15. Games: Steam, Epic, Xbox app, and other launchers' installs
# ---------------------------------------------------------------------------------------
Invoke-Section 'games' {
    $steam = [ordered]@{ installed = $false }
    $steamPath = Get-RegValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    $libPaths = @()
    if ($steamPath) {
        $steamPath = $steamPath -replace '/', '\'
        $steam.installed = $true
        $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) { $libPaths = @([regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }) }
        if ($libPaths.Count -eq 0) { $libPaths = @($steamPath) }
        $gamesList = New-Object System.Collections.ArrayList
        foreach ($lib in $libPaths) {
            foreach ($acf in (Get-ChildItem -LiteralPath (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
                $t = Get-Content -LiteralPath $acf.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $t) { continue }
                $get = { param($key) if ($t -match ('"' + $key + '"\s+"([^"]*)"')) { $matches[1] } else { $null } }
                $lp = Get-FromUnixTime (& $get 'LastPlayed')
                $lu = Get-FromUnixTime (& $get 'LastUpdated')
                $size = & $get 'SizeOnDisk'
                [void]$gamesList.Add([pscustomobject]@{
                    appid = (& $get 'appid'); name = (& $get 'name'); library = $lib
                    sizeGB = $(if ($size) { ConvertTo-GB ([double]$size) } else { $null })
                    lastPlayed = $(if ($lp) { $lp.ToString('yyyy-MM-dd') } else { 'never or unknown' })
                    daysSincePlayed = $(if ($lp) { [int]((Get-Date) - $lp).TotalDays } else { $null })
                    lastUpdated = $(if ($lu) { $lu.ToString('yyyy-MM-dd') } else { $null })
                })
            }
        }
        $steam['libraries'] = $libPaths
        $steam['totalGB'] = [math]::Round(($gamesList | Measure-Object sizeGB -Sum).Sum, 1)
        $steam['games'] = @($gamesList | Sort-Object sizeGB -Descending | ForEach-Object { [ordered]@{ appid = $_.appid; name = $_.name; sizeGB = $_.sizeGB; lastPlayed = $_.lastPlayed; daysSincePlayed = $_.daysSincePlayed; library = $_.library } })
        $stale = @($gamesList | Where-Object { ($_.daysSincePlayed -and $_.daysSincePlayed -gt 365) -or $_.lastPlayed -eq 'never or unknown' } | Where-Object { $_.sizeGB -ge 1 -and $_.name -notmatch 'Steamworks Common|Redistributable|Proton|Steam Linux Runtime' })
        $staleGB = [math]::Round(($stale | Measure-Object sizeGB -Sum).Sum)
        if ($staleGB -ge 20) { Add-Flag 'space' 'check' ([string]$stale.Count + ' Steam games (' + $staleGB + ' GB) have not been played for over a year or never. The user decides what goes.') }
        $extra = @()
        foreach ($lib in $libPaths) { foreach ($sub in 'downloading', 'temp', 'shadercache', 'workshop') { $p = Join-Path $lib ('steamapps\' + $sub); if (Test-Path -LiteralPath $p) { if ($Quick) { $extra += [ordered]@{ path = $p } } else { $extra += (Measure-Folder $p 20) } } } }
        $steam['steamFolders'] = $extra
    }
    $epic = @()
    $epicDir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path -LiteralPath $epicDir) {
        $epic = @(Get-ChildItem -LiteralPath $epicDir -Filter '*.item' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $j = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                [ordered]@{ name = $j.DisplayName; location = $j.InstallLocation; sizeGB = $(if ($j.InstallSize) { ConvertTo-GB ([double]$j.InstallSize) } else { $null }) }
            } catch { }
        })
    }
    $xbox = @()
    foreach ($v in $R.storage.volumes) {
        $xd = $v.drive + '\XboxGames'
        if (Test-Path -LiteralPath $xd) {
            foreach ($g in (Get-ChildItem -LiteralPath $xd -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'GameSave' })) {
                if ($Quick) { $xbox += [ordered]@{ name = $g.Name; path = $g.FullName } }
                else { $m = Measure-Folder $g.FullName 30; if ($m) { $xbox += [ordered]@{ name = $g.Name; path = $g.FullName; sizeGB = $m.sizeGB; lastChanged = $m.newestFile } } }
            }
        }
    }
    $otherPublishers = 'Blizzard|Electronic Arts|Ubisoft|Riot Games|Rockstar|Bethesda|Activision|Battlestate|Grinding Gear|Jagex|Square Enix|Bandai|CD PROJEKT|Wargaming|Bungie|Respawn'
    $others = @($Apps | Where-Object { $_.publisher -match $otherPublishers -or $_.location -match 'GOG Games|Battle\.net|Riot Games|Ubisoft Game Launcher\\games|EA Games' } |
        Where-Object { $_.name -notmatch 'Launcher|Battle\.net|EA app|Ubisoft Connect|Riot Client|Vanguard|Redistributable|Update Helper' } |
        ForEach-Object { [ordered]@{ name = $_.name; publisher = $_.publisher; sizeGB = $_.sizeGB; installed = $_.installDate; location = $_.location } })
    [ordered]@{ steam = $steam; epic = $epic; xboxApp = $xbox; otherLaunchers = $others }
}

# ---------------------------------------------------------------------------------------
# 16. Space: clean-up candidates, caches to keep, and the biggest folders
# ---------------------------------------------------------------------------------------
Invoke-Section 'space' {
    $sys = $env:SystemDrive
    $junk = [ordered]@{}
    $junkPaths = [ordered]@{
        userTemp = $env:TEMP
        windowsTemp = ($env:SystemRoot + '\Temp')
        nvidiaDownloadedInstallers = ($env:ProgramData + '\NVIDIA Corporation\Downloader')
        crashDumps = ($env:LOCALAPPDATA + '\CrashDumps')
        windowsMinidumps = ($env:SystemRoot + '\Minidump')
        windowsUpdateDownloads = ($env:SystemRoot + '\SoftwareDistribution\Download')
        windowsOld = ($sys + '\Windows.old')
    }
    foreach ($k in $junkPaths.Keys) { if ($Quick) { $junk[$k] = [ordered]@{ path = $junkPaths[$k]; exists = (Test-Path -LiteralPath $junkPaths[$k]) } } else { $junk[$k] = Measure-Folder $junkPaths[$k] 30 } }
    $memDmp = $sys + '\Windows\MEMORY.DMP'
    if (Test-Path -LiteralPath $memDmp) { try { $junk['memoryDump'] = [ordered]@{ path = $memDmp; sizeGB = ConvertTo-GB (Get-Item -LiteralPath $memDmp -Force).Length } } catch { } }
    if ($junk.windowsOld -and $junk.windowsOld.sizeGB) { Add-Flag 'space' 'check' ('Windows.old (the previous Windows version, ' + $junk.windowsOld.sizeGB + ' GB) is still there. Once the PC has been fine for 10 days it can go via Settings > System > Storage > Temporary files.') }

    $keep = [ordered]@{}
    $keepPaths = [ordered]@{
        nvidiaDXCache = ($env:LOCALAPPDATA + '\NVIDIA\DXCache')
        nvidiaGLCache = ($env:LOCALAPPDATA + '\NVIDIA\GLCache')
        directXShaderCache = ($env:LOCALAPPDATA + '\D3DSCache')
        amdDxCache = ($env:LOCALAPPDATA + '\AMD\DxCache')
        amdDxcCache = ($env:LOCALAPPDATA + '\AMD\DxcCache')
    }
    foreach ($k in $keepPaths.Keys) { if (Test-Path -LiteralPath $keepPaths[$k]) { if ($Quick) { $keep[$k] = [ordered]@{ path = $keepPaths[$k] } } else { $keep[$k] = Measure-Folder $keepPaths[$k] 20 } } }

    $recycle = $null
    try {
        $sh = New-Object -ComObject Shell.Application
        $sum = [double]0; $n = 0
        foreach ($i in $sh.NameSpace(10).Items()) { $n++; if ($n -gt 20000) { break }; try { $sum += [double]$i.ExtendedProperty('System.Size') } catch { } }
        $recycle = [ordered]@{ items = $n; sizeGB = (ConvertTo-GB $sum) }
        if ($recycle.sizeGB -ge 5) { Add-Flag 'space' 'check' ('The Recycle Bin holds ' + $recycle.sizeGB + ' GB of already-deleted files. Emptying it is the user''s call.') }
    } catch { }

    $biggest = @()
    if (-not $Quick) {
        $targets = New-Object System.Collections.ArrayList
        foreach ($f in 'Downloads', 'Videos', 'Desktop', 'Documents', 'Pictures', 'Music') {
            $p = Join-Path $env:USERPROFILE $f
            if (Test-Path -LiteralPath $p) { [void]$targets.Add($p) }
        }
        $vid = [Environment]::GetFolderPath('MyVideos')
        if ($vid -and -not $targets.Contains($vid)) { [void]$targets.Add($vid) }
        $skipC = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', '$Recycle.Bin', 'System Volume Information', 'Recovery', '$WinREAgent', 'PerfLogs', 'Config.Msi', 'Documents and Settings', 'OneDriveTemp', '$SysReset', '$Windows.~BT', '$Windows.~WS', 'Windows.old', 'XboxGames')
        $steamLibs = @($R.games.steam.libraries | ForEach-Object { ([string]$_).TrimEnd('\').ToLower() })
        foreach ($v in $R.storage.volumes) {
            foreach ($d in (Get-ChildItem -LiteralPath ($v.drive + '\') -Directory -Force -ErrorAction SilentlyContinue)) {
                if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($skipC -contains $d.Name) { continue }
                if ($steamLibs -contains $d.FullName.TrimEnd('\').ToLower()) { continue }
                if ($d.Name -match '^\$') { continue }
                [void]$targets.Add($d.FullName)
            }
        }
        $sized = @(foreach ($t in $targets) { Measure-Folder $t 45 })
        $local = @(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -Directory -Force -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 } | ForEach-Object { Measure-Folder $_.FullName 15 })
        $biggest = @(($sized + $local) | Where-Object { $_ -and $_.sizeGB -ge 2 } | Sort-Object { [double]$_.sizeGB } -Descending | Select-Object -First 30)
        $videoHeavy = @($sized | Where-Object { $_ -and $_.videoGB -ge 20 })
        foreach ($vh in $videoHeavy) { Add-Flag 'space' 'check' ($vh.path + ' holds ' + $vh.videoGB + ' GB of video files (newest file ' + $vh.newestFile + '). Old game recordings and clips are often the biggest easy win; films and family videos are not. The user decides.') }
    }
    [ordered]@{ cleanupCandidates = $junk; shaderCachesKeep = $keep; recycleBin = $recycle; biggestFolders = $biggest; note = 'Shader caches are listed so they are NOT deleted: clearing them causes stutter while games rebuild them.' }
}

# ---------------------------------------------------------------------------------------
# 17. Network
# ---------------------------------------------------------------------------------------
Invoke-Section 'network' {
    $ads = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object { $_.Name } | ForEach-Object {
        [ordered]@{ name = $_.Name; description = $_.InterfaceDescription; status = [string]$_.Status; linkSpeed = [string]$_.LinkSpeed; physical = [bool]$_.HardwareInterface; virtual = [bool]$_.Virtual }
    })
    $up = @($ads | Where-Object { $_.status -eq 'Up' -and $_.physical })
    $wiredUp = @($up | Where-Object { $_.description -notmatch 'Wi-?Fi|Wireless|WLAN|802\.11' })
    $wifiUp = @($up | Where-Object { $_.description -match 'Wi-?Fi|Wireless|WLAN|802\.11' })
    if (-not $IsLaptop -and $wiredUp.Count -eq 0 -and $wifiUp.Count -gt 0) { Add-Flag 'network' 'info' 'This desktop is on Wi-Fi. A cable gives steadier ping in online games, if one can reach.' }
    foreach ($w in $wiredUp) { if ($w.linkSpeed -match '^100 Mbps') { Add-Flag 'network' 'fix' ('The wired connection (' + $w.description + ') is linked at only 100 Mbps. Usually a damaged or old cable, or a loose plug. Try another cable.') } }
    $tunnels = @($ads | Where-Object { $_.description -match 'TAP|Wintun|WireGuard|NordLynx|OpenVPN|TUN|VPN' })
    $bindings = @()
    foreach ($a in $wiredUp + $wifiUp) {
        try { $bindings += @(Get-NetAdapterBinding -Name $a.name -ErrorAction Stop | Where-Object { $_.Enabled -and $_.ComponentID -notmatch '^ms_' } | ForEach-Object { [ordered]@{ adapter = $a.name; component = $_.DisplayName; id = $_.ComponentID } }) } catch { }
    }
    [ordered]@{ adapters = $ads; vpnAndTunnelAdapters = @($tunnels | ForEach-Object { $_.description }); thirdPartyFiltersOnActiveAdapters = $bindings }
}

# ---------------------------------------------------------------------------------------
# 18. Peripherals Windows can see (so their apps are not switched off by mistake)
# ---------------------------------------------------------------------------------------
Invoke-Section 'peripherals' {
    $vids = @{ '046D' = 'Logitech'; '1532' = 'Razer'; '1038' = 'SteelSeries'; '1B1C' = 'Corsair'; '0951' = 'HyperX (Kingston)'; '03F0' = 'HP/HyperX'; '0B05' = 'ASUS'; '1E7D' = 'ROCCAT/Turtle Beach'; '258A' = 'Glorious/generic'; '320F' = 'Glorious'; '3434' = 'Keychron'; '31E3' = 'Wooting'; '0FD9' = 'Elgato'; '2516' = 'Cooler Master'; '1462' = 'MSI'; '04D9' = 'generic keyboard'; '045E' = 'Microsoft'; '054C' = 'Sony'; '057E' = 'Nintendo'; '28DE' = 'Valve'; '2833' = 'Meta/Oculus'; '0BB4' = 'HTC'; '044F' = 'Thrustmaster'; '046A' = 'Cherry'; '3537' = 'GameSir'; '2DC8' = '8BitDo'; '0D8C' = 'USB audio'; '2972' = 'FiiO'; '19F7' = 'RODE'; '1235' = 'Focusrite'; '0B0E' = 'Jabra'; '1395' = 'EPOS/Sennheiser' }
    $devs = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^(USB|HID)\\VID_([0-9A-F]{4})' })
    $brands = @{}
    foreach ($d in $devs) { if ($d.InstanceId -match 'VID_([0-9A-F]{4})') { $v = $matches[1]; if ($vids.ContainsKey($v)) { $brands[$vids[$v]] = $true } } }
    $bt = @(Get-PnpDevice -PresentOnly -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -notmatch 'Enumerator|Radio|Adapter|Generic|Microsoft|Service|Protocol|RFCOMM|LE ' } | ForEach-Object { $_.FriendlyName } | Sort-Object -Unique)
    [ordered]@{
        usbBrandsSeen = @($brands.Keys | Sort-Object)
        bluetoothDevices = $bt
        note = 'Wireless and Bluetooth peripherals often show up under a generic or receiver brand (or not at all). Never switch off a peripheral app just because its brand is missing here: ask first.'
    }
}

# ---------------------------------------------------------------------------------------
# 19. Admin-only extras
# ---------------------------------------------------------------------------------------
if ($isAdmin) {
    Invoke-Section 'adminExtras' {
        $h = $null
        try { $h = ((& bcdedit /enum '{current}' 2>$null) | Select-String 'hypervisorlaunchtype' | ForEach-Object { ($_.Line -split '\s+')[-1] }) } catch { }
        $feats = [ordered]@{}
        foreach ($f in 'VirtualMachinePlatform', 'Microsoft-Hyper-V-All', 'HypervisorPlatform', 'Microsoft-Windows-Subsystem-Linux', 'Containers-DisposableClientVM') {
            try { $feats[$f] = [string](Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State } catch { $feats[$f] = 'n/a' }
        }
        $rp = $null
        try { $last = Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -Last 1; if ($last) { $rp = [ordered]@{ last = $last.ConvertToDateTime($last.CreationTime).ToString('yyyy-MM-dd HH:mm'); description = $last.Description } } } catch { }
        # Secure Boot key databases (read-only). Microsoft moved Windows to its 2023 certificate;
        # restoring "default keys" on a BIOS whose defaults lack it can stop Windows booting.
        $keys = [ordered]@{}
        foreach ($n in 'db', 'dbDefault', 'KEK', 'KEKDefault') {
            try {
                $txt = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name $n -ErrorAction Stop).Bytes)
                $keys[$n] = [ordered]@{ windowsUefiCa2023 = ($txt -match 'Windows UEFI CA 2023'); kekCa2023 = ($txt -match 'KEK 2K CA 2023|KEK CA 2023'); productionPca2011 = ($txt -match 'Windows Production PCA 2011') }
            } catch { $keys[$n] = 'unavailable' }
        }
        try { $keys['setupMode'] = ((Get-SecureBootUEFI -Name SetupMode -ErrorAction Stop).Bytes[0] -eq 1) } catch { }
        if ($R.security.secureBoot -eq 'off' -and $keys['dbDefault'] -is [System.Collections.IDictionary]) {
            if ($keys['dbDefault'].windowsUefiCa2023) { Add-Flag 'security' 'info' 'This BIOS''s default Secure Boot keys include Microsoft''s 2023 certificate, so restoring default keys while switching Secure Boot back on is safe here.' }
            else { Add-Flag 'security' 'check' 'This BIOS''s default Secure Boot keys do NOT include Microsoft''s 2023 certificate. Do not tell the user to "install/restore default keys" before a BIOS update: on a PC already moved to the 2023 boot manager that can stop Windows starting.' }
        }
        [ordered]@{ hypervisorLaunchType = $h; optionalFeatures = $feats; lastRestorePoint = $rp; secureBootKeys = $keys }
    }
} else {
    $R['adminExtras'] = [ordered]@{ skipped = 'Run with -Elevate (one admin prompt) to add Secure Boot, TPM, BitLocker, drive wear and Windows feature checks.' }
}

# ---------------------------------------------------------------------------------------
# Write results
# ---------------------------------------------------------------------------------------
$order = @{ fix = 0; check = 1; info = 2; good = 3 }
$sortedFlags = @($Flags | Sort-Object { $order[$_.level] }, { $_.area })
$R['flags'] = $sortedFlags
$R.meta['finished'] = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$R.meta['seconds'] = [int]((Get-Date) - $started).TotalSeconds

$jsonPath = Join-Path $OutDir 'diagnostic.json'
$R | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$sb = New-Object System.Text.StringBuilder
function Add-Line([string]$s) { [void]$sb.AppendLine($s) }
Add-Line ('GAMING PC HEALTH CHECK - scan summary (' + $R.meta.started + ', admin: ' + $isAdmin + ', ' + $R.meta.seconds + 's)')
Add-Line ''
Add-Line ('PC:      ' + $R.system.manufacturer + ' ' + $R.system.model + ' (' + $R.system.formFactor + '), ' + $R.system.os + ' ' + $R.system.displayVersion + ' build ' + $R.system.build)
Add-Line ('CPU:     ' + $R.cpu.name + ' (' + $R.cpu.cores + ' cores / ' + $R.cpu.threads + ' threads), microcode ' + $R.cpu.microcode)
foreach ($g in $R.gpu.adapters) { Add-Line ('GPU:     ' + $g.name + ', driver ' + $g.driverVersion + ' (' + $g.driverDate + ')') }
if ($R.gpu.nvidia) { $n = $R.gpu.nvidia; Add-Line ('         NVIDIA driver ' + $n.driver + ', ' + $n.tempC + ' C, ' + $n.powerW + ' W, PCIe gen ' + $n.pcieGenNow + '/' + $n.pcieGenMax + ' x' + $n.pcieWidthNow + '/' + $n.pcieWidthMax + ', Resizable BAR ' + $n.resizableBar) }
Add-Line ('Board:   ' + $R.motherboard.manufacturer + ' ' + $R.motherboard.product + ', BIOS ' + $R.motherboard.biosVersion + ' (' + $R.motherboard.biosDate + ')')
Add-Line ('Memory:  ' + $R.system.installedRamGB + ' GB, ' + $R.memory.sticksFitted + ' of ' + $R.memory.totalSlots + ' slots, running ' + ($R.memory.runningSpeeds -join '/') + ' MT/s: ' + $R.memory.verdict)
foreach ($m in $R.memory.modules) { Add-Line ('         ' + ((@($m.bank, $m.slot) | Where-Object { $_ }) -join ' / ') + ': ' + $m.sizeGB + ' GB ' + $m.type + ' ' + $m.maker + ' ' + $m.partNumber + ' (rated guess ' + $m.ratedSpeedGuessFromPartNumber + ')') }
foreach ($v in $R.storage.volumes) { Add-Line ('Drive:   ' + $v.drive + ' ' + $v.label + ' ' + $v.sizeGB + ' GB, ' + $v.freeGB + ' GB free (' + $v.freePercent + '%), ' + $v.media) }
foreach ($d in $R.displays) { Add-Line ('Display: ' + $d.monitor + ' on ' + $d.adapter + ': ' + $d.current + ' (native ' + $d.native + ', best ' + $d.bestHzAtNative + ' Hz)' + $(if ($d.primary) { ' [primary]' } else { '' })) }
Add-Line ''
Add-Line 'FINDINGS (fix = worth fixing, check = needs a look or a decision, info, good = already right)'
foreach ($f in $sortedFlags) { Add-Line ('  [' + $f.level.ToUpper() + '] ' + $f.area + ': ' + $f.text) }
Add-Line ''
$errs = @($R.Keys | Where-Object { $R[$_] -is [System.Collections.IDictionary] -and $R[$_].Contains('error') })
if ($errs.Count -gt 0) { Add-Line ('Sections that could not be read: ' + ($errs -join ', ') + ' (see diagnostic.json).') }
Add-Line ('Full detail: ' + $jsonPath)
$sb.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'diagnostic-summary.txt') -Encoding UTF8

Write-Host ''
Write-Host $sb.ToString()
