extends Node

## Offline authored-template news/social feed (P33): listens for
## already-emitted simulation events and posts a headline built entirely
## from data/news_templates.json + current simulation variables. No
## network call of any kind is ever made here or anywhere in this
## project — this is pure local string substitution (String.format()),
## deterministic given the same sequence of events for a given
## campaign_seed (template/outlet picks go through SimClock's named RNG
## streams, same discipline as every other content-selection system).

## Fictional publications only — never a real news outlet, platform, or
## service name.
const OUTLETS: Array[String] = [
    "The Daily Ledger", "Signal & Noise", "Compute Weekly", "The Quiet Part Loud", "Northbound Wire",
]
const MAX_FEED_ENTRIES: int = 200

func _ready() -> void:
    EventBus.incident_resolved.connect(_on_incident_resolved)
    EventBus.rival_launched.connect(_on_rival_launched)
    EventBus.funding_round_accepted.connect(_on_funding_round_accepted)
    EventBus.legal_case_filed.connect(_on_legal_case_filed)
    EventBus.deployment_churn_event.connect(_on_deployment_churn_event)
    EventBus.audit_triggered.connect(_on_audit_triggered)
    EventBus.datacenter_tier_purchased.connect(_on_datacenter_tier_purchased)

func _post(category: String, values: Dictionary) -> void:
    var templates: Array = NewsTemplateCatalog.templates_for(category)
    if templates.is_empty():
        return
    var filled: Dictionary = values.duplicate()
    filled["outlet"] = String(SimClock.pick_from("news_outlet", OUTLETS))
    filled["day"] = GameState.calendar_day
    var template: String = String(SimClock.pick_from("news_template_%s" % category, templates))
    var headline: String = String(template).format(filled)
    GameState.news_feed.append({"day": GameState.calendar_day, "category": category, "headline": headline})
    while GameState.news_feed.size() > MAX_FEED_ENTRIES:
        GameState.news_feed.pop_front()
    EventBus.news_posted.emit(headline)

func _on_incident_resolved(incident_id: String, choice_id: String) -> void:
    var def: Dictionary = IncidentCatalog.get_def(incident_id)
    var choice_label: String = ""
    for c: Variant in (def.get("choices", []) as Array):
        if String((c as Dictionary).get("id", "")) == choice_id:
            choice_label = String((c as Dictionary).get("label", ""))
            break
    _post("incident_resolved", {"incident_title": def.get("title", "?"), "choice_label": choice_label})

func _on_rival_launched(rival_id: String, generation: int) -> void:
    var rival_name: String = String(RivalManager.find_rival(rival_id).get("name", "A rival"))
    _post("rival_launched", {"rival_name": rival_name, "generation": generation})

func _on_funding_round_accepted(round_id: String) -> void:
    var def: Dictionary = FundingRoundCatalog.get_def(round_id)
    _post("funding_round_accepted", {"round_name": def.get("name", round_id), "amount": int(def.get("amount", 0))})

func _on_legal_case_filed(case_type_id: String) -> void:
    var def: Dictionary = LegalCaseTypeCatalog.get_def(case_type_id)
    _post("legal_case_filed", {"case_name": def.get("name", case_type_id)})

func _on_deployment_churn_event(deployment_id: String, churned_fraction: float) -> void:
    var deployment: Dictionary = {}
    for d: Variant in GameState.deployments:
        if String((d as Dictionary).get("id", "")) == deployment_id:
            deployment = d
            break
    var deployment_label: String = ModelManager.model_name(String(deployment.get("model_id", "")))
    _post("deployment_churn_event", {"deployment_label": deployment_label, "churn_pct": int(round(churned_fraction * 100.0))})

func _on_audit_triggered() -> void:
    _post("audit_triggered", {})

func _on_datacenter_tier_purchased(tier_id: String) -> void:
    var def: Dictionary = DatacenterTierCatalog.get_def(tier_id)
    _post("datacenter_tier_purchased", {"tier_name": def.get("name", tier_id)})
