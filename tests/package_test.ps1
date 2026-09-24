param(
  [string]$Artifact = '.\dist\isometric-dual-grid-0.1.0.aseprite-extension'
)

$expected = @(
  'assets/preview-extruded-64-e16.png',
  'assets/preview-top-64.png',
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
  'src/preview.lua',
  'src/preview_window.lua',
  'src/raster.lua',
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
