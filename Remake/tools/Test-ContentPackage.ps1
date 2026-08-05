[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ContentRoot,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [switch]$VerifyAllHashes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath($ContentRoot).TrimEnd('\', '/')
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
$manifestFile = [IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Content root was not found: $root"
}
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw "Content manifest was not found: $manifestFile"
}
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding utf8 |
    ConvertFrom-Json
if ([int]$manifest.schema_version -ne 1) {
    throw "Unsupported content manifest schema: $($manifest.schema_version)"
}

$failures = [Collections.Generic.List[string]]::new()
$observedBytes = [int64]0
$observedFiles = 0
foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path).Replace('/', '\').TrimStart('\')
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $candidate.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add("Unsafe manifest path: $($entry.path)")
        continue
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $failures.Add("Missing file: $($entry.path)")
        continue
    }
    $file = Get-Item -LiteralPath $candidate
    $observedFiles++
    $observedBytes += [int64]$file.Length
    if ([int64]$file.Length -ne [int64]$entry.bytes) {
        $failures.Add("Length mismatch: $($entry.path)")
        continue
    }
    if ($VerifyAllHashes -or [bool]$entry.critical) {
        $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
        if ($actual -ne [string]$entry.sha256) {
            $failures.Add("SHA-256 mismatch: $($entry.path)")
        }
    }
}
if ($observedFiles -ne [int]$manifest.file_count) {
    $failures.Add(
        "File count mismatch: expected $($manifest.file_count), observed $observedFiles"
    )
}
if ($observedBytes -ne [int64]$manifest.total_bytes) {
    $failures.Add(
        "Byte count mismatch: expected $($manifest.total_bytes), observed $observedBytes"
    )
}
if ($failures.Count -gt 0) {
    throw "Content package validation failed:`n - $($failures -join "`n - ")"
}

[pscustomobject]@{
    Profile = [string]$manifest.profile_id
    Files = $observedFiles
    Bytes = $observedBytes
    HashMode = if ($VerifyAllHashes) { 'all' } else { 'critical' }
    Status = 'passed'
}
