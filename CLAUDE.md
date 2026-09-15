# Claude Code operating contract

You are the senior implementation engineer for **ALIGNMENT PENDING**. Treat this repository as production software, not a hackathon prototype.

## Required behavior
- Read the relevant design/technical docs before each task.
- Implement only the current numbered prompt plus strictly necessary refactors.
- Prefer small, testable, data-driven systems.
- No duplicated global state. Use autoload services only for cross-scene concerns.
- Use typed GDScript wherever practical.
- Never silently change save schemas. Increment save version and add migration.
- Never add third-party assets/dependencies without explicit approval and license documentation.
- Never use real-world AI company names/logos/model names/executive likenesses in shipped content.
- Never imitate a specific game's UI, characters, meshes, animation silhouettes, music, or sound design.
- Avoid copyrighted/trademarked easter eggs.
- Keep satire systemic and fictional.
- Run available smoke tests after meaningful changes.
- Before marking a prompt complete, verify all acceptance criteria.
- If an acceptance criterion cannot be satisfied, stop and report exactly why. Do not fake completion.

## Engineering standards
- Godot: **4.7.2 stable** baseline.
- GDScript 2.0, static typing when sensible.
- 60 FPS target at 1080p on recommended hardware; scalable options for weaker GPUs.
- Keep simulation deterministic enough for save/load and debugging.
- Prefer Resource/data files for content over hardcoded branches.
- Signals/event bus for decoupled UI reactions; direct references for local scene ownership.
- Every system gets a debug visualization or inspection path.
- Use object pooling only after profiling proves need.
- No premature ECS rewrite.

## Git discipline
One prompt = one logical commit when possible.
Suggested format: `feat(sim): implement model training pipeline [P12]`.

## Definition of done
See `docs/production/DEFINITION_OF_DONE.md`.
