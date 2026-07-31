[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceTrace,

    [Parameter(Mandatory)]
    [string]$CandidateTrace,

    [string]$OutputJson = '',

    [string]$OutputMarkdown = '',

    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-Trace {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $trace = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([int]$trace.schema_version -ne 1) {
        throw "Unsupported runtime parity trace schema: $resolved"
    }
    return $trace
}

function Property-Exists {
    param($Source, [string]$Name)

    return $null -ne $Source -and
        $null -ne $Source.PSObject.Properties[$Name]
}

function Add-Mismatch {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )

    $Items.Add([pscustomobject][ordered]@{
        path = $Path
        expected = $Expected
        actual = $Actual
        rule = $Rule
    })
}

function Compare-ExactValue {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule = 'exact'
    )

    if ([string]$Expected -cne [string]$Actual) {
        Add-Mismatch $Items $Path $Expected $Actual $Rule
    }
}

function Get-CheckpointMap {
    param(
        $Trace,
        [Collections.Generic.List[object]]$Items,
        [string]$RuntimeLabel
    )

    $map = @{}
    foreach ($checkpoint in @($Trace.checkpoints)) {
        $id = [string]$checkpoint.id
        if ($map.ContainsKey($id)) {
            Add-Mismatch $Items "$RuntimeLabel.checkpoints.$id" `
                'unique' 'duplicate' 'unique checkpoint ID'
        }
        else {
            $map[$id] = $checkpoint
        }
    }
    return $map
}

function Get-Actor {
    param(
        $Checkpoint,
        [int]$SceneIndex
    )

    return @(
        $Checkpoint.actors |
            Where-Object { [int]$_.scene_index -eq $SceneIndex }
    ) | Select-Object -First 1
}

function Compare-Inventory {
    param(
        [Collections.Generic.List[object]]$Items,
        [string]$Path,
        $Expected,
        $Actual
    )

    if ($null -eq $Expected -or $null -eq $Actual) {
        Add-Mismatch $Items $Path 'canonical inventory' `
            $(if ($null -eq $Actual) { 'missing' } else { 'present' }) `
            'required'
        return
    }

    foreach ($field in @(
            'schema_version',
            'active_attack_type',
            'weapon_entries',
            'item_entries')) {
        if (-not (Property-Exists $Expected $field) -or
            -not (Property-Exists $Actual $field)) {
            Add-Mismatch $Items "$Path.$field" 'present' `
                $(if (Property-Exists $Actual $field) {
                    'present'
                }
                else {
                    'missing'
                }) `
                'canonical inventory field'
            continue
        }
        if ($field -in @('schema_version', 'active_attack_type')) {
            Compare-ExactValue $Items "$Path.$field" `
                $Expected.$field $Actual.$field
        }
    }

    foreach ($container in @('weapon_entries', 'item_entries')) {
        if (-not (Property-Exists $Expected $container) -or
            -not (Property-Exists $Actual $container)) {
            continue
        }
        $expectedEntries = @($Expected.$container)
        $actualEntries = @($Actual.$container)
        Compare-ExactValue $Items "$Path.$container.count" `
            $expectedEntries.Count $actualEntries.Count `
            'exact ordered entry count'
        $commonCount = [Math]::Min(
            $expectedEntries.Count,
            $actualEntries.Count)
        for ($index = 0; $index -lt $commonCount; $index++) {
            foreach ($field in @(
                    'inventory_index',
                    'item_id',
                    'quantity',
                    'quantity_mode')) {
                $expectedEntry = $expectedEntries[$index]
                $actualEntry = $actualEntries[$index]
                if (-not (Property-Exists $expectedEntry $field) -or
                    -not (Property-Exists $actualEntry $field)) {
                    Add-Mismatch $Items `
                        "$Path.$container[$index].$field" `
                        'present' `
                        $(if (Property-Exists $actualEntry $field) {
                            'present'
                        }
                        else {
                            'missing'
                        }) `
                        'canonical inventory entry field'
                    continue
                }
                Compare-ExactValue $Items `
                    "$Path.$container[$index].$field" `
                    $expectedEntry.$field $actualEntry.$field
            }
        }
    }
}

function Get-ItemQuantity {
    param(
        $Inventory,
        [string]$Container,
        [int]$ItemId
    )

    $entries = @($Inventory.$Container |
        Where-Object { [int]$_.item_id -eq $ItemId })
    if ($entries.Count -eq 0) {
        return 0
    }
    return [int]$entries[0].quantity
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$mismatches = [Collections.Generic.List[object]]::new()

$scenarioDefinitions = @{
    'm001-mine-pickup-inventory-v1' = [ordered]@{
        level_id = 'm001'
        selector_level = 2
        engine_mission = 2
        actor_scene = 2280
        actor_database_entry = 918
        checkpoints = @('before_pickup', 'after_pickup')
        active_attack_type = 4
        delta_container = 'weapon_entries'
        delta_item_id = 43
        delta_quantity = 1
        expected_before_quantity = 2
        expected_after_quantity = 3
        target_scene = -1
    }
    'm000-pistol-attack-inventory-v1' = [ordered]@{
        level_id = 'm000'
        selector_level = 1
        engine_mission = 1
        actor_scene = 1436
        actor_database_entry = 924
        checkpoints = @('before_attack', 'after_attack')
        active_attack_type = 1
        delta_container = 'weapon_entries'
        delta_item_id = 36
        delta_quantity = -1
        expected_before_quantity = 7
        expected_after_quantity = 6
        target_scene = 1598
    }
}

$scenarioId = [string]$reference.scenario.id
if (-not $scenarioDefinitions.ContainsKey($scenarioId)) {
    throw "Unsupported inventory parity scenario: $scenarioId"
}
$definition = $scenarioDefinitions[$scenarioId]

foreach ($field in @('content_profile')) {
    Compare-ExactValue $mismatches "trace.$field" `
        $reference.$field $candidate.$field
}
Compare-ExactValue $mismatches 'scenario.id' `
    $scenarioId $candidate.scenario.id
Compare-ExactValue $mismatches 'scenario.coordinate_space' `
    $reference.scenario.coordinate_space `
    $candidate.scenario.coordinate_space
Compare-ExactValue $mismatches 'level.id' `
    $definition.level_id $reference.level.id `
    'scenario identity'
Compare-ExactValue $mismatches 'candidate.level.id' `
    $definition.level_id $candidate.level.id `
    'scenario identity'
foreach ($field in @('selector_level', 'engine_mission')) {
    Compare-ExactValue $mismatches "reference.level.$field" `
        $definition.$field $reference.level.$field `
        'scenario identity'
    Compare-ExactValue $mismatches "candidate.level.$field" `
        $definition.$field $candidate.level.$field `
        'scenario identity'
}

$referenceCheckpointMap = Get-CheckpointMap `
    $reference $mismatches 'reference'
$candidateCheckpointMap = Get-CheckpointMap `
    $candidate $mismatches 'candidate'
$expectedCheckpointIds = @($definition.checkpoints)
Compare-ExactValue $mismatches 'reference.checkpoints.count' `
    $expectedCheckpointIds.Count @($reference.checkpoints).Count `
    'exact scenario checkpoint count'
Compare-ExactValue $mismatches 'candidate.checkpoints.count' `
    $expectedCheckpointIds.Count @($candidate.checkpoints).Count `
    'exact scenario checkpoint count'

foreach ($checkpointId in $expectedCheckpointIds) {
    if (-not $referenceCheckpointMap.ContainsKey($checkpointId) -or
        -not $candidateCheckpointMap.ContainsKey($checkpointId)) {
        Add-Mismatch $mismatches "checkpoints.$checkpointId" `
            'present in both traces' `
            ('reference={0}, candidate={1}' -f
                $referenceCheckpointMap.ContainsKey($checkpointId),
                $candidateCheckpointMap.ContainsKey($checkpointId)) `
            'required'
        continue
    }

    $referenceCheckpoint = $referenceCheckpointMap[$checkpointId]
    $candidateCheckpoint = $candidateCheckpointMap[$checkpointId]
    $referenceActor = Get-Actor `
        $referenceCheckpoint ([int]$definition.actor_scene)
    $candidateActor = Get-Actor `
        $candidateCheckpoint ([int]$definition.actor_scene)
    if ($null -eq $referenceActor -or $null -eq $candidateActor) {
        Add-Mismatch $mismatches `
            "checkpoints.$checkpointId.actors.scene:$($definition.actor_scene)" `
            'present in both traces' `
            ('reference={0}, candidate={1}' -f
                ($null -ne $referenceActor),
                ($null -ne $candidateActor)) `
            'required tracked actor'
        continue
    }

    foreach ($field in @(
            'actor_id',
            'role',
            'scene_index',
            'database_entry_id',
            'faction_id')) {
        Compare-ExactValue $mismatches `
            "checkpoints.$checkpointId.actors.scene:$($definition.actor_scene).$field" `
            $referenceActor.$field $candidateActor.$field
    }
    Compare-ExactValue $mismatches `
        "checkpoints.$checkpointId.actors.scene:$($definition.actor_scene).database_entry_id" `
        $definition.actor_database_entry `
        $referenceActor.database_entry_id `
        'scenario identity'
    Compare-Inventory $mismatches `
        "checkpoints.$checkpointId.actors.scene:$($definition.actor_scene).inventory" `
        $referenceActor.inventory $candidateActor.inventory

    if ([int]$definition.target_scene -ge 0) {
        $referenceTarget = Get-Actor `
            $referenceCheckpoint ([int]$definition.target_scene)
        $candidateTarget = Get-Actor `
            $candidateCheckpoint ([int]$definition.target_scene)
        if ($null -eq $referenceTarget -or $null -eq $candidateTarget) {
            Add-Mismatch $mismatches `
                "checkpoints.$checkpointId.actors.scene:$($definition.target_scene)" `
                'present in both traces' `
                ('reference={0}, candidate={1}' -f
                    ($null -ne $referenceTarget),
                    ($null -ne $candidateTarget)) `
                'required attack target'
        }
        else {
            foreach ($field in @('current', 'maximum')) {
                Compare-ExactValue $mismatches `
                    "checkpoints.$checkpointId.actors.scene:$($definition.target_scene).hit_points.$field" `
                    $referenceTarget.hit_points.$field `
                    $candidateTarget.hit_points.$field `
                    'exact attack-result hit points'
            }
        }
    }
}

foreach ($traceCase in @(
        [pscustomobject]@{ label = 'reference'; trace = $reference },
        [pscustomobject]@{ label = 'candidate'; trace = $candidate })) {
    $beforeCheckpoint = $traceCase.trace.checkpoints |
        Where-Object {
            [string]$_.id -ceq [string]$expectedCheckpointIds[0]
        } |
        Select-Object -First 1
    $afterCheckpoint = $traceCase.trace.checkpoints |
        Where-Object {
            [string]$_.id -ceq [string]$expectedCheckpointIds[1]
        } |
        Select-Object -First 1
    if ($null -eq $beforeCheckpoint -or $null -eq $afterCheckpoint) {
        continue
    }
    $beforeActor = Get-Actor `
        $beforeCheckpoint ([int]$definition.actor_scene)
    $afterActor = Get-Actor `
        $afterCheckpoint ([int]$definition.actor_scene)
    if ($null -eq $beforeActor -or $null -eq $afterActor) {
        continue
    }
    $beforeQuantity = Get-ItemQuantity `
        $beforeActor.inventory `
        ([string]$definition.delta_container) `
        ([int]$definition.delta_item_id)
    $afterQuantity = Get-ItemQuantity `
        $afterActor.inventory `
        ([string]$definition.delta_container) `
        ([int]$definition.delta_item_id)
    Compare-ExactValue $mismatches `
        "$($traceCase.label).delta.before_quantity" `
        $definition.expected_before_quantity $beforeQuantity `
        "original item $($definition.delta_item_id) baseline"
    Compare-ExactValue $mismatches `
        "$($traceCase.label).delta.after_quantity" `
        $definition.expected_after_quantity $afterQuantity `
        "original item $($definition.delta_item_id) baseline"
    Compare-ExactValue $mismatches `
        "$($traceCase.label).delta.quantity" `
        $definition.delta_quantity ($afterQuantity - $beforeQuantity) `
        'exact inventory delta'
    Compare-ExactValue $mismatches `
        "$($traceCase.label).active_attack_type.before" `
        $definition.active_attack_type `
        $beforeActor.inventory.active_attack_type `
        'original active weapon'
    Compare-ExactValue $mismatches `
        "$($traceCase.label).active_attack_type.after" `
        $definition.active_attack_type `
        $afterActor.inventory.active_attack_type `
        'original active weapon'
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    reference_runtime = [string]$reference.runtime
    candidate_runtime = [string]$candidate.runtime
    level_id = [string]$definition.level_id
    scenario_id = $scenarioId
    actor_scene_index = [int]$definition.actor_scene
    checkpoint_ids = $expectedCheckpointIds
    inventory_delta = [pscustomobject][ordered]@{
        container = [string]$definition.delta_container
        item_id = [int]$definition.delta_item_id
        before_quantity = [int]$definition.expected_before_quantity
        after_quantity = [int]$definition.expected_after_quantity
        delta = [int]$definition.delta_quantity
    }
    mismatch_count = $mismatches.Count
    passed = $mismatches.Count -eq 0
    position_policy = (
        'Actor positions are diagnostic only for these scenarios because the ' +
        'live patrol target phase differs between isolated launches.')
    mismatches = @($mismatches)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($resolvedOutput)) | Out-Null
    $result | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
}

if (-not [string]::IsNullOrWhiteSpace($OutputMarkdown)) {
    $resolvedMarkdown = [IO.Path]::GetFullPath($OutputMarkdown)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($resolvedMarkdown)) | Out-Null
    $status = if ($result.passed) { 'PASS' } else { 'FAIL' }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("# Inventory parity: $scenarioId")
    $lines.Add('')
    $lines.Add("- Status: **$status**")
    $lines.Add("- Tracked actor: scene $($definition.actor_scene)")
    $lines.Add(
        "- Inventory delta: item $($definition.delta_item_id) " +
        "$($definition.expected_before_quantity) -> " +
        "$($definition.expected_after_quantity)")
    $lines.Add("- Mismatches: $($mismatches.Count)")
    $lines.Add('')
    if ($mismatches.Count -gt 0) {
        $lines.Add('| Path | Expected | Actual | Rule |')
        $lines.Add('|---|---|---|---|')
        foreach ($mismatch in $mismatches) {
            $expected = ([string]$mismatch.expected).Replace('|', '\|')
            $actual = ([string]$mismatch.actual).Replace('|', '\|')
            $rule = ([string]$mismatch.rule).Replace('|', '\|')
            $lines.Add(
                "| $($mismatch.path) | $expected | $actual | $rule |")
        }
    }
    else {
        $lines.Add(
            'Canonical ordered weapon/backpack inventories and the required ' +
            'quantity transition match the stable MOD baseline.')
    }
    $lines.Add('')
    $lines.Add(
        '> Position is intentionally diagnostic: a moving patrol target can ' +
        'start at a different phase in two isolated launches.')
    $lines |
        Set-Content -LiteralPath $resolvedMarkdown -Encoding UTF8
}

if (-not $result.passed -and -not $AllowMismatch) {
    throw (
        "Inventory parity failed for $scenarioId with " +
        "$($mismatches.Count) mismatch(es).")
}

return $result
