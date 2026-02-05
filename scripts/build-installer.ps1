<#
.SYNOPSIS
  DEV-only CI pipeline for building and validating a Windows installer
  using MSBuild and InstallShield.
#>

param (
    [string]$Configuration = "Release",
    [string]$Environment   = "Dev"
)

# ==============================
# Safety Settings
# ==============================
$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# ==============================
# CI Detection
# ==============================
$IsCI = $env:GITHUB_ACTIONS -eq "true"

Write-Host "========================================"
Write-Host " DEV Installer Pipeline Started"
Write-Host " Configuration : $Configuration"
Write-Host " Environment   : $Environment"
Write-Host " CI Mode       : $IsCI"
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
function Write-Step {
    param ([string]$Message)
    Write-Host "`n=== $Message ==="
}

function Ensure-Path {
    param ([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Required path not found: $Path"
    }
}

# ==============================
# STEP 1: Validate Required Files
# ==============================
Write-Step "Validating required files"

Ensure-Path $SolutionPath
Ensure-Path $ISMPath
Ensure-Path $InstallShieldPath

# ==============================
# STEP 2: Validate MSBuild (CI only)
# ==============================
Write-Step "Validating MSBuild availability"

if ($IsCI) {
    if (-not (Get-Command msbuild -ErrorAction SilentlyContinue)) {
        throw "MSBuild not found on CI runner"
    }
    Write-Host "MSBuild detected"
}
else {
    Write-Host "Local execution detected — MSBuild check skipped"
}

# ==============================
# STEP 3: Build Application (CI only)
# ==============================
Write-Step "Building application"

if ($IsCI) {
    msbuild $SolutionPath `
        /p:Configuration=$Configuration `
        /m
}
else {
    Write-Host "Skipping MSBuild locally (corporate laptop)"
}

# ==============================
# STEP 4: Build Installer (InstallShield)
# ==============================
Write-Step "Building installer using InstallShield"

$IsCmd = Join-Path $InstallShieldPath "IsCmdBld.exe"
Ensure-Path $IsCmd

& $IsCmd `
    -p $ISMPath `
    -r ProductConfiguration `
    -c $Configuration

# ==============================
# STEP 5: Locate Installer Output
# ==============================
Write-Step "Locating installer output"

Ensure-Path $InstallerOutputPath

$Installer = Get-ChildItem $InstallerOutputPath -Filter *.exe | Select-Object -First 1

if (-not $Installer) {
    throw "Installer EXE not found in $InstallerOutputPath"
}

Write-Host "Installer found: $($Installer.FullName)"

# ==============================
# STEP 6: Silent Install Test (CI only)
# ==============================
Write-Step "Testing silent install"

if ($IsCI) {
    Start-Process $Installer.FullName `
        -ArgumentList "/s /v`"/qn`"" `
        -Wait

    if ($LASTEXITCODE -ne 0) {
        throw "Silent install failed with exit code $LASTEXITCODE"
    }

    Write-Host "Silent install succeeded"
}
else {
    Write-Host "Skipping silent install locally"
}

# ==============================
# STEP 7: Validate Installation (CI only)
# ==============================
Write-Step "Validating installation"

if ($IsCI) {
    $service = Get-Service $ServiceName -ErrorAction SilentlyContinue

    if (-not $service) {
        throw "Validation failed: Service '$ServiceName' not found"
    }

    Write-Host "Service '$ServiceName' validated"
}
else {
    Write-Host "Skipping installation validation locally"
}

# ==============================
# STEP 8: Uninstall (Cleanup - CI only)
# ==============================
Write-Step "Uninstalling application (cleanup)"

if ($IsCI) {
    $product = Get-WmiObject Win32_Product |
        Where-Object { $_.Name -like "MyApp*" }

    if ($product) {
        $product.Uninstall() | Out-Null
        Write-Host "Application uninstalled"
    }
    else {
        Write-Host "Application not found (already clean)"
    }
}
else {
    Write-Host "Skipping uninstall locally"
}

# ==============================
# DONE
# ==============================
Write-Host "`n========================================"
Write-Host " DEV Installer Pipeline Completed OK"
Write-Host "========================================"
