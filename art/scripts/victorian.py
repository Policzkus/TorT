"""Scripted Victorian horror house for Trick or Treat with Friends (Blender 4.4, headless).

    blender -b --factory-startup --python art/scripts/victorian.py -- [--render NAME] [--night] [--export]

Units are studs (1 Blender unit = 1 Roblox stud). The house stands with its front-centre at the
origin, street toward -Y, house toward +Y, Z up (the same layout as the old part-built version,
which had good proportions for kids 4.6 studs tall: storeys 11.5, front door 7.6).

Everything is built as separate pieces in collections named after a material group; at the end
each group is merged into one mesh (one Roblox MeshPart). Doors stay separate objects with their
origin on the hinge so they can swing in-game.
"""

import math
import pathlib
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEX = ROOT / "textures"
RENDERS = ROOT / "renders"
EXPORT = ROOT / "export" / "victorian"

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
SEED = 7
rng = random.Random(SEED)

# Proportions (studs) -------------------------------------------------------------------------------
FOUND = 2.6
STORY = 11.5
EAVE = FOUND + 2 * STORY
T = 0.9  # wall thickness
MAIN = dict(x0=-15.0, x1=15.0, y0=0.0, y1=24.0)
RIDGE_Y, RIDGE_Z = 12.0, EAVE + 11.0
BAY = dict(x0=-15.0, x1=-3.0, y=-4.0)
BAY_RIDGE_Z = EAVE + 10.5
TOWER = dict(x=10.5, y=-1.2, apothem=5.4, eave=EAVE + 8.0, roof=15.0)
PORCH = dict(x0=-3.0, x1=16.6, y=-10.0)
DOOR = dict(x=1.5, w=4.2, h=7.6)


# Scene helpers -----------------------------------------------------------------------------------
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


GROUPS = {}


def group(name):
    if name not in GROUPS:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
        GROUPS[name] = coll
    return GROUPS[name]


def mesh_object(name, bm, grp):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    group(grp).objects.link(obj)
    return obj


def frame_matrix(loc=(0, 0, 0), rot=(0, 0, 0)):
    return Matrix.Translation(Vector(loc)) @ (
        Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
    )


def box(grp, size, loc, rot=(0, 0, 0), bevel=0.0, name="Box", matrix=None):
    """A box of `size` centred at `loc` (in `matrix` space if given), with chamfered edges."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        b = min(bevel, min(size) * 0.45)
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=b, segments=1, affect="EDGES", profile=0.5)
    m = frame_matrix(loc, rot)
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return mesh_object(name, bm, grp)


def prism(grp, points, thickness, matrix, name="Prism", bevel=0.0):
    """Extrudes a 2D polygon (x, z points in a frame whose local -Y is 'outward') by `thickness`
    toward +Y."""
    bm = bmesh.new()
    verts = [bm.verts.new((x, 0.0, z)) for x, z in points]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, thickness, 0)), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return mesh_object(name, bm, grp)


def lathe(grp, profile, loc, segments=10, name="Turned", matrix=None):
    """A turned post: `profile` is [(radius, height)] from the bottom up."""
    bm = bmesh.new()
    rings = []
    for r, h in profile:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, h)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    m = Matrix.Translation(Vector(loc))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return mesh_object(name, bm, grp)


def slab(grp, low, high, width, thickness, name="Slab", bevel=0.05):
    """A board from the midpoint of its low edge to the midpoint of its high edge (world points),
    `width` along the horizontal edge direction, `thickness` along the surface normal (outward up)."""
    low, high = Vector(low), Vector(high)
    up = high - low
    along = Vector((0, 0, 1)).cross(up).normalized()
    normal = up.normalized().cross(along)
    if normal.z < 0:
        normal, along = -normal, -along
    y_axis = up.normalized()
    m = Matrix((along, y_axis, normal)).transposed().to_4x4()
    m.translation = (low + high) / 2 + normal * thickness / 2
    return box(grp, (width, up.length, thickness), (0, 0, 0), bevel=bevel, name=name, matrix=m)


def torus(grp, center, major, minor, matrix, segments=10, sides=4):
    """A ring standing in the XZ plane (scroll rings in ironwork)."""
    bm = bmesh.new()
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        c = Vector((math.cos(a) * major, 0, math.sin(a) * major))
        out = Vector((math.cos(a), 0, math.sin(a)))
        ring = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            p = c + out * math.cos(b) * minor + Vector((0, 1, 0)) * math.sin(b) * minor
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for i in range(segments):
        a, b2 = rings[i], rings[(i + 1) % segments]
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((a[j], a[k], b2[k], b2[j]))
    bmesh.ops.transform(bm, matrix=matrix @ Matrix.Translation(Vector(center)), verts=bm.verts)
    return mesh_object("Ring", bm, grp)


def spear(grp, x, z, matrix=Matrix()):
    lathe(grp, [(0.0, 0.0), (0.12, 0.06), (0.17, 0.26), (0.06, 0.5), (0.0, 0.62)], (x, 0, z), segments=4, matrix=matrix)


def tube(grp, points, radii, sides=1):
    """A smooth tapered tube through `points`: a Bezier spline with a radius per point."""
    cu = bpy.data.curves.new("Branch", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = sides
    cu.resolution_u = 3 if sides > 0 else 2
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p, r in zip(sp.bezier_points, points, radii):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = r
    obj = bpy.data.objects.new("Branch", cu)
    bpy.context.scene.collection.objects.link(obj)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    bpy.data.objects.remove(obj, do_unlink=True)
    mobj = bpy.data.objects.new("Branch", me)
    group(grp).objects.link(mobj)
    return mobj


def cut(target, cutters):
    """Boolean-subtract boxes (objects) from `target`, then delete the cutters."""
    coll = bpy.data.collections.new(target.name + "_cut")
    bpy.context.scene.collection.children.link(coll)
    for c in cutters:
        for old in list(c.users_collection):
            old.objects.unlink(c)
        coll.objects.link(c)
    mod = target.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    mod.solver = "EXACT"
    apply_modifiers(target)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    bpy.data.collections.remove(coll)


def apply_modifiers(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    obj.modifiers.clear()
    old = obj.data
    obj.data = me
    bpy.data.meshes.remove(old)


# Building blocks ---------------------------------------------------------------------------------
# A wall "frame": origin at the bottom centre of the outer face, local -Y = outward, X along it.
def wall_frame(loc, yaw):
    return frame_matrix(loc, (0, 0, yaw))


def wall(frame, width, height, openings, grp="Siding"):
    w = box(grp, (width, T, height), (0, T / 2, height / 2), matrix=frame, name="Wall")
    cutters = [
        box("_cutters", (o["w"], T * 3, o["h"]), (o["x"], T / 2, o["y"] + o["h"] / 2), matrix=frame)
        for o in openings
    ]
    if cutters:
        cut(w, cutters)
    return w


def casing(frame, o, crown=True):
    tw, d = 0.55, 0.32
    x, y, w, h = o["x"], o["y"], o["w"], o["h"]
    for side in (-1, 1):
        box("Trim", (tw, d, h + tw), (x + side * (w / 2 + tw / 2), -d / 2, y + h / 2), bevel=0.06, matrix=frame)
    if crown:
        box("Trim", (w + 2 * tw + 0.5, 0.45, 0.75), (x, -0.22, y + h + 0.37), bevel=0.06, matrix=frame)
        box("Trim", (w + 2 * tw + 0.9, 0.75, 0.22), (x, -0.36, y + h + 0.86), bevel=0.04, matrix=frame)
        box("Trim", (w + 2 * tw + 0.7, 0.5, 0.18), (x, -0.25, y + h + 1.03), bevel=0.03, matrix=frame)
    else:
        box("Trim", (w + 2 * tw, d, tw), (x, -d / 2, y + h + tw / 2), bevel=0.06, matrix=frame)


def window(frame, o, lit=False, boarded=False, broken=False, shutters=False, curtains=False):
    x, y, w, h = o["x"], o["y"], o["w"], o["h"]
    casing(frame, o)
    box("Trim", (w + 1.5, 0.95, 0.32), (x, -0.32, y - 0.16), bevel=0.06, matrix=frame)  # sill
    box("Trim", (w + 0.9, 0.3, 0.35), (x, -0.08, y - 0.5), bevel=0.04, matrix=frame)  # apron
    inset = 0.55
    # Sash frames: outer frame, meeting rail, muntins.
    fd = 0.22
    for side in (-1, 1):
        box("Trim", (0.22, fd, h), (x + side * (w / 2 - 0.11), inset, y + h / 2), matrix=frame)
    box("Trim", (w, fd, 0.24), (x, inset, y + 0.12), matrix=frame)
    box("Trim", (w, fd, 0.24), (x, inset, y + h - 0.12), matrix=frame)
    box("Trim", (w, fd + 0.06, 0.2), (x, inset - 0.03, y + h / 2), matrix=frame)
    box("Trim", (0.12, fd, h), (x, inset + 0.02, y + h / 2), matrix=frame)
    if w > 4.5:
        for f in (-0.25, 0.25):
            box("Trim", (0.1, fd, h), (x + w * f, inset + 0.02, y + h / 2), matrix=frame)
    # Glass and the room behind it.
    glass = "Glass"
    if broken:
        # Bottom pane intact, top-right pane gone (dark hole), a shard left hanging.
        box(glass, (w - 0.3, 0.05, h / 2 - 0.2), (x, inset + 0.1, y + h / 4), matrix=frame)
        box(glass, (w / 2 - 0.2, 0.05, h / 2 - 0.2), (x - w / 4, inset + 0.1, y + h * 0.75), matrix=frame)
        prism(
            glass,
            [(0, 0), (w * 0.22, 0), (0.05, h * 0.3)],
            0.05,
            frame @ frame_matrix((x + 0.1, inset + 0.08, y + h / 2 + 0.1)),
        )
    else:
        box(glass, (w - 0.2, 0.05, h - 0.2), (x, inset + 0.1, y + h / 2), matrix=frame)
    box("Interior", (w + 2, 0.1, h + 2), (x, T + 2.4, y + h / 2), matrix=frame)
    if curtains:
        cw = w * rng.uniform(0.28, 0.42)
        box("Curtain", (cw, 0.12, h * 0.95), (x - w / 2 + cw / 2, T + 0.8, y + h / 2), matrix=frame)
        cw2 = w * rng.uniform(0.2, 0.35)
        box("Curtain", (cw2, 0.12, h * 0.7), (x + w / 2 - cw2 / 2, T + 0.8, y + h * 0.62), rot=(0, 0.05, 0), matrix=frame)
    if boarded:
        for i in range(3):
            zz = y + h * (0.22 + 0.28 * i) + rng.uniform(-0.3, 0.3)
            box(
                "Boards",
                (w + 1.6, 0.18, 0.8),
                (x + rng.uniform(-0.3, 0.3), -0.42, zz),
                rot=(0, rng.uniform(-0.25, 0.25), 0),
                bevel=0.05,
                matrix=frame,
            )
    if shutters:
        for side in (-1, 1):
            loose = rng.random() < 0.35
            sx = x + side * (w / 2 + 0.55 + 0.75)
            hang = frame @ frame_matrix((sx + side * 0.75, -0.3, y + h), (0, side * (0.2 if loose else 0), 0))
            box("Shutter", (1.5, 0.18, h), (-side * 0.75, 0, -h / 2), bevel=0.04, matrix=hang)
            for i in range(int(h / 0.55)):
                box(
                    "Shutter",
                    (1.2, 0.26, 0.08),
                    (-side * 0.75, -0.08, -h + 0.4 + i * 0.55),
                    rot=(0.5, 0, 0),
                    matrix=hang,
                )


def door(frame, x, y, name, hall=True):
    """Door opening trim, transom, and the door slab as its own object hinged on one side."""
    w, h = DOOR["w"], DOOR["h"]
    o = dict(x=x, y=y, w=w, h=h + 1.5)
    casing(frame, o)
    box("Glass", (w - 0.2, 0.05, 1.1), (x, 0.55, y + h + 0.78), matrix=frame)
    box("Trim", (w, 0.4, 0.3), (x, 0.45, y + h + 0.12), matrix=frame)
    box("Trim", (w + 0.6, 1.4, 0.2), (x, 0.35, y + 0.1), bevel=0.04, matrix=frame)  # threshold
    # The slab: a separate object, origin on the hinge (left edge as seen from outside).
    hinge_local = Vector((x - w / 2, 0.55, y))
    hinge = frame @ Matrix.Translation(hinge_local)
    slab_grp = name
    box(slab_grp, (w - 0.08, 0.3, h - 0.1), (w / 2, 0, h / 2 + 0.05), bevel=0.05, matrix=hinge, name=name)
    for row, (pz, ph) in enumerate(((h * 0.2, h * 0.3), (h * 0.56, h * 0.3), (h * 0.84, h * 0.18))):
        for px in (w * 0.28, w * 0.72):
            box(slab_grp, (w * 0.34, 0.08, ph), (px, -0.18, pz), bevel=0.04, matrix=hinge)
            box(slab_grp, (w * 0.26, 0.06, ph * 0.8), (px, -0.23, pz), bevel=0.03, matrix=hinge)
    box("Brass_" + name, (0.32, 0.32, 0.32), (w - 0.45, -0.3, h * 0.47), bevel=0.12, matrix=hinge)
    box("Brass_" + name, (0.32, 0.32, 0.32), (w - 0.45, 0.3, h * 0.47), bevel=0.12, matrix=hinge)
    box("Brass_" + name, (0.45, 0.1, 0.55), (w / 2, -0.22, h * 0.7), bevel=0.04, matrix=hinge)
    if hall:
        depth, hw, hh = 9.0, w + 2.4, h + 3.0
        inner = frame @ Matrix.Translation(Vector((x, T, y)))
        box("Porch", (hw, depth, 0.3), (0, depth / 2, -0.15), matrix=inner)
        box("Interior", (hw, depth, 0.3), (0, depth / 2, hh), matrix=inner)
        for side in (-1, 1):
            box("Wallpaper", (0.3, depth, hh), (side * hw / 2, depth / 2, hh / 2), matrix=inner)
        box("Interior", (hw, 0.3, hh), (0, depth, hh / 2), matrix=inner)
        for i in range(1, 7):
            box("Porch", (hw * 0.45, 1.0, 0.6 * i), (hw * 0.25, depth - 1 - (6 - i) * 0.9, 0.3 * i), matrix=inner)
    return hinge


# The house ----------------------------------------------------------------------------------------
def foundation():
    box("Stone", (30.4, 24.4, FOUND), (0, 12, FOUND / 2), bevel=0.1)
    box("Stone", (12.4, 4.4, FOUND), ((BAY["x0"] + BAY["x1"]) / 2, -2, FOUND / 2), bevel=0.1)
    s = TOWER["apothem"] * 2 + 0.4
    for a in (0, math.pi / 4):
        box("Stone", (s, s, FOUND), (TOWER["x"], TOWER["y"], FOUND / 2), rot=(0, 0, a), bevel=0.1)
    box("Trim", (30.8, 24.8, 0.5), (0, 12, FOUND + 0.25), bevel=0.06)
    box("Trim", (12.8, 4.8, 0.5), ((BAY["x0"] + BAY["x1"]) / 2, -2, FOUND + 0.25), bevel=0.06)
    for x in (-8, 6):
        f = wall_frame((x, MAIN["y1"] + 0.25, FOUND * 0.5), math.pi)
        box("Interior", (2.4, 0.2, 1.1), (0, 0, 0), matrix=f)
        for i in (-1, 0, 1):
            box("Iron", (0.12, 0.12, 1.1), (i * 0.6, -0.15, 0), matrix=f)


def main_walls():
    up = STORY
    front = wall_frame((0, MAIN["y0"], FOUND), 0)
    fo = [dict(x=DOOR["x"], y=0, w=DOOR["w"], h=DOOR["h"] + 1.5), dict(x=DOOR["x"], y=up + 2.4, w=3.2, h=6)]
    wall(front, 30, EAVE - FOUND, fo, "SidingFront")
    front_hinge = door(front, DOOR["x"], 0, "FrontDoor")
    window(front, fo[1], boarded=True, curtains=True)

    bay_x = (BAY["x0"] + BAY["x1"]) / 2
    bay = wall_frame((bay_x, BAY["y"], FOUND), 0)
    bo = [dict(x=0, y=2.2, w=7, h=6.6), dict(x=-3, y=up + 2.2, w=2.8, h=6.2), dict(x=3, y=up + 2.2, w=2.8, h=6.2)]
    wall(bay, BAY["x1"] - BAY["x0"], EAVE - FOUND, bo, "SidingFront")
    window(bay, bo[0], lit=True, curtains=True)
    window(bay, bo[1], shutters=True, broken=True)
    window(bay, bo[2], shutters=True)
    wall(wall_frame((BAY["x1"], BAY["y"] / 2, FOUND), math.pi / 2), -BAY["y"], EAVE - FOUND, [], "SidingFront")

    left_len = MAIN["y1"] - BAY["y"]
    mid = (MAIN["y1"] + BAY["y"]) / 2
    left = wall_frame((MAIN["x0"], mid, FOUND), -math.pi / 2)
    lo = []
    for yy in (6, 17):
        lo.append(dict(x=mid - yy, y=2.4, w=3, h=6))
        lo.append(dict(x=mid - yy, y=up + 2.4, w=3, h=6))
    wall(left, left_len, EAVE - FOUND, lo, "SidingSides")
    for i, o in enumerate(lo):
        window(left, o, boarded=(i == 1), shutters=(i == 2))

    right = wall_frame((MAIN["x1"], 12, FOUND), math.pi / 2)
    ro = []
    for yy in (11, 19):
        ro.append(dict(x=yy - 12, y=2.4, w=3, h=6))
        ro.append(dict(x=yy - 12, y=up + 2.4, w=3, h=6))
    wall(right, 24, EAVE - FOUND, ro, "SidingSides")
    for i, o in enumerate(ro):
        window(right, o, curtains=(i == 0), boarded=(i == 3), shutters=(i == 1), broken=(i == 1))

    back = wall_frame((0, MAIN["y1"], FOUND), math.pi)
    bko = [
        dict(x=8, y=0, w=DOOR["w"], h=DOOR["h"] + 1.5),
        dict(x=0, y=2.4, w=3, h=6),
        dict(x=-8, y=2.4, w=3, h=6),
        dict(x=8, y=up + 2.4, w=3, h=6),
        dict(x=0, y=up + 2.4, w=3, h=6),
        dict(x=-8, y=up + 2.4, w=3, h=6),
    ]
    wall(back, 30, EAVE - FOUND, bko, "SidingBack")
    back_hinge = door(back, 8, 0, "BackDoor")
    for i, o in enumerate(bko[1:]):
        window(back, o, boarded=(i in (1, 4)), curtains=(i == 2))
    box("Stone", (6, 4, FOUND), (0, 0, 0), matrix=back @ Matrix.Translation(Vector((8, -2, -FOUND / 2))))

    # Corner boards, frieze under the eaves, belt between floors.
    for cx, cy in ((MAIN["x0"], BAY["y"]), (MAIN["x0"], MAIN["y1"]), (MAIN["x1"], MAIN["y1"]), (BAY["x1"], BAY["y"])):
        box("Trim", (0.85, 0.85, EAVE - FOUND), (cx, cy, FOUND + (EAVE - FOUND) / 2), bevel=0.08)
    box("Trim", (30.6, 0.45, 1.2), (0, MAIN["y1"] + 0.22, EAVE - 0.6), bevel=0.06)
    box("Trim", (0.45, 28.6, 1.2), (MAIN["x0"] - 0.22, mid, EAVE - 0.6), bevel=0.06)
    box("Trim", (0.45, 24.4, 1.2), (MAIN["x1"] + 0.22, 12, EAVE - 0.6), bevel=0.06)
    box("Trim", (12.6, 0.45, 1.2), (bay_x, BAY["y"] - 0.22, EAVE - 0.6), bevel=0.06)
    box("Trim", (9, 0.45, 1.2), (1.5, -0.22, EAVE - 0.6), bevel=0.06)
    box("Trim", (12.6, 0.4, 0.45), (bay_x, BAY["y"] - 0.2, FOUND + STORY), bevel=0.05)
    box("Trim", (9, 0.4, 0.45), (1.5, -0.2, FOUND + STORY), bevel=0.05)
    return front_hinge, back_hinge


def gable_wall(points, frame, grp="Siding"):
    return prism(grp, points, T, frame)


def main_roof():
    over = 1.4
    slope = (RIDGE_Z - EAVE) / (RIDGE_Y - MAIN["y0"])
    low_z = EAVE - over * slope
    for side in (-1, 1):
        eave_y = MAIN["y0"] - over if side < 0 else MAIN["y1"] + over
        slab("Roof", (0, eave_y, low_z), (0, RIDGE_Y, RIDGE_Z), 32.6, 0.7, bevel=0.08)
        box("Trim", (32.6, 0.3, 0.7), (0, eave_y + side * 0.12, low_z - 0.15), bevel=0.04)
    box("Roof", (32.8, 1.2, 0.55), (0, RIDGE_Y, RIDGE_Z + 0.55), bevel=0.15)
    h, run = RIDGE_Z - EAVE, RIDGE_Y - MAIN["y0"]
    for x, yaw in ((MAIN["x0"], -math.pi / 2), (MAIN["x1"], math.pi / 2)):
        f = wall_frame((x, RIDGE_Y, EAVE), yaw)
        gable_wall([(-run, 0), (run, 0), (0, h)], f, "Shakes")
        out = -1 if x < 0 else 1
        for side in (-1, 1):
            eave_y = MAIN["y0"] - over if side < 0 else MAIN["y1"] + over
            slab("Trim", (x + out * 1.15, eave_y, low_z), (x + out * 1.15, RIDGE_Y, RIDGE_Z + 0.25), 0.35, 1.2)
        # Round attic vent.
        vent = wall_frame((x + out * 0.05, RIDGE_Y, EAVE + 4.4), yaw)
        lathe("Trim", [(1.3, 0), (1.3, 0.35), (0, 0.35)], (0, 0, 0), segments=16, matrix=vent @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Translation((0, 0, -0.35)))
        lathe("Interior", [(1.0, 0), (1.0, 0.4), (0, 0.4)], (0, 0, 0), segments=16, matrix=vent @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Translation((0, 0, -0.38)))
    # Chimney, leaning a hair.
    ch = frame_matrix((6, 17, (EAVE + RIDGE_Z) / 2 + 6), (math.radians(1.2), math.radians(-1.5), 0))
    box("Brick", (3.2, 3.2, 22), (0, 0, 0), bevel=0.06, matrix=ch)
    box("Stone", (4.0, 4.0, 0.6), (0, 0, 11.2), bevel=0.08, matrix=ch)
    box("Brick", (3.6, 3.6, 0.5), (0, 0, 10.0), bevel=0.05, matrix=ch)
    for dx in (-0.7, 0.8):
        lathe("Brick", [(0.42, 0), (0.42, 1.2), (0.5, 1.3), (0.5, 1.5), (0.3, 1.5)], (dx, 0.2, 11.5), segments=10, matrix=ch)


def bay_roof():
    cx = (BAY["x0"] + BAY["x1"]) / 2
    half = (BAY["x1"] - BAY["x0"]) / 2
    rise = BAY_RIDGE_Z - EAVE
    slope = (RIDGE_Z - EAVE) / (RIDGE_Y - MAIN["y0"])
    back_y = rise / slope
    over, front = 0.9, BAY["y"] - 1.5
    for side in (-1, 1):
        eave_x = cx + side * (half + over)
        low_z = EAVE - over * rise / half
        mid_y = (front + back_y) / 2
        slab("Roof", (eave_x, mid_y, low_z), (cx, mid_y, BAY_RIDGE_Z), back_y - front, 0.7, bevel=0.08)
    box("Roof", (1.1, back_y - front, 0.5), (cx, (front + back_y) / 2, BAY_RIDGE_Z + 0.5), bevel=0.15)
    f = wall_frame((cx, BAY["y"], EAVE), 0)
    gable = gable_wall([(-half, 0), (half, 0), (0, rise)], f, "Shakes")
    # The attic window is cut through the gable: lit, with someone standing in it.
    af = wall_frame((cx, BAY["y"], EAVE + 1.9), 0)
    o = dict(x=0, y=0, w=2.6, h=4.2)
    cut(gable, [box("_cutters", (o["w"], T * 3, o["h"]), (0, T / 2, o["h"] / 2), matrix=af)])
    # Scalloped vergeboards with drops, king post and collar.
    for side in (-1, 1):
        low = Vector((cx + side * (half + over), front + 0.25, EAVE - over * rise / half - 0.1))
        high = Vector((cx, front + 0.25, BAY_RIDGE_Z + 0.3))
        slab("Trim", low, high, 0.45, 1.4)
        for i in range(1, 7):
            pt = low.lerp(high, i / 7)
            lathe("Trim", [(0.14, 0), (0.2, 0.3), (0.12, 0.6), (0.16, 0.9), (0.0, 1.05)], (pt.x, pt.y, pt.z - 2.2), segments=6)
    box("Trim", (0.4, 0.4, 3.6), (cx, front + 0.4, BAY_RIDGE_Z - 2.1), bevel=0.05)
    box("Trim", (4.6, 0.35, 0.35), (cx, front + 0.4, BAY_RIDGE_Z - 3.5), bevel=0.05)
    casing(af, o, crown=False)
    box("Trim", (3.6, 0.7, 0.3), (0, -0.3, -0.15), bevel=0.05, matrix=af)
    box("Glass", (2.5, 0.04, 4.1), (0, 0.45, 2.1), matrix=af)
    box("Trim", (0.15, 0.2, 4.2), (0, 0.4, 2.1), matrix=af)
    box("Trim", (2.6, 0.2, 0.15), (0, 0.4, 2.3), matrix=af)
    box("Silhouette", (1.4, 0.1, 2.1), (0.1, T + 1.0, 1.05), matrix=af)
    box("Silhouette", (0.35, 0.1, 0.4), (0.1, T + 1.0, 2.25), matrix=af)
    head = af @ frame_matrix((0.32, T + 1.0, 2.85), (0, 0.4, 0))
    lathe("Silhouette", [(0.0, -0.55), (0.4, -0.45), (0.48, 0.0), (0.4, 0.45), (0.0, 0.55)], (0, 0, 0), segments=10, matrix=head)
    box("Interior", (3.6, 0.1, 5.0), (0, T + 2.4, 2.1), matrix=af)


def tower():
    a = TOWER["apothem"]
    pw = 2 * a * math.tan(math.pi / 8)
    height = TOWER["eave"] - FOUND
    lean = frame_matrix((TOWER["x"], TOWER["y"], 0), (math.radians(-1.4), math.radians(2.0), 0))
    for k in range(8):
        if k in (4, 5):
            continue
        theta = k * math.pi / 4
        f = lean @ frame_matrix((0, 0, 0), (0, 0, theta)) @ Matrix.Translation((0, -a, FOUND))
        ops = []
        if k in (0, 1, 7, 2):
            ops = [dict(x=0, y=2.6, w=2.4, h=5.6), dict(x=0, y=STORY + 2.6, w=2.4, h=5.6), dict(x=0, y=2 * STORY + 1.4, w=2.0, h=4.2)]
        wall(f, pw + 0.12, height, ops, "SidingTower")
        for i, o in enumerate(ops):
            window(f, o, boarded=(k == 1 and i == 0) or (k == 2 and i == 1), broken=(k == 7 and i == 2), curtains=(k == 0 and i == 1))
        corner = lean @ frame_matrix((0, 0, 0), (0, 0, theta + math.pi / 8)) @ Matrix.Translation((0, -a / math.cos(math.pi / 8), FOUND + height / 2))
        box("Trim", (0.75, 0.75, height), (0, 0, 0), rot=(0, 0, math.pi / 8), bevel=0.08, matrix=corner)
        box("Trim", (pw + 0.5, 0.45, 1.3), (0, -0.22, height - 0.65), bevel=0.06, matrix=f)
        for z in (STORY, 2 * STORY):
            box("Trim", (pw + 0.35, 0.4, 0.45), (0, -0.2, z), bevel=0.05, matrix=f)
    # Bell-cast witch-hat roof: a steep cone over a flared skirt, then a finial and a bent vane.
    top = TOWER["eave"]
    bm = bmesh.new()
    ring_r = (a + 0.3) / math.cos(math.pi / 8)
    flare_r = (a + 1.6) / math.cos(math.pi / 8)
    apex_h = TOWER["roof"]
    rings = []
    for r, z in ((flare_r, -0.9), (ring_r, 1.4), (ring_r * 0.55, apex_h * 0.45), (0.25, apex_h)):
        ring = []
        for k in range(8):
            ang = k * math.pi / 4 + math.pi / 8
            ring.append(bm.verts.new((math.sin(ang) * r, -math.cos(ang) * r, z)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(8):
            j = (k + 1) % 8
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.transform(bm, matrix=lean @ Matrix.Translation((0, 0, top)), verts=bm.verts)
    mesh_object("TowerRoof", bm, "Roof")
    spike = lean @ Matrix.Translation((0, 0, top + apex_h))
    lathe("Iron", [(0.18, -0.3), (0.18, 1.0), (0.4, 1.2), (0.4, 1.6), (0.12, 1.8), (0.1, 3.4), (0.0, 3.8)], (0, 0, 0), segments=8, matrix=spike)
    vane = spike @ frame_matrix((0, 0, 2.8), (0, math.radians(14), 0.7))
    box("Iron", (3.0, 0.08, 0.12), (0, 0, 0), matrix=vane)
    prism("Iron", [(-1.5, -0.1), (-1.0, 0.5), (-0.7, -0.1)], 0.06, vane @ Matrix.Translation((0, -0.03, 0)))
    prism("Iron", [(1.5, 0.0), (1.1, 0.25), (1.1, -0.25)], 0.06, vane @ Matrix.Translation((0, -0.03, 0)))


def porch():
    x0, x1, y0 = PORCH["x0"], PORCH["x1"], PORCH["y"]
    w, d = x1 - x0, -y0
    cx = (x0 + x1) / 2
    deck = box("Porch", (w, d, 0.4), (cx, y0 / 2, FOUND - 0.2), bevel=0.04)
    cut(deck, [box("_cutters", (2.6, 1.8, 1.0), (10.0, -7.6, FOUND - 0.2))])
    box("PorchTrim", (w + 0.4, 0.5, 0.5), (cx, y0 + 0.1, FOUND - 0.2), bevel=0.05)
    box("Interior", (w - 0.4, 0.2, FOUND - 0.5), (cx, y0 + 0.4, (FOUND - 0.5) / 2))
    i = 0
    xx = x0 + 0.6
    while xx < x1 - 0.4:
        for ang in (0.8, -0.8):
            box("Lattice", (0.16, 0.1, 3.0), (xx, y0 + 0.25, (FOUND - 0.5) / 2), rot=(0, ang, 0))
        xx += 1.4
        i += 1
    # A rotted-through patch of deck: a black hole, two snapped planks sagging into it.
    box("Interior", (2.8, 2.0, 0.1), (10.0, -7.6, FOUND - 1.4))
    box("Porch", (2.8, 0.55, 0.12), (9.6, -8.3, FOUND - 0.35), rot=(0.25, 0.12, 0))
    box("Porch", (1.6, 0.5, 0.12), (10.8, -6.9, FOUND - 0.3), rot=(-0.3, -0.2, 0))
    # Steps and stringers.
    for s in range(1, 4):
        top = FOUND - s * FOUND / 4
        box("Porch", (5.4, 1.15, top), (DOOR["x"], y0 - (s - 0.5) * 1.15, top / 2), rot=(0, math.radians((s - 2) * 0.8), 0), bevel=0.04)
    for side in (-1, 1):
        prism("PorchTrim", [(0, 0), (3.6, 0), (0, FOUND)], 0.4, frame_matrix((DOOR["x"] + side * 2.9 - 0.2, y0, 0), (0, 0, -math.pi / 2)))
    # Turned posts with brackets.
    post_y = y0 + 0.5
    posts = [x0 + 0.4, DOOR["x"] + 3.1, 8.6, 12.4, x1 - 0.4]
    roof_low, roof_high = FOUND + 10.2, FOUND + 11.4
    profile = lambda h: [
        (0.45, 0), (0.45, 1.3), (0.32, 1.45), (0.24, 1.8), (0.34, 2.2), (0.22, 2.6), (0.2, h * 0.45),
        (0.32, h * 0.5), (0.2, h * 0.55), (0.2, h - 2.2), (0.32, h - 1.8), (0.24, h - 1.4), (0.42, h - 1.2), (0.42, h),
    ]
    for i, x in enumerate(posts):
        sag = -0.35 if i in (2, 3) else 0.0
        h = roof_low - FOUND + sag
        lathe("PorchTrim", profile(h), (x, post_y, FOUND), segments=10)
        for side in (-1, 1):
            prism(
                "PorchTrim",
                [(0, 0), (1.3, 0), (1.3, -0.25), (0.6, -0.4), (0.25, -0.9), (0.0, -1.3)],
                0.22,
                frame_matrix((x + side * 0.4, post_y - 0.11, FOUND + h - 1.3), (0, 0, 0)) if side > 0 else frame_matrix((x - 0.4, post_y + 0.11, FOUND + h - 1.3), (0, 0, math.pi)),
            )
    # Railings with turned balusters (one bay snapped).
    def railing(a, b, broken=False):
        a, b = Vector(a), Vector(b)
        length = (b - a).length
        yaw = math.atan2(b.y - a.y, b.x - a.x)
        f = frame_matrix(((a + b) / 2).to_tuple(), (0, 0, yaw))
        box("PorchTrim", (length, 0.34, 0.26), (0, 0, 3.1), bevel=0.06, matrix=f)
        box("PorchTrim", (length, 0.28, 0.22), (0, 0, 0.5), bevel=0.05, matrix=f)
        n = int(length / 0.9)
        for k in range(1, n):
            px = -length / 2 + k * length / n
            if broken and n * 0.4 <= k <= n * 0.55:
                continue
            lathe("PorchTrim", [(0.1, 0.6), (0.14, 0.8), (0.09, 1.2), (0.17, 1.8), (0.09, 2.4), (0.13, 2.8), (0.1, 3.0)], (px, 0, 0), segments=6, matrix=f)
        if broken:
            box("PorchTrim", (length * 0.4, 0.3, 0.26), (length * 0.05, 0, 2.3), rot=(0, math.radians(-22), 0), matrix=f)
    for k in range(1, len(posts) - 1):
        railing((posts[k], post_y, FOUND), (posts[k + 1], post_y, FOUND), broken=(k == 2))
    railing((x0 + 0.4, post_y, FOUND), (x0 + 0.4, BAY["y"] - 0.4, FOUND))
    railing((x1 - 0.4, post_y, FOUND), (x1 - 0.4, -3.8, FOUND))
    # Roof: sagging shed roof with beam, ceiling boards and a spindle frieze.
    slab("Roof", (cx, y0 - 0.7, roof_low), (cx, 0, roof_high), w + 0.9, 0.55)
    box("PorchTrim", (w, 0.5, 1.3), (cx, post_y, roof_low - 0.65), rot=(0, math.radians(0.6), 0), bevel=0.05)
    box("Boards", (w, d - 0.4, 0.2), (cx, y0 / 2 + 0.2, roof_low - 0.12))
    xx = x0 + 0.3
    while xx < x1:
        lathe("PorchTrim", [(0.06, 0), (0.1, 0.2), (0.06, 0.45), (0.1, 0.7), (0.06, 0.9)], (xx, post_y, roof_low - 2.25), segments=5)
        xx += 0.7
    box("PorchTrim", (w, 0.25, 0.22), (cx, post_y, roof_low - 2.3), bevel=0.04)
    # Lantern by the door.
    lf = frame_matrix((DOOR["x"] - 3.2, -0.6, FOUND + 6.9))
    box("Iron", (0.9, 0.9, 0.3), (0, 0, 0.75), bevel=0.05, matrix=lf)
    box("Iron", (0.15, 0.8, 0.15), (0, 0.35, 0.95), matrix=lf)
    box("LanternGlow", (0.6, 0.6, 1.1), (0, 0, 0), matrix=lf)
    for sx in (-0.3, 0.3):
        for sy in (-0.3, 0.3):
            box("Iron", (0.08, 0.08, 1.2), (sx, sy, 0), matrix=lf)
    # Rocking chair and a swing hanging by one chain.
    ch = frame_matrix((-0.8, -3, FOUND), (0, 0, math.radians(-35)))
    box("Boards", (1.8, 1.8, 0.25), (0, 0, 1.6), bevel=0.04, matrix=ch)
    box("Boards", (1.8, 0.25, 2.4), (0, 0.85, 2.9), rot=(math.radians(-10), 0, 0), bevel=0.04, matrix=ch)
    for sx in (-0.8, 0.8):
        box("Boards", (0.18, 2.6, 0.3), (sx, 0.1, 0.2), rot=(math.radians(6), 0, 0), matrix=ch)
        box("Boards", (0.18, 0.18, 1.5), (sx, -0.7, 0.9), matrix=ch)
        box("Boards", (0.18, 0.18, 1.5), (sx, 0.8, 0.9), matrix=ch)
    st = Vector((11.6, -3.2, roof_low - 0.2))
    box("Iron", (0.08, 0.08, 5.5), (st.x - 2, st.y, st.z - 2.75))
    sw = frame_matrix((st.x + 0.2, st.y, st.z - 6.4), (0, math.radians(-24), 0))
    box("Boards", (4.6, 1.6, 0.3), (0, 0, 0), bevel=0.05, matrix=sw)
    box("Boards", (4.6, 0.25, 1.6), (0, 0.7, 0.9), bevel=0.05, matrix=sw)
    box("Iron", (0.08, 0.08, 1.6), (2.2, 0, 0.8), rot=(0, math.radians(40), 0), matrix=sw)


def cellar():
    f = wall_frame((MAIN["x1"], 6, 0), math.pi / 2)
    w, run = 5.0, 4.2
    box("Stone", (w + 1, run + 0.6, 1.2), (0, -run / 2, 0.6), bevel=0.08, matrix=f)
    box("Interior", (w, run, 0.1), (0, -run / 2, 1.25), matrix=f)
    tilt = math.atan2(FOUND - 1.2, run)
    mid_z = 1.2 + (FOUND - 1.2) / 2 + 0.15
    hinges = []
    for side, name in ((-1, "CellarDoorL"), (1, "CellarDoorR")):
        leaf = f @ frame_matrix((side * w / 2, -run / 2, mid_z), (-tilt, 0, 0))
        box(name, (w / 2 - 0.05, run / math.cos(tilt), 0.3), (-side * w / 4, 0, 0), bevel=0.04, matrix=leaf, name=name)
        for dz in (-1.2, 0, 1.2):
            box(name, (w / 2 - 0.4, 0.25, 0.08), (-side * w / 4, dz, 0.18), matrix=leaf)
        hinges.append((name, leaf))
    return hinges


def bar(grp, a, b, w, h, bevel=0.04):
    """A beam of cross-section w x h from point a to point b (h stays as upright as it can)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    x = d.normalized()
    up = Vector((0, 0, 1)) if abs(x.z) < 0.95 else Vector((0, 1, 0))
    y = up.cross(x).normalized()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (a + b) / 2
    return box(grp, (d.length + 0.02, w, h), (0, 0, 0), bevel=bevel, matrix=m)


def downspout(top, wall_y, out, bottom=0.5):
    """A downspout from a gutter at `top` back to the wall and down it, kicking out at the foot.
    `out` is the direction away from the wall (+1/-1 along Y)."""
    top = Vector(top)
    elbow = Vector((top.x, wall_y + out * 0.35, top.z - 1.0))
    bar("Iron", top, elbow, 0.36, 0.36)
    foot = Vector((top.x, wall_y + out * 0.35, bottom + 0.5))
    bar("Iron", elbow, foot, 0.36, 0.36)
    bar("Iron", foot, foot + Vector((0, out * 1.1, -0.45)), 0.36, 0.36)
    for z in (foot.z + 3, (foot.z + elbow.z) / 2, elbow.z - 1.5):
        box("Iron", (0.5, 0.5, 0.12), (top.x, wall_y + out * 0.35, z))  # straps


def gutters():
    """Gutters along the back eave and the porch roof with downspouts; the back one has torn away at
    its left end and hangs down the wall."""
    over = 1.4
    slope = (RIDGE_Z - EAVE) / (RIDGE_Y - MAIN["y0"])
    z = EAVE - over * slope - 0.35
    gy = MAIN["y1"] + over + 0.3
    bar("Iron", (-9.5, gy, z), (16.2, gy, z), 0.55, 0.45, bevel=0.08)
    bar("Iron", (-9.5, gy, z), (-16.0, gy + 0.5, z - 3.6), 0.55, 0.45, bevel=0.08)
    downspout((15.4, gy, z), MAIN["y1"], 1)
    # A broken-off downspout stub under the torn end, its lower half lying in the weeds.
    bar("Iron", (-14.6, MAIN["y1"] + 0.35, 14.0), (-14.6, MAIN["y1"] + 0.35, 6.0), 0.36, 0.36)
    bar("Iron", (-13.4, MAIN["y1"] + 1.5, 0.2), (-15.6, MAIN["y1"] + 4.8, 0.25), 0.36, 0.36)
    # Porch roof: a fascia board to give the roof edge some weight, and a gutter under it.
    x0, x1, y0 = PORCH["x0"], PORCH["x1"], PORCH["y"]
    roof_low, roof_high = FOUND + 10.2, FOUND + 11.4
    cx, w = (x0 + x1) / 2, x1 - x0
    box("PorchTrim", (w + 1.0, 0.3, 0.85), (cx, y0 - 0.85, roof_low + 0.1), bevel=0.05)
    box("PorchTrim", (w + 1.1, 0.5, 0.18), (cx, y0 - 0.8, roof_low + 0.6), bevel=0.04)  # drip edge
    for x in (x0 - 0.5, x1 + 0.5):
        bar("PorchTrim", (x, y0 - 0.85, roof_low + 0.15), (x, -0.2, roof_high + 0.15), 0.3, 0.85)
    gz = roof_low - 0.05
    bar("Iron", (x0 - 0.5, y0 - 1.25, gz), (x1 + 0.7, y0 - 1.25, gz), 0.5, 0.42, bevel=0.07)
    top = Vector((x1 + 0.45, y0 - 1.25, gz))
    bar("Iron", top, top + Vector((0, 0, -(gz - 0.6))), 0.34, 0.34)
    bar("Iron", Vector((top.x, top.y, 0.6)), Vector((top.x, top.y - 1.1, 0.15)), 0.34, 0.34)


def back_entry():
    """Stone steps down from the back stoop, an iron handrail, and a little hood over the door."""
    bx = -8.0
    stoop_y = MAIN["y1"] + 4
    for s_ in range(1, 4):
        top = FOUND - s_ * FOUND / 4
        box("Stone", (5.0, 1.0, top), (bx, stoop_y + (s_ - 0.5) * 1.0, top / 2), rot=(0, 0, math.radians((s_ - 2) * 1.2)), bevel=0.06)
    rail_x = bx - 2.8
    for y, z0 in ((MAIN["y1"] + 0.6, FOUND), (stoop_y + 2.8, 0.0)):
        box("Iron", (0.14, 0.14, 3.2), (rail_x, y, z0 + 1.6))
        lathe("Iron", [(0.12, 0), (0.12, 0.1), (0.05, 0.25), (0.0, 0.32)], (rail_x, y, z0 + 3.2), segments=6)
    bar("Iron", (rail_x, MAIN["y1"] + 0.4, FOUND + 3.0), (rail_x, stoop_y, FOUND + 3.0), 0.16, 0.12)
    bar("Iron", (rail_x, stoop_y, FOUND + 3.0), (rail_x, stoop_y + 3.0, 3.0), 0.16, 0.12)
    # Hood: a shed roof on two scrolled brackets above the door casing.
    hz = FOUND + DOOR["h"] + 1.5 + 1.4
    slab("Roof", (bx, MAIN["y1"] + 3.0, hz), (bx, MAIN["y1"] + 0.1, hz + 1.3), 6.6, 0.4)
    box("Trim", (6.7, 0.25, 0.55), (bx, MAIN["y1"] + 3.1, hz - 0.05), bevel=0.04)
    for side in (-1, 1):
        prism(
            "Trim",
            [(0, 0), (2.7, 0), (2.5, -0.35), (1.6, -0.6), (0.7, -1.2), (0.25, -1.9), (0, -2.3)],
            0.25,
            frame_matrix((bx + side * 2.9 + 0.125, MAIN["y1"], hz - 0.05), (0, 0, math.pi / 2)),
        )


def cresting():
    """Cast-iron cresting along the main ridge: spear tips and rings on a rail, finials at the ends."""
    top = RIDGE_Z + 0.83
    x0, x1 = MAIN["x0"] - 0.4, MAIN["x1"] + 0.4
    bar("Iron", (x0, RIDGE_Y, top + 0.15), (x1, RIDGE_Y, top + 0.15), 0.12, 0.12, bevel=0.02)
    bar("Iron", (x0, RIDGE_Y, top + 0.75), (x1, RIDGE_Y, top + 0.75), 0.1, 0.1, bevel=0.02)
    n = 36
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        if i in (12, 13):
            continue  # a stretch has snapped off
        box("Iron", (0.09, 0.09, 0.95), (x, RIDGE_Y, top + 0.5))
        spear("Iron", 0, 0, matrix=Matrix.Translation((x, RIDGE_Y, top + 0.97)) @ Matrix.Scale(0.8, 4))
        if i < n:
            torus("Iron", (x + (x1 - x0) / n / 2, RIDGE_Y, top + 0.45), 0.2, 0.035, Matrix(), segments=10, sides=4)
    for x in (x0 - 0.3, x1 + 0.3):
        lathe("Iron", [(0.2, 0), (0.2, 0.3), (0.32, 0.5), (0.12, 0.8), (0.1, 1.8), (0.25, 2.1), (0.1, 2.4), (0.0, 3.1)], (x, RIDGE_Y, top - 0.2), segments=8)


detail = random.Random(21)  # the newer details roll their own dice so the older pieces keep their shapes


def creeper(base, height, sideways, runners=(), radius=0.2):
    """A dead creeper: a woody stem climbing from `base` (wobbling `sideways`, a unit vector along
    the wall) and runners that wander off it. `runners` are (height, end offset, droop) in world
    space; each runner leaves the stem at that height and ends at stem point + offset."""
    base = Vector(base)
    sideways = Vector(sideways)
    pts, radii = [], []
    z = 0.0
    while z < height:
        pts.append(base + sideways * detail.uniform(-0.25, 0.25) + Vector((0, 0, z)))
        radii.append(radius * (1 - 0.65 * z / height))
        z += detail.uniform(1.1, 1.8)
    tube("Vines", pts, radii)
    for h, off, droop in runners:
        start = base + Vector((0, 0, h))
        off = Vector(off)
        tip = start + off
        n = 8
        run, rr = [], []
        for i in range(n + 1):
            t = i / n
            wave = math.sin(t * math.pi * 3 + h) * 0.35 * min(1.0, off.length / 4)
            run.append(start + off * t + Vector((0, 0, droop * math.sin(t * math.pi) + wave * t)))
            rr.append(max(0.03, radius * 0.5 * (1 - 0.8 * t)))
        tube("Vines", run, rr, sides=0)
        # A few curling tendrils off each runner.
        for t in (0.35, 0.7):
            p = start.lerp(tip, t) + Vector((0, 0, droop * 0.6))
            curl = Vector((detail.uniform(-0.4, 0.4), detail.uniform(-0.4, 0.4), detail.uniform(-0.6, 0.6)))
            tube("Vines", [p, p + curl * 0.6, p + curl + Vector((0, 0, -0.25))], [0.05, 0.04, 0.02], sides=0)


def spiral_vine(x, y, z0, z1, r=0.5, turns=2.5):
    pts, radii = [], []
    n = int(turns * 8)
    for i in range(n + 1):
        t = i / n
        a = t * turns * 2 * math.pi + 0.6 + detail.uniform(-0.25, 0.25)
        rr = r + detail.uniform(-0.05, 0.08)
        pts.append(Vector((x + math.cos(a) * rr, y + math.sin(a) * rr, z0 + (z1 - z0) * (t + detail.uniform(-0.02, 0.02)))))
        radii.append(0.095 * (1 - 0.45 * t))
    tube("Vines", pts, radii, sides=0)
    return pts[-1]


def vines():
    # Up the bay's front corner, spreading over the side wall (there's room between its windows).
    creeper(
        (BAY["x0"] - 0.6, BAY["y"] - 0.6, 0.2),
        22.0,
        (0.7, -0.7, 0),
        runners=[
            (4.0, (-0.1, 6.0, 1.5), -0.6),
            (9.5, (-0.1, 7.5, -2.0), 0.8),
            (14.0, (-0.1, 5.5, 3.0), -0.5),
            (18.5, (-0.1, 4.5, -1.5), 0.6),
            (7.0, (1.3, -0.1, 2.5), 0.3),
            (12.5, (1.2, -0.1, -1.8), -0.3),
        ],
        radius=0.22,
    )
    # Up the tower's front-left corner, hugging it (the windows sit close either side).
    lean = frame_matrix((TOWER["x"], TOWER["y"], 0), (math.radians(-1.4), math.radians(2.0), 0))
    corner = lean @ frame_matrix((0, 0, 0), (0, 0, -math.pi / 8))
    r = TOWER["apothem"] / math.cos(math.pi / 8) + 0.55
    pts, radii = [], []
    z = FOUND
    while z < TOWER["eave"] - 2:
        p = corner @ Vector((detail.uniform(-0.25, 0.25), -r, z))
        pts.append(p)
        radii.append(0.18 * (1 - 0.6 * (z - FOUND) / (TOWER["eave"] - FOUND)))
        z += detail.uniform(1.2, 1.9)
    tube("Vines", pts, radii)
    for h in (6.0, 10.5, 15.0, 21.0, 26.0):
        side = detail.choice((-1, 1))
        start = corner @ Vector((0, -r, FOUND + h))
        tip = corner @ Vector((side * 1.1, -r + 0.2, FOUND + h + detail.uniform(-1.4, 1.4)))
        tube("Vines", [start, start.lerp(tip, 0.5) + Vector((0, 0, 0.3)), tip], [0.08, 0.06, 0.03], sides=0)
    # Round two porch posts and a little way along the beam.
    post_y = PORCH["y"] + 0.5
    roof_low = FOUND + 10.2
    for x, along in ((PORCH["x0"] + 0.4, 1), (PORCH["x1"] - 0.4, -1)):
        end = spiral_vine(x, post_y, FOUND, roof_low - 1.4, r=0.48, turns=2.6)
        beam_y = post_y - 0.45
        pts = [end, Vector((x + along * 0.6, beam_y, roof_low - 1.1))]
        for i in range(1, 5):
            pts.append(Vector((x + along * (0.6 + i * 1.2), beam_y, roof_low - 1.0 + detail.uniform(-0.35, 0.35))))
        tube("Vines", pts, [0.08, 0.07, 0.06, 0.05, 0.04, 0.03], sides=0)
        for p in pts[2::2]:
            tube("Vines", [p, p + Vector((detail.uniform(-0.3, 0.3), -0.1, -1.2)), p + Vector((detail.uniform(-0.5, 0.5), -0.15, -2.1))], [0.04, 0.03, 0.02], sides=0)


def pumpkin(loc, size, yaw, carved=False, rotten=False):
    """A ribbed pumpkin. A carved one is hollow with a face cut through it and a candle glow inside;
    a rotten one has slumped and caved in on one side."""
    bm = bmesh.new()
    segs, rings = 20, 10
    grid = []
    for j in range(1, rings):
        phi = -math.pi / 2 + j / rings * math.pi
        row = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            rib = 0.9 + 0.1 * abs(math.cos(a * 5))
            rr = math.cos(phi) * size * rib
            zz = (math.sin(phi) * 0.62 + 0.62) * size
            if rotten:
                zz *= 0.85
                zz -= max(0.0, math.cos(a - 0.6)) * max(0.0, math.sin(phi)) * 0.35 * size
                rr *= 1.08
            row.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
        grid.append(row)
    for j in range(len(grid) - 1):
        for i in range(segs):
            k = (i + 1) % segs
            bm.faces.new((grid[j][i], grid[j][k], grid[j + 1][k], grid[j + 1][i]))
    low = bm.verts.new((0, 0, 0.02 * size))
    high = bm.verts.new((0, 0, (1.18 if not rotten else 0.8) * size))
    for i in range(segs):
        k = (i + 1) % segs
        bm.faces.new((low, grid[0][k], grid[0][i]))
        bm.faces.new((high, grid[-1][i], grid[-1][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    m = frame_matrix(loc, (0, 0, yaw))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    shell = mesh_object("Pumpkin", bm, "Pumpkin")
    if carved:
        inner = lathe("_cutters", [(0.01, size * 0.22), (size * 0.66, size * 0.35), (size * 0.74, size * 0.62), (size * 0.58, size * 0.95), (0.01, size * 1.05)], (0, 0, 0), segments=12, matrix=m)
        face = m @ Matrix.Translation((0, -size * 1.4, size * 0.62))
        cutters = [inner]
        for ex in (-0.32, 0.32):
            eye = [((ex - 0.14) * size, 0.08 * size), ((ex + 0.14) * size, 0.08 * size), ((ex + ex * 0.3) * size, 0.34 * size)]
            cutters.append(prism("_cutters", eye, size * 1.2, face))
        mouth = [(-0.42, -0.06), (-0.27, -0.14), (-0.18, -0.06), (-0.06, -0.16), (0.06, -0.06), (0.17, -0.16), (0.28, -0.08), (0.42, -0.04), (0.3, -0.3), (0.0, -0.37), (-0.3, -0.3)]
        cutters.append(prism("_cutters", [(x * size, z * size) for x, z in reversed(mouth)], size * 1.2, face))
        cut(shell, cutters)
        lathe("PumpkinGlow", [(0.01, size * 0.3), (size * 0.35, size * 0.4), (size * 0.4, size * 0.6), (size * 0.3, size * 0.8), (0.01, size * 0.85)], (0, 0, 0), segments=8, matrix=m)
    stem = (1.15 if not rotten else 0.75) * size
    tube("Vines", [m @ Vector((0, 0, stem - 0.1)), m @ Vector((0.05, 0.02, stem + 0.2 * size)), m @ Vector((0.18 * size, 0.05, stem + 0.3 * size))], [0.12 * size, 0.1 * size, 0.07 * size], sides=0)


def clutter():
    """Things left on the porch and steps: jack-o'-lanterns (one guttering on the top step, one by
    the door), a rotten one slumped on a lower step, and an iron urn of dead stalks."""
    step1 = FOUND - FOUND / 4
    step2 = FOUND - 2 * FOUND / 4
    y0 = PORCH["y"]
    pumpkin((DOOR["x"] - 2.05, y0 - 0.58, step1), 0.62, math.radians(-15), carved=True)
    pumpkin((DOOR["x"] + 2.1, y0 - 1.72, step2), 0.55, math.radians(30), rotten=True)
    pumpkin((DOOR["x"] + 3.0, -1.0, FOUND), 0.5, math.radians(20), carved=True)
    pot = frame_matrix((PORCH["x0"] + 1.4, y0 + 1.0, FOUND), (0, 0, 0.4))
    lathe(
        "Iron",
        [(0.45, 0), (0.45, 0.12), (0.2, 0.25), (0.14, 0.5), (0.3, 0.6), (0.55, 0.75), (0.68, 1.05), (0.72, 1.2), (0.62, 1.22), (0.01, 1.1)],
        (0, 0, 0),
        segments=14,
        matrix=pot,
    )
    for i in range(5):
        a = i * 1.3
        d = Vector((math.cos(a), math.sin(a), 0))
        p0 = pot @ Vector((d.x * 0.2, d.y * 0.2, 1.1))
        p1 = pot @ Vector((d.x * 0.35, d.y * 0.35, 2.0 + detail.uniform(-0.3, 0.3)))
        p2 = pot @ Vector((d.x * (0.8 + detail.uniform(0, 0.4)), d.y * 0.9, 1.7 + detail.uniform(-0.6, 0.2)))
        tube("Vines", [p0, p1, p2], [0.05, 0.035, 0.02], sides=0)


# Materials ---------------------------------------------------------------------------------------
def image(nodes, path, colorspace="sRGB"):
    node = nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(str(path), check_existing=True)
    node.image.colorspace_settings.name = colorspace
    return node


def textured(name, tex, tint=(1, 1, 1, 1), paint=None, rough=1.0, dirt=0.6, emission=None, metal=0.0, moss=0.0):
    """A material from a Poly Haven set (diffuse/normal/rough), sampled with the 'Tile' UV map.
    `paint` recolours the texture (multiply by its luminance) for painted wood."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "Tile"
    color_out = None
    if tex:
        folder = TEX / tex
        diff = image(nodes, folder / f"{tex}_diff_1k.jpg")
        nor = image(nodes, folder / f"{tex}_nor_gl_1k.jpg", "Non-Color")
        rgh = image(nodes, folder / f"{tex}_rough_1k.jpg", "Non-Color")
        for n in (diff, nor, rgh):
            links.new(uv.outputs["UV"], n.inputs["Vector"])
        color_out = diff.outputs["Color"]
        if paint is not None:
            bw = nodes.new("ShaderNodeRGBToBW")
            links.new(color_out, bw.inputs["Color"])
            ramp = nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].color = (paint[0] * 0.25, paint[1] * 0.25, paint[2] * 0.25, 1)
            ramp.color_ramp.elements[1].color = paint
            links.new(bw.outputs["Val"], ramp.inputs["Fac"])
            color_out = ramp.outputs["Color"]
        mul = nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs[0].default_value = 1.0
        links.new(color_out, mul.inputs[6])
        mul.inputs[7].default_value = tint
        color_out = mul.outputs[2]
        nmap = nodes.new("ShaderNodeNormalMap")
        links.new(nor.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        rmath = nodes.new("ShaderNodeMath")
        rmath.operation = "MULTIPLY"
        rmath.inputs[1].default_value = rough
        links.new(rgh.outputs["Color"], rmath.inputs[0])
        links.new(rmath.outputs["Value"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Base Color"].default_value = tint
        bsdf.inputs["Roughness"].default_value = rough
    if color_out is not None and dirt > 0:
        # Grime: ambient occlusion in corners + darker toward the ground + streaky noise.
        ao = nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = 1.5
        geo = nodes.new("ShaderNodeNewGeometry")
        sep = nodes.new("ShaderNodeSeparateXYZ")
        links.new(geo.outputs["Position"], sep.inputs["Vector"])
        ground = nodes.new("ShaderNodeMapRange")
        ground.inputs["From Min"].default_value = 0.0
        ground.inputs["From Max"].default_value = 6.0
        ground.inputs["To Min"].default_value = 1.0 - dirt * 0.5
        ground.inputs["To Max"].default_value = 1.0
        links.new(sep.outputs["Z"], ground.inputs["Value"])
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.35
        noise.inputs["Detail"].default_value = 6
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (3.0, 3.0, 0.25)  # streaks run downward
        links.new(geo.outputs["Position"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
        streak = nodes.new("ShaderNodeMapRange")
        streak.inputs["From Min"].default_value = 0.35
        streak.inputs["From Max"].default_value = 0.75
        streak.inputs["To Min"].default_value = 1.0
        streak.inputs["To Max"].default_value = 1.0 - dirt * 0.45
        links.new(noise.outputs["Fac"], streak.inputs["Value"])
        aomix = nodes.new("ShaderNodeMapRange")
        aomix.inputs["To Min"].default_value = 1.0 - dirt * 0.9
        aomix.inputs["To Max"].default_value = 1.0
        links.new(ao.outputs["AO"], aomix.inputs["Value"])
        m1 = nodes.new("ShaderNodeMath")
        m1.operation = "MULTIPLY"
        links.new(aomix.outputs["Result"], m1.inputs[0])
        links.new(ground.outputs["Result"], m1.inputs[1])
        m2 = nodes.new("ShaderNodeMath")
        m2.operation = "MULTIPLY"
        links.new(m1.outputs["Value"], m2.inputs[0])
        links.new(streak.outputs["Result"], m2.inputs[1])
        grime = nodes.new("ShaderNodeMix")
        grime.data_type = "RGBA"
        grime.blend_type = "MULTIPLY"
        grime.inputs[0].default_value = 1.0
        links.new(color_out, grime.inputs[6])
        comb = nodes.new("ShaderNodeCombineColor")
        for ch in ("Red", "Green", "Blue"):
            links.new(m2.outputs["Value"], comb.inputs[ch])
        links.new(comb.outputs["Color"], grime.inputs[7])
        color_out = grime.outputs[2]
    if color_out is not None and moss > 0:
        mnoise = nodes.new("ShaderNodeTexNoise")
        mnoise.inputs["Scale"].default_value = 0.12
        mnoise.inputs["Detail"].default_value = 8
        mgeo = nodes.new("ShaderNodeNewGeometry")
        links.new(mgeo.outputs["Position"], mnoise.inputs["Vector"])
        mrange = nodes.new("ShaderNodeMapRange")
        mrange.inputs["From Min"].default_value = 0.5
        mrange.inputs["From Max"].default_value = 0.7
        mrange.inputs["To Min"].default_value = 0.0
        mrange.inputs["To Max"].default_value = moss
        links.new(mnoise.outputs["Fac"], mrange.inputs["Value"])
        mmix = nodes.new("ShaderNodeMix")
        mmix.data_type = "RGBA"
        links.new(mrange.outputs["Result"], mmix.inputs[0])
        links.new(color_out, mmix.inputs[6])
        mmix.inputs[7].default_value = (0.07, 0.09, 0.04, 1)
        color_out = mmix.outputs[2]
    if color_out is not None:
        links.new(color_out, bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission[0]
        bsdf.inputs["Emission Strength"].default_value = emission[1]
    return mat


# Material per group, and how its tiling UVs are laid out: (texture size in studs, grain direction)
MATERIALS = {}
UV_RULES = {}


def build_materials():
    sage = (0.62, 0.68, 0.6, 1)
    siding = textured("Siding", "distressed_painted_planks", tint=(0.6, 0.66, 0.6, 1), dirt=0.95)
    for g in ("Siding", "SidingFront", "SidingSides", "SidingBack", "SidingTower"):
        MATERIALS[g] = siding
        UV_RULES[g] = (6.0, "horizontal")
    MATERIALS["Shakes"] = textured("Shakes", "roof_slates_02", tint=(0.5, 0.47, 0.47, 1), dirt=0.8)
    UV_RULES["Shakes"] = (8.0, "vertical")
    MATERIALS["Trim"] = textured("Trim", "distressed_painted_planks", paint=(0.62, 0.6, 0.54, 1), dirt=0.95)
    MATERIALS["PorchTrim"] = MATERIALS["Trim"]
    UV_RULES["PorchTrim"] = (4.0, "long")
    MATERIALS["Lattice"] = textured("Lattice", "weathered_planks", tint=(0.32, 0.3, 0.28, 1), dirt=0.8)
    UV_RULES["Lattice"] = (4.0, "long")
    UV_RULES["Trim"] = (4.0, "long")
    MATERIALS["Roof"] = textured("Roof", "roof_slates_02", tint=(0.3, 0.3, 0.32, 1), dirt=0.7, moss=0.55)
    UV_RULES["Roof"] = (12.0, "vertical")
    MATERIALS["Stone"] = textured("Stone", "mossy_stone_wall", tint=(0.7, 0.7, 0.68, 1), dirt=0.5)
    UV_RULES["Stone"] = (6.0, "vertical")
    MATERIALS["Brick"] = textured("Brick", "dark_brick_wall", tint=(0.8, 0.72, 0.7, 1), dirt=0.6)
    UV_RULES["Brick"] = (5.0, "vertical")
    MATERIALS["Porch"] = textured("Porch", "weathered_planks", tint=(0.7, 0.66, 0.62, 1), dirt=0.6)
    UV_RULES["Porch"] = (6.0, "long")
    MATERIALS["Boards"] = textured("Boards", "weathered_planks", tint=(0.85, 0.82, 0.78, 1), dirt=0.5)
    UV_RULES["Boards"] = (5.0, "long")
    MATERIALS["Shutter"] = textured("Shutter", "wood_shutter", paint=(0.16, 0.2, 0.17, 1), dirt=0.6)
    UV_RULES["Shutter"] = (4.0, "vertical")
    door = textured("DoorWood", "dark_wooden_planks", tint=(0.72, 0.66, 0.62, 1), rough=0.9, dirt=0.55)
    MATERIALS["FrontDoor"] = door
    MATERIALS["BackDoor"] = door
    MATERIALS["CellarDoorL"] = MATERIALS["Boards"]
    MATERIALS["CellarDoorR"] = MATERIALS["Boards"]
    for g in ("FrontDoor", "BackDoor"):
        UV_RULES[g] = (7.0, "horizontal")  # boards run up the door
    for g in ("CellarDoorL", "CellarDoorR"):
        UV_RULES[g] = (5.0, "vertical")
    MATERIALS["Wallpaper"] = textured("Wallpaper", None, tint=(0.22, 0.2, 0.15, 1), rough=0.9)
    MATERIALS["Interior"] = textured("Interior", None, tint=(0.01, 0.01, 0.012, 1), rough=1.0)
    glass = textured("Glass", None, tint=(0.06, 0.07, 0.07, 1), rough=0.06)
    glass.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.4
    glass.surface_render_method = "BLENDED"
    MATERIALS["Glass"] = glass
    glow = textured("Glow", None, tint=(0.25, 0.1, 0.03, 1), rough=0.9, emission=((1.0, 0.5, 0.2, 1), 1.6))
    MATERIALS["LanternGlow"] = MATERIALS["PumpkinGlow"] = glow
    MATERIALS["Vines"] = textured("Vines", "bark_willow", tint=(0.32, 0.3, 0.29, 1), dirt=0.5)
    UV_RULES["Vines"] = (2.0, "vertical")
    MATERIALS["Pumpkin"] = textured("Pumpkin", "concrete_wall_006", paint=(0.62, 0.22, 0.03, 1), rough=0.75, dirt=0.8, moss=0.55)
    UV_RULES["Pumpkin"] = (1.5, "vertical")
    MATERIALS["Silhouette"] = textured("Silhouette", None, tint=(0.005, 0.005, 0.005, 1), rough=1.0)
    MATERIALS["Curtain"] = textured("Curtain", None, tint=(0.3, 0.26, 0.24, 1), rough=1.0)
    iron = textured("Iron", None, tint=(0.05, 0.05, 0.055, 1), rough=0.55, metal=0.8)
    MATERIALS["Iron"] = iron
    brass = textured("Brass", None, tint=(0.18, 0.14, 0.08, 1), rough=0.55, metal=0.9)
    for g in ("Brass_FrontDoor", "Brass_BackDoor"):
        MATERIALS[g] = brass
    for g in MATERIALS:
        UV_RULES.setdefault(g, (4.0, "vertical"))


# Merging, UVs ------------------------------------------------------------------------------------
def merge_group(name):
    """Merge every object of a group into one mesh with world-space tiling UVs."""
    coll = GROUPS.get(name)
    if coll is None or not coll.objects:
        return None
    size, grain = UV_RULES.get(name, (4.0, "vertical"))
    bm = bmesh.new()
    for obj in list(coll.objects):
        if obj.modifiers:
            apply_modifiers(obj)
        tmp = bmesh.new()
        tmp.from_mesh(obj.data)
        bmesh.ops.transform(tmp, matrix=obj.matrix_world, verts=tmp.verts)
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        bpy.data.objects.remove(obj, do_unlink=True)
    bm.normal_update()
    uv = bm.loops.layers.uv.new("Tile")
    for face in bm.faces:
        n = face.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            p = loop.vert.co
            if ax == 2:  # floors/roof tops: grain along X
                u, v = p.x, p.y
            elif ax == 0:  # walls facing X
                u, v = p.y, p.z
            else:  # walls facing Y
                u, v = p.x, p.z
            if grain == "horizontal":
                u, v = v, u  # the texture's boards run vertically; turn them sideways
            loop[uv].uv = (u / size, v / size)
    # A second UV map for baking (filled by smart project at export).
    bm.loops.layers.uv.new("Atlas")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    if name in MATERIALS:
        me.materials.append(MATERIALS[name])
    return obj


# Render ------------------------------------------------------------------------------------------
def setup_render(name, night):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x, scene.render.resolution_y = 1280, 860
    scene.eevee.taa_render_samples = 32
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    ground = bpy.data.objects.new("Ground", bpy.data.meshes.new("Ground"))
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=80)
    bm.to_mesh(ground.data)
    bm.free()
    scene.collection.objects.link(ground)
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.08, 0.08, 0.06, 1)
    ground.data.materials.append(gmat)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    cam.data.lens = 24
    views = {
        "front": ((-6, -52, 9), (1, 4, 16)),
        "corner": ((34, -40, 12), (2, 4, 15)),
        "porch": ((-2, -24, 6), (2, -4, 8)),
        "back": ((-28, 58, 14), (0, 12, 14)),
        "steps": ((-2, -19, 4.5), (1.5, -9, 2.6)),
        "bay": ((-30, -16, 8), (-14, 2, 12)),
        "roof": ((-20, -30, 44), (0, 12, 36)),
    }
    if night:
        bg.inputs["Color"].default_value = (0.004, 0.005, 0.008, 1)
        bg.inputs["Strength"].default_value = 1.0
        moon = bpy.data.objects.new("Moon", bpy.data.lights.new("Moon", "SUN"))
        moon.data.energy = 0.25
        moon.data.color = (0.6, 0.7, 1.0)
        moon.rotation_euler = (math.radians(55), 0, math.radians(-30))
        scene.collection.objects.link(moon)
        lamp = bpy.data.objects.new("Lantern", bpy.data.lights.new("Lantern", "POINT"))
        lamp.data.energy = 900
        lamp.data.color = (1.0, 0.65, 0.35)
        lamp.data.shadow_soft_size = 0.3
        lamp.location = (DOOR["x"] - 3.2, -1.2, FOUND + 6.9)
        scene.collection.objects.link(lamp)
        inside = bpy.data.objects.new("Inside", bpy.data.lights.new("Inside", "POINT"))
        inside.data.energy = 600
        inside.data.color = (1.0, 0.5, 0.25)
        inside.location = (-9, -1.5, FOUND + 5.5)
        scene.collection.objects.link(inside)
        scene.view_settings.look = "AgX - Medium High Contrast"
    else:
        bg.inputs["Color"].default_value = (0.55, 0.6, 0.7, 1)
        bg.inputs["Strength"].default_value = 0.8
        sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
        sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
        scene.collection.objects.link(sun)
    return cam, views


def render(name, night=False, views=("front", "corner")):
    cam, presets = setup_render(name, night)
    scene = bpy.context.scene
    scene.camera = cam
    RENDERS.mkdir(parents=True, exist_ok=True)
    for v in views:
        loc, target = presets[v]
        cam.location = loc
        d = Vector(target) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(RENDERS / f"{name}_{v}{'_night' if night else ''}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)


# Main --------------------------------------------------------------------------------------------
def build():
    reset()
    build_materials()
    foundation()
    front_hinge, back_hinge = main_walls()
    main_roof()
    bay_roof()
    tower()
    porch()
    cellar_hinges = cellar()
    gutters()
    back_entry()
    cresting()
    vines()
    clutter()
    # Remove leftover cutter collection if any.
    if "_cutters" in GROUPS:
        for obj in list(GROUPS["_cutters"].objects):
            bpy.data.objects.remove(obj, do_unlink=True)
    merged = {}
    for name in list(GROUPS):
        if name.startswith("_"):
            continue
        obj = merge_group(name)
        if obj:
            merged[name] = obj
    def set_origin(obj, matrix):
        if obj is None:
            return
        obj.data.transform(matrix.inverted())
        obj.matrix_world = matrix
    set_origin(merged.get("FrontDoor"), front_hinge)
    set_origin(merged.get("Brass_FrontDoor"), front_hinge)
    set_origin(merged.get("BackDoor"), back_hinge)
    set_origin(merged.get("Brass_BackDoor"), back_hinge)
    for name, leaf in cellar_hinges:
        set_origin(merged.get(name), leaf)
    tris = {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()}
    print("TRIANGLES", sum(tris.values()), sorted(tris.items(), key=lambda kv: -kv[1])[:8])
    return merged, front_hinge, back_hinge, cellar_hinges


if __name__ == "__main__":
    merged, *_ = build()
    if "--render" in ARGS:
        name = ARGS[ARGS.index("--render") + 1]
        views = ("front", "corner", "porch") if "--night" not in ARGS else ("front", "porch")
        if "--views" in ARGS:
            views = ARGS[ARGS.index("--views") + 1].split(",")
        render(name, night="--night" in ARGS, views=views)
