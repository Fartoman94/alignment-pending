# Humanoid pipeline report

Response to `ALIGNMENT_PENDING_TOTAL_VISUAL_AND_SYSTEM_REWORK`'s prompt 02 (`02_HUMANOID_PIPELINE.md`), which asked for real, rigged, faced, role-clothed humanoid characters generated via `03_BLENDER_GENERATORS/generate_humanoids.py`.

## Environment: Blender was not installed, installed it for real

This environment had no Blender. Installed Blender 5.0.1 from the official `blender.org` release tarball (Linux x64), checksum-verified against the published `SHA256` before extracting — same verification discipline this project already applies to the Godot engine binary and export templates. A local dev tool, not a shipped game asset/dependency — doesn't need the same approval gate `CLAUDE.md` requires for third-party assets bundled into the game itself.

## A real bug found and fixed, not assumed correct

The supplied `generate_humanoids.py` builds a real `Armature` (root/hips/spine/chest/neck/head, upper/lower arms+hands, upper/lower legs+feet) and separate primitive-mesh body parts, then bakes 5 real animations (idle/walk/typing/talk/sit) as pose-bone keyframes. But it only ever does `mesh.parent = armature_object` before export — a plain hierarchical parent, not a skin binding. No mesh vertex was ever assigned a bone weight, so the pose bones move but nothing visible follows them.

**Confirmed, not guessed**: ran the original script unmodified, loaded its export in Godot, screenshotted the idle pose, played the "walk" animation for 10 frames, screenshotted again — pixel-identical. The character would ship completely static regardless of which animation state code plays.

**Fixed** (`game/tools/blender_generators/generate_humanoids.py`, a corrected copy of the supplied script): a `bind()` helper adds a full-weight vertex group + a real `Armature` modifier to every body-part mesh, one bone each (the standard rigid-bind pattern for a blocky low-poly character where each part moves as one rigid unit — matching, not exceeding, the fidelity this project's existing procedural animation already has). Re-verified the same way: idle vs. walk frames now show a visibly different leg pose — `docs/art/screenshots/generated_humanoid_idle.png` vs. `generated_humanoid_walk.png`.

## What got generated

Full run, all 8 roles × 3 variants = 24 real character files in `game/assets/models/generated_humanoids/`. Spot-verified 3 roles side by side (`docs/art/screenshots/generated_humanoids_roles.png`) — researcher (labcoat + glasses), safety (vest + hard hat), team_leader (shirt + tie) — confirming role-specific accessories (glasses, helmet, tie) all still attach and export correctly after the fix, not just the base body. Every file has a real face (eyes, iris, pupils, brows, nose, mouth, ears) and real hair — none of this project's existing character models (from either supplied asset pack) have a face at all.

## Not yet wired into `StaffAgent` — the real reason, not a vague TODO

The existing character pipeline (`StaffAgent._build_visual()`) expects a flat hierarchy: a `world` root node containing loose, *unskinned* mesh parts named `leg_l`/`leg_r`/`arm_l`/`arm_r`, manually reparented into hand-built rotation pivots that `_animate_visual()` drives every frame with trig math — no `Skeleton3D`, no `AnimationPlayer`, by design (the project's existing character models are static meshes; see that function's own doc comment).

These new characters are structured completely differently — a real `Rig`/`Skeleton3D` with properly skinned meshes and baked `AnimationPlayer` clips, which is the *better*, standard way to do character animation, but a genuinely different code path, not a drop-in replacement for the existing one. Wiring them in for real needs:

1. `_build_visual()` detects a model has a `Skeleton3D` + `AnimationPlayer` and branches to a skeletal-animation path instead of pivot construction (no reparenting needed at all in that path — the skeleton handles posing).
2. `StaffAgent.State` (`IDLE`/`MOVING`/`WORKING`) maps to the baked animation names (`idle`/`walk`/`typing` or `sit`) via `AnimationPlayer.play()`.
3. `_apply_variation()`'s skin/hair-tint lookup moves to search `Head`/`Hair` directly under `Skeleton3D` instead of the `_bob_group` reparenting target it uses today — skinned meshes can't be reparented into a pivot group without breaking their skin binding, so that step doesn't apply to this hierarchy.

4. **Scale correction.** Rendered a generated character next to an existing `desk_single.glb` and the existing StaffAgent character side by side, same camera, same depth (`docs/art/screenshots/generated_humanoid_scale_check.png`) — the new characters are visibly bigger and bulkier than the existing ones, the same "orthogonal-camera has no distance-based size cue" scale-authoring mismatch already hit and fixed once this session for the city-backdrop buildings. Needs a measured `model_scale` correction (empirically tuned against the desk, the same way the building fix was) before mixing new and old characters in the same scene would look consistent.

Real, bounded, already-understood work (points 1-4 above are the actual spec for it) — deliberately not rushed into the one system every scene in this project depends on, this late in an already long pass, without the room to test it as thoroughly as everything else this session.

## Role mapping for whenever this gets wired in

The generator's 8 roles don't share the game's exact role IDs — mapping for reference: `team_leader` → `product_manager`, `support` → `support_specialist`, `safety` → `safety_analyst`, `legal` → `legal_specialist`, `hr` → `hr_partner`; `engineer`/`researcher`/`data_ops` match directly. No `ceo`/`cfo` variants were generated (the script's own `ROLES` list doesn't include them) — those two roles would keep their existing mega-pack models until/unless the generator is extended.
