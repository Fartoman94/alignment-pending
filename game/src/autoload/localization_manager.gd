extends Node

## Localization architecture (P45): a self-contained tr()/pseudo-locale
## layer, deliberately NOT built on Godot's TranslationServer/Translation
## classes — a custom Translation subclass (the idiomatic Godot approach
## for a generated pseudo-locale) reproducibly crashes this project's
## Godot 4.7.2 headless build at shutdown, confirmed with a minimal
## reproduction (a *plain*, un-subclassed `Translation.new()` alone
## crashes on quit() in this environment, before any of this project's
## code runs). See docs/production/IMPLEMENTATION_STATUS.md for the
## reproduction and the decision to avoid the engine class entirely
## rather than ship something the CI harness can't even run.
##
## "en" is the real, authored game text as written everywhere in the
## project (no key indirection needed). "es" is a *test* locale, not a
## real Spanish translation: PseudoLocale.pseudo_localize() transforms it
## algorithmically, guaranteeing every string is both accented (exercises
## non-ASCII glyph rendering) and >=35% longer than the source (the
## "+30% string expansion" acceptance criterion) — a real Spanish
## translation could easily be shorter than English and wouldn't reliably
## prove either thing.

const AVAILABLE_LOCALES: Array[String] = ["en", "es"]
const DEFAULT_LOCALE: String = "en"

## Never trust the host OS locale for this: a player (or this dev
## container, whose OS locale is Spanish) must see the real English text
## by default, unless they explicitly opt in via Settings.
func set_locale(locale_id: String) -> void:
    if not AVAILABLE_LOCALES.has(locale_id):
        locale_id = DEFAULT_LOCALE
    SettingsManager.locale = locale_id

func current_locale() -> String:
    return SettingsManager.locale if AVAILABLE_LOCALES.has(SettingsManager.locale) else DEFAULT_LOCALE

func locale_display_name(locale_id: String) -> String:
    match locale_id:
        "es":
            return "Pseudo-Spanish (QA)"
        _:
            return "English"

## The actual translation entry point every UI script routes real,
## player-facing text through.
func tr_text(source: String) -> String:
    if current_locale() == "es":
        return PseudoLocale.pseudo_localize(source)
    return source

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
