<#
.SYNOPSIS
  DEV-only CI pipeline for building and validating a Windows installer.
#>

# ==============================
# Safety Settings
# ==============================
$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# ==============================
# Parameters
# ==============================
param (
    [string]$Configuration = "Release",
    [string]$Environment   = "Dev"
)

Write-Host "========================================"
Write-Host " DEV Installer Pipeline Started"
Write-Host " Configuration : $Configuration"
Write-Host " Environment   : $Environment"
Write-Host "========================================"

# ==============================
# Paths & Settings
# ==============================
$SolutionPath        = "MyApp.sln"
$InstallShieldPath   = "C:\Program Files (x86)\InstallShield\2022\System"
$ISMPath             = "Installer\MyApp.ism"
$InstallerOutputPath = "Installer\Output"
$ServiceName         = "MyAppService"

# ==============================
# Helper Functions
# ==============================
function Ensure-Path {
    param ([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Required path not found: $Path"
    }
}

function Write-Step {
    param ([string]$Message)
    Write-Host "`n=== $Message ==="
}

# ==============================
# STEP 1: Validate Inputs
# ==============================
Write-Step "Validating inputs"

Ensure-Path $SolutionPath
Ensure-Path $ISMPath
Ensure-Path $InstallShieldPath

# ==============================
# STEP 2: Build Application
# ==============================
Write-Step "Building application"

msbuild $SolutionPath `
    /p:Configuration=$Configuration `
    /m

# ==============================
# STEP 3: Build Installer
# ==============================
Write-Step "Building installer (InstallShield)"

$IsCmd = Join-Path $InstallShieldPath "IsCmdBld.exe"
Ensure-Path $IsCmd

& $IsCmd `
    -p $ISMPath `
    -r ProductConfiguration `
    -c $Configuration

# ==============================
# STEP 4: Locate Installer
# ==============================
Write-Step "Locating installer output"

Ensure-Path $InstallerOutputPath

$Installer = Get-ChildItem $InstallerOutputPath -Filter *.exe | Select-Object -First 1

if (-not $Installer) {
    throw "Installer EXE not found in $InstallerOutputPath"
}

Write-Host "Installer: $($Installer.FullName)"

# ==============================
# STEP 5: Silent Install Test
# ==============================
Write-Step "Testing silent install"

Start-Process $Installer.FullName `
    -ArgumentList "/s /v`"/qn`"" `
    -Wait

if ($LASTEXITCODE -ne 0) {
    throw "Silent install failed with exit code $LASTEXITCODE"
}

# ==============================
# STEP 6: Validate Installation
# ==============================
Write-Step "Validating installation"

$service = Get-Service $ServiceName -ErrorAction SilentlyContinue

if (-not $service) {
    throw "Validation failed: Service '$ServiceName' not found"
}

Write-Host "Service '$ServiceName' validated"

# ==============================
# STEP 7: Uninstall (Cleanup)
# ==============================
Write-Step "Uninstalling application"

$product = Get-WmiObject Win32_Product |
    Where-Object { $_.Name -like "MyApp*" }

if ($product) {
    $product.Uninstall() | Out-Null
    Write-Host "Application uninstalled"
}
else {
    Write-Host "Application not found (already clean)"
}

# ==============================
# DONE
# ==============================
Write-Host "`n========================================"
Write-Host " DEV Installer Pipeline Completed OK"
Write-Host "========================================"
