#!ps
#timeout=900000
#maxlength=9000000

## Created by Andrew Harkins
# Works in Screen Connect or normal Administrative PowerShell session. 
## Completely remove known ConnectWise Automate/LabTech remnants
## and install a fresh Automate agent.

param(
[Parameter(Mandatory = $true)]
[string]$Server,

[Parameter(Mandatory = $true)]
[int]$LocationID,

[Parameter(Mandatory = $true)]
[string]$Token

)

$ErrorActionPreference = "Continue"

Write-Host "=== Starting Automate RMM Reinstall ===" -ForegroundColor Cyan

# ============================================================
# FUNCTIONS
# ============================================================

function Write-Step {
param(
[string]$Message
)

    Write-Host "`n$Message" -ForegroundColor Yellow
}

function Write-Success {
param(
[string]$Message
)

    Write-Host "  $Message" -ForegroundColor Green
}

function Write-WarningMessage {
param(
[string]$Message
)

    Write-Host "  $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
param(
[string]$Message
)

    Write-Host "  $Message" -ForegroundColor Red
}

# ============================================================
# START
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        CONNECTWISE AUTOMATE RMM RECOVERY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Server:   $Server"
Write-Host "Location: $LocationID"
Write-Host ""

# ============================================================
# KNOWN AUTOMATE COMPONENTS
# ============================================================

$Services = @(
"LTService",
"LTSvcMon"
)

$Processes = @(
"LTService",
"LTSvcMon",
"LTSvc",
"LTTray"
)

$AutomatePaths = @(
"C:\Windows\LTSvc",
"C:\Windows\System32\LTSvc",
"C:\Program Files\LabTech",
"C:\Program Files (x86)\LabTech",
"C:\Program Files\ConnectWise Automate",
"C:\Program Files (x86)\ConnectWise Automate"
)

$AutomateRegistryKeys = @(
"HKLM:\SOFTWARE\LabTech",
"HKLM:\SOFTWARE\WOW6432Node\LabTech",
"HKLM:\SYSTEM\CurrentControlSet\Services\LTService",
"HKLM:\SYSTEM\CurrentControlSet\Services\LTSvcMon"
)

$UninstallRegistryKeys = @(
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ============================================================
# STEP 1 - DETECT EXISTING AUTOMATE INSTALLATION
# ============================================================

Write-Step "[1/6] Detecting existing Automate installation..."

$FoundSomething = $false

# Check services
foreach ($svc in $Services) {

    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if ($service) {
        Write-Host "  Service found: $svc [$($service.Status)]"
        $FoundSomething = $true
    }
}

# Check processes
foreach ($processName in $Processes) {

    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue

    if ($process) {
        Write-Host "  Process found: $processName"
        $FoundSomething = $true
    }
}

# Check installation directories
foreach ($path in $AutomatePaths) {

    if (Test-Path $path) {
        Write-Host "  Installation path found: $path"
        $FoundSomething = $true
}
}

# Check registry
foreach ($reg in $AutomateRegistryKeys) {

    if (Test-Path $reg) {
        Write-Host "  Registry entry found: $reg"
        $FoundSomething = $true
    }

}

if ($FoundSomething) {
Write-Success "Existing Automate remnants detected."
}
else {
Write-WarningMessage "No obvious Automate installation detected."
Write-Host "  Continuing with cleanup and reinstall anyway."
}
# ============================================================
# STEP 1 - Stop Services and Processes
# ============================================================
Write-Step "[2/6] Stopping Automate services and processes..."

foreach ($svc in $Services) {

    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if ($service) {
        Write-Host "  Stopping service: $svc"

        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            $serviceCheck = Get-Service -Name $svc -ErrorAction SilentlyContinue

            if ($serviceCheck -and $serviceCheck.Status -eq "Stopped") {
                Write-Success "$svc stopped."
            }
            else {
                Write-WarningMessage "$svc may still be running."
            }
        }
        catch {
            Write-WarningMessage "Unable to stop $svc : $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "  $svc not registered."
    }
}

# Kill known Automate processes
foreach ($processName in $Processes) {

    $processesFound = Get-Process -Name $processName -ErrorAction SilentlyContinue

    foreach ($process in $processesFound) {

        Write-Host "  Terminating process: $processName (PID $($process.Id))"

        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-Success "Process terminated."
        }
        catch {
            Write-WarningMessage "Unable to terminate PID $($process.Id)."
        }
    }
}
# ============================================================
# STEP 2 - Uninstall via MSI/Add-Remove Programs
# ============================================================
Write-Step "[3/6] Searching for Automate uninstall entries..."

$FoundUninstaller = $false

foreach ($key in $UninstallRegistryKeys) {

    if (-not (Test-Path $key)) {
        continue
    }

    Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {

        $app = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue

        if (-not $app) {
            return
        }

        $displayName = $app.DisplayName

        if (
            $displayName -like "*Automate*" -or
            $displayName -like "*LabTech*" -or
            $displayName -like "*ConnectWise Automate*"
        ) {

            Write-Host "  Found installed product: $displayName"
            $FoundUninstaller = $true

            if ($app.UninstallString) {

                Write-Host "  Uninstall command:"
                Write-Host "  $($app.UninstallString)"

                try {

                    if ($app.UninstallString -match "msiexec") {

                        $guidMatch = [regex]::Match(
                            $app.UninstallString,
                            '\{[A-Fa-f0-9\-]+\}'
                        )

                        if ($guidMatch.Success) {

                            $guid = $guidMatch.Value

                            Write-Host "  Running MSI uninstall for $guid"

                            Start-Process `
                                -FilePath "msiexec.exe" `
                                -ArgumentList "/x $guid /qn /norestart" `
                                -Wait `
                                -ErrorAction SilentlyContinue

                            Write-Success "MSI uninstall completed."
                        }
                        else {
                            Write-WarningMessage "MSI detected but product GUID could not be determined."
                        }

                    }
                    else {

                        Write-Host "  Running existing uninstall command..."

                        Start-Process `
                            -FilePath "cmd.exe" `
                            -ArgumentList "/c `"$($app.UninstallString)`"" `
                            -Wait `
                            -ErrorAction SilentlyContinue

                        Write-Success "Uninstaller completed."
                    }

                }
                catch {
                    Write-WarningMessage "Uninstall attempt failed: $($_.Exception.Message)"
                }
            }
            else {
                Write-WarningMessage "No uninstall command was registered."
            }
        }
    }
}

if (-not $FoundUninstaller) {
    Write-Host "  No Automate uninstall entry found."
}
# Give the uninstaller time to finish

Start-Sleep -Seconds 5

# ============================================================
# STEP 4 - REMOVE SERVICES, FILES AND REGISTRY REMNANTS
# ============================================================

Write-Step "[4/6] Removing Automate remnants..."

# ------------------------------------------------------------
# Remove services
# ------------------------------------------------------------

foreach ($svc in $Services) {

    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if ($service) {

        Write-Host "  Removing service: $svc"

        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
        catch {}

        sc.exe delete $svc | Out-Null

        Start-Sleep -Seconds 2

        if (-not (Get-Service -Name $svc -ErrorAction SilentlyContinue)) {
            Write-Success "$svc removed."
        }
        else {
            Write-WarningMessage "$svc may still exist."
        }
    }
}

# ------------------------------------------------------------
# Remove files/directories
# ------------------------------------------------------------

foreach ($path in $AutomatePaths) {

    if (Test-Path $path) {

        Write-Host "  Removing: $path"

        try {
            Remove-Item `
                -Path $path `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue

            if (-not (Test-Path $path)) {
                Write-Success "Removed."
            }
            else {
                Write-WarningMessage "Path still exists."
            }
        }
        catch {
            Write-WarningMessage "Unable to completely remove path."
        }
    }
}

# ------------------------------------------------------------
# Remove registry remnants
# ------------------------------------------------------------

foreach ($reg in $AutomateRegistryKeys) {

    if (Test-Path $reg) {

        Write-Host "  Removing registry key: $reg"

        try {

            Remove-Item `
                -Path $reg `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue

            if (-not (Test-Path $reg)) {
                Write-Success "Registry key removed."
            }
            else {
                Write-WarningMessage "Registry key still exists."
            }

        }
        catch {
            Write-WarningMessage "Unable to remove registry key."
        }
    }
}

# ============================================================
# STEP 5 - VERIFY CLEANUP AND INSTALL
# ============================================================

Write-Step "[5/6] Verifying cleanup before reinstall..."

$Remaining = $false

foreach ($svc in $Services) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Write-WarningMessage "Service still exists: $svc"
        $Remaining = $true
    }
}

foreach ($path in $AutomatePaths) {
    if (Test-Path $path) {
        Write-WarningMessage "Installation path still exists: $path"
        $Remaining = $true
    }
}

if ($Remaining) {
    Write-WarningMessage "Some Automate remnants remain."
    Write-Host "  Continuing with installation because the Automate installer"
    Write-Host "  can perform its own existing-agent detection/removal."
}
else {
    Write-Success "Known Automate remnants successfully removed."
}

Start-Sleep -Seconds 3

Write-Host ""
Write-Host "Installing fresh Automate agent..." -ForegroundColor Cyan
Write-Host ""

# ============================================================
# INSTALL AUTOMATE
# ============================================================

try {
    Write-Host "Downloading Automate PowerShell module..."

    Invoke-Expression (
        New-Object Net.WebClient
    ).DownloadString(
        'https://raw.githubusercontent.com/Braingears/PowerShell/master/Automate-Module.psm1'
    )

    Write-Host ""
    Write-Host "Running Install-Automate..." -ForegroundColor Cyan
    Write-Host ""

    $InstallResult = Install-Automate `
        -Server $Server `
        -LocationID $LocationID `
        -Token $Token `
        -Force
}
catch {
    Write-Host ""
    Write-ErrorMessage "Automate installation failed."
    Write-ErrorMessage $_.Exception.Message

    exit 1
}

# ============================================================
# STEP 6 - VERIFY INSTALLATION
# ============================================================

Write-Step "[6/6] Verifying Automate installation..."
Start-Sleep -Seconds 5

# ------------------------------------------------------------
# Check services
# ------------------------------------------------------------

$LTService = Get-Service -Name "LTService" -ErrorAction SilentlyContinue
$LTSvcMon  = Get-Service -Name "LTSvcMon" -ErrorAction SilentlyContinue

if ($LTService) {
    if ($LTService.Status -eq "Running") {
        Write-Success "LTService is RUNNING."
    }
    else {
        Write-ErrorMessage "LTService exists but is $($LTService.Status)."
    }
}
else {
    Write-ErrorMessage "LTService was NOT found."
}

if ($LTSvcMon) {
    if ($LTSvcMon.Status -eq "Running") {
        Write-Success "LTSvcMon is RUNNING."
    }
    else {
        Write-WarningMessage "LTSvcMon exists but is $($LTSvcMon.Status)."
    }
}
else {
    Write-WarningMessage "LTSvcMon was not found." 
}

# ------------------------------------------------------------
# Display installer result
# ------------------------------------------------------------

if ($InstallResult) {
    Write-Host ""
    Write-Host "Automate installation result:" -ForegroundColor Cyan
    Write-Host ""

    $InstallResult | Format-List

}

# ============================================================
# FINAL RESULT
# ============================================================

$FinalService = Get-Service -Name "LTService" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan

if ($FinalService -and $FinalService.Status -eq "Running") {
    Write-Host "        AUTOMATE REINSTALL SUCCESSFUL" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "LTService: RUNNING" -ForegroundColor Green
}
else {
    Write-Host "        AUTOMATE REINSTALL REQUIRES ATTENTION" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "LTService was not confirmed as running." -ForegroundColor Red
    Write-Host "Review the installation transcript:"
    Write-Host "C:\Windows\Temp\Automate_Deploy.txt"
}

Write-Host ""
Write-Host "=== Automate RMM Recovery Complete ===" -ForegroundColor Cyan
