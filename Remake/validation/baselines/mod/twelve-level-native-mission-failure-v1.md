# Twelve-level native mission failure parity

Content profile: `repository-mod-12-level-20260729`

The stable MOD was launched once per level in an isolated runtime. At a
process-local replay boundary, the diagnostic invoked original actor damage
entry `sub_458700` for one player explicitly required by that level's original
mission evaluator. It then only observed `sub_405410` change the mission result
from active `0` to failed `2`. No mission result field, system cursor or
foreground-window state was written.

The Remake replay loaded the same real level and scene, applied the same fatal
damage through `SquadUnit.take_damage()`, and required the normal death event to
produce `required_character_lost`. Each pair passed 26 strict identity, state,
damage and mission checks.

| Level | Required scene | Runtime type | Native result | Checks | Result |
|---|---:|---:|---:|---:|---|
| m000 | 1436 | 1 | 0 → 2 | 26 | pass |
| m001 | 1994 | 10 | 0 → 2 | 26 | pass |
| m002 | 886 | 2 | 0 → 2 | 26 | pass |
| m003 | 1150 | 2 | 0 → 2 | 26 | pass |
| m004 | 2629 | 8 | 0 → 2 | 26 | pass |
| m005 | 663 | 2 | 0 → 2 | 26 | pass |
| m006 | 1458 | 1 | 0 → 2 | 26 | pass |
| m007 | 2325 | 2 | 0 → 2 | 26 | pass |
| m008 | 753 | 2 | 0 → 2 | 26 | pass |
| m009 | 1709 | 2 | 0 → 2 | 26 | pass |
| m010 | 1590 | 2 | 0 → 2 | 26 | pass |
| m011 | 1176 | 2 | 0 → 2 | 26 | pass |

Reproduce with:

```powershell
.\Remake\tools\Capture-TwelveLevelNativeMissionFailureParity.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe
```

This closes native required-player failure parity. It does not replace the
remaining requirement for full human-input victory and natural-combat failure
recordings.
