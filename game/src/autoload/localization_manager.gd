extends Node

## Localization architecture (P45, extended in the finalization pass):
## a self-contained tr()/pseudo-locale layer, deliberately NOT built on
## Godot's TranslationServer/Translation classes — a custom Translation
## subclass (the idiomatic Godot approach) reproducibly crashes this
## project's Godot 4.7.2 headless build at shutdown, confirmed with a
## minimal reproduction (a *plain*, un-subclassed `Translation.new()`
## alone crashes on quit() in this environment, before any of this
## project's code runs). See docs/production/IMPLEMENTATION_STATUS.md.
##
## Two player-facing locales: "en" (the real, authored game text as
## written everywhere in the project — no key indirection needed) and
## "es" (real authored Spanish, data/locales/es.json: a flat map of the
## exact English source string -> its Spanish translation, covering both
## static UI text and every data-driven content string across
## data/*.json). A third, non-player-facing QA_PSEUDO_LOCALE keeps the
## original P45 pseudo-locale mechanism (algorithmic accenting + >=30%
## string expansion, for exercising UI layout/glyph rendering) — it is
## deliberately excluded from AVAILABLE_LOCALES so it never appears in
## the Settings language dropdown, but remains directly settable
## (LocalizationManager.set_locale(QA_PSEUDO_LOCALE)) for automated tests.

const AVAILABLE_LOCALES: Array[String] = ["en", "es"]
const DEFAULT_LOCALE: String = "en"
const QA_PSEUDO_LOCALE: String = "qa-pseudo"
## Flat file directly under res://data/ (not a subdirectory) so it is
## automatically covered by DataValidator.scan_for_real_world_marks(),
## which only lists res://data's immediate children.
const CONTENT_DICT_PATH: String = "res://data/locale_es.json"

static var _es_dict: Dictionary = {}
static var _es_dict_loaded: bool = false
static var _missing_keys: Dictionary = {}

## Never trust the host OS locale for this: a player (or this dev
## container, whose OS locale is Spanish) must see the real English text
## by default, unless they explicitly opt in via Settings.
func set_locale(locale_id: String) -> void:
    if not (AVAILABLE_LOCALES.has(locale_id) or locale_id == QA_PSEUDO_LOCALE):
        locale_id = DEFAULT_LOCALE
    SettingsManager.locale = locale_id

func current_locale() -> String:
    var raw: String = SettingsManager.locale
    if AVAILABLE_LOCALES.has(raw) or raw == QA_PSEUDO_LOCALE:
        return raw
    return DEFAULT_LOCALE

func locale_display_name(locale_id: String) -> String:
    match locale_id:
        "es":
            return "Español"
        QA_PSEUDO_LOCALE:
            return "Pseudo-locale (QA)"
        _:
            return "English"

static func _load_es_dict() -> void:
    if _es_dict_loaded:
        return
    _es_dict_loaded = true
    var file: FileAccess = FileAccess.open(CONTENT_DICT_PATH, FileAccess.READ)
    if file == null:
        push_error("LocalizationManager: could not open %s" % CONTENT_DICT_PATH)
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Dictionary:
        _es_dict = parsed
    else:
        push_error("LocalizationManager: %s root must be a JSON object" % CONTENT_DICT_PATH)

## The actual translation entry point every UI script and content display
## call routes real, player-facing text through. Same flat lookup for both
## code-authored UI strings and data-driven content strings — the "key" is
## simply the exact authored English source text.
func tr_text(source: String) -> String:
    var locale: String = current_locale()
    if locale == QA_PSEUDO_LOCALE:
        return PseudoLocale.pseudo_localize(source)
    if locale == "es":
        _load_es_dict()
        if _es_dict.has(source):
            return String(_es_dict[source])
        if not source.is_empty():
            _missing_keys[source] = true
        return source
    return source

## QA/CI hook (docs/qa/EXPORTED_BUILD_SMOKE.md, tools/i18n_report.py): every
## English source string that was looked up under "es" and had no
## translation, so it silently fell back to English. Not an error by
## itself (graceful fallback is the point), but worth tracking so
## untranslated content doesn't go unnoticed.
static func missing_translation_keys() -> Array:
    return _missing_keys.keys()

static func reset_missing_translation_keys() -> void:
    _missing_keys.clear()

## Localizes every text-bearing Control under `root` (Label/Button/
## CheckButton/LinkButton text, plus tooltip_text on any Control) in
## place. The ORIGINAL source string is cached in metadata so calling
## this again after a locale change re-derives from the real source
## instead of compounding an already-pseudo-localized string.
func localize_control_tree(root: Node) -> void:
    _localize_node(root)
    for child in root.get_children():
        localize_control_tree(child)

func _localize_node(node: Node) -> void:
    if not (node is Control):
        return
    var control: Control = node
    if "text" in control and control.get("text") is String and not String(control.get("text")).is_empty():
        var source_text: String = String(control.get_meta("i18n_source_text", control.get("text")))
        control.set_meta("i18n_source_text", source_text)
        control.set("text", tr_text(source_text))
    var tooltip: String = control.tooltip_text
    if not tooltip.is_empty():
        var source_tooltip: String = String(control.get_meta("i18n_source_tooltip", tooltip))
        control.set_meta("i18n_source_tooltip", source_tooltip)
        control.tooltip_text = tr_text(source_tooltip)
