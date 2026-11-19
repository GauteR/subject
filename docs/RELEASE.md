# Releasing Subject

Local packaging uses [BigWigsMods/packager](https://github.com/BigWigsMods/packager) (`release.sh` **v2.7.0**, Forever-aware).

## Prerequisites

**All platforms**

- `bash`
- `lua` on PATH (for unit tests), or pass `-SkipTests` / `--skip-tests`
- `gh` on PATH and authenticated (`gh auth login`) for real releases (GitHub Release)
- `curl` (for CurseForge/Wago upload)
- `jq` on PATH when uploading to CurseForge/Wago (not required for dry-run)
- `zip` on PATH, or Python (`python`/`python3`) as fallback for a real ZIP (do not use Windows `tar.exe -a`)

**Windows extras**

- Prefer Git Bash for `./scripts/*.sh` (not the WSL `bash.exe` launcher)
- PowerShell wrappers (`scripts/*.ps1`) are available as an alternative
- Run release from the **primary checkout** (not a linked git worktree); BigWigs packager requires a `.git` directory

## One-time setup

1. Ensure [`.release/release.sh`](../.release/release.sh) is present (tracked in git; pinned **BigWigsMods/packager v2.7.0**).
2. Copy [`.release/.env.example`](../.release/.env.example) to `.release/.env` and add tokens when you are ready to upload to CurseForge/Wago:
   - `CF_API_TOKEN` — CurseForge
   - `WAGO_API_TOKEN` — Wago Addons  
   Both `scripts/release.ps1` and `scripts/release.sh` load `.release/.env` (and optionally repo-root `.env`) into the process environment before calling the packager. Do not commit either env file. GitHub Releases use `gh` (not `GH_API_TOKEN`).
3. When CurseForge / Wago projects exist, add these lines to [`subject/subject.toc`](../subject/subject.toc):
   - `## X-Curse-Project-ID: <id>`
   - `## X-Wago-ID: <id>`

Until those IDs exist, omit the lines (dry-run packaging still works; upload needs real IDs + tokens).

## Versioning

Packager reads the version from an **annotated git tag** on HEAD (for example `v1.1.0`).  
`## Version: @project-version@` in the TOC is replaced at package time.

Bump `Config.VERSION` before a real release. `scripts/release.sh` / `scripts/release.ps1`:

1. Update root [`CHANGELOG.md`](../CHANGELOG.md) from git commits since the previous `v*` tag (Keep a Changelog; conventional commits map to Added/Fixed/Changed/…)
2. On real release: commit `CHANGELOG.md` when it changed (`docs: update CHANGELOG for vX.Y.Z`)
3. Create annotated tag `v{Config.VERSION}` on HEAD when missing, then push it to `origin`
4. Package the zip (packager `manual-changelog: CHANGELOG.md` for CurseForge/Wago upload notes)
5. Create a GitHub Release with notes from the new CHANGELOG section and attach the forever zip; if the release already exists, upload the zip with `--clobber`

Dry-run still rewrites `CHANGELOG.md` in the working tree for preview, but does not commit or tag. CurseForge GitHub webhooks read `CHANGELOG.md` from the repo root on the tagged commit — that is why the file is committed before the tag.

Wrappers clear packager GitHub tokens so BigWigs `upload_github` does not create a duplicate release. `lua` is required for changelog updates even when tests are skipped.

Manual tag equivalent:

```powershell
git tag -a v1.1.0 -m "v1.1.0"
git push origin refs/tags/v1.1.0
```

If the tag already exists on another commit, release fails. Untagged HEAD builds (including dry-run without a prior tag) are treated as alpha by packager.

## Local in-game test (not a release)

Copy the working tree addon into Forever AddOns:

```powershell
.\scripts\publish-local.ps1
```

```bash
./scripts/publish-local.sh
```

Same test policy as release: requires `lua` on PATH unless you pass `-SkipTests` / `--skip-tests`. See [`INSTALL.md`](INSTALL.md) for path overrides. This does **not** run packager or upload.

`publish-local` replaces `@project-version@` in the copied TOC with `Config.VERSION` so the AddOn List shows a real number during `/reload` testing. Source TOC in git stays as the packager placeholder.

## Commands

Dry-run (tests + zip, no upload):

```powershell
.\scripts\release.ps1 -DryRun
```

```bash
./scripts/release.sh --dry-run
```

Skip tests:

```powershell
.\scripts\release.ps1 -DryRun -SkipTests
```

```bash
./scripts/release.sh --dry-run --skip-tests
```

Real release (tag push + GitHub Release via `gh`; CurseForge/Wago when tokens and project IDs exist):

```powershell
.\scripts\release.ps1
```

```bash
./scripts/release.sh
```

Extra packager flags:

```powershell
.\scripts\release.ps1 -DryRun -ExtraArgs @("-g", "forever")
```

```bash
./scripts/release.sh --dry-run -- -g forever
```


## What gets packaged

[`.pkgmeta`](../.pkgmeta) uses `package-as: subject` and `move-folders` so the nested [`subject/`](../subject/) addon becomes the zip root. `ignore` excludes docs, tests, scripts, and other repo metadata.

Artifacts land under `.release/` (gitignored except `release.sh` and `.env.example`).

## CurseForge description

Paste [`docs/CURSEFORGE.md`](CURSEFORGE.md) (body below the horizontal rule) into the CurseForge project Description field when the project exists. That file is not included in the zip.

Root [`CHANGELOG.md`](../CHANGELOG.md) is the changelog CurseForge reads from GitHub (webhook) and that packager uploads with `manual-changelog`. It stays listed under `.pkgmeta` `ignore` so it is not copied as addon content beyond changelog handling.
