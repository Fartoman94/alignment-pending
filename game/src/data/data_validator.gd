class_name DataValidator
extends RefCounted

## Startup validator for JSON content data: duplicate IDs, missing required
## fields, invalid numeric ranges. Only validates fields the current data
## actually uses (see docs/technical/DATA_SCHEMA.md).

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
const EVENT_EFFECT_KEYS: Array[String] = ["cash", "public_trust", "safety_debt"]
# IncidentManager's generic min_<metric>/max_<metric> prerequisite vocabulary.
const EVENT_CONDITION_METRICS: Array[String] = [
    "safety_debt", "public_trust", "cash", "deployed_models_count",
    "staff_count", "models_count", "calendar_day", "compute_used_ratio",
    "total_user_scale", "total_incident_exposure",
]

const BUILDABLE_REQUIRED_FIELDS: Array[String] = ["id", "name", "category", "footprint", "cost", "refund_ratio"]

const STAFF_ROLE_REQUIRED_FIELDS: Array[String] = ["id", "name", "base_salary_min", "base_salary_max", "primary_skill"]
const STAFF_SKILL_KEYS: Array[String] = ["capability", "engineering", "operations", "safety", "communication"]

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
    issues.append_array(validate_work_task_file("res://data/work_tasks.json"))
    issues.append_array(validate_research_node_file("res://data/research_nodes.json"))
    issues.append_array(validate_model_tier_file("res://data/model_tiers.json"))
    issues.append_array(validate_deployment_mode_file("res://data/deployment_modes.json"))
    issues.append_array(validate_user_segment_file("res://data/user_segments.json"))
    issues.append_array(validate_communication_action_file("res://data/communication_actions.json"))
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
    var seen_ids: Dictionary = {}
    for i in records.size():
        issues.append_array(_validate_event_record(path, records[i], i, seen_ids))
    return issues

static func _validate_event_record(path: String, record: Variant, index: int, seen_ids: Dictionary) -> Array[Issue]:
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

static func _is_whole_number_at_least(value: Variant, minimum: int) -> bool:
    if not (value is int or value is float):
        return false
    var f: float = float(value)
    return is_equal_approx(f, round(f)) and int(round(f)) >= minimum

## Runs validate_all() and pushes one actionable engine error per issue.
## Returns true if the data is clean.
static func run_startup_validation() -> bool:
    var issues: Array[Issue] = validate_all()
    for issue: Issue in issues:
        push_error("DataValidator: %s" % issue.format())
    return issues.is_empty()
