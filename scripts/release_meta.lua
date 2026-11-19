-- Pure helpers for release tag / zip naming (shared contract for scripts + tests).
local M = {}

function M.parse_version(config_text)
  if type(config_text) ~= "string" then
    return nil
  end
  return config_text:match("VERSION%s*=%s*\"([^\"]+)\"")
end

function M.version_tag(version)
  if type(version) ~= "string" or version == "" then
    return nil
  end
  return "v" .. version
end

function M.forever_zip_name(package_name, version)
  if type(package_name) ~= "string" or package_name == "" then
    return nil
  end
  if type(version) ~= "string" or version == "" then
    return nil
  end
  -- Packager names archives from the git tag (v1.2.3), not bare Config.VERSION.
  local labeled = version
  if not labeled:match("^[vV]") then
    labeled = "v" .. labeled
  end
  return string.format("%s-%s-forever.zip", package_name, labeled)
end

return M
