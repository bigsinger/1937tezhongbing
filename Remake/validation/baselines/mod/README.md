# Stable MOD runtime baselines

These files are read-only behavioral evidence captured from the repository's
hash-locked `repository-mod-12-level-20260729` content profile.

`m000-basic-movement-v1.json` and `m000-obstacle-route-v1.json` were produced by
`Patch/analysis/tools/ModRegressionProbe.cs`. The probe:

- starts an isolated copy of the MOD;
- reads only the tested process;
- posts input only to the tested window and its process-local DirectInput queue;
- never calls a global cursor, keyboard, focus, or input-injection API;
- maps the unique m000 player at `(241,51)` to recovered VWF scene 1436 /
  DBL entry 924;
- records the unobstructed command-replacement route `(1,3) -> (5,3)`;
- records the tree-edge detour `(16,34) -> (9,8)`, including the original
  one-open-side diagonal rule and early return to the prior movement corridor.

`m000-player-obstacle-route-v1.json` through
`m011-player-obstacle-route-v1.json` extend the same process-private probe to
one identity-resolved player and an outbound/return obstacle route in every
formal level. Each observed checkpoint contains regularly sampled world
positions. `Compare-RuntimeParityTrace.ps1 -CompareObservedRouteShape` strictly
checks three directed point-to-polyline distances: stable-MOD observations to
the Remake planned path, Remake observations to stable-MOD observations, and
Remake observations to the Remake planned path. The gate is 4 pixels; the
audited twelve-level worst case is 3.420 pixels. Missing samples or planned
points fail rather than falling back to endpoint-only comparison.

The MOD's compact runtime object array is not the VWF scene array. Only an
identity that has a recovered, reviewable mapping may be assigned a VWF
`scene_index`; unproven enemy identities are deliberately excluded from this
first baseline.

`m000-enemy-patrol-v1.json` through `m011-enemy-patrol-v1.json` are
four-checkpoint, two-interval observations of all 656 identity-resolved hostile
actors. They were captured from canonical isolated 1024x768 runtimes after the
original “Return to Mission” flow actually resumed world simulation. A second
isolated run reproduced the kinematics within the documented tolerances. Exact
route phase remains diagnostic; per-actor identities and interval
displacements, maximum/P90 displacement, and moving/stationary counts are
strict gates. `Capture-TwelveLevelPatrolParity.ps1` reproduces the paired
stable-MOD/Remake gate without moving, clipping, or reading the system cursor.
The latest audited result is summarized in
`twelve-level-patrol-parity-v1.md`.

Run `Remake/tools/Run-RuntimeProbe.ps1` to generate the matching Remake trace
and `comparison.json` / `comparison.md`.

`initial-weapon-inventory-v1.json` is a gameplay-entry baseline for all twelve
levels. It contains 660 exact actor identities, 761 ordered weapon-container
entries and 67 intentionally empty containers; the player-only compatibility
subset contains 27 identities and 83 entries. The active attack type is taken
from the stable runtime snapshots rather than the VWF authored default. Enemy
containers remain exact even though recovered `sub_456DF0` semantics do not
consume their quantities. Every level records SHA-256 provenance for both
entry and steady read-only snapshots plus its runtime identity catalog.
Identity JSON hashes use UTF-8 text normalized to LF without BOM for
cross-platform reproducibility. Product data in
`game/data/original_initial_weapon_inventory.json` must remain semantically
identical and is checked on every build.

`initial-item-inventory-v1.json` is the corresponding `RuntimeActorV1 +0x228`
backpack baseline. Exact identity filtering produces 660 actors and 539 ordered
entries across all twelve levels; the 27 captured players account for 74
entries and one intentionally empty backpack. Resolved/high and unresolved
identities remain evidence-only and are never guessed into product scene IDs.
The baseline also records the recovered item names, direct effects, generic
mode semantics, death-drop behavior, raw snapshot hashes, and canonical
identity hashes. Product data in
`game/data/original_initial_item_inventory.json` is cross-checked on every
build.

`world-pickups-v1.json` is generated directly from the hash-locked
`1937Database.dbl` by `Build-ModWorldPickupBaseline.ps1`. DBL sprite
`header[2]` supplies the runtime item ID; the recovered `sub_45AE10` branch
classifies the actor-local weapon/backpack container and quantity mode; the
`sub_453F70` caller fixes the pickup grant at one item. It covers ten field
pickups plus the non-pickable gasoline barrel's runtime item 53.
`Test-OriginalWorldPickups.ps1` cross-checks this baseline against product data
and also verifies the materialized MOD DBL hash when it is available.

`m001-mine-pickup-inventory-v1.json` is a two-checkpoint live-command trace.
The stable MOD selects scene 2280, clicks the scene-2096 mine through the
process-local DirectInput queue, walks into the recovered adjacent 32x16-cell
range and changes ordered weapon item 43 from quantity 2 to 3. It proves the
click-to-route-to-transfer lifecycle rather than calling the inventory API.

`m000-pistol-attack-inventory-v1.json` similarly selects scene 1436, equips
the pistol and clicks live enemy scene 1598. Ordered weapon item 36 changes
from 7 to 6. Ten additional live-command traces cover Qiangzi's rifle
(item 37, 20 to 19), machine gun (item 38, 10 to 9) and grenade (item 44,
3 to 2) in m010, plus Daniu's dart (item 41, 20 to 19) against stationary
scene 2685 in m004. The m007 slingshot trace keeps controllable Tiedan in
original player slot 2 while preserving his live faction 1, then force-targets
adjacent Gu Ming; durable item 42 remains 1 and target HP changes from 8 to 7.
Daniu's m010 dagger and broadsword traces preserve their
mode-1 item quantities at 1 while matching the target transition from 8 HP
to dead at 0 HP. Lao Zhao's mine and timed-explosive traces both consume one
mode-0 item (3 to 2) and require the runtime object count to increase by one.
The m010 cases also prove that a commanded attacker can leave the original
four-person spawn formation instead of being trapped by friendly dynamic
occupancy.

Six `*-world-item-v1.json` traces cover the original command-9 drop, route,
enemy pickup and effect lifecycle for chicken 33, canned meat 48, hypnosis
doll 49, poisoned wine 52, dog bone 82 and cigarette 83. They strictly compare
ordered containers and modes before/after collection, retained versus forced
consumption, runtime object removal, temporary control, distraction and the
poison tick-81 damage boundary. The original retains a dead poisoned actor's
container until its later death-drop phase, while Remake materializes that
drop immediately; only the `after_effect` container timing is diagnostic for
that scenario. Its poison-active flag, counter/limit, HP and alive transition
remain strict, and all before/after-collection container checks remain strict.

All traces retain the complete audited actor roster, but
`Compare-InventoryParityTrace.ps1` deliberately treats moving-patrol
positions as diagnostic because independent launches can begin at different
patrol phases. Canonical ordered inventory contents, modes, active attack type,
the required quantity transition, and target HP in scenarios that require a
committed hit are strict.

Run `Remake/tools/Capture-InventoryParity.ps1` to recapture all eighteen MOD traces,
replay every scenario in Remake and produce JSON/Markdown comparisons. Pass
`-ScenarioId ID` to isolate one scenario while developing. The runner copies
the MOD to an isolated `E:\1937` runtime, sends input only to the target
process/window and never captures, clips, warps or moves the system cursor.

`m010-sight-direct-target-v1.json` and `m010-burial-command-v1.json` extend the
same live-command harness to the contextual `S` and `B` commands. The sight
trace proves that `S` followed by a hostile click selects the living hostile
without creating a persistent type-90 watch marker. The burial trace first
kills scene 1126 with Daniu, then selects the surviving Lao Zhao and proves
that `B` followed by the corpse click assigns the original goal kind 4 without
creating type 78 immediately. `Compare-ContextualCommandParity.ps1` treats
identity, life state, selection/goal transitions and runtime-object lifecycle
as strict; patrol phase and elapsed time remain diagnostic.

`m010-briefing-left-click-dismissal-v1.json` is captured separately by
`Capture-BriefingInputParity.ps1`. With the original game held on its in-window
mission briefing, a process-private left-button pulse advances into the loaded
world. The Remake comparison uses the real imported M010 briefing image,
consumes the press in the modal layer and closes exactly once on release so the
same click cannot leak into gameplay. Both capture workflows assert
`global_pointer_control=false`.

`m000-native-required-player-failure-v1.json` through
`m011-native-required-player-failure-v1.json` are paired mission-outcome
baselines. In twelve isolated stable-MOD processes, the probe queues fatal
damage for an evaluator-required player at a process-local input boundary,
invokes the original `sub_458700` actor-damage routine, and then only observes
`sub_405410` select engine result 2. It never writes a mission-result field.
The matching Remake scenarios apply the same 8 HP damage through the product
`take_damage()` path and require `MissionRuntime` to produce
`required_character_lost`.
`Compare-NativeMissionFailureParity.ps1` strictly checks the actor identity,
position, faction/runtime type, HP/alive transition, damage event and native
active-to-failed result. The observer and replay diagnostic are opt-in through
`M1937_MISSION_TRACE=1` and do not alter normal MOD input or cursor behavior.
`Capture-TwelveLevelNativeMissionFailureParity.ps1` reproduces all twelve
captures, comparisons and the summary from one isolated runtime. The audited
scene/type/result matrix is retained in
`twelve-level-native-mission-failure-v1.md`.

`m000-human-input-natural-failure-v1.json` through
`m011-human-input-natural-failure-v1.json` close the diagnostic-entry gap in
that evidence. The stable MOD receives only process-local DirectInput character
hotkeys and a ground or forced-attack click; the Remake receives only equivalent
target-viewport events. Each runtime then relies on its ordinary enemy combat
pipeline to reduce the evaluator-required player from 8 HP to 0 and on its own
mission evaluator to choose `required_character_lost` / result 2. The probes
never write actor HP or a mission result, and never call the system cursor or
global focus APIs. `Compare-HumanInputNaturalMissionFailureParity.ps1` checks
59 facts per level, including identity, spawn state, isolated input sequence,
monotonic damage, live attacker evidence and the active-to-failed transition.
The audited 12-level result is 708 checks, zero mismatches; see
`twelve-level-human-input-natural-failure-v1.md`.

Use `Capture-TwelveLevelHumanInputNaturalFailureParity.ps1 -UpdateBaselines`
to recapture both runtimes from an isolated MOD copy. CI uses
`Verify-TwelveLevelHumanInputNaturalFailureParity.ps1` to replay all twelve
Remake scenarios against the checked-in read-only MOD evidence without needing
to launch the legacy executable.

`m000-human-input-cheat-victory-v1.json` through
`m011-human-input-cheat-victory-v1.json` cover the complementary native victory
transition. The stable MOD receives the original built-in `FLIPMISSION` text
as 22 process-local DirectInput down/up events; the Remake receives the same
letters as 22 target-viewport events. Each runtime must move from active/result
0 to victory/result 3, with all authored Remake objectives complete. The probe
does not write actor state or mission results and does not call system cursor,
keyboard or global-focus APIs.

This is deliberately labelled `cheat-victory-transition-only`: it verifies
the original cheat recognizer, mission evaluator and victory presentation
entry, but it is not evidence of a non-cheat gameplay completion. The latter
remains an explicit parity-contract gap. The checked-in comparison contains 60
strict checks per level, 720 total, with zero mismatches. Use
`Capture-TwelveLevelHumanInputCheatVictoryParity.ps1 -UpdateBaselines` to
recapture it and `Verify-TwelveLevelHumanInputCheatVictoryParity.ps1` for the
CI replay.
