"""Finds z-fighting in exported models: faces that lie in (almost) the same plane, face the same
way and overlap, so the renderer can't decide which to draw and the textures flicker as the camera
moves. Imports each FBX and reports every overlapping pair, grouped by the meshes involved.

    blender -b --factory-startup --python art/scripts/zfight.py -- art/export/victorian/Victorian.fbx [...]
        [--gap 0.03] [--min 0.02] [--detail] [--self] [--all]

--gap: how close two parallel faces count as one plane (studs); --min: smallest overlap reported
(square studs). A pair buried inside other geometry (a wall's top under the roof) can't be seen
and is left out unless --all: a point just in front of the overlap that every ray from it leaves
through the back of a face is inside a solid. --self: only faces of the same mesh (a set of pieces
all modelled at one origin, like the furniture).
"""

import math
import pathlib
import sys
from collections import defaultdict

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def option(name, default):
    if name in ARGS:
        i = ARGS.index(name)
        value = ARGS[i + 1]
        del ARGS[i : i + 2]
        return float(value)
    return default


GAP = option("--gap", 0.03)
MIN_AREA = option("--min", 0.02)
DETAIL = "--detail" in ARGS
SELF = "--self" in ARGS  # only faces of the same mesh (a set of pieces modelled at one origin)
PAIR = None  # --pair A,B: print some of the overlapping triangles of those two meshes
if "--pair" in ARGS:
    i = ARGS.index("--pair")
    PAIR = tuple(sorted(ARGS[i + 1].split(",")))
    del ARGS[i : i + 2]
ALL = "--all" in ARGS  # also the pairs buried inside other geometry, which nobody can see
for flag in ("--detail", "--self", "--all"):
    if flag in ARGS:
        ARGS.remove(flag)
COS = math.cos(math.radians(1.5))  # parallel enough


def triangles(scale):
    """Every triangle of every mesh in the scene, in world space (studs)."""
    out = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(depsgraph)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        mw = obj.matrix_world
        verts = [(mw @ v.co) * scale for v in me.vertices]
        for tri in me.loop_triangles:
            a, b, c = (verts[i] for i in tri.vertices)
            n = (b - a).cross(c - a)
            area = n.length / 2
            if area < 1e-4:
                continue
            n.normalize()
            out.append((obj.name, a, b, c, n, n.dot(a), area))
        ev.to_mesh_clear()
    return out


def basis(n):
    u = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
    u = (u - n * u.dot(n)).normalized()
    return u, n.cross(u)


def clip(poly, a, b):
    """Sutherland-Hodgman: the part of the convex polygon `poly` left of the edge a->b."""
    out = []

    def side(p):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])

    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        sp, sq = side(p), side(q)
        if sp >= 0:
            out.append(p)
        if (sp >= 0) != (sq >= 0):
            t = sp / (sp - sq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def area2d(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))) / 2


def ccw(tri):
    (ax, ay), (bx, by), (cx, cy) = tri
    return tri if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) >= 0 else [tri[0], tri[2], tri[1]]


DIRS = [Vector(d).normalized() for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1), (0.6, 0.6, 0.53), (-0.6, -0.6, -0.53))]


def buried(tree, point, n):
    """Whether `point` (just in front of a face with normal n) is inside a closed solid: every ray
    from it, except those heading back to the face itself, hits the back of a face."""
    for d in DIRS:
        if d.dot(n) < -0.5:
            continue
        hit, normal, _, _ = tree.ray_cast(point, d, 500.0)
        if hit is None or normal.dot(d) < 0:
            return False
    return True


def check(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    return analyze(path.name)


def analyze(label):
    """Reports the z-fighting among the meshes in the current scene (a build script's, with
    --zfight, or an imported FBX's)."""
    # The exporter writes studs with FBX unit scale; find the scale that makes the model's height
    # sensible (the importer may bring it in at 1/100).
    tris = triangles(1.0)
    zs = [t[1].z for t in tris] + [t[1].y for t in tris]
    span = max(zs) - min(zs) if zs else 1
    scale = 100.0 if span < 1.0 else 1.0
    if scale != 1.0:
        tris = triangles(scale)
    verts, polys = [], []
    for t in tris:
        polys.append((len(verts), len(verts) + 1, len(verts) + 2))
        verts += [t[1], t[2], t[3]]
    tree = BVHTree.FromPolygons(verts, polys)
    # Bucket by direction (rounded) and plane offset, so only near-coplanar faces meet.
    buckets = defaultdict(list)
    for i, t in enumerate(tris):
        n, d = t[4], t[5]
        key = (round(n.x * 20), round(n.y * 20), round(n.z * 20), math.floor(d / GAP))
        buckets[key].append(i)
    seen = set()
    pairs = defaultdict(lambda: [0.0, Vector(), 0])
    patches = defaultdict(lambda: [0.0, [1e9] * 3, [-1e9] * 3])
    for key, members in buckets.items():
        nx, ny, nz, dk = key
        near = []
        for ex in (-1, 0, 1):
            for ey in (-1, 0, 1):
                for ez in (-1, 0, 1):
                    for ed in (-1, 0, 1):
                        near.extend(buckets.get((nx + ex, ny + ey, nz + ez, dk + ed), ()))
        for i in members:
            name1, a1, b1, c1, n1, d1, _ = tris[i]
            u, v = basis(n1)
            p1 = ccw([(p.dot(u), p.dot(v)) for p in (a1, b1, c1)])
            lo1 = (min(p[0] for p in p1), min(p[1] for p in p1))
            hi1 = (max(p[0] for p in p1), max(p[1] for p in p1))
            for j in near:
                if j <= i or (i, j) in seen:
                    continue
                seen.add((i, j))
                name2, a2, b2, c2, n2, d2, _ = tris[j]
                if SELF and name1 != name2:
                    continue
                if n1.dot(n2) < COS:
                    continue
                if abs(n1.dot(a2) - d1) > GAP or abs(n1.dot(b2) - d1) > GAP or abs(n1.dot(c2) - d1) > GAP:
                    continue
                p2 = ccw([(p.dot(u), p.dot(v)) for p in (a2, b2, c2)])
                if max(p[0] for p in p2) <= lo1[0] or min(p[0] for p in p2) >= hi1[0]:
                    continue
                if max(p[1] for p in p2) <= lo1[1] or min(p[1] for p in p2) >= hi1[1]:
                    continue
                poly = p1
                for k in range(3):
                    poly = clip(poly, p2[k], p2[(k + 1) % 3])
                    if len(poly) < 3:
                        break
                area = area2d(poly) if len(poly) >= 3 else 0.0
                if area < 1e-3:
                    continue
                cx = sum(q[0] for q in poly) / len(poly)
                cy = sum(q[1] for q in poly) / len(poly)
                spot = u * cx + v * cy + n1 * (d1 + 0.06)
                if not ALL and (buried(tree, spot, n1) or spot.z < 0.0):  # under the ground
                    continue
                if PAIR == tuple(sorted((name1, name2))) and pairs[PAIR][2] < 12:
                    def fmt(p):
                        return f"({p.x:.2f}, {p.y:.2f}, {p.z:.2f})"
                    print(f"  {name1} {fmt(a1)} {fmt(b1)} {fmt(c1)} n {fmt(n1)}")
                    print(f"  {name2} {fmt(a2)} {fmt(b2)} {fmt(c2)} n {fmt(n2)}  overlap {area:.2f}")
                rec = pairs[tuple(sorted((name1, name2)))]
                rec[0] += area
                rec[1] += (a1 + b1 + c1) / 3 * area
                rec[2] += 1
                # Patches: each plane and 3-stud cell separately, so each spot can be found.
                centre = (a1 + b1 + c1) / 3
                axis = max(range(3), key=lambda k: abs(n1[k]))
                cell = (tuple(sorted((name1, name2))), "xyz"[axis] + ("+" if n1[axis] > 0 else "-"), round(d1, 1),
                        tuple(math.floor(centre[k] / 3) for k in range(3) if k != axis))
                patch = patches[cell]
                patch[0] += area
                for k in range(3):
                    for p in (a1, b1, c1):
                        patch[1][k] = min(patch[1][k], p[k])
                        patch[2][k] = max(patch[2][k], p[k])
    print(f"\nZFIGHT {label}: {len(tris)} triangles, gap {GAP}, scale {scale}{'' if ALL else ', visible only'}")
    report = sorted(((k, v) for k, v in pairs.items() if v[0] >= MIN_AREA), key=lambda kv: -kv[1][0])
    for (n1, n2), (area, centre, count) in report:
        c = centre / area
        print(f"  {n1:>22} | {n2:<22} {area:8.2f} sq studs  {count:5d} tris  around ({c.x:.1f}, {c.y:.1f}, {c.z:.1f})")
    if not report:
        print("  none")
    if DETAIL:
        print("  patches (pair, facing, plane, bounds of the faces involved):")
        for (pair, facing, d, _), (area, lo, hi) in sorted(patches.items(), key=lambda kv: -kv[1][0]):
            if area >= MIN_AREA:
                print(f"    {pair[0]}|{pair[1]} {facing} {d:6.1f} {area:7.2f}  x {lo[0]:.1f}..{hi[0]:.1f}  y {lo[1]:.1f}..{hi[1]:.1f}  z {lo[2]:.1f}..{hi[2]:.1f}")
    return report


def main():
    paths = [pathlib.Path(p) for p in ARGS if not p.startswith("--")]
    for p in paths:
        check(p)


if __name__ == "__main__":
    main()
