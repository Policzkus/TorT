"""A rotting Carpenter Gothic farmhouse for Maple Lane (Blender 4.4, headless).

    blender -b --factory-startup --python art/scripts/farmhouse.py -- [--render NAME [--views a,b] [--night]] [--export]

One and a half storeys of board-and-batten under a steep tin roof gone to rust, a steep central
gable with a pointed Gothic window, gingerbread bargeboards, a sagging full-width porch, a lean-to
kitchen at the back, a fieldstone chimney and a rooster weathervane. Real rooms behind every window
(interiors.py pieces). Same layout rules as the Victorian: front door centre at x = 0 on the front
wall (y = 0), street toward -Y, studs. Writes World/HouseData/Farmhouse.luau.
"""

import math
import pathlib
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import housekit as K  # noqa: E402
import interiors as I  # noqa: E402
import victorian as V  # noqa: E402

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "farmhouse"
rng = random.Random(23)

T = V.T
FOUND = 2.0
STORY = V.STORY
EAVE = FOUND + STORY + 3.0  # a knee wall above the ground storey
RIDGE = EAVE + 11.0
GABLE_TOP = EAVE + 10.0  # the steep front gable
GHALF = 4.5
MAIN = dict(x0=-12.0, x1=12.0, y0=0.0, y1=18.0)
LEAN = dict(x0=-12.0, x1=4.0, y0=18.0, y1=24.0, low=FOUND + 10.0, high=FOUND + 12.4)
PORCH = dict(x0=-12.6, x1=12.6, y=-8.0)
D = K.Data("Farmhouse")


def materials():
    M, U = V.MATERIALS, V.UV_RULES
    M["Siding"] = V.textured("FarmSiding", "distressed_painted_planks", tint=(1.3, 1.28, 1.2, 1), dirt=0.95)
    U["Siding"] = (8.0, "vertical")  # the boards run up the wall
    trim = V.textured("FarmTrim", "distressed_painted_planks", paint=(0.07, 0.09, 0.075, 1), dirt=0.8)
    M["Trim"] = M["PorchTrim"] = trim
    U["Trim"] = U["PorchTrim"] = (4.0, "long")
    M["Roof"] = V.textured("TinRoof", "rusty_painted_metal", tint=(0.3, 0.26, 0.25, 1), dirt=0.75, rough=1.0)
    U["Roof"] = (4.0, "vertical")
    M["Shutter"] = V.textured("FarmShutter", "wood_shutter", paint=(0.2, 0.12, 0.1, 1), dirt=0.7)


def walls():
    E = EAVE - FOUND
    # Front: up to the eave, rising into the steep central gable.
    front = V.wall_frame((0, MAIN["y0"], FOUND), 0)
    door_o = dict(x=0, y=0, w=V.DOOR["w"], h=V.DOOR["h"] + 1.5)
    win = [dict(x=-7.5, y=2.4, w=3.0, h=6.5), dict(x=7.5, y=2.4, w=3.0, h=6.5)]
    outline = [(-12, 0), (12, 0), (12, E), (GHALF, E), (0, GABLE_TOP - FOUND), (-GHALF, E), (-12, E)]
    gothic = dict(x=0, y=STORY + 0.9, w=2.8, h=6.6)
    front_wall = K.poly_wall(V, front, outline, [door_o] + win, "Siding")
    apex = K.gothic_window(V, front, gothic["x"], gothic["y"], gothic["w"], gothic["h"], wall=front_wall)
    front_hinge = V.door(front, 0, 0, "FrontDoor", hall=False)
    V.window(front, win[0], shutters=True, curtains=True)
    V.window(front, win[1], broken=True, shutters=True)
    K.battens(V, front, -12, 12, lambda x: E if abs(x) > GHALF else E + (GABLE_TOP - EAVE) * (1 - abs(x) / GHALF) - 0.4,
              [door_o] + win + [dict(x=0, y=gothic["y"] - 0.5, w=gothic["w"] + 1.2, h=apex - gothic["y"] + 1.0)])
    # Sides: full gables up to the ridge, two windows below and one in the gable.
    side_outline = [(-9, 0), (9, 0), (9, E), (0, RIDGE - FOUND), (-9, E)]
    for x, yaw, sign in ((MAIN["x0"], -math.pi / 2, -1), (MAIN["x1"], math.pi / 2, 1)):
        f = V.wall_frame((x, 9.0, FOUND), yaw)
        # Local x runs to world y = 9 - lx on the left, 9 + lx on the right.
        ops = [dict(x=sign * (5 - 9), y=2.4, w=3.0, h=6.5), dict(x=sign * (14 - 9), y=2.4, w=3.0, h=6.5), dict(x=0, y=STORY + 1.4, w=2.6, h=5.0)]
        if sign > 0:
            ops[0]["x"], ops[1]["x"] = -4, 5
        else:
            ops[0]["x"], ops[1]["x"] = 4, -5
        K.poly_wall(V, f, side_outline, ops, "Siding")
        for i, o in enumerate(ops):
            V.window(f, o, shutters=(i == 0), boarded=(sign > 0 and i == 2), curtains=(sign < 0 and i == 2), broken=(sign < 0 and i == 1))
        K.battens(V, f, -9, 9, lambda lx: E + (RIDGE - EAVE) * (1 - abs(lx) / 9) - 0.4, ops)
    # Back wall (the lean-to covers its left part), and the lean-to.
    back = V.wall_frame((0, MAIN["y1"], FOUND), math.pi)
    back_ops = [dict(x=-7.5, y=2.4, w=3.0, h=6.5)]  # world x = 7.5
    V.wall(back, 24, E, back_ops, "Siding")
    V.window(back, back_ops[0], curtains=True)
    K.battens(V, back, -12, 12, lambda x: E, back_ops)
    lb = V.wall_frame(((LEAN["x0"] + LEAN["x1"]) / 2, LEAN["y1"], FOUND), math.pi)  # local x -> world -x + (-4)
    lean_ops = [dict(x=0, y=0, w=V.DOOR["w"], h=V.DOOR["h"] + 1.5), dict(x=5, y=2.6, w=2.6, h=4.6)]
    V.wall(lb, LEAN["x1"] - LEAN["x0"], LEAN["low"] - FOUND, lean_ops, "Siding")
    back_hinge = V.door(lb, 0, 0, "BackDoor", hall=False)
    V.window(lb, lean_ops[1])
    for x, yaw in ((LEAN["x0"], -math.pi / 2), (LEAN["x1"], math.pi / 2)):
        f = V.wall_frame((x, (LEAN["y0"] + LEAN["y1"]) / 2, FOUND), yaw)
        lo, hi = LEAN["low"] - FOUND, LEAN["high"] - FOUND
        pts = [(-3, 0), (3, 0), (3, hi), (-3, lo)] if yaw < 0 else [(-3, 0), (3, 0), (3, lo), (-3, hi)]
        K.poly_wall(V, f, pts, [], "Siding")
    # Corner boards and the eave fascia.
    for cx, cy in ((MAIN["x0"], MAIN["y0"]), (MAIN["x1"], MAIN["y0"]), (MAIN["x0"], MAIN["y1"]), (MAIN["x1"], MAIN["y1"])):
        V.box("Trim", (0.7, 0.7, E), (cx, cy, FOUND + E / 2), bevel=0.06)
    return front_hinge, back_hinge


def roofs():
    slope = (RIDGE - EAVE) / 9.0
    over = 1.2
    low_z = EAVE - over * slope
    for side, eave_y in ((-1, MAIN["y0"] - over), (1, MAIN["y1"] + over)):
        V.slab("Roof", (0, eave_y, low_z), (0, 9.0, RIDGE), 24 + 2 * over, 0.45, bevel=0.04)
        V.box("Trim", (24 + 2 * over, 0.3, 0.8), (0, eave_y + side * 0.15, low_z - 0.2), bevel=0.04)  # fascia
    V.box("Roof", (24 + 2 * over + 0.2, 0.8, 0.4), (0, 9.0, RIDGE + 0.35), bevel=0.1)  # ridge cap
    for x, out in ((MAIN["x0"], -1), (MAIN["x1"], 1)):
        K.gable_trim(V, (x + out * (over + 0.1), MAIN["y0"] - over, low_z), (x + out * (over + 0.1), 9.0, RIDGE + 0.3), (x + out * (over + 0.1), MAIN["y1"] + over, low_z))
    # The steep front gable's roof, running back into the main roof.
    gslope = (GABLE_TOP - EAVE) / GHALF
    for s in (-1, 1):
        V.slab("Roof", (s * (GHALF + 0.8), 4.0, EAVE - 0.8 * gslope), (0, 4.0, GABLE_TOP + 0.1), 10.4, 0.45, bevel=0.04)
    V.box("Roof", (0.7, 10.4, 0.4), (0, 4.0, GABLE_TOP + 0.45), bevel=0.1)
    K.gable_trim(V, (-(GHALF + 0.8), -1.15, EAVE - 0.8 * gslope), (0, -1.15, GABLE_TOP + 0.4), (GHALF + 0.8, -1.15, EAVE - 0.8 * gslope))
    # Lean-to roof.
    V.slab("Roof", (-4, LEAN["y1"] + 0.8, LEAN["low"] - 0.25), (-4, LEAN["y0"] - 0.2, LEAN["high"] + 0.2), 17.2, 0.4)
    # Fieldstone chimney on the left gable end.
    V.box("Stone", (2.6, 3.8, RIDGE + 3.5), (MAIN["x0"] - 1.3, 9.0, (RIDGE + 3.5) / 2), bevel=0.08)
    V.box("Stone", (3.2, 4.4, 0.5), (MAIN["x0"] - 1.3, 9.0, RIDGE + 3.6), bevel=0.06)
    for dy in (-0.8, 0.8):
        V.lathe("Brick", [(0.4, 0), (0.4, 1.0), (0.5, 1.1), (0.5, 1.3), (0.3, 1.3)], (MAIN["x0"] - 1.3, 9.0 + dy, RIDGE + 3.85), segments=10)
    # A rooster weathervane, bent.
    vane = V.frame_matrix((5.0, 9.0, RIDGE + 0.5), (math.radians(4), math.radians(-6), 0))
    V.box("Iron", (0.12, 0.12, 3.4), (0, 0, 1.7), matrix=vane)
    for a in (0, math.pi / 2):
        V.box("Iron", (1.6, 0.06, 0.06), (0, 0, 2.4), rot=(0, 0, a), matrix=vane)
    rooster = [(-0.8, 0.0), (0.5, 0.0), (0.9, 0.35), (0.75, 0.75), (0.95, 1.05), (0.7, 1.1), (0.5, 0.75), (0.1, 0.55), (-0.3, 0.95), (-0.65, 1.2), (-0.55, 0.6)]
    V.prism("Iron", rooster, 0.06, vane @ V.frame_matrix((0, -0.03, 3.0), (0, 0, 0.6)))


def porch():
    x0, x1, y0 = PORCH["x0"], PORCH["x1"], PORCH["y"]
    w, d = x1 - x0, -y0
    cx = (x0 + x1) / 2
    deck = V.box("Porch", (w, d, 0.35), (cx, y0 / 2, FOUND - 0.18), bevel=0.04)
    V.cut(deck, [V.box("_cutters", (1.4, 1.1, 1.0), (8.6, -5.2, FOUND - 0.2))])  # a rotted hole
    V.box("Interior", (1.6, 1.3, 0.1), (8.6, -5.2, FOUND - 1.2))
    V.box("PorchTrim", (w + 0.3, 0.4, 0.45), (cx, y0 + 0.05, FOUND - 0.2), bevel=0.05)
    V.box("Interior", (w - 0.4, 0.2, FOUND - 0.4), (cx, y0 + 0.4, (FOUND - 0.4) / 2))
    xx = x0 + 0.5
    while xx < x1 - 0.3:
        for ang in (0.8, -0.8):
            V.box("Lattice", (0.14, 0.1, 2.4), (xx, y0 + 0.25, (FOUND - 0.4) / 2), rot=(0, ang, 0))
        xx += 1.3
    for s in range(1, 4):
        top = FOUND - s * FOUND / 3
        V.box("Porch", (5.0, 1.05, top), (0, y0 - (s - 0.5) * 1.05, top / 2), rot=(0, math.radians((s - 2) * 1.2), 0), bevel=0.04)
    # Posts (the middle ones have sunk, so the roof sags), with little brackets.
    posts = [x0 + 0.35, -7.3, -2.7, 2.7, 7.3, x1 - 0.35]
    roof_low, roof_high = FOUND + 10.0, FOUND + 11.2
    post_y = y0 + 0.4
    for i, x in enumerate(posts):
        sag = -0.3 if i in (2, 3) else (-0.15 if i in (1, 4) else 0.0)
        h = roof_low - FOUND + sag - 0.6
        V.box("PorchTrim", (0.5, 0.5, h), (x, post_y, FOUND + h / 2), bevel=0.06)
        V.box("PorchTrim", (0.7, 0.7, 0.3), (x, post_y, FOUND + 0.15), bevel=0.05)
        for s in (-1, 1):
            V.prism("PorchTrim", [(0, 0), (1.0, 0), (0, -1.0)], 0.2, V.frame_matrix((x + s * 0.25, post_y - 0.1, FOUND + h), (0, 0, 0 if s > 0 else math.pi)))
    V.box("PorchTrim", (w, 0.45, 0.9), (cx, post_y, roof_low - 0.45), rot=(0, math.radians(0.5), 0), bevel=0.05)  # beam
    V.slab("Roof", (cx, y0 - 0.6, roof_low), (cx, 0.2, roof_high), w + 0.6, 0.4)
    V.box("Boards", (w, d - 0.3, 0.15), (cx, y0 / 2 + 0.15, roof_low - 0.1))
    # Railings of plain square balusters, broken in places; open at the steps.
    def railing(a, b, gap=None):
        a, b = Vector(a), Vector(b)
        length = (b - a).length
        f = V.frame_matrix(((a + b) / 2).to_tuple(), (0, 0, math.atan2(b.y - a.y, b.x - a.x)))
        V.box("PorchTrim", (length, 0.3, 0.2), (0, 0, 3.0), bevel=0.04, matrix=f)
        V.box("PorchTrim", (length, 0.25, 0.18), (0, 0, 0.4), bevel=0.04, matrix=f)
        n = int(length / 0.55)
        for k in range(1, n):
            px = -length / 2 + k * length / n
            if gap and gap[0] <= k / n <= gap[1]:
                continue
            V.box("PorchTrim", (0.14, 0.14, 2.5), (px, 0, 1.7), rot=(rng.uniform(-0.04, 0.04), 0, 0), matrix=f)
    railing((posts[0], post_y, FOUND), (posts[1], post_y, FOUND))
    railing((posts[1], post_y, FOUND), (posts[2], post_y, FOUND), gap=(0.35, 0.6))
    railing((posts[3], post_y, FOUND), (posts[4], post_y, FOUND))
    railing((posts[4], post_y, FOUND), (posts[5], post_y, FOUND))
    railing((x0 + 0.35, post_y, FOUND), (x0 + 0.35, -0.4, FOUND))
    railing((x1 - 0.35, post_y, FOUND), (x1 - 0.35, -0.4, FOUND))
    # The lantern by the door, a rocking chair, a washtub, a broom, pumpkins.
    lf = V.frame_matrix((-2.9, -0.55, FOUND + 6.9))
    V.box("Iron", (0.8, 0.8, 0.25), (0, 0, 0.7), bevel=0.05, matrix=lf)
    V.box("Iron", (0.12, 0.7, 0.12), (0, 0.3, 0.9), matrix=lf)
    V.box("LanternGlow", (0.55, 0.55, 1.0), (0, 0, 0), matrix=lf)
    for sx in (-0.27, 0.27):
        for sy in (-0.27, 0.27):
            V.box("Iron", (0.07, 0.07, 1.1), (sx, sy, 0), matrix=lf)
    I.rocking_chair(V, I.at(V, -6.0, -2.4, FOUND, -0.4))
    V.lathe("Iron", [(0.9, 0), (1.0, 0.1), (1.1, 1.0), (1.15, 1.05), (1.0, 1.05), (0.9, 0.15), (0.01, 0.12)], (9.8, -2.0, FOUND), segments=14)
    V.tube("Boards", [Vector((4.3, -0.7, FOUND + 0.4)), Vector((4.5, -0.6, FOUND + 3.4)), Vector((4.6, -0.55, FOUND + 5.6))], [0.08, 0.07, 0.07], sides=0)
    V.box("Boards", (0.9, 0.3, 1.2), (4.3, -0.75, FOUND + 0.5), rot=(0.1, 0.05, 0))
    V.pumpkin((-1.9, y0 - 0.5, FOUND - FOUND / 3), 0.6, math.radians(-12), carved=True)
    V.pumpkin((3.2, -1.0, FOUND), 0.5, math.radians(25), carved=True)
    V.pumpkin((2.0, y0 - 1.6, FOUND - 2 * FOUND / 3), 0.5, math.radians(30), rotten=True)
    D.light("PorchLight", (-2.9, -1.1, FOUND + 6.9), 16, 0.9, (255, 170, 96))
    D.light("PumpkinLight", (-1.9, y0 - 0.5, FOUND - FOUND / 3 + 0.4), 7, 0.8, (255, 130, 50), shadows=False)
    D.light("PumpkinLight", (3.2, -1.0, FOUND + 0.32), 7, 0.8, (255, 130, 50), shadows=False)
    for i in range(len(posts) - 1):
        if i == 2:
            continue  # over the steps
        D.anchor("Garland", ((posts[i] + posts[i + 1]) / 2, post_y - 0.45, roof_low - 0.95))
    D.anchor("PumpkinPile", (-4.6, y0 - 3.0, 0), 15)
    # Dead vines up two posts and the front-right corner of the house.
    for x in (posts[1], posts[5]):
        V.spiral_vine(x, post_y, FOUND, roof_low - 1.0, r=0.42, turns=2.4)
    V.creeper((MAIN["x1"] + 0.5, -0.5, FOUND), 13.0, (0.7, -0.7, 0),
              runners=[(4.0, (-0.1, 5.0, 1.2), -0.5), (8.5, (-0.1, 6.5, -1.5), 0.6), (11.0, (-3.0, 0.1, 1.0), -0.4)], radius=0.2)
    return posts, post_y


def foundation():
    V.box("Stone", (24.4, 18.4, FOUND), (0, 9, FOUND / 2), bevel=0.08)
    V.box("Stone", (16.4, 6.4, FOUND), (-4, 21, FOUND / 2), bevel=0.08)
    for s in range(1, 3):  # back steps down from the lean-to door
        top = FOUND - s * FOUND / 3
        V.box("Stone", (4.6, 1.0, top), (-4, LEAN["y1"] + (s - 0.5), top / 2), bevel=0.05)


def rooms():
    """Rooms behind every window (see interiors.py for the furniture)."""
    pi, U = math.pi, I.U
    g, c = FOUND, FOUND + STORY - 0.6
    u, uc = FOUND + STORY, FOUND + STORY + 6.1
    xi0, xi1, yb = MAIN["x0"] + T, MAIN["x1"] - T, MAIN["y1"] - T
    plan = [
        dict(id="G1", x0=xi0, x1=-2.9, y0=T, y1=10.0, floor=g, ceil=c, paper="WallpaperC"),
        dict(id="G2", x0=-2.7, x1=2.7, y0=T, y1=10.0, floor=g, ceil=c, paper="WallpaperA"),
        dict(id="G3", x0=2.9, x1=xi1, y0=T, y1=10.0, floor=g, ceil=c, paper="WallpaperB"),
        dict(id="G4", x0=xi0, x1=-2.9, y0=10.2, y1=yb, floor=g, ceil=c, paper="WallpaperA"),
        dict(id="G5", x0=-2.7, x1=xi1, y0=10.2, y1=yb, floor=g, ceil=c, paper="WallpaperC"),
        dict(id="K", x0=LEAN["x0"] + T, x1=LEAN["x1"] - T, y0=LEAN["y0"] + 0.1, y1=LEAN["y1"] - T, floor=g, ceil=LEAN["low"] - 0.6, paper="WallpaperA"),
        dict(id="U1", x0=xi0, x1=-4.2, y0=3.5, y1=14.5, floor=u, ceil=uc, paper="WallpaperB"),
        dict(id="U2", x0=-3.0, x1=3.0, y0=T, y1=8.0, floor=u, ceil=uc - 0.4, paper="WallpaperC"),
        dict(id="U3", x0=4.2, x1=xi1, y0=3.5, y1=14.5, floor=u, ceil=uc, paper="WallpaperA"),
    ]
    roles = {"G1": ("living", "y0"), "G2": ("hall", "y0"), "G3": ("living", "y0"), "G4": ("living", "x0"), "G5": ("living", "x1"),
             "K": ("kitchen", "y1"), "U1": ("living", "x0"), "U2": ("living", "y0"), "U3": ("attic", "x1")}
    for room in plan:
        lamp = I.box_room(V, room)
        role, front = roles[room["id"]]
        D.room(room, lamp, role, front)
        if room["id"] == "G2":  # the hall keeps its stairs and clock; the game furnishes the rest
            f = room["floor"]
            I.stairs(V, I.at(V, 1.4, 1.6, f), steps=10)
            I.clock(V, I.at(V, -2.6 + 0.16 * U, 8.6, f, pi / 2))
            # What the game may stand in it (seen through the door when it opens).
            D.entrance(lamp, (-1.4, 8.8, f))
            D.prop((-1.0, 4.2, f), 0, ["Runner"], 0.85)
            D.prop((-1.85, 2.4, f), 90, ["CoatRack", "UmbrellaStand"], 0.9)
            D.prop((-2.25, 5.4, f), 90, ["Console"], 0.8)
            D.prop((-2.55, 5.4, f + 5.0), 90, ["HallMirror", "Portrait"], 0.8)
            D.prop((1.0, 1.6 + 2 * 0.95, f + 0.18 * 3 * U), 15, ["Doll"], 0.3)  # on the third stair


def colliders(posts, post_y):
    E = EAVE
    D.collider((24, 18, E), (0, 9, E / 2))
    D.collider((16, 6, LEAN["low"]), (-4, 21, LEAN["low"] / 2))
    D.collider((25.2, 8, FOUND), (0, -4, FOUND / 2))
    for s in range(1, 4):
        top = FOUND - s * FOUND / 3
        D.collider((5.0, 1.05, top), (0, PORCH["y"] - (s - 0.5) * 1.05, top / 2))
    for s in range(1, 3):
        top = FOUND - s * FOUND / 3
        D.collider((4.6, 1.0, top), (-4, LEAN["y1"] + (s - 0.5), top / 2))
    D.collider((2.6, 3.8, RIDGE + 3.5), (MAIN["x0"] - 1.3, 9.0, (RIDGE + 3.5) / 2))
    # Railings (open at the steps) and the porch posts.
    for a, b in ((posts[0], posts[2]), (posts[3], posts[5])):
        D.collider((b - a, 0.5, 3.4), ((a + b) / 2, post_y, FOUND + 1.7))
    for x in (posts[0], posts[5]):
        D.collider((0.5, -PORCH["y"], 3.4), (x, PORCH["y"] / 2, FOUND + 1.7))
    for x in posts:
        D.collider((0.6, 0.6, 10), (x, post_y, FOUND + 5))


def build():
    V.reset()
    V.build_materials()
    I.materials(V)
    materials()
    foundation()
    front_hinge, back_hinge = walls()
    roofs()
    posts, post_y = porch()
    rooms()
    colliders(posts, post_y)
    # Doors: the front one opens inward on its left hinge; the back one into the kitchen.
    w, h = V.DOOR["w"], V.DOOR["h"]
    D.front_door(0.0, 0.55, FOUND)
    D.hinge("FrontDoor", "FrontDoor", (-w / 2, 0.55, FOUND + h / 2), 0, 100, False)
    D.hinge("BackDoor", "BackDoor", (-4 + w / 2, LEAN["y1"] - 0.55, FOUND + h / 2), 180, 100, True, "Back door")
    D.yard = dict(fence="Picket", pathFrom=PORCH["y"] - 3.3, tree=(9.5, -12.5, 0), graves=[(-8.0, -11.5, 0), (-10.4, -12.8, 0)])
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
        V.render("farm_" + name, night="--night" in ARGS, views=views)
    if "--export" in ARGS:
        import export_victorian

        export_victorian.export(merged, EXPORT, "Farmhouse.fbx", flat=FLAT)
