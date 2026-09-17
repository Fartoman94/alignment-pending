# Real-game-visual-overhaul follow-up, street/traffic pass ("seguí con
# esa parte antes de cerrar la vertical slice" — direct user follow-up
# after characters/furniture/buildings already got the smooth-geometry
# treatment). The mega_pack's road/sidewalk/tree/lamp_post/cars were
# confirmed, by rendering them in isolation, to be genuinely the crudest
# placeholders in the whole pack — a flat box+box car, a single blob
# "cloud" tree, a bare pole with a white rectangle for a lamp head. Full
# reworks, not a bevel pass on the same shapes.
#
# Same technique as every generator before this one in this pass: bevel
# applied (baked) into real geometry, then shade_smooth() + angle-based
# auto-smooth. Car/lamp/tree geometry is genuinely new (not just "more
# rounded boxes") since the originals had no real silhouette to begin
# with.
#
# Lamp posts and car headlights/taillights use real emission — Campaign.
# _update_time_of_day() (game/src/world/campaign.gd) turns lamp OmniLight3D
# children on/off by day_t; the emissive material underneath stays a
# faint "glass catching light" look even when the light itself is off,
# so the fixture doesn't look like a dead bulb at noon.
#
# Run from the `game/` directory:
#   blender --background --python tools/blender_generators/generate_street_assets.py
import bpy, math, os

OUT = "assets/models/generated_street"

ASPHALT = (.09, .09, .11, 1)
CURB = (.42, .42, .44, 1)
SIDEWALK = (.46, .46, .48, 1)
LINE = (.85, .78, .35, 1)
BARK = (.30, .20, .12, 1)
LEAF_A = (.16, .42, .18, 1)
LEAF_B = (.20, .50, .20, 1)
POLE = (.14, .14, .16, 1)
LAMP_GLASS = (.95, .90, .70, 1)
TIRE = (.03, .03, .03, 1)
GLASS = (.10, .12, .16, 1)
CHROME = (.55, .55, .58, 1)

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

def box(name, loc, scale, ma, bev=.03, segments=4):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bev > 0:
        mod = o.modifiers.new("bev", "BEVEL"); mod.width = bev; mod.segments = segments
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(ma)
    return _smooth(o)

def cyl(name, loc, r, d, ma, bev=.01, segments=3, vertices=14, top_r=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r, radius2=(top_r if top_r is not None else r), depth=d, location=loc)
    o = bpy.context.object; o.name = name
    if bev > 0:
        mod = o.modifiers.new("bev", "BEVEL"); mod.width = bev; mod.segments = segments
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(ma)
    return _smooth(o)

def sph(name, loc, scale, ma):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(ma)
    return _smooth(o, 50)

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

def export(name, yup=False):
    os.makedirs(bpy.path.abspath(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(f"{OUT}/{name}.glb"), export_format="GLB", export_yup=yup)

# ---- Road segment: real volume (raised curb either side), lane lines ----
def make_road():
    clear()
    asphalt = mat("Asphalt", ASPHALT, .85)
    curb = mat("Curb", CURB, .7)
    line = mat("Line", LINE, .4, 0, emission=LINE, emission_strength=.3)
    box("Surface", (0, 0, -.02), (5.0, 1.9, .04), asphalt, bev=.0)
    for y in (-1.85, 1.85):
        box(f"Curb_{y}", (0, y, .05), (5.0, .08, .09), curb, bev=.02, segments=2)
    box("LineDash1", (-3.5, 0, .01), (.5, .045, .01), line, bev=0)
    box("LineDash2", (-1.0, 0, .01), (.5, .045, .01), line, bev=0)
    box("LineDash3", (1.5, 0, .01), (.5, .045, .01), line, bev=0)
    box("LineDash4", (4.0, 0, .01), (.5, .045, .01), line, bev=0)
    export("road_straight")

def make_sidewalk():
    clear()
    slab = mat("Slab", SIDEWALK, .8)
    groove = mat("Groove", (.30, .30, .32, 1), .8)
    box("Slab", (0, 0, .02), (5.0, .9, .06), slab, bev=.0)
    for x in (-3.75, -2.5, -1.25, 0, 1.25, 2.5, 3.75):
        box(f"Groove_{x}", (x, 0, .051), (.015, .88, .004), groove, bev=0)
    export("sidewalk_tile")

# ---- Tree: layered canopy, tapered trunk, root flare ----
def make_tree():
    clear()
    bark = mat("Bark", BARK, .85)
    leafa = mat("LeafA", LEAF_A, .9)
    leafb = mat("LeafB", LEAF_B, .9)
    cyl("Trunk", (0, 0, .65), .09, 1.3, bark, bev=.02, segments=2, top_r=.06)
    sph("CanopyLow", (0, 0, 1.35), (.62, .62, .55), leafa)
    sph("CanopyMidL", (-.22, .18, 1.7), (.46, .46, .42), leafb)
    sph("CanopyMidR", (.24, -.15, 1.72), (.44, .44, .40), leafa)
    sph("CanopyTop", (0, .05, 2.05), (.38, .38, .34), leafb)
    export("tree_city")

# ---- Lamp post: base, tapered pole, arm, glowing head ----
def make_lamp_post():
    clear()
    pole_mat = mat("Pole", POLE, .5, .5)
    glass_mat = mat("Glass", LAMP_GLASS, .2, 0, emission=LAMP_GLASS, emission_strength=.6)
    cyl("Base", (0, 0, .08), .09, .16, pole_mat, bev=.015, segments=2)
    cyl("Pole", (0, 0, 1.55), .045, 2.9, pole_mat, bev=.01, segments=2, top_r=.03)
    box("Arm", (.14, 0, 2.95), (.16, .04, .04), pole_mat, bev=.008, segments=2)
    box("Head", (.30, 0, 2.90), (.13, .09, .09), glass_mat, bev=.02, segments=3)
    export("lamp_post")

# ---- Car: real silhouette (lower body + cabin greenhouse), wheels,
# lights — parameterized by body color so blue/orange/taxi share one
# shape. sedan_body_color/roof_light adds the taxi's roof sign. ----
def make_car(name, body_color, roof_light=False):
    clear()
    body_mat = mat("Body", body_color, .35, .15)
    glass_mat = mat("Glass", GLASS, .15, .3)
    chrome_mat = mat("Chrome", CHROME, .3, .7)
    tire_mat = mat("Tire", TIRE, .9)
    head_mat = mat("Headlight", (.95, .95, .85, 1), .2, 0, emission=(.95, .95, .85, 1), emission_strength=1.2)
    tail_mat = mat("Taillight", (.85, .1, .08, 1), .2, 0, emission=(.85, .1, .08, 1), emission_strength=1.0)
    box("LowerBody", (0, 0, .28), (.85, .38, .18), body_mat, bev=.05, segments=4)
    box("Cabin", (-.05, 0, .48), (.55, .34, .14), body_mat, bev=.045, segments=4)
    box("Windshield", (-.05, 0, .48), (.50, .30, .11), glass_mat, bev=.03, segments=3)
    box("Bumper", (0, .40, .22), (.86, .04, .08), chrome_mat, bev=.015, segments=2)
    for x, y in [(.30, .18), (.30, -.18), (-.30, .18), (-.30, -.18)]:
        cyl(f"Wheel_{x}_{y}", (x, y, .12), .12, .09, tire_mat, bev=.01, segments=2, vertices=16)
    box("HeadL", (.42, .12, .22), (.03, .06, .05), head_mat, bev=.008, segments=2)
    box("HeadR", (.42, -.12, .22), (.03, .06, .05), head_mat, bev=.008, segments=2)
    box("TailL", (-.42, .12, .28), (.02, .06, .06), tail_mat, bev=.008, segments=2)
    box("TailR", (-.42, -.12, .28), (.02, .06, .06), tail_mat, bev=.008, segments=2)
    if roof_light:
        light_mat = mat("RoofLight", (.95, .78, .15, 1), .3, 0, emission=(.95, .78, .15, 1), emission_strength=1.3)
        box("RoofSign", (-.05, 0, .58), (.16, .07, .045), light_mat, bev=.01, segments=2)
    export(name)

def make_van(name, body_color):
    clear()
    body_mat = mat("Body", body_color, .4, .1)
    glass_mat = mat("Glass", GLASS, .15, .3)
    tire_mat = mat("Tire", TIRE, .9)
    head_mat = mat("Headlight", (.95, .95, .85, 1), .2, 0, emission=(.95, .95, .85, 1), emission_strength=1.2)
    tail_mat = mat("Taillight", (.85, .1, .08, 1), .2, 0, emission=(.85, .1, .08, 1), emission_strength=1.0)
    box("Body", (0, 0, .40), (1.0, .42, .34), body_mat, bev=.06, segments=4)
    box("Windshield", (.38, 0, .55), (.10, .34, .16), glass_mat, bev=.02, segments=3)
    for x, y in [(.34, .21), (.34, -.21), (-.34, .21), (-.34, -.21)]:
        cyl(f"Wheel_{x}_{y}", (x, y, .13), .13, .10, tire_mat, bev=.01, segments=2, vertices=16)
    box("HeadL", (.50, .13, .30), (.03, .06, .06), head_mat, bev=.008, segments=2)
    box("HeadR", (.50, -.13, .30), (.03, .06, .06), head_mat, bev=.008, segments=2)
    box("TailL", (-.50, .13, .40), (.02, .07, .09), tail_mat, bev=.008, segments=2)
    box("TailR", (-.50, -.13, .40), (.02, .07, .09), tail_mat, bev=.008, segments=2)
    export(name)

make_road()
make_sidewalk()
make_tree()
make_lamp_post()
make_car("car_blue", (.10, .30, .62, 1))
make_car("car_orange", (.72, .34, .06, 1))
make_car("car_taxi", (.90, .74, .08, 1), roof_light=True)
make_van("delivery_van", (.75, .76, .78, 1))
