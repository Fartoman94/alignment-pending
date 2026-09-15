# Performance budget

## Target
60 FPS at 1080p on a mainstream 4-core CPU and modest dedicated GPU; scalable to integrated GPUs through lower shadows/effects.

## Budgets
- Visible staff in one office: 100 target, 150 stress test.
- Active navigation agents: stagger path queries.
- Draw calls: batch repeated props where practical; MultiMesh for rack LEDs/repeated decoration after profiling.
- Physics: simplified collision shapes, no unnecessary rigid bodies.
- UI: avoid rebuilding large trees each frame.
- Simulation: target <4 ms average CPU at 1x, <10 ms at 4x on reference machine.

## LOD
Character/prop LOD can be added after vertical slice. No micro-optimization before profiler evidence.

## Stress scenes
- 150 staff + 500 props.
- 5,000 user cohorts simulated abstractly.
- 100 pending events in history.
- 20 rival models.
