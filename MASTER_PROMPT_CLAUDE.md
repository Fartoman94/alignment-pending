# MASTER PROMPT — Build ALIGNMENT PENDING

You are taking over a greenfield Godot project as a principal gameplay engineer and technical lead.

## Mission
Build **ALIGNMENT PENDING**, an original 3D management/narrative strategy game. The player runs a fictional AI laboratory from a tiny office to global scale. The tone is dry corporate satire. The game must remain legally and creatively distinct from real AI companies and existing life/management games.

## First actions
1. Read `README_START_HERE.md` and `CLAUDE.md`.
2. Read all files in `docs/design/`, `docs/technical/`, `docs/legal/`, then `docs/production/ROADMAP.md`.
3. Inspect the starter project under `game/`.
4. Do not delete working scaffolding merely to replace it with a preferred architecture.
5. Execute prompts strictly in `prompts/RUN_ORDER.md` order.
6. After each prompt: run syntax/smoke checks available locally, update `docs/production/IMPLEMENTATION_STATUS.md`, and commit if Git is available.

## Absolute constraints
- All player-facing names/brands are fictional or player-generated.
- No scraped/copyrighted training data is included as content. Dataset choices are abstract gameplay cards/categories.
- No external art/audio/model downloads.
- No cloned UI layout from a known game.
- Included visuals/audio are placeholders owned by this project; replace them only with newly created original work.
- Keep the game playable offline. No external LLM API is required for gameplay.
- Dynamic news/incidents use authored templates + simulation variables, not live generative AI.
- Build for keyboard/mouse first, then controller parity.

## Product pillars
1. **Temptation:** every powerful capability has a business reason to ship early.
2. **Consequence:** shortcuts generate incidents, regulation, staff churn, lawsuits, outages, and trust damage.
3. **Legibility:** the player can understand why metrics changed.
4. **Emergent satire:** humor comes from interacting systems, not references to real people.
5. **Replayability:** market conditions, staff, competitors, regulations, incidents, and research opportunities vary by seed.

## Completion rule
Do not attempt the entire game in one change. Complete the next unchecked prompt only. The repository contains 48 prompts designed to avoid architecture collapse.
