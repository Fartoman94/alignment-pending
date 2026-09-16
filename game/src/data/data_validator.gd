class_name DataValidator
extends RefCounted

## Startup validator for JSON content data: duplicate IDs, missing required
## fields, invalid numeric ranges. Only validates fields the current data
## actually uses (see docs/technical/DATA_SCHEMA.md).

## P47 release-candidate quality gate: a project-wide sweep for real
## AI-company/product names across every data/*.json file (not just the
## rival-name and credits checks earlier prompts already had), matched on
## whole words so it doesn't false-positive on ordinary English words
## that happen to contain one as a substring (e.g. "metadata" vs "meta").
const REAL_WORLD_MARKS: Array[String] = [
    "openai", "anthropic", "google", "deepmind", "meta", "microsoft", "xai",
    "mistral", "cohere", "claude", "chatgpt", "gpt", "gemini", "llama",
    "copilot", "grok", "bard", "palm", "nvidia", "amazon", "apple",
]

const EVENT_CATEGORIES: Array[String] = [
    "reliability", "security", "misuse", "hallucination", "privacy",
    "employee", "infrastructure", "legal", "media", "market",
    "autonomous-agent", "governance",
]
# P0 (crisis) .. P3 (minor), matching the P0/P1/P2 release-gate severities
# already used in docs/production/QA_MATRIX.md, extended one tier lower.
const EVENT_SEVERITY_MIN: int = 0
const EVENT_SEVERITY_MAX: int = 3
const EVENT_MIN_CHOICES: int = 2
const EVENT_MAX_CHOICES: int = 4
const EVENT_REQUIRED_FIELDS: Array[String] = ["id", "category", "severity", "weight", "cooldown_days", "prerequisites", "title", "body", "choices"]
const EVENT_CHOICE_REQUIRED_FIELDS: Array[String] = ["id", "label", "effects"]
const EVENT_EFFECT_KEYS: Array[String] = ["cash", "public_trust", "safety_debt", "regulatory_pressure"]
# IncidentManager's generic min_<metric>/max_<metric> prerequisite vocabulary.
const EVENT_CONDITION_METRICS: Array[String] = [
    "safety_debt", "public_trust", "cash", "deployed_models_count",
    "staff_count", "models_count", "calendar_day", "compute_used_ratio",
    "total_user_scale", "total_incident_exposure",
    "rival_generation", "rival_pressure", "regulatory_pressure",
]

const BUILDABLE_REQUIRED_FIELDS: Array[String] = ["id", "name", "category", "footprint", "cost", "refund_ratio"]

const STAFF_ROLE_REQUIRED_FIELDS: Array[String] = ["id", "name", "base_salary_min", "base_salary_max", "primary_skill", "visual_color"]
const STAFF_SKILL_KEYS: Array[String] = ["capability", "engineering", "operations", "safety", "communication"]

# P24: staff depth. Traits must have bounded impact (acceptance criterion),
# so these caps are enforced at data-load time, not just by convention.
const STAFF_TRAIT_REQUIRED_FIELDS: Array[String] = ["id", "name", "skill_deltas", "morale_delta", "fatigue_resistance"]
const STAFF_TRAIT_SKILL_DELTA_MAX: float = 15.0
const STAFF_TRAIT_MORALE_DELTA_MAX: float = 10.0
const STAFF_TRAIT_FATIGUE_RESISTANCE_MIN: float = 0.7
const STAFF_TRAIT_FATIGUE_RESISTANCE_MAX: float = 1.3

const WORK_TASK_REQUIRED_FIELDS: Array[String] = ["id", "name", "category", "required_buildable", "required_skill", "duration_minutes"]

const RESEARCH_NODE_REQUIRED_FIELDS: Array[String] = ["id", "name", "branch", "cost", "duration_minutes", "prerequisites", "unlock_effect"]
const RESEARCH_BRANCHES: Array[String] = ["capability", "efficiency", "safety", "interpretability", "infrastructure", "organization"]
const RESEARCH_EFFECT_TYPES: Array[String] = ["compute_bonus", "safety_debt_delta", "trust_delta"]

const MODEL_TIER_REQUIRED_FIELDS: Array[String] = ["id", "name", "cost", "duration_minutes", "capability_base", "safety_base", "autonomy_base", "cost_efficiency_base"]
const MODEL_TIER_STAT_FIELDS: Array[String] = ["capability_base", "safety_base", "autonomy_base", "cost_efficiency_base"]

const DEPLOYMENT_MODE_REQUIRED_FIELDS: Array[String] = ["id", "name", "base_user_scale", "exposure_multiplier", "rollout_days", "inference_compute_per_1k_users"]

const USER_SEGMENT_REQUIRED_FIELDS: Array[String] = ["id", "name", "share_of_market", "max_price", "elasticity", "capability_weight", "reliability_weight", "safety_weight"]
const USER_SEGMENT_WEIGHT_FIELDS: Array[String] = ["capability_weight", "reliability_weight", "safety_weight"]

const COMMUNICATION_ACTION_REQUIRED_FIELDS: Array[String] = ["id", "name", "cost", "trust_delta", "hype_debt_delta", "cooldown_days"]
# A single action nudging trust by more than this would let PR erase severe
# evidence in one click; keep it small (see docs P19 acceptance criteria).
const COMMUNICATION_MAX_TRUST_DELTA: float = 10.0

const RIVAL_DOCTRINE_REQUIRED_FIELDS: Array[String] = ["id", "name", "research_pace_multiplier", "market_pressure_multiplier"]

const REGULATOR_REQUIRED_FIELDS: Array[String] = ["id", "name", "audit_threshold", "audit_deadline_days", "requirements", "full_disclosure", "minimal_disclosure"]

const EPILOGUE_REQUIRED_FIELDS: Array[String] = ["id", "title", "body"]

# P25: board and funding rounds.
const FUNDING_ROUND_REQUIRED_FIELDS: Array[String] = ["id", "name", "min_valuation", "amount", "equity_pct", "obligation_per_day"]
const BOARD_TRACK_REQUIRED_FIELDS: Array[String] = ["id", "name", "demand_threshold", "demand_deadline_days", "ask", "yield_to_board", "hold_the_line"]
## Board demand choice effects reuse the incident effect vocabulary plus
## "board_pressure", which only the board track uses.
const BOARD_EFFECT_KEYS: Array[String] = ["cash", "public_trust", "safety_debt", "regulatory_pressure", "board_pressure"]

# P27: legal exposure system. Cases are abstract archetypes only — no real
# plaintiffs (enforced by content review, not a data check).
const LEGAL_CASE_TYPE_REQUIRED_FIELDS: Array[String] = ["id", "name", "trigger_min_exposure", "case_deadline_days", "cooldown_days", "injunction_probability_per_day", "settle", "fight", "injunction"]
const LEGAL_EFFECT_KEYS: Array[String] = ["cash", "public_trust", "safety_debt", "legal_exposure"]

# P28: autonomous agent permissions. Acceptance criterion "each autonomy
# permission has productivity gain + explicit risk surface" is enforced
# here at load time: both effect dicts must be non-empty.
const AGENT_PERMISSION_REQUIRED_FIELDS: Array[String] = ["id", "name", "category", "productivity_description", "risk_description", "productivity_effects", "risk_effects"]
const AGENT_PERMISSION_CATEGORIES: Array[String] = ["coding", "support", "research", "tool_access", "spending"]
const AGENT_PERMISSION_EFFECT_KEYS: Array[String] = ["cash", "public_trust", "safety_debt", "regulatory_pressure", "legal_exposure"]

# P29: automation and workforce policy. Bounded per-pressure multipliers.
const WORKFORCE_POLICY_REQUIRED_FIELDS: Array[String] = ["id", "name", "description", "cash_per_pressure", "morale_per_pressure", "trust_per_pressure", "safety_debt_per_pressure"]
const WORKFORCE_POLICY_AXES: Array[String] = ["cash_per_pressure", "morale_per_pressure", "trust_per_pressure", "safety_debt_per_pressure"]
const WORKFORCE_CASH_PER_PRESSURE_MAX: float = 200.0
const WORKFORCE_MORALE_TRUST_PER_PRESSURE_MAX: float = 10.0
const WORKFORCE_SAFETY_DEBT_PER_PRESSURE_MAX: float = 5.0

# P30: remote datacenter progression.
const DATACENTER_TIER_REQUIRED_FIELDS: Array[String] = ["id", "name", "description", "cost", "compute_capacity_bonus", "operating_cost_per_day"]

# P31: world-state simulation cycles. Amplitude is bounded relative to
# midpoint so a cycle can never push the value outside [0, 100].
const WORLD_VARIABLE_REQUIRED_FIELDS: Array[String] = ["id", "name", "description", "effect_description", "midpoint", "amplitude", "period_days"]

# P32: deployment plans and subscriptions.
const SUBSCRIPTION_PLAN_REQUIRED_FIELDS: Array[String] = ["id", "name", "description", "price", "quota_users", "enterprise_contract_revenue_per_day", "min_reliability_for_contract"]

# P33: news and social feed. Offline authored templates only.
const NEWS_TEMPLATE_REQUIRED_FIELDS: Array[String] = ["id", "category", "template"]
const NEWS_TEMPLATE_CATEGORIES: Array[String] = ["incident_resolved", "rival_launched", "funding_round_accepted", "legal_case_filed", "deployment_churn_event", "audit_triggered", "datacenter_tier_purchased"]

# P36: campaign acts and pacing.
const CAMPAIGN_ACT_REQUIRED_FIELDS: Array[String] = ["number", "name", "tagline", "milestone_description"]
const CAMPAIGN_ACT_COUNT: int = 5

# P38: tutorial and onboarding.
const TUTORIAL_STEP_REQUIRED_FIELDS: Array[String] = ["id", "title", "body", "completion_metric"]
const TUTORIAL_STEP_METRICS: Array[String] = ["manual", "server_rack_built", "staff_hired", "model_trained", "model_evaluated", "model_deployed"]
const GLOSSARY_TERM_REQUIRED_FIELDS: Array[String] = ["id", "term", "definition"]

# P41: audio. Every SFX cue is procedurally synthesized (AudioSynth) from
# these fields — no imported sound files. The envelope-fits-duration rule
# below is a structural enforcement of this prompt's "click-free" accept-
# ance criterion: attack+decay can never exceed the clip's own duration,
# so a generated clip can never contain an abrupt (non-enveloped) jump.
const SFX_CUE_REQUIRED_FIELDS: Array[String] = ["id", "bus", "waveform", "base_freq", "duration_sec", "attack_sec", "decay_sec", "gain_db"]
const SFX_CUE_BUSES: Array[String] = ["SFX", "UI"]
const SFX_CUE_WAVEFORMS: Array[String] = ["sine", "square", "triangle", "noise"]

# P46: platform integration (achievements/cloud hooks). AchievementManager
# owns the actual detection logic per trigger id; this is just the closed
# vocabulary DataValidator checks against.
const ACHIEVEMENT_REQUIRED_FIELDS: Array[String] = ["id", "name", "description", "trigger"]
const ACHIEVEMENT_TRIGGERS: Array[String] = [
    "final_act_reached", "staff_count_50", "first_public_deployment",
    "successful_rollback", "runway_under_7_days", "ending_low_market_share",
    "eval_warning_release", "delayed_launch_after_safety_warning",
    "reliability_streak_30_days", "clean_compute_act",
]

## One validation problem: which file, which record, and why.
class Issue:
    var source: String
    var record_label: String
    var message: String

    func _init(p_source: String, p_record_label: String, p_message: String) -> void:
        source = p_source
        record_label = p_record_label
        message = p_message

    func format() -> String:
        var label_part: String = "" if record_label.is_empty() else " [%s]" % record_label
        return "%s%s: %s" % [source, label_part, message]

## Validates every known startup dataset. Returns every issue found
## (empty = all clean). Safe to call more than once.
static func validate_all() -> Array[Issue]:
    var issues: Array[Issue] = []
    issues.append_array(validate_event_file("res://data/events_seed.json"))
    issues.append_array(validate_buildable_file("res://data/buildables.json"))
    issues.append_array(validate_staff_role_file("res://data/staff_roles.json"))
    issues.append_array(validate_staff_trait_file("res://data/staff_traits.json"))
    issues.append_array(validate_work_task_file("res://data/work_tasks.json"))
    issues.append_array(validate_research_node_file("res://data/research_nodes.json"))
    issues.append_array(validate_model_tier_file("res://data/model_tiers.json"))
    issues.append_array(validate_deployment_mode_file("res://data/deployment_modes.json"))
    issues.append_array(validate_user_segment_file("res://data/user_segments.json"))
    issues.append_array(validate_communication_action_file("res://data/communication_actions.json"))
    issues.append_array(validate_rival_doctrine_file("res://data/rival_doctrines.json"))
    issues.append_array(validate_regulator_file("res://data/regulator_track.json"))
    issues.append_array(validate_funding_round_file("res://data/funding_rounds.json"))
    issues.append_array(validate_board_track_file("res://data/board_track.json"))
    issues.append_array(validate_legal_case_type_file("res://data/legal_case_types.json"))
    issues.append_array(validate_agent_permission_file("res://data/agent_permissions.json"))
    issues.append_array(validate_workforce_policy_file("res://data/workforce_policies.json"))
    issues.append_array(validate_datacenter_tier_file("res://data/datacenter_tiers.json"))
    issues.append_array(validate_world_variable_file("res://data/world_variables.json"))
    issues.append_array(validate_subscription_plan_file("res://data/subscription_plans.json"))
    issues.append_array(validate_news_template_file("res://data/news_templates.json"))
    issues.append_array(validate_campaign_act_file("res://data/campaign_acts.json"))
    issues.append_array(validate_tutorial_step_file("res://data/tutorial_steps.json"))
    issues.append_array(validate_glossary_term_file("res://data/glossary_terms.json"))
    issues.append_array(validate_epilogue_file("res://data/epilogues.json"))
    issues.append_array(validate_sfx_cue_file("res://data/sfx_cues.json"))
    issues.append_array(validate_achievement_file("res://data/achievements.json"))
    return issues

static func validate_event_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of event records"))
        return issues

    var records: Array = parsed
    var all_ids: Dictionary = {}
    for entry: Variant in records:
        if entry is Dictionary and (entry as Dictionary).has("id"):
            all_ids[String((entry as Dictionary)["id"])] = true

    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_event_record(path, records[i], i, seen_ids, all_ids))
    return issues

## P34: a choice may optionally schedule a follow-up incident
## (follow_up_incident_id + follow_up_delay_days) — a scripted narrative
## continuation. all_ids is every event id in the file, for the
## cross-reference check below.
static func _validate_event_record(path: String, record: Variant, index: int, seen_ids: Dictionary, all_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "event record must be a JSON object"))
        return issues

    var event: Dictionary = record
    for field: String in EVENT_REQUIRED_FIELDS:
        if not event.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var event_id: String = str(event.get("id", ""))
    var id_label: String = event_id if not event_id.is_empty() else record_label
    if event.has("id"):
        if event_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(event_id):
            issues.append(Issue.new(path, event_id, "duplicate id (first seen at record #%d)" % int(seen_ids[event_id])))
        else:
            seen_ids[event_id] = index

    if event.has("category"):
        var category: String = str(event.get("category", ""))
        if not EVENT_CATEGORIES.has(category):
            issues.append(Issue.new(path, id_label, "unknown category '%s' (expected one of %s)" % [category, EVENT_CATEGORIES]))

    if event.has("severity"):
        var severity: Variant = event.get("severity")
        if not (severity is int or severity is float):
            issues.append(Issue.new(path, id_label, "'severity' must be numeric"))
        elif int(severity) < EVENT_SEVERITY_MIN or int(severity) > EVENT_SEVERITY_MAX:
            issues.append(Issue.new(path, id_label, "'severity' %s out of range [%d, %d]" % [severity, EVENT_SEVERITY_MIN, EVENT_SEVERITY_MAX]))

    if event.has("weight"):
        var weight: Variant = event.get("weight")
        if not (weight is int or weight is float) or float(weight) <= 0.0:
            issues.append(Issue.new(path, id_label, "'weight' must be a number > 0"))

    if event.has("cooldown_days") and not _is_whole_number_at_least(event.get("cooldown_days"), 0):
        issues.append(Issue.new(path, id_label, "'cooldown_days' must be a whole number >= 0"))

    if event.has("prerequisites"):
        var prereqs: Variant = event.get("prerequisites")
        if not (prereqs is Dictionary):
            issues.append(Issue.new(path, id_label, "'prerequisites' must be an object"))
        else:
            for key: String in (prereqs as Dictionary):
                var metric: String = ""
                if key.begins_with("min_"):
                    metric = key.substr(4)
                elif key.begins_with("max_"):
                    metric = key.substr(4)
                else:
                    issues.append(Issue.new(path, id_label, "prerequisite key '%s' must start with 'min_' or 'max_'" % key))
                    continue
                if not EVENT_CONDITION_METRICS.has(metric):
                    issues.append(Issue.new(path, id_label, "prerequisite key '%s' references unknown metric '%s' (expected one of %s)" % [key, metric, EVENT_CONDITION_METRICS]))
                var value: Variant = (prereqs as Dictionary)[key]
                if not (value is int or value is float):
                    issues.append(Issue.new(path, id_label, "prerequisite '%s' value must be numeric" % key))

    if event.has("choices"):
        var choices: Variant = event.get("choices")
        if not (choices is Array):
            issues.append(Issue.new(path, id_label, "'choices' must be an array"))
        else:
            var choices_arr: Array = choices
            if choices_arr.size() < EVENT_MIN_CHOICES or choices_arr.size() > EVENT_MAX_CHOICES:
                issues.append(Issue.new(path, id_label, "'choices' has %d entries, expected %d-%d" % [choices_arr.size(), EVENT_MIN_CHOICES, EVENT_MAX_CHOICES]))
            var seen_choice_ids: Dictionary = {}
            for choice: Variant in choices_arr:
                if not (choice is Dictionary):
                    issues.append(Issue.new(path, id_label, "each choice must be an object"))
                    continue
                var choice_dict: Dictionary = choice
                for field: String in EVENT_CHOICE_REQUIRED_FIELDS:
                    if not choice_dict.has(field):
                        issues.append(Issue.new(path, id_label, "a choice is missing required field '%s'" % field))
                var choice_id: String = str(choice_dict.get("id", ""))
                if choice_id.is_empty():
                    issues.append(Issue.new(path, id_label, "a choice has an empty 'id'"))
                elif seen_choice_ids.has(choice_id):
                    issues.append(Issue.new(path, id_label, "duplicate choice id '%s'" % choice_id))
                else:
                    seen_choice_ids[choice_id] = true
                if choice_dict.has("label") and (not (choice_dict["label"] is String) or String(choice_dict["label"]).is_empty()):
                    issues.append(Issue.new(path, id_label, "a choice's 'label' must be a non-empty string"))
                if choice_dict.has("effects"):
                    var effects: Variant = choice_dict.get("effects")
                    if not (effects is Dictionary):
                        issues.append(Issue.new(path, id_label, "a choice's 'effects' must be an object"))
                    else:
                        for effect_key: String in (effects as Dictionary):
                            if not EVENT_EFFECT_KEYS.has(effect_key):
                                issues.append(Issue.new(path, id_label, "unknown effect key '%s' (expected one of %s)" % [effect_key, EVENT_EFFECT_KEYS]))
                            var effect_value: Variant = (effects as Dictionary)[effect_key]
                            if not (effect_value is int or effect_value is float):
                                issues.append(Issue.new(path, id_label, "effect '%s' value must be numeric" % effect_key))

                if choice_dict.has("follow_up_incident_id") or choice_dict.has("follow_up_delay_days"):
                    if not (choice_dict.has("follow_up_incident_id") and choice_dict.has("follow_up_delay_days")):
                        issues.append(Issue.new(path, id_label, "a choice with a follow-up must set both 'follow_up_incident_id' and 'follow_up_delay_days'"))
                    else:
                        var follow_up_id: String = str(choice_dict.get("follow_up_incident_id", ""))
                        if follow_up_id.is_empty() or not all_ids.has(follow_up_id):
                            issues.append(Issue.new(path, id_label, "'follow_up_incident_id' references unknown incident '%s'" % follow_up_id))
                        if follow_up_id == event_id:
                            issues.append(Issue.new(path, id_label, "a choice cannot schedule its own incident as a follow-up"))
                        if not _is_whole_number_at_least(choice_dict.get("follow_up_delay_days"), 1):
                            issues.append(Issue.new(path, id_label, "'follow_up_delay_days' must be a whole number >= 1"))

    if event.has("title") and (not (event["title"] is String) or String(event["title"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'title' must be a non-empty string"))
    if event.has("body") and (not (event["body"] is String) or String(event["body"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'body' must be a non-empty string"))

    return issues

static func validate_buildable_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of buildable records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_buildable_record(path, records[i], i, seen_ids))
    return issues

static func _validate_buildable_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "buildable record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in BUILDABLE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("cost"):
        var cost: Variant = entry.get("cost")
        if not (cost is int or cost is float) or float(cost) <= 0.0:
            issues.append(Issue.new(path, id_label, "'cost' must be a number > 0"))

    if entry.has("refund_ratio"):
        var refund_ratio: Variant = entry.get("refund_ratio")
        if not (refund_ratio is int or refund_ratio is float) or float(refund_ratio) < 0.0 or float(refund_ratio) > 1.0:
            issues.append(Issue.new(path, id_label, "'refund_ratio' must be a number in [0, 1]"))

    # Infrastructure fields (P12): optional, only server_rack-like buildables
    # use them, but must be non-negative numbers when present.
    for infra_field: String in ["compute_units", "power_draw", "heat_output", "operating_cost_per_day"]:
        if entry.has(infra_field):
            var value: Variant = entry.get(infra_field)
            if not (value is int or value is float) or float(value) < 0.0:
                issues.append(Issue.new(path, id_label, "'%s' must be a number >= 0" % infra_field))

    if entry.has("footprint"):
        var footprint: Variant = entry.get("footprint")
        if not (footprint is Dictionary) or not footprint.has("w") or not footprint.has("d"):
            issues.append(Issue.new(path, id_label, "'footprint' must be an object with 'w' and 'd'"))
        else:
            var fp: Dictionary = footprint
            var w: Variant = fp.get("w")
            var d: Variant = fp.get("d")
            # JSON has no int/float distinction: parsed numbers are always
            # float, so accept a whole-number float here too (see the
            # matching note in SaveManager._wrap_envelope).
            if not _is_whole_number_at_least(w, 1) or not _is_whole_number_at_least(d, 1):
                issues.append(Issue.new(path, id_label, "'footprint.w'/'footprint.d' must be whole numbers >= 1"))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

static func validate_staff_role_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of staff role records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_staff_role_record(path, records[i], i, seen_ids))
    return issues

static func _validate_staff_role_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "staff role record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in STAFF_ROLE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("base_salary_min") and entry.has("base_salary_max"):
        var salary_min: Variant = entry.get("base_salary_min")
        var salary_max: Variant = entry.get("base_salary_max")
        var min_ok: bool = (salary_min is int or salary_min is float) and float(salary_min) > 0.0
        var max_ok: bool = (salary_max is int or salary_max is float) and float(salary_max) >= float(salary_min) if min_ok else false
        if not min_ok or not max_ok:
            issues.append(Issue.new(path, id_label, "'base_salary_min'/'base_salary_max' must be numbers with min > 0 and max >= min"))

    if entry.has("primary_skill"):
        var primary_skill: String = str(entry.get("primary_skill", ""))
        if not STAFF_SKILL_KEYS.has(primary_skill):
            issues.append(Issue.new(path, id_label, "unknown primary_skill '%s' (expected one of %s)" % [primary_skill, STAFF_SKILL_KEYS]))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    if entry.has("visual_color"):
        var visual_color: Variant = entry.get("visual_color")
        if not (visual_color is String) or not String(visual_color).is_valid_html_color():
            issues.append(Issue.new(path, id_label, "'visual_color' must be a valid hex color string (e.g. 'a1b2c3')"))

    return issues

static func validate_staff_trait_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of staff trait records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_staff_trait_record(path, records[i], i, seen_ids))
    return issues

static func _validate_staff_trait_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "staff trait record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in STAFF_TRAIT_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    if entry.has("skill_deltas"):
        var skill_deltas: Variant = entry.get("skill_deltas")
        if not (skill_deltas is Dictionary):
            issues.append(Issue.new(path, id_label, "'skill_deltas' must be an object"))
        else:
            var deltas: Dictionary = skill_deltas
            for skill_key: Variant in deltas:
                if not STAFF_SKILL_KEYS.has(String(skill_key)):
                    issues.append(Issue.new(path, id_label, "'skill_deltas' has unknown skill key '%s' (expected one of %s)" % [skill_key, STAFF_SKILL_KEYS]))
                var delta_value: Variant = deltas[skill_key]
                if not (delta_value is int or delta_value is float) or absf(float(delta_value)) > STAFF_TRAIT_SKILL_DELTA_MAX:
                    issues.append(Issue.new(path, id_label, "'skill_deltas.%s' must be a number with |value| <= %s (bounded impact)" % [skill_key, STAFF_TRAIT_SKILL_DELTA_MAX]))

    if entry.has("morale_delta"):
        var morale_delta: Variant = entry.get("morale_delta")
        if not (morale_delta is int or morale_delta is float) or absf(float(morale_delta)) > STAFF_TRAIT_MORALE_DELTA_MAX:
            issues.append(Issue.new(path, id_label, "'morale_delta' must be a number with |value| <= %s (bounded impact)" % STAFF_TRAIT_MORALE_DELTA_MAX))

    if entry.has("fatigue_resistance"):
        var fatigue_resistance: Variant = entry.get("fatigue_resistance")
        var in_range: bool = (fatigue_resistance is int or fatigue_resistance is float) and float(fatigue_resistance) >= STAFF_TRAIT_FATIGUE_RESISTANCE_MIN and float(fatigue_resistance) <= STAFF_TRAIT_FATIGUE_RESISTANCE_MAX
        if not in_range:
            issues.append(Issue.new(path, id_label, "'fatigue_resistance' must be a number in [%s, %s] (bounded impact)" % [STAFF_TRAIT_FATIGUE_RESISTANCE_MIN, STAFF_TRAIT_FATIGUE_RESISTANCE_MAX]))

    return issues

static func validate_work_task_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of work task records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_work_task_record(path, records[i], i, seen_ids))
    return issues

static func _validate_work_task_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "work task record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in WORK_TASK_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("required_skill"):
        var required_skill: String = str(entry.get("required_skill", ""))
        if not STAFF_SKILL_KEYS.has(required_skill):
            issues.append(Issue.new(path, id_label, "unknown required_skill '%s' (expected one of %s)" % [required_skill, STAFF_SKILL_KEYS]))

    if entry.has("required_buildable") and (not (entry["required_buildable"] is String) or String(entry["required_buildable"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'required_buildable' must be a non-empty string"))

    if entry.has("duration_minutes") and not _is_whole_number_at_least(entry.get("duration_minutes"), 1):
        issues.append(Issue.new(path, id_label, "'duration_minutes' must be a whole number >= 1"))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    if entry.has("compute_cost"):
        var compute_cost: Variant = entry.get("compute_cost")
        if not (compute_cost is int or compute_cost is float) or float(compute_cost) < 0.0:
            issues.append(Issue.new(path, id_label, "'compute_cost' must be a number >= 0"))

    return issues

static func validate_research_node_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of research node records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_research_node_record(path, records[i], i, seen_ids))

    # Second pass: prerequisites must reference ids that actually exist.
    for i in records.size():
        var record: Variant = records[i]
        if not (record is Dictionary):
            continue
        var entry: Dictionary = record
        var entry_id: String = str(entry.get("id", "record #%d" % i))
        var prereqs: Variant = entry.get("prerequisites")
        if prereqs is Array:
            for prereq: Variant in prereqs:
                if not seen_ids.has(str(prereq)):
                    issues.append(Issue.new(path, entry_id, "prerequisite '%s' does not match any research node id" % prereq))

    return issues

static func _validate_research_node_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "research node record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in RESEARCH_NODE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("branch"):
        var branch: String = str(entry.get("branch", ""))
        if not RESEARCH_BRANCHES.has(branch):
            issues.append(Issue.new(path, id_label, "unknown branch '%s' (expected one of %s)" % [branch, RESEARCH_BRANCHES]))

    if entry.has("cost") and not _is_whole_number_at_least(entry.get("cost"), 1):
        issues.append(Issue.new(path, id_label, "'cost' must be a whole number >= 1"))

    if entry.has("duration_minutes") and not _is_whole_number_at_least(entry.get("duration_minutes"), 1):
        issues.append(Issue.new(path, id_label, "'duration_minutes' must be a whole number >= 1"))

    if entry.has("prerequisites") and not (entry["prerequisites"] is Array):
        issues.append(Issue.new(path, id_label, "'prerequisites' must be an array"))

    if entry.has("unlock_effect"):
        var effect: Variant = entry.get("unlock_effect")
        if not (effect is Dictionary) or not effect.has("type") or not effect.has("amount"):
            issues.append(Issue.new(path, id_label, "'unlock_effect' must be an object with 'type' and 'amount'"))
        else:
            var effect_dict: Dictionary = effect
            var effect_type: String = str(effect_dict.get("type", ""))
            if not RESEARCH_EFFECT_TYPES.has(effect_type):
                issues.append(Issue.new(path, id_label, "unknown unlock_effect.type '%s' (expected one of %s)" % [effect_type, RESEARCH_EFFECT_TYPES]))
            var amount: Variant = effect_dict.get("amount")
            if not (amount is int or amount is float):
                issues.append(Issue.new(path, id_label, "'unlock_effect.amount' must be a number"))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

static func validate_model_tier_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of model tier records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_model_tier_record(path, records[i], i, seen_ids))
    return issues

static func _validate_model_tier_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "model tier record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in MODEL_TIER_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("cost") and not _is_whole_number_at_least(entry.get("cost"), 1):
        issues.append(Issue.new(path, id_label, "'cost' must be a whole number >= 1"))

    if entry.has("duration_minutes") and not _is_whole_number_at_least(entry.get("duration_minutes"), 1):
        issues.append(Issue.new(path, id_label, "'duration_minutes' must be a whole number >= 1"))

    for stat_field: String in MODEL_TIER_STAT_FIELDS:
        if entry.has(stat_field):
            var value: Variant = entry.get(stat_field)
            if not (value is int or value is float) or float(value) < 0.0 or float(value) > 100.0:
                issues.append(Issue.new(path, id_label, "'%s' must be a number in [0, 100]" % stat_field))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

static func validate_deployment_mode_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of deployment mode records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_deployment_mode_record(path, records[i], i, seen_ids))
    return issues

static func _validate_deployment_mode_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "deployment mode record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in DEPLOYMENT_MODE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("base_user_scale") and not _is_whole_number_at_least(entry.get("base_user_scale"), 0):
        issues.append(Issue.new(path, id_label, "'base_user_scale' must be a whole number >= 0"))

    if entry.has("exposure_multiplier"):
        var exposure: Variant = entry.get("exposure_multiplier")
        if not (exposure is int or exposure is float) or float(exposure) < 0.0:
            issues.append(Issue.new(path, id_label, "'exposure_multiplier' must be a number >= 0"))

    if entry.has("rollout_days") and not _is_whole_number_at_least(entry.get("rollout_days"), 1):
        issues.append(Issue.new(path, id_label, "'rollout_days' must be a whole number >= 1"))

    if entry.has("inference_compute_per_1k_users"):
        var inference: Variant = entry.get("inference_compute_per_1k_users")
        if not (inference is int or inference is float) or float(inference) < 0.0:
            issues.append(Issue.new(path, id_label, "'inference_compute_per_1k_users' must be a number >= 0"))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

static func validate_user_segment_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of user segment records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    var share_total: float = 0.0
    for i in records.size():
        issues.append_array(_validate_user_segment_record(path, records[i], i, seen_ids))
        var record: Variant = records[i]
        if record is Dictionary and (record as Dictionary).get("share_of_market") is float:
            share_total += float((record as Dictionary)["share_of_market"])
        elif record is Dictionary and (record as Dictionary).get("share_of_market") is int:
            share_total += float((record as Dictionary)["share_of_market"])

    if not records.is_empty() and not is_equal_approx(share_total, 1.0):
        issues.append(Issue.new(path, "", "share_of_market across all segments should sum to 1.0 (got %.3f)" % share_total))

    return issues

static func _validate_user_segment_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "user segment record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in USER_SEGMENT_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("share_of_market"):
        var share: Variant = entry.get("share_of_market")
        if not (share is int or share is float) or float(share) <= 0.0 or float(share) > 1.0:
            issues.append(Issue.new(path, id_label, "'share_of_market' must be a number in (0, 1]"))

    if entry.has("max_price"):
        var max_price: Variant = entry.get("max_price")
        if not (max_price is int or max_price is float) or float(max_price) <= 0.0:
            issues.append(Issue.new(path, id_label, "'max_price' must be a number > 0"))

    if entry.has("elasticity"):
        var elasticity: Variant = entry.get("elasticity")
        if not (elasticity is int or elasticity is float) or float(elasticity) <= 0.0:
            issues.append(Issue.new(path, id_label, "'elasticity' must be a number > 0"))

    for weight_field: String in USER_SEGMENT_WEIGHT_FIELDS:
        if entry.has(weight_field):
            var weight: Variant = entry.get(weight_field)
            if not (weight is int or weight is float) or float(weight) < 0.0:
                issues.append(Issue.new(path, id_label, "'%s' must be a number >= 0" % weight_field))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

static func validate_communication_action_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of communication action records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_communication_action_record(path, records[i], i, seen_ids))
    return issues

static func _validate_communication_action_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "communication action record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in COMMUNICATION_ACTION_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("cost"):
        var cost: Variant = entry.get("cost")
        if not (cost is int or cost is float) or float(cost) < 0.0:
            issues.append(Issue.new(path, id_label, "'cost' must be a number >= 0"))

    if entry.has("trust_delta"):
        var trust_delta: Variant = entry.get("trust_delta")
        if not (trust_delta is int or trust_delta is float):
            issues.append(Issue.new(path, id_label, "'trust_delta' must be numeric"))
        elif absf(float(trust_delta)) > COMMUNICATION_MAX_TRUST_DELTA:
            issues.append(Issue.new(path, id_label, "'trust_delta' magnitude %s exceeds the single-action cap of %s (PR must not be able to erase severe evidence in one action)" % [trust_delta, COMMUNICATION_MAX_TRUST_DELTA]))

    if entry.has("hype_debt_delta"):
        var hype_delta: Variant = entry.get("hype_debt_delta")
        if not (hype_delta is int or hype_delta is float) or float(hype_delta) < 0.0:
            issues.append(Issue.new(path, id_label, "'hype_debt_delta' must be a number >= 0"))

    if entry.has("cooldown_days") and not _is_whole_number_at_least(entry.get("cooldown_days"), 0):
        issues.append(Issue.new(path, id_label, "'cooldown_days' must be a whole number >= 0"))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

static func validate_rival_doctrine_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of rival doctrine records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_rival_doctrine_record(path, records[i], i, seen_ids))
    return issues

static func _validate_rival_doctrine_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "rival doctrine record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in RIVAL_DOCTRINE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    for mult_field: String in ["research_pace_multiplier", "market_pressure_multiplier"]:
        if entry.has(mult_field):
            var value: Variant = entry.get(mult_field)
            if not (value is int or value is float) or float(value) <= 0.0:
                issues.append(Issue.new(path, id_label, "'%s' must be a number > 0" % mult_field))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

## The regulator config is a single object (one fictional regulator for
## the MVP), not an array of records like the other catalogs.
static func validate_regulator_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        issues.append(Issue.new(path, "", "root must be a JSON object (a single regulator)"))
        return issues

    var entry: Dictionary = parsed
    for field: String in REGULATOR_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, "", "missing required field '%s'" % field))

    if entry.has("id") and (not (entry["id"] is String) or String(entry["id"]).is_empty()):
        issues.append(Issue.new(path, "", "'id' must be a non-empty string"))
    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, "", "'name' must be a non-empty string"))

    if entry.has("audit_threshold"):
        var threshold: Variant = entry.get("audit_threshold")
        if not (threshold is int or threshold is float) or float(threshold) < 0.0 or float(threshold) > 100.0:
            issues.append(Issue.new(path, "", "'audit_threshold' must be a number in [0, 100]"))

    if entry.has("audit_deadline_days") and not _is_whole_number_at_least(entry.get("audit_deadline_days"), 1):
        issues.append(Issue.new(path, "", "'audit_deadline_days' must be a whole number >= 1"))

    if entry.has("requirements"):
        var requirements: Variant = entry.get("requirements")
        if not (requirements is Array) or (requirements as Array).is_empty():
            issues.append(Issue.new(path, "", "'requirements' must be a non-empty array — an audit needs clear requirements"))
        else:
            for req: Variant in (requirements as Array):
                if not (req is String) or String(req).is_empty():
                    issues.append(Issue.new(path, "", "each requirement must be a non-empty string"))
                    break

    for disclosure_field: String in ["full_disclosure", "minimal_disclosure"]:
        if entry.has(disclosure_field):
            var effects: Variant = entry.get(disclosure_field)
            if not (effects is Dictionary):
                issues.append(Issue.new(path, "", "'%s' must be an object of effects" % disclosure_field))
            else:
                for effect_key: String in (effects as Dictionary):
                    if not EVENT_EFFECT_KEYS.has(effect_key):
                        issues.append(Issue.new(path, "", "'%s' has unknown effect key '%s' (expected one of %s)" % [disclosure_field, effect_key, EVENT_EFFECT_KEYS]))
                    var effect_value: Variant = (effects as Dictionary)[effect_key]
                    if not (effect_value is int or effect_value is float):
                        issues.append(Issue.new(path, "", "'%s' effect '%s' value must be numeric" % [disclosure_field, effect_key]))

    return issues

static func validate_funding_round_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of funding round records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_funding_round_record(path, records[i], i, seen_ids))
    return issues

static func _validate_funding_round_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "funding round record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in FUNDING_ROUND_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("min_valuation") and not _is_whole_number_at_least(entry.get("min_valuation"), 0):
        issues.append(Issue.new(path, id_label, "'min_valuation' must be a whole number >= 0"))

    if entry.has("amount"):
        var amount: Variant = entry.get("amount")
        if not (amount is int or amount is float) or float(amount) <= 0.0:
            issues.append(Issue.new(path, id_label, "'amount' must be a number > 0"))

    if entry.has("equity_pct"):
        var equity_pct: Variant = entry.get("equity_pct")
        if not (equity_pct is int or equity_pct is float) or float(equity_pct) <= 0.0 or float(equity_pct) > 100.0:
            issues.append(Issue.new(path, id_label, "'equity_pct' must be a number in (0, 100]"))

    if entry.has("obligation_per_day"):
        var obligation: Variant = entry.get("obligation_per_day")
        if not (obligation is int or obligation is float) or float(obligation) < 0.0:
            issues.append(Issue.new(path, id_label, "'obligation_per_day' must be a number >= 0"))

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    return issues

## The board track config is a single object (one board for the MVP), not
## an array of records — same shape as the regulator config.
static func validate_board_track_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        issues.append(Issue.new(path, "", "root must be a JSON object (a single board)"))
        return issues

    var entry: Dictionary = parsed
    for field: String in BOARD_TRACK_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, "", "missing required field '%s'" % field))

    if entry.has("id") and (not (entry["id"] is String) or String(entry["id"]).is_empty()):
        issues.append(Issue.new(path, "", "'id' must be a non-empty string"))
    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, "", "'name' must be a non-empty string"))
    if entry.has("ask") and (not (entry["ask"] is String) or String(entry["ask"]).is_empty()):
        issues.append(Issue.new(path, "", "'ask' must be a non-empty string"))

    if entry.has("demand_threshold"):
        var threshold: Variant = entry.get("demand_threshold")
        if not (threshold is int or threshold is float) or float(threshold) < 0.0 or float(threshold) > 100.0:
            issues.append(Issue.new(path, "", "'demand_threshold' must be a number in [0, 100]"))

    if entry.has("demand_deadline_days") and not _is_whole_number_at_least(entry.get("demand_deadline_days"), 1):
        issues.append(Issue.new(path, "", "'demand_deadline_days' must be a whole number >= 1"))

    for choice_field: String in ["yield_to_board", "hold_the_line"]:
        if entry.has(choice_field):
            var effects: Variant = entry.get(choice_field)
            if not (effects is Dictionary):
                issues.append(Issue.new(path, "", "'%s' must be an object of effects" % choice_field))
            else:
                for effect_key: String in (effects as Dictionary):
                    if not BOARD_EFFECT_KEYS.has(effect_key):
                        issues.append(Issue.new(path, "", "'%s' has unknown effect key '%s' (expected one of %s)" % [choice_field, effect_key, BOARD_EFFECT_KEYS]))
                    var effect_value: Variant = (effects as Dictionary)[effect_key]
                    if not (effect_value is int or effect_value is float):
                        issues.append(Issue.new(path, "", "'%s' effect '%s' value must be numeric" % [choice_field, effect_key]))

    return issues

static func validate_legal_case_type_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of legal case type records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_legal_case_type_record(path, records[i], i, seen_ids))
    return issues

static func _validate_legal_case_type_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "legal case type record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in LEGAL_CASE_TYPE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    if entry.has("trigger_min_exposure"):
        var threshold: Variant = entry.get("trigger_min_exposure")
        if not (threshold is int or threshold is float) or float(threshold) < 0.0 or float(threshold) > 100.0:
            issues.append(Issue.new(path, id_label, "'trigger_min_exposure' must be a number in [0, 100]"))

    if entry.has("case_deadline_days") and not _is_whole_number_at_least(entry.get("case_deadline_days"), 1):
        issues.append(Issue.new(path, id_label, "'case_deadline_days' must be a whole number >= 1"))

    if entry.has("cooldown_days") and not _is_whole_number_at_least(entry.get("cooldown_days"), 0):
        issues.append(Issue.new(path, id_label, "'cooldown_days' must be a whole number >= 0"))

    if entry.has("injunction_probability_per_day"):
        var prob: Variant = entry.get("injunction_probability_per_day")
        if not (prob is int or prob is float) or float(prob) < 0.0 or float(prob) > 1.0:
            issues.append(Issue.new(path, id_label, "'injunction_probability_per_day' must be a number in [0, 1] (bounded outcome)"))

    for choice_field: String in ["settle", "fight", "injunction"]:
        if entry.has(choice_field):
            var effects: Variant = entry.get(choice_field)
            if not (effects is Dictionary):
                issues.append(Issue.new(path, id_label, "'%s' must be an object of effects" % choice_field))
            else:
                for effect_key: String in (effects as Dictionary):
                    if not LEGAL_EFFECT_KEYS.has(effect_key):
                        issues.append(Issue.new(path, id_label, "'%s' has unknown effect key '%s' (expected one of %s)" % [choice_field, effect_key, LEGAL_EFFECT_KEYS]))
                    var effect_value: Variant = (effects as Dictionary)[effect_key]
                    if not (effect_value is int or effect_value is float):
                        issues.append(Issue.new(path, id_label, "'%s' effect '%s' value must be numeric" % [choice_field, effect_key]))

    return issues

static func validate_agent_permission_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of agent permission records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_agent_permission_record(path, records[i], i, seen_ids))
    return issues

static func _validate_agent_permission_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "agent permission record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in AGENT_PERMISSION_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))

    if entry.has("category"):
        var category: String = str(entry.get("category", ""))
        if not AGENT_PERMISSION_CATEGORIES.has(category):
            issues.append(Issue.new(path, id_label, "unknown category '%s' (expected one of %s)" % [category, AGENT_PERMISSION_CATEGORIES]))

    for desc_field: String in ["productivity_description", "risk_description"]:
        if entry.has(desc_field) and (not (entry[desc_field] is String) or String(entry[desc_field]).is_empty()):
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty string" % desc_field))

    for effect_field: String in ["productivity_effects", "risk_effects"]:
        if not entry.has(effect_field):
            continue
        var effects: Variant = entry.get(effect_field)
        if not (effects is Dictionary) or (effects as Dictionary).is_empty():
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty object — every permission needs both a productivity gain and an explicit risk surface" % effect_field))
        else:
            for effect_key: String in (effects as Dictionary):
                if not AGENT_PERMISSION_EFFECT_KEYS.has(effect_key):
                    issues.append(Issue.new(path, id_label, "'%s' has unknown effect key '%s' (expected one of %s)" % [effect_field, effect_key, AGENT_PERMISSION_EFFECT_KEYS]))
                var effect_value: Variant = (effects as Dictionary)[effect_key]
                if not (effect_value is int or effect_value is float):
                    issues.append(Issue.new(path, id_label, "'%s' effect '%s' value must be numeric" % [effect_field, effect_key]))

    return issues

static func validate_workforce_policy_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of workforce policy records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_workforce_policy_record(path, records[i], i, seen_ids))

    # Acceptance criterion: "no forced political conclusion; outcomes
    # depend on policy choices". Enforced structurally: no single policy
    # may be at-least-as-good on every axis (cash/morale/trust, and lower
    # safety_debt accrual) and strictly better on at least one — that
    # would make it the obviously-correct pick regardless of player
    # values, which is exactly the forced conclusion this must avoid.
    if records.size() >= 2:
        var goodness: Dictionary = {}
        for record: Variant in records:
            var entry: Dictionary = record
            if not entry.has("id"):
                continue
            goodness[String(entry["id"])] = {
                "cash": float(entry.get("cash_per_pressure", 0.0)),
                "morale": float(entry.get("morale_per_pressure", 0.0)),
                "trust": float(entry.get("trust_per_pressure", 0.0)),
                "safety": -float(entry.get("safety_debt_per_pressure", 0.0)),
            }
        for id_a: String in goodness:
            var dominates_everyone: bool = true
            for id_b: String in goodness:
                if id_a == id_b:
                    continue
                if not _dominates(goodness[id_a], goodness[id_b]):
                    dominates_everyone = false
                    break
            if dominates_everyone:
                issues.append(Issue.new(path, id_a, "dominates every other policy on every axis — this forces a single 'correct' choice instead of a real tradeoff"))

    return issues

## True if `a` is at least as good as `b` on every axis and strictly
## better on at least one (Pareto dominance).
static func _dominates(a: Dictionary, b: Dictionary) -> bool:
    var strictly_better_somewhere: bool = false
    for axis: String in a:
        var av: float = float(a[axis])
        var bv: float = float(b[axis])
        if av < bv:
            return false
        if av > bv:
            strictly_better_somewhere = true
    return strictly_better_somewhere

static func _validate_workforce_policy_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "workforce policy record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in WORKFORCE_POLICY_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))
    if entry.has("description") and (not (entry["description"] is String) or String(entry["description"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'description' must be a non-empty string"))

    if entry.has("cash_per_pressure"):
        var cash_val: Variant = entry.get("cash_per_pressure")
        if not (cash_val is int or cash_val is float) or absf(float(cash_val)) > WORKFORCE_CASH_PER_PRESSURE_MAX:
            issues.append(Issue.new(path, id_label, "'cash_per_pressure' must be a number with |value| <= %s" % WORKFORCE_CASH_PER_PRESSURE_MAX))

    for axis: String in ["morale_per_pressure", "trust_per_pressure"]:
        if entry.has(axis):
            var value: Variant = entry.get(axis)
            if not (value is int or value is float) or absf(float(value)) > WORKFORCE_MORALE_TRUST_PER_PRESSURE_MAX:
                issues.append(Issue.new(path, id_label, "'%s' must be a number with |value| <= %s" % [axis, WORKFORCE_MORALE_TRUST_PER_PRESSURE_MAX]))

    if entry.has("safety_debt_per_pressure"):
        var safety_val: Variant = entry.get("safety_debt_per_pressure")
        if not (safety_val is int or safety_val is float) or absf(float(safety_val)) > WORKFORCE_SAFETY_DEBT_PER_PRESSURE_MAX:
            issues.append(Issue.new(path, id_label, "'safety_debt_per_pressure' must be a number with |value| <= %s" % WORKFORCE_SAFETY_DEBT_PER_PRESSURE_MAX))

    return issues

static func validate_datacenter_tier_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of datacenter tier records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_datacenter_tier_record(path, records[i], i, seen_ids))
    return issues

static func _validate_datacenter_tier_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "datacenter tier record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in DATACENTER_TIER_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("name") and (not (entry["name"] is String) or String(entry["name"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'name' must be a non-empty string"))
    if entry.has("description") and (not (entry["description"] is String) or String(entry["description"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'description' must be a non-empty string"))

    if entry.has("cost"):
        var cost: Variant = entry.get("cost")
        if not (cost is int or cost is float) or float(cost) <= 0.0:
            issues.append(Issue.new(path, id_label, "'cost' must be a number > 0"))

    if entry.has("compute_capacity_bonus"):
        var bonus: Variant = entry.get("compute_capacity_bonus")
        if not (bonus is int or bonus is float) or float(bonus) <= 0.0:
            issues.append(Issue.new(path, id_label, "'compute_capacity_bonus' must be a number > 0"))

    if entry.has("operating_cost_per_day") and not _is_whole_number_at_least(entry.get("operating_cost_per_day"), 0):
        issues.append(Issue.new(path, id_label, "'operating_cost_per_day' must be a whole number >= 0"))

    return issues

static func validate_world_variable_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of world variable records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_world_variable_record(path, records[i], i, seen_ids))
    return issues

static func _validate_world_variable_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "world variable record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in WORLD_VARIABLE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    for text_field: String in ["name", "description", "effect_description"]:
        if entry.has(text_field) and (not (entry[text_field] is String) or String(entry[text_field]).is_empty()):
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty string" % text_field))

    var midpoint: float = 50.0
    var midpoint_ok: bool = false
    if entry.has("midpoint"):
        var midpoint_val: Variant = entry.get("midpoint")
        midpoint_ok = (midpoint_val is int or midpoint_val is float) and float(midpoint_val) >= 0.0 and float(midpoint_val) <= 100.0
        if midpoint_ok:
            midpoint = float(midpoint_val)
        else:
            issues.append(Issue.new(path, id_label, "'midpoint' must be a number in [0, 100]"))

    if entry.has("amplitude"):
        var amplitude_val: Variant = entry.get("amplitude")
        var amplitude_numeric: bool = (amplitude_val is int or amplitude_val is float) and float(amplitude_val) >= 0.0
        if not amplitude_numeric:
            issues.append(Issue.new(path, id_label, "'amplitude' must be a number >= 0"))
        elif midpoint_ok:
            var max_amplitude: float = minf(midpoint, 100.0 - midpoint)
            if float(amplitude_val) > max_amplitude:
                issues.append(Issue.new(path, id_label, "'amplitude' (%s) must be <= min(midpoint, 100-midpoint) = %s so the cycle can never leave [0, 100]" % [amplitude_val, max_amplitude]))

    if entry.has("period_days") and not _is_whole_number_at_least(entry.get("period_days"), 1):
        issues.append(Issue.new(path, id_label, "'period_days' must be a whole number >= 1"))

    return issues

static func validate_subscription_plan_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of subscription plan records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_subscription_plan_record(path, records[i], i, seen_ids))
    return issues

static func _validate_subscription_plan_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "subscription plan record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in SUBSCRIPTION_PLAN_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    for text_field: String in ["name", "description"]:
        if entry.has(text_field) and (not (entry[text_field] is String) or String(entry[text_field]).is_empty()):
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty string" % text_field))

    if entry.has("price"):
        var price: Variant = entry.get("price")
        if not (price is int or price is float) or float(price) < 0.0:
            issues.append(Issue.new(path, id_label, "'price' must be a number >= 0"))

    if entry.has("quota_users") and not _is_whole_number_at_least(entry.get("quota_users"), 1):
        issues.append(Issue.new(path, id_label, "'quota_users' must be a whole number >= 1"))

    if entry.has("enterprise_contract_revenue_per_day"):
        var bonus: Variant = entry.get("enterprise_contract_revenue_per_day")
        if not (bonus is int or bonus is float) or float(bonus) < 0.0:
            issues.append(Issue.new(path, id_label, "'enterprise_contract_revenue_per_day' must be a number >= 0"))

    if entry.has("min_reliability_for_contract"):
        var min_reliability: Variant = entry.get("min_reliability_for_contract")
        if not (min_reliability is int or min_reliability is float) or float(min_reliability) < 0.0 or float(min_reliability) > 100.0:
            issues.append(Issue.new(path, id_label, "'min_reliability_for_contract' must be a number in [0, 100]"))

    return issues

static func validate_news_template_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of news template records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_news_template_record(path, records[i], i, seen_ids))
    return issues

static func _validate_news_template_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "news template record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in NEWS_TEMPLATE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("category"):
        var category: String = str(entry.get("category", ""))
        if not NEWS_TEMPLATE_CATEGORIES.has(category):
            issues.append(Issue.new(path, id_label, "unknown category '%s' (expected one of %s)" % [category, NEWS_TEMPLATE_CATEGORIES]))

    if entry.has("template") and (not (entry["template"] is String) or String(entry["template"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'template' must be a non-empty string"))

    return issues

static func validate_campaign_act_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of campaign act records"))
        return issues

    var records: Array = parsed
    if records.size() != CAMPAIGN_ACT_COUNT:
        issues.append(Issue.new(path, "", "expected exactly %d acts (got %d)" % [CAMPAIGN_ACT_COUNT, records.size()]))

    var seen_numbers: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_campaign_act_record(path, records[i], i, seen_numbers))
    for expected_number in range(1, CAMPAIGN_ACT_COUNT + 1):
        if not seen_numbers.has(expected_number):
            issues.append(Issue.new(path, "", "missing act number %d" % expected_number))
    return issues

static func _validate_campaign_act_record(path: String, record: Variant, index: int, seen_numbers: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "campaign act record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in CAMPAIGN_ACT_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    if entry.has("number"):
        var number_val: Variant = entry.get("number")
        if not _is_whole_number_at_least(number_val, 1) or int(number_val) > CAMPAIGN_ACT_COUNT:
            issues.append(Issue.new(path, record_label, "'number' must be a whole number in [1, %d]" % CAMPAIGN_ACT_COUNT))
        elif seen_numbers.has(int(number_val)):
            issues.append(Issue.new(path, record_label, "duplicate act number %d" % int(number_val)))
        else:
            seen_numbers[int(number_val)] = index

    var number_label: String = str(entry.get("number", record_label))
    for text_field: String in ["name", "tagline", "milestone_description"]:
        if entry.has(text_field) and (not (entry[text_field] is String) or String(entry[text_field]).is_empty()):
            issues.append(Issue.new(path, number_label, "'%s' must be a non-empty string" % text_field))

    return issues

static func validate_tutorial_step_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of tutorial step records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_tutorial_step_record(path, records[i], i, seen_ids))
    return issues

static func _validate_tutorial_step_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "tutorial step record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in TUTORIAL_STEP_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    for text_field: String in ["title", "body"]:
        if entry.has(text_field) and (not (entry[text_field] is String) or String(entry[text_field]).is_empty()):
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty string" % text_field))

    if entry.has("completion_metric"):
        var metric: String = str(entry.get("completion_metric", ""))
        if not TUTORIAL_STEP_METRICS.has(metric):
            issues.append(Issue.new(path, id_label, "unknown completion_metric '%s' (expected one of %s)" % [metric, TUTORIAL_STEP_METRICS]))

    return issues

static func validate_glossary_term_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of glossary term records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_glossary_term_record(path, records[i], i, seen_ids))
    return issues

static func _validate_glossary_term_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "glossary term record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in GLOSSARY_TERM_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    for text_field: String in ["term", "definition"]:
        if entry.has(text_field) and (not (entry[text_field] is String) or String(entry[text_field]).is_empty()):
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty string" % text_field))

    return issues

static func validate_sfx_cue_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of SFX cue records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_sfx_cue_record(path, records[i], i, seen_ids))
    return issues

static func _validate_sfx_cue_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "SFX cue record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in SFX_CUE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("bus") and not SFX_CUE_BUSES.has(String(entry.get("bus"))):
        issues.append(Issue.new(path, id_label, "unknown bus '%s' (expected one of %s)" % [entry.get("bus"), SFX_CUE_BUSES]))

    if entry.has("waveform") and not SFX_CUE_WAVEFORMS.has(String(entry.get("waveform"))):
        issues.append(Issue.new(path, id_label, "unknown waveform '%s' (expected one of %s)" % [entry.get("waveform"), SFX_CUE_WAVEFORMS]))

    if entry.has("base_freq"):
        var base_freq: Variant = entry.get("base_freq")
        if not (base_freq is int or base_freq is float) or float(base_freq) <= 0.0:
            issues.append(Issue.new(path, id_label, "'base_freq' must be a number > 0"))

    if entry.has("gain_db"):
        var gain_db: Variant = entry.get("gain_db")
        if not (gain_db is int or gain_db is float) or float(gain_db) > 0.0:
            issues.append(Issue.new(path, id_label, "'gain_db' must be a number <= 0 (never boost above unity)"))

    var duration: float = float(entry.get("duration_sec", 0.0))
    if entry.has("duration_sec") and (not (entry.get("duration_sec") is int or entry.get("duration_sec") is float) or duration <= 0.0):
        issues.append(Issue.new(path, id_label, "'duration_sec' must be a number > 0"))

    var attack: float = float(entry.get("attack_sec", 0.0))
    if entry.has("attack_sec") and (not (entry.get("attack_sec") is int or entry.get("attack_sec") is float) or attack < 0.0):
        issues.append(Issue.new(path, id_label, "'attack_sec' must be a number >= 0"))

    var decay: float = float(entry.get("decay_sec", 0.0))
    if entry.has("decay_sec") and (not (entry.get("decay_sec") is int or entry.get("decay_sec") is float) or decay < 0.0):
        issues.append(Issue.new(path, id_label, "'decay_sec' must be a number >= 0"))

    # Structural "click-free" enforcement: an envelope that overruns the
    # clip would leave a raw, un-enveloped (clicking) sample at the seam.
    if entry.has("duration_sec") and entry.has("attack_sec") and entry.has("decay_sec") and duration > 0.0:
        if attack + decay > duration + 0.0001:
            issues.append(Issue.new(path, id_label, "'attack_sec' + 'decay_sec' (%.3f) must not exceed 'duration_sec' (%.3f) — would leave an un-enveloped, clicking sample" % [attack + decay, duration]))

    return issues

static func validate_epilogue_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of epilogue records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_epilogue_record(path, records[i], i, seen_ids))
    return issues

static func _validate_epilogue_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "epilogue record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in EPILOGUE_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    if entry.has("title") and (not (entry["title"] is String) or String(entry["title"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'title' must be a non-empty string"))
    if entry.has("body") and (not (entry["body"] is String) or String(entry["body"]).is_empty()):
        issues.append(Issue.new(path, id_label, "'body' must be a non-empty string"))

    return issues

static func validate_achievement_file(path: String) -> Array[Issue]:
    var issues: Array[Issue] = []
    if not FileAccess.file_exists(path):
        issues.append(Issue.new(path, "", "file does not exist"))
        return issues
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        issues.append(Issue.new(path, "", "could not open file (error %s)" % FileAccess.get_open_error()))
        return issues
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        issues.append(Issue.new(path, "", "root must be a JSON array of achievement records"))
        return issues

    var records: Array = parsed
    var seen_ids: Dictionary = {}
    var seen_triggers: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_achievement_record(path, records[i], i, seen_ids, seen_triggers))
    return issues

static func _validate_achievement_record(path: String, record: Variant, index: int, seen_ids: Dictionary, seen_triggers: Dictionary) -> Array[Issue]:
    var issues: Array[Issue] = []
    var record_label: String = "record #%d" % index
    if not (record is Dictionary):
        issues.append(Issue.new(path, record_label, "achievement record must be a JSON object"))
        return issues

    var entry: Dictionary = record
    for field: String in ACHIEVEMENT_REQUIRED_FIELDS:
        if not entry.has(field):
            issues.append(Issue.new(path, record_label, "missing required field '%s'" % field))

    var entry_id: String = str(entry.get("id", ""))
    var id_label: String = entry_id if not entry_id.is_empty() else record_label
    if entry.has("id"):
        if entry_id.is_empty():
            issues.append(Issue.new(path, record_label, "'id' must be a non-empty string"))
        elif seen_ids.has(entry_id):
            issues.append(Issue.new(path, entry_id, "duplicate id (first seen at record #%d)" % int(seen_ids[entry_id])))
        else:
            seen_ids[entry_id] = index

    for text_field: String in ["name", "description"]:
        if entry.has(text_field) and (not (entry[text_field] is String) or String(entry[text_field]).is_empty()):
            issues.append(Issue.new(path, id_label, "'%s' must be a non-empty string" % text_field))

    if entry.has("trigger"):
        var trigger: String = String(entry.get("trigger", ""))
        if not ACHIEVEMENT_TRIGGERS.has(trigger):
            issues.append(Issue.new(path, id_label, "unknown trigger '%s' (expected one of %s)" % [trigger, ACHIEVEMENT_TRIGGERS]))
        # Every trigger is 1:1 with an achievement — AchievementManager
        # unlocks the first (and only) matching achievement id per event,
        # so two records sharing a trigger would leave one unreachable.
        elif seen_triggers.has(trigger):
            issues.append(Issue.new(path, id_label, "trigger '%s' is already used by achievement '%s' — each trigger must map to exactly one achievement" % [trigger, seen_triggers[trigger]]))
        else:
            seen_triggers[trigger] = entry_id

    return issues

static func _is_whole_number_at_least(value: Variant, minimum: int) -> bool:
    if not (value is int or value is float):
        return false
    var f: float = float(value)
    return is_equal_approx(f, round(f)) and int(round(f)) >= minimum

## Runs validate_all() and pushes one actionable engine error per issue.
## Returns true if the data is clean.
static func run_startup_validation() -> bool:
    var issues: Array[Issue] = validate_all()
    issues.append_array(scan_for_real_world_marks())
    for issue: Issue in issues:
        push_error("DataValidator: %s" % issue.format())
    return issues.is_empty()

## Recursively scans every data/*.json file's string values (not just one
## record type at a time, unlike the schema validators above) for a real
## AI-company/product name. Whole-word matching only.
static func scan_for_real_world_marks() -> Array[Issue]:
    var issues: Array[Issue] = []
    var dir: DirAccess = DirAccess.open("res://data")
    if dir == null:
        issues.append(Issue.new("res://data", "", "could not open the data directory to scan for real-world marks"))
        return issues
    dir.list_dir_begin()
    var file_name: String = dir.get_next()
    while file_name != "":
        if file_name.ends_with(".json"):
            var path: String = "res://data/%s" % file_name
            var file: FileAccess = FileAccess.open(path, FileAccess.READ)
            if file != null:
                var parsed: Variant = JSON.parse_string(file.get_as_text())
                file.close()
                _scan_value_for_marks(path, "", parsed, issues)
        file_name = dir.get_next()
    dir.list_dir_end()
    return issues

static func _scan_value_for_marks(path: String, location: String, value: Variant, issues: Array[Issue]) -> void:
    if value is String:
        var lowered: String = String(value).to_lower()
        for mark: String in REAL_WORLD_MARKS:
            var re: RegEx = RegEx.new()
            re.compile("\\b%s\\b" % mark)
            if re.search(lowered) != null:
                issues.append(Issue.new(path, location, "contains the real-world mark '%s' in player-facing content: \"%s\"" % [mark, value]))
    elif value is Dictionary:
        for key: Variant in value.keys():
            _scan_value_for_marks(path, "%s.%s" % [location, String(key)] if not location.is_empty() else String(key), value[key], issues)
    elif value is Array:
        for i in value.size():
            _scan_value_for_marks(path, "%s[%d]" % [location, i], value[i], issues)
