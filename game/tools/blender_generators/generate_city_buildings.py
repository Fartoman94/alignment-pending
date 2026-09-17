# Real-game-visual-overhaul follow-up, exterior pass ("mejora todo lo
# visual" — after characters and interior furniture already got the
# smooth-geometry treatment, the background city buildings/park bench
# the garage's own street view shows were still sharp mega_pack boxes).
# Same technique as generate_humanoids.py/generate_furniture.py: bevel
# applied (baked) into real geometry, then shade_smooth() + angle-based
# auto-smooth — a bevel modifier's own generated faces don't inherit
# smooth shading from the base mesh on export, confirmed the hard way
# once already this session.
#
# Two building facades (small/mid, matching Campaign._build_exterior()'s
# existing small_building_exterior/mid_building_exterior naming and
# roughly their on-screen footprint at the 0.22 scale factor already
# used there) plus a park bench. Windows are separate emissive-capable
# panels, not just a flat color, so they read as glazing rather than a
# stripe painted on the wall.
#
# Run from the `game/` directory:
#   blender --background --python tools/blender_generators/generate_city_buildings.py
import bpy, math, os

OUT = "assets/models/generated_city"

WALL_A = (.52, .50, .56, 1)
WALL_B = (.34, .38, .46, 1)
TRIM = (.14, .14, .16, 1)
WINDOW = (.35, .62, .82, 1)
ROOF = (.20, .20, .22, 1)
WOOD = (.42, .30, .18, 1)
METAL = (.16, .16, .18, 1)

def mat(name, color, rough=.6, metal=0.0, emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emission is not None:
        b.inputs["Emission Color"].default_value = emission
        b.inputs["Emission Strength"].default_value = emission_strength
    return m

def _smooth(o, angle_deg=40):
    bpy.ops.object.shade_smooth()
    o.data.use_auto_smooth = True
    o.data.auto_smooth_angle = math.radians(angle_deg)
    return o

def box(name, loc, scale, ma, bev=.05, segments=5):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = o.modifiers.new("bev", "BEVEL"); mod.width = bev; mod.segments = segments
    o.data.materials.append(ma)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return _smooth(o)

def cyl(name, loc, r, d, ma, bev=.015, segments=4, vertices=14):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=r, depth=d, location=loc)
    o = bpy.context.object; o.name = name
    mod = o.modifiers.new("bev", "BEVEL"); mod.width = bev; mod.segments = segments
    o.data.materials.append(ma)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return _smooth(o)

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

def export(name, yup=True):
    os.makedirs(bpy.path.abspath(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(f"{OUT}/{name}.glb"), export_format="GLB", export_yup=yup)

def make_small_building():
    clear()
    wall = mat("Wall", WALL_A, .7)
    trim = mat("Trim", TRIM, .5, .3)
    win = mat("Window", WINDOW, .15, .1, emission=WINDOW, emission_strength=.4)
    roof = mat("Roof", ROOF, .8)
    box("Body", (0, 0, 4.5), (4.0, 3.5, 4.5), wall, bev=.10, segments=4)
    box("Roof", (0, 0, 9.1), (4.1, 3.6, .12), roof, bev=.03, segments=3)
    box("BaseTrim", (0, 0, .15), (4.05, 3.55, .18), trim, bev=.02, segments=3)
    for floor_z in (2.2, 4.6, 7.0):
        for x in (-2.6, 0, 2.6):
            box(f"Win_{floor_z}_{x}", (x, -3.52, floor_z), (.55, .04, .55), win, bev=.02, segments=2)
    export("small_building_exterior", yup=False)

def make_mid_building():
    clear()
    wall = mat("Wall", WALL_B, .65)
    trim = mat("Trim", TRIM, .5, .3)
    win = mat("Window", WINDOW, .15, .1, emission=WINDOW, emission_strength=.4)
    roof = mat("Roof", ROOF, .8)
    box("Body", (0, 0, 7.0), (4.6, 4.0, 7.0), wall, bev=.12, segments=4)
    box("Roof", (0, 0, 14.1), (4.7, 4.1, .12), roof, bev=.03, segments=3)
    box("BaseTrim", (0, 0, .15), (4.65, 4.05, .18), trim, bev=.02, segments=3)
    for floor_z in (2.0, 4.4, 6.8, 9.2, 11.6):
        for x in (-3.2, -1.05, 1.05, 3.2):
            box(f"Win_{floor_z}_{x}", (x, -4.02, floor_z), (.5, .04, .5), win, bev=.02, segments=2)
    export("mid_building_exterior", yup=False)

def make_park_bench():
    clear()
    wood = mat("Wood", WOOD, .7)
    metal = mat("Metal", METAL, .4, .4)
    box("Seat", (0, 0, .42), (.55, .16, .025), wood, bev=.015, segments=3)
    box("Back", (0, -.14, .62), (.55, .025, .18), wood, bev=.015, segments=3)
    for x in (-.42, .42):
        box(f"Leg_{x}", (x, 0, .21), (.04, .16, .21), metal, bev=.008, segments=2)
    export("park_bench", yup=False)

for fn in (make_small_building, make_mid_building, make_park_bench):
    fn()
