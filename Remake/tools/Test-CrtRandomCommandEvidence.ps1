[CmdletBinding()]
param(
    [string]$EvidencePath = '',
    [string]$SdkCatalogPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidencePath = Join-Path $remakeRoot (
        'game\data\original_crt_random_command_evidence.json')
}
if ([string]::IsNullOrWhiteSpace($SdkCatalogPath)) {
    $SdkCatalogPath = Join-Path $repositoryRoot 'SDK\crt-rand-call-sites.json'
}
$EvidencePath = (Resolve-Path -LiteralPath $EvidencePath).Path
$SdkCatalogPath = (Resolve-Path -LiteralPath $SdkCatalogPath).Path
$evidence = Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$sdk = Get-Content -LiteralPath $SdkCatalogPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($evidence.schema_version -ne 1 -or
    $evidence.catalog_id -ne 'original-crt-random-command-evidence-v1' -or
    $evidence.content_profile -ne 'repository-mod-12-level-20260729') {
    throw 'The original CRT random command-evidence header is invalid.'
}
if ($evidence.input_isolation -ne
    'target-window messages and process-local DirectInput only; no global cursor APIs') {
    throw 'Command evidence must retain its process-local input-isolation statement.'
}
if ([string]$evidence.scope -notmatch 'not playthroughs') {
    throw 'Command evidence must state that short probes are not playthroughs.'
}

$expectedFamilySites = @{
    selected = @{
        '2' = '0x0005D64F'
        '8' = '0x0005D67C'
        '9' = '0x0005D6A9'
        '10' = '0x0005D6D6'
        '91' = '0x0005D6D6'
    }
    acknowledge = @{
        '1' = '0x0005D7CF'
        '2' = '0x0005D7F8'
        '8' = '0x0005D821'
        '10' = '0x0005D855'
        '91' = '0x0005D855'
    }
}
foreach ($family in $expectedFamilySites.Keys) {
    $actualFamily = $evidence.call_site_families.$family
    $actualProperties = @($actualFamily.PSObject.Properties)
    if ($actualProperties.Count -ne $expectedFamilySites[$family].Count) {
        throw "Unexpected $family call-site family size."
    }
    foreach ($runtimeType in $expectedFamilySites[$family].Keys) {
        $property = $actualFamily.PSObject.Properties[$runtimeType]
        if ($null -eq $property -or
            [string]$property.Value -ne $expectedFamilySites[$family][$runtimeType]) {
            throw "Incorrect $family call site for runtime type $runtimeType."
        }
    }
}

$expectedDynamicConstructorSites = @(
    '0x00050967',
    '0x00050980',
    '0x0005340B',
    '0x0005358B'
)
$actualDynamicConstructorSites = @(
    $evidence.call_site_families.dynamic_constructor)
if ($actualDynamicConstructorSites.Count -ne
        $expectedDynamicConstructorSites.Count) {
    throw 'Unexpected dynamic-constructor call-site family size.'
}
for ($index = 0; $index -lt $expectedDynamicConstructorSites.Count; $index++) {
    if ([string]$actualDynamicConstructorSites[$index] -ne
        $expectedDynamicConstructorSites[$index]) {
        throw "Incorrect dynamic-constructor call site at index $index."
    }
}
if ([string]$evidence.call_site_families.saved_actor_facing -ne
    '0x0005BBBC') {
    throw 'The saved-actor facing call site changed unexpectedly.'
}

$sdkSites = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($caller in @($sdk.callers)) {
    foreach ($operation in @($caller.operations)) {
        foreach ($site in @($operation.sites)) {
            [void]$sdkSites.Add([string]$site)
        }
    }
}

$expectedScenarios = @{
    'm000-pistol-attack-inventory-v1' = @{
        level = 'm000'; action = 'pistol_attack'; records = 2
    }
    'm001-mine-pickup-inventory-v1' = @{
        level = 'm001'; action = 'world_item_pickup'; records = 3
    }
    'm010-burial-command-v1' = @{
        level = 'm010'; action = 'prepare_corpse_then_bury'; records = 4
    }
    'm010-sight-direct-target-v1' = @{
        level = 'm010'; action = 'sight_direct_target'; records = 0
    }
    'm010-cigarette-drop-inventory-v1' = @{
        level = 'm010'; action = 'backpack_item_drop'; records = 1
    }
    'm000-save-load-random-v1' = @{
        level = 'm000'; action = 'save_then_load'; records = 0
    }
}
$scenarios = @($evidence.scenarios)
if ($scenarios.Count -ne $expectedScenarios.Count) {
    throw 'Command evidence must contain exactly six short scenarios.'
}

$identityCache = @{}
$seenScenarios = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
$seenRecords = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
$familyCounts = @{ selected = 0; acknowledge = 0 }
$recordCount = 0
foreach ($scenario in $scenarios) {
    $scenarioId = [string]$scenario.scenario_id
    if (-not $seenScenarios.Add($scenarioId) -or
        -not $expectedScenarios.ContainsKey($scenarioId)) {
        throw "Unexpected or duplicate command scenario '$scenarioId'."
    }
    $expected = $expectedScenarios[$scenarioId]
    $levelId = [string]$scenario.level_id
    $records = @($scenario.records)
    if ($levelId -ne $expected.level -or
        [string]$scenario.action -ne $expected.action -or
        $records.Count -ne $expected.records) {
        throw "Scenario shape changed for '$scenarioId'."
    }
    foreach ($hashName in @('telemetry_sha256', 'result_sha256')) {
        $hash = [string]$scenario.$hashName
        if ($hash -cnotmatch '^[0-9A-F]{64}$') {
            throw "Scenario '$scenarioId' has an invalid $hashName."
        }
    }
    if ($records.Count -eq 0) {
        if ($scenarioId -notin @(
                'm010-sight-direct-target-v1',
                'm000-save-load-random-v1') -or
            -not [bool]$scenario.expected_zero_random_command_sites) {
            throw 'Only the recorded S sight and save/load probes may be zero-site scenarios.'
        }
    }

    if ($records.Count -gt 0 -and -not $identityCache.ContainsKey($levelId)) {
        $identityPath = Join-Path $remakeRoot (
            "validation\identities\mod\$levelId-runtime-actors-v1.json")
        $identityCache[$levelId] = Get-Content -LiteralPath $identityPath `
            -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $identities = @($identityCache[$levelId].identities)
    $previousSequence = -1
    foreach ($record in $records) {
        $sequence = [int64]$record.sequence
        $runtimeType = [string][int]$record.runtime_type
        $family = [string]$record.family
        $site = [string]$record.call_site_rva
        if ($sequence -le $previousSequence -or
            [int64]$record.tick_ms -lt 0 -or
            [int]$record.value -lt 0 -or [int]$record.value -gt 32767 -or
            [int]$record.faction_id -ne 3) {
            throw "Invalid ordered record in '$scenarioId'."
        }
        $previousSequence = $sequence
        $recordKey = "$levelId`:$sequence"
        if (-not $seenRecords.Add($recordKey)) {
            throw "Duplicate command record '$recordKey'."
        }
        if (-not $expectedFamilySites.ContainsKey($family) -or
            -not $expectedFamilySites[$family].ContainsKey($runtimeType) -or
            $site -ne $expectedFamilySites[$family][$runtimeType] -or
            -not $sdkSites.Contains($site)) {
            throw "Uncatalogued $family site $site for runtime type $runtimeType."
        }
        $matches = @($identities | Where-Object {
            [int]$_.runtime_index -eq [int]$record.runtime_index
        })
        if ($matches.Count -ne 1 -or
            [int]$matches[0].scene_index -ne [int]$record.scene_index -or
            [int]$matches[0].runtime_type -ne [int]$record.runtime_type -or
            [int]$matches[0].runtime_faction_id -ne [int]$record.faction_id) {
            throw "Identity mismatch for '$scenarioId' sequence $sequence."
        }
        $familyCounts[$family]++
        $recordCount++
    }
}
if ($recordCount -ne 10 -or
    $familyCounts.selected -ne 3 -or
    $familyCounts.acknowledge -ne 7) {
    throw 'The command evidence aggregate count changed unexpectedly.'
}

$dropScenario = @($scenarios | Where-Object {
    $_.scenario_id -eq 'm010-cigarette-drop-inventory-v1'
})
if ($dropScenario.Count -ne 1) {
    throw 'The backpack-drop scenario is missing.'
}
$factoryRecords = @($dropScenario[0].dynamic_factory_records)
if ($factoryRecords.Count -ne $expectedDynamicConstructorSites.Count) {
    throw 'A successful in-level backpack drop must have four constructor draws.'
}
$factoryEsi = [string]$factoryRecords[0].caller_esi
$previousFactorySequence = [int64]$dropScenario[0].records[0].sequence
for ($index = 0; $index -lt $factoryRecords.Count; $index++) {
    $record = $factoryRecords[$index]
    $site = [string]$record.call_site_rva
    if ($site -ne $expectedDynamicConstructorSites[$index] -or
        -not $sdkSites.Contains($site) -or
        [int64]$record.sequence -le $previousFactorySequence -or
        [int64]$record.tick_ms -lt 0 -or
        [string]$record.caller_esi -ne $factoryEsi -or
        [int]$record.runtime_type -ne 83 -or
        [int]$record.value -lt 0 -or [int]$record.value -gt 32767) {
        throw "Invalid backpack-drop constructor record at index $index."
    }
    $previousFactorySequence = [int64]$record.sequence
}
$absentFactorySites = @($dropScenario[0].expected_absent_factory_call_sites)
if ($absentFactorySites.Count -ne 1 -or
    [string]$absentFactorySites[0] -ne '0x0005BBBC') {
    throw 'The backpack-drop probe must explicitly exclude saved-actor facing.'
}

$saveScenario = @($scenarios | Where-Object {
    $_.scenario_id -eq 'm000-save-load-random-v1'
})
if ($saveScenario.Count -ne 1) {
    throw 'The save/load random-boundary scenario is missing.'
}
$boundary = $saveScenario[0].boundary_summary
if ([int]$boundary.source_entity_count -ne 1630 -or
    [int64]$boundary.before_save_tick_ms -ge
        [int64]$boundary.after_save_tick_ms -or
    [int64]$boundary.after_save_tick_ms -ge
        [int64]$boundary.after_load_tick_ms -or
    [int]$boundary.save_interval_call_count -ne 245 -or
    [int]$boundary.save_interval_structural_call_count -ne 0 -or
    [int]$boundary.load_interval_call_count -ne 14443) {
    throw 'The original save/load random boundary summary changed unexpectedly.'
}
$expectedLoadStructuralCounts = @{
    '0x00050967' = 1631
    '0x00050980' = 1631
    '0x0005340B' = 1631
    '0x0005358B' = 1631
    '0x00053655' = 1631
    '0x000537A3' = 1631
    '0x00050B64' = 1631
    '0x00050B7D' = 1631
    '0x0005BBBC' = 1
}
$actualLoadProperties = @(
    $boundary.load_interval_structural_counts.PSObject.Properties)
if ($actualLoadProperties.Count -ne $expectedLoadStructuralCounts.Count) {
    throw 'The original load structural call-site set changed unexpectedly.'
}
foreach ($site in $expectedLoadStructuralCounts.Keys) {
    $property = $boundary.load_interval_structural_counts.PSObject.Properties[$site]
    if ($null -eq $property -or
        [int]$property.Value -ne $expectedLoadStructuralCounts[$site] -or
        -not $sdkSites.Contains($site)) {
        throw "Incorrect original load structural count for $site."
    }
}

$mainSource = Get-Content -LiteralPath (
    Join-Path $remakeRoot 'game\scripts\main.gd') -Raw -Encoding UTF8
$requiredProductPaths = @{
    '_handle_original_key_action' = '_play_original_actor_audio'
    '_try_bury_at' = 'queue_original_acknowledgement'
    '_try_issue_legacy_world_object_deployment' = 'queue_original_acknowledgement'
    'issue_attack_order' = 'queue_original_acknowledgement'
    'drop_selected_item_at' = 'queue_original_acknowledgement'
    'issue_original_pickup_order' = 'queue_original_acknowledgement'
}
foreach ($functionName in $requiredProductPaths.Keys) {
    $pattern = '(?ms)^func\s+' + [Regex]::Escape($functionName) +
        '\b.*?(?=^func\s+|\z)'
    $functionMatch = [Regex]::Match($mainSource, $pattern)
    if (-not $functionMatch.Success -or
        $functionMatch.Value -notmatch
            [Regex]::Escape($requiredProductPaths[$functionName])) {
        throw "Product command path '$functionName' is not wired to actor audio."
    }
}

$unitSource = Get-Content -LiteralPath (
    Join-Path $remakeRoot 'game\scripts\squad_unit.gd') -Raw -Encoding UTF8
foreach ($marker in @(
        'pending_acknowledgement_count',
        'acknowledgement_serial',
        '_consume_original_pending_acknowledgement')) {
    if ($unitSource -notmatch [Regex]::Escape($marker)) {
        throw "Saved actor acknowledgement marker '$marker' is missing."
    }
}

Write-Host (
    'Original CRT random command evidence passed ' +
    "($($scenarios.Count) short scenarios, $recordCount command sites, " +
    "$($factoryRecords.Count) successful constructor sites, " +
    'zero global cursor APIs).')
