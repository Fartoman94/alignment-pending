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
