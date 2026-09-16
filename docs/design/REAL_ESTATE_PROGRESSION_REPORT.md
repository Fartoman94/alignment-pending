# Real estate & company progression report

Response to the `ALIGNMENT_PENDING_FULL_CODE_BUNDLE` package, specifically prompts 35 ("Garage inicial y progresión a oficinas"), 37 ("Ciudad, distritos y bienes raíces"), and the roster-closing part of 36 ("NPCs con función real"). Prompts 01-31 in that bundle are the same finalization pack already completed across earlier sessions (same base commit, same content) — not re-done. Prompt 39 (GLB integration/gallery) was also already done in the earlier 3D-asset-integration pass. Prompt 38 (landing page/branding/screen audit) is explicitly **not** attempted this pass — see "Deferred" below.

## What this pass adds

A real, playable garage → corporate-building progression layer on top of the existing simulation, plus closing a roster gap two earlier passes had already flagged (`ceo`/`cfo`/`hr`/`legal` had character models with no gameplay role to attach them to).

### Data + catalogs (`game/data/districts.json`, `buildings.json`, `company_tiers.json`, `office_upgrades.json`)
- **Districts** (6): rent/buy multipliers, prestige, talent, regulation — the location stats prompt 37 asks for.
- **Buildings** (5): `garage_start` (owned, free, canon campaign start) → `loft_alpha` → `office_hub_12` → `meridian_tower_floor` → `north_quarter_hq`, each tagged with a district, a lease mode (`owned`/`rent`/`rent_or_buy`), and a company tier.
- **Company tiers** (6, including `garage_plus` — an in-place garage upgrade with no separate building): `employee_cap` and `unlock_requirements` (cash + trust).
- **Office upgrades** (7): in-place renovations to whichever building is current, each with `morale`/`employee_cap`/`trust` effects — narrowed from the bundle's original wider effect vocabulary (which also proposed `compute`/`power_use`/`coordination`) to the 3 that have a real, direct GameState hook, rather than inventing new unused stats.
- 4 new `DataValidator` record types (district/building/company-tier/office-upgrade), cross-referencing `building.district`/`building.tier` against the other catalogs — same rigor as every other content type in this project.

### `RealEstateManager` autoload (new)
- `move_to(building_id, buy)` — relocates, deducting a relocation cost (destination's `purchase_cost` if buying, plus a moving-overhead fraction always charged) gated by the destination company tier's cash/trust unlock and by affordability. Clears `office_upgrades_purchased` on every move — a new space doesn't inherit the old one's coffee corner, so upgrades stay a real, repeated investment instead of compounding forever.
- `effective_employee_cap()` = current tier's base cap + every purchased upgrade's `employee_cap` bonus. `StaffManager.hire()` is now gated by this — real capacity, not a UI-only number.
- `daily_rent_cost()` feeds `EconomyManager.rent_cost()`, replacing a flat `$300/day` placeholder constant that's been in the ledger since the original finalization pass. The garage (owned) pays nothing.
- District `talent` nudges `StaffManager`'s generated-candidate skill rolls; district `prestige`/`regulation` apply a small, bounded daily drift to `public_trust`/`regulatory_pressure` — secondary modifiers layered on top of each stat's existing primary driver, never the dominant one (see the "clamp-order" note under Testing).
- `passive_morale_bonus_per_day()` feeds `StaffManager`'s existing daily morale-drift step.

### Roster gap closed (prompt 36)
Added `legal_specialist`, `hr_partner`, `ceo`, `cfo` to `data/staff_roles.json` — the 4 pack character models (`legal.glb`/`hr.glb`/`ceo.glb`/`cfo.glb`) that two earlier passes (3D-asset-integration, NPC-visual-rework) had already imported and validated but never wired into the hireable roster, for lack of a gameplay system to attach them to. Each gets a **real, bounded, mechanical** effect, not just a name and a salary:
- `legal_specialist` — added to `LegalManager`'s compliance-mitigation headcount (previously `safety_analyst`-only), directly reducing daily legal exposure gain.
- `hr_partner` — widens `StaffManager`'s real candidate pool (`effective_candidate_pool_size()`), capped, so a hired HR partner visibly surfaces more hiring offers on the next refresh.
- `ceo` — mitigates `BoardManager`'s daily control-pressure accrual.
- `cfo` — mitigates `BoardManager`'s daily low-runway pressure accrual.

`junior`/`manager` from the bundle's own role list were **not** added as separate roles — they'd duplicate the existing `support_specialist`/`product_manager` roles (which already claim `junior.glb`/`manager.glb` and cover the same niches), so adding them would've been redundant clones, not new content.

### Visual progression (`campaign.gd`)
The buildable grid/navmesh footprint never changes per tier — resizing it could strand an already-placed building from an earlier tier outside a shrunk floor, a correctness risk far beyond this pass's scope. What *does* change, live, the moment `RealEstateManager.move_to()` fires (`EventBus.real_estate_moved` → `_rebuild_office_visuals()`, no scene reload needed): wall/floor/trim palette and window glow intensity, tiered garage → baseline → premium, plus a literal garage-door prop (with hazard-yellow trim) that only exists at the `garage`/`garage_plus` tiers — the one unmistakable "this is still the garage" signal, removed the moment the company moves out. Screenshots below confirm this rendering live, not just in data.

### UI (`hud.gd`'s World panel)
A new "Real estate" section: current building/district/staff-vs-cap/rent, the current building's office upgrades (buy buttons, gated by affordability and already-installed state), and every other building available (rent and/or buy buttons, gated by `can_move_to()`, showing cost/capacity/district stats). Nested inside the existing World panel rather than a 9th bottom-nav tab — the bundle's own brief calls it the "World / Real Estate" screen, and the bottom nav already has 8 buttons.

All new strings added to `data/locale_es.json` (32 new entries, including the new building/district/upgrade/role display names), maintaining this project's full-coverage i18n discipline rather than leaving new UI text English-only under `es`.

## Deferred (honest scope boundary)

- **Prompt 38 (landing/branding/screen audit)**: not attempted this pass. It's a marketing-facing deliverable (a landing page, a screen-by-screen consistency pass across Build/Staff/Research/Models/Deployments/Company/World/Glossary) largely orthogonal to the gameplay-progression system this pass focused on, and the master prompt's own numbered objectives put "progresión inmobiliaria" (#2) and "ciudad y distritos" (#4) ahead of "landing/branding" (#6). Worth its own pass.
- **A literal city map**: this implementation keeps the same "abstract management screen, not a spatial map" pattern `DatacenterManager` already established for remote datacenter tiers — a real, itemized listing with real stats/filters-by-affordability, not a clickable 2D/3D city. Building a literal map view is a much larger UI/rendering undertaking the brief's own UI section ("listado de inmuebles, filtros por distrito") describes as a listing anyway, not a map.
- **`garage_plus` has no dedicated visual state** — mechanically it's reached via `office_upgrades_purchased` (specifically `extra_desks`, matching its `employee_cap` bump) while still occupying `garage_start`, and the garage-door/grungy palette (tied to `company_tier == "garage"` or `"garage_plus"`) already covers it; no separate art treatment was warranted for a tier that isn't a distinct building.
- **Talent/prestige/regulation are secondary modifiers, not new subsystems**: they nudge existing GameState scalars (trust, regulatory pressure, candidate skill rolls) by small bounded amounts. A deeper "reputation" or "local politics" system was out of scope.

## Testing

- `tools/bootstrap.sh`: green throughout, including 8 new dedicated assertions (catalog seeding, garage defaults, hire-cap gating, `move_to()`'s cost/cap/rent/upgrade-clearing behavior, save/load persistence, and the 4 new roles' real mechanical effects) plus fixes to 4 pre-existing assertions that this pass's new daily trust/regulatory-pressure drift genuinely changed the expected values of (not bugs in the new code — those assertions now account for the new driver, the same way they already isolated the pre-existing world-mood/automation-policy drivers).
- One real clamp-ordering subtlety found and documented rather than papered over: `RealEstateManager` connects to `EventBub.day_advanced` before `RegulatorManager` (autoload declaration order), and the garage's district (`industrial`, regulation 20 — below the 50 midpoint) drifts `regulatory_pressure` *down*. In the one test that pins `regulatory_pressure` at exactly `0.0` before the tick, that negative drift is floor-clamped away before `RegulatorManager`'s own positive delta applies — so it contributes nothing on that specific tick. Documented in-line in the test rather than "fixed" with a formula that would've been wrong.
- Full `tools/export_release.sh`: Linux + Windows export, packaged-binary smoke (`--qa-exported-smoke`) green — 30 (up from 26) `res://src/data` catalog scripts confirmed loading from the embedded package, including the 4 new ones.
- Real (non-headless) rendering, not just tests: `docs/design/screenshots/real_estate_garage_office.png` (fresh campaign, garage door + hazard trim visible), `real_estate_premium_office.png` (after a real `move_to("meridian_tower_floor", true)` call — brighter walls, orange trim, garage door gone, cash correctly deducted in the HUD), `real_estate_world_panel.png` (the real World panel showing "Meridian Tower Floor (Downtown district) — 0/50 staff" after the same move).

## Performance

No new per-frame cost: `RealEstateManager`'s daily recompute is O(purchased upgrades) (small, bounded array), same order of magnitude as `DatacenterManager`'s existing tier-bonus recompute. The office-visual rebuild only runs on an explicit player move (rare), not every frame. Not re-profiled with `gpu_profile.gd` this pass — nothing here touches per-agent or per-buildable rendering cost, the two things that profiler measures.
