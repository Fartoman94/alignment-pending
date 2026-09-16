# Release checklist

Legend: `[x]` verified by an automated check or a direct audit; `[~]` partially resolved — real, verified progress exists, but a human/real-hardware step is still explicitly needed before calling it done; `[ ] (human)` not started, needs the human owner — see the reason given and `docs/production/KNOWN_ISSUES.md`. **This checklist itself is not signed off** — that is the human owner's action, not something an automated gate can certify on its own.

## Code/build
- [x] Godot version pinned and documented — `CLAUDE.md`'s "Engineering standards" pins 4.7.2 stable; `docs/production/BUILD_INSTRUCTIONS.md` restates it.
- [x] Reproducible clean export — resolved in the finalization pass. `tools/export_release.sh` reproducibly exports+packages+checksums both `Linux` and `Windows Desktop` release presets (`game/export_presets.cfg`, committed). Export templates installed from the official Godot 4.7.2 stable release, SHA512-verified before use.
- [x] Debug cheats excluded/disabled from retail build — audited: no cheat/debug-unlock code path exists anywhere in `game/src/` (grepped for cheat/god-mode/unlock-all patterns).
- [x] Zero open P0/P1 defects — `tools/bootstrap.sh`'s full suite (200 assertions, every prompt's acceptance criteria) passes clean as of this commit.
- [x] Save migration suite green — part of the same full suite (P26's migration scaffold, exercised end-to-end against a hand-built legacy save).
- [~] Crash-on-boot tested on clean Windows/Linux environments — Linux is now verified two ways: exhaustive headless-source testing (every bootstrap run this whole project) *and*, new this pass, the actual packaged Linux binary running standalone outside the editor (`--qa-exported-smoke`, see `docs/qa/EXPORTED_BUILD_SMOKE.md`). Windows `.exe` is built/packaged by the same pipeline but **(human)** still needs an actual Windows machine to run on — that part remains open.

## Content
- [x] All final assets in provenance ledger — `docs/legal/ASSET_PROVENANCE.md` audited and corrected this pass (removed 11 unreferenced placeholder `.wav` files that predated the numbered prompts and were never wired to any code; P41's real audio system replaced that approach).
- [x] No placeholder copyrighted/system-dependent fonts accidentally bundled — audited: the project bundles zero font files; every Control uses Godot's built-in default font.
- [x] No real-world marks/likenesses in fiction or screenshots — a new project-wide scanner (`DataValidator.scan_for_real_world_marks()`, wired into the startup validation gate permanently) checks every `data/*.json` file's text against a real-AI-company/product blocklist; zero hits. Screenshots don't exist yet (human/marketing task, see Store section).
- [x] Localization overflow pass — P45's pseudo-locale architecture (now `QA_PSEUDO_LOCALE`), verified to guarantee >=30% string expansion on real UI text end-to-end.
- [x] Content localization — resolved in the finalization pass. Real, complete Spanish translation (798 strings: all 27 `data/*.json` catalogs, every static scene label, every dynamic UI template) wired end-to-end and selectable in Settings, including a real bug fix (a GDScript operator-precedence issue meant ~64 dynamic/templated strings silently never translated despite being "in the dictionary" — found during the UI polish pass below, fixed, pinned down with a regression test). See `docs/design/LOCALIZATION_CONTENT.md`. **(human)** not yet reviewed by a native-speaker localization professional before treating it as shipping-final.
- [x] Audio mastering pass and loop audit — N/A by construction: all SFX/music is procedurally synthesized at runtime (P41) with gain levels enforced by `DataValidator`'s schema rules and loops proven phase-continuous/click-free by construction; no separately-authored audio files to master.

## Legal/platform
- [ ] (human) Final title trademark clearance — legal/business action.
- [ ] (human) Steam content survey completed accurately — needs a Steamworks account.
- [ ] (human) AI-assisted shipped content disclosed if required by current rules — this project's git history plainly shows every commit was AI-authored; the human owner should disclose that accurately wherever the current platform rules require it.
- [x] Privacy policy only if telemetry/account data actually requires it — audited: zero network calls anywhere in `game/src/` (no `HTTPRequest`/`HTTPClient`/`WebSocket` usage); the game is fully offline with local-only saves, so no privacy policy is required.
- [x] Third-party notices complete — audited: no `addons/` directory and no third-party dependency was ever added (verified against every prompt's own constraint against unapproved packages); there is nothing to give notice for.

## Store
- [ ] (human) Capsules/icons original — creative asset production, not yet done; plan exists in `docs/production/STEAM_STORE_AND_DEMO.md`.
- [ ] (human) Trailer uses cleared music/assets — not yet produced.
- [ ] (human) Screenshots match actual build — not yet produced.
- [~] System requirements measured, not guessed — this pass added a real GPU-rendered profile (`docs/performance/REAL_GPU_PROFILE.md`): 55-60 FPS sustained through an empty office, 20 staff, and the 150-staff stress scenario on this dev container's AMD integrated GPU. That's real evidence the render path performs, but **(human)** it's one integrated GPU in one dev container, not a defined minimum-spec target or a player's discrete GPU — real system-requirements numbers still need a benchmark pass on actual target hardware.
- [x] Achievements complete — all 10 draft achievements from `docs/design/ACHIEVEMENTS_AND_META.md` implemented with real tracked-state detection (the 4 that were deferred in P46 are done as of this pass — see `KNOWN_ISSUES.md`).
- [~] UI/UX polish (prompt 09) — real confirmation dialogs added for every previously-one-click destructive action (fire staff, roll back a deployment), a genuinely new bug found and fixed in the process (`ConfirmationDialog.popup_centered()`/`grab_focus()` throw if called synchronously right after `add_child()` — needs one deferred frame, reproduced directly), and end-to-end tested through the real HUD scene (button press → dialog → confirm → the actual manager call), not just the manager API. A few empty-state messages were also localized that the earlier localization pass missed. Not a full audit of every panel's spacing/hover/focus states (prompt 09's broader scope) — this pass targeted the highest-risk gap (irreversible actions with zero confirmation) rather than a cosmetic sweep.
