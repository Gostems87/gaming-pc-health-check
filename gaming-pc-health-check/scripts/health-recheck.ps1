<#
.SYNOPSIS
    Gaming PC Health Check: after-care check. Read-only.

.DESCRIPTION
    Run after a change (a BIOS update, XMP/EXPO, new drivers) and a day or two of normal
    gaming. Looks for hardware errors (WHEA), blue screens, sudden power-offs, graphics
    driver resets and app crashes since a given time, and gives a plain verdict.

.PARAMETER Since
    Start of the window as "yyyy-MM-dd HH:mm" (or "yyyy-MM-dd"), e.g. "2026-11-03 18:00".
    This fixed format avoids day/month mix-ups between British and US settings.
    Default: 7 days ago.

.PARAMETER OutDir
    Optional folder to save the result as recheck-YYYYMMDD-HHMM.txt.

.EXAMPLE
    .\health-recheck.ps1 -Since "2026-11-03 18:00" -OutDir .\pc-health-check-2026-11-03
#>
[CmdletBinding()]
param(
    [string]$Since,
    [string]$OutDir
)

$ErrorActionPreference = 'Continue'
if ($Since) {
    $parsed = [datetime]::MinValue
    $formats = [string[]]@('yyyy-MM-dd HH:mm', 'yyyy-MM-dd H:mm', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd')
    if (-not [datetime]::TryParseExact($Since.Trim(), $formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        Write-Host ('Could not read -Since "' + $Since + '". Use the form yyyy-MM-dd HH:mm, for example 2026-11-03 18:00.')
        exit 2
    }
    if ($parsed -gt (Get-Date)) { Write-Host '-Since is in the future. Use the time the change was made.'; exit 2 }
    $sinceDate = $parsed
} else {
    $sinceDate = (Get-Date).AddDays(-7)
}
# $Since is typed as text by the parameter; swap it for an untyped date variable.
Remove-Variable -Name Since -Force
$Since = $sinceDate
function Get-Events($filter) { try { return @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) } catch { return @() } }

$whea = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $Since })
$bsod = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $Since })
$kp41 = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $Since })
$tdr = @(Get-Events @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $Since })
$app = @(Get-Events @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $Since })
$boots = @(Get-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12; StartTime = $Since })
$problemDevices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -notin 0, 22, 45 })
$mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | ForEach-Object { $_.ConfiguredClockSpeed } | Sort-Object -Unique)
$sb = $null
try { $sb = (Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop).GetValue('UEFISecureBootEnabled') } catch { }

$lines = New-Object System.Collections.ArrayList
function Add-Line([string]$s) { [void]$lines.Add($s) }
$hours = [math]::Round(((Get-Date) - $Since).TotalHours)
Add-Line ('HEALTH RE-CHECK since ' + $Since.ToString('yyyy-MM-dd HH:mm') + ' (' + $hours + ' hours, ' + $boots.Count + ' start-ups)')
Add-Line ('Memory speed now: ' + ($mem -join '/') + ' MT/s.  Secure Boot: ' + $(if ($sb -eq 1) { 'on' } elseif ($sb -eq 0) { 'OFF' } else { 'unknown' }) + '.  Devices with driver problems: ' + $problemDevices.Count)
Add-Line ''
Add-Line ('Hardware errors (WHEA):     ' + $whea.Count + $(if ($whea.Count) { '  IDs: ' + (($whea | Group-Object Id | ForEach-Object { $_.Name + ' x' + $_.Count }) -join ', ') } else { '' }))
Add-Line ('Blue screens:               ' + $bsod.Count)
Add-Line ('Sudden power-offs:          ' + $kp41.Count + $(if ($kp41.Count) { '  (noticed at start-up: ' + (($kp41 | ForEach-Object { $_.TimeCreated.ToString('MM-dd HH:mm') }) -join ', ') + ')' } else { '' }))
Add-Line ('Graphics driver resets:     ' + $tdr.Count)
$topApps = @($app | ForEach-Object { try { [string]$_.Properties[0].Value } catch { 'unknown' } } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5)
Add-Line ('App crashes:                ' + $app.Count + $(if ($topApps.Count) { '  top: ' + (($topApps | ForEach-Object { $_.Name + ' x' + $_.Count }) -join ', ') } else { '' }))
Add-Line ''

$memWhea = @($whea | Where-Object { $_.Id -in 19, 47, 18, 1 })
if ($memWhea.Count -gt 0 -or $bsod.Count -gt 0) {
    Add-Line 'VERDICT: NOT CLEAN. Hardware errors or blue screens since the change. If XMP/EXPO or a memory speed was changed, step the memory down one notch (or back to Auto) in the BIOS and re-check. Do not try anything faster.'
} elseif ($kp41.Count -gt 0 -or $tdr.Count -gt 0) {
    Add-Line 'VERDICT: LOOK CLOSER. No hardware errors, but there were sudden power-offs or graphics driver resets. Ask the user what happened at those times (a held power button logs the same as a crash).'
} elseif ($hours -lt 12 -or $boots.Count -lt 1) {
    Add-Line 'VERDICT: CLEAN SO FAR, but the window is short. Re-check after a full day of normal gaming.'
} else {
    Add-Line 'VERDICT: CLEAN. No hardware errors, blue screens, power-offs or driver resets.'
}
if ($sb -eq 0) { Add-Line 'NOTE: Secure Boot is off. If it was on before a BIOS change, loading BIOS defaults probably turned it off. Anti-cheat games may refuse to start.' }

$text = $lines -join [Environment]::NewLine
Write-Host $text
if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $p = Join-Path $OutDir ('recheck-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.txt')
    $text | Set-Content -LiteralPath $p -Encoding UTF8
    Write-Host ('Saved: ' + $p)
}
