#!/usr/bin/env bash
# Build dist/<name>-<version>.aseprite-extension from the runtime allowlist.
# Bash counterpart of scripts/package.ps1; works in Git Bash, WSL, Linux, macOS.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
manifest="$repo_root/package.json"

if [ ! -f "$manifest" ]; then
  echo "package.sh: package.json not found at $manifest" >&2
  exit 1
fi

# Top-level manifest keys. The file order puts the top-level "name" first, so the
# first match is the extension name and not author.name.
manifest_field() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$manifest" |
    head -n 1 | tr -d '\r'
}

name="$(manifest_field name)"
version="$(manifest_field version)"
if [ -z "$name" ] || [ -z "$version" ]; then
  echo "package.sh: could not read name/version from $manifest" >&2
  exit 1
fi

dist="$repo_root/dist"
artifact="$dist/$name-$version.aseprite-extension"
zip_path="$dist/$name-$version.zip"

# Runtime files only: no tests/, docs/, scripts/, dist/, or .git/.
allowlist=(
  package.json
  main.lua
  assets/preview-top-64.png
  assets/preview-extruded-64-e16.png
  assets/border.png
  assets/heighthint.png
  src/atlas.lua
  src/bootstrap.lua
  src/dialog.lua
  src/document.lua
  src/errors.lua
  src/export.lua
  src/font.lua
  src/geometry.lua
  src/model.lua
  src/placement.lua
  src/placement_window.lua
  src/preview.lua
  src/preview_window.lua
  src/raster.lua
  src/seams.lua
  src/slice_data.lua
  src/slice_ref.lua
  src/variants.lua
)

# Native tools (bsdtar, python) need a Windows-style path on MSYS.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m -- "$1"
  else
    printf '%s' "$1"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Zip the given relative paths (cwd must be the staging directory). bsdtar needs
# --format=zip explicitly: the artifact extension is not a recognized suffix.
create_zip() {
  local dest="$1"
  shift
  if have zip; then
    zip -q -X -9 "$(native_path "$dest")" "$@"
  elif [ -x /c/Windows/System32/tar.exe ]; then
    /c/Windows/System32/tar.exe --format=zip -c -f "$(native_path "$dest")" "$@"
  elif have python3 || have python; then
    local py
    py="$(command -v python3 || command -v python)"
    "$py" - "$(native_path "$dest")" "$@" <<'PY'
import sys, zipfile

dest, names = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as archive:
    for name in names:
        archive.write(name, name)
PY
  elif tar --format=zip -cf /dev/null --files-from /dev/null 2>/dev/null; then
    tar --format=zip -c -f "$(native_path "$dest")" "$@"
  else
    echo "package.sh: no zip-capable tool found (need zip, bsdtar, or python)" >&2
    return 1
  fi
}

list_zip() {
  local archive="$1"
  if have unzip; then
    unzip -Z1 "$archive"
  else
    local py
    py="$(command -v python3 || command -v python)"
    "$py" - "$(native_path "$archive")" <<'PY'
import sys, zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    for info in archive.infolist():
        if not info.is_dir():
            print(info.filename.replace("\\", "/"))
PY
  fi
}

stage="$(mktemp -d "${TMPDIR:-/tmp}/isometric-dual-grid-XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

for relative in "${allowlist[@]}"; do
  source="$repo_root/$relative"
  if [ ! -f "$source" ]; then
    echo "package.sh: runtime file missing: $relative" >&2
    exit 1
  fi
  mkdir -p -- "$stage/$(dirname -- "$relative")"
  cp -p -- "$source" "$stage/$relative"
done

mkdir -p -- "$dist"
rm -f -- "$zip_path" "$artifact"

(
  cd -- "$stage"
  create_zip "$zip_path" "${allowlist[@]}"
)
mv -f -- "$zip_path" "$artifact"

# Verify the archive carries exactly the runtime allowlist.
expected="$(printf '%s\n' "${allowlist[@]}" | LC_ALL=C sort)"
actual="$(list_zip "$artifact" | tr -d '\r' | LC_ALL=C sort)"
if [ "$expected" != "$actual" ]; then
  echo "package.sh: package entries differ from the runtime allowlist." >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
  rm -f -- "$artifact"
  exit 1
fi

bytes="$(wc -c < "$artifact" | tr -d '[:space:]')"
echo "PACKAGE=$artifact"
echo "BYTES=$bytes"
