"""A Second Empire mansion for Cardboard Court, standing between the Victorians (Blender 4.4).

    blender -b --factory-startup --python art/scripts/mansard.py -- [--render NAME [--views a,b] [--night]] [--export]

Two storeys of stained stucco under a steep slate mansard with dormers, and a tall central tower
with its own mansard cap, a round window and iron cresting. Paired scroll brackets under the
cornices, quoins at the corners, arched hoods over tall windows, and a columned entry portico with
a balcony. Real rooms behind the windows (interiors.py pieces). Front door centre at x = 0 on the
tower's front wall; writes World/HouseData/Mansard.luau.
"""

import math
import pathlib
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import housekit as K  # noqa: E402
import interiors as I  # noqa: E402
import victorian as V  # noqa: E402

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "mansard"
rng = random.Random(29)

T = V.T
FOUND = 3.0
STORY = V.STORY
CORNICE = FOUND + 2 * STORY  # 26
MANSARD_TOP = CORNICE + 9.0
INSET = 2.8  # how far the mansard leans in over its height
MAIN = dict(x0=-13.0, x1=13.0, y0=0.0, y1=22.0)
TOWER = dict(x0=-4.5, x1=4.5, y0=-3.0, y_back=6.0, top=CORNICE + 8.0, cap=CORNICE + 17.0)
PORCH_Y = -6.6  # front edge of the portico platform
D = K.Data("Mansard")


def materials():
    M, U = V.MATERIALS, V.UV_RULES
    M["Siding"] = V.textured("Stucco", "concrete_wall_006", tint=(0.66, 0.62, 0.56, 1), dirt=0.95, moss=0.25)
    U["Siding"] = (8.0, "vertical")
    M["Trim"] = M["PorchTrim"] = V.textured("MansardTrim", "distressed_painted_planks", paint=(0.62, 0.58, 0.5, 1), dirt=0.9)
    U["Trim"] = U["PorchTrim"] = (4.0, "long")
    M["Shakes"] = V.textured("MansardSlate", "roof_slates_02", tint=(0.34, 0.31, 0.37, 1), dirt=0.75, moss=0.3)
    U["Shakes"] = (6.0, "vertical")
    M["Roof"] = V.textured("MansardRoof", "roof_slates_02", tint=(0.22, 0.21, 0.23, 1), dirt=0.6)


def frustum(grp, x0, x1, y0, y1, z0, z1, inset, top=True):
    """A mansard: four steep slopes from a rectangle at z0 leaning in by `inset` at z1."""
    bm = bmesh.new()
    lo = [bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0))]
    hi = [bm.verts.new(p) for p in ((x0 + inset, y0 + inset, z1), (x1 - inset, y0 + inset, z1), (x1 - inset, y1 - inset, z1), (x0 + inset, y1 - inset, z1))]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(list(reversed(lo)))
    if top:
        bm.faces.new(hi)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return V.mesh_object("Mansard", bm, grp)


def hood(frame, o):
    """A segmental arched hood with a keystone over a window, on two small brackets."""
    x, y, w, h = o["x"], o["y"], o["w"], o["h"]
    top = y + h + 0.35
    arc = [(x - w / 2 - 0.6, top), (x + w / 2 + 0.6, top)]
    for i in range(8, -1, -1):
        a = math.pi * i / 8
        arc.append((x + math.cos(a) * (w / 2 + 0.6), top + 0.35 + math.sin(a) * 0.65))
    V.prism("Trim", arc, 0.45, frame @ Matrix.Translation((0, -0.45, 0)), bevel=0.04)
    V.box("Trim", (0.5, 0.55, 0.8), (x, -0.3, top + 0.7), bevel=0.04, matrix=frame)  # keystone
    for s in (-1, 1):
        V.prism("Trim", [(0, 0), (0.3, 0), (0.3, -0.7), (0.1, -0.5)], 0.35, frame @ V.frame_matrix((x + s * (w / 2 + 0.45) - 0.15, -0.5, top), (0, 0, 0)))


def brackets(a, b, z, out):
    """Paired scroll brackets under a cornice from a to b (world points on the wall face), facing out."""
    a, b = Vector(a), Vector(b)
    d = b - a
    yaw = math.atan2(d.y, d.x)
    n = max(2, int(d.length / 2.6))
    scroll = [(0, 0), (0.0, -1.3), (0.25, -1.2), (0.55, -0.7), (0.85, -0.25), (1.05, 0.0)]
    for i in range(n + 1):
        p = a + d * (i / n)
        for off in (-0.3, 0.3):
            q = p + d.normalized() * off
            V.prism("Trim", scroll, 0.2, V.frame_matrix((q.x, q.y, z), (0, 0, yaw - math.pi / 2)) @ Matrix.Translation((0, -0.1, 0)))


def quoins(x, y, z0, z1, yaw):
    """Alternating long and short blocks up a corner (x, y), the corner's outward bisector at yaw."""
    zz, i = z0, 0
    while zz < z1 - 0.4:
        long = i % 2 == 0
        for s in (-1, 1):
            m = V.frame_matrix((x, y, zz + 0.45), (0, 0, yaw + s * math.pi / 4))
            V.box("Trim", (1.4 if long else 0.9, 0.25, 0.85), (0.45 if long else 0.2, -0.12, 0), bevel=0.06, matrix=m)
        zz += 1.0
        i += 1


def cresting(points, z):
    """Iron cresting round a roof edge: a rail, spear tips and rings."""
    for a, b in zip(points, points[1:] + points[:1]):
        a, b = Vector((a[0], a[1], z)), Vector((b[0], b[1], z))
        V.bar("Iron", a + Vector((0, 0, 0.12)), b + Vector((0, 0, 0.12)), 0.1, 0.1, bevel=0.02)
        V.bar("Iron", a + Vector((0, 0, 0.7)), b + Vector((0, 0, 0.7)), 0.08, 0.08, bevel=0.02)
        n = max(2, int((b - a).length / 1.4))
        d = (b - a) / n
        for i in range(n):
            p = a + d * i
            V.box("Iron", (0.08, 0.08, 0.9), (p.x, p.y, z + 0.45))
            V.spear("Iron", 0, 0, matrix=Matrix.Translation((p.x, p.y, z + 0.92)) @ Matrix.Scale(0.75, 4))
            q = p + d / 2
            V.torus("Iron", (0, 0, 0), 0.18, 0.03, Matrix.Translation((q.x, q.y, z + 0.42)) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z"), segments=8, sides=4)


def round_window(frame, x, z, r, wall=None):
    """An oculus: a round opening with a moulded ring, glass and a cross bar."""
    pts = [(x + math.cos(2 * math.pi * i / 16) * r, z + math.sin(2 * math.pi * i / 16) * r) for i in range(16)]
    if wall is not None:
        V.cut(wall, [V.prism("_cutters", pts, T * 3, frame @ Matrix.Translation((0, -T, 0)))])
    V.OPENINGS.append(dict(frame=frame, o=dict(x=x, y=z - r, w=2 * r, h=2 * r)))
    V.torus("Trim", (0, 0, 0), r + 0.25, 0.22, frame @ V.frame_matrix((x, -0.1, z), (0, 0, 0)), segments=20, sides=6)
    V.prism("Glass", pts, 0.05, frame @ Matrix.Translation((0, 0.55, 0)))
    V.box("Trim", (2 * r, 0.15, 0.14), (x, 0.5, z), matrix=frame)
    V.box("Trim", (0.14, 0.15, 2 * r), (x, 0.5, z), matrix=frame)


def walls():
    H = CORNICE - FOUND
    up = STORY
    # Main front, its middle opened up behind the tower so the hall and tower rooms run deep.
    front = V.wall_frame((0, MAIN["y0"], FOUND), 0)
    fo = [dict(x=-8.75, y=2.2, w=2.8, h=7.4), dict(x=8.75, y=2.2, w=2.8, h=7.4), dict(x=-8.75, y=up + 2.2, w=2.8, h=7.0), dict(x=8.75, y=up + 2.2, w=2.8, h=7.0)]
    V.wall(front, 26, H, fo + [dict(x=0, y=-0.5, w=7.2, h=H + 1)], "Siding")
    for i, o in enumerate(fo):
        V.window(front, o, curtains=(i in (0, 3)), shutters=False, broken=(i == 1))
        hood(front, o)
    # Tower: a front wall (door, window, oculus) and two short side walls, up to its own cornice.
    TH = TOWER["top"] - FOUND
    tf = V.wall_frame((0, TOWER["y0"], FOUND), 0)
    door_o = dict(x=0, y=0, w=V.DOOR["w"], h=V.DOOR["h"] + 1.5)
    tw = dict(x=0, y=up + 2.0, w=3.0, h=7.2)
    tower_front = V.wall(tf, 9, TH, [door_o, tw], "Siding")
    front_hinge = V.door(tf, 0, 0, "FrontDoor", hall=False)
    V.window(tf, tw, curtains=True)
    hood(tf, tw)
    round_window(tf, 0, CORNICE - FOUND + 4.2, 1.5, wall=tower_front)
    for x, yaw in ((TOWER["x0"], -math.pi / 2), (TOWER["x1"], math.pi / 2)):
        # Below the cornice the side walls run back to the main front; above it, to the tower's back.
        f = V.wall_frame((x, (TOWER["y0"] + 0.0) / 2, FOUND), yaw)
        V.wall(f, 3.0, H, [], "Siding")
        f2 = V.wall_frame((x, (TOWER["y0"] + TOWER["y_back"]) / 2, CORNICE), yaw)
        V.wall(f2, TOWER["y_back"] - TOWER["y0"], TOWER["top"] - CORNICE, [], "Siding")
    tb = V.wall_frame((0, TOWER["y_back"], CORNICE), math.pi)
    V.wall(tb, 9, TOWER["top"] - CORNICE, [], "Siding")
    # Sides: two windows a floor.
    for x, yaw, sign in ((MAIN["x0"], -math.pi / 2, -1), (MAIN["x1"], math.pi / 2, 1)):
        f = V.wall_frame((x, 11.0, FOUND), yaw)
        lx = [-sign * (6 - 11), -sign * (16 - 11)]  # world y 6 and 16
        lx = [5, -5] if sign < 0 else [-5, 5]
        ops = [dict(x=lx[0], y=2.2, w=2.8, h=7.4), dict(x=lx[1], y=2.2, w=2.8, h=7.4), dict(x=lx[0], y=up + 2.2, w=2.8, h=7.0), dict(x=lx[1], y=up + 2.2, w=2.8, h=7.0)]
        V.wall(f, 22, H, ops, "Siding")
        for i, o in enumerate(ops):
            V.window(f, o, shutters=(i == 2), boarded=(sign > 0 and i == 3), curtains=(sign < 0 and i == 1))
            hood(f, o)
    # Back: the back door and windows.
    back = V.wall_frame((0, MAIN["y1"], FOUND), math.pi)  # local x -> world -x
    bo = [dict(x=6, y=0, w=V.DOOR["w"], h=V.DOOR["h"] + 1.5), dict(x=-6, y=2.2, w=2.8, h=7.4), dict(x=6, y=up + 2.2, w=2.8, h=7.0), dict(x=-6, y=up + 2.2, w=2.8, h=7.0)]
    V.wall(back, 26, H, bo, "Siding")
    back_hinge = V.door(back, 6, 0, "BackDoor", hall=False)
    for o in bo[1:]:
        V.window(back, o, boarded=(o["x"] == 6))
        hood(back, o)
    # Belt course between the floors, the cornice, quoins.
    for (a, b) in (((MAIN["x0"], 0), (TOWER["x0"], 0)), ((TOWER["x1"], 0), (MAIN["x1"], 0))):
        V.box("Trim", (abs(b[0] - a[0]), 0.4, 0.45), ((a[0] + b[0]) / 2, -0.2, FOUND + STORY), bevel=0.05)
    V.box("Trim", (9.0, 0.4, 0.45), (0, TOWER["y0"] - 0.2, FOUND + STORY), bevel=0.05)
    for z, sx, sy, cy in ((CORNICE, 26.8, 22.8, 11.0),):
        V.box("Trim", (sx + 0.4, sy + 0.4, 0.5), (0, cy, z + 0.25), bevel=0.06)
        V.box("Trim", (sx, sy, 1.2), (0, cy, z - 0.6), bevel=0.04)
    V.box("Trim", (10.2, TOWER["y_back"] - TOWER["y0"] + 1.2, 0.5), (0, (TOWER["y0"] + TOWER["y_back"]) / 2, TOWER["top"] + 0.25), bevel=0.06)
    V.box("Trim", (9.6, TOWER["y_back"] - TOWER["y0"] + 0.6, 1.0), (0, (TOWER["y0"] + TOWER["y_back"]) / 2, TOWER["top"] - 0.5), bevel=0.04)
    brackets((MAIN["x0"], -0.3, 0), (TOWER["x0"], -0.3, 0), CORNICE - 1.2, -1)
    brackets((TOWER["x1"], -0.3, 0), (MAIN["x1"], -0.3, 0), CORNICE - 1.2, -1)
    brackets((TOWER["x0"], TOWER["y0"] - 0.3, 0), (TOWER["x1"], TOWER["y0"] - 0.3, 0), CORNICE - 1.2, -1)
    brackets((TOWER["x0"], TOWER["y0"] - 0.3, 0), (TOWER["x1"], TOWER["y0"] - 0.3, 0), TOWER["top"] - 1.0, -1)
    brackets((MAIN["x1"] + 0.3, 0, 0), (MAIN["x1"] + 0.3, MAIN["y1"], 0), CORNICE - 1.2, 1)
    brackets((MAIN["x0"] - 0.3, MAIN["y1"], 0), (MAIN["x0"] - 0.3, 0, 0), CORNICE - 1.2, 1)
    for x, y, yaw in ((MAIN["x0"], 0, -3 * math.pi / 4 + math.pi), (MAIN["x1"], 0, 3 * math.pi / 4 - math.pi), (MAIN["x0"], MAIN["y1"], -math.pi / 4), (MAIN["x1"], MAIN["y1"], math.pi / 4)):
        pass
    for x in (MAIN["x0"], MAIN["x1"]):
        for y in (MAIN["y0"], MAIN["y1"]):
            V.box("Trim", (1.0, 1.0, CORNICE - FOUND), (x, y, (FOUND + CORNICE) / 2), bevel=0.06)  # corner pilasters
            for zz in range(int(FOUND) + 1, int(CORNICE) - 1, 2):
                V.box("Trim", (1.3, 1.3, 0.9), (x, y, zz + 0.45), bevel=0.08)  # quoin blocks
    for x in (TOWER["x0"], TOWER["x1"]):
        V.box("Trim", (0.9, 0.9, TOWER["top"] - FOUND), (x, TOWER["y0"], (FOUND + TOWER["top"]) / 2), bevel=0.06)
        for zz in range(int(FOUND) + 1, int(TOWER["top"]) - 1, 2):
            V.box("Trim", (1.2, 1.2, 0.9), (x, TOWER["y0"], zz + 0.45), bevel=0.08)
    return front_hinge, back_hinge


def roofs():
    # The main mansard, cut where its dormers stand.
    over = 0.5
    m = frustum("Shakes", MAIN["x0"] - over, MAIN["x1"] + over, MAIN["y0"] - over, MAIN["y1"] + over, CORNICE + 0.5, MANSARD_TOP, INSET)
    dormers = [((-8.75, MAIN["y0"] - over), 0.0), ((8.75, MAIN["y0"] - over), 0.0), ((MAIN["x0"] - over, 11.0), -math.pi / 2), ((MAIN["x1"] + over, 11.0), math.pi / 2), ((0.0, MAIN["y1"] + over), math.pi)]
    cutters = []
    for (x, y), yaw in dormers:
        f = V.wall_frame((x, y, CORNICE + 0.5), yaw)
        cutters.append(V.box("_cutters", (3.0, 6.0, 5.6), (0, 2.6, 2.6), matrix=f))
    V.cut(m, cutters)
    for (x, y), yaw in dormers:
        f = V.wall_frame((x, y, CORNICE + 0.5), yaw)
        o = dict(x=0, y=1.0, w=2.2, h=3.8)
        dw = V.wall(f, 3.8, 6.2, [o], "Trim")
        V.window(f, o)
        for s in (-1, 1):
            V.box("Trim", (0.3, 5.0, 6.2), (s * 1.9, 2.4, 3.1), matrix=f)  # cheeks
        arc = [(-2.3, 6.2), (2.3, 6.2)]
        for i in range(8, -1, -1):
            a = math.pi * i / 8
            arc.append((math.cos(a) * 2.3, 6.2 + math.sin(a) * 1.0))
        V.prism("Roof", arc, 5.6, f @ Matrix.Translation((0, -0.3, 0)), bevel=0.04)
    V.box("Roof", (MAIN["x1"] - MAIN["x0"] + 2 * over - 2 * INSET + 0.4, MAIN["y1"] - MAIN["y0"] + 2 * over - 2 * INSET + 0.4, 0.4), (0, 11.0, MANSARD_TOP + 0.2), bevel=0.06)
    top = [(MAIN["x0"] - over + INSET, MAIN["y0"] - over + INSET), (MAIN["x1"] + over - INSET, MAIN["y0"] - over + INSET), (MAIN["x1"] + over - INSET, MAIN["y1"] + over - INSET), (MAIN["x0"] - over + INSET, MAIN["y1"] + over - INSET)]
    cresting(top, MANSARD_TOP + 0.4)
    # Tower cap: a taller, steeper mansard with a dormer, cresting and finials.
    ty0, ty1 = TOWER["y0"] - 0.5, TOWER["y_back"] + 0.5
    cap = frustum("Shakes", TOWER["x0"] - 0.5, TOWER["x1"] + 0.5, ty0, ty1, TOWER["top"] + 0.5, TOWER["cap"], 1.6)
    f = V.wall_frame((0, ty0, TOWER["top"] + 0.5), 0)
    V.cut(cap, [V.box("_cutters", (2.4, 4.0, 4.4), (0, 1.8, 2.6), matrix=f)])
    o = dict(x=0, y=1.0, w=1.6, h=3.0)
    V.wall(f, 2.8, 4.8, [o], "Trim")
    V.window(f, o, broken=True)
    V.prism("Roof", [(-1.6, 4.8), (1.6, 4.8), (0, 6.3)], 4.0, f @ Matrix.Translation((0, -0.2, 0)), bevel=0.04)
    V.box("Roof", (TOWER["x1"] - TOWER["x0"] - 2.2, ty1 - ty0 - 3.2 + 0.4, 0.4), (0, (ty0 + ty1) / 2, TOWER["cap"] + 0.2), bevel=0.06)
    ttop = [(TOWER["x0"] + 1.1, ty0 + 1.6), (TOWER["x1"] - 1.1, ty0 + 1.6), (TOWER["x1"] - 1.1, ty1 - 1.6), (TOWER["x0"] + 1.1, ty1 - 1.6)]
    cresting(ttop, TOWER["cap"] + 0.4)
    for (x, y) in ttop:
        V.lathe("Iron", [(0.18, 0), (0.18, 0.4), (0.3, 0.6), (0.1, 0.9), (0.08, 2.2), (0.2, 2.5), (0.0, 3.4)], (x, y, TOWER["cap"] + 0.3), segments=8)
    # Chimneys rising through the mansard.
    for x in (-9.5, 9.5):
        V.box("Brick", (2.6, 2.6, 12.0), (x, 16.0, MANSARD_TOP - 2.0), bevel=0.06)
        V.box("Stone", (3.2, 3.2, 0.5), (x, 16.0, MANSARD_TOP + 4.2), bevel=0.06)
        V.lathe("Brick", [(0.38, 0), (0.38, 1.0), (0.46, 1.1), (0.46, 1.3), (0.28, 1.3)], (x - 0.6, 16.0, MANSARD_TOP + 4.45), segments=10)


def portico():
    """A columned porch in front of the tower, a balcony on top, and wide stone steps."""
    x0, x1, y0 = -4.6, 4.6, PORCH_Y
    V.box("Stone", (x1 - x0, TOWER["y0"] - y0, FOUND), (0, (y0 + TOWER["y0"]) / 2, FOUND / 2), bevel=0.08)
    V.box("Porch", (x1 - x0 - 0.4, TOWER["y0"] - y0 - 0.2, 0.15), (0, (y0 + TOWER["y0"]) / 2, FOUND + 0.07))
    for s in range(1, 5):
        top = FOUND - s * FOUND / 4
        V.box("Stone", (6.0, 1.0, top), (0, y0 - (s - 0.5), top / 2), bevel=0.05)
    for sx in (-3.5, 3.5):  # cheek walls with urns
        V.prism("Stone", [(0, 0), (4.6, 0), (0, FOUND + 0.6)], 1.0, V.frame_matrix((sx - 0.5 if sx < 0 else sx + 0.5, y0, 0), (0, 0, -math.pi / 2)) @ Matrix.Translation((0, -0.5, 0)))
    col_h = 9.0
    for sx in (-3.6, 3.6):
        V.lathe("Trim", [(0.62, 0), (0.62, 0.35), (0.5, 0.5), (0.42, 0.7), (0.36, col_h - 0.8), (0.48, col_h - 0.5), (0.62, col_h - 0.3), (0.62, col_h)], (sx, y0 + 0.9, FOUND), segments=14)
        V.box("Trim", (1.3, 1.3, 0.3), (sx, y0 + 0.9, FOUND + 0.15), bevel=0.04)
    ent = FOUND + col_h
    V.box("Trim", (x1 - x0 + 0.8, TOWER["y0"] - y0 + 0.6, 1.3), (0, (y0 + TOWER["y0"]) / 2 - 0.3, ent + 0.65), bevel=0.06)
    V.box("Trim", (x1 - x0 + 1.2, TOWER["y0"] - y0 + 1.0, 0.3), (0, (y0 + TOWER["y0"]) / 2 - 0.3, ent + 1.45), bevel=0.05)
    brackets((x0 - 0.2, y0 - 0.4, 0), (x1 + 0.2, y0 - 0.4, 0), ent + 0.0, -1)
    # Balcony balustrade on top (the tower's middle window looks out over it).
    bz = ent + 1.6
    V.box("Trim", (x1 - x0 + 0.6, 0.3, 0.25), (0, y0 - 0.1, bz + 2.6), bevel=0.04)
    i = 0
    xx = x0
    while xx <= x1 + 0.01:
        if i not in (6, 7):  # two balusters gone
            V.lathe("Trim", [(0.14, 0), (0.2, 0.3), (0.1, 0.9), (0.22, 1.6), (0.12, 2.3), (0.14, 2.6)], (xx, y0 - 0.1, bz), segments=6)
        xx += 0.6
        i += 1
    for sx in (x0, x1):
        V.box("Trim", (0.3, TOWER["y0"] - y0, 0.25), (sx, (y0 + TOWER["y0"]) / 2, bz + 2.6), bevel=0.04)
    # Lantern on a bracket beside the door, pumpkins on the steps.
    lf = V.frame_matrix((-2.9, TOWER["y0"] - 0.55, FOUND + 6.9))
    V.box("Iron", (0.8, 0.8, 0.25), (0, 0, 0.7), bevel=0.05, matrix=lf)
    V.box("Iron", (0.12, 0.7, 0.12), (0, 0.3, 0.9), matrix=lf)
    V.box("LanternGlow", (0.55, 0.55, 1.0), (0, 0, 0), matrix=lf)
    for sx in (-0.27, 0.27):
        for sy in (-0.27, 0.27):
            V.box("Iron", (0.07, 0.07, 1.1), (sx, sy, 0), matrix=lf)
    V.pumpkin((-2.4, y0 - 0.5, FOUND - FOUND / 4), 0.6, math.radians(-10), carved=True)
    V.pumpkin((2.5, y0 - 1.5, FOUND - 2 * FOUND / 4), 0.5, math.radians(30), rotten=True)
    V.pumpkin((3.0, TOWER["y0"] - 1.2, FOUND + 0.07), 0.55, math.radians(15), carved=True)
    D.light("PorchLight", (-2.9, TOWER["y0"] - 1.1, FOUND + 6.9), 16, 0.9, (255, 170, 96))
    D.light("PumpkinLight", (-2.4, y0 - 0.5, FOUND - FOUND / 4 + 0.4), 7, 0.8, (255, 130, 50), shadows=False)
    D.light("PumpkinLight", (3.0, TOWER["y0"] - 1.2, FOUND + 0.4), 7, 0.8, (255, 130, 50), shadows=False)
    D.anchor("Garland", (0, y0 - 0.55, ent - 0.05))
    D.anchor("PumpkinPile", (-6.5, y0 - 3.4, 0), 15)
    # Dead vines up the tower corner and one column.
    V.spiral_vine(3.6, y0 + 0.9, FOUND, ent - 0.4, r=0.72, turns=2.2)
    V.creeper((MAIN["x0"] - 0.7, -0.7, FOUND), 20.0, (0.7, -0.7, 0),
              runners=[(5.0, (-0.1, 6.0, 1.5), -0.6), (10.5, (2.0, -0.1, -1.0), 0.5), (15.5, (-0.1, 4.5, 2.0), -0.4)], radius=0.22)


def foundation():
    V.box("Stone", (26.6, 22.6, FOUND), (0, 11, FOUND / 2), bevel=0.08)
    V.box("Stone", (9.6, 3.6, FOUND), (0, -1.5, FOUND / 2), bevel=0.08)
    V.box("Trim", (27.0, 23.0, 0.4), (0, 11, FOUND + 0.2), bevel=0.05)
    for s in range(1, 5):  # back steps
        top = FOUND - s * FOUND / 4
        V.box("Stone", (5.0, 1.0, top), (-6, MAIN["y1"] + (s - 0.5), top / 2), bevel=0.05)


def rooms():
    pi, U = math.pi, I.U
    g, c = FOUND + 0.5, FOUND + STORY - 0.6
    u, uc = FOUND + STORY, FOUND + 2 * STORY - 0.6
    m, mc = CORNICE + 0.6, CORNICE + 5.4
    xi0, xi1, yb = MAIN["x0"] + T, MAIN["x1"] - T, MAIN["y1"] - T
    ty = TOWER["y0"] + T
    plan = [
        dict(id="G1", x0=xi0, x1=-5.4, y0=T, y1=10.8, floor=g, ceil=c, paper="WallpaperB"),
        dict(id="G2", x0=-3.6, x1=3.6, y0=ty, y1=10.8, floor=g, ceil=c, paper="WallpaperC"),
        dict(id="G3", x0=5.4, x1=xi1, y0=T, y1=10.8, floor=g, ceil=c, paper="WallpaperA"),
        dict(id="G4", x0=xi0, x1=-0.2, y0=11.0, y1=yb, floor=g, ceil=c, paper="WallpaperA"),
        dict(id="G5", x0=0.0, x1=xi1, y0=11.0, y1=yb, floor=g, ceil=c, paper="WallpaperC"),
        dict(id="U1", x0=xi0, x1=-5.4, y0=T, y1=10.8, floor=u, ceil=uc, paper="WallpaperC"),
        dict(id="U2", x0=-3.6, x1=3.6, y0=ty, y1=10.8, floor=u, ceil=uc, paper="WallpaperB"),
        dict(id="U3", x0=5.4, x1=xi1, y0=T, y1=10.8, floor=u, ceil=uc, paper="WallpaperB"),
        dict(id="U4", x0=xi0, x1=-0.2, y0=11.0, y1=yb, floor=u, ceil=uc, paper="WallpaperB"),
        dict(id="U5", x0=0.0, x1=xi1, y0=11.0, y1=yb, floor=u, ceil=uc, paper="WallpaperA"),
        dict(id="M1", x0=-11.0, x1=-5.6, y0=1.2, y1=9.0, floor=m, ceil=mc, paper="Boards"),
        dict(id="M2", x0=5.6, x1=11.0, y0=1.2, y1=9.0, floor=m, ceil=mc, paper="Boards"),
        dict(id="T3", x0=-3.6, x1=3.6, y0=ty, y1=TOWER["y_back"] - T, floor=m, ceil=TOWER["top"] - 0.6, paper="WallpaperC"),
    ]
    roles = {"G1": ("living", "y0"), "G2": ("hall", "y0"), "G3": ("living", "y0"), "G4": ("kitchen", "x0"), "G5": ("living", "x1"),
             "U1": ("living", "y0"), "U2": ("living", "y0"), "U3": ("living", "y0"), "U4": ("living", "x0"), "U5": ("living", "x1"),
             "M1": ("attic", "y0"), "M2": ("attic", "y0"), "T3": ("tower", "y0")}
    for room in plan:
        lamp = I.box_room(V, room)
        role, front = roles[room["id"]]
        D.room(room, lamp, role, front)
        if room["id"] == "G2":  # the hall keeps its grand stair and clock; the game furnishes the rest
            I.stairs(V, I.at(V, 1.6, 2.0, room["floor"]), steps=12)
            I.clock(V, I.at(V, -3.5 + 0.16 * U, 6.0, room["floor"], pi / 2))


def colliders():
    D.collider((26, 22, CORNICE), (0, 11, CORNICE / 2))
    D.collider((9, 3, TOWER["top"]), (0, -1.5, TOWER["top"] / 2))
    D.collider((9.2, TOWER["y0"] - PORCH_Y, FOUND), (0, (PORCH_Y + TOWER["y0"]) / 2, FOUND / 2))
    for s in range(1, 5):
        top = FOUND - s * FOUND / 4
        D.collider((6.0, 1.0, top), (0, PORCH_Y - (s - 0.5), top / 2))
        D.collider((5.0, 1.0, top), (-6, MAIN["y1"] + (s - 0.5), top / 2))
    for sx in (-4.0, 4.0):
        D.collider((1.0, 4.6, FOUND + 0.6), (sx, PORCH_Y - 2.3, (FOUND + 0.6) / 2))  # cheek walls
    for sx in (-3.6, 3.6):
        D.collider((1.3, 1.3, 9.0), (sx, PORCH_Y + 0.9, FOUND + 4.5))
    for x in (-9.5, 9.5):
        D.collider((2.6, 2.6, 12), (x, 16, MANSARD_TOP - 2))


def build():
    V.reset()
    V.build_materials()
    I.materials(V)
    materials()
    foundation()
    front_hinge, back_hinge = walls()
    roofs()
    portico()
    rooms()
    colliders()
    w, h = V.DOOR["w"], V.DOOR["h"]
    D.front_door(0.0, TOWER["y0"] + 0.55, FOUND)
    D.hinge("FrontDoor", "FrontDoor", (-w / 2, TOWER["y0"] + 0.55, FOUND + h / 2), 0, 100, False)
    D.hinge("BackDoor", "BackDoor", (-6 + w / 2, MAIN["y1"] - 0.55, FOUND + h / 2), 180, 100, True, "Back door")
    D.yard = dict(fence="Iron", pathFrom=PORCH_Y - 4.3, tree=(-10.5, -13.0, 0), graves=[(8.0, -11.0, 0), (10.6, -12.2, 0)])
    D.write(V.ROOT)
    for obj in list(V.GROUPS.get("_cutters", bpy.data.collections.new("_none")).objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    merged = {}
    for name in list(V.GROUPS):
        if not name.startswith("_"):
            obj = V.merge_group(name)
            if obj:
                merged[name] = obj

    def set_origin(obj, matrix):
        if obj is not None:
            obj.data.transform(matrix.inverted())
            obj.matrix_world = matrix

    for name, hinge in (("FrontDoor", front_hinge), ("Brass_FrontDoor", front_hinge), ("BackDoor", back_hinge), ("Brass_BackDoor", back_hinge)):
        set_origin(merged.get(name), hinge)
    tris = {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()}
    print("TRIANGLES", sum(tris.values()), sorted(tris.items(), key=lambda kv: -kv[1])[:8])
    return merged


FLAT = {"Glass", "LanternGlow", "PumpkinGlow", "Interior", "Silhouette", "Iron", "Brass_FrontDoor", "Brass_BackDoor", "Canvas", "Pale"}

if __name__ == "__main__":
    merged = build()
    if "--render" in ARGS:
        name = ARGS[ARGS.index("--render") + 1]
        views = ARGS[ARGS.index("--views") + 1].split(",") if "--views" in ARGS else ["front", "corner"]
        V.render("mansard_" + name, night="--night" in ARGS, views=views)
    if "--export" in ARGS:
        import export_victorian

        export_victorian.export(merged, EXPORT, "Mansard.fbx", flat=FLAT)
