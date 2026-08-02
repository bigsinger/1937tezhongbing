[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferenceTrace,
    [Parameter(Mandatory)]
    [string]$CandidateTrace,
    [ValidateRange(0, 6)]
    [int]$MaximumOnsetCheckpointDrift = 1,
    [string]$OutputJson = '',
    [switch]$AllowMismatch
)

$ErrorActionPreference = 'Stop'
$playerSceneIndex = 1436
# The original 0x45DDA0 runtime trace recovered after the first stable MOD
# baseline was recorded proves that scene 1598's shot also queues scene 1433.
# Depending on the captured patrol phase, scene 1433 may acquire the player
# before the settled checkpoint. Keep the old trace as the minimum contract
# while accepting this one evidence-backed additional live contact.
$recoveredAdditionalContactScenes = @(1433)
$expectedCheckpointIds = @(
    'contact_ready',
    'player_selected',
    'move_outbound_commanded',
    'move_outbound_observed',
    'move_return_commanded',
    'move_return_observed',
    'contact_settled'
)

function Read-Trace {
    param([string]$Path)
    return Get-Content -LiteralPath (Resolve-Path -LiteralPath $Path).Path `
        -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Add-Mismatch {
    param(
        [Collections.Generic.List[object]]$Target,
        [string]$Path,
        $Expected,
        $Actual,
        [string]$Rule
    )
    $Target.Add([pscustomobject][ordered]@{
        path = $Path
        expected = $Expected
        actual = $Actual
        rule = $Rule
    })
}

function Actors-ByScene {
    param($Checkpoint)
    $result = @{}
    foreach ($actor in @($Checkpoint.actors)) {
        $sceneIndex = [int]$actor.scene_index
        if ($result.ContainsKey($sceneIndex)) {
            throw "Duplicate actor scene identity in checkpoint: $sceneIndex"
        }
        $result[$sceneIndex] = $actor
    }
    return $result
}

function Property-Exists {
    param($Source, [string]$Name)
    return $null -ne $Source -and
        $null -ne $Source.PSObject.Properties[$Name]
}

function Actor-AttackType {
    param($Actor)
    if ($null -eq $Actor) {
        return 0
    }
    if ((Property-Exists $Actor 'native') -and
        (Property-Exists $Actor.native 'default_attack_type')) {
        return [int]$Actor.native.default_attack_type
    }
    if ((Property-Exists $Actor 'weapon') -and
        (Property-Exists $Actor.weapon 'attack_type')) {
        return [int]$Actor.weapon.attack_type
    }
    return 0
}

function Is-LiveContact {
    param($Actor, [int]$TargetSceneIndex)
    if ($null -eq $Actor -or
        [string]$Actor.role -ne 'enemy' -or
        -not [bool]$Actor.alive) {
        return $false
    }
    $native = $Actor.native
    return (
        $null -ne $native -and
        [int]$native.contact_state -eq 1 -and
        [int]$native.target_lost -eq 0 -and
        [int]$native.interest_scene_index -eq $TargetSceneIndex -and
        [int]$native.target_scene_index -eq $TargetSceneIndex
    )
}

function Contact-Scenes {
    param($Checkpoint, [hashtable]$AuditedScenes)
    $contacts = [Collections.Generic.List[int]]::new()
    foreach ($actor in @($Checkpoint.actors)) {
        $sceneIndex = [int]$actor.scene_index
        if ($AuditedScenes.ContainsKey($sceneIndex) -and
            (Is-LiveContact $actor $playerSceneIndex)) {
            $contacts.Add($sceneIndex)
        }
    }
    return @($contacts | Sort-Object)
}

function Contact-OnsetIndex {
    param($Checkpoints, [int]$SceneIndex)
    for ($index = 0; $index -lt @($Checkpoints).Count; ++$index) {
        $actors = Actors-ByScene $Checkpoints[$index]
        if ($actors.ContainsKey($SceneIndex) -and
            (Is-LiveContact $actors[$SceneIndex] $playerSceneIndex)) {
            return $index
        }
    }
    return -1
}

$reference = Read-Trace $ReferenceTrace
$candidate = Read-Trace $CandidateTrace
$runtimeActorCatalogPath = Join-Path `
    ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) `
    'game\data\original_runtime_actor_catalog.json'
$runtimeActorCatalog = Read-Trace $runtimeActorCatalogPath
$runtimeActorProfiles = $runtimeActorCatalog.levels.m000.actors
$mismatches = [Collections.Generic.List[object]]::new()
if ($reference.runtime -ne 'mod' -or
    $reference.scenario.id -ne 'm000-natural-contact-v1' -or
    $candidate.scenario.id -ne $reference.scenario.id -or
    $candidate.level.id -ne 'm000' -or
    $candidate.level.id -ne $reference.level.id -or
    $candidate.content_profile -ne $reference.content_profile) {
    throw 'Natural-contact traces do not share the stable m000 MOD identity.'
}

$referenceCheckpoints = @($reference.checkpoints)
$candidateCheckpoints = @($candidate.checkpoints)
if ($referenceCheckpoints.Count -ne $expectedCheckpointIds.Count -or
    $candidateCheckpoints.Count -ne $expectedCheckpointIds.Count -or
    (@($referenceCheckpoints.id) -join '|') -cne
        ($expectedCheckpointIds -join '|') -or
    (@($candidateCheckpoints.id) -join '|') -cne
        ($expectedCheckpointIds -join '|')) {
    throw 'Natural-contact traces must contain the canonical seven checkpoints.'
}

$referenceActors = Actors-ByScene $referenceCheckpoints[0]
$candidateActors = Actors-ByScene $candidateCheckpoints[0]
$auditedScenes = @{}
foreach ($sceneIndex in $referenceActors.Keys) {
    $auditedScenes[[int]$sceneIndex] = $true
    if (-not $candidateActors.ContainsKey([int]$sceneIndex)) {
        Add-Mismatch $mismatches "actors.scene:$sceneIndex" `
            'present' 'missing' 'required audited identity'
        continue
    }
    $expected = $referenceActors[[int]$sceneIndex]
    $actual = $candidateActors[[int]$sceneIndex]
    foreach ($field in @('role', 'database_entry_id')) {
        if ([string]$actual.$field -cne [string]$expected.$field) {
            Add-Mismatch $mismatches "actors.scene:$sceneIndex.$field" `
                $expected.$field $actual.$field 'exact audited identity'
        }
    }
    # The early natural-contact trace predates the live-faction catalog and
    # recorded the authored VWF faction for scene 1427.  The independent
    # RuntimeActorV1 gameplay-entry capture is authoritative for live faction
    # identity, including all five catalogued VWF/runtime overrides.
    $runtimeProfileProperty = $runtimeActorProfiles.PSObject.Properties[
        [string]$sceneIndex]
    $expectedFaction = if ($null -ne $runtimeProfileProperty) {
        [int]$runtimeProfileProperty.Value.runtime_faction_id
    }
    else {
        [int]$expected.faction_id
    }
    if ([int]$actual.faction_id -ne $expectedFaction) {
        Add-Mismatch $mismatches "actors.scene:$sceneIndex.faction_id" `
            $expectedFaction ([int]$actual.faction_id) `
            'exact process-captured runtime faction identity'
    }
    foreach ($field in @('current', 'maximum')) {
        if (-not (Property-Exists $expected 'hit_points') -or
            -not (Property-Exists $actual 'hit_points') -or
            [int]$actual.hit_points.$field -ne
                [int]$expected.hit_points.$field) {
            Add-Mismatch $mismatches `
                "actors.scene:$sceneIndex.hit_points.$field" `
                $(if (Property-Exists $expected 'hit_points') {
                    $expected.hit_points.$field
                } else {
                    'present'
                }) `
                $(if (Property-Exists $actual 'hit_points') {
                    $actual.hit_points.$field
                } else {
                    'missing'
                }) `
                'exact recovered runtime hit points'
        }
    }
    $expectedAttackType = Actor-AttackType $expected
    $actualAttackType = Actor-AttackType $actual
    if ($actualAttackType -ne $expectedAttackType) {
        Add-Mismatch $mismatches `
            "actors.scene:$sceneIndex.default_attack_type" `
            $expectedAttackType $actualAttackType `
            'exact recovered RuntimeActor +0x20C attack type'
    }
}

$referencePlayerHitPoints = [Collections.Generic.List[int]]::new()
$candidatePlayerHitPoints = [Collections.Generic.List[int]]::new()
$referenceContactEnemyHitPoints = [Collections.Generic.List[int]]::new()
$candidateContactEnemyHitPoints = [Collections.Generic.List[int]]::new()
for ($index = 0; $index -lt $candidateCheckpoints.Count; ++$index) {
    $referenceByScene = Actors-ByScene $referenceCheckpoints[$index]
    $candidateByScene = Actors-ByScene $candidateCheckpoints[$index]
    if (-not $candidateByScene.ContainsKey($playerSceneIndex)) {
        Add-Mismatch $mismatches `
            "checkpoints.$($expectedCheckpointIds[$index]).player" `
            'present and alive' 'missing' 'required player identity'
        continue
    }
    $player = $candidateByScene[$playerSceneIndex]
    $referencePlayer = $referenceByScene[$playerSceneIndex]
    if ([string]$player.role -ne 'player' -or -not [bool]$player.alive) {
        Add-Mismatch $mismatches `
            "checkpoints.$($expectedCheckpointIds[$index]).player.alive" `
            $true ([bool]$player.alive) 'player must survive the contact probe'
    }
    $expectedPlayerHitPoints = [int]$referencePlayer.hit_points.current
    $actualPlayerHitPoints = [int]$player.hit_points.current
    $referencePlayerHitPoints.Add($expectedPlayerHitPoints)
    $candidatePlayerHitPoints.Add($actualPlayerHitPoints)
    if ($actualPlayerHitPoints -ne $expectedPlayerHitPoints -or
        [int]$player.hit_points.maximum -ne
            [int]$referencePlayer.hit_points.maximum) {
        Add-Mismatch $mismatches `
            "checkpoints.$($expectedCheckpointIds[$index]).player.hit_points" `
            "$expectedPlayerHitPoints/$($referencePlayer.hit_points.maximum)" `
            "$actualPlayerHitPoints/$($player.hit_points.maximum)" `
            'exact MOD damage sequence'
    }

    foreach ($sceneIndex in $auditedScenes.Keys) {
        if (-not $referenceByScene.ContainsKey([int]$sceneIndex) -or
            -not $candidateByScene.ContainsKey([int]$sceneIndex)) {
            continue
        }
        $expectedActor = $referenceByScene[[int]$sceneIndex]
        $actualActor = $candidateByScene[[int]$sceneIndex]
        if ([int]$actualActor.hit_points.current -ne
                [int]$expectedActor.hit_points.current -or
            [int]$actualActor.hit_points.maximum -ne
                [int]$expectedActor.hit_points.maximum) {
            Add-Mismatch $mismatches `
                "checkpoints.$($expectedCheckpointIds[$index]).actors.scene:$sceneIndex.hit_points" `
                "$($expectedActor.hit_points.current)/$($expectedActor.hit_points.maximum)" `
                "$($actualActor.hit_points.current)/$($actualActor.hit_points.maximum)" `
                'exact audited actor hit points'
        }
        $expectedAttackType = Actor-AttackType $expectedActor
        $actualAttackType = Actor-AttackType $actualActor
        if ($actualAttackType -ne $expectedAttackType) {
            Add-Mismatch $mismatches `
                "checkpoints.$($expectedCheckpointIds[$index]).actors.scene:$sceneIndex.default_attack_type" `
                $expectedAttackType $actualAttackType `
                'exact recovered attack type'
        }
    }
}

$referenceFinalContacts = @(
    Contact-Scenes $referenceCheckpoints[-1] $auditedScenes
)
$candidateFinalContacts = @(
    Contact-Scenes $candidateCheckpoints[-1] $auditedScenes
)
if ($referenceFinalContacts.Count -eq 0) {
    throw 'The stable MOD baseline has no final natural contact.'
}

$primaryContactScene = [int]$referenceFinalContacts[0]
for ($index = 0; $index -lt $candidateCheckpoints.Count; ++$index) {
    $referenceByScene = Actors-ByScene $referenceCheckpoints[$index]
    $candidateByScene = Actors-ByScene $candidateCheckpoints[$index]
    if (-not $referenceByScene.ContainsKey($primaryContactScene) -or
        -not $candidateByScene.ContainsKey($primaryContactScene)) {
        continue
    }
    $referenceContactEnemyHitPoints.Add(
        [int]$referenceByScene[$primaryContactScene].hit_points.current)
    $candidateContactEnemyHitPoints.Add(
        [int]$candidateByScene[$primaryContactScene].hit_points.current)
}

# Candidate-only diagnostics make the two recovered 2-HP losses attributable
# and prevent a different nearby enemy from accidentally satisfying the same
# aggregate HP sequence.
$expectedDamageEvents = @(0, 0, 0, 0, 0, 1, 2)
for ($index = 0; $index -lt $candidateCheckpoints.Count; ++$index) {
    $candidateByScene = Actors-ByScene $candidateCheckpoints[$index]
    if (-not $candidateByScene.ContainsKey($playerSceneIndex)) {
        continue
    }
    $player = $candidateByScene[$playerSceneIndex]
    if (-not (Property-Exists $player 'native')) {
        continue
    }
    $native = $player.native
    if (Property-Exists $native 'damage_event_count') {
        $actualEvents = [int]$native.damage_event_count
        if ($actualEvents -ne $expectedDamageEvents[$index]) {
            Add-Mismatch $mismatches `
                "checkpoints.$($expectedCheckpointIds[$index]).player.damage_event_count" `
                $expectedDamageEvents[$index] $actualEvents `
                'one recovered 2-HP rifle hit per damaging checkpoint'
        }
    }
    if (Property-Exists $native 'damage_taken_total') {
        $expectedTotal = 8 - [int]$referencePlayerHitPoints[$index]
        if ([int]$native.damage_taken_total -ne $expectedTotal) {
            Add-Mismatch $mismatches `
                "checkpoints.$($expectedCheckpointIds[$index]).player.damage_taken_total" `
                $expectedTotal ([int]$native.damage_taken_total) `
                'exact cumulative damage'
        }
    }
    if (Property-Exists $native 'last_damage_attacker_scene_index') {
        $actualSource = [int]$native.last_damage_attacker_scene_index
        $allowedSources = if ($expectedDamageEvents[$index] -eq 0) {
            @(-1)
        } else {
            @($referenceFinalContacts) +
                @($recoveredAdditionalContactScenes)
        }
        if ($actualSource -notin $allowedSources) {
            Add-Mismatch $mismatches `
                "checkpoints.$($expectedCheckpointIds[$index]).player.last_damage_attacker_scene_index" `
                ($allowedSources -join ',') `
                $actualSource `
                'damage source is an audited stable or recovered native alert recipient'
        }
    }
}
$missingRequiredContacts = @(
    $referenceFinalContacts |
        Where-Object { $_ -notin $candidateFinalContacts }
)
$unexpectedContacts = @(
    $candidateFinalContacts |
        Where-Object {
            $_ -notin $referenceFinalContacts -and
            $_ -notin $recoveredAdditionalContactScenes
        }
)
if ($missingRequiredContacts.Count -gt 0 -or
    $unexpectedContacts.Count -gt 0) {
    Add-Mismatch $mismatches 'contact_settled.live_contact_scenes' `
        (
            'required=' + ($referenceFinalContacts -join ',') +
            '; optional=' +
            ($recoveredAdditionalContactScenes -join ',')
        ) `
        ($candidateFinalContacts -join ',') `
        'stable contacts are required and only recovered native recipients may be added'
}

$onsetResults = @()
foreach ($sceneIndex in $referenceFinalContacts) {
    $referenceOnset = Contact-OnsetIndex $referenceCheckpoints $sceneIndex
    $candidateOnset = Contact-OnsetIndex $candidateCheckpoints $sceneIndex
    $drift = if ($candidateOnset -ge 0) {
        [Math]::Abs($candidateOnset - $referenceOnset)
    }
    else {
        [int]::MaxValue
    }
    if ($candidateOnset -lt 0 -or
        $drift -gt $MaximumOnsetCheckpointDrift) {
        Add-Mismatch $mismatches "actors.scene:$sceneIndex.contact_onset" `
            $expectedCheckpointIds[$referenceOnset] `
            $(if ($candidateOnset -ge 0) {
                $expectedCheckpointIds[$candidateOnset]
            } else {
                'never'
            }) `
            "checkpoint drift <= $MaximumOnsetCheckpointDrift"
    }
    $onsetResults += [pscustomobject][ordered]@{
        scene_index = [int]$sceneIndex
        reference_checkpoint = if ($referenceOnset -ge 0) {
            $expectedCheckpointIds[$referenceOnset]
        } else {
            'never'
        }
        candidate_checkpoint = if ($candidateOnset -ge 0) {
            $expectedCheckpointIds[$candidateOnset]
        } else {
            'never'
        }
        checkpoint_drift = $drift
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    level_id = 'm000'
    scenario_id = 'm000-natural-contact-v1'
    audited_actor_count = $referenceActors.Count
    runtime_faction_catalog_id = $runtimeActorCatalog.catalog_id
    player_scene_index = $playerSceneIndex
    required_contact_scenes = $referenceFinalContacts
    recovered_optional_contact_scenes =
        $recoveredAdditionalContactScenes
    player_hit_point_sequence = [pscustomobject][ordered]@{
        reference = @($referencePlayerHitPoints)
        candidate = @($candidatePlayerHitPoints)
    }
    primary_contact_enemy_hit_point_sequence = [pscustomobject][ordered]@{
        scene_index = $primaryContactScene
        reference = @($referenceContactEnemyHitPoints)
        candidate = @($candidateContactEnemyHitPoints)
    }
    contact_onsets = $onsetResults
    maximum_onset_checkpoint_drift = $MaximumOnsetCheckpointDrift
    mismatch_count = $mismatches.Count
    passed = $mismatches.Count -eq 0
    mismatches = @($mismatches)
}
if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = [IO.Path]::GetFullPath($OutputJson)
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($OutputJson)) | Out-Null
    $result | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $OutputJson -Encoding UTF8
}
if (-not $result.passed -and -not $AllowMismatch) {
    throw (
        "Natural-contact comparison failed with " +
        "$($mismatches.Count) mismatches.")
}
$result
