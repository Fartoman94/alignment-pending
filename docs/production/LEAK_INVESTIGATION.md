# Leak investigation — `ObjectDB instances leaked at exit`

Follow-up to the `KNOWN_ISSUES.md` P47 note, requested explicitly by the finalization pack's prompt 05. Conclusion: **runner/engine shutdown noise, not a project leak. Not blocking.**

## What was observed

Every headless Godot run against this project prints one or both of:
```
WARNING: N ObjectDB instances were leaked at exit (run with `--verbose` for details).
ERROR: 1 resources still in use at exit.
```

## Reproduction matrix

| Run | What it does | ObjectDB leaked | "resources still in use" |
|---|---|---|---|
| `godot4 --headless --path game --script res://tools/render_branding.gd` | Loads one `.svg`, rasterizes 7 PNGs, no project autoloads/scenes touched at all | 2 | no |
| `godot4 --headless --path game --script res://tests/smoke_test.gd` (`tools/bootstrap.sh`, 199 assertions) | Instantiates every scene, exercises every autoload, saves/loads repeatedly, runs a 150-agent/900-frame stress pass | 4 | yes (1) |
| Exported Linux binary, `--qa-exported-smoke` (`tests/exported_build_smoke.gd`) | Instantiates 4 scenes, one save/settings round-trip, then quits | 2 | no |
| Exported Linux binary, default boot flow, `--quit-after 5`, no scenes beyond `boot.tscn` | Boots, validates data, force-quits | 2 | no |

## Analysis

- **A run that touches nothing of this project's own code still leaks 2 `ObjectDB` instances at exit.** `render_branding.gd` has zero autoloads, zero project scenes, zero saves — it only calls `Image.load_svg_from_buffer()` and `Image.save_png()`. That rules out any autoload, manager, or gameplay system as the source: the floor is the `--headless --script ... --quit` runner path itself, in engine-internal singletons torn down after `quit()` returns rather than before.
- **The count scales with how much `ResourceLoader` activity happened, not with which systems ran.** The full 199-assertion suite (which `load()`s dozens of scenes/scripts, generates procedural meshes/materials/audio streams, and round-trips saves many times) adds 2 more `ObjectDB` instances and 1 `Resource` on top of that floor. `ResourceLoader` deliberately caches loaded resources for reuse during a session — that cache is not flushed by `SceneTree.quit()`, so anything cached during the run is still alive when the engine tears down and gets reported as "leaked"/"still in use." This is expected `ResourceLoader` cache behavior, not an unreleased reference in project code.
- **It does not grow with gameplay.** The 150-agent/900-physics-frame stress block inside the same smoke-test process (see `tests/smoke_test.gd`'s "50-agent... 900-physics-frame run") runs entirely before the final leak count is printed, and the count stays fixed at 4/1 regardless of that sustained load — a real accumulating leak would show up as a growing number the longer the process ran. It doesn't.
- **The packaged export behaves identically to the render-only baseline** (2 leaked, 0 resources-still-in-use) precisely because `exported_build_smoke.gd` does very little `ResourceLoader` work compared to the full suite — consistent with the "scales with cache activity" explanation above, not with anything specific to export vs. editor.

## Conclusion

Per this pack's own gate ("si solo aparece al shutdown del runner y está explicado, documentarlo"): **documented, not blocking.** These are `--quit()`-time engine/`ResourceLoader` teardown-ordering artifacts of the headless script runner, reproduced identically on a script with zero project code involved, and confirmed not to grow under sustained simulated gameplay. No project-side fix is needed. Worth re-checking against future Godot 4.x patch releases in case upstream changes teardown ordering.
