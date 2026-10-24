"""The figures that stand in the open houses' halls and behind windows (furniture.py pieces, built
in metres at the furniture origin, facing -Y): smooth, subdivided silhouettes, read from far off in
the dark by their shape and their pale hands and faces.

  FigureWidow - a woman in a long black mourning dress, her face behind a black veil, arms hanging
                too long, pale fingers at her knees
  FigureTall  - a gaunt man in a long coat, much too tall, a small bald head tilted on a long neck,
                hollow eyes, hands down by his knees
  FigureGirl  - a little girl in a grey nightgown, barefoot, head bowed, long black hair hanging
                over her face
"""

import math

import bmesh
from mathutils import Matrix, Vector

V = None  # victorian, set by furniture.py
U = 3.8


def setup(v, u):
    global V, U
    V, U = v, u


def materials():
    M, R = V.MATERIALS, V.UV_RULES
    M["Mourning"] = V.textured("Mourning", "velour_velvet", paint=(0.055, 0.05, 0.058, 1), rough=0.75, dirt=0.5)
    M["Veil"] = V.textured("Veil", "rough_linen", paint=(0.03, 0.028, 0.03, 1), rough=0.85, dirt=0.3)
    M["Coat"] = V.textured("Coat", "caban", paint=(0.05, 0.045, 0.042, 1), rough=0.9, dirt=0.6)
    M["Nightgown"] = V.textured("Nightgown", "rough_linen", paint=(0.5, 0.49, 0.45, 1), rough=0.9, dirt=0.85)
    M["Skin"] = V.textured("Skin", None, tint=(0.56, 0.55, 0.52, 1), rough=0.55, dirt=0.5)
    M["Hair"] = V.textured("Hair", None, tint=(0.015, 0.013, 0.013, 1), rough=0.45, dirt=0.2)
    M["Hollow"] = V.textured("Hollow", None, tint=(0.0, 0.0, 0.0, 1), rough=1.0, dirt=0.0)
    for name, size in (("Mourning", 1.2), ("Veil", 1.0), ("Coat", 1.4), ("Nightgown", 1.2), ("Skin", 2.0), ("Hair", 2.0), ("Hollow", 2.0)):
        R[name] = (size, "vertical")


def soften(obj, levels=1):
    """Subdivides a piece smooth and shades it smooth."""
    mod = obj.modifiers.new("Soft", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    V.apply_modifiers(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def shell(grp, profile, m, segs=28, squash=1.0, ripple=None, caps=(True, True), thick=0.0):
    """A lathed body round the vertical axis: `profile` [(radius, z)] from the bottom up, its cross
    sections squashed front to back by `squash`, `ripple(theta, z)` adding to the radius (pleats,
    folds, strands of hair). `thick` > 0 gives an open shell that thickness (a veil, a curtain of
    hair). In frame m (metres)."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(segs):
            t = 2 * math.pi * i / segs
            rr = max(0.0, r + (ripple(t, z) if ripple else 0.0))
            ring.append(bm.verts.new((math.cos(t) * rr, math.sin(t) * rr * squash, z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if caps[0] and thick == 0:
        bm.faces.new(list(reversed(rings[0])))
    if caps[1] and thick == 0:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    obj = V.mesh_object("Shell", bm, grp)
    if thick > 0:
        mod = obj.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = thick * U
        mod.offset = -1
        V.apply_modifiers(obj)
    return obj


def egg(grp, m, rx, ry, rz, segs=20, rings=12):
    """An ellipsoid (a head, a shoulder) in frame m."""
    profile = [(math.sin(math.pi * k / rings) * rx, -math.cos(math.pi * k / rings) * rz) for k in range(1, rings)]  # capped, no poles
    return shell(grp, profile, m, segs=segs, squash=ry / rx)


def limb(grp, m, points, radii, sides=3):
    """A smooth tapering tube through `points` (metres, frame m), `radii` in metres."""
    return V.tube(grp, [m @ Vector(p) for p in points], [r * U for r in radii], sides=sides)


def hand(grp, m, wrist, down, out, length=0.13, palm=0.06):
    """A long pale hand hanging from `wrist` along `down`, its back toward `out` (unit vectors,
    metres): a flattened palm and four thin fingers curling a little."""
    wrist, down, out = Vector(wrist), Vector(down).normalized(), Vector(out).normalized()
    side = down.cross(out).normalized()
    centre = wrist + down * palm * 0.6
    basis = Matrix((side, out, down)).transposed().to_4x4()
    basis.translation = centre
    egg(grp, m @ basis, 0.035, 0.014, palm * 0.6, segs=12, rings=8)
    for k, spread in enumerate((-1.5, -0.5, 0.5, 1.5)):
        base = centre + down * palm * 0.5 + side * spread * 0.013
        reach = length * (0.82 if k in (0, 3) else 1.0)
        tip = base + down * reach + out * -0.02 * (1 + abs(spread) * 0.3)
        mid = base + down * reach * 0.55 + out * 0.004
        limb(grp, m, [base, mid, tip], [0.009, 0.008, 0.006], sides=2)
    thumb = centre + side * 0.03 + out * -0.01
    limb(grp, m, [thumb, thumb + down * 0.05 + side * 0.012 + out * -0.015], [0.008, 0.006], sides=2)


def widow(m):
    """The widow: mourning dress, veil, hands at her knees."""
    pleats = lambda t, z: (0.016 * math.sin(t * 13 + 0.6 * math.sin(t * 3)) * max(0.0, 1.0 - z / 1.0)) + (0.006 * math.sin(t * 7) if z < 0.06 else 0.0)
    dress = shell("Mourning", [(0.38, 0.0), (0.44, 0.02), (0.43, 0.15), (0.38, 0.45), (0.31, 0.75), (0.24, 0.95), (0.19, 1.05),
                               (0.2, 1.15), (0.215, 1.3), (0.205, 1.4), (0.17, 1.48), (0.09, 1.53), (0.0, 1.535)], m, segs=40, squash=0.72, ripple=pleats)
    soften(dress)
    for s in (-1, 1):  # shoulders under the dress
        egg("Mourning", m @ Matrix.Translation((s * 0.15, 0.0, 1.47)), 0.075, 0.07, 0.06)
    soften(shell("Mourning", [(0.065, 1.5), (0.07, 1.56), (0.062, 1.64), (0.0, 1.645)], m, segs=20))  # high collar
    head = egg("Skin", m @ Matrix.Translation((0.0, -0.005, 1.74)), 0.085, 0.095, 0.115)
    soften(head)
    # The veil: from the crown over the face and down past the shoulders, in soft folds.
    folds = lambda t, z: 0.012 * math.sin(t * 9 + z * 6) * min(1.0, (1.86 - z) * 3)
    veil = shell("Veil", [(0.26, 1.34), (0.225, 1.45), (0.17, 1.57), (0.128, 1.67), (0.122, 1.76), (0.11, 1.84), (0.07, 1.895), (0.02, 1.915)],
                 m, segs=36, squash=0.9, ripple=folds, thick=0.008)
    soften(veil)
    # Arms hanging too long, sleeves to the wrist, pale hands at the knees.
    for s in (-1, 1):
        pts = [(s * 0.17, 0.0, 1.46), (s * 0.235, 0.0, 1.22), (s * 0.245, -0.025, 0.98), (s * 0.235, -0.045, 0.74), (s * 0.225, -0.05, 0.62)]
        limb("Mourning", m, pts, [0.05, 0.042, 0.038, 0.034, 0.036], sides=3)
        soften(shell("Mourning", [(0.03, 0.6), (0.042, 0.61), (0.04, 0.64), (0.0, 0.645)], m @ Matrix.Translation((s * 0.225, -0.05, 0.0)), segs=14))
        hand("Skin", m, (s * 0.225, -0.05, 0.6), (0, -0.05, -1), (s, 0.2, 0), length=0.15)


def tall(m):
    """The tall man: a long coat, a small bald skull of a head on a long neck, hands by his knees."""
    for s in (-1, 1):
        limb("Coat", m, [(s * 0.085, 0.0, 0.06), (s * 0.088, 0.0, 0.5), (s * 0.09, 0.0, 0.85)], [0.046, 0.05, 0.053], sides=3)
        soften(shell("Hollow", [(0.04, 0.0), (0.055, 0.004), (0.06, 0.05), (0.04, 0.07), (0.01, 0.075)], m @ Matrix.Translation((s * 0.085, -0.04, 0.0)) @ Matrix.Diagonal((1, 1.9, 1, 1)), segs=14))
    hem = lambda t, z: 0.01 * math.sin(t * 9) * max(0.0, 1.0 - (z - 0.42) / 0.6)
    # Shoulders square and narrow under the coat: wider side to side than front to back.
    coat = shell("Coat", [(0.24, 0.42), (0.27, 0.44), (0.25, 0.7), (0.21, 1.0), (0.18, 1.2), (0.2, 1.45), (0.23, 1.62),
                          (0.225, 1.69), (0.16, 1.74), (0.07, 1.77), (0.04, 1.775)], m, segs=36, squash=0.58, ripple=hem)
    soften(coat)
    soften(shell("Coat", [(0.075, 1.72), (0.085, 1.78), (0.08, 1.86), (0.072, 1.88)], m, segs=20, squash=0.9, thick=0.012))  # a stiff collar
    lean = m @ Matrix.Translation((0.0, -0.015, 1.74)) @ Matrix.Rotation(0.1, 4, "X") @ Matrix.Rotation(-0.08, 4, "Y")
    soften(shell("Skin", [(0.036, 0.0), (0.03, 0.12), (0.03, 0.22), (0.034, 0.27), (0.01, 0.28)], lean, segs=16))
    head = lean @ Matrix.Translation((0.0, -0.005, 0.36)) @ Matrix.Rotation(-0.3, 4, "Y")
    # A long skull: wide at the temples, sunken at the cheeks, a narrow jaw.
    skull = shell("Skin", [(0.03, -0.12), (0.05, -0.11), (0.058, -0.08), (0.056, -0.04), (0.064, 0.0), (0.072, 0.04),
                           (0.07, 0.08), (0.058, 0.11), (0.032, 0.13), (0.008, 0.135)], head, segs=24, squash=1.12)
    soften(skull)
    for s in (-1, 1):  # deep sockets
        egg("Hollow", head @ Matrix.Translation((s * 0.03, -0.068, 0.03)) @ Matrix.Rotation(s * 0.25, 4, "Y"), 0.022, 0.012, 0.03, segs=12, rings=8)
    egg("Hollow", head @ Matrix.Translation((0.0, -0.062, -0.075)), 0.018, 0.008, 0.012, segs=12, rings=6)  # the mouth, slack
    for s in (-1, 1):
        pts = [(s * 0.2, 0.0, 1.66), (s * 0.235, 0.01, 1.42), (s * 0.245, -0.01, 1.1), (s * 0.24, -0.03, 0.8), (s * 0.23, -0.035, 0.7)]
        limb("Coat", m, pts, [0.048, 0.042, 0.038, 0.035, 0.037], sides=3)
        hand("Skin", m, (s * 0.23, -0.035, 0.68), (0, -0.04, -1), (s, 0.15, 0), length=0.19, palm=0.065)


def girl(m):
    """The girl: nightgown, bare feet, head bowed under long black hair."""
    for s in (-1, 1):
        soften(shell("Skin", [(0.0, 0.0), (0.03, 0.004), (0.033, 0.03), (0.025, 0.06), (0.0, 0.065)], m @ Matrix.Translation((s * 0.06, -0.055, 0.0)) @ Matrix.Diagonal((1, 2.1, 1, 1)), segs=12))
    folds = lambda t, z: 0.012 * math.sin(t * 11 + 0.8 * math.sin(t * 2)) * max(0.0, 1.0 - z / 0.6)
    gown = shell("Nightgown", [(0.17, 0.05), (0.2, 0.07), (0.19, 0.3), (0.16, 0.55), (0.135, 0.72), (0.14, 0.82), (0.12, 0.88),
                               (0.06, 0.92), (0.0, 0.925)], m, segs=36, squash=0.75, ripple=folds)
    soften(gown)
    bow = m @ Matrix.Translation((0.0, -0.01, 0.9)) @ Matrix.Rotation(0.38, 4, "X")
    soften(shell("Skin", [(0.032, 0.0), (0.03, 0.06), (0.0, 0.07)], bow, segs=12))
    head = bow @ Matrix.Translation((0.0, 0.0, 0.14))
    soften(egg("Skin", head, 0.075, 0.08, 0.088))
    # Hair: a curtain from the crown hanging past her face to her waist, in strands.
    strands = lambda t, z: 0.006 * math.sin(t * 31) + 0.004 * math.sin(t * 17 + z * 9)
    hair = shell("Hair", [(0.115, -0.5), (0.11, -0.3), (0.1, -0.12), (0.092, 0.0), (0.088, 0.05), (0.07, 0.085), (0.0, 0.1)],
                 head, segs=48, squash=0.95, ripple=strands, thick=0.012)
    soften(hair)
    for s in (-1, 1):
        pts = [(s * 0.115, 0.0, 0.84), (s * 0.15, 0.0, 0.68), (s * 0.155, -0.02, 0.52), (s * 0.15, -0.03, 0.44)]
        limb("Nightgown", m, pts, [0.03, 0.027, 0.024, 0.022], sides=3)
        hand("Skin", m, (s * 0.15, -0.03, 0.43), (0, -0.05, -1), (s, 0.2, 0), length=0.08, palm=0.04)


PIECES = {"FigureWidow": widow, "FigureTall": tall, "FigureGirl": girl}
