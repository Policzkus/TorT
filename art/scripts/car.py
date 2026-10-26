"""The car that drives down the streets now and then (Blender 4.4, headless, the houses' pipeline):
a 1950s pontoon sedan left out for decades. Faded black-cherry paint with rust eating through it,
a toothy chrome grille, round headlights, wrap-around bumpers, a hood ornament, whitewall tyres
under fat round fenders, a dark greenhouse with nobody at the wheel.

    blender -b --factory-startup --python art/scripts/car.py -- [--render NAME [--side|--back|--day]] [--export]

Built at one origin on the ground under the middle of the car, its front toward -Y, so in Roblox
(x, y, z) -> (-x, z, y) it faces -Z. Each wheel is its own meshes (CarTire/CarWall/CarHub + FL, FR,
RL, RR) so the game can spin it. Markers: Mark_Origin, Mark_HeadL/R (where the headlights shine
from), Mark_TailL/R. Exports art/export/car/Car.fbx; tools/setup_car.luau files it under
ReplicatedStorage.Assets.Vehicles.Car.
"""

import math
import pathlib
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import victorian as V  # noqa: E402
from victorian import box, frame_matrix, lathe  # noqa: E402
import lobby  # noqa: E402  (shared shapes: rounded_rect, solid, ring, rusted)

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "car"

W = 3.6  # half width of the body
FRONT, REAR = -8.5, 8.5  # the body's nose and tail
R = 1.25  # wheel radius
ARCH = R + 0.32  # the wheel arches' radius
AXLES = {"F": -5.1, "R": 4.9}
TRACK = W - 0.85  # the wheels' centres, either side (tucked in under the fenders)
BELT = 3.62  # where the windows start
CAB = (-2.45, 4.75)  # the greenhouse, windshield foot to rear window foot
ROOF = 5.45
TYRE = 1.1  # the tyres' width


def side_solid(grp, pts, half, bevel, name, segments=4, taper=None):
    """A side profile [(y, z)] extruded across the car from -half to +half, its long edges rounded
    (the rounding clamped so short edges don't fold over themselves: the arches' cut needs a
    clean solid). `taper` (z0, z1, k) pulls the sides in toward the top: by k at z1."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((y, z, 0)) for y, z in pts])
    if face.normal.z < 0:
        face.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=Vector((0, 0, 2 * half)), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    caps = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-4]
    bmesh.ops.bevel(bm, geom=caps, offset=bevel, segments=segments, affect="EDGES", profile=0.5, clamp_overlap=True)
    m = Matrix(((0, 0, 1, -half), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # local X->Y, Y->Z, extrude ->X
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    if taper:
        z0, z1, k = taper
        for v in bm.verts:
            v.co.x *= 1 - k * min(max((v.co.z - z0) / (z1 - z0), 0), 1)
    return V.mesh_object(name, bm, grp)


def across(grp, pts, x0, x1, name="Across"):
    """A side profile [(y, z)] as a plain prism from x0 to x1 (the window cutters)."""
    m = Matrix(((0, 0, 1, x0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    return lobby.solid(grp, pts, x1 - x0, m, name=name)


def along(grp, pts, y0, y1, name="Along"):
    """A front profile [(x, z)] as a plain prism from y0 to y1."""
    m = Matrix(((1, 0, 0, 0), (0, 0, -1, y1), (0, 1, 0, 0), (0, 0, 0, 1)))  # a rotation (a mirror turns it inside out)
    return lobby.solid(grp, pts, y1 - y0, m, name=name)


# The body --------------------------------------------------------------------------------------------
def body():
    # Long and low: a rounded nose, the hood rising to the cowl, the belt along the doors, the rear
    # deck falling away to a rounded tail.
    pts = [
        (FRONT + 0.25, 1.05), (FRONT + 0.05, 1.5), (FRONT, 2.2), (FRONT + 0.12, 2.8), (FRONT + 0.55, 3.18),
        (-6.4, 3.36), (-4.0, 3.48), (-2.6, BELT), (3.4, BELT + 0.06), (5.4, 3.55), (7.2, 3.32), (8.05, 2.95),
        (REAR, 2.35), (REAR - 0.05, 1.6), (REAR - 0.25, 1.05),
    ]
    shell = side_solid("CarPaint", pts, W, 0.62, "Shell", segments=5)
    arches = []
    for y in AXLES.values():
        m = frame_matrix((-W - 1, y, R), (0, math.pi / 2, 0))
        arches.append(lathe("_cutters", [(ARCH, 0), (ARCH, 2 * W + 2)], (0, 0, 0), segments=28, matrix=m))
    V.cut(shell, arches)
    # Inside each arch, a black wheel well over the wheel (the cut shows the body's inside otherwise).
    for y in AXLES.values():
        for side in (-1, 1):
            well(side, y)
    # Chrome down each side, a spear just over the arches; the door seams (the rear door's stops
    # short of its arch) and handles.
    for side in (-1, 1):
        x = side * (W + 0.01)
        V.tube("CarChrome", [Vector((x, -6.6, 2.98)), Vector((x, -3.0, 2.95)), Vector((x, 2.0, 2.93)), Vector((x, 5.9, 2.9))],
               [0.03, 0.07, 0.07, 0.03], sides=2)
        for y in (-2.35, 1.0, 3.25):
            box("CarTrim", (0.03, 0.05, 1.15), (side * (W + 0.002), y, 2.36))
        for y in (-0.2, 2.75):
            box("CarChrome", (0.1, 0.5, 0.09), (side * (W + 0.04), y, 2.78), bevel=0.035)


def well(side, y):
    """A wheel well: the arch's lining over the tyre and its back wall, so nothing shows through."""
    bm = bmesh.new()
    radius, steps = ARCH - 0.02, 16
    x0, x1 = side * (W - 0.03), side * (W - 1.7)
    lo = -math.asin((R - 1.05) / radius)  # where the arch meets the bottom of the body
    rows = []
    for i in range(steps + 1):
        a = lo + (math.pi - 2 * lo) * i / steps
        z = R + math.sin(a) * radius
        # Low down the body's side rounds under (its 0.62 bevel): the lining follows it in.
        under = max(0.0, 1.67 - z)
        x = x0 - side * (0.62 - math.sqrt(max(0.62**2 - under**2, 0.0))) if under > 0 else x0
        rows.append([bm.verts.new((px, y + math.cos(a) * radius, z)) for px in (x, x1)])
    for i in range(steps):
        bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
    wall = bm.faces.new([r[1] for r in rows])
    for face in bm.faces:  # facing the wheel (one-sided in Roblox)
        face.normal_update()
        centre = face.calc_center_median()
        inward = Vector((side, 0, 0)) if face is wall else Vector((0, y - centre.y, R - centre.z))
        if face.normal.dot(inward) < 0:
            face.normal_flip()
    V.mesh_object("Well", bm, "CarTrim")


def greenhouse():
    """The cabin: a painted shell (roof, pillars, its sides pulled in toward the top) with the
    windows cut out of it, dark glass set back in them, and through the glass an empty front seat
    and a steering wheel."""
    lo = BELT - 0.25  # sunk into the body
    prof = [(CAB[0], lo), (CAB[0], BELT), (-0.75, 5.28), (-0.4, ROOF), (2.55, ROOF + 0.02), (2.95, 5.3), (CAB[1], BELT), (CAB[1], lo)]
    half, taper = W - 0.66, (BELT, ROOF, 0.12)
    cabin = side_solid("CarPaint", prof, half, 0.32, "Cabin", segments=4, taper=taper)
    sill, head = BELT + 0.2, 5.1
    cutters = [
        # Windshield and rear window: one opening through the whole cabin, front to back.
        along("_cutters", [(-(half - 0.5), sill), (half - 0.5, sill), (half - 0.75, head), (-(half - 0.75), head)], -12, 12),
        # The side windows: the front door's behind the slanted A-pillar, the rear door's short of the C-pillar.
        across("_cutters", [(-2.05, sill), (0.85, sill), (0.85, head), (-0.78, head)], -W - 1, W + 1),
        across("_cutters", [(1.15, sill), (3.45, sill), (2.55, head), (1.15, head)], -W - 1, W + 1),
    ]
    V.cut(cabin, cutters)
    glass = [(CAB[0] + 0.12, lo), (CAB[0] + 0.12, BELT), (-0.75, 5.2), (2.95, 5.22), (CAB[1] - 0.12, BELT), (CAB[1] - 0.12, lo)]
    side_solid("CarGlass", glass, half - 0.1, 0.12, "Glass", segments=2, taper=taper)
    for side in (-1, 1):
        box("CarChrome", (0.06, CAB[1] - CAB[0] - 0.2, 0.07), (side * (half + 0.01), (CAB[0] + CAB[1]) / 2, BELT + 0.02))
    # Inside: the floor, an empty bench seat front and back, the dash and the wheel (driver's side, +X).
    box("CarInside", (2 * half - 0.4, CAB[1] - CAB[0] - 0.4, 0.1), (0, (CAB[0] + CAB[1]) / 2, BELT - 0.1))
    for y, h in ((0.35, 1.15), (3.1, 1.0)):
        box("CarSeat", (2 * half - 0.5, 0.42, h), (0, y, BELT + h / 2 - 0.1), rot=(math.radians(-12), 0, 0), bevel=0.15)
        box("CarSeat", (2 * half - 0.5, 0.95, 0.3), (0, y - 0.6, BELT - 0.05), bevel=0.12)
    box("CarInside", (2 * half - 0.4, 0.75, 0.3), (0, CAB[0] + 0.55, BELT + 0.02), bevel=0.12)  # dash
    m = frame_matrix((1.25, CAB[0] + 1.2, BELT + 0.75), (math.radians(-65), 0, 0))
    circle = [(math.cos(2 * math.pi * k / 20), math.sin(2 * math.pi * k / 20)) for k in range(20)]
    lobby.ring("CarTrim", [(x * 0.6, y * 0.6) for x, y in circle], [(x * 0.51, y * 0.51) for x, y in circle], 0.08, m)
    box("CarTrim", (0.1, 0.9, 0.1), (1.25, CAB[0] + 0.85, BELT + 0.45), rot=(math.radians(-60), 0, 0))  # its column


def front():
    """The grille's chrome teeth in a surround, round headlights in chrome bezels, the wrap-around
    bumper with its two bullet guards, the hood ornament."""
    surround = frame_matrix((0, FRONT - 0.02, 2.05), (math.pi / 2, 0, 0))
    lobby.ring("CarChrome", lobby.rounded_rect(4.6, 1.5, 0.55, 5), lobby.rounded_rect(4.2, 1.15, 0.4, 5), 0.25, surround)
    box("CarTrim", (4.2, 0.1, 1.15), (0, FRONT + 0.1, 2.05))  # dark behind the teeth
    for k in range(9):
        x = -1.8 + k * 0.45
        lathe("CarChrome", [(0.11, 0.0), (0.13, 0.15), (0.11, 0.9), (0.06, 1.0)], (0, 0, 0), segments=10,
              matrix=frame_matrix((x, FRONT - 0.05, 1.55), (0, 0, 0)))
    for side in (-1, 1):
        m = frame_matrix((side * 2.62, FRONT + 0.32, 2.72), (math.pi / 2, 0, 0))  # local +Z out the front
        lathe("CarChrome", [(0.62, -0.3), (0.62, 0.05), (0.56, 0.16), (0.47, 0.12)], (0, 0, 0), segments=24, matrix=m)
        lathe("LightWhite", [(0.47, 0.06), (0.4, 0.14), (0.2, 0.19), (0.0, 0.2)], (0, 0, 0), segments=24, matrix=m)
        # A bullet guard on the bumper either side of the grille.
        lathe("CarChrome", [(0.24, 0.0), (0.24, 0.12), (0.19, 0.4), (0.09, 0.56), (0.0, 0.6)], (0, 0, 0), segments=16,
              matrix=frame_matrix((side * 1.35, FRONT - 0.38, 1.5), (math.pi / 2, 0, 0)))
    bumper(FRONT - 0.18, -1)
    # A chrome fin down the hood, and the ornament leaping off its nose.
    box("CarChrome", (0.12, 4.5, 0.06), (0, -6.1, 3.42), rot=(math.radians(-2.5), 0, 0))
    V.tube("CarChrome", [Vector((0, -8.0, 3.28)), Vector((0, -7.55, 3.62)), Vector((0, -7.1, 3.5))], [0.05, 0.12, 0.03], sides=1)


def bumper(y, out):
    """A fat chrome bar across the end, wrapping round the corners toward the wheels."""
    pts = [
        Vector((-W - 0.08, y - out * 1.5, 1.32)), Vector((-W + 0.25, y - out * 0.15, 1.35)), Vector((0, y + out * 0.05, 1.38)),
        Vector((W - 0.25, y - out * 0.15, 1.35)), Vector((W + 0.08, y - out * 1.5, 1.32)),
    ]
    V.tube("CarChrome", pts, [0.26, 0.3, 0.32, 0.3, 0.26], sides=2)


def rear():
    for side in (-1, 1):
        m = frame_matrix((side * 2.78, REAR - 0.25, 2.55), (-math.pi / 2, 0, 0))  # local +Z out the back
        lathe("CarChrome", [(0.42, -0.25), (0.42, 0.08), (0.36, 0.14)], (0, 0, 0), segments=20, matrix=m)
        lathe("LightRed", [(0.36, 0.06), (0.3, 0.16), (0.0, 0.2)], (0, 0, 0), segments=20, matrix=m)
    bumper(REAR + 0.18, 1)
    box("CarPlate", (1.5, 0.06, 0.72), (0, REAR + 0.03, 1.95), bevel=0.03)
    box("CarChrome", (1.7, 0.1, 0.12), (0, REAR + 0.02, 2.4), bevel=0.03)  # the trunk handle over it


def tire(m, grp):
    """A tyre round local Z (the axle): rounded shoulders, a fat sidewall with a bead line, a
    groove round the middle of the tread and staggered blocks either side of it (you see it roll)."""
    segs = 72
    prof = [(0.62, -0.45), (0.72, -0.5), (0.86, -0.5), (0.9, -0.49), (0.95, -0.44), (0.99, -0.34), (1.0, -0.28),
            (1.0, -0.07), (0.965, -0.04), (0.965, 0.04), (1.0, 0.07), (1.0, 0.28), (0.99, 0.34), (0.95, 0.44),
            (0.9, 0.49), (0.86, 0.5), (0.72, 0.5), (0.62, 0.45)]
    left, right = {6, 7}, {10, 11}  # the tread either side of the groove
    per = 3  # segments a block
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        # A block's edge is a sheer step: two rings at the one angle, one each side of it.
        states = [(i // per) % 2, ((i - 1) // per) % 2] if i % per == 0 else [(i // per) % 2]
        for block in reversed(states):
            ring = []
            for k, (f, z) in enumerate(prof):
                if (k in left and block == 0) or (k in right and block == 1):
                    f -= 0.035
                ring.append(bm.verts.new((math.cos(a) * f * R, math.sin(a) * f * R, z * TYRE)))
            rings.append(ring)
    n = len(prof)
    for i in range(len(rings)):
        cur, nxt = rings[i], rings[(i + 1) % len(rings)]
        for k in range(n):
            j = (k + 1) % n
            bm.faces.new((cur[k], nxt[k], nxt[j], cur[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)  # the steps' flat sides fold away
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    V.mesh_object("Tire", bm, grp)


def turned(grp, profile, matrix, segments=36, name="Turned"):
    """An open lathe: `profile` [(radius, height)] turned round local Z with no caps (a trim ring
    mustn't close over the middle), every face turned out toward +Z (one-sided in Roblox)."""
    bm = bmesh.new()
    rings = [[bm.verts.new((math.cos(2 * math.pi * i / segments) * r, math.sin(2 * math.pi * i / segments) * r, h))
              for i in range(segments)] for r, h in profile]
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            face = bm.faces.new((a[i], a[j], b[j], b[i]))
            face.normal_update()
            if face.normal.z < 0:
                face.normal_flip()
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return V.mesh_object(name, bm, grp)


def wheels():
    """Each wheel its own pieces (the game spins them): the tyre with its tread, an old cream
    whitewall, the steel wheel painted like the body with six slots punched round it, a chrome
    trim ring at its edge and a domed chrome cap with a two-eared spinner and a red badge."""
    circle = [(math.cos(2 * math.pi * k / 48), math.sin(2 * math.pi * k / 48)) for k in range(48)]
    face = 0.5 * TYRE  # the tyre's outer wall
    for axle, y in AXLES.items():
        for side, s in (("L", 1), ("R", -1)):  # the car's left is +X (facing -Y)
            key = axle + side
            out = frame_matrix((s * TRACK, y, R), (0, s * math.pi / 2, 0))  # local +Z away from the car
            tire(out, f"CarTire{key}")
            lobby.ring(f"CarWall{key}", [(x * 0.84 * R, y * 0.84 * R) for x, y in circle], [(x * 0.7 * R, y * 0.7 * R) for x, y in circle],
                       0.02, out @ Matrix.Translation((0, 0, face - 0.005)), name="Whitewall")
            # The steel wheel, dished in toward the middle.
            lathe(f"CarRim{key}", [(0.66 * R, face - 0.12), (0.64 * R, face - 0.03), (0.52 * R, face - 0.06), (0.4 * R, face - 0.02)],
                  (0, 0, 0), segments=40, matrix=out)
            for k in range(6):
                slot = out @ Matrix.Rotation(2 * math.pi * k / 6 + math.pi / 6, 4, "Z") @ Matrix.Translation((0.53 * R, 0, face - 0.06))
                lobby.solid(f"CarTire{key}", lobby.rounded_rect(0.07 * R, 0.17 * R, 0.03 * R, 3), 0.025, slot, name="Slot")
            # The trim ring round its edge and the cap in the middle.
            turned(f"CarHub{key}", [(0.69 * R, face - 0.06), (0.685 * R, face + 0.01), (0.66 * R, face + 0.035), (0.6 * R, face + 0.01),
                                    (0.58 * R, face - 0.04)], out, segments=48, name="TrimRing")
            lathe(f"CarHub{key}", [(0.4 * R, face - 0.08), (0.39 * R, face + 0.02), (0.33 * R, face + 0.09), (0.22 * R, face + 0.14),
                                   (0.08 * R, face + 0.165), (0.0, face + 0.17)], (0, 0, 0), segments=32, matrix=out)
            # A boss in the middle with the spinner's two ears off it, leaning down over the dome.
            lathe(f"CarHub{key}", [(0.11 * R, face + 0.12), (0.11 * R, face + 0.24), (0.08 * R, face + 0.27), (0.0, face + 0.27)],
                  (0, 0, 0), segments=24, matrix=out)
            for k in (-1, 1):
                ear = out @ Matrix.Translation((k * 0.24 * R, 0, face + 0.2)) @ Matrix.Rotation(k * math.radians(14), 4, "Y")
                box(f"CarHub{key}", (0.3 * R, 0.1 * R, 0.05), (0, 0, 0), bevel=0.018, matrix=ear)
                box(f"CarHub{key}", (0.05 * R, 0.17 * R, 0.07), (k * 0.14 * R, 0, 0), bevel=0.02, matrix=ear)
            lathe(f"CarRim{key}", [(0.075 * R, face + 0.26), (0.07 * R, face + 0.29), (0.0, face + 0.295)], (0, 0, 0), segments=20, matrix=out)


def details():
    """The bits that make it a real old car: a chrome mirror on the driver's door, the wipers parked
    at the foot of the windshield, a whip aerial off the front fender, the exhaust under the back."""
    x = W - 0.66  # the cabin's side at the belt
    V.tube("CarChrome", [Vector((x + 0.05, CAB[0] + 0.55, BELT + 0.05)), Vector((x + 0.35, CAB[0] + 0.5, BELT + 0.32)),
                         Vector((x + 0.5, CAB[0] + 0.48, BELT + 0.5))], [0.05, 0.045, 0.04], sides=1)
    m = frame_matrix((x + 0.55, CAB[0] + 0.5, BELT + 0.62), (math.pi / 2, 0, 0))
    lathe("CarChrome", [(0.24, -0.06), (0.25, 0.0), (0.2, 0.05), (0.0, 0.06)], (0, 0, 0), segments=20, matrix=m)
    lathe("CarTrim", [(0.19, 0.0), (0.19, 0.012)], (0, 0, 0), segments=20, matrix=frame_matrix((x + 0.55, CAB[0] + 0.555, BELT + 0.62), (-math.pi / 2, 0, 0)))
    # Wipers flat across the glass where it meets the cowl (the windshield leans back 45 degrees).
    for wx in (-1.15, 0.95):
        box("CarTrim", (1.7, 0.05, 0.06), (wx, CAB[0] + 0.12 + 0.28 - 0.06, BELT + 0.28), rot=(math.radians(-45), 0, 0))
        box("CarTrim", (0.06, 0.25, 0.06), (wx + 0.85, CAB[0] - 0.02, BELT + 0.1), rot=(math.radians(-45), 0, 0))
    V.tube("CarChrome", [Vector((W - 0.55, -5.9, 3.35)), Vector((W - 0.6, -5.5, 4.8)), Vector((W - 0.66, -5.05, 6.6))],
           [0.045, 0.025, 0.012], sides=1)
    m = frame_matrix((-1.9, REAR - 0.15, 0.95), (-math.pi / 2, 0, 0))
    lathe("CarTrim", [(0.17, -0.6), (0.17, 0.25), (0.13, 0.25), (0.13, -0.1)], (0, 0, 0), segments=14, matrix=m)


def markers():
    box("Mark_Origin", (0.1, 0.1, 0.1), (0, 0, 0.05))
    for side, s in (("L", 1), ("R", -1)):
        box(f"Mark_Head{side}", (0.2, 0.2, 0.2), (s * 2.62, FRONT - 0.1, 2.72))
        box(f"Mark_Tail{side}", (0.2, 0.2, 0.2), (s * 2.78, REAR + 0.1, 2.55))


# Build ------------------------------------------------------------------------------------------------
WHEEL_KEYS = ("FL", "FR", "RL", "RR")
WHEEL_PARTS = ("Tire", "Wall", "Rim", "Hub")


def build():
    V.reset()
    V.build_materials()
    M, U = V.MATERIALS, V.UV_RULES
    paint = V.textured("CarPaint", "concrete_wall_006", paint=(0.2, 0.045, 0.05, 1), rough=0.5, dirt=0.7, moss=0.15, bump=0.35)
    lobby.rusted(paint, 0.85, scale=0.22)
    M["CarPaint"], U["CarPaint"] = paint, (6.0, "vertical")
    M["CarChrome"] = V.textured("CarChrome", "concrete_wall_006", paint=(0.8, 0.8, 0.82, 1), rough=0.28, dirt=0.55, metal=1.0)
    lobby.rusted(M["CarChrome"], 0.35, scale=0.5)
    U["CarChrome"] = (2.0, "long")
    M["CarTrim"] = V.textured("CarTrim", None, tint=(0.02, 0.02, 0.02, 1), rough=0.8)
    M["CarInside"] = V.textured("CarInside", None, tint=(0.05, 0.035, 0.03, 1), rough=0.85)
    M["CarSeat"] = V.textured("CarSeat", "brown_leather", tint=(0.35, 0.2, 0.14, 1), rough=0.55, dirt=0.85)
    U["CarSeat"] = (1.6, "vertical")
    M["CarGlass"] = M["Glass"]
    M["CarPlate"] = V.textured("CarPlate", None, tint=(0.72, 0.68, 0.55, 1), rough=0.7)
    M["LightWhite"] = V.textured("LightWhite", None, tint=(0.4, 0.38, 0.3, 1), emission=((1.0, 0.86, 0.6, 1), 4.0))
    M["LightRed"] = V.textured("LightRed", None, tint=(0.3, 0.02, 0.02, 1), emission=((1.0, 0.05, 0.03, 1), 2.5))
    for key in WHEEL_KEYS:
        M[f"CarTire{key}"] = V.textured(f"CarTire{key}", None, tint=(0.014, 0.013, 0.012, 1), rough=0.92)
        M[f"CarWall{key}"] = V.textured(f"CarWall{key}", None, tint=(0.56, 0.52, 0.43, 1), rough=0.85)
        M[f"CarRim{key}"] = V.textured(f"CarRim{key}", None, tint=(0.14, 0.03, 0.03, 1), rough=0.55, metal=0.4)
        M[f"CarHub{key}"] = V.textured(f"CarHub{key}", None, tint=(0.6, 0.6, 0.62, 1), rough=0.22, metal=1.0)
    for name in list(M):
        U.setdefault(name, (4.0, "vertical"))
    body()
    greenhouse()
    front()
    rear()
    wheels()
    details()
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
    smooth = {"CarPaint", "CarChrome", "CarSeat", "CarGlass"} | {f"Car{p}{k}" for p in WHEEL_PARTS for k in WHEEL_KEYS}
    for name in smooth:
        if name in merged:
            obj = merged[name]
            for o in bpy.context.scene.objects:
                o.select_set(False)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    print("TRIANGLES", {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()})
    return merged


# Plain in the game (a colour and material set by tools/setup_car.luau): glass, lamps, the wheels.
FLAT = {"CarGlass", "CarPlate", "CarTrim", "CarInside", "LightWhite", "LightRed"} | {
    f"Car{p}{k}" for p in WHEEL_PARTS for k in WHEEL_KEYS
} | {f"Mark_{n}" for n in ("Origin", "HeadL", "HeadR", "TailL", "TailR")}


def render(name):
    day = "--day" in ARGS
    cam, _ = V.setup_render("car", night=not day)
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
        scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.035, 0.05, 1)  # for the chrome
        moon = bpy.data.objects.new("Moon", bpy.data.lights.new("Moon", "SUN"))
        moon.data.energy = 2.2
        moon.data.color = (0.55, 0.65, 1.0)
        moon.rotation_euler = (math.radians(50), 0, math.radians(-140))
        scene.collection.objects.link(moon)
        light("StreetLamp", "POINT", (-12, -6, 14), 9000, (1.0, 0.7, 0.42), size=0.8)
        light("Rim", "POINT", (12, 18, 9), 3000, (0.45, 0.55, 1.0), size=2.0)
        light("Fill", "AREA", (-22, -22, 10), 5000, (0.75, 0.8, 1.0), rot=(math.radians(70), 0, math.radians(-45)), size=10)
    for x in (-2.62, 2.62):
        light("Beam", "SPOT", (x, FRONT - 0.4, 2.72), 1500, (1.0, 0.88, 0.65), rot=(math.radians(-86), 0, 0), spot=math.radians(45))
    if "--side" in ARGS:
        cam.location = (-26, 0, 4.5)
        target = Vector((0, 0, 2.6))
        cam.data.lens = 30
    elif "--back" in ARGS:
        cam.location = (12, 24, 5.5)
        target = Vector((0, 3, 2.6))
        cam.data.lens = 30
    elif "--wheel" in ARGS:  # close on the front wheel, the driver's side
        cam.location = (7.5, -8.6, 2.2)
        target = Vector((TRACK, AXLES["F"], R))
        cam.data.lens = 50
    else:
        cam.location = (-13, -21, 5.0)
        target = Vector((0, -2.5, 2.4))
        cam.data.lens = 30
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

        export_victorian.export(merged, EXPORT, "Car.fbx", flat=FLAT)
