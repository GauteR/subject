-- Pure helpers for Keep a Changelog generation (release wrappers + tests).
local M = {}

local CATEGORY_ORDER = {
  "Added",
  "Changed",
  "Deprecated",
  "Removed",
  "Fixed",
  "Security",
}

local TYPE_TO_CATEGORY = {
  feat = "Added",
  feature = "Added",
  fix = "Fixed",
  bugfix = "Fixed",
  remove = "Removed",
  removed = "Removed",
  revert = "Removed",
  deprecate = "Deprecated",
  deprecated = "Deprecated",
  security = "Security",
  docs = "Changed",
  doc = "Changed",
  chore = "Changed",
  refactor = "Changed",
  perf = "Changed",
  style = "Changed",
  test = "Changed",
  build = "Changed",
  ci = "Changed",
  change = "Changed",
  changed = "Changed",
}

local HEADER = [[# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
]]

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.parse_subject_lines(text)
  local subjects = {}
  if type(text) ~= "string" or text == "" then
    return subjects
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local subject = trim(line)
    if subject ~= "" then
      subjects[#subjects + 1] = subject
    end
  end
  return subjects
end

function M.classify_subject(subject)
  if type(subject) ~= "string" then
    return nil
  end
  subject = trim(subject)
  if subject == "" then
    return nil
  end
  local type_name = subject:match("^([%w]+)%s*%b()%s*:")
  if not type_name then
    type_name = subject:match("^([%w]+)%s*:")
  end
  if type_name then
    local category = TYPE_TO_CATEGORY[type_name:lower()]
    if category then
      return category
    end
  end
  return "Changed"
end

function M.strip_conventional_prefix(subject)
  if type(subject) ~= "string" then
    return ""
  end
  subject = trim(subject)
  local rest = subject:match("^[%w]+%s*%b()%s*:%s*(.+)$")
  if rest then
    return trim(rest)
  end
  rest = subject:match("^[%w]+%s*:%s*(.+)$")
  if rest then
    return trim(rest)
  end
  return subject
end

local function group_subjects(subjects)
  local buckets = {}
  for _, category in ipairs(CATEGORY_ORDER) do
    buckets[category] = {}
  end
  if type(subjects) ~= "table" then
    return buckets
  end
  for _, subject in ipairs(subjects) do
    local category = M.classify_subject(subject)
    if category then
      local bullet = M.strip_conventional_prefix(subject)
      if bullet ~= "" then
        local list = buckets[category]
        list[#list + 1] = bullet
      end
    end
  end
  return buckets
end

function M.build_version_section(version, date, subjects)
  local lines = {
    string.format("## [%s] - %s", version, date),
    "",
  }
  local buckets = group_subjects(subjects)
  local any = false
  for _, category in ipairs(CATEGORY_ORDER) do
    local items = buckets[category]
    if #items > 0 then
      any = true
      lines[#lines + 1] = "### " .. category
      lines[#lines + 1] = ""
      for _, item in ipairs(items) do
        lines[#lines + 1] = "- " .. item
      end
      lines[#lines + 1] = ""
    end
  end
  if not any then
    lines[#lines + 1] = "### Changed"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "- Maintenance release"
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

local function ensure_header(text)
  if type(text) ~= "string" or trim(text) == "" then
    return HEADER .. "\n## [Unreleased]\n\n"
  end
  if not text:find("# Changelog", 1, true) then
    return HEADER .. "\n## [Unreleased]\n\n" .. text
  end
  if not text:find("## %[Unreleased%]") then
    local header_end = text:find("\n## %[")
    if header_end then
      return text:sub(1, header_end) .. "## [Unreleased]\n\n" .. text:sub(header_end + 1)
    end
    return trim(text) .. "\n\n## [Unreleased]\n\n"
  end
  return text
end

local function version_heading_pattern(version)
  -- Match ## [version] - date through next ## heading or EOF.
  local escaped = version:gsub("(%W)", "%%%1")
  return "## %[" .. escaped .. "%]%s*%-[^\n]*\n"
end

function M.merge_changelog(existing_text, version, date, subjects)
  local text = ensure_header(existing_text)
  local section = M.build_version_section(version, date, subjects)
  local start_pos, end_heading = text:find(version_heading_pattern(version))
  if start_pos then
    local next_heading = text:find("\n## [", end_heading + 1, true)
    local before = text:sub(1, start_pos - 1)
    local after = ""
    if next_heading then
      after = text:sub(next_heading + 1)
    end
    return trim(before) .. "\n\n" .. trim(section) .. "\n\n" .. trim(after) .. "\n"
  end

  local unreleased = text:find("## %[Unreleased%]")
  if unreleased then
    local after_unreleased = text:find("\n## [", unreleased + 1, true)
    if after_unreleased then
      local before = text:sub(1, after_unreleased)
      local after = text:sub(after_unreleased + 1)
      return trim(before) .. "\n\n" .. trim(section) .. "\n\n" .. trim(after) .. "\n"
    end
    return trim(text) .. "\n\n" .. trim(section) .. "\n"
  end

  return trim(text) .. "\n\n" .. trim(section) .. "\n"
end

function M.extract_version_notes(changelog_text, version)
  if type(changelog_text) ~= "string" or type(version) ~= "string" then
    return nil
  end
  local start_pos, end_heading = changelog_text:find(version_heading_pattern(version))
  if not start_pos then
    return nil
  end
  local next_heading = changelog_text:find("\n## [", end_heading + 1, true)
  local body
  if next_heading then
    body = changelog_text:sub(end_heading + 1, next_heading)
  else
    body = changelog_text:sub(end_heading + 1)
  end
  body = trim(body)
  if body == "" then
    return nil
  end
  return body .. "\n"
end

return M
