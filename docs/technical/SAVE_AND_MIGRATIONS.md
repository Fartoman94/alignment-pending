# Save/load & migrations

- Save format begins version 1.
- Maintain 3 rotating autosaves plus manual saves.
- Write to temporary file, validate, then atomic replace where platform allows.
- Add checksum/hash for corruption detection.
- Every schema change adds a migration function `vN -> vN+1`.
- Never delete old migration code before the minimum supported save version is intentionally raised.
- Include recovery UI when most recent autosave is corrupt.
- Store settings separately from campaign saves.
