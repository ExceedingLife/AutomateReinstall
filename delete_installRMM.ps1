#!ps
#timeout=900000
#maxlength=9000000

## Created by Andrew Harkins
# Works in Screen Connect or normal Administrative PowerShell session. 

param(
    [string]$Server,
    [int]$LocationID,
    [string]$Token
)

Write-Host "=== Starting Automate RMM Reinstall ===" -ForegroundColor Cyan

# ============================================================
# STEP 1 - Stop Services
# ============================================================
Write-Host "`n[1/5] Stopping Automate services..." -ForegroundColor Yellow

$services = @("LTService", "LTSvcMon")

foreach ($svc in $services) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Write-Host "  Stopping $svc..."
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Host "  $svc not found, skipping..."
    }
}

# ============================================================
# STEP 2 - Uninstall via MSI/Add-Remove Programs
# ============================================================
Write-Host "`n[2/5] Uninstalling via registry/MSI..." -ForegroundColor Yellow

$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$found = $false
foreach ($key in $uninstallKeys) {
    Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
        $app = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
        if ($app.DisplayName -like "*Automate*" -or $app.DisplayName -like "*LabTech*" -or $app.DisplayName -like "*ConnectWise Automate*") {
            Write-Host "  Found: $($app.DisplayName)"
            $found = $true
            
            if ($app.UninstallString) {
                Write-Host "  Uninstalling via: $($app.UninstallString)"
                
                if ($app.UninstallString -like "*msiexec*") {
                    # MSI uninstall
                    $guid = ($app.UninstallString -replace '.*({.*}).*', '$1')
                    Write-Host "  Running msiexec /x $guid"
                    Start-Process "msiexec.exe" -ArgumentList "/x `"$guid`" /qn /norestart" -Wait -ErrorAction SilentlyContinue
                } else {
                    # EXE uninstall
                    Start-Process cmd.exe -ArgumentList "/c $($app.UninstallString) /S" -Wait -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

if (-not $found) {
    Write-Host "  No MSI entry found, continuing with manual cleanup..."
}

# ============================================================
# STEP 3 - Delete Services
# ============================================================
Write-Host "`n[3/5] Removing services..." -ForegroundColor Yellow

foreach ($svc in $services) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Write-Host "  Deleting service: $svc"
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe delete $svc | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "  $svc deleted"
    } else {
        Write-Host "  $svc already gone"
    }
}

# ============================================================
# STEP 4 - Clean Up Files and Registry
# ============================================================
Write-Host "`n[4/5] Cleaning up files and registry..." -ForegroundColor Yellow

# File paths to remove
$paths = @(
    "C:\Windows\LTSvc",
    "C:\Windows\System32\LTSvc",
    "C:\Program Files\LabTech",
    "C:\Program Files (x86)\LabTech",
    "C:\Program Files\ConnectWise Automate",
    "C:\Program Files (x86)\ConnectWise Automate"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Write-Host "  Removing: $path"
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Registry keys to remove
$regKeys = @(
    "HKLM:\SOFTWARE\LabTech",
    "HKLM:\SOFTWARE\WOW6432Node\LabTech",
    "HKLM:\SYSTEM\CurrentControlSet\Services\LTService",
    "HKLM:\SYSTEM\CurrentControlSet\Services\LTSvcMon"
)

foreach ($reg in $regKeys) {
    if (Test-Path $reg) {
        Write-Host "  Removing registry: $reg"
        Remove-Item -Path $reg -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# STEP 5 - Reinstall
# ============================================================
Write-Host "`n[5/5] Installing fresh Automate agent..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Invoke-Expression(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Braingears/PowerShell/master/Automate-Module.psm1')
Install-Automate -Server $Server -LocationID $LocationID -Token $Token -Transcript -Show -Force
Write-Host "`n=== Automate Reinstall Complete ===" -ForegroundColor Cyan