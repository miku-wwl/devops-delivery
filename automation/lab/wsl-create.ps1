<#
.SYNOPSIS
  Create the isolated "devops-lab" WSL2 distro (Ubuntu 24.04 LTS) on drive D:.

.DESCRIPTION
  Downloads the official Ubuntu WSL root filesystem from cloud-images.ubuntu.com,
  verifies its SHA256 against the published SHA256SUMS, then registers it with
  `wsl --import`. Needs no administrator rights. Idempotent: exits early when the
  distro already exists.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File automation\lab\wsl-create.ps1
#>
param(
  [string]$DistroName = 'devops-lab',
  [string]$InstallDir = 'D:\wsl\devops-lab',
  [string]$CacheDir   = 'D:\wsl\images',
  [string]$BaseUrl    = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/current',
  [string]$ImageName  = 'ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz'
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'   # make wsl.exe print UTF-8 instead of UTF-16

if ((wsl.exe -l -q) -contains $DistroName) {
  Write-Host "WSL distro '$DistroName' already exists - nothing to do."
  exit 0
}

New-Item -ItemType Directory -Force -Path $CacheDir, $InstallDir | Out-Null
$image = Join-Path $CacheDir $ImageName

if (-not (Test-Path $image)) {
  Write-Host "Downloading $BaseUrl/$ImageName"
  curl.exe -fsSL --retry 3 -o $image "$BaseUrl/$ImageName"
  if ($LASTEXITCODE -ne 0) { throw "download failed" }
}

$sums = curl.exe -fsSL "$BaseUrl/SHA256SUMS"
$expected = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($ImageName) } |
             Select-Object -First 1).Split(' ')[0].Trim().ToLower()
$actual = (Get-FileHash -Algorithm SHA256 $image).Hash.ToLower()
Write-Host "expected sha256: $expected"
Write-Host "actual   sha256: $actual"
if ($expected -ne $actual) { throw "SHA256 mismatch - refusing to import" }

wsl.exe --import $DistroName $InstallDir $image --version 2
if ($LASTEXITCODE -ne 0) { throw "wsl --import failed" }
wsl.exe -l -v
