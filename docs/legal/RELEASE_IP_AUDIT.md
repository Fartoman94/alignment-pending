# Release IP/legal/AI-disclosure audit

Finalization pack prompt 29. Covers what an automated audit + code/content review can actually verify; the human/business actions it can't (trademark clearance, Steam survey filing) are called out explicitly rather than checked off.

## Names, logos, copy

- **Real-world AI-company/product marks**: `DataValidator.scan_for_real_world_marks()` walks every `data/*.json` file's string values (title/body/label/name/description/etc.) against a 21-term blocklist (`openai`, `anthropic`, `google`, `deepmind`, `meta`, `microsoft`, `xai`, `mistral`, `cohere`, `claude`, `chatgpt`, `gpt`, `gemini`, `llama`, `copilot`, `grok`, `bard`, `palm`, `nvidia`, `amazon`, `apple`), whole-word matching, wired into the permanent startup validation gate and `tools/bootstrap.sh`. Zero hits as of this commit, re-verified after this pass added `data/locale_es.json` (703 Spanish strings) — which itself caught one real false-positive during translation (the Spanish verb "llama", reworded) proving the scanner actually works on real content, not just English.
- **Company/product name**: the in-fiction company is "Null Meridian Labs" (per the epilogue text) — an invented name, not a play on any real lab's name.
- **Working title** "ALIGNMENT PENDING": informal web-collision check only, not legal clearance — see `docs/legal/TITLE_CLEARANCE.md` (unchanged, still needs a qualified IP professional's review before commercial announcement).
- **Logo/wordmark** (`assets/ui/alignment_pending_logo.svg`) and **app icon** (`assets/branding/icon.svg`, added this pass): both built from scratch as vector primitives (rectangles, a circle, text) for this project, not derived from or resembling any real company's mark.

## Incidents, rivals, world content

- 83 incidents (`data/events_seed.json`): fictional scenarios in the "AI company" genre generically (model reliability, safety, security, legal, media, staff, market pressure) — none reference a real company, real product, real person, or a real documented incident by name.
- Rival companies: procedurally generated names, verified by `tools/bootstrap.sh`'s own assertion ("no rival is named after or mapped to a real company") — this isn't just a claim, it's an automated check that runs every bootstrap.
- Regulator ("Central AI Compliance Authority"): a generic invented body, not a real regulator (no reference to any real AI-safety agency, government body, or real legislation by name).

## Characters/likenesses

- No named individual characters exist in the shipped content — staff/executives are procedurally generated (name + role + traits), not depictions of real people. No character art/portraits exist yet (deferred, see `KNOWN_ISSUES.md`'s visual-asset scope boundary) — nothing to audit for likeness risk there because nothing has been drawn.

## Audio

- 100% procedurally synthesized at runtime (`AudioSynth`/`AudioManager`, P41) — no sampled, recorded, or downloaded audio files anywhere in the project (`find game -name "*.wav" -o -name "*.ogg" -o -name "*.mp3"` returns nothing). Nothing to clear.

## Fonts, textures, models

- **Fonts**: zero bundled font files — every `Control` uses Godot's built-in default font (already audited, `RELEASE_CHECKLIST.md`).
- **Textures**: no imported/downloaded texture files beyond this pass's own originally-authored `assets/branding/icon*.png` (rasterized from the project's own SVG) and the pre-existing `assets/ui/*.svg` concept art. All office/staff/prop geometry is `StandardMaterial3D` procedural coloring, not textures.
- **3D models**: zero imported mesh files (`.glb`/`.fbx`/`.obj`/etc.) anywhere in the project — every mesh (office geometry, staff bodies) is built at runtime from primitive `BoxMesh`/`CapsuleMesh`/`CylinderMesh` via `ProceduralMeshFactory`, per `docs/legal/ASSET_PROVENANCE.md`.

## Licenses, third-party packages

- **Godot Engine 4.7.2 stable**: MIT-licensed, the approved engine dependency per `CLAUDE.md`; downloaded from the official `godotengine/godot` GitHub release and SHA512-verified against the release's own published checksums before use (both the editor and the export templates).
- **Third-party addons/packages**: none. No `addons/` directory exists; every numbered prompt's own constraint against unapproved dependencies held. `tools/bootstrap.sh` asserts this directly ("no third-party addons ... ship with the project").
- **This finalization pass's own tooling dependencies** (all dev-only, never shipped in the game build — see `export_presets.cfg`'s `exclude_filter`): Python 3's standard library + Pillow (for building `icon.ico` from PNGs) and GitHub Actions' own `actions/checkout`/`actions/cache`/`actions/upload-artifact` (for CI). None of these ship inside the exported game.

## AI-assisted content inventory (for Steam's Content Survey)

Every line of this project — code, design docs, and content — was written by Claude (Anthropic) working from the human owner's numbered prompts and the finalization pack, visible in this repository's own commit history. Concretely, by category:

| Category | AI-assisted? | Detail |
|---|---|---|
| Code (GDScript, all systems) | Yes | All ~14K+ lines across `game/src/` |
| Narrative/incident text (English) | Yes | All 83 incidents, tutorial, glossary, epilogues, etc. — original writing, not generated from/trained-on any specific copyrighted source text |
| Spanish translation | Yes | `data/locale_es.json`, 703 entries — see `docs/design/LOCALIZATION_CONTENT.md`'s "Known limitation": first-pass, not yet human-reviewed |
| Audio (SFX/music) | Yes | Procedural synthesis code and its parameters (P41) |
| Visual assets (icon/wordmark) | Yes | Vector primitives, no image-generation model involved — literal `<rect>`/`<circle>`/`<path>` SVG authored directly |
| Documentation | Yes | Every doc under `docs/` |

Per `docs/legal/STEAM_AI_DISCLOSURE_NOTE.md` (unchanged): the human owner should disclose this accurately in Steamworks' Content Survey per whatever the platform's rules are at submission time — this audit's job is to make sure that disclosure would be *accurate*, not to file it (needs a Steamworks account, a human/business action).

## Explicitly not covered by this audit (human/business actions)

- Trademark/title clearance (`docs/legal/TITLE_CLEARANCE.md`) — needs a qualified IP professional.
- Steam Content Survey filing — needs a Steamworks partner account.
- Store art / trailer footage's own clearance once actually produced (music licensing if any is added, etc.) — nothing has been produced yet to clear (see `docs/production/STEAM_STORE_AND_DEMO.md`'s briefs, this pass).

## Conclusion

No real-world IP violations found in anything this audit can check automatically or by direct content review. The two open items are explicitly human/business actions (title clearance, platform disclosure filing) that were already correctly flagged as such before this pass and remain so — this audit found nothing new to add to that list, only confirmed the automated guardrails (mark scanner, rival-naming check, dependency/addon check) are real, wired into the permanent test gate, and still pass clean after this pass's changes.
