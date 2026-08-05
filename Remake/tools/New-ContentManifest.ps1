[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ContentRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ProfileId = 'repository-mod-12-level-20260729',

    [string[]]$CriticalPaths = @(
        'asset-manifest.json',
        'levels/m000/level.json',
        'levels/m011/level.json'
    )
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath($ContentRoot).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Content root was not found: $root"
}
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
$output = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}

$criticalLookup = @{}
foreach ($relativePath in $CriticalPaths) {
    $normalized = ([string]$relativePath).Replace('\', '/').TrimStart('/')
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        $criticalLookup[$normalized.ToLowerInvariant()] = $true
    }
}

$entries = [Collections.Generic.List[object]]::new()
$totalBytes = [int64]0
$files = Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName
foreach ($file in $files) {
    $fullPath = [IO.Path]::GetFullPath($file.FullName)
    if (-not $fullPath.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Content file escaped its root: $fullPath"
    }
    $relative = $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $length = [int64]$file.Length
    $totalBytes += $length
    $entries.Add([ordered]@{
        path = $relative
        bytes = $length
        sha256 = $hash
        critical = $criticalLookup.ContainsKey($relative.ToLowerInvariant())
    })
}

$missingCritical = @(
    $criticalLookup.Keys | Where-Object {
        $key = $_
        -not ($entries | Where-Object {
            ([string]$_.path).ToLowerInvariant() -eq $key
        })
    }
)
if ($missingCritical.Count -gt 0) {
    throw "Critical content is missing: $($missingCritical -join ', ')"
}

$identityPayload = ($entries | ForEach-Object {
    '{0}|{1}|{2}' -f $_.path, $_.bytes, $_.sha256
}) -join "`n"
$identityBytes = [Text.Encoding]::UTF8.GetBytes($identityPayload)
# Windows PowerShell 5.1 runs on .NET Framework, which has SHA256.Create /
# ComputeHash but not the newer static SHA256.HashData or Convert.ToHexString
# APIs. Keep the release entrypoint compatible with both Windows PowerShell and
# PowerShell 7 because the playable-build helper intentionally supports either.
$identityAlgorithm = [Security.Cryptography.SHA256]::Create()
try {
    $identityHash = $identityAlgorithm.ComputeHash($identityBytes)
}
finally {
    $identityAlgorithm.Dispose()
}
$identity = [BitConverter]::ToString($identityHash).Replace('-', '').ToLowerInvariant()

$manifest = [ordered]@{
    schema_version = 1
    profile_id = $ProfileId
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    content_root_name = Split-Path -Leaf $root
    file_count = $entries.Count
    total_bytes = $totalBytes
    content_identity_sha256 = $identity
    files = $entries
}
$manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $output -Encoding utf8

[pscustomobject]@{
    Manifest = $output
    Profile = $ProfileId
    Files = $entries.Count
    Bytes = $totalBytes
    Identity = $identity
}
