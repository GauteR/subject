#Requires -Version 5.1
<#
.SYNOPSIS
  Run unit tests, then package Subject with BigWigs release.sh (optional upload).

.PARAMETER DryRun
  Skip CurseForge/Wago upload and GitHub release (passes -d to release.sh).

.PARAMETER SkipTests
  Skip lua unit tests.

.PARAMETER ExtraArgs
  Extra arguments forwarded to release.sh.

  Non-dry-run updates CHANGELOG.md from commits, commits it when needed, ensures
  annotated tag v{Config.VERSION} on HEAD, pushes it to origin, then creates a
  GitHub Release (gh) with notes from CHANGELOG.md and the forever zip asset.
#>
param(
  [switch]$DryRun,
  [switch]$SkipTests,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"
$PackageName = "subject"
$ConfigPathRel = "subject\Config.lua"
$ChangelogPathRel = "CHANGELOG.md"
$script:ReleaseVersion = $null
$script:ChangelogNotesFile = $null
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

# BigWigs packager requires a .git directory; linked worktrees use a .git file.
$gitEntry = Join-Path $RepoRoot ".git"
if ((Test-Path $gitEntry) -and -not (Test-Path $gitEntry -PathType Container)) {
  Write-Error "Run release from the primary git checkout, not a linked worktree (packager needs a .git directory)."
}

function ConvertTo-GitBashPath([string]$WinPath) {
  $full = (Resolve-Path $WinPath).Path
  if ($full -match '^([A-Za-z]):\\(.*)$') {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = ($Matches[2] -replace '\\', '/')
    return "/$drive/$rest"
  }
  return ($full -replace '\\', '/')
}

function Find-Bash {
  # Prefer Git Bash. Avoid Windows\system32\bash.exe (WSL launcher).
  $candidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notmatch '(?i)\\Windows\\System32\\bash\.exe$') {
    return $cmd.Source
  }
  return $null
}

function Test-GitBashHasZip([string]$BashPath) {
  & $BashPath -lc "command -v zip >/dev/null 2>&1"
  return ($LASTEXITCODE -eq 0)
}

function New-ReleaseZip {
  param(
    [string]$PackageDir,
    [string]$ZipPath
  )
  if (-not (Test-Path $PackageDir)) {
    Write-Error "Package directory missing: $PackageDir"
  }
  if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
  $parent = Split-Path -Parent $PackageDir
  $name = Split-Path -Leaf $PackageDir

  # Real ZIP only. Windows tar.exe -a often writes a tar stream named *.zip;
  # CurseForge then rejects uploads ("Failed to verify archive").
  $zipCmd = Get-Command zip -ErrorAction SilentlyContinue
  if ($zipCmd) {
    Push-Location $parent
    try {
      & zip -r $ZipPath $name
      if ($LASTEXITCODE -ne 0) {
        Write-Error "zip failed to create $ZipPath (exit $LASTEXITCODE)."
      }
    }
    finally {
      Pop-Location
    }
    return
  }

  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  if ($py) {
    & $py.Source -c "import sys; from pathlib import Path; import shutil; parent, name, zip_path = sys.argv[1:4]; shutil.make_archive(str(Path(zip_path).with_suffix('')), 'zip', root_dir=parent, base_dir=name)" $parent $name $ZipPath
    if ($LASTEXITCODE -ne 0) {
      Write-Error "python failed to create $ZipPath (exit $LASTEXITCODE)."
    }
    return
  }

  Push-Location $parent
  try {
    Compress-Archive -Path $name -DestinationPath $ZipPath -Force
  }
  finally {
    Pop-Location
  }
}

function Import-DotEnv([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) { return }
    $name = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    # Do not overwrite tokens already set in the process environment.
    $existing = [Environment]::GetEnvironmentVariable($name, "Process")
    if ([string]::IsNullOrEmpty($existing)) {
      [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
  return $true
}

function Clear-PackagerGitHubTokens {
  foreach ($name in @("GH_API_TOKEN", "GITHUB_API_TOKEN", "GITHUB_OAUTH")) {
    [Environment]::SetEnvironmentVariable($name, $null, "Process")
  }
}

function Find-ReleaseZip {
  param(
    [string]$PackageName,
    [string]$Version
  )
  $labeled = if ($Version -match '^[vV]') { $Version } else { "v$Version" }
  $preferred = Join-Path (Join-Path $RepoRoot ".release") "$PackageName-$labeled-forever.zip"
  if (Test-Path $preferred) { return $preferred }
  $zipMatches = @(Get-ChildItem (Join-Path $RepoRoot ".release\$PackageName-*.zip") -ErrorAction SilentlyContinue)
  if ($zipMatches.Count -gt 0) { return $zipMatches[0].FullName }
  return $null
}

function Get-ConfigVersion([string]$ConfigPath) {
  if (-not (Test-Path $ConfigPath)) {
    Write-Error "Missing Config.lua at $ConfigPath"
  }
  $raw = Get-Content $ConfigPath -Raw
  if ($raw -notmatch '(?m)^\s*VERSION\s*=\s*"([^"]+)"') {
    Write-Error "Could not resolve Config.VERSION from $ConfigPath"
  }
  return $Matches[1].Trim()
}

function Get-PreviousVersionTag([string]$CurrentTag) {
  $tags = @(git tag -l "v*" --sort=-v:refname)
  foreach ($tag in $tags) {
    if ($tag -and $tag -ne $CurrentTag) {
      return $tag
    }
  }
  return $null
}

function Update-Changelog {
  param(
    [string]$Version,
    [bool]$CommitChanges
  )
  $lua = Get-Command lua -ErrorAction SilentlyContinue
  if (-not $lua) {
    Write-Error "lua not found on PATH (required to update CHANGELOG.md)."
  }
  $dateUtc = [DateTime]::UtcNow.ToString("yyyy-MM-dd")
  $notesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("subject-changelog-notes-" + [guid]::NewGuid().ToString("n") + ".md")
  $subjectsFile = Join-Path ([System.IO.Path]::GetTempPath()) ("subject-changelog-subjects-" + [guid]::NewGuid().ToString("n") + ".txt")
  $script:ChangelogNotesFile = $notesFile
  $prev = Get-PreviousVersionTag "v$Version"
  if ($prev) {
    $range = "$prev..HEAD"
  } else {
    $range = "HEAD"
  }
  Write-Host "==> Updating CHANGELOG.md for v$Version from $range"
  # Avoid PowerShell UTF-8 BOM on subject files; write ASCII/UTF-8 without BOM.
  $subjects = @(& git log $range --no-merges --pretty=format:%s)
  $subjectText = ($subjects -join "`n") + "`n"
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($subjectsFile, $subjectText, $utf8NoBom)
  Get-Content -Path $subjectsFile -Raw | & lua (Join-Path $RepoRoot "scripts\update_changelog.lua") $Version $dateUtc (Join-Path $RepoRoot $ChangelogPathRel) --notes-out $notesFile
  if ($LASTEXITCODE -ne 0) {
    Write-Error "update_changelog.lua failed (exit $LASTEXITCODE)."
  }
  Remove-Item -Force $subjectsFile -ErrorAction SilentlyContinue
  if ($CommitChanges) {
    git add -- $ChangelogPathRel
    & git diff --cached --quiet -- $ChangelogPathRel
    if ($LASTEXITCODE -ne 0) {
      # --only keeps other staged files out of this commit.
      git commit --only -m "docs: update CHANGELOG for v$Version" -- $ChangelogPathRel
      if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to commit CHANGELOG.md (exit $LASTEXITCODE)."
      }
      Write-Host "==> Committed CHANGELOG.md"
    } else {
      Write-Host "==> CHANGELOG.md unchanged"
    }
  }
}

function New-GitHubRelease {
  param(
    [string]$PackageName,
    [string]$Version
  )
  $tag = "v$Version"
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) {
    Write-Error "gh not found on PATH. Install GitHub CLI (https://cli.github.com/) and run gh auth login."
  }
  $zipPath = Find-ReleaseZip -PackageName $PackageName -Version $Version
  if (-not $zipPath) {
    Write-Error "No release zip found under .release/ for $PackageName"
  }
  Write-Host "==> GitHub release $tag with $(Split-Path -Leaf $zipPath)"
  & gh release view $tag 1>$null 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "==> Release $tag already exists; uploading asset"
    & gh release upload $tag $zipPath --clobber
    if ($LASTEXITCODE -ne 0) {
      Write-Error "gh release upload failed (exit $LASTEXITCODE)."
    }
  } else {
    $notesArgs = @("--generate-notes")
    if ($script:ChangelogNotesFile -and (Test-Path $script:ChangelogNotesFile)) {
      $notesArgs = @("--notes-file", $script:ChangelogNotesFile)
    }
    & gh release create $tag --title $tag @notesArgs $zipPath
    if ($LASTEXITCODE -ne 0) {
      Write-Error "gh release create failed (exit $LASTEXITCODE)."
    }
  }
}

# release.sh only auto-loads $topdir/.env; also support .release/.env via this wrapper.
$loadedReleaseEnv = Import-DotEnv (Join-Path $RepoRoot ".release\.env")
$loadedRootEnv = Import-DotEnv (Join-Path $RepoRoot ".env")
if ($loadedReleaseEnv -or $loadedRootEnv) {
  Write-Host "==> Loaded local token env file(s)"
}

# Ensure annotated v{Config.VERSION} on HEAD and push to origin (real releases only).
function Ensure-VersionTag([string]$ConfigPath) {
  $version = Get-ConfigVersion $ConfigPath
  $tag = "v$version"
  $script:ReleaseVersion = $version
  # Avoid piping git into Out-Null — that can drop a reliable $LASTEXITCODE.
  & git show-ref --tags --verify --quiet "refs/tags/$tag"
  if ($LASTEXITCODE -eq 0) {
    $tagCommit = (git rev-list -n 1 $tag).Trim()
    $headCommit = (git rev-parse HEAD).Trim()
    if ($tagCommit -ne $headCommit) {
      Write-Error "Tag $tag exists but does not point at HEAD ($tagCommit vs $headCommit)."
    }
    Write-Host "==> Tag $tag already on HEAD"
  } else {
    Write-Host "==> Creating annotated tag $tag from Config.VERSION"
    git tag -a $tag -m $tag
    if ($LASTEXITCODE -ne 0) {
      Write-Error "Failed to create tag $tag (exit $LASTEXITCODE)."
    }
  }
  Write-Host "==> Pushing tag $tag to origin"
  git push origin "refs/tags/$tag"
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push tag $tag (exit $LASTEXITCODE)."
  }
}

if (-not $SkipTests) {
  $lua = Get-Command lua -ErrorAction SilentlyContinue
  if (-not $lua) {
    Write-Error "lua not found on PATH. Install a Lua interpreter or pass -SkipTests."
  }
  Write-Host "==> Running tests"
  foreach ($test in @("test_subject.lua", "test_release_meta.lua", "test_changelog_meta.lua")) {
    & lua "tests/$test"
    if ($LASTEXITCODE -ne 0) {
      Write-Error "Tests failed ($test exit $LASTEXITCODE)."
    }
  }
}

$script:ReleaseVersion = Get-ConfigVersion (Join-Path $RepoRoot $ConfigPathRel)
if ($DryRun) {
  Update-Changelog -Version $script:ReleaseVersion -CommitChanges $false
} else {
  Update-Changelog -Version $script:ReleaseVersion -CommitChanges $true
}

$bash = Find-Bash
if (-not $bash) {
  Write-Error "Git Bash (bash.exe) not found. Install Git for Windows or put bash on PATH."
}

$releaseSh = Join-Path $RepoRoot ".release\release.sh"
if (-not (Test-Path $releaseSh)) {
  Write-Error "Missing $releaseSh. Restore from BigWigsMods/packager (pinned v2.7.0)."
}

$unixRoot = ConvertTo-GitBashPath $RepoRoot
$useFallbackZip = -not (Test-GitBashHasZip $bash)
$argList = @()
if ($DryRun) {
  $argList += "-d"
} else {
  Ensure-VersionTag (Join-Path $RepoRoot $ConfigPathRel)
}
# Wrapper owns GitHub releases via gh; prevent packager duplicate upload_github.
Clear-PackagerGitHubTokens
if ($useFallbackZip) {
  Write-Host "==> zip not found in Git Bash; packager will skip zip (-z), then Python/Compress-Archive will create a real ZIP"
  $argList += "-z"
}
if ($ExtraArgs) { $argList += $ExtraArgs }
$argString = ($argList | ForEach-Object {
  if ($_ -match '[\s]') { "'" + ($_ -replace "'", "'\''") + "'" } else { $_ }
}) -join " "

Write-Host "==> Packaging with release.sh $argString"
$bashCmd = "cd '$unixRoot' && bash ./.release/release.sh $argString"
& $bash -lc $bashCmd
if ($LASTEXITCODE -ne 0) {
  Write-Error "release.sh failed (exit $LASTEXITCODE)."
}

$packageDir = Join-Path $RepoRoot ".release\$PackageName"
if (-not (Test-Path (Join-Path $packageDir "$PackageName.toc"))) {
  Write-Error "Expected packaged TOC at .release/$PackageName/$PackageName.toc"
}
$forbidden = @("docs", "tests", "scripts")
foreach ($name in $forbidden) {
  if (Test-Path (Join-Path $packageDir $name)) {
    Write-Error "Packaged tree must not contain '$name'."
  }
}

if ($useFallbackZip) {
  $toc = Get-Content (Join-Path $packageDir "$PackageName.toc") -Raw
  $version = "unknown"
  if ($toc -match '(?m)^## Version:\s*(.+)\s*$') {
    $version = $Matches[1].Trim()
  }
  $labeled = if ($version -match '^[vV]') { $version } else { "v$version" }
  $zipName = "$PackageName-$labeled-forever.zip"
  $zipPath = Join-Path (Join-Path $RepoRoot ".release") $zipName
  Write-Host "==> Creating $zipName (real ZIP fallback)"
  New-ReleaseZip -PackageDir $packageDir -ZipPath $zipPath
}

if (-not $DryRun) {
  if (-not $script:ReleaseVersion) {
    $raw = Get-Content (Join-Path $RepoRoot $ConfigPathRel) -Raw
    if ($raw -match '(?m)^\s*VERSION\s*=\s*"([^"]+)"') {
      $script:ReleaseVersion = $Matches[1].Trim()
    }
  }
  if (-not $script:ReleaseVersion) {
    Write-Error "Could not resolve release version for GitHub release."
  }
  New-GitHubRelease -PackageName $PackageName -Version $script:ReleaseVersion
}

Write-Host "==> Done. Artifacts are under .release/"
Get-ChildItem (Join-Path $RepoRoot ".release\*.zip") | ForEach-Object { Write-Host "  $($_.Name) ($([int]($_.Length/1KB)) KB)" }
