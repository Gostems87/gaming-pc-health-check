<#
.SYNOPSIS
    Gaming PC Health Check: apply the safe, reversible Windows fixes the user approved.

.DESCRIPTION
    PREVIEW BY DEFAULT. Without -Apply it only shows what it would change.

    Each switch is one fix. Before a setting is changed, its old value is written to an
    undo file, and "apply-safe.ps1 -Undo <file> -Apply" puts every setting back exactly
    as it was. The undo step only ever touches the settings this script itself changes.

    Clean-ups delete only caches and leftovers that rebuild themselves (temp files older
    than 7 days, NVIDIA's downloaded installers, app crash dumps, the Windows component
    store) and, only when asked by name, the Recycle Bin. They cannot be undone.

    It never touches games, documents, pictures, recordings, downloads or the BIOS.

.PARAMETER Apply
    Actually make the changes. Without it, nothing changes (preview only).

.PARAMETER Elevate
    Relaunch as administrator (one UAC prompt). Needed for GPU scheduling, hibernation,
    component clean-up, machine-wide startup entries and the restore point. If the
    prompt is declined while -Apply is set, nothing is changed.

.PARAMETER OutDir
    Folder for the change log and undo file. Default: .\pc-health-check-YYYY-MM-DD

.PARAMETER DisableStartup
    Startup entry names to switch off (as listed by diagnose.ps1). Separate several with
    semicolons. Same effect as Task Manager > Startup apps > Disable; nothing is uninstalled.

.PARAMETER Undo
    Path to an undo-*.json file written by this script. Add -Apply to restore.

.EXAMPLE
    .\apply-safe.ps1 -GameMode -WindowedOptimisations -VariableRefreshRate -GameBarCaptureOff
    (preview)

.EXAMPLE
    .\apply-safe.ps1 -GameMode -GpuScheduling -HibernateOff -CleanTemp -Apply -Elevate

.EXAMPLE
    .\apply-safe.ps1 -Undo .\pc-health-check-2026-11-03\undo-20261103-171500.json -Apply -Elevate
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Elevate,
    [string]$OutDir,
    [switch]$GameMode,
    [switch]$GpuScheduling,
    [switch]$WindowedOptimisations,
    [switch]$VariableRefreshRate,
    [switch]$GameBarCaptureOff,
    [switch]$MouseAccelerationOff,
    [switch]$BalancedPowerPlan,
    [switch]$HibernateOff,
    [switch]$AllowOnLaptop,
    [string[]]$DisableStartup,
    [switch]$CleanTemp,
    [switch]$CleanInstallerLeftovers,
    [switch]$CleanComponentStore,
    [switch]$EmptyRecycleBin,
    [switch]$NoRestorePoint,
    [string]$Undo,
    [string]$LaunchedBy
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if (-not $OutDir) { $OutDir = Join-Path (Get-Location).Path ('pc-health-check-' + (Get-Date -Format 'yyyy-MM-dd')) }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
if ($OutDir.Length -gt 3) { $OutDir = $OutDir.TrimEnd('\') }
if ($Undo) { $Undo = [System.IO.Path]::GetFullPath($Undo) }
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$mySid = $me.User.Value

# -File passes "a;b" as one string, so accept either an array or a separated string.
$DisableStartup = @($DisableStartup | ForEach-Object { $_ -split ';' } | Where-Object { $_ -and $_.Trim() })

# Quotes in any text value would break the admin relaunch's command line: refuse them.
foreach ($v in @($OutDir, $Undo) + $DisableStartup) {
    if ($v -and $v.Contains('"')) { Write-Host 'Refusing to run: a folder, file or startup name contains a double quote.'; exit 2 }
}
foreach ($v in $DisableStartup) {
    if ($v.TrimEnd().EndsWith('\')) { Write-Host ('Refusing to run: the startup name "' + $v + '" ends with a backslash. Switch that one off in Task Manager > Startup apps instead.'); exit 2 }
}

# Elevated by a different account (for example a parent typing admin credentials)?
# Then HKCU and %TEMP% belong to that other account, so per-user items must be skipped.
$UserMismatch = [bool]($LaunchedBy -and $LaunchedBy -ne $mySid)

# ---------------------------------------------------------------------------------------
# Optional self-elevation: relaunch with the same switches, then show the log it wrote.
# ---------------------------------------------------------------------------------------
if ($Elevate -and -not $isAdmin) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $outArg = $OutDir
    if ($outArg.EndsWith('\')) { $outArg += '.' }
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-OutDir', ('"' + $outArg + '"'), '-LaunchedBy', $mySid)
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if (@('Elevate', 'OutDir', 'LaunchedBy') -contains $kv.Key) { continue }
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value.IsPresent) { $parts += ('-' + $kv.Key) } }
        elseif ($kv.Key -eq 'DisableStartup') { $parts += '-DisableStartup'; $parts += ('"' + ($DisableStartup -join ';') + '"') }
        elseif ($kv.Key -eq 'Undo') { $parts += '-Undo'; $parts += ('"' + $Undo + '"') }
    }
    $launched = Get-Date
    $declined = $false
    try {
        Write-Host 'Asking Windows for admin rights. Click Yes on the prompt.'
        Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -WindowStyle Minimized | Out-Null
    } catch { $declined = $true }
    if (-not $declined) {
        $log = Get-ChildItem -LiteralPath $OutDir -Filter 'apply-*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $launched } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($log) { Get-Content -LiteralPath $log.FullName; exit 0 }
        Write-Warning 'The admin run did not write a log. Nothing may have changed; check the folder.'
        exit 1
    }
    if ($Apply) {
        Write-Host 'The admin prompt was declined, so NOTHING has been changed. Run again without -Elevate to apply only the items that do not need admin rights.'
        exit 3
    }
    Write-Warning 'The admin prompt was declined. Showing the preview without admin rights.'
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mode = $(if ($Undo) { $(if ($Apply) { 'undo' } else { 'undo-preview' }) } elseif ($Apply) { 'changes' } else { 'preview' })
$LogPath = Join-Path $OutDir ('apply-' + $mode + '-' + $stamp + '.log')
$UndoPath = Join-Path $OutDir ('undo-' + $stamp + '.json')
$UndoData = [ordered]@{ tool = 'gaming-pc-health-check'; created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); changes = (New-Object System.Collections.ArrayList) }
$NeedsAdmin = New-Object System.Collections.ArrayList

# The only registry values this script may write, and therefore the only ones Undo may restore.
$StartupApprovedKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
)
$AllowedValues = @{
    'HKCU:\Software\Microsoft\GameBar' = @('AutoGameModeEnabled', 'AllowAutoGameMode')
    'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' = @('HwSchMode')
    'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' = @('DirectXUserGlobalSettings')
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' = @('AppCaptureEnabled')
    'HKCU:\System\GameConfigStore' = @('GameDVR_Enabled')
    'HKCU:\Control Panel\Mouse' = @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2')
}
function Test-AllowedValue([string]$Path, [string]$Name, [string]$Kind) {
    if ($StartupApprovedKeys -contains $Path) { return ($Kind -eq 'Binary' -or -not $Kind) }
    if ($AllowedValues.ContainsKey($Path)) { return ($AllowedValues[$Path] -contains $Name) }
    return $false
}

function Write-Log([string]$Text) {
    Write-Host $Text
    Add-Content -LiteralPath $LogPath -Value $Text -Encoding UTF8
}

function Save-Undo { $UndoData | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $UndoPath -Encoding UTF8 }

function Get-RegValue([string]$Path, [string]$Name) {
    try { $k = Get-Item -LiteralPath $Path -ErrorAction Stop; $v = $k.GetValue($Name, $null) } catch { return $null }
    if ($v -is [array]) { return , $v }
    return $v
}

function Format-RegValue($Exists, $Value) {
    if (-not $Exists) { return '(not set)' }
    if ($Value -is [byte[]]) { return ('bytes ' + (($Value | Select-Object -First 4 | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') + '...') }
    if ($Value -is [array]) { return ($Value -join ',') }
    return ('"' + [string]$Value + '"')
}

function Test-SameValue($a, $b) {
    if ($a -is [byte[]] -and $b -is [byte[]]) { return ([Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b)) }
    return ([string]$a -eq [string]$b)
}

# Change one registry value, recording the old one first. Creates the key only when it is
# missing (New-Item -Force on an EXISTING registry key deletes everything inside it).
function Set-RegTracked {
    param([string]$Path, [string]$Name, $Value, [string]$Kind, [string]$Label)
    if (-not (Test-AllowedValue $Path $Name $Kind)) { Write-Log ('  REFUSED (not on the allowed list) ' + $Label); return }
    if ($Path -like 'HKCU:*' -and $UserMismatch) { Write-Log ('  SKIPPED (admin rights came from a different account; run this item without -Elevate) ' + $Label); return }
    $needsAdmin = ($Path -like 'HKLM:*' -and -not $isAdmin)
    $keyExisted = Test-Path -LiteralPath $Path
    $existed = $false; $old = $null; $oldKind = $null
    if ($keyExisted) {
        $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($key -and ($key.GetValueNames() -contains $Name)) {
            $existed = $true
            $old = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $oldKind = [string]$key.GetValueKind($Name)
        }
    }
    if ($existed -and (Test-SameValue $old $Value)) { Write-Log ('  already right: ' + $Label); return }
    $from = Format-RegValue $existed $old
    $to = Format-RegValue $true $Value
    if (-not $Apply) {
        $note = ''
        if ($needsAdmin) { $note = '  (needs admin: add -Elevate)'; [void]$NeedsAdmin.Add($Label) }
        Write-Log ('  PREVIEW ' + $Label + ': ' + $from + ' -> ' + $to + $note)
        return
    }
    if ($needsAdmin) { [void]$NeedsAdmin.Add($Label); Write-Log ('  SKIPPED (needs admin) ' + $Label); return }
    $rec = [ordered]@{ kind = 'reg'; label = $Label; path = $Path; name = $Name; existed = $existed; valueKind = $oldKind; keyCreated = (-not $keyExisted) }
    if ($existed) { if ($old -is [byte[]]) { $rec['base64'] = [Convert]::ToBase64String($old) } else { $rec['value'] = $old } }
    [void]$UndoData.changes.Add($rec)
    Save-Undo
    if (-not $keyExisted) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
    Write-Log ('  CHANGED ' + $Label + ': ' + $from + ' -> ' + $to)
}

# A folder is only cleaned if it really is a temp-style folder: never a drive root, the
# user profile, Windows itself, or a link to somewhere else.
function Test-SafeCleanTarget([string]$Path, [string[]]$Leaves) {
    if (-not $Path) { return $false }
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $false }
    if ($full.Length -le 3) { return $false }
    $leaf = Split-Path $full -Leaf
    $parentLeaf = Split-Path (Split-Path $full -Parent) -Leaf
    $ok = ($Leaves -contains $leaf) -or ($Leaves -contains 'Temp' -and $parentLeaf -eq 'Temp' -and $leaf -match '^\d+$')
    if (-not $ok) { return $false }
    $protected = @($env:USERPROFILE, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA,
        [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    if ($protected -contains $full) { return $false }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.PSIsContainer) { return $false }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    return $true
}

# Walk a folder by hand, never following links (junctions or symbolic links) at any level.
function Get-FolderEntries([string]$Root, [string[]]$SkipTop = @()) {
    $files = New-Object System.Collections.ArrayList
    $dirs = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($Root, $true))
    while ($stack.Count -gt 0) {
        $pair = $stack.Pop(); $dir = $pair[0]; $isTop = $pair[1]
        foreach ($e in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($isTop -and ($SkipTop -contains $e.Name)) { continue }
            if (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($e.PSIsContainer) { [void]$dirs.Add([pscustomobject]@{ path = $e.FullName; written = $e.LastWriteTime }); $stack.Push(@($e.FullName, $false)) }
            else { [void]$files.Add($e) }
        }
    }
    return [pscustomobject]@{ files = $files; dirs = $dirs }
}

# True only if the item and every folder between it and Root is a real folder (no links),
# and the item really sits inside Root.
function Test-ChainClean([string]$Root, [string]$ItemPath) {
    try {
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        $full = [IO.Path]::GetFullPath($ItemPath)
    } catch { return $false }
    if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
    $dir = Split-Path $full -Parent
    while ($dir) {
        $d = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
        if (-not $d -or (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        if ($dir.TrimEnd('\') -ieq $rootFull) { return $true }
        $dir = Split-Path $dir -Parent
    }
    return $false
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label, [string[]]$Leaves, [int]$MinAgeDays = 7, [string[]]$Skip = @())
    if (-not (Test-Path -LiteralPath $Path)) { Write-Log ('  ' + $Label + ': not present'); return }
    if (-not (Test-SafeCleanTarget $Path $Leaves)) { Write-Log ('  REFUSED ' + $Label + ': ' + $Path + ' does not look like a temp or cache folder, so it was left alone.'); return }
    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $entries = Get-FolderEntries $Path $Skip
    $old = @($entries.files | Where-Object { $_.LastWriteTime -lt $cutoff })
    $oldGB = [math]::Round((($old | Measure-Object Length -Sum).Sum) / 1GB, 2)
    $ageText = $(if ($MinAgeDays -gt 0) { 'older than ' + $MinAgeDays + ' days' } else { 'of any age' })
    if (-not $Apply) { Write-Log ('  PREVIEW ' + $Label + ': would delete ' + $old.Count + ' file(s) ' + $ageText + ', about ' + $oldGB + ' GB, from ' + $Path); return }
    $freed = [double]0; $removed = 0; $skippedLinks = 0
    foreach ($f in $old) {
        # Re-check just before deleting: if any folder on the way down has been swapped for a
        # link since the listing, skip the file (guards against redirect tricks).
        if (-not (Test-ChainClean $Path $f.FullName)) { $skippedLinks++; continue }
        $len = $f.Length
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $f.FullName)) { $freed += $len; $removed++ }
    }
    foreach ($d in ($entries.dirs | Sort-Object { $_.path.Length } -Descending)) {
        if ($d.written -ge $cutoff) { continue }
        if (-not (Test-ChainClean $Path (Join-Path $d.path 'x'))) { continue }
        if (-not (Get-ChildItem -LiteralPath $d.path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) { Remove-Item -LiteralPath $d.path -Force -ErrorAction SilentlyContinue }
    }
    if ($skippedLinks -gt 0) { Write-Log ('  NOTE: ' + $skippedLinks + ' file(s) skipped because a folder on their path had become a link.') }
    Write-Log ('  CLEARED ' + $Label + ': ' + $removed + ' file(s), ' + [math]::Round($freed / 1GB, 2) + ' GB (files in use were left alone)')
}

function Test-IsLaptop {
    $types = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes | ForEach-Object { [int]$_ })
    if (@($types | Where-Object { @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) -contains $_ }).Count -gt 0) { return $true }
    # Only trust a battery when the chassis type is unknown: a USB UPS also shows up as a battery.
    $unknown = ($types.Count -eq 0) -or (@($types | Where-Object { $_ -gt 2 }).Count -eq 0)
    return ($unknown -and @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0)
}

function Get-ActiveSchemeGuid {
    $line = ((& powercfg /getactivescheme 2>$null) -join ' ')
    if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $matches[1].ToLower() }
    return $null
}

$PendingRestart = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                  (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')

Write-Log ('Gaming PC Health Check: ' + $mode + ' (' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ', admin: ' + $isAdmin + ')')
if (-not $Apply) { Write-Log 'PREVIEW ONLY: nothing below has been changed. Add -Apply to make these changes.' }
if ($UserMismatch) { Write-Log 'NOTE: admin rights came from a different Windows account, so per-user settings and the user temp folder are skipped in this run.' }

# ---------------------------------------------------------------------------------------
# Undo mode: restores only values on the allowed list, from a file this script wrote.
# ---------------------------------------------------------------------------------------
if ($Undo) {
    if (-not (Test-Path -LiteralPath $Undo)) { Write-Log ('Undo file not found: ' + $Undo); exit 1 }
    try { $data = Get-Content -LiteralPath $Undo -Raw | ConvertFrom-Json } catch { Write-Log 'The undo file could not be read.'; exit 1 }
    if ($data.tool -ne 'gaming-pc-health-check') { Write-Log 'That file was not written by this tool. Nothing restored.'; exit 1 }
    $changes = @($data.changes)
    [array]::Reverse($changes)
    $validKinds = @('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')
    $planList = ((& powercfg /list 2>$null) -join ' ').ToLower()
    Write-Log ('Restoring ' + $changes.Count + ' change(s) from ' + $Undo)
    foreach ($c in $changes) {
        switch ($c.kind) {
            'reg' {
                $kindToCheck = $(if ($c.existed) { [string]$c.valueKind } else { $null })
                if (-not (Test-AllowedValue $c.path $c.name $kindToCheck) -or ($c.existed -and $validKinds -notcontains $c.valueKind)) { Write-Log ('  REFUSED (not a setting this tool changes) ' + $c.path + ' ' + $c.name); continue }
                if ($c.path -like 'HKCU:*' -and $UserMismatch) { Write-Log ('  SKIPPED (different account; run without -Elevate) ' + $c.label); continue }
                if ($c.path -like 'HKLM:*' -and -not $isAdmin) { [void]$NeedsAdmin.Add($c.label); Write-Log ('  SKIPPED (needs admin) ' + $c.label); continue }
                if (-not $Apply) { Write-Log ('  PREVIEW restore ' + $c.label + $(if ($c.existed) { ' to its old value' } else { ' by removing the value (it did not exist before)' })); continue }
                if ($c.existed) {
                    $val = $c.value
                    if ($c.base64) { $val = [Convert]::FromBase64String($c.base64) }
                    switch ($c.valueKind) { 'DWord' { $val = [int]$val } 'QWord' { $val = [long]$val } 'MultiString' { $val = [string[]]$val } default { } }
                    if (-not (Test-Path -LiteralPath $c.path)) { New-Item -Path $c.path -Force | Out-Null }
                    New-ItemProperty -LiteralPath $c.path -Name $c.name -Value $val -PropertyType $c.valueKind -Force | Out-Null
                } else {
                    Remove-ItemProperty -LiteralPath $c.path -Name $c.name -ErrorAction SilentlyContinue
                    if ($c.keyCreated) {
                        $k = Get-Item -LiteralPath $c.path -ErrorAction SilentlyContinue
                        if ($k -and $k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item -LiteralPath $c.path -ErrorAction SilentlyContinue }
                    }
                }
                Write-Log ('  RESTORED ' + $c.label)
            }
            'hibernate' {
                if (-not $c.wasEnabled) { Write-Log '  nothing to restore for hibernation (it was already off)'; continue }
                if (-not $isAdmin) { [void]$NeedsAdmin.Add('Hibernation'); Write-Log '  SKIPPED (needs admin) hibernation'; continue }
                if (-not $Apply) { Write-Log '  PREVIEW turn hibernation and Fast Startup back on'; continue }
                & powercfg /hibernate on | Out-Null
                Write-Log '  RESTORED hibernation (and Fast Startup) on'
            }
            'powerplan' {
                $g = ([string]$c.previousGuid).ToLower()
                if ($g -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or -not $planList.Contains($g)) { Write-Log '  REFUSED power plan restore (not a valid plan on this PC)'; continue }
                if (-not $Apply) { Write-Log ('  PREVIEW switch power plan back to ' + $c.previousName); continue }
                & powercfg /setactive $g | Out-Null
                Write-Log ('  RESTORED power plan: ' + $c.previousName)
            }
            default { Write-Log ('  REFUSED unknown entry type: ' + $c.kind) }
        }
    }
    if ($NeedsAdmin.Count -gt 0) { Write-Log 'Some items need admin rights: run again with -Elevate.' }
    Write-Log 'Restart the PC to make sure every restored setting is live.'
    exit 0
}

# ---------------------------------------------------------------------------------------
# Restore point (best effort; the undo file is the main safety net for settings)
# ---------------------------------------------------------------------------------------
$settingsRequested = $GameMode -or $GpuScheduling -or $WindowedOptimisations -or $VariableRefreshRate -or $GameBarCaptureOff -or $MouseAccelerationOff -or $BalancedPowerPlan -or $HibernateOff -or ($DisableStartup.Count -gt 0)
if ($settingsRequested -and -not $NoRestorePoint) {
    if (-not $isAdmin) { Write-Log 'Restore point: skipped (needs admin). The undo file still records every setting changed.' }
    elseif (-not $Apply) { Write-Log 'PREVIEW create a System Restore point first.' }
    else {
        $warn = $null
        try {
            Checkpoint-Computer -Description 'Before Gaming PC Health Check' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningVariable warn -WarningAction SilentlyContinue
            if ($warn) { Write-Log ('Restore point: not created (' + (($warn | ForEach-Object { $_.Message }) -join ' ') + '). The undo file still records every setting.') }
            else { Write-Log 'Restore point: created.' }
        } catch { Write-Log ('Restore point: not created (' + $_.Exception.Message + '). System Protection may be off for this drive. The undo file still records every setting.') }
    }
}

# ---------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------
if ($GameMode) {
    Write-Log 'Game Mode on'
    Set-RegTracked 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 'DWord' 'Game Mode'
    Set-RegTracked 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 'DWord' 'Game Mode (allow)'
}

if ($GpuScheduling) {
    Write-Log 'Hardware-accelerated GPU scheduling on (live after a restart)'
    Set-RegTracked 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord' 'GPU scheduling'
}

if ($WindowedOptimisations -or $VariableRefreshRate) {
    Write-Log 'Windowed-game optimisations / variable refresh rate'
    $path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $cur = Get-RegValue $path 'DirectXUserGlobalSettings'
    if (-not $cur) { $cur = '' }
    $tokens = [ordered]@{}
    foreach ($t in ($cur -split ';')) { if ($t -match '^(\w+)=(.*)$') { $tokens[$matches[1]] = $matches[2] } }
    if ($WindowedOptimisations) { $tokens['SwapEffectUpgradeEnable'] = '1' }
    if ($VariableRefreshRate) { $tokens['VRROptimizeEnable'] = '1' }
    $new = (($tokens.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value }) -join ';') + ';'
    Set-RegTracked $path 'DirectXUserGlobalSettings' $new 'String' 'Windowed optimisations / VRR'
}

if ($GameBarCaptureOff) {
    Write-Log 'Xbox Game Bar background capture off (Game Bar itself stays installed)'
    Set-RegTracked 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord' 'Game Bar capture'
    Set-RegTracked 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord' 'Game DVR'
}

if ($MouseAccelerationOff) {
    Write-Log 'Mouse acceleration ("Enhance pointer precision") off (live after signing out and in)'
    Set-RegTracked 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String' 'Mouse acceleration'
    Set-RegTracked 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String' 'Mouse threshold 1'
    Set-RegTracked 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String' 'Mouse threshold 2'
}

if ($BalancedPowerPlan) {
    Write-Log 'Power plan: Balanced'
    $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $prev = Get-ActiveSchemeGuid
    $prevName = ((& powercfg /getactivescheme 2>$null) -join ' ') -replace '^.*\(([^)]+)\)\s*$', '$1'
    if ($prev -eq $balanced) { Write-Log '  already right: Balanced' }
    elseif (-not $Apply) { Write-Log ('  PREVIEW power plan: ' + $prevName + ' -> Balanced') }
    else {
        [void]$UndoData.changes.Add([ordered]@{ kind = 'powerplan'; label = 'Power plan'; previousGuid = $prev; previousName = $prevName })
        Save-Undo
        & powercfg /setactive $balanced | Out-Null
        if ((Get-ActiveSchemeGuid) -eq $balanced) { Write-Log ('  CHANGED power plan: ' + $prevName + ' -> Balanced') } else { Write-Log '  FAILED to switch power plan (Balanced may be hidden on this PC).' }
    }
}

if ($HibernateOff) {
    Write-Log 'Hibernation and Fast Startup off (frees hiberfil.sys)'
    $was = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
    $hf = $env:SystemDrive + '\hiberfil.sys'
    if ((Test-IsLaptop) -and -not $AllowOnLaptop) { Write-Log '  SKIPPED: this looks like a laptop, where hibernation protects work when the battery runs out. Add -AllowOnLaptop only if the user insists.' }
    elseif ($was -eq 0 -and -not (Test-Path -LiteralPath $hf)) { Write-Log '  already right: hibernation off' }
    elseif (-not $Apply) { Write-Log ('  PREVIEW powercfg /hibernate off' + $(if (-not $isAdmin) { '  (needs admin: add -Elevate)' } else { '' })); if (-not $isAdmin) { [void]$NeedsAdmin.Add('Hibernation') } }
    elseif (-not $isAdmin) { [void]$NeedsAdmin.Add('Hibernation'); Write-Log '  SKIPPED (needs admin) hibernation' }
    else {
        [void]$UndoData.changes.Add([ordered]@{ kind = 'hibernate'; label = 'Hibernation'; wasEnabled = ($was -ne 0) })
        Save-Undo
        & powercfg /hibernate off | Out-Null
        Start-Sleep -Seconds 2
        Write-Log ('  CHANGED hibernation off; hiberfil.sys present now: ' + (Test-Path -LiteralPath $hf))
    }
}

if ($DisableStartup.Count -gt 0) {
    Write-Log 'Startup apps off (same as Task Manager > Startup apps > Disable; nothing uninstalled)'
    $sources = @(
        @{ list = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; approved = $StartupApprovedKeys[0]; folder = $false },
        @{ list = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; approved = $StartupApprovedKeys[1]; folder = $false },
        @{ list = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; approved = $StartupApprovedKeys[2]; folder = $false },
        @{ list = [Environment]::GetFolderPath('Startup'); approved = $StartupApprovedKeys[3]; folder = $true },
        @{ list = [Environment]::GetFolderPath('CommonStartup'); approved = $StartupApprovedKeys[4]; folder = $true }
    )
    foreach ($want in $DisableStartup) {
        $wantT = $want.Trim()
        $hits = 0
        foreach ($s in $sources) {
            $names = @()
            if ($s.folder) { if ($s.list -and (Test-Path -LiteralPath $s.list)) { $names = @(Get-ChildItem -LiteralPath $s.list -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } }
            else { $k = Get-Item -LiteralPath $s.list -ErrorAction SilentlyContinue; if ($k) { $names = @($k.GetValueNames()) } }
            foreach ($n in $names) {
                if ($n.Trim() -ne $wantT) { continue }
                $hits++
                $cur = Get-RegValue $s.approved $n
                if ($cur -is [byte[]] -and $cur.Length -gt 0 -and ($cur[0] -band 1) -eq 1) { Write-Log ('  already right: ' + $n + ' is off'); continue }
                $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()))
                Set-RegTracked $s.approved $n $bytes 'Binary' ('Startup: ' + $n)
            }
        }
        if ($hits -eq 0) { Write-Log ('  NOT FOUND: no startup entry named "' + $wantT + '" (names are listed in diagnostic.json > startup)') }
    }
}

# ---------------------------------------------------------------------------------------
# Clean-ups (cannot be undone; caches and leftovers only)
# ---------------------------------------------------------------------------------------
if ($CleanTemp) {
    Write-Log 'Temporary files older than 7 days (files in use are skipped)'
    if ($PendingRestart) { Write-Log '  SKIPPED: Windows has a restart pending, and installers often finish from temp files after it. Restart first, then run this again.' }
    else {
        # Claude Code keeps its own working files in %TEMP%\claude: never touch them.
        if ($UserMismatch) { Write-Log '  SKIPPED your temp folder (admin rights came from a different account)' }
        else { Clear-FolderContents -Path $env:TEMP -Label 'Your temp folder' -Leaves @('Temp') -MinAgeDays 7 -Skip @('claude') }
        # The machine-wide C:\Windows\Temp is deliberately left to Windows' own tool
        # (Settings > System > Storage > Temporary files), which cleans it safely as admin.
        Write-Log '  Windows'' own temp folder: use Settings > System > Storage > Temporary files.'
    }
}

if ($CleanInstallerLeftovers) {
    Write-Log 'Installer leftovers and crash dumps'
    Clear-FolderContents -Path ($env:ProgramData + '\NVIDIA Corporation\Downloader') -Label 'NVIDIA downloaded installers' -Leaves @('Downloader') -MinAgeDays 7
    if ($UserMismatch) { Write-Log '  SKIPPED app crash dumps (admin rights came from a different account)' }
    else { Clear-FolderContents -Path ($env:LOCALAPPDATA + '\CrashDumps') -Label 'App crash dumps' -Leaves @('CrashDumps') -MinAgeDays 0 }
}

if ($CleanComponentStore) {
    Write-Log 'Windows component store clean-up (DISM StartComponentCleanup; can take several minutes)'
    if (-not $isAdmin) { [void]$NeedsAdmin.Add('Component store clean-up'); Write-Log '  SKIPPED (needs admin)' }
    elseif (-not $Apply) { Write-Log '  PREVIEW DISM /Online /Cleanup-Image /StartComponentCleanup' }
    else {
        $before = (Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1)).SizeRemaining
        & DISM /Online /Cleanup-Image /StartComponentCleanup | Out-Null
        $code = $LASTEXITCODE
        $after = (Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1)).SizeRemaining
        $state = $(if ($code -eq 0) { 'DONE' } elseif ($code -eq 3010) { 'DONE (restart needed)' } else { 'FINISHED WITH ERROR CODE ' + $code })
        Write-Log ('  ' + $state + ': ' + [math]::Round(($after - $before) / 1GB, 2) + ' GB freed on ' + $env:SystemDrive)
    }
}

if ($EmptyRecycleBin) {
    Write-Log 'Recycle Bin (files the user already deleted)'
    if ($UserMismatch) { Write-Log '  SKIPPED (admin rights came from a different account)' }
    elseif (-not $Apply) { Write-Log '  PREVIEW empty the Recycle Bin on every drive' }
    else {
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log '  EMPTIED Recycle Bin' } catch { Write-Log ('  Recycle Bin: ' + $_.Exception.Message) }
    }
}

# ---------------------------------------------------------------------------------------
# Wrap up
# ---------------------------------------------------------------------------------------
if ($Apply -and $UndoData.changes.Count -gt 0) {
    Write-Log ''
    Write-Log ('Undo file: ' + $UndoPath)
    Write-Log ('To put every setting back: apply-safe.ps1 -Undo "' + $UndoPath + '" -Apply -Elevate')
}
if ($NeedsAdmin.Count -gt 0) { Write-Log ('Needs admin: ' + (($NeedsAdmin | Sort-Object -Unique) -join ', ') + '. Run again with -Elevate.') }
if ($Apply -and ($GpuScheduling -or $HibernateOff)) { Write-Log 'Restart the PC to make GPU scheduling / hibernation changes live.' }
Write-Log ('Log: ' + $LogPath)
