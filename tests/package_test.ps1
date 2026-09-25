param(
  [string]$Artifact
)

if ([string]::IsNullOrWhiteSpace($Artifact)) {
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\package.json') |
    ConvertFrom-Json
  $Artifact = Join-Path $PSScriptRoot (
    "..\dist\{0}-{1}.aseprite-extension" -f $manifest.name, $manifest.version)
}

$expected = @(
  'assets/preview-extruded-64-e16.png',
  'assets/preview-top-64.png',
  'assets/border.png',
  'assets/heighthint.png',
  'assets/transparent_mask.png',
  'assets/opaque_mask.png',
  'assets/interlaced_mask.png',
  'main.lua',
  'package.json',
  'src/atlas.lua',
  'src/bootstrap.lua',
  'src/dialog.lua',
  'src/document.lua',
  'src/errors.lua',
  'src/export.lua',
  'src/font.lua',
  'src/geometry.lua',
  'src/model.lua',
  'src/placement.lua',
  'src/placement_window.lua',
  'src/preview.lua',
  'src/preview_window.lua',
  'src/raster.lua',
  'src/side_copy.lua',
  'src/side_copy_data.lua',
  'src/seams.lua',
  'src/slice_data.lua',
  'src/slice_ref.lua',
  'src/variants.lua'
) | Sort-Object

if (-not (Test-Path -LiteralPath $Artifact)) {
  throw "Package artifact missing: $Artifact"
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead(
  (Resolve-Path -LiteralPath $Artifact).Path)
try {
  $actual = $archive.Entries |
    Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
    ForEach-Object { $_.FullName.Replace('\', '/') } |
    Sort-Object
} finally {
  $archive.Dispose()
}
$difference = Compare-Object -ReferenceObject $expected -DifferenceObject $actual
if ($difference) {
  $difference | Format-Table | Out-String | Write-Error
  throw 'Package entries differ from the runtime allowlist.'
}
