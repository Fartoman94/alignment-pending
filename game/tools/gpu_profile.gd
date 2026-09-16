extends SceneTree

## Real GPU-rendered performance profile (finalization pack prompt 19).
## Unlike tools/bootstrap.sh's P44 stress pass (--headless, CPU/logic cost
## only, zero rendering), this drives the actual campaign.tscn scene
## non-headless against a real GPU, sampling Godot's own Performance
## monitors while it renders. Run with a real display available:
##   godot4 --path game --script res://tools/gpu_profile.gd
## (no --headless — that would fall back to a dummy renderer and defeat
## the point). Writes docs/performance/REAL_GPU_PROFILE.md.
##
## Autoloads (GameState, SimClock, etc.) are accessed via
## get_root().get_node(...), never by bare global identifier — this
## --script entrypoint compiles before Godot's autoload-singleton global
## identifier table is populated, so `GameState.foo()` fails to compile
## here even though the exact same call works from every other script in
## the project (all of which load later, through the normal dependency
## graph). tests/smoke_test.gd hits the same constraint and uses the same
## get_node() pattern throughout for the same reason.

const SAMPLE_SECONDS: float = 6.0

var _report_lines: Array[String] = []

func _initialize() -> void:
    await process_frame
    await process_frame
    var state: Node = get_root().get_node("GameState")
    var sim_clock: Node = get_root().get_node("SimClock")
    var rival_mgr: Node = get_root().get_node("RivalManager")
    var world_state_mgr: Node = get_root().get_node("WorldStateManager")
    var scene_router: Node = get_root().get_node("SceneRouter")

    state.reset_to_defaults()
    sim_clock.reset_rng_streams()
    rival_mgr.generate_rival()
    world_state_mgr.generate()

    # A representative small office: server racks + desks spread across
    # the buildable grid (8x6, row 3 reserved as the mandatory route —
    # see build_grid.gd), so there's real geometry/material variety to
    # render, not just an empty floor.
    var buildings: Array = []
    var next_id: int = 1
    for col in 7:
        buildings.append({"id": "prof_rack_%d" % next_id, "buildable_id": "server_rack", "cell_x": col, "cell_y": 0, "rotated": false})
        next_id += 1
    for col in 7:
        buildings.append({"id": "prof_desk_%d" % next_id, "buildable_id": "desk", "cell_x": col, "cell_y": 5, "rotated": false})
        next_id += 1
    state.buildings = buildings
    state.next_building_id = next_id

    await scene_router.go_to("res://scenes/campaign.tscn")
    await process_frame
    await process_frame

    var campaign_node: Node = get_root().get_node("Campaign")

    print("== GPU PROFILE: small scene (0 staff, 14 buildings) ==")
    await _sample_scenario("Small (0 staff, 14 buildings)")

    var staff: Array = []
    var role_ids: Array = StaffRoleCatalog.load_all().keys()
    for i in 20:
        staff.append({"id": "prof_staff_%d" % i, "role": String(role_ids[i % role_ids.size()])})
    state.staff = staff
    campaign_node.call("_sync_staff_agents")
    await process_frame
    print("== GPU PROFILE: mid-game scene (20 staff, 14 buildings) ==")
    await _sample_scenario("Mid-game (20 staff, 14 buildings)")

    staff = []
    for i in 150:
        staff.append({"id": "prof_staff_%d" % i, "role": String(role_ids[i % role_ids.size()])})
    state.staff = staff
    campaign_node.call("_sync_staff_agents")
    await process_frame
    print("== GPU PROFILE: stress scene (150 staff, 14 buildings) ==")
    await _sample_scenario("Stress (150 staff, 14 buildings)")

    _write_report()
    quit(0)

func _sample_scenario(label: String) -> void:
    var fps_samples: Array[float] = []
    var frame_time_samples: Array[float] = []
    var draw_calls_samples: Array[float] = []
    var primitives_samples: Array[float] = []
    var start_ms: int = Time.get_ticks_msec()
    while float(Time.get_ticks_msec() - start_ms) < SAMPLE_SECONDS * 1000.0:
        await process_frame
        fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
        frame_time_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
        draw_calls_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
        primitives_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
    var static_mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
    var video_mem_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)

    var line: String = "%s: FPS min=%.1f avg=%.1f max=%.1f | frame_time_ms avg=%.2f max=%.2f | draw_calls avg=%.0f | primitives avg=%.0f | static_mem=%.1fMB video_mem=%.1fMB (%d samples)" % [
        label,
        fps_samples.min(), _avg(fps_samples), fps_samples.max(),
        _avg(frame_time_samples), frame_time_samples.max(),
        _avg(draw_calls_samples),
        _avg(primitives_samples),
        static_mem_mb, video_mem_mb, fps_samples.size(),
    ]
    print(line)
    _report_lines.append(line)

func _avg(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var total: float = 0.0
    for v in values:
        total += v
    return total / values.size()

func _write_report() -> void:
    var renderer: String = "%s / %s" % [OS.get_name(), RenderingServer.get_video_adapter_name()]
    var out: String = "# Real GPU profile\n\n"
    out += "Generated by `godot4 --path game --script res://tools/gpu_profile.gd` (real rendering, not `--headless` — see tools/bootstrap.sh's P44 pass for the CPU-only/headless equivalent). Renderer/GPU: `%s`. This is this development environment's hardware, not necessarily a player's minimum-spec machine — see `docs/production/KNOWN_ISSUES.md`.\n\n" % renderer
    for line in _report_lines:
        out += "- %s\n" % line
    # res:// doesn't support ".." traversal reliably; go through the real
    # filesystem path instead (this tool only ever runs from an editable
    # checkout via --path game --script, never from an export).
    var game_dir: String = ProjectSettings.globalize_path("res://")
    var repo_root: String = game_dir.trim_suffix("/").get_base_dir()
    var out_dir: String = "%s/docs/performance" % repo_root
    DirAccess.make_dir_recursive_absolute(out_dir)
    var out_path: String = "%s/REAL_GPU_PROFILE.md" % out_dir
    var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
    if file == null:
        push_error("gpu_profile: could not write %s (error %s)" % [out_path, FileAccess.get_open_error()])
        return
    file.store_string(out)
    file.close()
    print("wrote docs/performance/REAL_GPU_PROFILE.md")
