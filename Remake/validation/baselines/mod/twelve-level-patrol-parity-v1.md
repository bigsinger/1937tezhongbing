# Twelve-level stable MOD patrol parity

This report records the audited 2026-07-30 differential run for content profile
`repository-mod-12-level-20260729`. The stable MOD and Godot 4.7.1 Remake were
captured at the same four gameplay checkpoints, yielding two one-second
movement intervals per actor.

The MOD probe posts only to the target window and its process-local DirectInput
proxy. It made zero system-cursor calls and zero global-focus calls.

| Level | MOD audited hostiles | Remake audited hostiles | Additional mission actors | Kinematics mismatches |
|---|---:|---:|---:|---:|
| m000 | 54 | 54 | 0 | 0 |
| m001 | 70 | 70 | 0 | 0 |
| m002 | 28 | 28 | 0 | 0 |
| m003 | 48 | 48 | 0 | 0 |
| m004 | 96 | 96 | 0 | 0 |
| m005 | 79 | 79 | 1 | 0 |
| m006 | 31 | 31 | 1 | 0 |
| m007 | 74 | 74 | 1 | 0 |
| m008 | 26 | 26 | 0 | 0 |
| m009 | 43 | 43 | 0 | 0 |
| m010 | 74 | 74 | 0 | 0 |
| m011 | 33 | 33 | 0 | 0 |
| **Total** | **656** | **656** | **3** | **0** |

The three additional Remake nodes are mission/story actors outside the MOD
patrol-hostile roster: m005 scene 736, m006 scene 1460, and m007 scene 2298.
They are reported separately instead of being hidden or counted as patrol
differences.

The strict comparison covers actor identity and both interval displacements,
plus maximum/P90 displacement and moving/stationary counts. It does not claim
continuous frame-by-frame equivalence between the finite checkpoints.

Reproduce the gate from a checkout containing the local original resources:

```powershell
.\tools\Capture-TwelveLevelPatrolParity.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe
```
