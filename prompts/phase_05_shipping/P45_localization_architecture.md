# P45 — Localization architecture

## Context
Read `CLAUDE.md`, the relevant GDD/architecture documents, and current implementation status before editing.

## Task
Externalize all player-facing strings; seed English + Spanish test locales with pseudo-localization.

## Constraints
- Preserve fictional/original branding.
- Do not download or import unapproved third-party assets/packages.
- Keep save compatibility in mind.
- Add or update tests where the feature has deterministic logic.
- Do not implement future prompts opportunistically unless required to avoid broken architecture.

## Acceptance criteria
No critical hardcoded gameplay text; UI survives +30% string expansion.

## Required completion report
1. Files changed.
2. Tests/checks run and results.
3. Remaining limitations or TODOs.
4. Update `docs/production/IMPLEMENTATION_STATUS.md`.
