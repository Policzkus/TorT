"""Checks a Blender house's invisible colliders against the model you see (Blender 4.4, headless).

    blender -b --factory-startup --python art/scripts/colcheck.py -- victorian|farmhouse|mansard [--step 0.25]

The game walks on the colliders (World/BlenderLot builds them from the house data), never on the
meshes, so wherever the two disagree something feels wrong. Over a grid across the lot it casts a
vertical ray through the model (solid where a ray goes in through an upward face and out through a
downward one) and through the collider boxes, and reports patches of:

  FLOOR  - the floor you stand on (the top collider below porch height) isn't where the visible
           floor is: you'd float over it, sink into it, or walk on air over a hole;
  WALL   - a collider stands where nothing is visible (an invisible wall or bump);
  THROUGH- something solid you can see, waist high, with no collider: you walk through it.

Each patch prints its bounds in Blender coordinates and what the model has there, and a top-down
map is written to art/renders/colcheck_<style>.png (street at the bottom): grey is the floor you
walk on (lighter is higher), dark red where you'd walk on air over a lower floor, blue where the
visible floor is higher than the one you walk on, magenta an invisible wall, yellow something you
walk through, and the house's own block colliders dark.
"""

import importlib
import math
import pathlib
import sys
from collections import defaultdict

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
STYLE = ARGS[0] if ARGS else "victorian"
STEP = float(ARGS[ARGS.index("--step") + 1]) if "--step" in ARGS else 0.25
# Meshes that don't stop anyone (or can't be reached): glass sits in walls, glows, curtains behind
# windows, vines and cresting are thin, the doors swing.
SOFT = ("Glass", "LanternGlow", "PumpkinGlow", "Curtain", "Vines", "Silhouette", "Interior", "FrontDoor", "BackDoor",
        "Brass_FrontDoor", "Brass_BackDoor", "CellarDoorL", "CellarDoorR", "Canvas", "Pale")
WAIST = (0.8, 3.6)  # heights above the floor where something solid should stop you
STEP_UP = 0.6  # higher than this above the floor is an obstacle, not a step


def model_tree():
    verts, polys, owners = [], [], []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.name.split(".")[0] in SOFT:
            continue
        me = obj.evaluated_get(depsgraph).to_mesh()
        me.calc_loop_triangles()
        mw = obj.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in me.vertices]
        for tri in me.loop_triangles:
            polys.append(tuple(base + i for i in tri.vertices))
            owners.append(obj.name.split(".")[0])
        obj.evaluated_get(depsgraph).to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys), owners


def column(tree, owners, x, y, top=80.0):
    """Solid intervals [(z0, z1, owner)] of the model along the vertical line at (x, y)."""
    hits = []
    z = top
    origin = Vector((x, y, top))
    down = Vector((0, 0, -1))
    while True:
        hit, normal, index, dist = tree.ray_cast(origin, down, z + 1.0)
        if hit is None:
            break
        hits.append((hit.z, normal.z > 0, owners[index]))
        origin = hit + down * 1e-4
        z = origin.z
        if len(hits) > 60:
            break
    # Going down: an upward face is a top (solid below it), a downward face a bottom.
    solids = []
    depth, top_z, owner = 0, None, None
    for hz, facing_up, name in hits:
        if facing_up:
            if depth == 0:
                top_z, owner = hz, name
            depth += 1
        else:
            depth = max(0, depth - 1)
            if depth == 0 and top_z is not None:
                solids.append((hz, top_z, owner))
                top_z = None
    if depth > 0 and top_z is not None:
        solids.append((0.0, top_z, owner))
    return solids


def collider_column(boxes, x, y):
    out = []
    for size, centre, yaw in boxes:
        a = math.radians(yaw)
        dx, dy = x - centre.x, y - centre.y
        lx = dx * math.cos(a) + dy * math.sin(a)
        ly = -dx * math.sin(a) + dy * math.cos(a)
        if abs(lx) <= size.x / 2 and abs(ly) <= size.y / 2:
            out.append((centre.z - size.z / 2, centre.z + size.z / 2))
    return out


def floor_at(intervals, below):
    """The top of the highest solid starting below `below` (the ground, 0, if none)."""
    best = 0.0
    for z0, z1, *_ in intervals:
        if z0 < below and z1 <= below + STEP_UP and z1 > best:
            best = z1
    return best


def covers(intervals, lo, hi):
    return any(z0 < hi and z1 > lo for z0, z1, *_ in intervals)


def patches(cells):
    """Connected patches of flagged cells: [(count, (x0, x1, y0, y1), notes)]."""
    seen = set()
    out = []
    for cell in cells:
        if cell in seen:
            continue
        stack, members = [cell], []
        seen.add(cell)
        while stack:
            c = stack.pop()
            members.append(c)
            i, j = c
            for n in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)):
                if n in cells and n not in seen:
                    seen.add(n)
                    stack.append(n)
        xs = [m[0] * STEP for m in members]
        ys = [m[1] * STEP for m in members]
        notes = defaultdict(int)
        for m in members:
            notes[cells[m]] += 1
        out.append((len(members), (min(xs), max(xs), min(ys), max(ys)), dict(notes)))
    return sorted(out, key=lambda p: -p[0])


def main():
    module = importlib.import_module(STYLE)
    built = module.build()
    boxes = module.colliders() if STYLE == "victorian" else [(Vector(s), Vector(c), yaw) for s, c, yaw in module.D.colliders]
    porch = module.FOUND + 0.9  # floors below this count (porches, steps, stoops)
    tree, owners = model_tree()
    lo = Vector((-24, -18))
    hi = Vector((24, 32))
    floors, walls, throughs = {}, {}, {}
    pixels = {}
    i0, i1 = int(lo.x / STEP), int(hi.x / STEP)
    j0, j1 = int(lo.y / STEP), int(hi.y / STEP)
    for i in range(i0, i1 + 1):
        for j in range(j0, j1 + 1):
            x, y = (i + 0.5) * STEP, (j + 0.5) * STEP  # cell centres, off the boxes' edges
            model = column(tree, owners, x, y)
            boxes_here = collider_column(boxes, x, y)
            # Inside the house's own block colliders nobody walks: skip those cells.
            if any(z1 - z0 > 8 and z0 < 0.5 for z0, z1 in boxes_here):
                pixels[(i, j)] = (0.08, 0.08, 0.1)
                continue
            seen_floor = floor_at(model, porch)
            walk_floor = floor_at(boxes_here, porch)
            g = 0.25 + 0.15 * walk_floor
            pixels[(i, j)] = (g, g, g)
            if seen_floor < walk_floor - 0.3:
                pixels[(i, j)] = (0.55, 0.05, 0.05)
            elif seen_floor > walk_floor + 0.3:
                pixels[(i, j)] = (0.1, 0.3, 0.9)
            band = (walk_floor + WAIST[0], walk_floor + WAIST[1])
            blocked = covers(boxes_here, *band)  # an obstacle cell: its rails aren't floors
            if blocked:
                pixels[(i, j)] = (0.35, 0.1, 0.35)
            elif abs(seen_floor - walk_floor) > 0.3:
                what = next((o for z0, z1, o in model if abs(z1 - seen_floor) < 0.05), "ground")
                floors[(i, j)] = f"see {seen_floor:.2f} ({what}) walk {walk_floor:.2f}"
            model_band = [m for m in model if m[0] < band[1] and m[1] > band[0]]
            if covers(boxes_here, *band) and not model_band:
                walls[(i, j)] = "collider, nothing visible"
                pixels[(i, j)] = (0.9, 0.1, 0.9)
            if model_band and not covers(boxes_here, *band):
                throughs[(i, j)] = model_band[0][2]
                pixels[(i, j)] = (1.0, 0.85, 0.1)
    # The map: 4 pixels a cell, street (-y) at the bottom, x mirrored like the game sees it from
    # the street (Blender +x is to the viewer's right when facing the house).
    w, h = (i1 - i0 + 1) * 4, (j1 - j0 + 1) * 4
    img = bpy.data.images.new("colcheck", w, h, alpha=False)
    data = [0.0] * (w * h * 4)
    for (i, j), (r, g, b) in pixels.items():
        for dx in range(4):
            for dy in range(4):
                px, py = (i - i0) * 4 + dx, (j - j0) * 4 + dy
                k = (py * w + px) * 4
                data[k : k + 4] = [r, g, b, 1.0]
    # grid lines every 5 studs
    for i in range(i0, i1 + 1):
        if (i * STEP) % 5 == 0:
            for py in range(h):
                k = (py * w + (i - i0) * 4) * 4
                data[k : k + 4] = [0.0, 0.5, 0.0, 1.0]
    for j in range(j0, j1 + 1):
        if (j * STEP) % 5 == 0:
            for px in range(w):
                k = (((j - j0) * 4) * w + px) * 4
                data[k : k + 4] = [0.0, 0.5, 0.0, 1.0]
    img.pixels = data
    path = pathlib.Path(__file__).resolve().parents[1] / "renders" / f"colcheck_{STYLE}.png"
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    print("MAP", path)
    for label, cells in (("FLOOR", floors), ("WALL", walls), ("THROUGH", throughs)):
        found = [p for p in patches(cells) if p[0] >= 3]
        print(f"\n{label}: {len(found)} patches")
        for count, (x0, x1, y0, y1), notes in found[:25]:
            top = sorted(notes.items(), key=lambda kv: -kv[1])[:3]
            print(f"  {count * STEP * STEP:6.2f} sq  x {x0:6.2f}..{x1:6.2f}  y {y0:6.2f}..{y1:6.2f}  {top}")


if __name__ == "__main__":
    main()
