"""The furniture the game puts in the houses' rooms (Blender 4.4, headless). Each piece is one mesh
with its own baked atlas, built at the origin standing on the floor and facing -Y (the room's
window side); the game picks a layout per room per house (Config/RoomLayouts), so every house is
furnished differently.

    blender -b --factory-startup --python art/scripts/furniture.py -- [--render NAME] [--export]

Most pieces come from interiors.py; new here: a coffin on trestles, an upright piano, a seance
table, a trunk, a birdcage, floor candles, toy blocks, and for the entrance halls a coat rack, a
mirror, an umbrella stand, a runner, a console table, a porcelain doll, a pram and a hanging bulb. Exports art/export/furniture/Furniture.fbx;
tools/setup_furniture.luau files it under ReplicatedStorage.Assets.Furniture.
"""

import math
import pathlib
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import interiors as I  # noqa: E402
import victorian as V  # noqa: E402

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "furniture"
U = I.U


def at0(yaw=0.0):
    return I.at(V, 0, 0, 0, yaw)


def outline_slab(grp, pts, z0, z1, m):
    """A flat-topped solid from a top-view outline (x, y points), z0 to z1, in metres."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x, y, z0)) for x, y in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=Vector((0, 0, z1 - z0)), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return V.mesh_object("Slab", bm, grp)


def coffin():
    """A coffin on two trestles, its lid pushed aside, red lining showing."""
    m = at0()
    for y in (-0.55, 0.55):  # trestles
        for s in (-1, 1):
            V.box("FurnitureWood", (0.05, 0.05, 0.78), (0, y, 0.33), rot=(0, s * 0.45, 0), matrix=m)
        V.box("FurnitureWood", (0.62, 0.08, 0.05), (0, y, 0.62), matrix=m)
    shape = [(-0.2, -0.95), (0.2, -0.95), (0.3, 0.42), (0.24, 0.95), (-0.24, 0.95), (-0.3, 0.42)]
    outline_slab("FurnitureWood", shape, 0.65, 1.08, m)
    inner = [(x * 0.82, y * 0.92) for x, y in shape]
    outline_slab("Velvet", inner, 1.06, 1.09, m)
    lid = m @ V.frame_matrix((0.16, 0.05, 1.1), (0, 0, 0.22))
    outline_slab("FurnitureWood", shape, 0.0, 0.05, lid)
    for y in (-0.5, 0.2, 0.7):
        for s in (-1, 1):
            V.box("Iron", (0.03, 0.12, 0.03), (s * 0.31 * (0.8 if y < 0 else 1.0), y, 0.85), matrix=m)


def piano():
    """An upright piano with a candle sconce either side, and its stool."""
    m = at0()
    V.box("FurnitureWood", (1.5, 0.55, 1.3), (0, 0.1, 0.65), bevel=0.02, matrix=m)
    V.box("FurnitureWood", (1.55, 0.6, 0.06), (0, 0.1, 1.33), bevel=0.02, matrix=m)
    V.box("FurnitureWood", (1.45, 0.32, 0.08), (0, -0.28, 0.72), bevel=0.01, matrix=m)  # key bed
    V.box("Pale", (1.3, 0.16, 0.025), (0, -0.33, 0.775), matrix=m)  # white keys
    for i in range(18):
        if i % 7 in (2, 6):
            continue
        V.box("Canvas", (0.025, 0.09, 0.02), (-0.6 + i * 0.07, -0.29, 0.795), matrix=m)
    V.box("FurnitureWood", (0.6, 0.03, 0.3), (0, -0.16, 1.0), rot=(0.25, 0, 0), matrix=m)  # music rest
    for sx in (-0.62, 0.62):
        V.box("FurnitureWood", (0.08, 0.5, 0.65), (sx, -0.1, 0.36), matrix=m)  # legs/cheeks
        V.lathe("Iron", [(0.04, 1.05), (0.06, 1.08), (0.02, 1.12), (0.05, 1.16)], (sx, -0.22, 0), segments=8, matrix=m)
        V.lathe("Pale", [(0.015, 1.16), (0.015, 1.28)], (sx, -0.22, 0), segments=6, matrix=m)
    V.lathe("FurnitureWood", [(0.15, 0), (0.04, 0.05), (0.04, 0.42), (0.2, 0.45), (0.2, 0.5), (0.01, 0.5)], (0.1, -0.8, 0), segments=12, matrix=m)


def seance():
    """A round table under a velvet cloth with a crystal ball and candles."""
    m = at0()
    V.lathe("FurnitureWood", [(0.25, 0), (0.06, 0.06), (0.05, 0.7), (0.01, 0.72)], (0, 0, 0), segments=10, matrix=m)
    V.lathe("Velvet", [(0.56, 0.45), (0.58, 0.5), (0.6, 0.74), (0.6, 0.76), (0.01, 0.77)], (0, 0, 0), segments=18, matrix=m)
    V.lathe("Iron", [(0.07, 0.77), (0.04, 0.8), (0.06, 0.82)], (0, 0, 0), segments=8, matrix=m)
    V.lathe("Glass", [(0.0, 0.81), (0.07, 0.83), (0.1, 0.9), (0.07, 0.97), (0.0, 0.99)], (0, 0, 0), segments=12, matrix=m)
    for i in range(5):
        a = i * 2 * math.pi / 5 + 0.3
        h = 0.08 + (i % 3) * 0.04
        V.lathe("Pale", [(0.022, 0.77), (0.022, 0.77 + h), (0.0, 0.77 + h + 0.01)], (math.cos(a) * 0.38, math.sin(a) * 0.38, 0), segments=6, matrix=m)


def trunk():
    m = at0()
    V.box("FurnitureWood", (1.0, 0.55, 0.5), (0, 0, 0.27), bevel=0.02, matrix=m)
    V.lathe("FurnitureWood", [(0.27, 0), (0.27, 1.0), (0.0, 1.0)], (0, 0, 0), segments=10,
            matrix=m @ Matrix.Translation((-0.5, 0, 0.52)) @ Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Diagonal((0.55 / 0.54, 1, 1, 1)))
    for x in (-0.35, 0.35):
        V.box("Iron", (0.05, 0.57, 0.52), (x, 0, 0.28), matrix=m)
    V.box("Iron", (0.12, 0.04, 0.14), (0, -0.29, 0.48), matrix=m)  # hasp


def birdcage():
    m = at0()
    V.lathe("Iron", [(0.25, 0), (0.03, 0.04), (0.025, 1.2), (0.0, 1.22)], (0, 0, 0), segments=8, matrix=m)
    V.lathe("Iron", [(0.2, 1.2), (0.21, 1.23), (0.0, 1.24)], (0, 0, 0), segments=12, matrix=m)
    for i in range(12):
        a = i * 2 * math.pi / 12
        V.box("Iron", (0.012, 0.012, 0.45), (math.cos(a) * 0.19, math.sin(a) * 0.19, 1.45), matrix=m)
    for z, r in ((1.36, 0.2), (1.68, 0.19)):
        V.torus("Iron", (0, 0, 0), r, 0.01, m @ Matrix.Translation((0, 0, z)) @ Matrix.Rotation(math.pi / 2, 4, "X"), segments=14, sides=4)
    V.lathe("Iron", [(0.19, 1.67), (0.14, 1.75), (0.05, 1.8), (0.0, 1.85)], (0, 0, 0), segments=12, matrix=m)
    V.torus("Iron", (0, 0, 0), 0.05, 0.01, m @ Matrix.Translation((0, 0, 1.9)), segments=10, sides=4)


def candles():
    m = at0()
    V.lathe("Iron", [(0.24, 0), (0.25, 0.015), (0.0, 0.02)], (0, 0, 0), segments=14, matrix=m)
    for i, (x, y, h) in enumerate(((0, 0, 0.32), (0.1, 0.06, 0.22), (-0.09, 0.08, 0.18), (0.05, -0.1, 0.27), (-0.08, -0.07, 0.12))):
        V.lathe("Pale", [(0.03, 0.02), (0.03, h), (0.034, h + 0.01), (0.0, h + 0.02)], (x, y, 0), segments=8, matrix=m)


def toy_blocks():
    m = at0()
    for i, (x, y, z, r) in enumerate(((0, 0, 0, 0.1), (0.2, 0.05, 0, 0.5), (0.08, 0.02, 0.16, 0.9), (-0.25, 0.15, 0, 0.3))):
        V.box("FurnitureWood", (0.16, 0.16, 0.16), (x, y, z + 0.08), rot=(0, 0, r), bevel=0.01, matrix=m)


# The entrance halls (seen through an opened door, and the open houses): ------------------------


def coat_rack():
    """A bentwood coat stand: three splayed feet, two old coats on its hooks and a hat on top."""
    m = at0()
    V.lathe("FurnitureWood", [(0.035, 0.05), (0.03, 0.9), (0.028, 1.75), (0.05, 1.8), (0.0, 1.86)], (0, 0, 0), segments=8, matrix=m)
    for i in range(3):
        a = i * 2 * math.pi / 3
        V.box("FurnitureWood", (0.04, 0.34, 0.04), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.06), rot=(0.25, 0, a + math.pi / 2), matrix=m)
    for i in range(4):
        a = i * math.pi / 2 + 0.4
        V.box("Iron", (0.02, 0.13, 0.02), (math.cos(a) * 0.07, math.sin(a) * 0.07, 1.68), rot=(-0.6, 0, a + math.pi / 2), matrix=m)
    # The coats: long, heavy, slumped, hanging off two hooks.
    I.lump(V, "Cloth", (0.42, 0.2, 1.05), m @ V.frame_matrix((0.12, -0.09, 0.62), (0.05, 0, 0.4)), droop=0.08, seed=7)
    I.lump(V, "Velvet", (0.38, 0.18, 0.92), m @ V.frame_matrix((-0.1, 0.1, 0.72), (-0.04, 0, -0.9)), droop=0.08, seed=8)
    # A hat on the top hook.
    V.lathe("Canvas", [(0.0, 0.0), (0.17, 0.0), (0.17, 0.015), (0.1, 0.02), (0.1, 0.14), (0.0, 0.15)], (0.05, -0.03, 1.74), segments=14, matrix=m)


def hall_mirror():
    """A tall mirror in a heavy frame, hung on the wall (origin at its centre, glass toward -Y)."""
    m = at0()
    w, h = 0.6, 1.2
    V.box("FurnitureWood", (w + 0.14, 0.05, h + 0.14), (0, 0.02, 0), bevel=0.02, matrix=m)
    V.box("Mirror", (w, 0.02, h), (0, -0.01, 0), matrix=m)
    V.lathe("FurnitureWood", [(0.0, 0.0), (0.06, 0.0), (0.05, 0.04), (0.0, 0.08)], (0, -0.02, h / 2 + 0.07), segments=8, matrix=m)


def umbrella_stand():
    m = at0()
    V.lathe("Iron", [(0.0, 0.0), (0.13, 0.0), (0.14, 0.04), (0.12, 0.3), (0.14, 0.52), (0.12, 0.54), (0.11, 0.06)], (0, 0, 0), segments=12, matrix=m)
    for i, (x, y, lean) in enumerate(((0.04, 0.02, 0.12), (-0.05, -0.03, -0.18))):
        tilt = m @ V.frame_matrix((x, y, 0.05), (lean, lean * 0.5, 0))
        V.lathe("Canvas", [(0.0, 0.0), (0.03, 0.05), (0.055, 0.35), (0.04, 0.78), (0.0, 0.84)], (0, 0, 0), segments=8, matrix=tilt)
        V.lathe("Iron", [(0.008, 0.84), (0.008, 0.96)], (0, 0, 0), segments=5, matrix=tilt)
        hook = [tilt @ Vector(p) for p in ((0, 0, 0.96), (0, -0.03, 1.02), (0, -0.08, 1.0), (0, -0.08, 0.96))]
        V.tube("FurnitureWood", hook, [0.012 * U] * 4, sides=0)


def runner():
    I.rug(V, at0(), 0.8, 2.4)


def console():
    """A narrow hall table: a bowl of keys nobody uses, a candle stub, a little frame."""
    m = at0()
    V.box("FurnitureWood", (0.95, 0.32, 0.04), (0, 0, 0.82), bevel=0.01, matrix=m)
    V.box("FurnitureWood", (0.88, 0.26, 0.1), (0, 0, 0.75), matrix=m)
    V.box("FurnitureWood", (0.84, 0.24, 0.02), (0, 0, 0.2), matrix=m)
    for sx in (-0.42, 0.42):
        for sy in (-0.12, 0.12):
            V.lathe("FurnitureWood", [(0.02, 0), (0.028, 0.1), (0.018, 0.5), (0.024, 0.8)], (sx, sy, 0), segments=6, matrix=m)
    V.lathe("Iron", [(0.0, 0.84), (0.11, 0.85), (0.13, 0.9), (0.12, 0.91), (0.09, 0.86)], (-0.22, 0, 0), segments=12, matrix=m)
    V.lathe("Iron", [(0.05, 0.84), (0.02, 0.88), (0.015, 1.02), (0.03, 1.04)], (0.3, 0.02, 0), segments=8, matrix=m)
    V.lathe("Pale", [(0.016, 1.04), (0.016, 1.1), (0.0, 1.11)], (0.3, 0.02, 0), segments=6, matrix=m)
    I.portrait(V, m @ V.frame_matrix((0.06, 0.1, 0.98), (-0.25, 0, 0.2)) @ Matrix.Scale(0.3, 4))


def doll():
    """A porcelain doll sitting with its legs out: cracked face, one eye gone."""
    m = at0()
    I.lump(V, "Velvet", (0.2, 0.16, 0.2), m @ Matrix.Translation((0, 0.02, 0.12)), droop=0.04, seed=3)
    V.lathe("Pale", [(0.0, 0.2), (0.05, 0.21), (0.07, 0.26), (0.06, 0.31), (0.0, 0.33)], (0, 0.02, 0), segments=10, matrix=m)
    head = m @ Matrix.Translation((0, 0.01, 0.4))
    V.lathe("Pale", [(0.0, -0.07), (0.055, -0.06), (0.07, 0.0), (0.06, 0.05), (0.0, 0.075)], (0, 0, 0), segments=12, matrix=head)
    V.lathe("Canvas", [(0.0, 0.0), (0.065, 0.02), (0.075, 0.05), (0.0, 0.085)], (0, 0.01, 0), segments=12, matrix=head)
    V.lathe("Interior", [(0.0, -0.012), (0.014, 0.0), (0.0, 0.012)], (0.025, -0.058, 0.005), segments=6, matrix=head @ Matrix.Rotation(math.pi / 2, 4, "X"))
    V.lathe("Interior", [(0.0, -0.016), (0.019, 0.0), (0.0, 0.016)], (-0.026, -0.05, 0.005), segments=6, matrix=head @ Matrix.Rotation(math.pi / 2, 4, "X"))
    V.box("Canvas", (0.004, 0.003, 0.06), (-0.012, -0.065, -0.01), rot=(0, 0.4, 0), matrix=head)
    for sx in (-1, 1):
        V.tube("Pale", [m @ Vector((sx * 0.07, 0.0, 0.27)), m @ Vector((sx * 0.1, -0.04, 0.18)), m @ Vector((sx * 0.09, -0.07, 0.12))], [0.018 * U, 0.016 * U, 0.015 * U], sides=0)
        V.tube("Pale", [m @ Vector((sx * 0.05, -0.02, 0.06)), m @ Vector((sx * 0.06, -0.14, 0.04)), m @ Vector((sx * 0.07, -0.24, 0.03))], [0.022 * U, 0.02 * U, 0.018 * U], sides=0)


def pram():
    """An old baby carriage, hood up, left in the hall. Nothing in it. Probably."""
    m = at0()
    for x in (-0.3, 0.3):
        for y in (-0.38, 0.38):
            V.torus("Iron", (0, 0, 0), 0.17, 0.012, m @ Matrix.Translation((x, y, 0.18)) @ Matrix.Rotation(math.pi / 2, 4, "Y"), segments=16, sides=4)
            for k in range(4):
                V.box("Iron", (0.006, 0.006, 0.32), (x, y, 0.18), rot=(k * math.pi / 4, 0, 0), matrix=m)
        V.box("Iron", (0.015, 0.9, 0.015), (x, 0, 0.3), matrix=m)
    # The tub: a deep, rounded basket in faded velvet, dark inside, a black rim round its mouth.
    tub = [(math.cos(a) * 0.25, math.sin(a) * 0.42) for a in [k * math.pi / 8 for k in range(16)]]
    outline_slab("Velvet", tub, 0.36, 0.68, m)
    outline_slab("Interior", [(x * 0.9, y * 0.93) for x, y in tub], 0.68, 0.685, m)
    V.torus("Canvas", (0, 0, 0), 0.25, 0.018, m @ Matrix.Translation((0, 0, 0.69)) @ Matrix.Diagonal((1, 1.68, 1, 1)), segments=20, sides=4)
    # The hood, curving up over the head end in black panels.
    for k in range(6):
        a = (k + 0.5) * math.pi / 12
        V.box("Canvas", (0.5, 0.02, 0.085), (0, 0.12 + math.cos(a) * 0.3, 0.7 + math.sin(a) * 0.3), rot=(a, 0, 0), matrix=m)
    V.tube("Iron", [m @ Vector((0, -0.4, 0.62)), m @ Vector((0, -0.6, 0.95)), m @ Vector((0, -0.66, 1.0))], [0.015 * U] * 3, sides=0)
    V.box("Iron", (0.5, 0.03, 0.03), (0, -0.66, 1.0), matrix=m)


def hanging_bulb():
    """A bare bulb under a tin shade on a long cord (origin at the ceiling; it hangs down from it)."""
    m = at0()
    V.lathe("Iron", [(0.04, 0.0), (0.03, -0.02), (0.0, -0.03)], (0, 0, 0), segments=8, matrix=m)
    V.lathe("Canvas", [(0.006, -0.02), (0.006, -0.9)], (0, 0, 0), segments=5, matrix=m)
    V.lathe("Iron", [(0.02, -0.9), (0.03, -0.94), (0.16, -1.04), (0.17, -1.06), (0.03, -0.96)], (0, 0, 0), segments=14, matrix=m)
    V.lathe("Pale", [(0.0, -0.95), (0.025, -0.98), (0.04, -1.04), (0.03, -1.09), (0.0, -1.11)], (0, 0, 0), segments=10, matrix=m)


PIECES = {
    "Armchair": lambda: I.armchair(V, at0()),
    "SideTable": lambda: I.side_table(V, at0()),
    "Fireplace": lambda: I.fireplace(V, at0()),
    "Portrait": lambda: I.portrait(V, at0()),
    "Bed": lambda: I.bed(V, at0()),
    "Wardrobe": lambda: I.wardrobe(V, at0()),
    "Dresser": lambda: I.dresser(V, at0()),
    "Chair": lambda: I.chair(V, at0()),
    "Table": lambda: I.table(V, at0()),
    "DiningTable": lambda: I.table(V, at0(), w=1.8, d=1.0),
    "Candelabra": lambda: I.candelabra(V, at0()),
    "Bookshelf": lambda: I.bookshelf(V, at0(), seed=10),
    "Bookshelf2": lambda: I.bookshelf(V, at0(), seed=11),
    "Desk": lambda: I.desk(V, at0()),
    "Crib": lambda: I.crib(V, at0()),
    "RockingChair": lambda: I.rocking_chair(V, at0()),
    "RockingChairDoll": lambda: I.rocking_chair(V, at0(), doll=True),
    "Stove": lambda: I.stove(V, at0()),
    "Shelves": lambda: I.shelves(V, at0(), seed=3),
    "Crate": lambda: I.crate(V, at0()),
    "DressForm": lambda: I.dress_form(V, at0()),
    "Clock": lambda: I.clock(V, at0()),
    "Rug": lambda: I.rug(V, at0(), 2.4, 1.6),
    "SheetSofa": lambda: I.lump(V, "Cloth", (2.0, 0.85, 0.85), at0(), seed=1),
    "SheetChair": lambda: I.lump(V, "Cloth", (0.5, 0.5, 1.0), at0(), seed=2),
    "SheetTall": lambda: I.lump(V, "Cloth", (0.35, 0.25, 1.9), at0(), seed=3),
    "SheetLow": lambda: I.lump(V, "Cloth", (0.6, 0.4, 0.75), at0(), seed=4),
    "Figure": lambda: I.figure(V, "Silhouette", at0()),
    "Coffin": coffin,
    "Piano": piano,
    "SeanceTable": seance,
    "Trunk": trunk,
    "Birdcage": birdcage,
    "Candles": candles,
    "ToyBlocks": toy_blocks,
    "CoatRack": coat_rack,
    "HallMirror": hall_mirror,
    "UmbrellaStand": umbrella_stand,
    "Runner": runner,
    "Console": console,
    "Doll": doll,
    "Pram": pram,
    "HangingBulb": hanging_bulb,
}


def build():
    V.reset()
    V.build_materials()
    I.materials(V)
    # The hall mirror's glass: nearly black, glossy, so it catches the light.
    V.MATERIALS["Mirror"] = V.textured("Mirror", None, tint=(0.05, 0.055, 0.06, 1), rough=0.12)
    for name, fn in PIECES.items():
        before = set(bpy.data.objects)
        fn()
        for obj in [o for o in bpy.data.objects if o not in before]:
            src = obj.users_collection[0]
            if src.name.startswith("_"):
                continue
            key = f"{name}|{src.name}"
            V.MATERIALS[key] = V.MATERIALS[src.name]
            V.UV_RULES[key] = V.UV_RULES.get(src.name, (2.0, "vertical"))
            src.objects.unlink(obj)
            V.group(key).objects.link(obj)
    merged = {}
    for name in PIECES:
        parts = [V.merge_group(g) for g in list(V.GROUPS) if g.startswith(name + "|")]
        parts = [p for p in parts if p is not None]
        for o in bpy.context.scene.objects:
            o.select_set(False)
        for p in parts:
            p.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        if len(parts) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = name
        obj.data.name = name
        merged[name] = obj
    tris = {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()}
    print("TRIANGLES", sum(tris.values()), sorted(tris.items(), key=lambda kv: -kv[1])[:6])
    return merged


if __name__ == "__main__":
    merged = build()
    if "--render" in ARGS:
        # --only A,B,C: just those pieces, in a row, closer up.
        only = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
        shown = [(n, o) for n, o in merged.items() if only is None or n in only]
        for name, obj in merged.items():
            obj.hide_render = only is not None and name not in only
        cols = 7 if only is None else len(shown)
        hung = {"HallMirror": 5.5, "Portrait": 5.5, "HangingBulb": 6.5}  # shown at about their height
        spacing = 7.5 if only is None else 5.0
        for i, (name, obj) in enumerate(shown):
            obj.location = ((i % cols) * spacing - (cols - 1) * spacing / 2, (i // cols) * 9.0, hung.get(name, 0))
        cam, _ = V.setup_render("furniture", night=False)
        scene = bpy.context.scene
        scene.camera = cam
        cam.location = (0, -42, 30) if only is None else (0, -2.6 * len(shown) - 7, 6)
        look = Vector((0, 16, 0)) if only is None else Vector((0, 0, 3))
        cam.rotation_euler = (look - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(V.RENDERS / f"{ARGS[ARGS.index('--render') + 1]}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)
    if "--export" in ARGS:
        import export_victorian

        export_victorian.export(merged, EXPORT, "Furniture.fbx", sizes={n: 512 for n in merged})
