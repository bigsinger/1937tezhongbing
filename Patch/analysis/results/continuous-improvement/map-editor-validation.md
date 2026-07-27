# MapEditor Validation

- Release build: 0 warnings, 0 errors
- Core/editing/quality/spatial/mission/collaboration tests: passed
- Original VWF import: 155×140, 5 layers, 1,630 objects, 47 patrol routes
- Native no-change VWF round-trip: m000–m014 passed byte-for-byte
- Corrupt input, out-of-bounds data and capacity changes: rejected
- Native entity/reference/occupancy and patrol synchronization: passed
- Atomic save and backup rollback: passed
- Shipped sidecar editor round-trip: 3/3 passed
- Asset placement metadata coverage: 1,037/1,037
- Published executable: `MapEditor/LocalBuild/1937MapEditor.exe`
- Executable SHA-256:
  `B21B8F45E6FBC3F4AAED723216CAD05B4D6A9369B12170AFBEC46003DFEE64A1`

The automated UI screenshot opened m014 without activation, used local Windows
OCR, and was compressed before visual inspection.
