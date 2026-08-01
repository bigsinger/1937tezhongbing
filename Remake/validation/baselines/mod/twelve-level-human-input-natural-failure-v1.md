# Twelve-level human-input natural mission failure parity

Both runtimes receive isolated character/weapon/mouse input, then their
unchanged combat pipeline must kill the required player and their mission
evaluator must select `required_character_lost`. No actor HP, mission result,
system cursor or global focus is written by the probes.

| Level | Scene | MOD route | Remake route | Checks | Mismatches | Result |
|---|---:|---|---|---:|---:|---|
| m000 | 1436 | ground_danger_route | ground_danger_route | 59 | 0 | pass |
| m001 | 1994 | ground_danger_route | ground_danger_route | 59 | 0 | pass |
| m002 | 886 | weapon_noise_lure | weapon_noise_lure | 59 | 0 | pass |
| m003 | 1150 | ground_danger_route | ground_danger_route | 59 | 0 | pass |
| m004 | 2629 | ground_danger_route | ground_danger_route | 59 | 0 | pass |
| m005 | 663 | ground_danger_route | ground_danger_route | 59 | 0 | pass |
| m006 | 1458 | ground_danger_route | weapon_noise_lure | 59 | 0 | pass |
| m007 | 2325 | ground_danger_route | weapon_noise_lure | 59 | 0 | pass |
| m008 | 753 | ground_danger_route | ground_danger_route | 59 | 0 | pass |
| m009 | 1709 | ground_danger_route | weapon_noise_lure | 59 | 0 | pass |
| m010 | 1590 | ground_danger_route | weapon_noise_lure | 59 | 0 | pass |
| m011 | 1176 | ground_danger_route | ground_danger_route | 59 | 0 | pass |

Overall: **pass** — 708 checks, 0 mismatches, 0 actor/mission writes,
0 system-cursor calls and 0 global-focus calls.
