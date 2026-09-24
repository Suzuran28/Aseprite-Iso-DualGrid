param([string]$Aseprite = $env:ASEPRITE_BIN)

if ([string]::IsNullOrWhiteSpace($Aseprite)) {
  $Aseprite = Join-Path $env:ProgramFiles 'Aseprite\Aseprite.exe'
}
if (-not (Test-Path -LiteralPath $Aseprite)) {
  throw "Aseprite executable not found. Pass -Aseprite or set ASEPRITE_BIN."
}

$runner = (Resolve-Path '.\tests\run.lua').Path
$testStdoutLog = $null
$testStderrLog = $null
try {
  $testStdoutLog = New-TemporaryFile -ErrorAction Stop
  $testStderrLog = New-TemporaryFile -ErrorAction Stop
  $testProcess = Start-Process -FilePath $Aseprite `
    -ArgumentList @('-b', '--script', $runner) `
    -Wait -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $testStdoutLog.FullName `
    -RedirectStandardError $testStderrLog.FullName -ErrorAction Stop
  Get-Content -LiteralPath $testStdoutLog.FullName -Raw
  Get-Content -LiteralPath $testStderrLog.FullName -Raw
  $testExitCode = $testProcess.ExitCode
} finally {
  if ($null -ne $testStdoutLog) {
    Remove-Item -LiteralPath $testStdoutLog.FullName -ErrorAction SilentlyContinue
  }
  if ($null -ne $testStderrLog) {
    Remove-Item -LiteralPath $testStderrLog.FullName -ErrorAction SilentlyContinue
  }
}
exit $testExitCode
