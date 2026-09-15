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

## IncidentDefinition
`id, category, severity, prerequisites, weight, cooldown_days, title_template, body_template, choices[], tags[]`

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
