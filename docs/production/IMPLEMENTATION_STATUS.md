# Implementation status

Update this file after every prompt.

| Prompt | Status | Commit | Notes |
|---|---|---|---|
| P00 | DONE | (pending) | Godot 4.7.2 headless installed for CI. Fixed `smoke_test.gd` Variant-inference parse error (strict typing treats inference warning as error). Bootstrap + headless editor import both clean. No gameplay added. |
| P01 | DONE | (pending) | Added SceneRouter autoload (fade + error-safe ResourceLoader checks, busy-guard). Boot -> MainMenu -> Campaign flow; renamed main.tscn/main.gd to campaign.tscn/campaign.gd. Esc returns to menu from Campaign. Extended smoke_test.gd with scene-resolution, autoload-presence, and router-failure checks (moved autoload checks to `_initialize()`, since autoloads aren't attached yet during `_init()`). |
| P02 | DONE | (pending) | Added SettingsManager autoload (audio bus volumes, UI scale 80-160%, fullscreen/resolution, reduced motion, camera shake) persisted to `user://settings.cfg` with a version field and safe-default fallback on load failure. Added Music/SFX/UI audio buses (`default_bus_layout.tres`). Added Settings screen reachable from MainMenu with Apply/Reset/Back. Wired reduced_motion into SceneRouter fades and Campaign camera lerp (not just stored). Extended smoke_test.gd with clamping and save/load round-trip checks. |
| P03 | DONE | (pending) | Extracted camera into `CameraController` (class_name, own script): WASD + middle-drag pan, Q/E 90° rotation, wheel zoom, F focus-selected (currently resets to office origin; real entity focus deferred to prompts that add selectable entities), bounds-clamped pan. All motion uses exponential (frame-rate-independent) smoothing instead of the old `delta*constant` lerp. Campaign.gd now only owns pause/menu input and HUD. Added a runtime instantiation smoke check (loads main_menu/settings/campaign, adds to tree, processes a frame) catching errors plain existence checks miss. |
| P04 | DONE | (pending) | Added reusable `Hud` scene/script: anchor-driven top resource strip (cash/compute/power/trust/safety debt/date/pause/1x-2x-3x speed), bottom section nav (Build/Staff/Research/Models/Deployments/Company/World — placeholder-only, systems don't exist yet), left objectives panel, right contextual inspector wired to `EventBus.selection_changed`. Replaced campaign.gd's fixed-pixel-position HUD. Added a structural anchor check (not pixel-perfect) proving every strip is anchor-based so 1280x720/1920x1080 both work. Caught and fixed two bugs via the runtime instantiation smoke test: `Hud` class_name needed a fresh editor import pass before headless script runs could resolve it, and BottomBar's button paths were missing a `Margin` path segment. Fixed `tools/bootstrap.sh` to always do a headless editor import/rescan before running the smoke test, so this class-cache trap won't recur for future prompts. |
| P05 | TODO | | |
| P06 | TODO | | |
| P07 | TODO | | |
| P08 | TODO | | |
| P09 | TODO | | |
| P10 | TODO | | |
| P11 | TODO | | |
| P12 | TODO | | |
| P13 | TODO | | |
| P14 | TODO | | |
| P15 | TODO | | |
| P16 | TODO | | |
| P17 | TODO | | |
| P18 | TODO | | |
| P19 | TODO | | |
| P20 | TODO | | |
| P21 | TODO | | |
| P22 | TODO | | |
| P23 | TODO | | |
| P24 | TODO | | |
| P25 | TODO | | |
| P26 | TODO | | |
| P27 | TODO | | |
| P28 | TODO | | |
| P29 | TODO | | |
| P30 | TODO | | |
| P31 | TODO | | |
| P32 | TODO | | |
| P33 | TODO | | |
| P34 | TODO | | |
| P35 | TODO | | |
| P36 | TODO | | |
| P37 | TODO | | |
| P38 | TODO | | |
| P39 | TODO | | |
| P40 | TODO | | |
| P41 | TODO | | |
| P42 | TODO | | |
| P43 | TODO | | |
| P44 | TODO | | |
| P45 | TODO | | |
| P46 | TODO | | |
| P47 | TODO | | |
