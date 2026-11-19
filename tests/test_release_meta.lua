-- Pure Lua tests for release tag / zip naming helpers.
-- Run: lua tests/test_release_meta.lua

local root = arg[0]:match("^(.*)[/\\]") or "."
package.path = root .. "/../scripts/?.lua;" .. package.path
local Meta = require("release_meta")

local failures = 0

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    failures = failures + 1
    print(string.format("FAIL: %s\n  expected: %s\n  actual:   %s", message, tostring(expected), tostring(actual)))
  else
    print("PASS: " .. message)
  end
end

assert_eq(Meta.parse_version('VERSION = "1.2.3",'), "1.2.3", "parse VERSION assignment")
assert_eq(Meta.parse_version("no version here"), nil, "missing VERSION -> nil")
assert_eq(Meta.version_tag("1.2.0"), "v1.2.0", "version tag prefix")
assert_eq(Meta.version_tag(""), nil, "empty version -> nil")
assert_eq(
  Meta.forever_zip_name("subject", "1.2.0"),
  "subject-v1.2.0-forever.zip",
  "forever zip basename"
)

local config_path = root .. "/../subject/Config.lua"
local fh = assert(io.open(config_path, "r"))
local config_text = fh:read("*a")
fh:close()
local version = Meta.parse_version(config_text)
assert_eq(type(version) == "string" and version ~= "", true, "Config.VERSION present")
assert_eq(Meta.version_tag(version), "v" .. version, "Config tag matches VERSION")
assert_eq(
  Meta.forever_zip_name("subject", version),
  string.format("subject-v%s-forever.zip", version),
  "Config zip name"
)

if failures > 0 then
  print(string.format("%d failure(s)", failures))
  os.exit(1)
end
print("All release_meta tests passed.")
