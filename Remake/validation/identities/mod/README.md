# Stable MOD runtime actor identities

The files in this directory connect read-only observations from the supported
stable MOD runtime to authored VWF scene identities. They are evidence for
differential MOD/Remake tests; they are not save data and do not modify the
original process.

Important field distinction:

- `RuntimeActorV1 +0x064` is a runtime actor type. The SDK historically called
  the field `database_entry`, but it is **not** a DBL id.
- `level.json.entities[].database_header_values[2]` is the corresponding VWF
  runtime type.
- `level.json.entities[].database_entry_id` is the actual DBL resource id.
- A runtime array index is scoped to the recorded capture and supported
  content profile. It is never used as a VWF scene index.

The directory now contains `m000` through `m011`. The initial conservative
catalog deliberately left ten actors unresolved. They are now recovered without
guessing: their runtime and VWF records form equal, contiguous, same-type runs
between independently resolved neighbors. Together the catalogs provide 772
resolved identities and zero unresolved actors.

The generator is `Remake/tools/Build-ModRuntimeIdentityCatalog.ps1`.
`Build-OriginalRuntimeActorCatalog.ps1` derives the smaller product catalog
`game/data/original_runtime_actor_catalog.json`, including five verified live
faction overrides and 656 stable-MOD patrol timelines. Source hashes and totals
are checked in CI. Identity JSON
hashes use UTF-8 text normalized to LF without BOM, so Windows and GitHub
checkouts produce the same evidence digest. m000 is additionally checked
against the locally imported VWF manifest when available.
