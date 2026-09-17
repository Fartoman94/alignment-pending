# UI cleanup pass report

Response to `ALIGNMENT_PENDING_WORLD_AND_NPC_OVERHAUL`'s prompt 06 ("La UI roba demasiado espacio y parece debug"), a repeat ask — the prior garage-recovery pass this session flagged the same complaint and deliberately deferred a full rebuild rather than rush a risky restructure of `hud.gd`'s ~20 `_dynamic_content` consumers.

## What was verified first, not assumed

Before changing anything, tested the specific claim the prior pass had made from reading code alone: that the Staff/Glossary side panel isn't literally stuck open forever. Did this for real — drove the actual HUD through the real "New Campaign" button, clicked Staff, then simulated a scene-object selection (`EventBus.selection_changed`, exactly what clicking an NPC/building fires) — and confirmed by screenshot that the panel really does clear back to a compact "Selected: ..." view. Not fixed, but not the "permanently blocking" problem the brief's wording implies either; worth knowing before deciding what to actually build.

## What changed

`scenes/hud.tscn`: `LeftPanel` (Inbox) narrowed 260px → 220px. Gives the 3D viewport real extra width, verified by rendering — the room reads noticeably larger in the default view. `RightPanel` was tried at 340px (down from 400px) and reverted — see below.

## A real bug found, not introduced, and not blindly worked around

Narrowing `RightPanel` to 340px made `Hud._show_world_panel()`'s rival/office-upgrade rows visibly overflow the right edge — text literally running off-screen. Before assuming the width change caused this, re-tested at the *original* 400px width: the same overflow is there, just less obviously (still runs past the edge, just by less). This is a pre-existing bug, not a regression from this pass — confirmed by screenshot comparison at both widths, not assumed from reading the code (every `Label` involved already has `autowrap_mode` set correctly, so the code alone doesn't explain it).

Given the underlying cause wasn't identified within this pass's time budget (see `docs/production/KNOWN_ISSUES.md`'s new "UI bugs found, not yet fixed" entry for what was ruled out), shrinking `RightPanel` further would have made an existing readability bug worse, not better — reverted to 400px rather than ship a panel that's narrower *and* more visibly broken. `LeftPanel`'s reduction was verified clean across Staff, Glossary, Research, Company, and World and kept.

## Not attempted this pass

- The `_show_world_panel()` overflow's actual root-cause fix — flagged, not fixed (see `KNOWN_ISSUES.md`).
- A dedicated non-blocking Staff/Glossary "screen" (as opposed to the existing docked panel) — still the larger, separate initiative named in the prior pass's own report (`docs/design/GARAGE_VERTICAL_SLICE_REPORT.md`).
- Top HUD bar / bottom nav compactness ("HUD superior compacto", "tabs inferiores con mejor presencia") — not touched; the highest-risk, most speculative part of this prompt without a clearer sense of what's actually crowded there.
