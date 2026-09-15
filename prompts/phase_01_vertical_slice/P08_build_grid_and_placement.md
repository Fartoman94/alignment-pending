# P08 — Build grid and placement

## Context
Read `CLAUDE.md`, the relevant GDD/architecture documents, and current implementation status before editing.

## Task
Create office grid placement, ghost preview, valid/invalid feedback, rotate, place, sell and path-obstruction validation.

## Constraints
- Preserve fictional/original branding.
- Do not download or import unapproved third-party assets/packages.
- Keep save compatibility in mind.
- Add or update tests where the feature has deterministic logic.
- Do not implement future prompts opportunistically unless required to avoid broken architecture.

## Acceptance criteria
Place desk/rack/lab; cannot overlap or block mandatory route; refund rules data-driven.

## Required completion report
1. Files changed.
2. Tests/checks run and results.
3. Remaining limitations or TODOs.
4. Update `docs/production/IMPLEMENTATION_STATUS.md`.
