"""The lobby's party bus (Blender 4.4, headless, the houses' pipeline): a conventional school bus
left out too long. Rounded roof and caps, a long sloping hood with a chrome-ringed grille, flared
black fenders, a white roof, rubber-sealed windows in a riveted body, the crossview mirrors and the
stop arm; rust bleeding through the yellow, a pane gone, one boarded over. Inside, where your
party sits while it gathers: vinyl benches with grab rails, the driver's seat and dash, ceiling
ribs and two bare lights.

    blender -b --factory-startup --python art/scripts/lobby.py -- [--render NAME [--back|--inside|--side]] [--export]

Built at one origin on the ground under the middle of the bus, its front toward -Y and its door on
the -X side, so in Roblox (x, y, z) -> (-x, z, y) it faces -Z with the door on +X (World/Lobby
parks it that way). Markers: Mark_Origin (that origin), Mark_Door (where the door's prompt goes),
Mark_Seat1..4 (where the party sits). Exports art/export/lobby/Lobby.fbx;
tools/setup_lobby.luau files it under ReplicatedStorage.Assets.Lobby.
"""

import math
import pathlib
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import victorian as V  # noqa: E402
from victorian import box, frame_matrix, lathe  # noqa: E402

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "lobby"
rng = random.Random(13)

W = 5.0  # half width of the body
FRONT, REAR = -13.5, 19.5  # the passenger body, windshield to back
HOOD = -20.8  # the front of the hood (the bumper is ahead of it)
SKIRT, FLOOR = 1.55, 3.1
EAVE, TOP, CORNER = 10.3, 11.75, 1.45  # side wall top, roof top, the roof's corner radius
WIN = (6.25, 9.35)  # side windows, bottom and top
WINDOWS = [-8.3 + k * 3.2 for k in range(8)]  # their centres
WIN_W = 2.65
DOOR_Y = (-13.25, -10.15)
WHEELS = [(-17.0, 1.95), (11.2, 1.95)]
# Bench rows: far enough apart that a seated kid's legs (out in front: the game's characters have
# no knees) clear the back of the bench ahead. 3.05 apart left 1.6 studs; the biggest need about 2.4.
SEAT_ROWS = [-8.0 + k * 4.2 for k in range(6)]


# Shapes -------------------------------------------------------------------------------------------
def rounded_rect(w, h, r, segs=4):
    """A rectangle (centred, w x h) with rounded corners, as 2D points, counter-clockwise."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(segs + 1):
            a = math.radians(a0 + 90 * i / segs)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def solid(grp, pts, depth, matrix, name="Solid", bevel=0.0, segments=1):
    """Extrudes 2D points (in the frame's XY plane) `depth` along the frame's +Z, edges rounded."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x, y, 0)) for x, y in pts])
    if face.normal.z < 0:
        face.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=Vector((0, 0, depth)), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0:
        caps = [e for e in bm.edges if all(abs(v.co.z) < 1e-4 or abs(v.co.z - depth) < 1e-4 for v in e.verts) and abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-4]
        bmesh.ops.bevel(bm, geom=caps, offset=bevel, segments=segments, affect="EDGES", profile=0.5)
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return V.mesh_object(name, bm, grp)


def ring(grp, outer, inner, depth, matrix, name="Ring"):
    """A flat ring between two closed outlines of the same point count (a window's rubber seal)."""
    bm = bmesh.new()
    n = len(outer)
    rings = []
    for z in (0.0, depth):
        rings.append(([bm.verts.new((x, y, z)) for x, y in outer], [bm.verts.new((x, y, z)) for x, y in inner]))
    (o0, i0), (o1, i1) = rings
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((o0[k], o0[j], i0[j], i0[k]))
        bm.faces.new((o1[k], i1[k], i1[j], o1[j]))
        bm.faces.new((o0[k], o1[k], o1[j], o0[j]))
        bm.faces.new((i0[k], i0[j], i1[j], i1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return V.mesh_object(name, bm, grp)


def side_frame(side, y, z):
    """A frame on the body's side at (y, z): X along the bus (reading direction from outside),
    Y up, +Z pointing outward."""
    return Matrix(((0, 0, side, side * W), (side, 0, 0, y), (0, 1, 0, z), (0, 0, 0, 1)))


def band(half, eave, top, corner, thickness, above):
    """A strip following the roof's curve from height `above` over the top and down again, between
    the profile and `thickness` inside it (ribs, the white roof)."""
    outer = [(x, z) for x, z in body_profile(half, 0, eave, top, corner) if z >= above]
    inner = [(x * (half - thickness) / half, z - thickness) for x, z in reversed(outer)]
    return outer + inner


def body_profile(half, bottom, eave, top, corner, segs=7):
    pts = [(-half + 0.15, bottom), (half - 0.15, bottom), (half, bottom + 0.15), (half, eave)]
    for i in range(1, segs + 1):  # the roof's corner, then its slightly crowned top
        a = math.pi / 2 * i / segs
        pts.append((half - corner + math.cos(a) * corner, eave + math.sin(a) * (top - eave) * 0.85))
    pts.append((0, top))
    n = len(pts)
    for i in range(n - 2, 1, -1):
        x, z = pts[i]
        pts.append((-x, z))
    return pts


def extruded(grp, pts, y0, y1, name, cap_bevel=0.0, cap_segments=5):
    """The body's cross-section from y0 to y1, its end edges rounded."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x, y0, z)) for x, z in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=Vector((0, y1 - y0, 0)), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if cap_bevel > 0:
        ends = [e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-4 and e.verts[0].co.z > SKIRT + 0.3 and e.verts[1].co.z > SKIRT + 0.3]
        bmesh.ops.bevel(bm, geom=ends, offset=cap_bevel, segments=cap_segments, affect="EDGES", profile=0.5)
    return V.mesh_object(name, bm, grp)


def cutter_box(size, loc, rot=(0, 0, 0)):
    return box("_cutters", size, loc, rot=rot)


def window_cutter(y, z0, z1, width=WIN_W, shrink=0.0):
    z0, z1, width = z0 + shrink, z1 - shrink, width - 2 * shrink
    pts = rounded_rect(width, z1 - z0, 0.38, 4)
    m = frame_matrix((-W - 1, y, (z0 + z1) / 2), (0, math.pi / 2, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z")
    return solid("_cutters", pts, 2 * W + 2, m)


def openings(shrink=0.0):
    cs = [window_cutter(y, *WIN, shrink=shrink) for y in WINDOWS]
    cs.append(window_cutter(-11.75, 5.9, 9.6, 2.3, shrink=shrink))  # the driver's window (cuts the door side too: the door goes there)
    cs.append(cutter_box((2.6, DOOR_Y[1] - DOOR_Y[0], 8.2), (-W, sum(DOOR_Y) / 2, SKIRT + 4.05)))  # the door
    m = frame_matrix((0, FRONT - 1, 8.15), (-math.pi / 2, 0, 0))  # local +Z runs back along the bus
    cs.append(solid("_cutters", rounded_rect(8.2, 3.75, 0.5), 2.4, m))  # windshield
    for x, w in ((-3.2, 2.3), (0.0, 2.2), (3.2, 2.3)):
        m = frame_matrix((x, REAR - 1.4, 8.0), (-math.pi / 2, 0, 0))
        cs.append(solid("_cutters", rounded_rect(w, 2.5, 0.35), 2.4, m))  # rear windows (the middle: the emergency door's)
    return cs


def wheel_arches(only_front=False):
    cs = []
    for y, r in WHEELS[:1] if only_front else WHEELS:
        m = frame_matrix((-W - 1, y, r), (0, math.pi / 2, 0))
        cs.append(lathe("_cutters", [(r + 0.45, 0), (r + 0.45, 2 * W + 2)], (0, 0, 0), segments=20, matrix=m))
    return cs


# The bus --------------------------------------------------------------------------------------------
def body():
    shell = extruded("BusPaint", body_profile(W, SKIRT, EAVE, TOP, CORNER), FRONT, REAR, "Shell", cap_bevel=0.85)
    hollow = extruded("_cutters", body_profile(W - 0.22, FLOOR - 0.2, EAVE - 0.22, TOP - 0.22, CORNER - 0.2), FRONT + 0.22, REAR - 0.22, "Hollow", cap_bevel=0.63)
    V.cut(shell, [hollow] + openings() + wheel_arches())
    lining = extruded("BusInside", body_profile(W - 0.22, FLOOR, EAVE - 0.22, TOP - 0.22, CORNER - 0.2), FRONT + 0.22, REAR - 0.22, "Lining", cap_bevel=0.63)
    inner = extruded("_cutters", body_profile(W - 0.32, FLOOR - 0.6, EAVE - 0.32, TOP - 0.32, CORNER - 0.28), FRONT + 0.32, REAR - 0.32, "Inner", cap_bevel=0.53)
    V.cut(lining, [inner] + openings(shrink=0.1))
    # The white roof over the top (painted over the yellow), two roof hatches on it; inside, the
    # housings over the back wheels.
    extruded("BusRoof", band(W + 0.03, EAVE, TOP + 0.03, CORNER, 0.06, EAVE + 0.7), FRONT + 0.8, REAR - 0.8, "RoofCap")
    for side in (-1, 1):
        box("BusInside", (1.5, 5.0, 1.5), (side * (W - 0.95), WHEELS[1][0], FLOOR + 0.7), bevel=0.45)
    for y in (-3.0, 10.0):
        solid("BusRoof", rounded_rect(2.6, 2.6, 0.3), 0.22, frame_matrix((0, y, TOP + 0.02)), bevel=0.08, segments=2)
        solid("BusTrim", rounded_rect(2.2, 2.2, 0.25), 0.08, frame_matrix((0, y, TOP + 0.24)))
    # The floor, with the door's step well dropped, and the steps down to the road.
    floor = box("BusFloor", (2 * W - 0.6, REAR - FRONT - 0.7, 0.16), (0, (FRONT + REAR) / 2, FLOOR - 0.08))
    V.cut(floor, [cutter_box((2.4, DOOR_Y[1] - DOOR_Y[0] + 0.1, 1.0), (-W + 1.3, sum(DOOR_Y) / 2, FLOOR))])
    # The steps: three solid treads climbing in from the doorway to the floor, a worn white edge on each.
    mid, wide = sum(DOOR_Y) / 2, DOOR_Y[1] - DOOR_Y[0] - 0.42  # clear of the folded leaves
    for x0, top in ((-W + 0.12, SKIRT + 0.55), (-W + 0.95, SKIRT + 1.05), (-W + 1.75, FLOOR - 0.01)):
        x1 = -W + 2.5
        box("BusFloor", (x1 - x0, wide, top - (SKIRT - 0.05)), ((x0 + x1) / 2, mid, (top + SKIRT - 0.05) / 2), bevel=0.02)
        box("BusRoof", (0.14, wide, 0.04), (x0 + 0.07, mid, top + 0.01))
    for y in (DOOR_Y[0] + 0.06, DOOR_Y[1] - 0.06):  # the stairwell's walls
        box("BusTrim", (2.4, 0.1, FLOOR - SKIRT + 0.1), (-W + 1.3, y, (FLOOR + SKIRT) / 2))
    box("BusTrim", (2.3, 0.12, 2.6), (-W + 1.45, DOOR_Y[1] + 0.25, FLOOR + 1.3), bevel=0.04)  # barrier by the first seat
    # The rubber seal round the doorway.
    m = side_frame(-1, mid, SKIRT + 4.05) @ Matrix.Translation((0, 0, -0.02))
    ring("BusRubber", rounded_rect(DOOR_Y[1] - DOOR_Y[0] + 0.3, 8.35, 0.25, 3), rounded_rect(DOOR_Y[1] - DOOR_Y[0] + 0.02, 8.12, 0.12, 3), 0.07, m)
    # Underneath: the chassis rails, the fuel tank, the exhaust.
    for x in (-1.6, 1.6):
        box("BusTrim", (0.5, REAR - HOOD - 2, 0.8), (x, (HOOD + REAR) / 2, 1.3))
    box("BusTrim", (2.4, 3.2, 1.0), (3.0, 4.0, 1.15), bevel=0.3)
    V.tube("BusChrome", [Vector((-3.2, 16.0, 1.0)), Vector((-3.3, REAR - 0.2, 1.0)), Vector((-3.3, REAR + 0.5, 1.05))], [0.16] * 3, sides=2)


def hood():
    """A long hood narrowing and dipping toward a rounded nose, the grille ringed in chrome."""
    bm = bmesh.new()
    back, nose = FRONT + 0.1, HOOD
    hb, hn = 4.25, 3.75
    zb, zn, bottom = 6.4, 5.75, 2.25
    vs = [bm.verts.new(p) for p in (
        (-hb, back, bottom), (hb, back, bottom), (hn, nose, bottom), (-hn, nose, bottom),
        (-hb, back, zb), (hb, back, zb), (hn, nose, zn), (-hn, nose, zn))]
    for f in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    top_and_nose = [e for e in bm.edges if not (e.verts[0].co.z < bottom + 0.01 and e.verts[1].co.z < bottom + 0.01) and not (abs(e.verts[0].co.y - back) < 0.01 and abs(e.verts[1].co.y - back) < 0.01)]
    bmesh.ops.bevel(bm, geom=top_and_nose, offset=0.7, segments=5, affect="EDGES", profile=0.5)
    obj = V.mesh_object("Hood", bm, "BusPaint")
    V.cut(obj, wheel_arches(only_front=True))
    # Grille: chrome ring, black mesh, bars, the badge.
    face = frame_matrix((0, nose - 0.02, 4.0), (math.pi / 2, 0, 0))
    ring("BusChrome", rounded_rect(3.9, 2.9, 0.45, 5), rounded_rect(3.45, 2.45, 0.25, 5), 0.18, face)
    solid("BusTrim", rounded_rect(3.5, 2.5, 0.25, 5), 0.06, frame_matrix((0, nose - 0.03, 4.0), (math.pi / 2, 0, 0)))
    for k in range(6):
        box("BusChrome", (3.4, 0.08, 0.1), (0, nose - 0.12, 3.05 + k * 0.38))
    lathe("BusChrome", [(0.32, 0.0), (0.32, 0.06), (0.2, 0.1)], (0, 0, 0), segments=12, matrix=frame_matrix((0, nose - 0.16, 5.25), (math.pi / 2, 0, 0)))
    # Headlights: twin round lamps either side in black housings.
    for side in (-1, 1):
        box("BusTrim", (1.3, 0.5, 0.95), (side * 2.75, nose + 0.15, 4.85), bevel=0.2)
        for dx in (-0.3, 0.3):
            m = frame_matrix((side * 2.75 + dx, nose - 0.12, 4.85), (math.pi / 2, 0, 0))
            lathe("BusChrome", [(0.3, 0.0), (0.3, 0.1), (0.25, 0.14)], (0, 0, 0), segments=14, matrix=m)
            lathe("LightWhite", [(0.25, 0.06), (0.22, 0.16), (0.0, 0.2)], (0, 0, 0), segments=14, matrix=m)
        box("LightAmber", (0.5, 0.15, 0.32), (side * 2.75, nose - 0.05, 4.05))  # turn signals
    # The bumper, with bolt heads, and the step plate on it.
    box("BusTrim", (10.3, 0.8, 1.05), (0, nose - 0.45, 2.35), bevel=0.25)
    for x in (-4.2, -1.4, 1.4, 4.2):
        lathe("BusChrome", [(0.09, 0.0), (0.09, 0.05), (0.0, 0.08)], (0, 0, 0), segments=6, matrix=frame_matrix((x, nose - 0.86, 2.35), (math.pi / 2, 0, 0)))
    # Crossview mirrors on their stalks off the fenders, looking down at the road ahead.
    for side in (-1, 1):
        base = Vector((side * 4.3, nose + 1.2, 4.6))
        top = Vector((side * 4.7, nose - 0.4, 7.3))
        V.tube("BusTrim", [base, base + Vector((side * 0.3, -0.4, 1.4)), top], [0.06] * 3, sides=1)
        lathe("BusTrim", [(0.0, -0.05), (0.42, 0.0), (0.5, 0.18), (0.42, 0.32), (0.0, 0.36)], (0, 0, 0), segments=12, matrix=frame_matrix(top.to_tuple(), (math.radians(70), 0, side * 0.6)))


def fenders():
    """Black fenders arching over the front wheels, flaring out past the hood."""
    y0, r = WHEELS[0]
    for side in (-1, 1):
        outer, inner = r + 0.85, r + 0.32
        pts = [(y0 + math.cos(math.pi * i / 14) * outer, r + math.sin(math.pi * i / 14) * outer) for i in range(15)]
        pts += [(y0 + math.cos(math.pi * i / 14) * inner, r + math.sin(math.pi * i / 14) * inner) for i in range(14, -1, -1)]
        x = side * 4.05 if side > 0 else -4.05 - 1.25
        m = Matrix(((0, 0, 1, x), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # points (y, z), extruded along +x
        solid("BusTrim", pts, 1.25, m, name="Fender", bevel=0.18, segments=3)


def trim():
    # Rub rails down both sides, riveted; the panel seams below the windows.
    for side in (-1, 1):
        # The door side's rails stop either side of the door (its frame is DOOR_Y, plus the seal).
        spans = [(FRONT + 0.7, REAR - 0.7)] if side > 0 else [(FRONT + 0.7, DOOR_Y[0] - 0.3), (DOOR_Y[1] + 0.3, REAR - 0.7)]
        for z in (FLOOR + 0.25, 5.45, EAVE - 0.6):
            for a, b in spans:
                if b - a < 0.3:
                    continue
                box("BusTrim", (0.14, b - a, 0.24), (side * (W + 0.05), (a + b) / 2, z), bevel=0.06)
            for k in range(20):
                y = FRONT + 1.2 + k * (REAR - FRONT - 2.4) / 19
                if any(a + 0.1 < y < b - 0.1 for a, b in spans):
                    lathe("BusChrome", [(0.06, 0.0), (0.06, 0.03), (0.0, 0.06)], (0, 0, 0), segments=5, matrix=side_frame(side, y, z) @ Matrix.Translation((0, 0, 0.1)))
        for y in WINDOWS + [WINDOWS[-1] + 3.2]:
            box("BusSeam", (0.05, 0.06, WIN[0] - FLOOR - 0.6), (side * (W + 0.01), y - 1.6, (WIN[0] + FLOOR) / 2 + 0.1))
    # Rubber seals round the windows, and the split across each pane.
    for side in (-1, 1):
        for y in WINDOWS:
            m = side_frame(side, y, sum(WIN) / 2)
            outer = rounded_rect(WIN_W + 0.16, WIN[1] - WIN[0] + 0.16, 0.45, 4)
            inner = rounded_rect(WIN_W - 0.08, WIN[1] - WIN[0] - 0.08, 0.32, 4)
            ring("BusRubber", outer, inner, 0.06, m @ Matrix.Translation((0, 0, -0.02)))
            box("BusChrome", (0.12, WIN_W - 0.1, 0.1), (side * (W - 0.08), y, sum(WIN) / 2 + 0.25))
    for side in (1,):
        m = side_frame(side, -11.75, 7.75)
        ring("BusRubber", rounded_rect(2.46, 3.86, 0.45, 4), rounded_rect(2.22, 3.62, 0.32, 4), 0.06, m @ Matrix.Translation((0, 0, -0.02)))
    # Windshield seal and centre post; the dash inside.
    face = frame_matrix((0, FRONT - 0.02, 8.15), (math.pi / 2, 0, 0))
    ring("BusRubber", rounded_rect(8.4, 3.95, 0.55, 5), rounded_rect(8.12, 3.67, 0.42, 5), 0.06, face)
    box("BusTrim", (0.28, 0.3, 3.7), (0, FRONT, 8.15))
    box("BusTrim", (2 * W - 0.7, 1.4, 2.4), (0, FRONT + 0.95, FLOOR + 1.2), bevel=0.25)
    for x in (2.4, 3.0, 3.6):  # the gauges, faintly lit
        lathe("BusGauge", [(0.22, 0.0), (0.22, 0.02)], (0, 0, 0), segments=12, matrix=frame_matrix((x, FRONT + 1.62, FLOOR + 2.15), (math.radians(-110), 0, 0)))
    # The back: the black band, the emergency door's outline and handle, the plate.
    box("BusTrim", (2 * W - 0.2, 0.3, 0.55), (0, REAR + 0.02, 5.45))
    m = frame_matrix((0, REAR + 0.03, 6.0), (-math.pi / 2, 0, 0))
    ring("BusRubber", rounded_rect(3.1, 7.6, 0.3, 3), rounded_rect(2.86, 7.36, 0.2, 3), 0.06, m)
    box("BusChrome", (0.9, 0.2, 0.18), (0.95, REAR + 0.12, 5.2), bevel=0.05)
    box("BusRoof", (1.6, 0.08, 0.8), (-3.2, REAR + 0.05, 3.2))  # licence plate
    box("BusTrim", (10.3, 0.8, 1.05), (0, REAR + 0.4, 2.35), bevel=0.25)
    # Side mirrors at the windshield's corners, on bent chrome arms.
    for side in (-1, 1):
        arm = [Vector((side * W, FRONT + 0.5, 9.3)), Vector((side * (W + 1.0), FRONT - 0.4, 9.7)), Vector((side * (W + 1.15), FRONT - 0.9, 7.8))]
        V.tube("BusChrome", arm, [0.07] * 3, sides=1)
        solid("BusTrim", rounded_rect(0.9, 1.7, 0.2), 0.3, frame_matrix((side * (W + 1.2), FRONT - 1.0, 7.4), (math.pi / 2, 0, side * 0.25)), bevel=0.06, segments=2)


def wheels():
    """Each wheel: a tyre with a bulging sidewall and staggered tread, an off-white steel disc wheel
    (rim flange, a dish with hand holes cut through it, a raised hub, ten lug nuts, a cap), the
    brake drum dark behind the holes. Twin wheels at the back, mud flaps behind them."""
    for y, r in WHEELS:
        duals = y > 0
        for side in (-1, 1):
            # Local +Z of `out` points away from the bus on this side (the wheel's face).
            out = frame_matrix((side * (W - 0.72), y, r), (0, side * math.pi / 2, 0))
            tire(out, r)
            steel_wheel(out, r, dish=0.3 if duals else 0.0)
            if duals:
                arch_liner(side, y, r)
            drum = 0.15 - (0.32 if duals else 0.0)  # its face just behind the wheel's dish
            lathe("BusTrim", [(r * 0.5, drum - 0.45), (r * 0.5, drum), (0.0, drum)], (0, 0, 0), segments=20, matrix=out)  # brake drum
            if duals:
                inner = out @ Matrix.Translation((0, 0, -1.32))
                tire(inner, r)
                lathe("BusRim", [(r * 0.6, -0.5), (r * 0.6, 0.5)], (0, 0, 0), segments=20, matrix=inner)
                box("BusRubber", (1.5, 0.08, 1.7), (side * (W - 1.35), y + r + 0.35, r * 0.62), rot=(0.06, 0, 0))  # mud flap
                box("BusTrim", (1.6, 0.25, 0.16), (side * (W - 1.35), y + r + 0.35, r * 1.07))


def tire(m, r):
    """A tyre: rounded shoulders and a bulging sidewall, two grooves round the tread and staggered
    lugs along each shoulder. Built round local Z (the axle), centred on the origin of `m`."""
    segs = 48
    # (radius factor, z, kind) across the tyre from the inner bead to the outer one.
    prof = [
        (0.6, -0.56, "bead"), (0.68, -0.63, "wall"), (0.8, -0.67, "wall"), (0.9, -0.64, "wall"), (0.965, -0.56, "wall"),
        (1.0, -0.45, "lugL"), (1.0, -0.22, "lugL"), (0.97, -0.2, "groove"), (0.97, -0.15, "groove"), (1.0, -0.13, "rib"),
        (1.0, 0.13, "rib"), (0.97, 0.15, "groove"), (0.97, 0.2, "groove"), (1.0, 0.22, "lugR"), (1.0, 0.45, "lugR"),
        (0.965, 0.56, "wall"), (0.9, 0.64, "wall"), (0.8, 0.67, "wall"), (0.68, 0.63, "wall"), (0.6, 0.56, "bead"),
    ]
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ring = []
        for f, z, kind in prof:
            rad = f * r
            if kind == "lugL" and i % 4 in (0, 1):
                rad -= 0.07
            elif kind == "lugR" and i % 4 in (2, 3):
                rad -= 0.07
            ring.append(bm.verts.new((math.cos(a) * rad, math.sin(a) * rad, z)))
        rings.append(ring)
    n = len(prof)
    for i in range(segs):
        cur, nxt = rings[i], rings[(i + 1) % segs]
        for k in range(n):
            j = (k + 1) % n
            bm.faces.new((cur[k], nxt[k], nxt[j], cur[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    V.mesh_object("Tire", bm, "BusTire")


def arch_liner(side, y, r):
    """The black liner inside a wheel arch, over the top of the wheel (hides the inside of the body)."""
    bm = bmesh.new()
    radius, steps = r + 0.4, 16
    x0, x1 = side * (W + 0.05), side * (W - 2.1)
    rows = []
    for i in range(steps + 1):
        a = math.pi * i / steps
        rows.append([bm.verts.new((x, y + math.cos(a) * radius, r + math.sin(a) * radius)) for x in (x0, x1)])
    for i in range(steps):
        face = bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
        face.normal_update()
        centre = Vector((face.calc_center_median().x, y, r))
        if face.normal.dot(centre - face.calc_center_median()) < 0:  # facing the wheel (one-sided in Roblox)
            face.normal_flip()
    V.mesh_object("Liner", bm, "BusRubber")


def steel_wheel(m, r, dish=0.0):
    """The disc wheel's outer face (local +Z outward), `dish` deeper for the back wheels."""
    prof = [
        (0.6 * r, 0.28 - dish), (0.6 * r, 0.36), (0.63 * r, 0.52), (0.6 * r, 0.6), (0.56 * r, 0.57),  # the rim's barrel, flange and lip
        (0.55 * r, 0.32 - dish), (0.42 * r, 0.36 - dish), (0.32 * r, 0.42 - dish),  # the dish
        (0.28 * r, 0.5 - dish), (0.2 * r, 0.52 - dish), (0.16 * r, 0.6 - dish), (0.01, 0.62 - dish),  # the hub
    ]
    wheel = lathe("BusRim", [(rr, z) for rr, z in prof], (0, 0, 0), segments=32, matrix=m)
    holes = []
    for k in range(8):  # hand holes through the dish
        a = 2 * math.pi * (k + 0.5) / 8
        c = Vector((math.cos(a), math.sin(a), 0)) * 0.43 * r
        hole = lathe("_cutters", [(0.11 * r, -0.5), (0.11 * r, 1.2)], (0, 0, 0), segments=10,
                     matrix=m @ Matrix.Translation(c) @ Matrix.Rotation(a + math.pi / 2, 4, "Z") @ Matrix.Scale(1.45, 4, Vector((1, 0, 0))))
        holes.append(hole)
    V.cut(wheel, holes)
    for k in range(10):  # lug nuts on the hub
        a = 2 * math.pi * k / 10
        lathe("BusChrome", [(0.075, 0.0), (0.075, 0.1), (0.05, 0.13)], (math.cos(a) * 0.24 * r, math.sin(a) * 0.24 * r, 0.5 - dish), segments=6, matrix=m)
    lathe("BusChrome", [(0.15 * r, 0.6 - dish), (0.15 * r, 0.68 - dish), (0.1 * r, 0.76 - dish), (0.0, 0.79 - dish)], (0, 0, 0), segments=16, matrix=m)


def lights():
    # The eight-way warning lights on the front and back caps, in black hoods; tail lights.
    for side in (-1, 1):
        for y, out, grp in ((FRONT - 0.15, -1, "LightAmber"), (REAR + 0.15, 1, "LightRed")):
            for dx, g in ((3.4, grp), (2.55, "LightRed" if grp == "LightAmber" else "LightAmber")):
                m = frame_matrix((side * dx, y, 10.85), (-out * math.pi / 2, 0, 0))
                lathe("BusTrim", [(0.42, 0.0), (0.42, 0.25)], (0, 0, 0), segments=14, matrix=m)
                lathe(g, [(0.34, 0.2), (0.3, 0.3), (0.0, 0.33)], (0, 0, 0), segments=14, matrix=m)
        for dz in (3.5, 4.2):
            m = frame_matrix((side * 4.0, REAR + 0.15, dz), (-math.pi / 2, 0, 0))
            lathe("LightRed", [(0.28, 0.0), (0.28, 0.12), (0.0, 0.16)], (0, 0, 0), segments=12, matrix=m)
        if side > 0:  # (the door side's front marker would sit in the doorway)
            box("LightAmber", (0.12, 0.5, 0.25), (side * (W + 0.06), FRONT + 0.8, 3.0))  # side markers
        box("LightAmber", (0.12, 0.5, 0.25), (side * (W + 0.06), REAR - 0.8, 3.0))
    for y in (-6.5, 2.0, 10.5):  # the bare lights down the ceiling
        solid("BusTrim", rounded_rect(1.0, 2.2, 0.2), 0.12, frame_matrix((0, y, TOP - 0.42)))
        solid("LightWhite", rounded_rect(0.8, 2.0, 0.15), 0.06, frame_matrix((0, y, TOP - 0.48)))
    for y in [FRONT + 1.6 + k * 3.05 for k in range(11)]:  # ribs following the ceiling down to the windows
        extruded("BusRib", band(W - 0.32, EAVE - 0.32, TOP - 0.32, CORNER - 0.28, 0.08, WIN[1] + 0.3), y - 0.11, y + 0.11, "Rib")


def glass():
    broken = {(1, 3), (-1, 5)}
    boarded = {(1, 6)}
    for side in (-1, 1):
        for k, y in enumerate(WINDOWS):
            m = side_frame(side, y, sum(WIN) / 2) @ Matrix.Translation((0, 0, -0.1))
            if (side, k) in boarded:
                for j in range(3):
                    box("BusBoards", (0.12, WIN_W + 0.7, 0.72), (side * (W + 0.1), y + rng.uniform(-0.2, 0.2), WIN[0] + 0.45 + j * 0.98), rot=(rng.uniform(-0.15, 0.15), 0, 0), bevel=0.04)
                    for dy in (-WIN_W / 2 - 0.15, WIN_W / 2 + 0.15):
                        lathe("BusChrome", [(0.05, 0.0), (0.05, 0.04)], (0, 0, 0), segments=5, matrix=side_frame(side, y + dy, WIN[0] + 0.45 + j * 0.98) @ Matrix.Translation((0, 0, 0.17)))
                continue
            h = WIN[1] - WIN[0]
            if (side, k) in broken:  # the lower pane gone but for a jagged shard in the corner
                solid("BusGlass", [(x, yy) for x, yy in rounded_rect(WIN_W, h, 0.35) if yy > 0.2] + [(-WIN_W / 2, 0.2), (WIN_W / 2, 0.2)], 0.04, m)
                solid("BusGlass", [(-WIN_W / 2, -h / 2 + 0.05), (-WIN_W / 2 + 0.9, -h / 2 + 0.05), (-WIN_W / 2 + 0.25, -h / 2 + 0.75), (-WIN_W / 2 + 0.1, -0.2)], 0.04, m)
                continue
            solid("BusGlass", rounded_rect(WIN_W, h, 0.35), 0.04, m)
    solid("BusGlass", rounded_rect(2.3, 3.7, 0.35), 0.04, side_frame(1, -11.75, 7.75) @ Matrix.Translation((0, 0, -0.1)))
    for x in (-2.05, 2.05):
        solid("BusGlass", rounded_rect(3.95, 3.7, 0.4), 0.04, frame_matrix((x, FRONT + 0.1, 8.15), (math.pi / 2, 0, 0)))
    for x, w in ((-3.2, 2.3), (0.0, 2.2), (3.2, 2.3)):
        solid("BusGlass", rounded_rect(w, 2.5, 0.35), 0.04, frame_matrix((x, REAR - 0.1, 8.0), (-math.pi / 2, 0, 0)))


def door():
    """The folding door: two tall glass leaves in chrome frames, folded open against the frame."""
    y0, y1 = DOOR_Y
    width = (y1 - y0) / 2
    for k in range(2):
        hinge = Vector((-W + 0.12, y0 + 0.08 + k * (2 * width - 0.16), SKIRT + 0.25))
        sgn = 1 if k == 0 else -1
        m = frame_matrix(hinge.to_tuple(), (0, 0, sgn * -1.5))
        for z in (0.08, 3.8, 7.55):
            box("BusChrome", (0.12, width, 0.16), (0, sgn * width / 2, z), matrix=m, bevel=0.03)
        for dy in (0.05, width - 0.05):
            box("BusChrome", (0.12, 0.1, 7.6), (0, sgn * dy, 3.8), matrix=m, bevel=0.03)
        box("BusGlass", (0.04, width - 0.1, 7.4), (0, sgn * width / 2, 3.8), matrix=m)
    V.tube("BusChrome", [Vector((-W + 0.5, y1 + 0.2, FLOOR - 0.6)), Vector((-W + 0.5, y1 + 0.2, FLOOR + 3.4)), Vector((-W + 1.6, y1 + 0.2, FLOOR + 4.3))], [0.07] * 3, sides=1)


def seats():
    """Vinyl benches down both sides, a grab rail on each, the driver's seat and wheel."""
    for y in SEAT_ROWS:
        for side in (-1, 1):
            x = side * 2.85
            solid("BusSeat", rounded_rect(3.4, 1.65, 0.3), 0.5, frame_matrix((x, y, FLOOR + 1.25)), bevel=0.14, segments=3)
            back = frame_matrix((x, y + 1.3, FLOOR + 1.6), (math.radians(80), 0, 0))  # local Y up, leaning back
            # Low enough that a kid sitting behind sees over it (down the aisle, out the windshield).
            solid("BusSeat", rounded_rect(3.4, 1.7, 0.45), 0.5, back @ Matrix.Translation((0, 0.85, 0)), bevel=0.14, segments=3)
            V.tube("BusChrome", [Vector((x - 1.5, y + 1.15, FLOOR + 3.35)), Vector((x, y + 1.1, FLOOR + 3.45)), Vector((x + 1.5, y + 1.15, FLOOR + 3.35))], [0.06] * 3, sides=1)
            aisle = x - side * 1.55
            box("BusTrim", (0.12, 0.12, 1.25), (aisle, y - 0.45, FLOOR + 0.62))
            box("BusTrim", (0.12, 1.4, 0.12), (aisle, y - 0.1, FLOOR + 0.1))
    solid("BusSeat", rounded_rect(2.0, 1.9, 0.4), 0.55, frame_matrix((2.9, -11.4, FLOOR + 1.3)), bevel=0.16, segments=3)
    back = frame_matrix((2.9, -9.95, FLOOR + 1.7), (math.radians(78), 0, 0))
    solid("BusSeat", rounded_rect(2.0, 2.7, 0.5), 0.55, back @ Matrix.Translation((0, 1.35, 0)), bevel=0.16, segments=3)
    box("BusTrim", (0.3, 0.3, 1.3), (2.9, -11.4, FLOOR + 0.65))
    m = frame_matrix((2.9, -12.75, FLOOR + 3.3), (math.radians(-40), 0, 0))
    V.torus("BusTrim", (0, 0, 0), 0.75, 0.09, m, segments=18, sides=6)
    box("BusTrim", (0.16, 0.16, 1.5), (2.9, -12.95, FLOOR + 2.55), rot=(math.radians(-40), 0, 0))
    # A backpack someone left on the back seat.
    solid("BusBag", rounded_rect(1.0, 0.6, 0.25), 1.1, frame_matrix((2.2, SEAT_ROWS[-1] - 0.1, FLOOR + 1.75), (0.15, 0, 0.3)), bevel=0.2, segments=2)


def text(grp, body, size, matrix, extrude=0.03, align="CENTER"):
    cu = bpy.data.curves.new("Text", "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.resolution_u = 2
    obj = bpy.data.objects.new("Text", cu)
    bpy.context.scene.collection.objects.link(obj)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    bpy.data.objects.remove(obj, do_unlink=True)
    mobj = bpy.data.objects.new("Text", me)
    mobj.matrix_world = matrix
    V.group(grp).objects.link(mobj)
    return mobj


def lettering():
    # SCHOOL BUS on boards over the windshield and the back window; the district down the sides.
    for y, out in ((FRONT - 0.2, -1), (REAR + 0.2, 1)):
        solid("BusPaint", rounded_rect(4.1, 0.95, 0.18), 0.2, frame_matrix((0, y, 10.85), (out * math.pi / 2, 0, 0)), bevel=0.05, segments=2)
        rot = (math.pi / 2, 0, 0) if out < 0 else (math.pi / 2, 0, math.pi)
        text("BusText", "SCHOOL BUS", 0.66, frame_matrix((0, y + out * 0.03, 10.62), rot))
    for side in (-1, 1):
        rot = (math.pi / 2, 0, math.pi / 2 if side > 0 else -math.pi / 2)
        text("BusText", "HOLLOW PINES SCHOOL DIST.", 0.6, frame_matrix((side * (W + 0.04), 3.0, 4.42), rot))
        text("BusText", "13", 0.85, frame_matrix((side * (W + 0.04), -11.6 if side > 0 else 17.6, 4.3), rot))
    text("BusText", "EMERGENCY DOOR", 0.32, frame_matrix((0, REAR + 0.06, 9.95), (math.pi / 2, 0, math.pi)))
    text("BusText", "13", 0.55, frame_matrix((2.9, HOOD - 0.92, 2.15), (math.pi / 2, 0, 0)))
    # The stop arm folded against the driver's side.
    def octagon(grp, radius, x, thick):
        pts = [(math.cos(math.pi / 8 + i * math.pi / 4) * radius, math.sin(math.pi / 8 + i * math.pi / 4) * radius) for i in range(8)]
        solid(grp, pts, thick, side_frame(1, -9.9, 4.95) @ Matrix.Translation((0, 0, x)))
    octagon("BusWhite", 0.95, 0.16, 0.05)
    octagon("BusRed", 0.86, 0.21, 0.05)
    text("BusWhite", "STOP", 0.42, side_frame(1, -9.9, 4.8) @ Matrix.Translation((0, 0, 0.27)), extrude=0.015)
    box("BusTrim", (0.3, 0.5, 0.6), (W + 0.12, -10.95, 4.95), bevel=0.05)


LAMP_AT = (40.0, 0.0)  # where the lamp is built, away from the bus (its own origin marker)


def lamp():
    """A cast-iron street lamp: a stepped foot, a slim ringed post, the ladder bar, and a tapering
    four-paned lantern under a pointed cap, glowing like the houses' porch lanterns."""
    x, y = LAMP_AT
    m = frame_matrix((x, y, 0))
    lathe("LampIron", [(1.0, 0.0), (1.0, 0.3), (0.82, 0.38), (0.78, 0.95), (0.55, 1.25), (0.42, 1.7), (0.34, 2.3)], (0, 0, 0), segments=8, matrix=m)
    lathe("LampIron", [(0.34, 2.3), (0.27, 2.55), (0.21, 9.3), (0.28, 9.45), (0.28, 9.65), (0.2, 9.8), (0.17, 12.0), (0.26, 12.15), (0.36, 12.45), (0.36, 12.6)], (0, 0, 0), segments=12, matrix=m)
    box("LampIron", (2.2, 0.12, 0.12), (x, y, 11.2), bevel=0.03)
    for s in (-1, 1):
        lathe("LampIron", [(0.0, -0.12), (0.11, -0.05), (0.11, 0.05), (0.0, 0.12)], (x + s * 1.1, y, 11.2), segments=8)
    box("LampIron", (1.25, 1.25, 0.16), (x, y, 12.68), bevel=0.04)
    bottom, top, z0, z1 = 0.5, 0.68, 12.76, 14.55
    for k in range(4):  # the panes and the corner bars between them
        a = k * math.pi / 2
        c, sn = math.cos(a), math.sin(a)
        d, t = Vector((c, sn, 0)), Vector((-sn, c, 0))
        base = Vector((x, y, 0))
        corners = [base + d * bottom - t * bottom + Vector((0, 0, z0)), base + d * bottom + t * bottom + Vector((0, 0, z0)),
                   base + d * top + t * top + Vector((0, 0, z1)), base + d * top - t * top + Vector((0, 0, z1))]
        bm = bmesh.new()
        outer = [bm.verts.new(v) for v in corners]
        inner = [bm.verts.new(v - d * 0.04) for v in corners]
        bm.faces.new(outer)
        bm.faces.new(list(reversed(inner)))
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((outer[i], inner[i], inner[j], outer[j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        V.mesh_object("Pane", bm, "LampGlow")
        cx, cy = math.cos(a + math.pi / 4) * math.sqrt(2), math.sin(a + math.pi / 4) * math.sqrt(2)
        V.tube("LampIron", [Vector((x + cx * bottom, y + cy * bottom, z0)), Vector((x + cx * top, y + cy * top, z1))], [0.05, 0.05], sides=1)
    lathe("LampIron", [(0.98, z1), (0.98, z1 + 0.14), (0.86, z1 + 0.2), (0.0, z1 + 1.0)], (0, 0, 0), segments=4, matrix=m @ Matrix.Rotation(math.pi / 4, 4, "Z"))
    lathe("LampIron", [(0.0, z1 + 0.95), (0.12, z1 + 1.05), (0.06, z1 + 1.2), (0.1, z1 + 1.3), (0.0, z1 + 1.5)], (0, 0, 0), segments=8, matrix=m)
    lathe("LampIron", [(0.42, z0 - 0.1), (0.3, z0 - 0.3), (0.0, z0 - 0.38)], (0, 0, 0), segments=8, matrix=m)
    box("Mark_LampOrigin", (0.1, 0.1, 0.1), (x, y, 0.05))
    box("Mark_LampLight", (0.1, 0.1, 0.1), (x, y, (z0 + z1) / 2))


def markers():
    box("Mark_Origin", (0.1, 0.1, 0.1), (0, 0, 0.05))
    box("Mark_Door", (0.2, DOOR_Y[1] - DOOR_Y[0], 7.4), (-W - 0.2, sum(DOOR_Y) / 2, SKIRT + 3.7))
    # The party sits a few rows back, looking up the aisle (the front row only sees the dash).
    for k, (x, y) in enumerate(((-2.85, SEAT_ROWS[2]), (2.85, SEAT_ROWS[2]), (-2.85, SEAT_ROWS[3]), (2.85, SEAT_ROWS[3]))):
        box(f"Mark_Seat{k + 1}", (1.0, 1.0, 0.1), (x, y, FLOOR + 1.8))


# Materials ------------------------------------------------------------------------------------------
def rusted(mat, amount, scale=0.16):
    """Rust eating through the paint in patches (rust_coarse_01), worse low down where the road
    splashes it."""
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    base = bsdf.inputs["Base Color"].links[0].from_socket
    rust = V.image(nodes, V.TEX / "rust_coarse_01" / "rust_coarse_01_diff_1k.jpg")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "Tile"
    links.new(uv.outputs["UV"], rust.inputs["Vector"])
    geo = nodes.new("ShaderNodeNewGeometry")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 12
    noise.inputs["Roughness"].default_value = 0.72
    links.new(geo.outputs["Position"], noise.inputs["Vector"])
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Position"], sep.inputs["Vector"])
    low = nodes.new("ShaderNodeMapRange")
    low.inputs["From Min"].default_value = 1.6
    low.inputs["From Max"].default_value = 5.0
    low.inputs["To Min"].default_value = 0.14
    low.inputs["To Max"].default_value = 0.0
    links.new(sep.outputs["Z"], low.inputs["Value"])
    add = nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    links.new(noise.outputs["Fac"], add.inputs[0])
    links.new(low.outputs["Result"], add.inputs[1])
    mask = nodes.new("ShaderNodeMapRange")
    mask.inputs["From Min"].default_value = 0.62
    mask.inputs["From Max"].default_value = 0.7
    mask.inputs["To Max"].default_value = amount
    links.new(add.outputs["Value"], mask.inputs["Value"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(mask.outputs["Result"], mix.inputs[0])
    links.new(base, mix.inputs[6])
    links.new(rust.outputs["Color"], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    rough = nodes.new("ShaderNodeMath")
    rough.operation = "MAXIMUM"
    links.new(mask.outputs["Result"], rough.inputs[0])
    old = bsdf.inputs["Roughness"].links[0].from_socket if bsdf.inputs["Roughness"].links else None
    if old is not None:
        links.new(old, rough.inputs[1])
        links.new(rough.outputs["Value"], bsdf.inputs["Roughness"])


def build():
    V.reset()
    V.build_materials()
    M, U = V.MATERIALS, V.UV_RULES
    paint = V.textured("BusPaint", "concrete_wall_006", paint=(0.74, 0.52, 0.12, 1), rough=0.62, dirt=0.6, moss=0.2, bump=0.45)
    rusted(paint, 0.9)
    M["BusPaint"], U["BusPaint"] = paint, (9.0, "vertical")
    M["BusRoof"] = V.textured("BusRoof", "concrete_wall_006", paint=(0.62, 0.6, 0.54, 1), rough=0.7, dirt=0.9, moss=0.55, bump=0.6)
    rusted(M["BusRoof"], 0.5)
    U["BusRoof"] = (8.0, "vertical")
    M["BusInside"] = V.textured("BusInside", "concrete_wall_006", paint=(0.62, 0.6, 0.52, 1), rough=0.6, dirt=0.5, bump=0.12)
    U["BusInside"] = (14.0, "vertical")
    M["BusRib"] = V.textured("BusRib", None, tint=(0.3, 0.29, 0.25, 1), rough=0.7)
    M["BusTrim"] = V.textured("BusTrim", "concrete_wall_006", paint=(0.06, 0.06, 0.06, 1), rough=0.55, dirt=0.4, bump=0.35)
    U["BusTrim"] = (4.0, "long")
    M["BusSeam"] = M["BusTrim"]
    M["BusRubber"] = V.textured("BusRubber", None, tint=(0.015, 0.015, 0.015, 1), rough=0.85)
    M["BusChrome"] = V.textured("BusChrome", "concrete_wall_006", paint=(0.78, 0.78, 0.8, 1), rough=0.32, dirt=0.45, metal=1.0)
    U["BusChrome"] = (2.0, "long")
    M["BusRim"] = V.textured("BusRim", "concrete_wall_006", paint=(0.6, 0.58, 0.52, 1), rough=0.55, dirt=0.85, bump=0.5)
    rusted(M["BusRim"], 0.45, scale=0.6)
    M["BusTire"] = V.textured("BusTire", None, tint=(0.012, 0.012, 0.012, 1), rough=0.95)
    M["BusSeat"] = V.textured("BusSeat", "brown_leather", tint=(0.3, 0.36, 0.27, 1), rough=0.55, dirt=0.8)
    U["BusSeat"] = (1.6, "vertical")
    M["BusBag"] = V.textured("BusBag", "denim_fabric_04", tint=(0.6, 0.25, 0.25, 1), rough=0.9, dirt=0.5)
    M["BusFloor"] = V.textured("BusFloor", "dark_wooden_planks", tint=(0.3, 0.29, 0.27, 1), rough=0.9, dirt=0.85)
    U["BusFloor"] = (5.0, "long")
    M["BusBoards"] = M["Boards"]
    U["BusBoards"] = U["Boards"]
    M["BusGlass"] = M["Glass"]
    M["BusRed"] = V.textured("BusRed", "rusty_painted_metal", paint=(0.75, 0.05, 0.03, 1), rough=0.55, dirt=0.4)
    M["BusWhite"] = V.textured("BusWhite", None, tint=(0.82, 0.8, 0.74, 1), rough=0.7)
    M["BusText"] = V.textured("BusText", None, tint=(0.04, 0.035, 0.03, 1), rough=0.8)
    M["LampIron"] = M["Iron"]
    M["LampGlow"] = M["LanternGlow"]
    M["BusGauge"] = V.textured("BusGauge", None, tint=(0.05, 0.08, 0.05, 1), emission=((0.4, 1.0, 0.5, 1), 0.15))
    M["LightWhite"] = V.textured("LightWhite", None, tint=(0.4, 0.38, 0.3, 1), emission=((1.0, 0.86, 0.6, 1), 4.0))
    M["LightAmber"] = V.textured("LightAmber", None, tint=(0.4, 0.2, 0.02, 1), emission=((1.0, 0.5, 0.05, 1), 2.5))
    M["LightRed"] = V.textured("LightRed", None, tint=(0.3, 0.02, 0.02, 1), emission=((1.0, 0.05, 0.03, 1), 2.5))
    for name in list(M):
        U.setdefault(name, (4.0, "vertical"))
    body()
    hood()
    fenders()
    trim()
    wheels()
    lights()
    glass()
    door()
    seats()
    lettering()
    lamp()
    markers()
    for obj in list(V.GROUPS.get("_cutters", bpy.data.collections.new("_none")).objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    merged = {}
    for name in list(V.GROUPS):
        if name.startswith("_"):
            continue
        obj = V.merge_group(name)
        if obj:
            obj.name = obj.data.name = name
            merged[name] = obj
    # Smooth where it's round (the rounded body, the wheels, the seats), crisp at hard edges.
    for name in ("BusPaint", "BusRoof", "BusInside", "BusTrim", "BusTire", "BusRim", "BusChrome", "BusSeat", "BusBag", "BusRubber"):
        if name in merged:
            obj = merged[name]
            for o in bpy.context.scene.objects:
                o.select_set(False)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    print("TRIANGLES", {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()})
    return merged


FLAT = {"BusGlass", "BusTire", "BusWhite", "BusText", "BusRubber", "BusGauge", "BusRib", "LightWhite", "LightAmber", "LightRed"} | {
    f"Mark_{n}" for n in ("Origin", "Door", "Seat1", "Seat2", "Seat3", "Seat4", "LampOrigin", "LampLight")
} | {"LampIron", "LampGlow"}


def render(name):
    day = "--day" in ARGS
    cam, _ = V.setup_render("bus", night=not day)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    for o in [o for o in bpy.data.objects if o.type == "LIGHT" and o.name in ("Lantern", "Inside", "Moon")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for obj in bpy.data.objects:
        if obj.name.startswith("Mark_"):
            obj.hide_render = True
    scene.camera = cam

    def light(lname, kind, loc, energy, color, rot=None, size=0.3, spot=None):
        obj = bpy.data.objects.new(lname, bpy.data.lights.new(lname, kind))
        obj.data.energy = energy
        obj.data.color = color
        obj.data.shadow_soft_size = size
        if spot:
            obj.data.spot_size = spot
        obj.location = loc
        if rot:
            obj.rotation_euler = rot
        scene.collection.objects.link(obj)

    if not day:
        moon = bpy.data.objects.new("Moon", bpy.data.lights.new("Moon", "SUN"))
        moon.data.energy = 2.2
        moon.data.color = (0.55, 0.65, 1.0)
        moon.rotation_euler = (math.radians(50), 0, math.radians(-140))
        scene.collection.objects.link(moon)
        light("StreetLamp", "POINT", (-16, -10, 16), 16000, (1.0, 0.7, 0.42), size=0.8)
        light("Rim", "POINT", (14, 26, 12), 5000, (0.45, 0.55, 1.0), size=2.0)
        light("Fill", "AREA", (-30, -30, 14), 9000, (0.75, 0.8, 1.0), rot=(math.radians(70), 0, math.radians(-45)), size=12)
    light("InsideA", "POINT", (0, -6.5, TOP - 0.8), 160, (1.0, 0.78, 0.5))
    light("InsideB", "POINT", (0, 2.0, TOP - 0.8), 160, (1.0, 0.78, 0.5))
    light("InsideC", "POINT", (0, 10.5, TOP - 0.8), 120, (1.0, 0.78, 0.5))
    for x in (-3.05, 3.05):
        light("Beam", "SPOT", (x, HOOD - 0.4, 4.85), 1800, (1.0, 0.88, 0.65), rot=(math.radians(-80), 0, 0), spot=math.radians(50))
    if "--inside" in ARGS:
        cam.location = (-2.85, SEAT_ROWS[2] + 0.1, 6.7)  # a seated kid's eyes in a party seat
        target = Vector((0.8, FRONT, 6.2))
        cam.data.lens = 18
        for lname in ("InsideA", "InsideB", "InsideC"):
            bpy.data.objects[lname].data.energy *= 2.5
    elif "--back" in ARGS:
        cam.location = (24, 46, 7)
        target = Vector((0, 5, 5.5))
        cam.data.lens = 30
    elif "--door" in ARGS:
        cam.location = (-15.0, -11.4, 5.2)
        target = Vector((-5.0, -11.7, 4.6))
        cam.data.lens = 32
    elif "--wheel" in ARGS:
        cam.location = (-13.5, -24.5, 3.2)
        target = Vector((-4.6, -15.5, 2.0))
        cam.data.lens = 40
    elif "--rear-wheel" in ARGS:
        cam.location = (-13.0, 4.0, 3.0)
        target = Vector((-4.6, 11.6, 1.9))
        cam.data.lens = 40
    elif "--lamp" in ARGS:
        cam.location = (LAMP_AT[0] - 9, LAMP_AT[1] - 16, 8)
        target = Vector((LAMP_AT[0], LAMP_AT[1], 8))
        cam.data.lens = 35
    elif "--side" in ARGS:
        cam.location = (-38, -4, 6)
        target = Vector((0, -1, 5.5))
        cam.data.lens = 26
    else:
        cam.location = (-24, -38, 6.5)
        target = Vector((0, -5, 5.5))
        cam.data.lens = 28
    cam.rotation_euler = (target - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(V.RENDERS / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    merged = build()
    if "--render" in ARGS:
        render(ARGS[ARGS.index("--render") + 1])
    if "--export" in ARGS:
        import export_victorian

        export_victorian.export(merged, EXPORT, "Lobby.fbx", flat=FLAT)
