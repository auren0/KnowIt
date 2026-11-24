[CmdletBinding()]
param(
    [switch]$SkipFlutterBuild,
    [string]$OutputDir = "build\installer"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " KnowIt Windows Installer Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Read application version from pubspec.yaml
$pubspecPath = Join-Path $PSScriptRoot "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
    Write-Error "pubspec.yaml not found at: $pubspecPath"
    exit 1
}

$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?') {
    $appVersion = $Matches[1]
    Write-Host "[1/4] Extracted application version: $appVersion" -ForegroundColor Green
} else {
    Write-Error "Could not parse version from pubspec.yaml."
    exit 1
}

# 2. Build Flutter Windows Release
$sourceDir = Join-Path $PSScriptRoot "build\windows\x64\runner\Release"
$exePath = Join-Path $sourceDir "knowit.exe"

if ($SkipFlutterBuild) {
    Write-Host "[2/4] Skipping Flutter build (-SkipFlutterBuild passed)." -ForegroundColor Yellow
    if (-not (Test-Path $exePath)) {
        Write-Error "Release executable not found at $exePath. Run without -SkipFlutterBuild first."
        exit 1
    }
} else {
    Write-Host "[2/4] Building Flutter Windows release..." -ForegroundColor Cyan
    $flutterCmd = Get-Command "flutter" -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        Write-Error "Flutter SDK not found in PATH. Please ensure flutter is installed and available in PATH."
        exit 1
    }

    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows release build failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }

    if (-not (Test-Path $exePath)) {
        Write-Error "Expected release executable not found at: $exePath"
        exit 1
    }
    Write-Host "      Flutter Windows release built successfully." -ForegroundColor Green
}

# 3. Locate Inno Setup Compiler (ISCC.exe)
Write-Host "[3/4] Locating Inno Setup Compiler (ISCC.exe)..." -ForegroundColor Cyan
$isccPath = $null

$cmd = Get-Command "iscc.exe" -ErrorAction SilentlyContinue
if ($cmd) {
    $isccPath = $cmd.Source
} else {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $isccPath = $cand
            break
        }
    }
}

if (-not $isccPath) {
    Write-Error @"
Inno Setup Compiler (ISCC.exe) was not found.
Please install Inno Setup 6 from https://jrsoftware.org/isdl.php or add ISCC.exe to PATH.
"@
    exit 1
}

Write-Host "      Found Inno Setup Compiler: $isccPath" -ForegroundColor Green

# 4. Compile installer.iss
Write-Host "[4/4] Compiling Windows installer with Inno Setup..." -ForegroundColor Cyan
$issPath = Join-Path $PSScriptRoot "installer.iss"
if (-not (Test-Path $issPath)) {
    Write-Error "installer.iss not found at: $issPath"
    exit 1
}

$targetOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $PSScriptRoot $OutputDir }
if (-not (Test-Path $targetOutputDir)) {
    New-Item -ItemType Directory -Path $targetOutputDir -Force | Out-Null
}

$isccArgs = @(
    "/Qp",
    "/DMyAppVersion=$appVersion",
    "/DMySourceDir=$sourceDir",
    "/DMyOutputDir=$targetOutputDir",
    $issPath
)

& $isccPath $isccArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup compilation failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

$finalInstaller = Join-Path $targetOutputDir "KnowIt-Setup.exe"
if (-not (Test-Path $finalInstaller)) {
    Write-Error "Expected installer output was not found at: $finalInstaller"
    exit 1
}

$fileInfo = Get-Item $finalInstaller
$sizeMb = [math]::Round($fileInfo.Length / 1MB, 2)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Windows Installer Successfully Created!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host " Path: $finalInstaller"
Write-Host " Size: $sizeMb MB ($($fileInfo.Length) bytes)"
Write-Host " App Version: $appVersion"
Write-Host ""
