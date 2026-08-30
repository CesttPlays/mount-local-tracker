#Requires -Version 5
<#
    Offline test suites for the addon (mirrors .github/workflows/ci.yml):

      * luacheck            static analysis (skipped if luacheck is not on PATH)
      * tests/run.py        headless smoke tests (addon loads + full lifecycle)
      * tests/test_*.py     generator unit tests, MountData/Overrides structure, TOC

    NOT a substitute for an in-game /reload. Usage:  .\run-tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$failed = @()

# Find a Python launcher.
$py = $null
foreach ($c in @("py", "python", "python3")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break }
}
if (-not $py) { throw "Python not found on PATH." }

# Ensure lupa (bundled Lua) is importable; install to --user if not.
& $py -c "import lupa" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing lupa (bundled Lua interpreter)..." -ForegroundColor Cyan
    & $py -m pip install --user --quiet lupa
    if ($LASTEXITCODE -ne 0) { throw "pip install lupa failed." }
}

if (Get-Command luacheck -ErrorAction SilentlyContinue) {
    Write-Host "`n== luacheck ==" -ForegroundColor Cyan
    & luacheck .
    if ($LASTEXITCODE -ne 0) { $failed += "luacheck" }
} else {
    Write-Host "`n== luacheck (skipped: not on PATH) ==" -ForegroundColor Yellow
}

Write-Host "`n== headless smoke tests ==" -ForegroundColor Cyan
& $py (Join-Path $root "tests/run.py")
if ($LASTEXITCODE -ne 0) { $failed += "smoke" }

Write-Host "`n== generator + mount-data + TOC ==" -ForegroundColor Cyan
& $py -m unittest discover -s (Join-Path $root "tests") -p "test_*.py" -v
if ($LASTEXITCODE -ne 0) { $failed += "unittest" }

if ($failed.Count -gt 0) {
    Write-Host "`nFAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll suites passed." -ForegroundColor Green
exit 0
