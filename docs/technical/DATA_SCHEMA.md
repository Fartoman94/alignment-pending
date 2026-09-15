# Data schemas

## CampaignState
```json
{
  "save_version": 2,
  "campaign_id": "uuid",
  "seed": 12345,
  "calendar": {"day": 1, "hour": 9, "minute": 0},
  "company": {},
  "staff": [],
  "buildings": [],
  "research": {},
  "models": [],
  "deployments": [],
  "rivals": [],
  "world": {},
  "event_history": []
}
```

## ModelArtifact
`id, name, generation, architecture_tier, capability, reliability, safety_confidence, cost_efficiency, latency_efficiency, autonomy, interpretability, latent_risk, evals_completed, training_cost, created_at`

## StaffMember
`id, generated_name, role, skills, salary, morale, fatigue, values, relationships, assigned_task, traits, is_lead, hire_date`

`traits` is a list of `StaffTraitCatalog` ids (bounded skill/morale/fatigue
modifiers, see `data/staff_traits.json`). `relationships` is a list of
`{with: staff_id, affinity: float}` entries, `affinity` clamped to
`[-20, 20]`. `is_lead` marks the one promoted department lead per role
(`StaffManager.promote()`), granting a fixed department-wide skill bonus.

## Rival
`id, name, doctrine, generation, progress_days, cycle_duration_days`
(v2, P26: `GameState.rivals` is an array of 3-5 of these — see
`SaveManager._migrate_v1_to_v2()` for the v1 single-`rival` migration).
`RivalManager.effective_launch_days()` applies a bounded catch-up speedup
to whichever rivals are behind `RivalManager.leading_generation()`.

## LegalCaseType
Config (`data/legal_case_types.json`, one array of abstract archetypes —
no real plaintiffs): `id, name, trigger_min_exposure, case_deadline_days,
cooldown_days, injunction_probability_per_day, settle, fight, injunction`.
Active instance: `GameState.active_legal_case = {case_type_id,
instance_id, filed_day, deadline_day}`. Resolved either by the player
(`LegalManager.resolve_case("settle"|"fight")`) or by the system (a daily
`injunction_probability_per_day` roll, or hitting `deadline_day` — so a
case can never sit open forever); every path applies one of the type's
own bounded, data-driven effect sets.

## AgentPermission
Config (`data/agent_permissions.json`): `id, name, category,
productivity_description, risk_description, productivity_effects,
risk_effects` — `productivity_effects` and `risk_effects` are both
required to be non-empty (every autonomy permission has a gain and an
explicit risk, enforced by `DataValidator`). Granted per-deployment: a
deployment's `agent_permissions` field is an array of permission ids
(`AgentPermissionManager.grant()`/`revoke()`); both effect sets apply
daily to every deployment holding that permission.

## WorkforcePolicy
Config (`data/workforce_policies.json`): `id, name, description,
cash_per_pressure, morale_per_pressure, trust_per_pressure,
safety_debt_per_pressure`, applied daily scaled by
`AutomationManager.automation_pressure()` (total granted
`AgentPermission`s across every deployment). `GameState.workforce_policy`
picks the active one (default `"status_quo"`, no effect). `DataValidator`
rejects a policy set where one policy is at-least-as-good as every other
on every axis and strictly better on at least one — no single policy may
be the forced "correct" answer.

## DatacenterTier
Config (`data/datacenter_tiers.json` + `DatacenterTierCatalog`): `id,
name, description, cost, compute_capacity_bonus, operating_cost_per_day`,
purchased strictly in order (`DatacenterTierCatalog.ORDER`). Abstract —
purchasing one adds a large `GameState.datacenter_compute_bonus` (read by
`GameState.effective_compute_capacity()`, not throttled by the local
office's heat simulation) and a recurring `datacenter_operating_cost`
(read by `EconomyManager.daily_ledger()`), so late-game compute scales
without placing individual racks.

## WorldVariable
Config (`data/world_variables.json` + `WorldVariableCatalog`): `id, name,
description, effect_description, midpoint, amplitude, period_days`.
`WorldStateManager.value(id)` follows `midpoint + amplitude *
sin(2*PI*(calendar_day + phase_offset)/period_days)`, always within
[0, 100] (`DataValidator` requires `amplitude <= min(midpoint,
100-midpoint)`). `phase_offset` (`GameState.world_state_phase_offsets`) is
rolled once per campaign from `campaign_seed`, so different campaigns see
differently-shaped cycles. Each variable feeds one concrete, named effect:
`energy_price` → `EconomyManager` ledger line, `chip_supply` →
`GameState.effective_compute_capacity()`, `talent_market` →
`StaffManager` candidate salaries, `public_mood` → a small daily
`public_trust` drift, `regulation_climate` → `RegulatorManager`'s
pressure-accrual rate.

## SubscriptionPlan
Config (`data/subscription_plans.json` + `SubscriptionPlanCatalog`):
`id, name, description, price, quota_users,
enterprise_contract_revenue_per_day, min_reliability_for_contract`.
A deployment's `plan_id` picks one (`DeploymentPlanManager.set_plan()`);
`quota_users` is a hard seat cap `RevenueManager.compute_breakdown()`
enforces (demand above it is turned away, not discounted).
`enterprise_contract_signed` (bool, `DeploymentPlanManager
.sign_enterprise_contract()`, gated by `min_reliability_for_contract` and
a one-time cost) adds the plan's flat daily revenue bonus. A deployment's
`capacity_reserved` (float, `DeploymentPlanManager.reserve_capacity()`)
permanently occupies that much compute (`GameState
.recompute_compute_used()`), and `churned_fraction` (0-1, bounded,
raised by sustained low `rate_limit` — see `DeploymentPlanManager
._on_day_advanced()`) permanently shrinks its addressable market.
`RevenueManager.predicted_range()` compares current vs. full-rate-limit
load/revenue for the pricing UI.

## NewsTemplate
Config (`data/news_templates.json` + `NewsTemplateCatalog`): `id,
category, template` — `template` is a `String.format()` pattern (e.g.
`"{outlet}: {rival_name} ships..."`), never live-generated text.
`category` must be one of `DataValidator.NEWS_TEMPLATE_CATEGORIES`.
`NewsFeedManager` listens for the matching `EventBus` signal, fills the
template from current simulation state plus a fictional outlet name
(`NewsFeedManager.OUTLETS` — never a real publication), and appends
`{day, category, headline}` to `GameState.news_feed` (capped at
`MAX_FEED_ENTRIES`, oldest dropped). Deterministic per campaign_seed:
outlet/template picks go through `SimClock`'s named RNG streams. No
network call is made anywhere in this project.

## CampaignAct
Config (`data/campaign_acts.json` + `CampaignActCatalog`, exactly 5,
matching `docs/design/WORLD_AND_NARRATIVE.md`'s "Narrative acts"):
`number, name, tagline, milestone_description`. `GameState.current_act`
is a ratchet (1-5, never regresses) advanced by `CampaignActManager`
purely from capability/scale milestones already tracked elsewhere
(first model deployed, first datacenter tier, first autonomy permission
granted, capability or safety_debt crossing a threshold) — never a
calendar timer.

## TutorialStep
Config (`data/tutorial_steps.json` + `TutorialStepCatalog`, file order =
sequence): `id, title, body, completion_metric`. `completion_metric` is
one of `DataValidator.TUTORIAL_STEP_METRICS` — a fact already tracked
elsewhere (`server_rack_built`, `staff_hired`, `model_trained`,
`model_evaluated`, `model_deployed`) or `"manual"` (only completes when
dismissed). `TutorialManager.current_step()` is the first incomplete step,
or `{}` once done or skipped (`GameState.tutorial_skipped_all`). Every
step — including "optional" ones — can be dismissed individually via
`dismiss_step()`, recorded in `GameState.tutorial_completed_steps`.

## GlossaryTerm
`data/glossary_terms.json` + `GlossaryCatalog`: `id, term, definition`,
listed alphabetically by `term`.

## IncidentDefinition
`id, category, severity, prerequisites, weight, cooldown_days, title,
body, choices[]` (`data/events_seed.json`, 83+ incidents across 12
categories). Each choice: `id, label, effects` plus optionally
`follow_up_incident_id` + `follow_up_delay_days` (P34) — schedules
another incident to fire automatically once the delay elapses
(`GameState.scheduled_incidents`, processed unconditionally in
`IncidentManager._on_day_advanced()`, ahead of the normal weighted-random
pick). `DataValidator` cross-checks `follow_up_incident_id` against every
other id in the file and rejects a choice that follows up on its own
incident.

## FundingRound
`id, name, min_valuation, amount, equity_pct, obligation_per_day` — raised
strictly in order (`FundingRoundCatalog.ORDER`), gated by
`BoardManager.valuation()`. `equity_pct` reduces
`GameState.board_control_pct`; `obligation_per_day` accrues into
`GameState.investor_obligation_per_day`, which `EconomyManager` deducts
daily and reports in `daily_ledger()`.

## BoardDemand
Config: `id, name, demand_threshold, demand_deadline_days, ask,
yield_to_board, hold_the_line` (a single object — one board, like the
regulator track). Active instance: `GameState.active_board_demand =
{id, name, ask, triggered_day, deadline_day}`. Resolving one
(`BoardManager.resolve_demand()`) always applies a data-driven effect —
never an ending.

## Save compatibility
Never serialize Node paths as authoritative domain identifiers. Use stable string/UUID IDs.
