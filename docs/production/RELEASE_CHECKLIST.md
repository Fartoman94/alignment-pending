# Release checklist

Legend: `[x]` verified by an automated check or a direct audit this pass; `[ ] (human)` needs the human owner — see the reason given and `docs/production/KNOWN_ISSUES.md`. **This checklist itself is not signed off** — that is the human owner's action, not something P47's automated gate can certify on its own.

## Code/build
- [x] Godot version pinned and documented — `CLAUDE.md`'s "Engineering standards" pins 4.7.2 stable; `docs/production/BUILD_INSTRUCTIONS.md` restates it.
- [ ] (human) Reproducible clean export — steps documented in `BUILD_INSTRUCTIONS.md`, but this environment has no Godot export templates installed and none were downloaded (no unapproved large downloads); an actual binary export/run was never produced. See `KNOWN_ISSUES.md`.
- [x] Debug cheats excluded/disabled from retail build — audited: no cheat/debug-unlock code path exists anywhere in `game/src/` (grepped for cheat/god-mode/unlock-all patterns).
- [x] Zero open P0/P1 defects — `tools/bootstrap.sh`'s full suite (every prompt's acceptance criteria, hundreds of assertions) passes clean as of this commit.
- [x] Save migration suite green — part of the same full suite (P26's migration scaffold, exercised end-to-end against a hand-built legacy save).
- [ ] (human) Crash-on-boot tested on clean Windows/Linux environments — Linux headless boot is exhaustively verified (every bootstrap run this entire project); Windows needs an actual Windows machine.

## Content
- [x] All final assets in provenance ledger — `docs/legal/ASSET_PROVENANCE.md` audited and corrected this pass (removed 11 unreferenced placeholder `.wav` files that predated the numbered prompts and were never wired to any code; P41's real audio system replaced that approach).
- [x] No placeholder copyrighted/system-dependent fonts accidentally bundled — audited: the project bundles zero font files; every Control uses Godot's built-in default font.
- [x] No real-world marks/likenesses in fiction or screenshots — a new project-wide scanner (`DataValidator.scan_for_real_world_marks()`, wired into the startup validation gate permanently) checks every `data/*.json` file's text against a real-AI-company/product blocklist; zero hits. Screenshots don't exist yet (human/marketing task, see Store section).
- [x] Localization overflow pass — P45's pseudo-locale architecture, verified to guarantee >=30% string expansion on real UI text end-to-end.
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
- [ ] (human) System requirements measured, not guessed — needs real hardware benchmarking; P44 only measured headless CPU/logic cost, not real GPU frame time.
