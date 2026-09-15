# Technical Architecture

## Engine
Godot 4.7.2 stable baseline. Use standard GDScript project, not C# unless a measured need appears.

## Render strategy
Default to Compatibility or Mobile-friendly path during development for broad hardware support; allow Forward+ option if effects justify it. Visual style is low-poly, so design does not depend on heavyweight rendering.

## Layers
### Presentation
Scenes, 3D meshes, camera, UI, audio.
### Domain simulation
Pure-ish GDScript models/services for economy, research, events, rivals, employees.
### Data
Resources/JSON definitions for items, events, research, roles and balance.
### Persistence
Save manager serializes domain state through versioned DTO dictionaries.

## Autoloads
- `EventBus`: cross-system signals only.
- `GameState`: campaign state owner/coordinator.
- `SaveManager`: persistence/migrations.
- `AudioManager`: buses/music state.
- `SceneRouter`: scene transitions.

Keep autoload count small.

## Update cadence
- Visual `_process`: frame rate.
- Character movement `_physics_process`.
- Simulation: fixed logical tick, e.g. 0.25 game-minutes per tick depending speed.
- Daily/weekly systems subscribe to calendar events.

## Data-driven content
Events/research/buildables should live as Resource definitions or validated JSON. Logic uses tags/conditions rather than giant match statements.

## Determinism
Campaign stores seed + RNG stream states when necessary. Avoid using global random calls in simulation code.

## Error policy
Fail loudly in development. Validate data on startup in debug builds. User-facing release recovers with safe defaults only where progress cannot be corrupted.
