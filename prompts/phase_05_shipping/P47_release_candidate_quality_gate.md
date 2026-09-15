# P47 — Release candidate quality gate

## Context
Read `CLAUDE.md`, the relevant GDD/architecture documents, and current implementation status before editing.

## Task
Run full QA matrix, save migration tests, content validator, provenance audit, title/legal checklist, build packaging and known-issues review.

## Constraints
- Preserve fictional/original branding.
- Do not download or import unapproved third-party assets/packages.
- Keep save compatibility in mind.
- Add or update tests where the feature has deterministic logic.
- Do not implement future prompts opportunistically unless required to avoid broken architecture.

## Acceptance criteria
Zero open P0/P1; reproducible build instructions; final release checklist signed off by human owner.

## Required completion report
1. Files changed.
2. Tests/checks run and results.
3. Remaining limitations or TODOs.
4. Update `docs/production/IMPLEMENTATION_STATUS.md`.
