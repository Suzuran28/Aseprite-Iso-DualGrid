$repoRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'package.json') |
  ConvertFrom-Json
$dist = Join-Path $repoRoot 'dist'
$artifact = Join-Path $dist ("{0}-{1}.aseprite-extension" -f
  $manifest.name, $manifest.version)
$zipPath = Join-Path $dist ("{0}-{1}.zip" -f
  $manifest.name, $manifest.version)
$stage = Join-Path ([System.IO.Path]::GetTempPath()) (
  'isometric-dual-grid-' + [guid]::NewGuid().ToString('N'))
$allowlist = @(
  'package.json','main.lua','assets/preview-top-64.png',
  'assets/preview-extruded-64-e16.png','assets/border.png',
  'assets/heighthint.png','assets/transparent_mask.png',
  'assets/opaque_mask.png','assets/interlaced_mask.png',
  'src/side_copy.lua','src/side_copy_data.lua','src/atlas.lua','src/bootstrap.lua',
  'src/dialog.lua','src/document.lua','src/errors.lua','src/export.lua',
  'src/font.lua','src/geometry.lua','src/model.lua','src/placement.lua',
  'src/placement_window.lua','src/preview.lua','src/preview_window.lua',
  'src/raster.lua','src/seams.lua',
  'src/slice_data.lua',
  'src/slice_ref.lua','src/variants.lua'
)

try {
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  foreach ($relative in $allowlist) {
    $source = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $source)) {
      throw "Runtime file missing: $relative"
    }
    $target = Join-Path $stage $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) |
      Out-Null
    Copy-Item -LiteralPath $source -Destination $target
  }
  New-Item -ItemType Directory -Force -Path $dist | Out-Null
  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }
  if (Test-Path -LiteralPath $artifact) {
    Remove-Item -LiteralPath $artifact -Force
  }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath
  Move-Item -LiteralPath $zipPath -Destination $artifact
} finally {
  $tempRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::GetTempPath())
  $stageFull = [System.IO.Path]::GetFullPath($stage)
  if ($stageFull.StartsWith($tempRoot,
      [System.StringComparison]::OrdinalIgnoreCase) -and
      (Test-Path -LiteralPath $stageFull)) {
    Remove-Item -LiteralPath $stageFull -Recurse -Force
  }
}

$item = Get-Item -LiteralPath $artifact
"PACKAGE=$($item.FullName)"
"BYTES=$($item.Length)"
