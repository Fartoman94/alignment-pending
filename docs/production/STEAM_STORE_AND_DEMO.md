# Steam store/demo production plan

## Store positioning
Pitch the systems and satire, not controversy involving specific real companies.

Suggested short description draft:
> Build an AI lab from a cramped office into a global institution. Train models, hire researchers, buy compute, survive incidents, negotiate regulators, and decide when “probably safe” is safe enough to ship.

## Screenshot targets
1. Small starter office with staff and racks.
2. Model evaluation/release decision.
3. Incident crisis panel over busy office.
4. Expanded campus/datacenter screen.
5. Research tree.
6. Endgame office at night.

## Demo
Target 30–45 minute vertical slice. End immediately after the first major governance crisis and show wishlist CTA. Demo saves should be separate from retail unless migration is explicitly supported.

## Trailer beats
Office build -> training -> benchmark success -> SHIP decision -> users spike -> alert -> board/regulator montage -> late-game datacenter -> title.

No real company marks, screenshots, executive images, or copied news layouts in marketing.

---

## Store art briefs (finalization pack prompt 27)

Specs and composition briefs only — the actual creative production (final capsule art, hero art, trailer footage/edit) is a human/design task this pass cannot do; see `docs/production/KNOWN_ISSUES.md`. Every brief below reuses the project's own established visual language: `docs/design/ART_BIBLE.md`'s low-poly corporate-satire palette, and `assets/branding/icon.svg`'s mark (purple/teal triangle pair + gold circle on `#11151b`) as the one recurring graphic element across all sizes, so the store presence reads as one system rather than one-off art per asset.

| Asset | Size (Steam spec) | Composition brief |
|---|---|---|
| Icon | 32x32 (client), 184x184 (Steam friends/library tile) | `assets/branding/icon.svg`'s mark alone, no wordmark — it has to read at 32px. Already built; export directly. |
| Small capsule | 231x87 | Wordmark (`assets/ui/alignment_pending_logo.svg`) left-aligned on the dark palette background, no scene art — this size is too small for a readable illustrated scene. |
| Header capsule | 460x215 | Wordmark top-left; a simple isometric vignette of the starter office (desk + server rack silhouettes, low-poly, matching in-game asset style) bottom-right, fading into the dark background so text stays legible over it. |
| Main capsule | 616x353 | The same office vignette, larger and more detailed — desk, server rack, one staff silhouette — with the tagline ("Build an AI lab. Ship the model. Live with the decision.") beneath the wordmark. This is the first thing a browsing Steam user sees; it should communicate "management sim" + "AI" + "consequences" in one glance without any UI screenshot clutter. |
| Library capsule | 600x900 (vertical) | Wordmark top, a taller single-column composition: starter office at the bottom grounding the scene, a research-tree/data-visualization motif (abstract, geometric, matching the UI Kit's node/line language, not a literal screenshot) rising through the middle, capped by an "ACT V" nod near the top — a visual "small office to institution" progression read top-to-bottom in one image. |
| Library hero | 3840x1240 (ultra-wide banner) | A wide establishing shot: the expanded campus/datacenter silhouette (P30's datacenter tiers) spanning the full width, low-poly and dusk-lit per the Art Bible's palette, wordmark centered or left-third. This is the banner behind the library page — keep the center-third clear of important detail since store UI overlays it. |
| Library logo | 640x360, transparent background | Wordmark only (`assets/ui/alignment_pending_logo.svg`, already original/authored), no background art — this overlays on top of the hero art above. |

**Direction, all assets:** management sim + fictional AI + the capability/safety tension, satirical corporate tone, 3D stylized/low-poly. No real company logos, no likenesses, nothing that could be mistaken for a real AI lab's branding (per `docs/legal/IP_AND_SATIRE_GUARDRAILS.md`, unchanged from the original prompt's rules).

## Screenshot capture list (prompt 28)

Concrete, capturable *from the real running game* (no mockups) once export/QA allow a windowed capture session — each maps to an existing, working panel this pass verified is real (`docs/qa/EXPORTED_BUILD_SMOKE.md`, `tools/gpu_profile.gd`'s scenarios):
1. Starter office, empty, camera at the default isometric angle — establishes the "cramped office" starting point.
2. Build mode open, a server rack ghost preview mid-placement.
3. Staff panel with several hired employees, one inspected (role/traits visible).
4. Research tree panel, several nodes unlocked, one in progress.
5. Model evaluation panel showing an uncertainty range pre-reveal.
6. Incident inbox with an active P0/P1 crisis and its choice buttons.
7. Deployment panel, a model at Public with the rollout/rate-limit controls.
8. World/company panel: rivals, regulator pressure, and the daily ledger together (busy, information-dense — the "management sim" proof shot).
9. Late-game: an expanded datacenter tier owned, 100+ staff, Act IV/V banner visible.

`tools/gpu_profile.gd`'s three scenarios (empty office / 20 staff / 150-staff stress) already prove 1, 3, and 9 are reachable and render correctly — a human capture session just needs to run the exported binary windowed and screenshot these moments instead of scripting them.

## Trailer script (prompt 28), 60 seconds

Footage-only rule (already in this doc, restated): every beat below must be real captured gameplay, nothing staged/faked, no feature shown that doesn't exist in the build.

| Time | Beat | On screen |
|---|---|---|
| 0:00-0:05 | Hook | Cold open on the incident inbox mid-crisis (a P0 alert), then cut to black with the wordmark. Text overlay: "Every model ships eventually." |
| 0:05-0:15 | Build the company | Rapid cuts: empty office → placing a desk → placing a server rack → hiring a candidate from the Staff panel. |
| 0:15-0:25 | Train | Research tree panel (node unlocking), then the training panel with a project in progress, progress bar climbing. |
| 0:25-0:35 | Push capability | Evaluation panel: uncertainty range narrowing across a couple of eval passes, then the Deploy button pressed — Internal → Beta → Public rollout stages shown in quick succession. |
| 0:35-0:45 | Consequences | The incident inbox again, a different crisis this time, the player choosing a response; cut to the regulator/board panels ticking up pressure; a rival's launch notification. |
| 0:45-0:52 | Scale | Late-game beat: datacenter tier purchase, staff roster past 100, Act banner advancing. |
| 0:52-0:58 | Title card | Wordmark centered, tagline beneath: "Build. Train. Ship. Explain." (already the in-universe tagline baked into `assets/ui/alignment_pending_logo.svg`). |
| 0:58-1:00 | CTA | "Wishlist now" / store page URL placeholder. |

This is a shot list and edit plan, not a rendered video — actually capturing and editing the footage is a human/creative task outside this pass's tooling.
