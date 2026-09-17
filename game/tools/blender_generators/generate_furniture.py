# Real-game-visual-overhaul follow-up, furniture pass ("mejora todo lo
# visual... no tiene forma de juego" — direct user feedback after the
# character geometry rework already fixed the "cuadrado" complaint for
# characters). The mega_pack/base_pack furniture (desk, chair, monitor,
# sofa, coffee table, whiteboard) is imported, sharp-edged low-poly
# geometry this project has no source file for and can't re-bevel —
# these are original, generated replacements instead, same technique
# proven on generate_humanoids.py: heavy bevel width/segments, APPLIED
# (baked into real geometry) before shade_smooth() + angle-based
# auto-smooth, since a bevel modifier's own generated faces don't
# inherit smooth shading from the base mesh on export.
#
# "display" naming on the monitor's screen face is deliberate — Campaign.
# _apply_screen_glow() (game/src/world/campaign.gd) already recurses any
# instanced prop looking for a mesh part literally named "display"/
# "display_N" and gives it the emissive glow material; naming it that
# here means the existing system picks it up for free, no Godot-side
# code change needed.
#
# Run from the `game/` directory:
#   blender --background --python tools/blender_generators/generate_furniture.py
import bpy, math, os

OUT = "assets/models/generated_furniture"

WOOD = (.72, .58, .40, 1)
DESK_LEG = (.18, .18, .20, 1)
CHAIR_SEAT = (.30, .34, .42, 1)
CHAIR_BASE = (.12, .12, .14, 1)
SOFA = (.42, .30, .48, 1)
SOFA_CUSHION = (.50, .38, .56, 1)
TABLE_TOP = (.62, .48, .34, 1)
BOARD_WHITE = (.92, .92, .90, 1)
BOARD_FRAME = (.15, .15, .17, 1)
BEZEL = (.08, .08, .10, 1)
SCREEN = (.10, .55, .85, 1)
STAND = (.20, .20, .22, 1)

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

def cyl(name, loc, r, d, ma, bev=.015, segments=4, vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=r, depth=d, location=loc)
    o = bpy.context.object; o.name = name
    mod = o.modifiers.new("bev", "BEVEL"); mod.width = bev; mod.segments = segments
    o.data.materials.append(ma)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return _smooth(o)

# yup=True (default): a normal glTF export, correctly Y-up on import —
# what every piece placed through Campaign._office_model() needs, paired
# with flat_wall_mount=true there to skip its -90°-X correction (that
# correction assumes the mega_pack's uncorrected-Z-up convention, which
# these files don't share). yup=False: keeps Blender's native Z-up
# instead, deliberately matching the mega_pack's own uncorrected
# convention — only the desk needs this, since it's placed through
# BuildController._make_real_mesh() instead, which applies that same
# unconditional -90°-X correction with no per-model opt-out. Confirmed
# by rendering both paths, not assumed from one working export alone —
# without this the desk landed on its side in-game.
def export(name, yup=True):
    os.makedirs(bpy.path.abspath(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(f"{OUT}/{name}.glb"), export_format="GLB", export_yup=yup)

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

# ---- Desk: replaces assets/models/furniture/desk_single.glb ----
def make_desk():
    clear()
    wood = mat("Wood", WOOD, .55)
    leg = mat("Leg", DESK_LEG, .4, .3)
    box("Top", (0, 0, .74), (.62, .32, .025), wood, bev=.02, segments=4)
    box("Drawer", (.42, -.10, .55), (.14, .18, .16), wood, bev=.015, segments=3)
    for x, y in [(-.55, -.28), (-.55, .28), (.55, -.28), (.55, .28)]:
        cyl(f"Leg_{x}_{y}", (x, y, .37), .018, .70, leg, bev=.006, segments=2)
    export("desk_single", yup=False)

# ---- Office chair: replaces mega/furniture/office_chair.glb ----
def make_chair():
    clear()
    seat_mat = mat("Seat", CHAIR_SEAT, .55)
    base_mat = mat("Base", CHAIR_BASE, .35, .4)
    box("Seat", (0, 0, .46), (.20, .20, .035), seat_mat, bev=.04, segments=5)
    box("Back", (0, -.17, .70), (.20, .03, .22), seat_mat, bev=.04, segments=5)
    cyl("Pole", (0, 0, .32), .025, .30, base_mat, bev=.008, segments=3)
    cyl("BaseDisc", (0, 0, .10), .16, .03, base_mat, bev=.01, segments=3, vertices=20)
    export("office_chair")

# ---- Monitor: replaces mega/computers/monitor.glb ----
def make_monitor():
    clear()
    bezel = mat("Bezel", BEZEL, .5, .2)
    screen_mat = mat("Screen", SCREEN, .2, 0, emission=SCREEN, emission_strength=1.4)
    stand = mat("Stand", STAND, .4, .3)
    box("Bezel", (0, 0, .28), (.24, .02, .15), bezel, bev=.012, segments=4)
    disp = box("display", (0, -.011, .28), (.215, .003, .13), screen_mat, bev=.004, segments=2)
    cyl("Neck", (0, 0, .10), .015, .16, stand, bev=.004, segments=2)
    box("Foot", (0, 0, .015), (.09, .06, .012), stand, bev=.006, segments=3)
    export("monitor")

# ---- Sofa: replaces mega/furniture/sofa_two_seat.glb ----
def make_sofa():
    clear()
    body = mat("SofaBody", SOFA, .65)
    cushion = mat("Cushion", SOFA_CUSHION, .7)
    box("Base", (0, 0, .24), (.55, .28, .20), body, bev=.06, segments=5)
    box("Back", (0, -.24, .48), (.55, .06, .22), body, bev=.06, segments=5)
    box("ArmL", (-.50, 0, .38), (.06, .28, .14), body, bev=.05, segments=4)
    box("ArmR", (.50, 0, .38), (.06, .28, .14), body, bev=.05, segments=4)
    box("CushionL", (-.15, .02, .36), (.19, .24, .06), cushion, bev=.04, segments=4)
    box("CushionR", (.15, .02, .36), (.19, .24, .06), cushion, bev=.04, segments=4)
    export("sofa_two_seat")

# ---- Coffee table: replaces mega/furniture/coffee_table.glb ----
def make_coffee_table():
    clear()
    wood = mat("Wood", TABLE_TOP, .5)
    leg = mat("Leg", DESK_LEG, .4, .3)
    box("Top", (0, 0, .34), (.34, .22, .02), wood, bev=.015, segments=4)
    for x, y in [(-.27, -.16), (-.27, .16), (.27, -.16), (.27, .16)]:
        cyl(f"Leg_{x}_{y}", (x, y, .17), .015, .34, leg, bev=.005, segments=2)
    export("coffee_table")

# ---- Whiteboard stand: replaces mega/furniture/whiteboard_stand.glb ----
def make_whiteboard():
    clear()
    board = mat("Board", BOARD_WHITE, .35)
    frame = mat("Frame", BOARD_FRAME, .5, .3)
    box("Board", (0, 0, 1.0), (.55, .015, .38), board, bev=.008, segments=3)
    for x in (-.52, .52):
        cyl(f"Leg_{x}", (x, .12, .48), .014, .96, frame, bev=.004, segments=2)
        cyl(f"Brace_{x}", (x, -.10, .12), .014, .30, frame, bev=.004, segments=2, vertices=12)
    export("whiteboard_stand")

for fn in (make_desk, make_chair, make_monitor, make_sofa, make_coffee_table, make_whiteboard):
    fn()
