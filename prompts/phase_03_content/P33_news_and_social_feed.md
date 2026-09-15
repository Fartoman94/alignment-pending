# P33 — News and social feed

## Context
Read `CLAUDE.md`, the relevant GDD/architecture documents, and current implementation status before editing.

## Task
Implement offline authored-template feed using simulation variables. Never call live LLM APIs.

## Constraints
- Preserve fictional/original branding.
- Do not download or import unapproved third-party assets/packages.
- Keep save compatibility in mind.
- Add or update tests where the feature has deterministic logic.
- Do not implement future prompts opportunistically unless required to avoid broken architecture.

## Acceptance criteria
100% deterministic from events; no real publication/service names.

## Required completion report
1. Files changed.
2. Tests/checks run and results.
3. Remaining limitations or TODOs.
4. Update `docs/production/IMPLEMENTATION_STATUS.md`.
