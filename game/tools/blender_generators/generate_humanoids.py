# Total-visual-rework pass: fixed version of the
# ALIGNMENT_PENDING_TOTAL_VISUAL_AND_SYSTEM_REWORK package's own
# 03_BLENDER_GENERATORS/generate_humanoids.py. The original built a real
# armature and separate body-part meshes, but only ever did
# `mesh.parent = armature_object` — a plain hierarchical parent, not a
# skin binding. No mesh vertex was ever weighted to any bone, so the
# exported "idle/walk/typing/talk/sit" animations moved the invisible
# bones while every visible mesh stayed rigidly frozen. Confirmed by
# loading the original script's export in Godot and diffing an idle
# frame against a played "walk" frame: pixel-identical. Fixed here by
# `bind()`: a full-weight vertex group per mesh + a real Armature
# modifier, the standard rigid-bind pattern for a blocky low-poly
# character where each part moves as one rigid unit — re-verified the
# same way afterward, this time with the leg pose visibly different
# between the idle and walk frames.
#
# Run from the `game/` directory so the relative OUT path below lands in
# the right place:
#   blender --background --python tools/blender_generators/generate_humanoids.py
import bpy, math, os
ROLES=["team_leader","engineer","researcher","support","safety","legal","hr","data_ops"]
OUT="assets/models/generated_humanoids"
SKINS=[(.96,.78,.63,1),(.82,.60,.45,1),(.66,.43,.31,1),(.45,.28,.21,1),(.28,.16,.12,1)]
HAIRS=[(.03,.025,.02,1),(.12,.06,.03,1),(.42,.24,.10,1),(.65,.60,.50,1)]
ROLE={
"team_leader":(.16,.22,.36,1),"engineer":(.08,.34,.56,1),"researcher":(.84,.86,.88,1),
"support":(.18,.50,.40,1),"safety":(.90,.48,.08,1),"legal":(.20,.20,.25,1),
"hr":(.58,.28,.48,1),"data_ops":(.12,.52,.65,1)
}

def mat(name,color,rough=.65,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=color;b.inputs["Roughness"].default_value=rough;b.inputs["Metallic"].default_value=metal
    return m
def cube(name,loc,scale,ma,bev=.04):
    bpy.ops.mesh.primitive_cube_add(location=loc);o=bpy.context.object;o.name=name;o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=o.modifiers.new("soft","BEVEL");mod.width=bev;mod.segments=2;o.data.materials.append(ma);return o
def sphere(name,loc,scale,ma):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=loc);o=bpy.context.object;o.name=name;o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(ma);return o
def cyl(name,loc,r,d,ma):
    bpy.ops.mesh.primitive_cylinder_add(vertices=14,radius=r,depth=d,location=loc);o=bpy.context.object;o.name=name;o.data.materials.append(ma);return o

def rig():
    bpy.ops.object.armature_add(enter_editmode=True,location=(0,0,.9))
    arm=bpy.context.object;arm.name="Rig";eb=arm.data.edit_bones;root=eb[0];root.name="root";root.head=(0,0,0);root.tail=(0,0,.2)
    def b(name,h,t,p=None):
        x=eb.new(name);x.head=h;x.tail=t;x.parent=p;return x
    hips=b("hips",(0,0,.82),(0,0,1.0),root);sp=b("spine",(0,0,1),(0,0,1.25),hips);ch=b("chest",(0,0,1.25),(0,0,1.45),sp)
    ne=b("neck",(0,0,1.45),(0,0,1.58),ch);hd=b("head",(0,0,1.58),(0,0,1.85),ne)
    for side,sgn in [("L",1),("R",-1)]:
        ua=b("upper_arm."+side,(.18*sgn,0,1.4),(.48*sgn,0,1.24),ch)
        la=b("lower_arm."+side,(.48*sgn,0,1.24),(.68*sgn,0,1.05),ua);b("hand."+side,(.68*sgn,0,1.05),(.76*sgn,0,1.0),la)
        ul=b("upper_leg."+side,(.12*sgn,0,.88),(.12*sgn,0,.5),hips)
        ll=b("lower_leg."+side,(.12*sgn,0,.5),(.12*sgn,0,.14),ul);b("foot."+side,(.12*sgn,0,.14),(.12*sgn,-.18,.08),ll)
    bpy.ops.object.mode_set(mode="OBJECT");return arm

# REAL FIX (not in the original script): the original just set
# `mesh.parent = armature_object` — a plain hierarchical parent, not a
# skin binding. The armature's pose bones could move, but no mesh vertex
# was ever weighted to any bone, so every exported "animation" moved
# nothing visible at all. Confirmed by actually loading the original
# script's export in Godot and diffing an idle frame against a played
# "walk" frame: pixel-identical. This binds each rigid body-part mesh to
# its one corresponding bone with a full-weight vertex group + Armature
# modifier — the standard rigid-bind pattern for a blocky low-poly
# character where a whole part moves as one unit, not a smoothly
# deforming surface — so the exported glTF skin actually works.
def bind(o,arm,bone):
    vg=o.vertex_groups.new(name=bone)
    vg.add(range(len(o.data.vertices)),1.0,'REPLACE')
    mod=o.modifiers.new("Armature",'ARMATURE');mod.object=arm
    o.parent=arm

def action(arm,name,frames):
    act=bpy.data.actions.new(name);arm.animation_data_create();arm.animation_data.action=act
    frames(arm)

def make(role,idx):
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    skin=mat("Skin",SKINS[idx%len(SKINS)],.45);hair=mat("Hair",HAIRS[idx%len(HAIRS)],.78);cloth=mat("Cloth",ROLE[role],.72)
    pants=mat("Pants",(.05,.07,.1,1),.8);white=mat("EyeWhite",(.98,.98,.98,1),.35);iris=mat("Iris",(.06,.25,.38,1),.3)
    pupil=mat("Pupil",(.005,.005,.005,1),.25);mouth=mat("Mouth",(.35,.05,.06,1),.5);shoe=mat("Shoe",(.02,.02,.025,1),.7)

    parts=[]  # (object, bone_name) pairs, bound after the armature exists.
    torso=cube("Torso",(0,0,1.15),(.28,.16,.34),cloth,.09);parts.append((torso,"chest"))
    hips_m=cube("Hips",(0,0,.82),(.22,.15,.11),pants,.06);parts.append((hips_m,"hips"))
    for side,s in [("L",1),("R",-1)]:
        ua=cube("UpperArm."+side,(.36*s,0,1.18),(.08,.08,.23),cloth,.05);parts.append((ua,"upper_arm."+side))
        la=cube("LowerArm."+side,(.50*s,0,.93),(.07,.07,.22),skin,.05);parts.append((la,"lower_arm."+side))
        ha=sphere("Hand."+side,(.50*s,0,.70),(.075,.065,.08),skin);parts.append((ha,"hand."+side))
        ul=cube("UpperLeg."+side,(.13*s,0,.55),(.10,.11,.26),pants,.05);parts.append((ul,"upper_leg."+side))
        ll=cube("LowerLeg."+side,(.13*s,0,.23),(.085,.1,.23),pants,.05);parts.append((ll,"lower_leg."+side))
        fo=cube("Foot."+side,(.13*s,-.08,.045),(.11,.18,.065),shoe,.04);parts.append((fo,"foot."+side))
    neck=cyl("Neck",(0,0,1.53),.08,.12,skin);parts.append((neck,"neck"))
    head=sphere("Head",(0,0,1.79),(.24,.21,.28),skin);parts.append((head,"head"))
    ear_l=sphere("EarL",(.235,0,1.79),(.045,.028,.065),skin);parts.append((ear_l,"head"))
    ear_r=sphere("EarR",(-.235,0,1.79),(.045,.028,.065),skin);parts.append((ear_r,"head"))
    for side,s in [("L",1),("R",-1)]:
        eye=sphere("Eye."+side,(.085*s,-.197,1.82),(.055,.025,.04),white);parts.append((eye,"head"))
        iris_o=sphere("Iris."+side,(.085*s,-.222,1.82),(.022,.01,.022),iris);parts.append((iris_o,"head"))
        pup=sphere("Pupil."+side,(.085*s,-.231,1.82),(.01,.006,.01),pupil);parts.append((pup,"head"))
        brow=cube("Brow."+side,(.085*s,-.218,1.885),(.06,.008,.012),hair,.008);parts.append((brow,"head"))
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=.045,radius2=.015,depth=.10,location=(0,-.235,1.76),rotation=(math.radians(90),0,0))
    nose=bpy.context.object;nose.name="Nose";nose.data.materials.append(skin);parts.append((nose,"head"))
    mouth_o=cube("Mouth",(0,-.22,1.685),(.07,.008,.012),mouth,.008);parts.append((mouth_o,"head"))
    hair_o=sphere("Hair",(0,.035,1.94),(.245,.215,.13),hair);parts.append((hair_o,"head"))
    if role=="safety":
        helmet=sphere("Helmet",(0,.02,2.02),(.26,.22,.09),mat("Helmet",(.95,.65,.04,1),.5));parts.append((helmet,"head"))
    if role in ("engineer","researcher"):
        g=mat("Glasses",(.02,.02,.025,1),.4)
        for side,s in [("L",1),("R",-1)]:
            gl=cube("Glasses."+side,(.085*s,-.232,1.82),(.065,.008,.045),g,.01);parts.append((gl,"head"))
    if role=="team_leader":
        tie=cube("Tie",(0,-.17,1.23),(.035,.012,.14),mat("Tie",(.55,.05,.04,1),.65),.01);parts.append((tie,"chest"))

    arm=rig()
    for o,bone in parts:
        bind(o,arm,bone)

    def idle(a):
        p=a.pose.bones["chest"];p.rotation_mode="XYZ"
        for f,x in [(1,0),(30,.018),(60,0)]: p.rotation_euler=(x,0,0);p.keyframe_insert("rotation_euler",frame=f)
    def walk(a):
        for f,x in [(1,.42),(15,-.42),(30,.42)]:
            for side,sgn in [("L",1),("R",-1)]:
                p=a.pose.bones["upper_leg."+side];p.rotation_mode="XYZ";p.rotation_euler=(x*sgn,0,0);p.keyframe_insert("rotation_euler",frame=f)
    def typing(a):
        for f,x in [(1,-.55),(12,-.45),(24,-.55)]:
            for side in ("L","R"):
                p=a.pose.bones["upper_arm."+side];p.rotation_mode="XYZ";p.rotation_euler=(x,0,0);p.keyframe_insert("rotation_euler",frame=f)
    def talk(a):
        p=a.pose.bones["lower_arm.R"];p.rotation_mode="XYZ"
        for f,z in [(1,0),(12,.35),(24,-.2),(36,0)]: p.rotation_euler=(0,0,z);p.keyframe_insert("rotation_euler",frame=f)
    def sit(a):
        for side in ("L","R"):
            p=a.pose.bones["upper_leg."+side];p.rotation_mode="XYZ";p.rotation_euler=(-1.1,0,0);p.keyframe_insert("rotation_euler",frame=1)
    for nm,fn in [("idle",idle),("walk",walk),("typing",typing),("talk",talk),("sit",sit)]: action(arm,nm,fn)

    os.makedirs(bpy.path.abspath(OUT),exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(f"{OUT}/{role}_{idx:02d}.glb"),export_format="GLB",export_animations=True)

for role in ROLES:
    for idx in range(3):
        make(role,idx)
