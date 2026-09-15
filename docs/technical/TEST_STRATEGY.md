# Test strategy

## Automated
- Headless boot smoke test.
- Data validation test.
- Save round-trip test.
- Save migration fixtures.
- Deterministic incident selection test with fixed seed.
- Economy invariants: no NaN/negative impossible state.
- Model training state-machine tests.

## Manual regression matrix
New game, save/load, build/delete, hire/fire, train/cancel, evaluate, deploy/rollback, incident choices, bankruptcy, endings, settings, resolution changes, localization overflow.

## Release gates
P0: crash/data loss/security/build failure. Zero open.
P1: progression blocker/major save inconsistency. Zero open.
P2: significant usability/balance bug. Must have explicit waiver if open.
