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
  `A73F0080DF9F0D401B23CF9D10AB7715666D87AB905E43B4E709EF8336E43DDE`

The automated UI screenshot opened m014 without activation, used local Windows
OCR, and was compressed before visual inspection.
