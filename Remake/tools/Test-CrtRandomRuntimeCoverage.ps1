[CmdletBinding()]
param(
    [string]$CoveragePath = '',
    [string]$SdkCatalogPath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($CoveragePath)) {
    $CoveragePath = Join-Path $remakeRoot (
        'game\data\original_crt_random_runtime_coverage.json')
}
if ([string]::IsNullOrWhiteSpace($SdkCatalogPath)) {
    $SdkCatalogPath = Join-Path $repositoryRoot 'SDK\crt-rand-call-sites.json'
}
$CoveragePath = (Resolve-Path -LiteralPath $CoveragePath).Path
$SdkCatalogPath = (Resolve-Path -LiteralPath $SdkCatalogPath).Path
$coverage = Get-Content -LiteralPath $CoveragePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$sdk = Get-Content -LiteralPath $SdkCatalogPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($coverage.schema_version -ne 1 -or
    $coverage.coverage_id -ne 'original-crt-random-runtime-coverage-v1' -or
    $coverage.content_profile -ne 'repository-mod-12-level-20260729') {
    throw 'The original CRT random runtime coverage header is invalid.'
}
if ($sdk.schema_version -ne 1 -or
    $sdk.direct_call_site_count -ne 119 -or
    $sdk.supported_executable_sha256 -ne
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3') {
    throw 'The SDK CRT random call-site catalog header is invalid.'
}

$validStatuses = @(
    'exact_runtime',
    'checkpoint_exact',
    'partial_runtime',
    'unimplemented_runtime',
    'nonformal'
)
$coverageByCaller = @{}
foreach ($entry in @($coverage.callers)) {
    $callerRva = ([string]$entry.caller_rva).ToUpperInvariant()
    if ($coverageByCaller.ContainsKey($callerRva)) {
        throw "Duplicate coverage entry for caller $callerRva."
    }
    if ($callerRva -notmatch '^0X[0-9A-F]{8}$') {
        throw "Invalid caller RVA in coverage: $callerRva."
    }
    $coverageByCaller[$callerRva] = $entry
}

$sdkCallers = @($sdk.callers)
if ($coverageByCaller.Count -ne $sdkCallers.Count -or
    [int]$coverage.summary.caller_count -ne $sdkCallers.Count) {
    throw 'Coverage must contain exactly one entry for every SDK caller.'
}

$statusCounts = @{}
foreach ($status in $validStatuses) {
    $statusCounts[$status] = 0
}
$formalSiteCount = 0
$liveExactSiteCount = 0
$checkpointSiteCount = 0
$missingSiteCount = 0
$catalogSites = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)

foreach ($caller in $sdkCallers) {
    $callerRva = ([string]$caller.caller_rva).ToUpperInvariant()
    if (-not $coverageByCaller.ContainsKey($callerRva)) {
        throw "Missing coverage entry for SDK caller $callerRva."
    }
    $entry = $coverageByCaller[$callerRva]
    $status = [string]$entry.status
    if ($status -notin $validStatuses) {
        throw "Invalid coverage status '$status' for caller $callerRva."
    }
    $statusCounts[$status]++

    $sites = @(
        $caller.operations |
            ForEach-Object { @($_.sites) } |
            ForEach-Object { ([string]$_).ToUpperInvariant() }
    )
    foreach ($site in $sites) {
        if (-not $catalogSites.Add($site)) {
            throw "SDK call site $site is registered more than once."
        }
    }
    $missing = @($entry.missing_sites |
        ForEach-Object { ([string]$_).ToUpperInvariant() })
    if (@($missing | Select-Object -Unique).Count -ne $missing.Count) {
        throw "Caller $callerRva repeats a missing call site."
    }
    foreach ($site in $missing) {
        if ($site -notin $sites) {
            throw "Caller $callerRva claims foreign missing site $site."
        }
    }

    $isFormal = [bool]$caller.formal_missions
    switch ($status) {
        'nonformal' {
            if ($isFormal -or $missing.Count -ne 0) {
                throw "Caller $callerRva cannot be classified as nonformal."
            }
        }
        'unimplemented_runtime' {
            if (-not $isFormal -or
                $missing.Count -ne $sites.Count -or
                @($sites | Where-Object { $_ -notin $missing }).Count -ne 0 -or
                [string]::IsNullOrWhiteSpace([string]$entry.note)) {
                throw "Unimplemented caller $callerRva must list every site and a reason."
            }
        }
        'partial_runtime' {
            $hasTimingGap = -not [string]::IsNullOrWhiteSpace(
                [string]$entry.timing_gap)
            if (-not $isFormal -or
                ($missing.Count -le 0 -and -not $hasTimingGap) -or
                $missing.Count -ge $sites.Count) {
                throw (
                    "Partial caller $callerRva must list a strict subset of " +
                    'its sites or an explicit lifecycle timing gap.')
            }
        }
        default {
            if (-not $isFormal -or $missing.Count -ne 0) {
                throw "Completed caller $callerRva cannot contain missing sites."
            }
        }
    }

    $markers = @()
    if ($null -ne $entry.PSObject.Properties['implementation_markers']) {
        $markers = @(
            $entry.implementation_markers |
                Where-Object { $null -ne $_ }
        )
    }
    if ($status -in @('exact_runtime', 'checkpoint_exact', 'partial_runtime') -and
        $markers.Count -eq 0) {
        throw "Implemented caller $callerRva has no source marker."
    }
    foreach ($marker in $markers) {
        $markerPath = [IO.Path]::GetFullPath(
            (Join-Path $repositoryRoot ([string]$marker.path)))
        $rootPrefix = $repositoryRoot.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar) +
            [IO.Path]::DirectorySeparatorChar
        if (-not $markerPath.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
            throw "Coverage marker escapes the repository: $markerPath."
        }
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw "Coverage marker file does not exist: $markerPath."
        }
        $needle = [string]$marker.contains
        if ([string]::IsNullOrWhiteSpace($needle) -or
            -not (Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8).
                Contains($needle)) {
            throw "Coverage marker '$needle' is absent from $markerPath."
        }
    }

    if ($isFormal) {
        $formalSiteCount += $sites.Count
        $missingSiteCount += $missing.Count
        if ($status -eq 'checkpoint_exact') {
            $checkpointSiteCount += $sites.Count
        }
        else {
            $liveExactSiteCount += $sites.Count - $missing.Count
        }
    }
}

if ($catalogSites.Count -ne [int]$sdk.direct_call_site_count) {
    throw 'Flattened SDK call-site count disagrees with direct_call_site_count.'
}
$expectedSummary = [ordered]@{
    exact_runtime_callers = $statusCounts.exact_runtime
    checkpoint_exact_callers = $statusCounts.checkpoint_exact
    partial_runtime_callers = $statusCounts.partial_runtime
    unimplemented_runtime_callers = $statusCounts.unimplemented_runtime
    nonformal_callers = $statusCounts.nonformal
}
foreach ($pair in $expectedSummary.GetEnumerator()) {
    if ([int]$coverage.summary.($pair.Key) -ne [int]$pair.Value) {
        throw "Coverage summary field $($pair.Key) is stale."
    }
}

[pscustomobject]@{
    Coverage = $coverage.coverage_id
    Callers = $sdkCallers.Count
    DirectSites = $catalogSites.Count
    FormalSites = $formalSiteCount
    LiveConnectedFormalSites = $liveExactSiteCount
    CheckpointFormalSites = $checkpointSiteCount
    MissingFormalSites = $missingSiteCount
}
