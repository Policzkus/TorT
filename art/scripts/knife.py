"""The Knifer's knife (Blender 4.4, headless, the houses' pipeline): a big old butcher's knife, the
blade spotted with rust and dark along the edge, a dark wooden handle held on with three brass
rivets, a steel bolster between them.

    blender -b --factory-startup --python art/scripts/knife.py -- [--render NAME [--day]] [--export]

Built standing up with the handle at the bottom: the grip's middle (Mark_Grip) at the origin, the
blade up +Z, its edge toward -Y. In Roblox (x, y, z) -> (-x, z, y) the blade is +Y and the edge -Z.
Exports art/export/knife/Knife.fbx; tools/setup_knife.luau files it as ReplicatedStorage.Assets.Props.Knife.
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
import lobby  # noqa: E402  (rusted)

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "knife"

HANDLE = 0.62  # studs, the grip's length
BLADE = 1.55  # from the bolster to the tip
WIDTH = 0.36  # the blade's height at its heel
THICK = 0.035


def blade():
    """The blade's outline (y across: the spine at +, the edge at -; z along it), its edge ground
    thin, a drop to the tip; one faint fuller line along the spine."""
    pts = [(WIDTH * 0.32, 0.0), (WIDTH * 0.36, BLADE * 0.7), (WIDTH * 0.2, BLADE * 0.93), (0.0, BLADE), (-WIDTH * 0.42, BLADE * 0.86),
           (-WIDTH * 0.64, BLADE * 0.55), (-WIDTH * 0.66, BLADE * 0.2), (-WIDTH * 0.6, 0.0)]
    bm = bmesh.new()
    rings = []
    for x in (-THICK / 2, THICK / 2):
        rings.append([bm.verts.new((x, y, z + HANDLE / 2 + 0.05)) for y, z in pts])  # from the bolster up
    n = len(pts)
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((rings[0][k], rings[0][j], rings[1][j], rings[1][k]))
    # The edge ground thin: the edge-side verts pulled in to the middle.
    for ring in rings:
        for v in ring:
            if v.co.y < -WIDTH * 0.3:
                v.co.x *= 0.15
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    V.mesh_object("Blade", bm, "KnifeBlade")
    # The edge, dark where it's been used.
    base = HANDLE / 2 + 0.05
    V.tube("KnifeDark", [Vector((0, -WIDTH * 0.6, base + 0.04)), Vector((0, -WIDTH * 0.65, base + BLADE * 0.35)),
                         Vector((0, -WIDTH * 0.52, base + BLADE * 0.7)), Vector((0, -WIDTH * 0.25, base + BLADE * 0.92))],
           [0.012, 0.016, 0.012, 0.006], sides=1)


def handle():
    """The grip: two wooden scales round the tang, rounded, swelling toward the butt; the bolster;
    three rivets through it."""
    pts = [(0.1, -HANDLE / 2), (0.13, -HANDLE / 2 + 0.06), (0.12, 0.0), (0.105, HANDLE / 2 - 0.04), (0.1, HANDLE / 2)]
    bm = bmesh.new()
    segs = 16
    rings = []
    for r, z in pts:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            ring.append(bm.verts.new((math.cos(a) * r * 0.55, math.sin(a) * r * 1.05 - 0.035, z)))  # flattened, toward the spine
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    V.mesh_object("Handle", bm, "KnifeHandle")
    box("KnifeBlade", (THICK * 2.6, WIDTH * 0.95, 0.07), (0, -0.04, HANDLE / 2 + 0.02), bevel=0.012)  # the bolster
    for z in (-0.19, 0.0, 0.19):
        m = frame_matrix((-0.075, -0.03, z), (0, math.pi / 2, 0))
        lathe("KnifeRivet", [(0.028, 0.0), (0.028, 0.15), (0.0, 0.155)], (0, 0, 0), segments=10, matrix=m)


WHAT = ("KnifeBlade", "KnifeDark", "KnifeHandle", "KnifeRivet")


def build():
    V.reset()
    V.build_materials()
    M, U = V.MATERIALS, V.UV_RULES
    steel = V.textured("KnifeBlade", "concrete_wall_006", paint=(0.62, 0.62, 0.63, 1), rough=0.38, dirt=0.75, metal=0.85, bump=0.2)
    lobby.rusted(steel, 0.55, scale=0.05)
    M["KnifeBlade"], U["KnifeBlade"] = steel, (0.6, "vertical")
    M["KnifeDark"] = V.textured("KnifeDark", None, tint=(0.09, 0.02, 0.015, 1), rough=0.45)
    M["KnifeHandle"] = V.textured("KnifeHandle", "dark_wooden_planks", tint=(0.42, 0.3, 0.22, 1), rough=0.6, dirt=0.8)
    U["KnifeHandle"] = (0.5, "vertical")
    M["KnifeRivet"] = V.textured("KnifeRivet", None, tint=(0.5, 0.36, 0.14, 1), rough=0.35, metal=1.0)
    blade()
    handle()
    box("Mark_Grip", (0.05, 0.05, 0.05), (0, 0, 0))
    merged = {}
    for name in list(V.GROUPS):
        obj = V.merge_group(name)
        if obj:
            obj.name = obj.data.name = name
            merged[name] = obj
    for name in ("KnifeHandle", "KnifeRivet", "KnifeDark"):
        obj = merged.get(name)
        if obj:
            for o in bpy.context.scene.objects:
                o.select_set(False)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    print("TRIANGLES", {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()})
    return merged


FLAT = {"KnifeDark", "KnifeRivet", "Mark_Grip"}


def render(name):
    day = "--day" in ARGS
    cam, _ = V.setup_render("knife", night=not day)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1400, 900
    for o in [o for o in bpy.data.objects if o.type == "LIGHT" and o.name in ("Lantern", "Inside")]:
        bpy.data.objects.remove(o, do_unlink=True)
    for obj in bpy.data.objects:
        if obj.name.startswith("Mark_") or obj.name == "Ground":
            obj.hide_render = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.26, 0.3, 1)  # something for the steel to show
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "AREA"))
    key.data.energy = 120
    key.data.size = 2
    key.location = (-2.5, -2.5, 2.5)
    key.rotation_euler = (Vector((0, 0, 0.6)) - key.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(key)
    rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", "POINT"))
    rim.data.energy = 60
    rim.data.color = (1.0, 0.6, 0.4)
    rim.location = (1.5, 2.0, 1.5)
    scene.collection.objects.link(rim)
    cam.location = (-4.2, -3.0, 1.6)
    cam.data.lens = 45
    target = Vector((0, 0, 0.95))
    cam.rotation_euler = (target - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = str(V.RENDERS / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    merged = build()
    if "--render" in ARGS:
        render(ARGS[ARGS.index("--render") + 1])
    if "--export" in ARGS:
        import export_victorian

        export_victorian.export(merged, EXPORT, "Knife.fbx", flat=FLAT, sizes={"KnifeBlade": 512, "KnifeHandle": 512})
