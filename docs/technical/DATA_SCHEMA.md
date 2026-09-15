# Data schemas

## CampaignState
```json
{
  "save_version": 1,
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
`id, generated_name, role, skills, salary, morale, fatigue, values, relationships, assigned_task, traits, hire_date`

## IncidentDefinition
`id, category, severity, prerequisites, weight, cooldown_days, title_template, body_template, choices[], tags[]`

## Save compatibility
Never serialize Node paths as authoritative domain identifiers. Use stable string/UUID IDs.
