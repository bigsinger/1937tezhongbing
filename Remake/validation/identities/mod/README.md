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

`m000-runtime-actors-v1.json` resolves only identities supported by
one-to-one evidence. The two scripted four-soldier formations remain explicit
as eight unresolved records instead of receiving guessed scene ids. The
generator is `Remake/tools/Build-ModRuntimeIdentityCatalog.ps1`; the checked-in
catalog is validated without original assets in CI and is additionally checked
against the locally imported VWF manifest when that manifest is available.
