[CmdletBinding()]
param(
    [switch]$RequireComplete
)

$ErrorActionPreference = 'Stop'
$remake = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repository = [IO.Path]::GetFullPath((Join-Path $remake '..'))
$mod = Join-Path $repository 'Mod'
$routesPath = Join-Path $repository 'SDK\mission-routes.json'
$missionsPath = Join-Path $remake 'game\data\missions.json'
$contractPath = Join-Path $remake 'game\data\mod_parity_contract.json'

$routes = (Get-Content -LiteralPath $routesPath -Raw -Encoding UTF8 |
    ConvertFrom-Json).routes
$selectorCatalog = Get-ChildItem -LiteralPath $mod -Filter '*.json' -File |
    ForEach-Object {
        try {
            $candidate = Get-Content -LiteralPath $_.FullName `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            if (@($candidate.missions).Count -eq 12 -and
                $null -ne $candidate.window_title) {
                $candidate
            }
        }
        catch {
            # Ignore unrelated runtime JSON.
        }
    } |
    Select-Object -First 1
if ($null -eq $selectorCatalog) {
    throw 'The stable Mod 12-level selector catalog was not found.'
}
$selector = $selectorCatalog.missions
$missions = (Get-Content -LiteralPath $missionsPath -Raw -Encoding UTF8 |
    ConvertFrom-Json).missions
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$expectedIds = @(0..11 | ForEach-Object { 'm{0:D3}' -f $_ })
$expectedMapNames = @(0..11 | ForEach-Object {
    '1937m{0:D3}.vwf' -f $_
})

foreach ($collection in @($routes, $selector, $missions, $contract.levels)) {
    if (@($collection).Count -ne 12) {
        throw 'Every route, selector, mission and parity collection must contain exactly 12 levels.'
    }
}
$actualMaps = @(Get-ChildItem -LiteralPath $mod -Filter '1937m*.vwf' -File |
    Sort-Object Name | Select-Object -ExpandProperty Name)
if ((Compare-Object $expectedMapNames $actualMaps).Count -ne 0) {
    throw (
        'Stable Mod VWF set must be exactly m000-m011. Actual: ' +
        ($actualMaps -join ', '))
}
if ($contract.authoritative_content_profile -ne
    'repository-mod-12-level-20260729') {
    throw 'The parity contract does not target the stable Mod content profile.'
}

for ($index = 0; $index -lt 12; $index++) {
    $number = $index + 1
    $id = $expectedIds[$index]
    $expectedVwf = $expectedMapNames[$index].ToUpperInvariant()
    $route = $routes[$index]
    $selectorMission = $selector[$index]
    $remakeMission = $missions[$index]
    $level = $contract.levels[$index]
    if ($route.selector_level -ne $number -or
        $route.engine_mission -ne $number -or
        $route.id -ne $id -or
        $route.vwf_name.ToUpperInvariant() -ne $expectedVwf -or
        $route.is_extension -or
        $selectorMission.number -ne $number -or
        $selectorMission.id -ne $id -or
        $remakeMission.number -ne $number -or
        $remakeMission.id -ne $id -or
        $level.number -ne $number -or
        $level.id -ne $id) {
        throw "Level identity mismatch at number $number."
    }
    if ($route.title -ne $selectorMission.title -or
        $route.title -ne $remakeMission.title -or
        $route.title -ne $level.title) {
        throw "Level title mismatch for $id."
    }
}

$allowedStatuses = @($contract.status_values)
$allTrackedItems = @($contract.feature_domains) + @($contract.levels)
foreach ($item in $allTrackedItems) {
    if ($allowedStatuses -notcontains $item.status) {
        throw "Invalid parity status '$($item.status)' for $($item.id)."
    }
    if ($item.status -eq 'verified' -and @($item.gaps).Count -ne 0) {
        throw "Verified parity item $($item.id) still declares gaps."
    }
}
$domainIds = @($contract.feature_domains.id)
if ($domainIds.Count -ne ($domainIds | Select-Object -Unique).Count) {
    throw 'Parity feature-domain ids must be unique.'
}

$remaining = @($allTrackedItems |
    Where-Object { $_.status -ne 'verified' })
if ($RequireComplete -and $remaining.Count -ne 0) {
    throw (
        "Complete parity gate failed; $($remaining.Count) items remain: " +
        (($remaining.id) -join ', '))
}

[pscustomobject]@{
    ContentProfile = $contract.authoritative_content_profile
    ModMaps = $actualMaps.Count
    Routes = @($routes).Count
    RemakeMissions = @($missions).Count
    FeatureDomains = @($contract.feature_domains).Count
    Verified = @($allTrackedItems |
        Where-Object { $_.status -eq 'verified' }).Count
    Remaining = $remaining.Count
    CompleteGate = if ($remaining.Count -eq 0) { 'passed' } else { 'open' }
}
