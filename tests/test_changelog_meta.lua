-- Pure Lua tests for Keep a Changelog helpers used by release wrappers.
-- Run: lua tests/test_changelog_meta.lua

local root = arg[0]:match("^(.*)[/\\]") or "."
package.path = root .. "/../scripts/?.lua;" .. package.path
local Changelog = require("changelog_meta")

local failures = 0

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    failures = failures + 1
    print(string.format("FAIL: %s\n  expected: %s\n  actual:   %s", message, tostring(expected), tostring(actual)))
  else
    print("PASS: " .. message)
  end
end

local function assert_contains(haystack, needle, message)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    failures = failures + 1
    print(string.format("FAIL: %s\n  missing: %s\n  in: %s", message, tostring(needle), tostring(haystack)))
  else
    print("PASS: " .. message)
  end
end

assert_eq(Changelog.classify_subject("feat: add window"), "Added", "feat -> Added")
assert_eq(Changelog.classify_subject("feat(ui): toggle"), "Added", "feat scope -> Added")
assert_eq(Changelog.classify_subject("fix: nil check"), "Fixed", "fix -> Fixed")
assert_eq(Changelog.classify_subject("fix(core): race"), "Fixed", "fix scope -> Fixed")
assert_eq(Changelog.classify_subject("remove: old flag"), "Removed", "remove -> Removed")
assert_eq(Changelog.classify_subject("deprecate: legacy API"), "Deprecated", "deprecate -> Deprecated")
assert_eq(Changelog.classify_subject("security: escape html"), "Security", "security -> Security")
assert_eq(Changelog.classify_subject("docs: update README"), "Changed", "docs -> Changed")
assert_eq(Changelog.classify_subject("chore: bump toc"), "Changed", "chore -> Changed")
assert_eq(Changelog.classify_subject("Update toc"), "Changed", "unprefixed -> Changed")
assert_eq(Changelog.classify_subject(""), nil, "empty subject -> nil")
assert_eq(Changelog.classify_subject("  "), nil, "whitespace subject -> nil")

assert_eq(
  Changelog.strip_conventional_prefix("feat(ui): add panel"),
  "add panel",
  "strip conventional prefix"
)
assert_eq(
  Changelog.strip_conventional_prefix("Fix tooltip flicker"),
  "Fix tooltip flicker",
  "keep unprefixed subject"
)

local section = Changelog.build_version_section("1.2.0", "2026-03-17", {
  "feat: add maintain UI",
  "fix: colon-form crash",
  "docs: release notes",
})
assert_contains(section, "## [1.2.0] - 2026-03-17", "section heading")
assert_contains(section, "### Added", "Added heading")
assert_contains(section, "- add maintain UI", "Added bullet")
assert_contains(section, "### Fixed", "Fixed heading")
assert_contains(section, "- colon-form crash", "Fixed bullet")
assert_contains(section, "### Changed", "Changed heading")
assert_contains(section, "- release notes", "Changed bullet")

local empty_merge = Changelog.merge_changelog(nil, "1.0.0", "2026-01-01", { "feat: initial" })
assert_contains(empty_merge, "# Changelog", "header on empty")
assert_contains(empty_merge, "## [Unreleased]", "Unreleased on empty")
assert_contains(empty_merge, "## [1.0.0] - 2026-01-01", "version after Unreleased")
assert_contains(empty_merge, "- initial", "initial bullet")

local existing = [[# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-01-01

### Added

- old entry
]]

local replaced = Changelog.merge_changelog(existing, "1.0.0", "2026-01-02", { "fix: bug" })
assert_contains(replaced, "## [1.0.0] - 2026-01-02", "replace same version date")
assert_contains(replaced, "- bug", "replace same version body")
if replaced:find("old entry", 1, true) then
  failures = failures + 1
  print("FAIL: old entry should be removed when replacing version")
else
  print("PASS: old version section replaced")
end

local inserted = Changelog.merge_changelog(existing, "1.1.0", "2026-02-01", { "feat: next" })
assert_contains(inserted, "## [1.1.0] - 2026-02-01", "insert newer version")
local unreleased_pos = inserted:find("## [Unreleased]", 1, true)
local v110_pos = inserted:find("## [1.1.0]", 1, true)
local v100_pos = inserted:find("## [1.0.0]", 1, true)
assert_eq(type(unreleased_pos) == "number" and type(v110_pos) == "number" and unreleased_pos < v110_pos, true, "1.1.0 after Unreleased")
assert_eq(type(v110_pos) == "number" and type(v100_pos) == "number" and v110_pos < v100_pos, true, "1.1.0 before 1.0.0")

local notes = Changelog.extract_version_notes(inserted, "1.1.0")
assert_contains(notes, "### Added", "extract notes has Added")
assert_contains(notes, "- next", "extract notes bullet")
assert_eq(Changelog.extract_version_notes(inserted, "9.9.9"), nil, "missing version notes -> nil")

local subjects = Changelog.parse_subject_lines("feat: a\n\nfix: b\n")
assert_eq(#subjects, 2, "parse two subjects")
assert_eq(subjects[1], "feat: a", "first subject")
assert_eq(subjects[2], "fix: b", "second subject")

if failures > 0 then
  print(string.format("%d failure(s)", failures))
  os.exit(1)
end
print("All changelog_meta tests passed.")
