[CmdletBinding()]
param(
    [string]$CatalogPath = '',
    [string]$ProjectileProfilesPath = '',
    [string]$CrtCoveragePath = ''
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $repositoryRoot (
        'SDK\dynamic-actor-lifecycle-sites.json')
}
if ([string]::IsNullOrWhiteSpace($ProjectileProfilesPath)) {
    $ProjectileProfilesPath = Join-Path $remakeRoot (
        'game\data\projectile_profiles.json')
}
if ([string]::IsNullOrWhiteSpace($CrtCoveragePath)) {
    $CrtCoveragePath = Join-Path $remakeRoot (
        'game\data\original_crt_random_runtime_coverage.json')
}
$CatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$ProjectileProfilesPath = (
    Resolve-Path -LiteralPath $ProjectileProfilesPath).Path
$CrtCoveragePath = (Resolve-Path -LiteralPath $CrtCoveragePath).Path
$addressCatalogPath = Join-Path $repositoryRoot 'SDK\address-catalog.json'

function ConvertTo-NormalizedRva {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value -notmatch '^0x[0-9A-Fa-f]{8}$') {
        throw "Invalid lifecycle RVA: $Value"
    }
    return $Value.ToUpperInvariant()
}

function Assert-ExactSet {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Expected,
        [Parameter(Mandatory = $true)]
        [object[]]$Actual,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $difference = @(Compare-Object `
        @($Expected | Sort-Object -Unique) `
        @($Actual | Sort-Object -Unique))
    if ($difference.Count -ne 0 -or
        @($Expected).Count -ne @($Actual).Count) {
        throw "$Description changed: $($difference | Out-String)"
    }
}

function Assert-ImplementationMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Markers,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if ($Markers.Count -eq 0) {
        throw "$Description has no implementation marker."
    }
    $repositoryPrefix = $repositoryRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    foreach ($marker in $Markers) {
        $markerPath = [IO.Path]::GetFullPath((Join-Path `
            $repositoryRoot `
            ([string]$marker.path)))
        if (-not $markerPath.StartsWith(
            $repositoryPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Description marker escapes the repository: $markerPath"
        }
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw "$Description marker file is missing: $markerPath"
        }
        $needle = [string]$marker.contains
        if ([string]::IsNullOrWhiteSpace($needle) -or
            -not (Get-Content -LiteralPath $markerPath `
                -Raw -Encoding UTF8).Contains($needle)) {
            throw "$Description marker '$needle' is absent from $markerPath"
        }
    }
}

$catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$profiles = Get-Content -LiteralPath $ProjectileProfilesPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$crtCoverage = Get-Content -LiteralPath $CrtCoveragePath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$addressCatalog = Get-Content -LiteralPath $addressCatalogPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json

if ([int]$catalog.schema_version -ne 1 -or
    [string]$catalog.catalog_id -ne
        'm1937-dynamic-actor-lifecycle-sites-v1' -or
    [string]$catalog.address_kind -ne
        'rva_from_loaded_M1937_exe_base' -or
    [string]$catalog.supported_executable_sha256 -ne
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3' -or
    [string]$catalog.content_profile -ne
        'repository-mod-12-level-20260729') {
    throw 'Dynamic actor lifecycle catalog header is invalid.'
}

$addressByName = @{}
foreach ($address in @($addressCatalog.addresses)) {
    $addressByName[[string]$address.name] = ConvertTo-NormalizedRva (
        [string]$address.rva)
}
if ($addressByName.CreateWorldActor -ne
        (ConvertTo-NormalizedRva `
            ([string]$catalog.functions.create_world_actor_rva)) -or
    $addressByName.RemoveWorldActor -ne
        (ConvertTo-NormalizedRva `
            ([string]$catalog.functions.remove_world_actor_rva)) -or
    $addressByName.EffectDispatch -ne
        (ConvertTo-NormalizedRva `
            ([string]$catalog.functions.effect_dispatch_rva)) -or
    [int]$catalog.functions.successful_factory_crt_draws -ne 4 -or
    [int]$catalog.functions.successful_removal_crt_draws -ne 4) {
    throw 'Lifecycle function identities disagree with SDK address catalog.'
}

$expectedFactorySites = @(
    '0X0004EC19', '0X00050003', '0X00050160', '0X000502FE',
    '0X00056D5C', '0X0005783C', '0X00057982', '0X00058428',
    '0X0005992C', '0X0005E383', '0X0005E449', '0X000632C2',
    '0X0006371E', '0X000638D6', '0X00063F8C', '0X00064082',
    '0X0006420E', '0X00064991', '0X00064A14'
)
$expectedRemovalSites = @(
    '0X0005032B', '0X00056C7C', '0X0005C85C', '0X00063213',
    '0X00063AF5', '0X00063BA2', '0X00063C95', '0X00063CF1',
    '0X00063DDF', '0X00063F27', '0X00064002', '0X00064047',
    '0X000640D2', '0X000641AA', '0X00064279', '0X0006433E',
    '0X000643F8', '0X000644ED', '0X000646EB', '0X00064AF6'
)
$factorySites = @($catalog.factory_sites)
$removalSites = @($catalog.removal_sites)
Assert-ExactSet `
    -Expected $expectedFactorySites `
    -Actual @($factorySites | ForEach-Object {
        ConvertTo-NormalizedRva ([string]$_.site_rva)
    }) `
    -Description 'Direct sub_44A350 factory call-site set'
Assert-ExactSet `
    -Expected $expectedRemovalSites `
    -Actual @($removalSites | ForEach-Object {
        ConvertTo-NormalizedRva ([string]$_.site_rva)
    }) `
    -Description 'Direct sub_449DA0 removal call-site set'

$factoryClassifications = @(
    'formal_startup_checkpoint',
    'formal_runtime',
    'formal_runtime_mixed',
    'nonformal_dormant'
)
$removalClassifications = @(
    'formal_runtime',
    'checkpoint_boundary_cleanup',
    'native_failure_guard',
    'nonformal_dormant'
)
foreach ($site in $factorySites) {
    $siteRva = ConvertTo-NormalizedRva ([string]$site.site_rva)
    ConvertTo-NormalizedRva ([string]$site.caller_rva) | Out-Null
    if ([string]$site.classification -notin $factoryClassifications -or
        [string]::IsNullOrWhiteSpace([string]$site.semantic)) {
        throw "Factory site $siteRva has an invalid classification."
    }
    if ([string]$site.classification -in @(
        'formal_startup_checkpoint',
        'formal_runtime',
        'formal_runtime_mixed')) {
        Assert-ImplementationMarkers `
            -Markers @($site.implementation_markers) `
            -Description "Factory site $siteRva"
    }
}
foreach ($site in $removalSites) {
    $siteRva = ConvertTo-NormalizedRva ([string]$site.site_rva)
    ConvertTo-NormalizedRva ([string]$site.caller_rva) | Out-Null
    if ([string]$site.classification -notin $removalClassifications -or
        [string]::IsNullOrWhiteSpace([string]$site.semantic)) {
        throw "Removal site $siteRva has an invalid classification."
    }
    if ([string]$site.classification -eq 'formal_runtime') {
        Assert-ImplementationMarkers `
            -Markers @($site.implementation_markers) `
            -Description "Removal site $siteRva"
    }
}
Assert-ImplementationMarkers `
    -Markers @($catalog.checkpoint_model.implementation_markers) `
    -Description 'Checkpoint-neutral manager cleanup model'

$factoryStartupCount = @($factorySites | Where-Object {
    [string]$_.classification -eq 'formal_startup_checkpoint'
}).Count
$factoryRuntimeCount = @($factorySites | Where-Object {
    [string]$_.classification -in @(
        'formal_runtime', 'formal_runtime_mixed')
}).Count
$factoryNonformalCount = @($factorySites | Where-Object {
    [string]$_.classification -eq 'nonformal_dormant'
}).Count
$removalRuntimeCount = @($removalSites | Where-Object {
    [string]$_.classification -eq 'formal_runtime'
}).Count
$removalCheckpointCount = @($removalSites | Where-Object {
    [string]$_.classification -eq 'checkpoint_boundary_cleanup'
}).Count
$removalFailureCount = @($removalSites | Where-Object {
    [string]$_.classification -eq 'native_failure_guard'
}).Count
$removalNonformalCount = @($removalSites | Where-Object {
    [string]$_.classification -eq 'nonformal_dormant'
}).Count
$summary = $catalog.summary
if ([int]$summary.factory_site_count -ne $factorySites.Count -or
    [int]$summary.factory_formal_startup_checkpoint_site_count -ne
        $factoryStartupCount -or
    [int]$summary.factory_formal_runtime_site_count -ne
        $factoryRuntimeCount -or
    [int]$summary.factory_nonformal_site_count -ne
        $factoryNonformalCount -or
    [int]$summary.removal_site_count -ne $removalSites.Count -or
    [int]$summary.removal_formal_runtime_exact_site_count -ne
        $removalRuntimeCount -or
    [int]$summary.removal_checkpoint_boundary_site_count -ne
        $removalCheckpointCount -or
    [int]$summary.removal_native_failure_guard_site_count -ne
        $removalFailureCount -or
    [int]$summary.removal_nonformal_site_count -ne
        $removalNonformalCount -or
    [int]$summary.formal_in_level_unimplemented_site_count -ne 0) {
    throw 'Dynamic actor lifecycle summary is stale.'
}

$proof = $catalog.mode_2_nonformal_proof
Assert-ExactSet `
    -Expected @(1, 2, 4, 5, 8, 10, 11, 12, 13, 14, 15) `
    -Actual @($proof.formal_effect_types_union | ForEach-Object { [int]$_ }) `
    -Description 'Formal effect-dispatch type set'
Assert-ExactSet `
    -Expected @(3, 6, 7, 9) `
    -Actual @($proof.unreferenced_effect_types | ForEach-Object { [int]$_ }) `
    -Description 'Unreferenced effect-dispatch type set'
Assert-ExactSet `
    -Expected @('0X0004CDB0', '0X00056DF0') `
    -Actual @($proof.effect_dispatch_direct_caller_rvas | ForEach-Object {
        ConvertTo-NormalizedRva ([string]$_)
    }) `
    -Description 'Effect-dispatch direct caller set'
Assert-ExactSet `
    -Expected @('0X0006371E', '0X000638D6') `
    -Actual @($proof.route_clone_factory_site_rvas | ForEach-Object {
        ConvertTo-NormalizedRva ([string]$_)
    }) `
    -Description 'Mode-2 route-clone factory site set'

$formalProfiles = @($profiles.projectiles.PSObject.Properties |
    ForEach-Object { $_.Value })
$formalModes = @($formalProfiles | ForEach-Object {
    [int]$_.delivery_mode
})
$formalEffects = @($formalProfiles | ForEach-Object {
    [int]$_.original_effect_type
})
if ([int]$proof.delivery_mode -ne 2 -or
    [int]$proof.effect_type -ne 3 -or
    [int]$proof.initial_runtime_actor_type -ne 58 -or
    [int]$proof.formal_projectile_profile_count -ne
        $formalProfiles.Count -or
    $formalProfiles.Count -ne 6 -or
    $formalModes -contains 2 -or
    $formalEffects -contains 3 -or
    [bool]$proof.formal_projectile_profile_has_mode_2) {
    throw 'Mode-2 nonformal proof disagrees with formal projectile profiles.'
}

if ([string]$crtCoverage.dynamic_actor_lifecycle_catalog -ne
        'SDK/dynamic-actor-lifecycle-sites.json') {
    throw 'CRT runtime coverage does not route to the lifecycle catalog.'
}
$staleTimingGap = @($crtCoverage.callers | Where-Object {
    ([string]$_.timing_gap).Contains('mission actor-101') -or
    ([string]$_.timing_gap).Contains('mission actor 101')
})
if ($staleTimingGap.Count -ne 0) {
    throw 'CRT runtime coverage still claims actor 101 is unimplemented.'
}

Write-Host ((
    'Dynamic actor lifecycle coverage passed: {0} factory sites, {1} ' +
    'removal sites, {2} exact formal in-level sites, 0 unimplemented.') -f
    $factorySites.Count,
    $removalSites.Count,
    ($factoryRuntimeCount + $removalRuntimeCount))
