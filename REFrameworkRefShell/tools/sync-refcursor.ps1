# Copy the built ref_cursor plugin into this package.
# Source of truth for C++: REFramework/examples/ref_cursor/plugin.cpp

param(
    [string]$From
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $here "reframework\plugins\ref_cursor.dll"

$candidates = @()
if ($From) {
    $candidates += $From
}

$devRoot = Split-Path -Parent (Split-Path -Parent $here)
$refRoot = Join-Path $devRoot "REFramework"
$candidates += @(
    (Join-Path $refRoot "build64_all\bin\REFramework\ref_cursor.dll"),
    (Join-Path $refRoot "build64_all\bin\ref_cursor\ref_cursor.dll")
)

$src = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $src) {
    throw "ref_cursor.dll not found. Build the ref_cursor target in REFramework, or pass -From <path>."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
Copy-Item -Force $src $dest
Get-Item $dest | Format-List FullName, Length, LastWriteTime
