# Phase 04 — Look gráfico

Response to `ALIGNMENT_PENDING_CLAUDE_VISUAL_EXECUTION_MASTERPACK`'s `PHASE_04_LIGHTING.md`. Most of this phase was already delivered by this session's earlier, separate `REAL_GAME_VISUAL_OVERHAUL` pass (`docs/art/REAL_GAME_VISUAL_OVERHAUL_REPORT.md`) — this phase audited that work against the masterpack's specific checklist and fixed the one real gap (fog) and re-captured screenshots at the exact 4 hours requested.

## Checklist

| Item | Status |
|---|---|
| WorldEnvironment serio | Already done |
| SSAO | Already done (`REAL_GAME_VISUAL_OVERHAUL` pass) |
| SSIL si rendimiento lo permite | Already done — real GPU profile showed no cost at the realistic 20-staff scenario |
| SDFGI / GI según renderer | Deliberately off — real profiling showed ~9 more FPS cost than SSAO+SSIL combined at the stress scenario for a difference barely visible in this box interior (documented in the prior pass's report) |
| Glow moderado | Already done |
| Tone mapping | Already done (Filmic) |
| Fog sutil | **Missing → added this phase** |
| Sol horario | Already done — real day-night cycle tied to `GameState.calendar_hour` |
| Mañana/tarde/atardecer/noche | Already done |
| Luces interiores cálidas | Already done |
| Pantallas emisivas | Already done (`_apply_screen_glow()`) |

## Fix: fog

No fog existed at all before this phase. Added `env.fog_enabled` with day-night-reactive color (same lerp as ambient light). **First attempt at `fog_density = 0.008` was rendered, compared directly against the pre-fog baseline, and rejected** — it visibly washed out the SSAO contact shadows and desaturated the whole floor into flat gray in this small 14×10-unit enclosed room (see `phase-04-fog-rejected-first-attempt.png`, a stacked before/after). Reduced to `0.0015`, re-rendered, and confirmed it now reads as genuinely subtle atmosphere with no visible loss of the existing contrast/AO work.

## Screenshots

Real windowed renders (Forward+/Vulkan) at the 4 exact hours the phase asks for:
- `phase-04-0800.png` — morning
- `phase-04-1200.png` — noon
- `phase-04-1800.png` — evening
- `phase-04-2200.png` — night

(Note: the in-scene HUD clock label in these captures doesn't always match the requested hour — a known test-script artifact from directly setting `GameState.calendar_hour` instead of advancing it through `SimClock`'s real tick, which is what actually fires the signal the HUD label listens for. The environment/lighting itself reads `GameState.calendar_hour` directly every frame and is correct; only the HUD text widget in this specific synthetic test setup lags. Established and documented earlier this session — not a gameplay bug.)

## Verification

`tools/bootstrap.sh` full smoke suite — green after the fog change.
