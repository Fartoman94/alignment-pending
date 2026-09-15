# ALIGNMENT PENDING — Development Kit v0.1

**Working title:** ALIGNMENT PENDING  
**Genre:** 3D management sim + narrative strategy + roguelite satire  
**Engine target:** Godot 4.7.2 stable  
**Camera:** orthographic/isometric-like 3D, rotatable in 90° steps, smooth zoom/pan  
**Visual identity:** original low-poly retro-futurist office simulation. Inspired by the *era* of early 3D management games, not by any specific game's assets, interface, characters, animations, names, music, or trade dress.

## One-sentence pitch
Build an artificial-intelligence company from a cramped office into a civilization-scale institution while balancing capability, safety, trust, money, regulation, compute, employees, and the increasingly awkward question of whether shipping one more model is a good idea.

## Non-negotiables
1. No real AI-company names, logos, executives, model names, slogans, interfaces, voices, datasets, or distinctive branding in the shipped fiction.
2. No copied third-party art, music, sound, code, fonts, UI kits, icons, textures, or 3D models.
3. All included placeholder player-facing assets in this kit are generated specifically for this project from simple geometry/vector/procedural synthesis.
4. Any final commercial release must complete trademark/title clearance and Steam's current content disclosures.
5. Claude must not download random assets or paste code of uncertain license. External dependencies require explicit approval and a license record.
6. Single-player first. No networking until the single-player simulation is stable and fun.

## Start here with Claude Code
From the extracted folder:

```bash
cd ALIGNMENT_PENDING_DEVKIT_v0.1
claude
```

Then paste the contents of `MASTER_PROMPT_CLAUDE.md`.

Claude must read `CLAUDE.md`, `docs/production/ROADMAP.md`, and the numbered prompt for the current task before editing code.

## What is already included
- Complete game vision and GDD.
- Technical architecture for Godot 4.7.2.
- Original art direction, UI mockup, logo concept, color/shape language.
- Original procedural audio placeholders plus generator script.
- Starter Godot project with a basic 3D office scene and HUD scaffold.
- Data schemas and balancing model.
- Save/versioning strategy.
- QA, accessibility, localization, performance and shipping requirements.
- Legal/IP guardrails for a fictional satire universe.
- 48 implementation prompts, each with acceptance criteria and tests.

## Quality target
"No bugs" cannot be guaranteed in software. The production target is **zero known P0/P1 defects at release**, deterministic save/load, no progress-loss bugs, stable frame pacing on minimum target hardware, and a reproducible build pipeline.
