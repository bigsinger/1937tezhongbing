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

`m000-enemy-patrol-v1.json` is a four-checkpoint, two-interval observation of
46 enemy actors resolved by
`validation/identities/mod/m000-runtime-actors-v1.json`. It was captured from
the canonical isolated 1024x768 runtime after the original “Return to Mission”
flow actually resumed world simulation. A second isolated run reproduced the
kinematics within the documented tolerances. Exact route phase remains a
diagnostic comparison; maximum displacement, 90th-percentile displacement,
moving/stationary counts, and all 46 identities are strict gates.

Run `Remake/tools/Run-RuntimeProbe.ps1` to generate the matching Remake trace
and `comparison.json` / `comparison.md`.

`initial-weapon-inventory-v1.json` is a gameplay-entry baseline for all twelve
levels. It contains 27 exact player identities and 83 ordered weapon-container
entries. Every level records SHA-256 provenance for both entry and steady
read-only snapshots plus its runtime identity catalog. Product data in
`game/data/original_initial_weapon_inventory.json` must remain semantically
identical and is checked on every build.
