class_name CityBackdrop
extends SubViewport

## Production-kit city layer, scoped to the kit's own brief: "decorative,
## low-cost" (its 10_CITY_AND_REAL_ESTATE.md), not a spatial/explorable
## city — RealEstateManager stays the deliberate abstract management
## screen it already is (KNOWN_ISSUES.md/ASSET_PROVENANCE.md's existing
## "not a literal city map" call, same as DatacenterManager). This is a
## small baked street scene rendered into a SubViewport once
## (render_target_update_mode = UPDATE_ONCE, not every frame — genuinely
## "low-cost", not a second live camera running the whole game) and used
## as the office windows' texture, so the real-estate tier the player is
## on shows through the glass: a sparse, empty lot at the garage, a
## denser skyline by HQ. Same Z-up-authored-in-local-space correction
## every other mega-pack model needs (StaffAgent/BuildController/
## Campaign's own _office_model()).

const VIEWPORT_SIZE: Vector2i = Vector2i(512, 256)

## How much city to build, keyed by RealEstateManager's company tier id.
## "sparse" for the cheap tiers (an empty-lot view, nothing to see yet),
## "mid" for the middle tiers, "dense" for the top two (a real skyline —
## the payoff for climbing the Art Bible's "cheap converted office ->
## corporate building" progression).
const TIER_RICHNESS: Dictionary = {
    "garage": "sparse", "garage_plus": "sparse", "small_office": "sparse",
    "medium_office": "mid",
    "premium_office": "dense", "hq_building": "dense",
}

const MODELS := "res://assets/models/mega/architecture/city/"

func _ready() -> void:
    size = VIEWPORT_SIZE
    transparent_bg = false
    render_target_update_mode = SubViewport.UPDATE_ONCE
    # Without this, a SubViewport shares its parent viewport's World3D by
    # default — the street scene below would render INTO the real office
    # (buildings/lamp posts spawning inside the actual room, visible to
    # the main camera too), not just into this SubViewport's own texture.
    # Confirmed by rendering without it first: exactly that happened.
    own_world_3d = true

## Rebuilds the baked street scene for `tier_id` and schedules exactly one
## render pass. Call before reading get_texture() (the texture is blank
## until that one pass completes, same one-frame-late tradeoff any
## SubViewport-as-texture setup has — acceptable for a decorative view,
## not worth a loading-state workaround).
func build_for_tier(tier_id: String) -> void:
    for child in get_children():
        child.queue_free()
    var env_node := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("7c93b0")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("c8d4e6")
    env.ambient_light_energy = 0.85
    env_node.environment = env
    add_child(env_node)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, -40, 0)
    sun.light_energy = 1.1
    add_child(sun)

    var richness: String = String(TIER_RICHNESS.get(tier_id, "sparse"))
    _build_street(richness)

    var cam := Camera3D.new()
    cam.position = Vector3(0, 1.7, 6.0)
    cam.rotation_degrees = Vector3(-2.0, 0.0, 0.0)
    cam.fov = 55.0
    add_child(cam)
    render_target_update_mode = SubViewport.UPDATE_ONCE

func _place(model_name: String, pos: Vector3, y_rot_deg: float = 0.0) -> void:
    var packed: PackedScene = load(MODELS + model_name + ".glb")
    if packed == null:
        push_error("CityBackdrop: could not load '%s'" % model_name)
        return
    var facing := Node3D.new()
    facing.position = pos
    facing.rotation_degrees = Vector3(0.0, y_rot_deg, 0.0)
    add_child(facing)
    var inst: Node3D = packed.instantiate()
    inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    facing.add_child(inst)

func _build_street(richness: String) -> void:
    _place("sidewalk_tile", Vector3(0, 0, 2))
    _place("road_straight", Vector3(0, -0.02, 5))
    match richness:
        "sparse":
            _place("small_building_exterior", Vector3(-2.0, 0, -4.0))
            _place("lamp_post", Vector3(2.5, 0, 1.0))
        "mid":
            _place("small_building_exterior", Vector3(-4.0, 0, -5.0))
            _place("mid_building_exterior", Vector3(0.0, 0, -6.0))
            _place("lamp_post", Vector3(3.0, 0, 1.0))
            _place("tree_city", Vector3(4.2, 0, -0.5))
            _place("car_blue", Vector3(1.0, 0, 4.2), 90.0)
        "dense":
            _place("mid_building_exterior", Vector3(-4.5, 0, -6.0))
            _place("hq_building_exterior", Vector3(0.0, 0, -7.0))
            _place("tower", Vector3(4.5, 0, -6.5))
            _place("lamp_post", Vector3(3.0, 0, 1.0))
            _place("lamp_post", Vector3(-3.0, 0, 1.0))
            _place("tree_city", Vector3(-4.2, 0, -0.5))
            _place("park_bench", Vector3(-2.0, 0, 1.5), 180.0)
            _place("car_orange", Vector3(1.0, 0, 4.2), 90.0)
            _place("delivery_van", Vector3(-1.5, 0, 4.4), -90.0)
