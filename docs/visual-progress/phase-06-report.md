# Phase 06 — UI

Response to `ALIGNMENT_PENDING_CLAUDE_VISUAL_EXECUTION_MASTERPACK`'s `PHASE_06_UI.md`. Most of this checklist was already satisfied by earlier passes (this session's "visual-target"/"visual audit" work and before).

## Checklist

| Item | Status |
|---|---|
| HUD más compacto | Already done — two-row top bar, resource chips |
| Iconos | Already done — chip icons, section nav icons |
| Panel contextual | Already done — `Inspector`/`RightPanel` |
| Roster sólo al abrir Staff | Already true — `_show_staff_panel()` is only ever called on demand (`_on_section_pressed`, hire/negotiate callbacks), confirmed by reading the call graph, not assumed |
| Cards bonitas | Already done — `_build_staff_card()` (portrait/skill bars/morale/quote) |
| Tabs consistentes | Already done — 7 bottom-nav sections, one dispatch point |
| **Transitions 120-180ms** | **Missing → added this phase** |
| No tapar escena principal | Already done (prior visual-audit pass fixed the last real overflow bug) |

## Fix: panel transitions

Bottom-nav tab switches (`Hud._on_section_pressed()`) used to swap `RightPanel`'s content instantly — `_clear_dynamic_content()` then an immediate rebuild, no animation. Added a 150ms fade-in (`_fade_in_dynamic_content()`, a `Tween` on `_dynamic_content.modulate.a`), inside the phase's requested 120-180ms range, gated by `SettingsManager.reduced_motion` (the same accessibility setting already used elsewhere in this project, e.g. the main menu's terminal cursor).

**Honest scope note**: this is hooked once, at the single common dispatch point for bottom-nav tab switches — the most visible, most frequent transition. A few narrower internal panel refreshes reached through other call sites (e.g. `_show_staff_panel()` being called again directly after a successful hire, not through `_on_section_pressed`) were not individually retrofitted with the same fade. Not claiming every possible panel refresh in the codebase animates — just the primary nav flow the phase is actually about.

## Verification

- Live instrumented capture: called `_on_section_pressed("Staff")` directly and sampled `_dynamic_content.modulate.a` every frame for 12 frames — a clean 0.000 → 1.000 ramp completing in ~11 frames (≈150-180ms at 60fps), confirmed with `reduced_motion` explicitly forced off.
- Separately confirmed the accessibility gate itself: with the environment's actual persisted `reduced_motion = true` setting (left on from earlier accessibility testing this session), the same call left `modulate.a` at `1.0` on every sampled frame — no animation, immediate full visibility, exactly the intended reduced-motion behavior.
- `tools/bootstrap.sh` full smoke suite — green.
