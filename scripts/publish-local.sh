#!/usr/bin/env bash
# Copy the subject addon into a local Forever AddOns folder for in-game testing.
#
# Usage:
#   ./scripts/publish-local.sh
#   ./scripts/publish-local.sh --destination "/path/to/Interface/AddOns"
#   ./scripts/publish-local.sh --skip-tests --dry-run
set -euo pipefail

DESTINATION=""
SKIP_TESTS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--destination)
      DESTINATION="${2:-}"
      [[ -n "$DESTINATION" ]] || { echo "--destination requires a path" >&2; exit 1; }
      shift 2
      ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --dry-run|--what-if) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/subject"

# Read Config.VERSION for local TOC substitution (packager uses @project-version@ at release).
get_config_version() {
  local config_path="$1"
  if [[ ! -f "$config_path" ]]; then
    return 1
  fi
  local version
  version="$(sed -nE 's/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$config_path" | head -n 1)"
  if [[ -z "$version" ]]; then
    return 1
  fi
  printf '%s\n' "$version"
}

# Replace packager placeholders in the published TOC so AddOn List shows a real version.
set_published_toc_version() {
  local toc_path="$1"
  local version="$2"
  if [[ -z "$version" ]]; then
    echo "Could not resolve Config.VERSION for TOC substitution." >&2
    exit 1
  fi
  if ! grep -q '@project-version@' "$toc_path"; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  sed "s/@project-version@/${version}/g" "$toc_path" > "$tmp"
  mv "$tmp" "$toc_path"
  echo "    TOC Version -> $version"
}

normalize_addons_dir() {
  local p="${1%/}"
  if [[ "$(basename "$p")" == "subject" ]]; then
    dirname "$p"
  else
    printf '%s\n' "$p"
  fi
}

resolve_forever_addons_dir() {
  local explicit="$1"
  if [[ -n "$explicit" ]]; then
    normalize_addons_dir "$explicit"
    return 0
  fi

  if [[ -n "${SUBJECT_FOREVER_ADDONS:-}" ]]; then
    normalize_addons_dir "$SUBJECT_FOREVER_ADDONS"
    return 0
  fi

  local local_file="$SCRIPT_DIR/forever-addons.path"
  if [[ -f "$local_file" ]]; then
    local path_line=""
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      local line
      line="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$line" || "$line" == \#* ]] && continue
      path_line="$line"
      break
    done < "$local_file"
    if [[ -n "$path_line" ]]; then
      normalize_addons_dir "$path_line"
      return 0
    fi
  fi

  local candidates=(
    "/d/World of Warcraft/_forever_/Interface/AddOns"
    "/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
    "/c/Program Files/World of Warcraft/_forever_/Interface/AddOns"
    "D:/World of Warcraft/_forever_/Interface/AddOns"
    "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
    "C:/Program Files/World of Warcraft/_forever_/Interface/AddOns"
    "$HOME/Games/World of Warcraft/_forever_/Interface/AddOns"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

if [[ ! -f "$SOURCE/subject.toc" ]]; then
  echo "Missing addon source at $SOURCE (expected subject.toc)." >&2
  exit 1
fi

if [[ $SKIP_TESTS -eq 0 ]]; then
  if ! command -v lua >/dev/null 2>&1; then
    echo "lua not found on PATH. Install a Lua interpreter or pass --skip-tests." >&2
    exit 1
  fi
  echo "==> Running tests"
  lua "$REPO_ROOT/tests/test_subject.lua"
fi

if ! ADDONS_DIR="$(resolve_forever_addons_dir "$DESTINATION")"; then
  cat >&2 <<'EOF'
Could not find Forever AddOns folder.
Pass --destination, set SUBJECT_FOREVER_ADDONS, or create scripts/forever-addons.path
with one line, e.g.:
  D:\World of Warcraft\_forever_\Interface\AddOns
EOF
  exit 1
fi

if [[ ! -d "$ADDONS_DIR" ]]; then
  echo "AddOns directory does not exist: $ADDONS_DIR" >&2
  exit 1
fi

TARGET="$ADDONS_DIR/subject"
echo "==> Publishing $SOURCE"
echo "    -> $TARGET"

if ! VERSION="$(get_config_version "$SOURCE/Config.lua")"; then
  echo "Could not resolve Config.VERSION from $SOURCE/Config.lua." >&2
  exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry-run: would replace target with source contents and set TOC Version to $VERSION."
  exit 0
fi

rm -rf "$TARGET"
mkdir -p "$TARGET"
# Copy contents (not the subject directory itself as an extra nesting level).
cp -a "$SOURCE"/. "$TARGET"/

if [[ ! -f "$TARGET/subject.toc" ]]; then
  echo "Publish failed: missing $TARGET/subject.toc" >&2
  exit 1
fi

set_published_toc_version "$TARGET/subject.toc" "$VERSION"

echo "==> Done. Reload the Forever client (/reload) or restart to load changes."
