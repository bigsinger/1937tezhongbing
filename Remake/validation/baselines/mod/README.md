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
levels. It contains 27 exact player identities and 83 ordered weapon-container
entries. Every level records SHA-256 provenance for both entry and steady
read-only snapshots plus its runtime identity catalog. Identity JSON hashes
use UTF-8 text normalized to LF without BOM for cross-platform reproducibility.
Product data in
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
from 7 to 6. Eight additional live-command traces cover Qiangzi's rifle
(item 37, 20 to 19), machine gun (item 38, 10 to 9) and grenade (item 44,
3 to 2) in m010, plus Daniu's dart (item 41, 20 to 19) against stationary
scene 2685 in m004. Daniu's m010 dagger and broadsword traces preserve their
mode-1 item quantities at 1 while matching the target transition from 8 HP
to dead at 0 HP. Lao Zhao's mine and timed-explosive traces both consume one
mode-0 item (3 to 2) and require the runtime object count to increase by one.
The m010 cases also prove that a commanded attacker can leave the original
four-person spawn formation instead of being trapped by friendly dynamic
occupancy.

All traces retain the complete audited actor roster, but
`Compare-InventoryParityTrace.ps1` deliberately treats moving-patrol
positions and target-HP timing as diagnostic: independent launches can begin
at different patrol phases and an in-flight projectile can cross a checkpoint
boundary. Canonical ordered inventory contents, modes, active attack type and
the required quantity transition are strict.

Run `Remake/tools/Capture-InventoryParity.ps1` to recapture all ten MOD traces,
replay every scenario in Remake and produce JSON/Markdown comparisons. Pass
`-ScenarioId ID` to isolate one scenario while developing. The runner copies
the MOD to an isolated `E:\1937` runtime, sends input only to the target
process/window and never captures, clips, warps or moves the system cursor.
