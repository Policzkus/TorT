"""The front-yard set for the Victorian (Blender 4.4, headless). Every piece is modelled at its own
origin so the game can tile and place it per lot (World/HouseStyles/Victorian.dressLot).

    blender -b --factory-startup --python art/scripts/yard.py -- [--render NAME [--views a,b]] [--export [--only A,B]]

Pieces (studs, origin on the ground, the fence line along X, the street toward -Y):
  FencePanel  - a 4-stud run of wrought iron: rails, spear-topped pickets, a band of scroll rings
  FencePost   - a heavier post with a finial, between panels
  Pillar      - a stone gate pillar with a capstone and a ball
  GateLeaf    - one leaf of an arched double gate, hinge at x = 0, 2.2 studs wide
  Mailbox, MailboxPost - a rusty mailbox on a leaning wooden post
  Grave1, Grave2 - a rounded headstone and a cross, both cracked and mossy
  Flag1, Flag2 - stepping stones for the path
  PicketPanel, PicketPost, PicketGate - a rotten white picket fence (the farmhouse's)
  Tree, Tree2 - gnarled dead trees (two shapes)
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
from victorian import box, frame_matrix, lathe, prism, spear, torus, tube  # noqa: E402

ARGS = V.ARGS
EXPORT = V.ROOT / "export" / "yard"
rng = random.Random(11)

PANEL = 4.0
HEIGHT = 4.6


def flaking(name, paint, amount=0.45, rust_tint=(0.5, 0.4, 0.36, 1)):
    """Old painted metal: dull paint flaking off to rust in patches, more of it near the ground and
    in the corners. Built on the rust texture with the house's grime on top."""
    mat = V.textured(name, "rust_coarse_01", tint=rust_tint, dirt=0.6)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    rust = bsdf.inputs["Base Color"].links[0].from_socket
    rust_rough = bsdf.inputs["Roughness"].links[0].from_socket
    nmap = bsdf.inputs["Normal"].links[0].from_node
    grime = next(n for n in nodes if n.bl_idname == "ShaderNodeCombineColor").outputs["Color"]
    geo = nodes.new("ShaderNodeNewGeometry")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.6
    noise.inputs["Detail"].default_value = 12
    noise.inputs["Roughness"].default_value = 0.7
    links.new(geo.outputs["Position"], noise.inputs["Vector"])
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Position"], sep.inputs["Vector"])
    low = nodes.new("ShaderNodeMapRange")
    low.inputs["From Min"].default_value = 0.0
    low.inputs["From Max"].default_value = 1.6
    low.inputs["To Min"].default_value = 0.22
    low.inputs["To Max"].default_value = 0.0
    links.new(sep.outputs["Z"], low.inputs["Value"])
    add = nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    links.new(noise.outputs["Fac"], add.inputs[0])
    links.new(low.outputs["Result"], add.inputs[1])
    # mask = 1 where the paint is gone
    mask = nodes.new("ShaderNodeMapRange")
    edge = 0.66 - amount * 0.25
    mask.inputs["From Min"].default_value = edge
    mask.inputs["From Max"].default_value = edge + 0.03
    links.new(add.outputs["Value"], mask.inputs["Value"])
    painted = nodes.new("ShaderNodeMix")
    painted.data_type = "RGBA"
    painted.blend_type = "MULTIPLY"
    painted.inputs[0].default_value = 1.0
    painted.inputs[6].default_value = paint
    links.new(grime, painted.inputs[7])
    color = nodes.new("ShaderNodeMix")
    color.data_type = "RGBA"
    links.new(mask.outputs["Result"], color.inputs[0])
    links.new(painted.outputs[2], color.inputs[6])
    links.new(rust, color.inputs[7])
    links.new(color.outputs[2], bsdf.inputs["Base Color"])
    rough = nodes.new("ShaderNodeMix")
    links.new(mask.outputs["Result"], rough.inputs[0])
    rough.inputs[2].default_value = 0.62
    links.new(rust_rough, rough.inputs[3])
    links.new(rough.outputs[0], bsdf.inputs["Roughness"])
    strength = nodes.new("ShaderNodeMapRange")
    strength.inputs["To Min"].default_value = 0.25
    strength.inputs["To Max"].default_value = 1.0
    links.new(mask.outputs["Result"], strength.inputs["Value"])
    links.new(strength.outputs["Result"], nmap.inputs["Strength"])
    return mat


def fence_panel():
    g = "FencePanel"
    box(g, (PANEL, 0.16, 0.16), (PANEL / 2, 0, 0.5), bevel=0.03)
    box(g, (PANEL, 0.12, 0.12), (PANEL / 2, 0, 3.05), bevel=0.02)
    box(g, (PANEL, 0.2, 0.2), (PANEL / 2, 0, 3.75), bevel=0.04)
    n = 8
    for i in range(n):
        x = (i + 0.5) * PANEL / n
        lean = rng.uniform(-0.03, 0.03)
        m = frame_matrix((x, 0, 0), (lean, 0, 0))
        box(g, (0.12, 0.12, 4.1), (0, 0, 2.15), bevel=0.02, matrix=m)
        spear(g, 0, 4.1, matrix=m)
        if i % 2 == 0:
            box(g, (0.2, 0.2, 0.14), (0, 0, 1.2), bevel=0.04, matrix=m)  # collar
    # Scroll rings between the middle and top rails, between the pickets.
    for i in range(1, n):
        torus(g, (i * PANEL / n, 0, 3.4), 0.26, 0.04, Matrix(), segments=14, sides=4)


def fence_post():
    g = "FencePost"
    box(g, (0.32, 0.32, 4.4), (0, 0, 2.2), bevel=0.04)
    box(g, (0.44, 0.44, 0.18), (0, 0, 0.09), bevel=0.04)
    lathe(g, [(0.2, 4.4), (0.24, 4.5), (0.12, 4.62), (0.22, 4.8), (0.22, 4.95), (0.1, 5.1), (0.04, 5.35), (0.0, 5.45)], (0, 0, 0), segments=8)


def pillar():
    g = "Pillar"
    box(g, (1.9, 1.9, 0.6), (0, 0, 0.3), bevel=0.08)
    box(g, (1.5, 1.5, 4.6), (0, 0, 2.9), bevel=0.06)
    box(g, (1.75, 1.75, 0.2), (0, 0, 4.0), bevel=0.04)
    box(g, (1.95, 1.95, 0.35), (0, 0, 5.38), bevel=0.06)
    box(g, (1.6, 1.6, 0.2), (0, 0, 5.65), bevel=0.04)
    lathe(g, [(0.3, 5.75), (0.22, 5.85), (0.5, 6.25), (0.55, 6.5), (0.45, 6.8), (0.0, 7.0)], (0, 0, 0), segments=10)


def gate_leaf():
    """One leaf of a double gate, hinge at x = 0, 2.2 wide; the arch climbs to its peak where the
    two leaves meet. The game uses it twice (the second turned round), so it's the same both sides."""
    g = "GateLeaf"
    w = 2.2

    def arch(x):
        return 3.9 + math.sin(x / w * math.pi / 2) * 0.75

    box(g, (0.2, 0.2, 3.9), (0.1, 0, 2.2), bevel=0.03)  # hinge stile
    lathe(g, [(0.12, 0), (0.16, 0.08), (0.08, 0.2), (0.14, 0.32), (0.0, 0.45)], (0.1, 0, 4.15), segments=6)
    box(g, (0.16, 0.16, 4.5), (w - 0.08, 0, 0.25 + 2.25), bevel=0.03)  # meeting stile
    spear(g, w - 0.08, 4.75)
    box(g, (w, 0.16, 0.16), (w / 2, 0, 0.55), bevel=0.03)
    box(g, (w, 0.12, 0.12), (w / 2, 0, 2.9), bevel=0.02)
    pts = [Vector((i / 6 * w, 0, arch(i / 6 * w))) for i in range(7)]
    for a, b in zip(pts, pts[1:]):
        d = b - a
        box(g, (d.length + 0.02, 0.18, 0.18), (0, 0, 0), bevel=0.03, matrix=frame_matrix(((a + b) / 2).to_tuple(), (0, -math.atan2(d.z, d.x), 0)))
    n = 5
    for i in range(1, n):
        x = i * w / n
        top = arch(x)
        box(g, (0.11, 0.11, top - 0.3), (x, 0, 0.3 + (top - 0.3) / 2), bevel=0.02)
        spear(g, x, top)
    for i in range(1, n - 1):
        torus(g, ((i + 0.5) * w / n, 0, 3.3), 0.2, 0.035, Matrix(), segments=14, sides=4)
    box(g, (math.hypot(w - 0.4, 2.0), 0.1, 0.12), (w / 2, 0, 1.7), rot=(0, -math.atan2(2.0, w - 0.4), 0), bevel=0.02)
    box(g, (0.22, 0.3, 0.45), (w - 0.08, 0, 2.0), bevel=0.04)  # the latch box


def picket(grp, x, height, r, lean=0.0):
    """One pointed picket, x along the fence, leaning a little."""
    m = frame_matrix((x, 0, 0), (r.uniform(-0.03, 0.03) + lean, 0, r.uniform(-0.04, 0.04)))
    box(grp, (0.32, 0.1, height), (0, 0, height / 2 + 0.15), bevel=0.02, matrix=m)
    prism(grp, [(-0.16, 0), (0.16, 0), (0, 0.32)], 0.1, m @ Matrix.Translation((0, -0.05, height + 0.15)))


def picket_panel():
    """A 4-stud run of rotten picket fence: two rails, pointed pickets, two missing and one snapped."""
    g = "PicketPanel"
    r = random.Random(17)
    for z in (0.9, 2.9):
        box(g, (PANEL, 0.18, 0.3), (PANEL / 2, 0.14, z), bevel=0.03)
    n = 8
    for i in range(n):
        x = (i + 0.5) * PANEL / n
        if i in (2, 6):
            continue
        if i == 4:
            box(g, (0.32, 0.1, 1.6), (x, 0, 0.95), rot=(0, 0.15, 0), bevel=0.02)  # snapped off
            continue
        picket(g, x, 3.4 + r.uniform(-0.15, 0.1), r)


def picket_post():
    g = "PicketPost"
    box(g, (0.5, 0.5, 4.0), (0, 0.12, 2.0), bevel=0.04)
    box(g, (0.66, 0.66, 0.18), (0, 0.12, 4.08), bevel=0.04)
    lathe(g, [(0.2, 4.15), (0.24, 4.3), (0.0, 4.6)], (0, 0.12, 0), segments=8)


def picket_gate():
    """One leaf of a picket gate, hinge at x = 0, 2.2 wide, with a Z brace; the second leaf is the
    same mesh turned round."""
    g = "PicketGate"
    w = 2.2
    r = random.Random(19)
    for z in (0.8, 2.9):
        box(g, (w, 0.16, 0.28), (w / 2, 0.14, z), bevel=0.03)
    box(g, (math.hypot(w - 0.3, 2.0), 0.14, 0.24), (w / 2, 0.14, 1.85), rot=(0, -math.atan2(2.0, w - 0.3), 0), bevel=0.03)
    for i in range(5):
        picket(g, 0.2 + i * (w - 0.4) / 4, 3.5 - abs(i - 2) * 0.12, r)


def mailbox():
    lean = frame_matrix((0, 0, 0), (math.radians(4), math.radians(-7), 0))
    box("MailboxPost", (0.36, 0.36, 3.5), (0, 0, 1.75), bevel=0.04, matrix=lean)
    box("MailboxPost", (0.9, 0.5, 0.18), (0, 0, 3.4), bevel=0.03, matrix=lean)
    top = lean @ Matrix.Translation((0, 0, 3.5))
    box("Mailbox", (0.9, 1.9, 0.55), (0, 0, 0.28), bevel=0.03, matrix=top)
    lathe("Mailbox", [(0.45, 0), (0.45, 1.9), (0.0, 1.9)], (0, 0, 0), segments=12, matrix=top @ Matrix.Translation((0, -0.95, 0.55)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    box("Mailbox", (0.06, 0.6, 0.5), (0.5, 0.3, 0.9), rot=(0, 0, 0), matrix=top)  # the flag, down
    box("Mailbox", (0.06, 0.25, 0.25), (0.5, 0.55, 1.15), matrix=top)


def flagstones():
    """Two irregular stepping stones for the path, sunk into the lawn with chipped edges."""
    for name, seed in (("Flag1", 3), ("Flag2", 8)):
        r = random.Random(seed)
        pts = []
        n = 9
        for i in range(n):
            a = 2 * math.pi * i / n + r.uniform(-0.15, 0.15)
            k = r.uniform(0.82, 1.0)
            pts.append((math.cos(a) * 1.1 * k, math.sin(a) * 0.85 * k))
        prism(name, pts, 0.32, frame_matrix((0, 0, -0.16), (math.pi / 2, 0, 0)), bevel=0.07)


def text_cutter(body, size, loc, depth):
    """Raised letters standing in the XZ plane (facing -Y), as a boolean cutter for engraving."""
    cu = bpy.data.curves.new("Text", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = depth
    obj = bpy.data.objects.new("Text", cu)
    bpy.context.scene.collection.objects.link(obj)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    bpy.data.objects.remove(obj, do_unlink=True)
    me.transform(Matrix.Translation(Vector(loc)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    cutter = bpy.data.objects.new("TextCut", me)
    V.group("_cutters").objects.link(cutter)
    return cutter


def graves():
    # A rounded headstone with R.I.P. cut into it, a chipped shoulder and a crack, sunk and leaning.
    arc = [(-0.9, 0), (0.9, 0), (0.9, 2.0)]
    for i in range(1, 8):
        a = math.pi * i / 8
        arc.append((math.cos(a) * 0.9, 2.0 + math.sin(a) * 0.55))
    arc.append((-0.9, 2.0))
    stone = prism("Grave1", arc, 0.42, frame_matrix((0, -0.21, 0)), bevel=0.04)
    cutters = [
        text_cutter("R.I.P.", 0.42, (0, -0.21, 1.72), 0.07),
        box("_cutters", (0.9, 0.06, 0.04), (0, -0.21, 1.38)),  # a rule under the letters
        box("_cutters", (0.7, 1.0, 0.6), (0.95, 0, 2.15), rot=(0.4, 0.7, 0.9)),  # chipped shoulder
    ]
    # A hairline crack wandering down from the chip.
    x, z = 0.62, 1.95
    for i in range(7):
        step = rng.uniform(0.18, 0.3)
        a = rng.uniform(-0.75, 0.35)
        nx, nz = x + math.sin(a) * step, z - math.cos(a) * step
        width = 0.035 * (1 - i / 9)
        cutters.append(box("_cutters", (width, 0.2, step + width), ((x + nx) / 2, -0.25, (z + nz) / 2), rot=(0, -a, 0)))
        x, z = nx, nz
    V.cut(stone, cutters)
    stone.matrix_world = frame_matrix((0, 0, -0.15), (math.radians(-6), math.radians(4), 0))
    box("Grave1", (2.2, 0.9, 0.3), (0, 0, 0.08), bevel=0.05)
    # A stone cross on a plinth, leaning the other way, one arm broken short.
    m = frame_matrix((0, 0, -0.1), (math.radians(8), math.radians(-5), 0))
    box("Grave2", (0.45, 0.45, 3.0), (0, 0, 1.5), bevel=0.05, matrix=m)
    arms = box("Grave2", (1.6, 0.45, 0.45), (0, 0, 2.2), bevel=0.05)
    V.cut(arms, [box("_cutters", (0.5, 0.8, 0.5), (0.8, 0, 2.42), rot=(0.3, 0.6, 0.4))])  # a chipped arm
    arms.matrix_world = m
    box("Grave2", (1.2, 1.0, 0.35), (0, 0, 0.17), bevel=0.05, matrix=m)
    box("Grave2", (0.9, 0.75, 0.2), (0, 0, 0.42), bevel=0.04, matrix=m)


def tree(grp="Tree", seed=11, height=9.0, lean=(0.12, 0.06)):
    """A gnarled dead tree: a twisting trunk that forks into crooked, tapering limbs and bare twigs,
    with roots clawing into the ground."""
    rng.seed(seed)

    def grow(base, d, length, radius, depth, segs):
        pts, radii = [base], [radius]
        wander = 0.25 + 0.12 * (3 - depth)
        for i in range(segs):
            d = (d + Vector((rng.uniform(-wander, wander), rng.uniform(-wander, wander), rng.uniform(-0.05, 0.18)))).normalized()
            pts.append(pts[-1] + d * length / segs)
            t = (i + 1) / segs
            radii.append(max(0.03, radius * (1 - 0.55 * t)) if depth > 0 or i < segs - 1 else 0.03)
        tube(grp, pts, radii, sides=1 if radius > 0.18 else 0)
        if depth == 0:
            return
        # Two limbs fork from the tip, and a few more break out lower down, each turned away
        # from the last so the crown spreads all round.
        kids = 2 + (rng.randint(1, 2) if depth > 1 else 0)
        spin = rng.uniform(0, 2 * math.pi)
        for k in range(kids):
            i = segs if k < 2 else rng.randint(max(2, segs // 2), segs - 1)
            spin += 2 * math.pi / kids + rng.uniform(-0.5, 0.5)
            out = Vector((math.cos(spin), math.sin(spin), 0))
            nd = (d * 0.55 + out * 0.85 + Vector((0, 0, rng.uniform(0.05, 0.45)))).normalized()
            start = pts[i - 1].lerp(pts[i], 0.85)
            scale = 0.85 if k < 2 else 0.6
            grow(start, nd, length * rng.uniform(0.55, 0.75) * scale ** 0.5, radii[i] * scale, depth - 1, max(3, segs - 1))

    for i in range(6):
        a = i * 2 * math.pi / 6 + rng.uniform(-0.25, 0.25)
        out = Vector((math.cos(a), math.sin(a), 0))
        reach = rng.uniform(1.8, 2.8)
        tube(grp, [Vector((0, 0, 1.8)), out * 0.9 + Vector((0, 0, 0.7)), out * reach * 0.7 + Vector((0, 0, 0.1)), out * reach + Vector((0, 0, -0.5))],
             [0.55, 0.45, 0.25, 0.08])
    grow(Vector((0, 0, -0.4)), Vector((lean[0], lean[1], 1)), height, 1.05, 4, 6)


def build():
    V.reset()
    V.build_materials()
    M, U = V.MATERIALS, V.UV_RULES
    iron = flaking("Iron", (0.028, 0.028, 0.03, 1), amount=0.4)
    for g in ("FencePanel", "FencePost", "GateLeaf"):
        M[g] = iron
        U[g] = (2.0, "vertical")
    picket = V.textured("Picket", "distressed_painted_planks", tint=(1.3, 1.28, 1.2, 1), dirt=0.9, moss=0.25)
    for g in ("PicketPanel", "PicketPost", "PicketGate"):
        M[g] = picket
        U[g] = (3.0, "vertical")
    M["Pillar"] = V.textured("PillarStone", "rustic_stone_wall", tint=(0.62, 0.65, 0.7, 1), dirt=0.6, moss=0.35)
    U["Pillar"] = (4.0, "vertical")
    M["Mailbox"] = flaking("MailboxMetal", (0.045, 0.06, 0.05, 1), amount=0.6)
    U["Mailbox"] = (2.0, "vertical")
    M["MailboxPost"] = V.textured("MailboxPost", "weathered_planks", tint=(0.75, 0.72, 0.68, 1), dirt=0.5)
    U["MailboxPost"] = (3.0, "vertical")
    stone = V.textured("GraveStone", "concrete_wall_006", tint=(1.0, 1.0, 1.0, 1), dirt=0.45, moss=0.35)
    M["Grave1"] = M["Grave2"] = stone
    U["Grave1"] = U["Grave2"] = (3.0, "vertical")
    M["Flag1"] = M["Flag2"] = V.textured("Flagstone", "concrete_wall_006", tint=(0.48, 0.5, 0.5, 1), dirt=0.6, moss=0.8)
    U["Flag1"] = U["Flag2"] = (2.5, "vertical")
    M["Tree"] = M["Tree2"] = V.textured("Bark", "bark_willow", tint=(0.6, 0.6, 0.64, 1), dirt=0.5, moss=0.25)
    U["Tree"] = U["Tree2"] = (3.0, "vertical")
    fence_panel()
    fence_post()
    pillar()
    gate_leaf()
    picket_panel()
    picket_post()
    picket_gate()
    mailbox()
    graves()
    flagstones()
    tree("Tree", seed=11)
    tree("Tree2", seed=5, height=7.5, lean=(-0.25, 0.1))
    merged = {}
    for name in list(V.GROUPS):
        if name.startswith("_"):
            continue
        obj = V.merge_group(name)
        if obj:
            merged[name] = obj
    tris = {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in merged.items()}
    print("TRIANGLES", tris)
    return merged


def layout_for_render(merged):
    """Spread the pieces out for a preview render."""
    spots = {
        "FencePanel": (-8, 0, 0), "FencePost": (-3.8, 0, 0), "Pillar": (-1.5, 0, 0), "GateLeaf": (0.4, 0, 0), "PicketPanel": (-8, -6, 0), "PicketPost": (-3.8, -6, 0), "PicketGate": (-3.2, -6, 0),
        "Mailbox": (7.5, -1, 0), "MailboxPost": (7.5, -1, 0), "Grave1": (10.5, 1, 0), "Grave2": (13, 1, 0), "Tree": (19, 3, 0), "Tree2": (30, 6, 0), "Flag1": (1, -3, 0), "Flag2": (3.6, -3.5, 0),
    }
    for name, obj in merged.items():
        if name in spots:
            obj.location = spots[name]


VIEWS = {
    "all": ((4, -24, 7), (5, 2, 3)),
    "graves": ((10.5, -6.5, 2.4), (11.6, 1, 1.4)),
    "fence": ((-3, -8, 3.2), (-3, 0, 2.6)),
    "picket": ((-4, -14, 3.2), (-4, -6, 2.2)),
    "tree": ((19, -20, 6), (19, 3, 8)),
    "tree2": ((30, -17, 6), (30, 6, 7)),
}


# Small pieces get a 512 atlas; the trees, the pillar and the lettered headstone keep 1024.
ATLAS = {n: 512 for n in ("FencePanel", "FencePost", "GateLeaf", "Mailbox", "MailboxPost", "Grave2", "Flag1", "Flag2", "PicketPanel", "PicketPost", "PicketGate")}


if __name__ == "__main__":
    merged = build()
    if "--export" in ARGS:
        import export_victorian

        only = set(ARGS[ARGS.index("--only") + 1].split(",")) if "--only" in ARGS else None
        export_victorian.export(merged, EXPORT, "Yard.fbx", only=only, sizes=ATLAS)
    if "--render" in ARGS:
        layout_for_render(merged)
        cam, presets = V.setup_render("yard", night="--night" in ARGS)
        scene = bpy.context.scene
        scene.camera = cam
        name = ARGS[ARGS.index("--render") + 1]
        views = ARGS[ARGS.index("--views") + 1].split(",") if "--views" in ARGS else ["all"]
        for v in views:
            loc, target = VIEWS[v]
            cam.location = loc
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = str(V.RENDERS / f"{name}_{v}.png")
            bpy.ops.render.render(write_still=True)
            print("RENDERED", scene.render.filepath)
