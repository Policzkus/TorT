"""Halloween decorations for "Decorated" houses (HouseVisualController hangs them on the client).
Blender 4.4, headless, same pipeline as the house and the yard set.

    blender -b --factory-startup --python art/scripts/decor.py -- [--render NAME] [--export]

Pieces share one origin (tools/setup_decor.luau puts every pivot there):
  Garland, BulbsA/B/C - a string of old C7 bulbs drooping between two hooks 3.4 studs apart, along X,
                        hooks at z = 0 (the origin is the middle of the span, at hook height). The
                        bulbs are three meshes so the game can colour each set (orange, purple, green).
  PumpkinPile, PumpkinPileGlow - a big carved jack-o'-lantern with three small pumpkins round it,
                        standing on the ground at the origin, face toward -Y (the street).
"""

import math
import pathlib
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import victorian as V  # noqa: E402
from victorian import box, frame_matrix, lathe, pumpkin, tube  # noqa: E402

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "decor"
rng = random.Random(31)

SPAN = 3.4
SAG = 0.75
BULBS = 6


def wire_point(x):
    t = 2 * x / SPAN
    return Vector((x, 0, -SAG * (1 - t * t)))


def garland():
    pts = [wire_point(-SPAN / 2 + SPAN * i / 16) for i in range(17)]
    tube("Garland", pts, [0.035] * len(pts), sides=0)
    for x in (-SPAN / 2, SPAN / 2):
        box("Garland", (0.07, 0.07, 0.16), (x, 0, -0.08))  # the hooks it hangs from
    for i in range(BULBS):
        x = -SPAN / 2 + (i + 0.5) * SPAN / BULBS
        p = wire_point(x)
        # Swinging only along the wire keeps the garland symmetric across it (setup_decor finds
        # the origin from that).
        tilt = frame_matrix(p.to_tuple(), (0, rng.uniform(-0.3, 0.3), 0))
        # Socket on the wire, then the bulb hanging from it, pointing down.
        lathe("Garland", [(0.075, -0.14), (0.075, 0.0), (0.05, 0.03)], (0, 0, 0), segments=8, matrix=tilt)
        bulb = [(0.07, -0.14), (0.11, -0.2), (0.12, -0.28), (0.1, -0.38), (0.05, -0.47), (0.0, -0.5)]
        lathe("Bulbs" + "ABC"[i % 3], bulb, (0, 0, 0), segments=10, matrix=tilt)


def pile():
    g, glow = "PumpkinPile", "PumpkinPileGlow"
    pumpkin((0, 0, 0), 0.95, 0, carved=True, grp=g, glow=glow, stem=g, tall=1.2)
    pumpkin((1.3, 0.35, 0), 0.5, math.radians(40), grp=g, stem=g, tall=1.1)
    pumpkin((-1.15, 0.55, 0), 0.42, math.radians(-25), grp=g, stem=g)
    pumpkin((0.75, -0.95, 0), 0.34, math.radians(15), grp=g, stem=g, tall=1.15)


def build():
    V.reset()
    V.build_materials()
    M, U = V.MATERIALS, V.UV_RULES
    M["PumpkinPile"] = V.textured("PumpkinPile", "concrete_wall_006", paint=(0.95, 0.38, 0.04, 1), rough=0.7, dirt=0.45, moss=0.15)
    U["PumpkinPile"] = U["Pumpkin"]
    M["PumpkinPileGlow"] = M["PumpkinGlow"]
    M["Garland"] = M["Iron"]
    for name, color in (("BulbsA", (1.0, 0.45, 0.05, 1)), ("BulbsB", (0.55, 0.2, 1.0, 1)), ("BulbsC", (0.4, 1.0, 0.25, 1))):
        M[name] = V.textured(name, None, tint=(0.2, 0.2, 0.2, 1), rough=0.3, emission=(color, 3.0))
    garland()
    pile()
    for obj in list(V.GROUPS.get("_cutters", bpy.data.collections.new("_none")).objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    merged = {}
    for name in list(V.GROUPS):
        if name.startswith("_"):
            continue
        obj = V.merge_group(name)
        if obj:
            merged[name] = obj
    # Smooth shading on the round things.
    for name in ("PumpkinPile", "BulbsA", "BulbsB", "BulbsC"):
        if name in merged:
            for poly in merged[name].data.polygons:
                poly.use_smooth = True
    print("TRIANGLES", {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()})
    return merged


FLAT = {"Garland", "BulbsA", "BulbsB", "BulbsC", "PumpkinPileGlow"}

if __name__ == "__main__":
    merged = build()
    if "--render" in ARGS:
        # Hang the garland at porch height beside the pile for the preview.
        for name in ("Garland", "BulbsA", "BulbsB", "BulbsC"):
            merged[name].location = (0, 0, 4.5)
        cam, _ = V.setup_render("decor", night="--night" in ARGS)
        scene = bpy.context.scene
        scene.camera = cam
        cam.location = (1.5, -7.5, 3.2)
        cam.rotation_euler = (Vector((0, 0, 2.2)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
        if "--night" in ARGS:
            for o in [o for o in bpy.data.objects if o.type == "LIGHT" and o.name in ("Lantern", "Inside")]:
                bpy.data.objects.remove(o, do_unlink=True)
            glow = bpy.data.objects.new("PumpkinCandle", bpy.data.lights.new("PumpkinCandle", "POINT"))
            glow.data.energy = 120
            glow.data.color = (1.0, 0.55, 0.2)
            glow.location = (0, 0, 0.6)
            scene.collection.objects.link(glow)
        scene.render.filepath = str(V.RENDERS / f"{ARGS[ARGS.index('--render') + 1]}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)
    if "--export" in ARGS:
        import export_victorian

        export_victorian.export(merged, EXPORT, "Decor.fbx", flat=FLAT)
