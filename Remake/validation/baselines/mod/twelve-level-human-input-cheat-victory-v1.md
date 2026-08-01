# Twelve-level human-input cheat-victory transition baseline

- Content profile: `repository-mod-12-level-20260729`
- Levels: `m000` through `m011`
- Original input: process-local DirectInput replay queue
- Remake input: target-viewport key events
- Text per level: `FLIPMISSION` (11 letters / 22 down-up events)
- Expected transition: active/result `0` to victory/result `3`
- Strict checks: 720
- Mismatches: 0
- Global cursor, system keyboard and focus calls: 0
- Actor-state and mission-result writes by probes: 0

The baseline proves only the built-in cheat input-to-victory transition. It
does not claim that either runtime completed a non-cheat gameplay route.
Long-form human-input gameplay victories remain tracked separately in
`game/data/mod_parity_contract.json`.
