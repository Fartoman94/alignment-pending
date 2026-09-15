# QA matrix

## Critical flows
| Flow | Checks |
|---|---|
| New campaign | seed, difficulty, company name, initial office |
| Build | preview, rotation, collision, cost, refund, pathing |
| Staff | hire, assign, pay, fire, resign, save/load |
| Train | configure, start, pause game, finish, cancel, insufficient compute |
| Evaluate | uncertainty, repeat eval, cost, warning persistence |
| Deploy | internal/beta/public, staged rollout, rate limit, rollback |
| Incident | trigger, pause, choice, delayed effect, history |
| Finance | ledger, runway, funding, bankruptcy recovery |
| Save | manual, autosave rotation, corrupt newest, migration |
| Settings | resolution, audio, UI scale, remapping, reduced motion |
| Endings | each family reachable, epilogue variables correct |

## Resolution test set
1280x720, 1600x900, 1920x1080, 2560x1440, ultrawide sanity check.

## Soak tests
- 2 simulated in-game years at 4x headless where possible.
- 150 staff stress scene for 20 minutes.
- Repeated save/load 100 cycles in test fixture.

## Accessibility regression checklist (P42)
Every item below is enforced by an automated check in `game/tests/smoke_test.gd`'s P42 block (or, for the two flagged, an earlier prompt's block) — re-run `tools/bootstrap.sh` after any UI/input change and treat any of these regressing as a blocking bug, not a nice-to-have.

| Item | How it's verified |
|---|---|
| UI scale 80-160% | P02 block: `SettingsManager.ui_scale` clamps to range and drives `content_scale_factor`. |
| Full remapping | P42 block: every `SettingsManager.REMAPPABLE_ACTIONS` entry has a default `InputMap` binding at boot; `rebind_action()` changes the binding, persists across a settings save/load round-trip, and `reset_to_defaults()` restores every default. |
| Reduced motion | P02 block: gates `SceneRouter` fade duration and `CameraController`'s focus lerp. |
| Camera shake toggle | P02 block: `SettingsManager.camera_shake_enabled` gates `CameraController`'s shake. |
| High contrast mode | P42 block: enabling `high_contrast` installs a procedurally-built, maximum-contrast `Theme` on the root viewport; disabling it clears the override. |
| Colorblind-independent icons | P42 block: `BuildController`'s ghost preview (green=valid/red=invalid, a color-only signal) grows a redundant "OK"/"X" `Label3D` when `colorblind_mode` is on. |
| Pause while reading events | P42 block: with `pause_on_incident` on, every incident (not just P0/critical) force-pauses the sim, verified against a real non-critical incident trigger. |
| Readable tooltip timing | P42 block: `SettingsManager.tooltip_delay_sec` (0.1-2.0s) writes through to the engine's `gui/timers/tooltip_delay_sec` project setting. |
