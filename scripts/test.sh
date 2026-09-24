#!/usr/bin/env bash
# Run the Aseprite batch test suite (tests/run.lua).
# Bash counterpart of scripts/test.ps1; works in Git Bash, WSL, Linux, macOS.
#
# Usage:
#   scripts/test.sh [--aseprite /path/to/aseprite]
# The ASEPRITE_BIN environment variable is used when no flag is given.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

aseprite="${ASEPRITE_BIN:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --aseprite) aseprite="${2:-}"; shift 2 ;;
    --aseprite=*) aseprite="${1#--aseprite=}"; shift ;;
    -h|--help)
      echo "usage: scripts/test.sh [--aseprite /path/to/aseprite]"
      exit 0
      ;;
    *) echo "test.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$aseprite" ]; then
  candidates=(
    "${PROGRAMFILES:-C:/Program Files}/Aseprite/Aseprite.exe"
    "/c/Program Files/Aseprite/Aseprite.exe"
    "/c/Program Files (x86)/Aseprite/Aseprite.exe"
    "$HOME/.local/share/Steam/steamapps/common/Aseprite/aseprite"
    "/Applications/Aseprite.app/Contents/MacOS/aseprite"
  )
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      aseprite="$candidate"
      break
    fi
  done
fi

if [ -z "$aseprite" ] || [ ! -x "$aseprite" ]; then
  echo "test.sh: Aseprite executable not found. Pass --aseprite or set ASEPRITE_BIN." >&2
  exit 1
fi

runner="$repo_root/tests/run.lua"
if [ ! -f "$runner" ]; then
  echo "test.sh: test runner missing: $runner" >&2
  exit 1
fi

# Aseprite is a native binary: it needs a Windows-style path on MSYS.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m -- "$1"
  else
    printf '%s' "$1"
  fi
}

status=0
"$aseprite" -b --script "$(native_path "$runner")" || status=$?
if [ "$status" -ne 0 ]; then
  echo "test.sh: Aseprite batch suite failed with exit code $status" >&2
fi
exit "$status"
