-- Update root CHANGELOG.md from commit subjects on stdin (Keep a Changelog).
-- Usage:
--   git log ... --pretty=format:%s | lua scripts/update_changelog.lua <version> <YYYY-MM-DD> [CHANGELOG.md] [--notes-out path]
--
-- Writes CHANGELOG.md and optionally extracts the version section body to --notes-out.

local version = arg[1]
local date = arg[2]
local changelog_path = "CHANGELOG.md"
local notes_out = nil

local i = 3
while i <= #arg do
  if arg[i] == "--notes-out" then
    notes_out = arg[i + 1]
    i = i + 2
  else
    changelog_path = arg[i]
    i = i + 1
  end
end

if not version or not date or version == "" or date == "" then
  io.stderr:write("Usage: lua scripts/update_changelog.lua <version> <YYYY-MM-DD> [CHANGELOG.md] [--notes-out path]\n")
  os.exit(1)
end

local script_path = arg[0]
local script_dir = script_path:match("^(.*)[/\\]") or "."
package.path = script_dir .. "/?.lua;" .. package.path
local Changelog = require("changelog_meta")

local stdin = io.read("*a") or ""
local subjects = Changelog.parse_subject_lines(stdin)

local existing = nil
local fh = io.open(changelog_path, "r")
if fh then
  existing = fh:read("*a")
  fh:close()
end

local merged = Changelog.merge_changelog(existing, version, date, subjects)
fh = assert(io.open(changelog_path, "w"))
fh:write(merged)
if not merged:match("\n$") then
  fh:write("\n")
end
fh:close()

if notes_out then
  local notes = Changelog.extract_version_notes(merged, version) or ("Release " .. version .. "\n")
  local out = assert(io.open(notes_out, "w"))
  out:write(notes)
  out:close()
end

print(string.format("Updated %s for [%s] - %s (%d commit subject(s))", changelog_path, version, date, #subjects))
