# Content localization — real Spanish, wired end-to-end

Follow-up to `docs/production/KNOWN_ISSUES.md`'s "content localization" scope boundary and the finalization pack's prompt 23. Status: **done** — every player-facing string in the game (static UI, dynamic UI templates, and all 27 `data/*.json` content catalogs) is real, translated, and connected.

## Architecture

Unchanged from P45's `LocalizationManager.tr_text(source: String) -> String` — the "key" is the exact authored English source string, no separate key namespace needed (this was already the project's convention: "en is the real, authored game text as written everywhere in the project"). What changed:

- **`"es"` is now real, authored Spanish** (`data/locale_es.json`, a flat `{English: Spanish}` map, 703 entries), not the P45 pseudo-locale. `tr_text()` looks the source up; on a hit it returns the translation, on a miss it falls back to the English source and records the miss (`LocalizationManager.missing_translation_keys()`) rather than crashing or showing a blank string.
- **The original P45 pseudo-locale mechanism is preserved**, just moved off `"es"` onto `LocalizationManager.QA_PSEUDO_LOCALE` (`"qa-pseudo"`), which is deliberately excluded from `AVAILABLE_LOCALES` so it never appears in the Settings language dropdown — it remains directly settable for the automated +30%-expansion/glyph-rendering QA checks `tests/smoke_test.gd` already ran under "es".
- `data/locale_es.json` lives as a flat file directly under `res://data/` (not a subdirectory) specifically so `DataValidator.scan_for_real_world_marks()` — which only lists `res://data`'s immediate children — automatically scans translated content for real-world AI-company marks the same as every other catalog. It already caught one real false-positive this way: the Spanish verb "llama" (to knock/call) in an incident title tripped the whole-word "llama" (as in the Meta model family) mark check, and was reworded rather than the validator being weakened.

## What's covered

- **All 27 `data/*.json` catalogs**: incidents (83, the bulk of the content — title/body/every choice label), tutorial steps, glossary terms, achievements, epilogues, staff roles/traits, research nodes, campaign acts, news templates' structural strings, and every smaller catalog (buildables, deployment modes, model tiers, subscription plans, legal case types, communication actions, world variables, workforce policies, datacenter tiers, rival doctrines, funding rounds, agent permissions, user segments, work tasks, board/regulator track names).
- **Every static `.tscn` Label/Button/tooltip string** across all 7 scenes (main menu, settings, HUD, ending, credits) — reached via `LocalizationManager.localize_control_tree()`, which every top-level scene script now calls in `_ready()` (`ending_screen.gd` and `credits_screen.gd` didn't before this pass; they do now).
- **Every dynamic UI format-string template** in `src/ui/hud.gd` (~45 call sites) and `src/ui/ending_screen.gd`, `src/menu/settings_menu.gd`'s keybind-remap labels — wrapped in `LocalizationManager.tr_text()` at the point of display, so the string is (re-)evaluated under whatever locale is active whenever that panel refreshes (which happens reactively on every relevant `EventBus` signal already, since that's how these panels stay in sync with game state in English too — no separate "re-render on locale change" plumbing needed for these, unlike static text).
- `EndingManager.MILESTONE_LABELS` (a `.gd`-defined constant dictionary, not JSON) — found by auditing every `tr_text()` call site by hand, not just grepping `data/*.json`.

## Verified

- `tools/bootstrap.sh` (199 assertions, including the rewritten P45 locale block): `tr_text()` returns real Spanish under `"es"`, falls back gracefully and tracks misses for an intentionally-untranslated probe string, the real main menu's "New Campaign" button reads "Nueva Partida" under `"es"` and still round-trips through the QA pseudo-locale's +30% expansion contract and back to exact English.
- `DataValidator`'s release-candidate content gate (schema + real-world-mark provenance scan) passes clean with `locale_es.json` included in the scan.
- Zero missing translations: a one-off audit script cross-referencing every text field across all 27 catalogs plus every static `.tscn` string plus every `tr_text()` literal found in `.gd` files against `data/locale_es.json` reported 0 gaps at the time of this pass (not itself part of the automated suite — if new content is added later without a translation, `tr_text()`'s graceful English fallback means nothing breaks, it just silently shows English; check `LocalizationManager.missing_translation_keys()` after a playthrough in `"es"` to catch drift).

## Known limitation

The Spanish translation was produced by Claude in this pass, not reviewed by a native-speaker localization professional. It is real, complete, and grammatically consistent Argentine-neutral Spanish (voseo avoided in favor of neutral forms except where a tutorial line directly addresses the player informally), but per this finalization pack's own prompt 23 ("no traducir automáticamente sin revisión si el juego va a shipping"), a human review pass is recommended before treating it as shipping-final — the pipeline and content are both ready for that review, which is the deliverable this prompt actually asked for.
