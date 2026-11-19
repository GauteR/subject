#Requires -Version 5.1
<#
.SYNOPSIS
  Copy the subject addon into a local Forever AddOns folder for in-game testing.

.PARAMETER Destination
  Full path to the AddOns directory (parent of the subject folder), or to the
  subject folder itself. Overrides env SUBJECT_FOREVER_ADDONS.

.PARAMETER SkipTests
  Skip lua tests/test_subject.lua.

.PARAMETER WhatIf
  Show what would be copied without writing files.
#>
param(
  [string]$Destination = "",
  [switch]$SkipTests,
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Source = Join-Path $RepoRoot "subject"

# Read Config.VERSION for local TOC substitution (packager uses @project-version@ at release).
function Get-ConfigVersion {
  param([string]$ConfigPath)
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    return $null
  }
  $raw = Get-Content -LiteralPath $ConfigPath -Raw
  if ($raw -match '(?m)^\s*VERSION\s*=\s*"([^"]+)"') {
    return $Matches[1]
  }
  return $null
}

# Replace packager placeholders in the published TOC so AddOn List shows a real version.
function Set-PublishedTocVersion {
  param(
    [string]$TocPath,
    [string]$Version
  )
  if (-not $Version) {
    Write-Error "Could not resolve Config.VERSION for TOC substitution."
  }
  $raw = [System.IO.File]::ReadAllText($TocPath)
  if ($raw -notlike "*@project-version@*") {
    return
  }
  $updated = $raw.Replace("@project-version@", $Version)
  # UTF-8 without BOM — default WriteAllText would add a BOM on Windows PowerShell 5.1.
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($TocPath, $updated, $utf8)
  Write-Host "    TOC Version -> $Version"
}

function Resolve-ForeverAddOnsDir {
  param([string]$Explicit)

  if ($Explicit) {
    $p = $Explicit.TrimEnd('\', '/')
    if ((Split-Path -Leaf $p) -eq "subject") {
      return (Split-Path -Parent $p)
    }
    return $p
  }

  if ($env:SUBJECT_FOREVER_ADDONS) {
    $p = $env:SUBJECT_FOREVER_ADDONS.TrimEnd('\', '/')
    if ((Split-Path -Leaf $p) -eq "subject") {
      return (Split-Path -Parent $p)
    }
    return $p
  }

  $localFile = Join-Path $PSScriptRoot "forever-addons.path"
  if (Test-Path $localFile) {
    $pathLine = $null
    foreach ($raw in Get-Content $localFile) {
      $line = $raw.Trim()
      if (-not $line -or $line.StartsWith("#")) { continue }
      $pathLine = $line
      break
    }
    if ($pathLine) {
      $p = $pathLine.TrimEnd('\', '/')
      if ((Split-Path -Leaf $p) -eq "subject") {
        return (Split-Path -Parent $p)
      }
      return $p
    }
  }

  $candidates = @(
    "D:\World of Warcraft\_forever_\Interface\AddOns",
    "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns",
    "C:\Program Files\World of Warcraft\_forever_\Interface\AddOns",
    (Join-Path ${env:ProgramFiles(x86)} "World of Warcraft\_forever_\Interface\AddOns"),
    (Join-Path $env:ProgramFiles "World of Warcraft\_forever_\Interface\AddOns")
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { return $c }
  }

  return $null
}

if (-not (Test-Path (Join-Path $Source "subject.toc"))) {
  Write-Error "Missing addon source at $Source (expected subject.toc)."
}

if (-not $SkipTests) {
  $lua = Get-Command lua -ErrorAction SilentlyContinue
  if (-not $lua) {
    Write-Error "lua not found on PATH. Install a Lua interpreter or pass -SkipTests."
  }
  Write-Host "==> Running tests"
  & lua (Join-Path $RepoRoot "tests\test_subject.lua")
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Tests failed (exit $LASTEXITCODE)."
  }
}

$addonsDir = Resolve-ForeverAddOnsDir -Explicit $Destination
if (-not $addonsDir) {
  Write-Error @"
Could not find Forever AddOns folder.
Pass -Destination, set SUBJECT_FOREVER_ADDONS, or create scripts/forever-addons.path
with one line, e.g.:
  D:\World of Warcraft\_forever_\Interface\AddOns
"@
}

if (-not (Test-Path $addonsDir)) {
  Write-Error "AddOns directory does not exist: $addonsDir"
}

$target = Join-Path $addonsDir "subject"
Write-Host "==> Publishing $Source"
Write-Host "    -> $target"

$version = Get-ConfigVersion -ConfigPath (Join-Path $Source "Config.lua")
if (-not $version) {
  Write-Error "Could not resolve Config.VERSION from $(Join-Path $Source 'Config.lua')."
}

if ($WhatIf) {
  Write-Host "WhatIf: would replace target with source contents and set TOC Version to $version."
  return
}

if (Test-Path $target) {
  Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -Path (Join-Path $Source "*") -Destination $target -Recurse -Force

$toc = Join-Path $target "subject.toc"
if (-not (Test-Path $toc)) {
  Write-Error "Publish failed: missing $toc"
}

Set-PublishedTocVersion -TocPath $toc -Version $version

Write-Host "==> Done. Reload the Forever client (/reload) or restart to load changes."
