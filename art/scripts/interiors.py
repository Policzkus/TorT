"""The rooms behind the Victorian's windows: real geometry, so they have depth and parallax as you
walk past, take real lamplight when the game switches a room on, and show their furniture in a
flashlight. Built into the house mesh by victorian.build() (which passes itself in as V).

Each room is a box just inside the house walls: wallpapered walls (window and door openings cut
through), floorboards, a plaster ceiling with a hanging lamp, skirting and a picture rail, and its
own furniture. The tower has a round (octagonal) room on each floor; the bay gable has an attic.

Also writes src/server/World/HouseStyles/VictorianRooms.luau: where each room's lamp hangs (and
which rooms have a figure that the game may keep), so the game can light rooms per house.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

U = 3.8  # studs per metre: furniture is modelled in metres (the front door is 2 m = 7.6 studs)
WALL = 0.1  # wallpaper slab thickness
rng = random.Random(41)


# Materials ---------------------------------------------------------------------------------------
def _node(nodes, kind, **inputs):
    n = nodes.new(kind)
    for key, value in inputs.items():
        n.inputs[key].default_value = value
    return n


def wallpaper(V, name, ground, accent, motif, kind):
    """Old wallpaper in the 'Tile' UV (1 unit = 1 stud): a printed pattern, water stains running
    down from the ceiling, patches peeled back to plaster, grime along the skirting."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "Tile"
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], sep.inputs["Vector"])

    def math_node(op, a, b=None, clamp=False):
        n = nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                links.new(v, n.inputs[i])
        return n.outputs[0]

    u, v = sep.outputs["X"], sep.outputs["Y"]
    if kind == "stripes":
        # Wide ground stripe, a narrow accent stripe and a pinstripe, every 1.1 studs.
        cell = math_node("FRACT", math_node("DIVIDE", u, 1.1))
        accent_mask = math_node("MULTIPLY", math_node("GREATER_THAN", cell, 0.62), math_node("LESS_THAN", cell, 0.86))
        pin = math_node("MULTIPLY", math_node("GREATER_THAN", cell, 0.93), math_node("LESS_THAN", cell, 0.96))
        # Little diamonds down the wide stripe.
        du = math_node("ABSOLUTE", math_node("SUBTRACT", cell, 0.31))
        dv = math_node("ABSOLUTE", math_node("SUBTRACT", math_node("FRACT", math_node("DIVIDE", v, 0.7)), 0.5))
        diamond = math_node("LESS_THAN", math_node("ADD", math_node("MULTIPLY", du, 2.2), dv), 0.16)
        motif_mask = math_node("MAXIMUM", diamond, pin)
    elif kind == "damask":
        # Medallions on a half-drop grid, each a ring round a dot, with a fainter lattice.
        gu = math_node("DIVIDE", u, 1.3)
        row = math_node("FLOOR", math_node("DIVIDE", v, 1.6))
        shift = math_node("MULTIPLY", math_node("MODULO", row, 2.0), 0.5)
        cu = math_node("SUBTRACT", math_node("FRACT", math_node("ADD", gu, shift)), 0.5)
        cv = math_node("SUBTRACT", math_node("FRACT", math_node("DIVIDE", v, 1.6)), 0.5)
        dist = math_node("SQRT", math_node("ADD", math_node("MULTIPLY", cu, cu), math_node("MULTIPLY", cv, cv)))
        ring = math_node("LESS_THAN", math_node("ABSOLUTE", math_node("SUBTRACT", dist, 0.26)), 0.045)
        dot = math_node("LESS_THAN", dist, 0.09)
        petals = math_node("LESS_THAN", math_node("ABSOLUTE", math_node("SINE", math_node("MULTIPLY", math_node("ARCTAN2", cv, cu), 4.0))), 0.35)
        petal_ring = math_node("MULTIPLY", petals, math_node("LESS_THAN", math_node("ABSOLUTE", math_node("SUBTRACT", dist, 0.17)), 0.05))
        motif_mask = math_node("MAXIMUM", math_node("MAXIMUM", ring, dot), petal_ring)
        accent_mask = math_node("LESS_THAN", math_node("ABSOLUTE", cu), 0.015)
    else:  # sprigs: small scattered flowers and pinstripes
        vor = nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 2.2
        comb = nodes.new("ShaderNodeCombineXYZ")
        links.new(u, comb.inputs["X"])
        links.new(v, comb.inputs["Y"])
        links.new(comb.outputs["Vector"], vor.inputs["Vector"])
        motif_mask = math_node("LESS_THAN", vor.outputs["Distance"], 0.12)
        cell = math_node("FRACT", math_node("DIVIDE", u, 0.9))
        accent_mask = math_node("LESS_THAN", math_node("ABSOLUTE", math_node("SUBTRACT", cell, 0.5)), 0.02)

    def mix(fac, a, b):
        n = nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        links.new(fac, n.inputs[0])
        for i, c in ((6, a), (7, b)):
            if isinstance(c, tuple):
                n.inputs[i].default_value = c
            else:
                links.new(c, n.inputs[i])
        return n.outputs[2]

    color = mix(accent_mask, ground, accent)
    color = mix(motif_mask, color, motif)
    # Age: stains running down from the ceiling, peeled patches, grime at the bottom, AO.
    geo = nodes.new("ShaderNodeNewGeometry")
    stain_noise = nodes.new("ShaderNodeTexNoise")
    stain_noise.inputs["Scale"].default_value = 0.25
    stain_noise.inputs["Detail"].default_value = 8
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 1.0, 0.35)
    links.new(geo.outputs["Position"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], stain_noise.inputs["Vector"])
    stain = math_node("MULTIPLY", math_node("SUBTRACT", stain_noise.outputs["Fac"], 0.5), 2.2, clamp=True)
    color = mix(math_node("MULTIPLY", stain, 0.55), color, (0.09, 0.06, 0.03, 1))
    peel_noise = nodes.new("ShaderNodeTexNoise")
    peel_noise.inputs["Scale"].default_value = 0.9
    peel_noise.inputs["Detail"].default_value = 10
    peel_noise.inputs["Roughness"].default_value = 0.7
    links.new(geo.outputs["Position"], peel_noise.inputs["Vector"])
    peel = math_node("GREATER_THAN", peel_noise.outputs["Fac"], 0.66)
    color = mix(peel, color, (0.36, 0.33, 0.28, 1))
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 2.0
    ao_dark = nodes.new("ShaderNodeMapRange")
    ao_dark.inputs["To Min"].default_value = 0.35
    links.new(ao.outputs["AO"], ao_dark.inputs["Value"])
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    links.new(color, mul.inputs[6])
    comb = nodes.new("ShaderNodeCombineColor")
    for ch in ("Red", "Green", "Blue"):
        links.new(ao_dark.outputs["Result"], comb.inputs[ch])
    links.new(comb.outputs["Color"], mul.inputs[7])
    links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    links.new(peel, bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def books_material(name):
    """Book spines: each book a different dull colour (Voronoi cells keyed on position)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    geo = nodes.new("ShaderNodeNewGeometry")
    vor = nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 5.0
    links.new(geo.outputs["Position"], vor.inputs["Vector"])
    hsv = nodes.new("ShaderNodeHueSaturation")
    hsv.inputs["Saturation"].default_value = 0.75
    hsv.inputs["Value"].default_value = 0.22
    links.new(vor.outputs["Color"], hsv.inputs["Color"])
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    links.new(hsv.outputs["Color"], mul.inputs[6])
    links.new(ao.outputs["AO"], mul.inputs[7])
    links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    return mat


def materials(V):
    M, UV = V.MATERIALS, V.UV_RULES
    papers = {
        "WallpaperA": ((0.16, 0.22, 0.15, 1), (0.1, 0.14, 0.09, 1), (0.42, 0.4, 0.26, 1), "stripes"),  # sage green stripes
        "WallpaperB": ((0.2, 0.05, 0.05, 1), (0.14, 0.03, 0.03, 1), (0.38, 0.26, 0.12, 1), "damask"),  # burgundy damask
        "WallpaperC": ((0.38, 0.32, 0.18, 1), (0.25, 0.2, 0.1, 1), (0.2, 0.08, 0.06, 1), "sprigs"),  # faded mustard sprigs
    }
    for name, (ground, accent, motif, kind) in papers.items():
        M[name] = wallpaper(V, name, ground, accent, motif, kind)
        UV[name] = (1.0, "vertical")
    M["Wallpaper"] = M["WallpaperB"]  # the halls behind the doors
    UV["Wallpaper"] = (1.0, "vertical")
    M["Floorboards"] = V.textured("Floorboards", "weathered_planks", tint=(0.42, 0.34, 0.28, 1), dirt=0.7)
    UV["Floorboards"] = (5.0, "horizontal")
    M["Plaster"] = V.textured("Plaster", "concrete_wall_006", tint=(1.25, 1.18, 1.05, 1), dirt=0.6, moss=0.2)
    UV["Plaster"] = (6.0, "vertical")
    M["FurnitureWood"] = V.textured("FurnitureWood", "dark_wooden_planks", tint=(0.5, 0.4, 0.36, 1), rough=0.6, dirt=0.5)
    UV["FurnitureWood"] = (2.0, "vertical")
    M["Cloth"] = V.textured("Cloth", "concrete_wall_006", paint=(0.62, 0.6, 0.55, 1), dirt=0.7)
    UV["Cloth"] = (3.0, "vertical")
    velvet = V.textured("Velvet", "concrete_wall_006", paint=(0.3, 0.05, 0.06, 1), rough=0.9, dirt=0.5)
    M["Velvet"] = M["Curtain"] = velvet
    UV["Velvet"] = UV["Curtain"] = (2.0, "vertical")
    M["Books"] = books_material("Books")
    M["Canvas"] = V.textured("Canvas", None, tint=(0.03, 0.025, 0.02, 1), rough=0.8)
    M["Pale"] = V.textured("Pale", None, tint=(0.5, 0.45, 0.38, 1), rough=0.8)


# Shapes ------------------------------------------------------------------------------------------
def at(V, x, y, z, yaw=0.0):
    """A furniture frame on the floor at (x, y, z) facing -Y rotated by yaw, in metres."""
    return V.frame_matrix((x, y, z), (0, 0, yaw)) @ Matrix.Scale(U, 4)


def lump(V, grp, size, m, droop=0.12, seed=0):
    """A dust sheet thrown over something: a soft, slumped box with folds hanging at the hem."""
    r = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=4, use_grid_fill=True)
    sx, sy, sz = size
    for vert in bm.verts:
        x, y, z = vert.co
        top = z + 0.5
        flare = (1 - top) * droop
        vert.co.x = x * (sx + flare * 2) + r.uniform(-0.03, 0.03)
        vert.co.y = y * (sy + flare * 2) + r.uniform(-0.03, 0.03)
        vert.co.z = top * sz + (r.uniform(-0.04, 0.02) if top > 0.05 else 0)
        if top > 0.95:
            vert.co.z -= abs(x) * 0.08 + abs(y) * 0.06  # sags off the edges
    for f in bm.faces:
        f.smooth = True
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return V.mesh_object("Sheet", bm, grp)


# Furniture (metres, facing -Y) -------------------------------------------------------------------
def armchair(V, m):
    for sx in (-0.33, 0.33):
        for sy in (-0.3, 0.3):
            V.lathe("FurnitureWood", [(0.035, 0), (0.025, 0.14)], (sx, sy, 0), segments=6, matrix=m)
    V.box("Velvet", (0.82, 0.78, 0.2), (0, 0, 0.24), bevel=0.05, matrix=m)
    V.box("Velvet", (0.82, 0.16, 0.8), (0, 0.33, 0.7), bevel=0.06, matrix=m)
    for sx in (-0.37, 0.37):
        V.box("Velvet", (0.14, 0.7, 0.26), (sx, -0.02, 0.48), bevel=0.05, matrix=m)
        V.box("Velvet", (0.12, 0.3, 0.42), (sx, 0.2, 0.86), bevel=0.04, matrix=m)


def side_table(V, m, lamp=True):
    V.lathe("FurnitureWood", [(0.2, 0), (0.06, 0.06), (0.04, 0.5), (0.3, 0.6), (0.3, 0.64), (0.01, 0.64)], (0, 0, 0), segments=12, matrix=m)
    if lamp:
        V.lathe("Iron", [(0.08, 0.64), (0.06, 0.68), (0.03, 0.74), (0.09, 0.82), (0.05, 0.86)], (0, 0, 0), segments=10, matrix=m)
        V.lathe("Glass", [(0.04, 0.86), (0.07, 0.95), (0.03, 1.08), (0.03, 1.12)], (0, 0, 0), segments=10, matrix=m)


def portrait(V, m, w=0.62, h=0.8):
    """A dark old portrait: a frame round a canvas set back in it, a pale face and the shoulders
    of someone in black. Each layer a little in front of the last (flush, they flickered); the
    back is 0.025 behind the origin."""
    V.box("FurnitureWood", (w + 0.12, 0.03, h + 0.12), (0, 0.01, 0), bevel=0.01, matrix=m)  # back board
    for sx in (-1, 1):
        V.box("FurnitureWood", (0.07, 0.06, h + 0.12), (sx * (w / 2 + 0.025), -0.02, 0), bevel=0.015, matrix=m)
    for sz in (-1, 1):
        V.box("FurnitureWood", (w - 0.02, 0.05, 0.07), (0, -0.015, sz * (h / 2 + 0.025)), bevel=0.015, matrix=m)
    V.box("Canvas", (w - 0.02, 0.01, h - 0.02), (0, -0.01, 0), matrix=m)
    face = m @ Matrix.Translation((0, -0.045, h * 0.12)) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((1, 1.3, 0.25, 1))
    V.lathe("Pale", [(0.0, -0.13), (0.09, -0.1), (0.11, 0.0), (0.09, 0.1), (0.0, 0.13)], (0, 0, 0), segments=10, matrix=face)
    V.prism("Canvas", [(-0.22, -h / 2 + 0.02), (0.22, -h / 2 + 0.02), (0.14, -h * 0.08), (-0.14, -h * 0.08)], 0.01, m @ Matrix.Translation((0, -0.025, 0)))


def fireplace(V, m):
    V.box("FurnitureWood", (1.5, 0.3, 1.15), (0, 0.15, 0.575), bevel=0.02, matrix=m)
    V.box("Interior", (0.72, 0.32, 0.66), (0, 0.12, 0.33), matrix=m)  # the firebox, black
    V.box("FurnitureWood", (1.7, 0.36, 0.06), (0, 0.12, 1.18), bevel=0.02, matrix=m)  # mantel
    V.box("Stone", (1.6, 0.45, 0.05), (0, -0.22, 0.025), matrix=m)  # hearth
    for i in range(5):
        V.box("Iron", (0.02, 0.2, 0.18), (-0.2 + i * 0.1, 0.0, 0.12), matrix=m)  # grate
    V.lathe("Iron", [(0.05, 1.21), (0.03, 1.3), (0.06, 1.42), (0.04, 1.48)], (-0.6, 0.12, 0), segments=8, matrix=m)  # candlestick
    V.lathe("Pale", [(0.018, 1.48), (0.018, 1.62)], (-0.6, 0.12, 0), segments=6, matrix=m)
    V.lathe("FurnitureWood", [(0.07, 1.21), (0.09, 1.32), (0.05, 1.45), (0.0, 1.47)], (0.55, 0.12, 0), segments=10, matrix=m)  # an urn
    portrait(V, m @ Matrix.Translation((0, 0.27, 1.75)))


def bed(V, m):
    """An iron bedstead with a sagging mattress, a pillow and a thrown-back blanket."""
    for sx in (-0.48, 0.48):
        V.box("Iron", (0.04, 0.04, 1.15), (sx, 1.0, 0.575), matrix=m)  # head posts
        V.box("Iron", (0.04, 0.04, 0.8), (sx, -1.0, 0.4), matrix=m)  # foot posts
        V.lathe("Iron", [(0.035, 0), (0.04, 0.03), (0.0, 0.07)], (sx, 1.0, 1.15), segments=8, matrix=m)
    for i in range(7):
        x = -0.36 + i * 0.12
        V.box("Iron", (0.02, 0.02, 0.6), (x, 1.0, 0.75), matrix=m)
        V.box("Iron", (0.02, 0.02, 0.35), (x, -1.0, 0.6), matrix=m)
    for z in (0.45, 1.05):
        V.box("Iron", (1.0, 0.03, 0.03), (0, 1.0, z), matrix=m)
    V.box("Iron", (1.0, 0.03, 0.03), (0, -1.0, 0.78), matrix=m)
    V.box("Cloth", (0.92, 1.95, 0.2), (0, 0, 0.5), bevel=0.06, matrix=m)
    V.box("Cloth", (0.6, 0.32, 0.12), (0, 0.78, 0.65), bevel=0.05, matrix=m)
    lump(V, "Velvet", (0.48, 0.55, 0.12), m @ Matrix.Translation((0, -0.45, 0.55)), droop=0.35, seed=7)


def wardrobe(V, m):
    V.box("FurnitureWood", (1.1, 0.55, 2.0), (0, 0, 1.06), bevel=0.02, matrix=m)
    V.box("FurnitureWood", (1.2, 0.6, 0.1), (0, 0, 2.1), bevel=0.02, matrix=m)
    V.box("FurnitureWood", (1.15, 0.58, 0.08), (0, 0, 0.04), matrix=m)
    for sx in (-0.27, 0.27):
        V.box("FurnitureWood", (0.46, 0.03, 1.6), (sx, -0.28, 1.06), bevel=0.01, matrix=m)
        knob = m @ Matrix.Translation((sx * 0.15, -0.3, 1.1)) @ Matrix.Rotation(math.pi / 2, 4, "X")
        V.lathe("Iron", [(0.015, 0), (0.02, 0.03), (0.0, 0.05)], (0, 0, 0), segments=6, matrix=knob)


def dresser(V, m):
    V.box("FurnitureWood", (1.0, 0.45, 0.8), (0, 0, 0.42), bevel=0.02, matrix=m)
    for z in (0.22, 0.47, 0.7):
        V.box("FurnitureWood", (0.9, 0.03, 0.18), (0, -0.23, z), bevel=0.01, matrix=m)
    V.box("FurnitureWood", (0.7, 0.04, 0.8), (0, 0.18, 1.25), bevel=0.02, matrix=m)
    V.box("Glass", (0.6, 0.02, 0.7), (0, 0.15, 1.25), matrix=m)


def chair(V, m):
    for sx in (-0.2, 0.2):
        for sy in (-0.18, 0.18):
            V.box("FurnitureWood", (0.04, 0.04, 0.45), (sx, sy, 0.225), matrix=m)
        V.box("FurnitureWood", (0.04, 0.04, 0.55), (sx, 0.18, 0.72), matrix=m)
    V.box("FurnitureWood", (0.46, 0.42, 0.04), (0, 0, 0.46), matrix=m)
    for z in (0.7, 0.92):
        V.box("FurnitureWood", (0.4, 0.03, 0.06), (0, 0.18, z), matrix=m)


def table(V, m, w=1.4, d=0.8, h=0.75):
    V.box("FurnitureWood", (w, d, 0.05), (0, 0, h), bevel=0.01, matrix=m)
    for sx in (-1, 1):
        for sy in (-1, 1):
            V.lathe("FurnitureWood", [(0.03, 0), (0.045, 0.2), (0.03, 0.45), (0.04, h)], (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), 0), segments=6, matrix=m)


def candelabra(V, m):
    V.lathe("Iron", [(0.08, 0), (0.03, 0.04), (0.02, 0.3), (0.0, 0.32)], (0, 0, 0), segments=8, matrix=m)
    for a in (-1, 0, 1):
        x = a * 0.12
        V.box("Iron", (0.24 if a == 0 else 0.02, 0.02, 0.02), (0, 0, 0.26), matrix=m)
        V.lathe("Pale", [(0.012, 0.28), (0.012, 0.4 - abs(a) * 0.05)], (x, 0, 0), segments=6, matrix=m)


def bookshelf(V, m, seed):
    r = random.Random(seed)
    V.box("FurnitureWood", (1.0, 0.34, 0.03), (0, 0, 2.1), matrix=m)
    for sx in (-0.5, 0.5):
        V.box("FurnitureWood", (0.03, 0.34, 2.1), (sx, 0, 1.05), matrix=m)
    V.box("FurnitureWood", (1.0, 0.02, 2.1), (0, 0.16, 1.05), matrix=m)
    for i in range(5):
        z = 0.08 + i * 0.42
        V.box("FurnitureWood", (1.0, 0.32, 0.025), (0, 0, z), matrix=m)
        x = -0.47
        while x < 0.45:
            bw = r.uniform(0.03, 0.065)
            bh = r.uniform(0.2, 0.32)
            if r.random() < 0.08:
                x += 0.08  # a gap
                continue
            lean = r.uniform(0.25, 0.4) if r.random() < 0.06 else 0.0
            V.box("Books", (bw, r.uniform(0.18, 0.24), bh), (x + bw / 2, -0.02, z + 0.012 + bh / 2), rot=(0, lean, 0), matrix=m)
            x += bw + 0.004


def desk(V, m):
    V.box("FurnitureWood", (1.3, 0.65, 0.05), (0, 0, 0.76), bevel=0.01, matrix=m)
    for sx in (-0.45, 0.45):
        V.box("FurnitureWood", (0.38, 0.6, 0.72), (sx, 0, 0.37), matrix=m)
    for i in range(4):  # papers, each lying on the last
        V.box("Pale", (0.21, 0.29, 0.01), (-0.3 + i * 0.13, -0.05 + i * 0.02, 0.79 + i * 0.012), rot=(0, 0, 0.2 * (i - 1.5)), matrix=m)
    V.lathe("Iron", [(0.07, 0.785), (0.02, 0.8), (0.02, 1.15), (0.0, 1.16)], (0.5, 0.15, 0), segments=6, matrix=m)
    V.lathe("Glass", [(0.0, 1.05), (0.12, 1.1), (0.05, 1.22), (0.0, 1.24)], (0.5, 0.15, 0), segments=10, matrix=m)


def crib(V, m):
    w, d = 1.2, 0.65
    for sx in (-w / 2, w / 2):
        for sy in (-d / 2, d / 2):
            V.box("FurnitureWood", (0.05, 0.05, 1.0), (sx, sy, 0.5), matrix=m)
    for z in (0.35, 0.95):
        for sy in (-d / 2, d / 2):
            V.box("FurnitureWood", (w, 0.035, 0.04), (0, sy, z), matrix=m)
        for sx in (-w / 2, w / 2):
            V.box("FurnitureWood", (0.035, d, 0.04), (sx, 0, z), matrix=m)
    for i in range(1, 12):
        x = -w / 2 + i * w / 12
        for sy in (-d / 2, d / 2):
            V.box("FurnitureWood", (0.02, 0.012, 0.6), (x, sy, 0.65), matrix=m)  # thinner than the rails they pass
    V.box("Cloth", (w - 0.08, d - 0.08, 0.1), (0, 0, 0.4), bevel=0.03, matrix=m)


def rocking_chair(V, m, doll=False):
    for sx in (-0.22, 0.22):
        pts = [Vector((sx, -0.45 + i * 0.1, 0.04 + 0.12 * ((i - 4.5) / 4.5) ** 2)) for i in range(10)]
        V.tube("FurnitureWood", [m @ p for p in pts], [0.025 * U] * len(pts), sides=0)
        for sy in (-0.2, 0.22):
            V.box("FurnitureWood", (0.035, 0.035, 0.42), (sx, sy, 0.27), matrix=m)
        V.box("FurnitureWood", (0.035, 0.035, 0.75), (sx, 0.24, 0.85), rot=(-0.15, 0, 0), matrix=m)
    V.box("FurnitureWood", (0.5, 0.46, 0.04), (0, 0, 0.47), matrix=m)
    for i in range(6):
        V.box("FurnitureWood", (0.02, 0.02, 0.6), (-0.18 + i * 0.072, 0.27, 0.82), rot=(-0.15, 0, 0), matrix=m)
    V.box("FurnitureWood", (0.5, 0.04, 0.06), (0, 0.33, 1.18), rot=(-0.15, 0, 0), matrix=m)
    if doll:
        # A porcelain-faced doll sitting slumped in it.
        V.lathe("Velvet", [(0.0, 0.49), (0.13, 0.5), (0.1, 0.62), (0.06, 0.74), (0.0, 0.76)], (0, 0.05, 0), segments=10, matrix=m)
        V.lathe("Pale", [(0.0, -0.02), (0.065, 0.01), (0.075, 0.07), (0.06, 0.13), (0.0, 0.15)], (0, 0, 0), segments=10, matrix=m @ V.frame_matrix((0.02, 0.06, 0.76), (0.0, 0.35, 0)))
        for sx in (-0.07, 0.07):
            V.box("Pale", (0.035, 0.18, 0.035), (sx, -0.08, 0.53), matrix=m)


def stove(V, m):
    V.box("Iron", (0.95, 0.6, 0.8), (0, 0, 0.42), bevel=0.02, matrix=m)
    V.box("Iron", (1.0, 0.65, 0.05), (0, 0, 0.84), bevel=0.01, matrix=m)
    for sx in (-0.25, 0.25):
        V.box("Iron", (0.38, 0.03, 0.3), (sx, -0.31, 0.45), bevel=0.01, matrix=m)
    for sx in (-0.4, 0.4):
        V.box("Iron", (0.06, 0.06, 0.06), (sx, -0.25, 0.03), matrix=m)
    V.lathe("Iron", [(0.07, 0.86), (0.07, 2.6)], (0.3, 0.2, 0), segments=10, matrix=m)  # the flue
    V.lathe("Iron", [(0.11, 0.87), (0.12, 1.0), (0.1, 1.05), (0.0, 1.06)], (-0.2, -0.05, 0), segments=10, matrix=m)  # kettle


def shelves(V, m, seed):
    r = random.Random(seed)
    for z in (1.0, 1.45, 1.9):
        V.box("FurnitureWood", (1.2, 0.28, 0.03), (0, 0, z), matrix=m)
        for i in range(5):
            if r.random() < 0.25:
                continue
            x = -0.5 + i * 0.25 + r.uniform(-0.04, 0.04)
            hh = r.uniform(0.14, 0.26)
            V.lathe("Glass", [(0.05, z), (0.06, z + 0.02), (0.06, z + hh * 0.8), (0.035, z + hh), (0.0, z + hh)], (x, -0.02, 0), segments=8, matrix=m)
    for sx in (-0.55, 0.55):
        V.box("FurnitureWood", (0.03, 0.03, 0.12), (sx, 0.1, 1.42), matrix=m)


def stairs(V, m, steps=12):
    """A staircase climbing away along +Y, with a banister on the open side."""
    for i in range(steps):
        V.box("FurnitureWood", (1.0, 0.27, 0.04), (0, i * 0.25, 0.18 * (i + 1)), bevel=0.01, matrix=m)
        V.box("FurnitureWood", (1.0, 0.02, 0.18), (0, i * 0.25 - 0.13, 0.18 * (i + 0.5)), matrix=m)
        V.box("FurnitureWood", (0.025, 0.025, 0.85), (-0.48, i * 0.25, 0.18 * (i + 1) + 0.42), matrix=m)
    V.box("FurnitureWood", (0.07, 0.07, 1.05), (-0.48, -0.1, 0.52), matrix=m)  # newel post
    V.lathe("FurnitureWood", [(0.06, 1.05), (0.08, 1.12), (0.0, 1.2)], (-0.48, -0.1, 0), segments=8, matrix=m)
    length = math.hypot(steps * 0.25, steps * 0.18)
    V.box("FurnitureWood", (0.06, length, 0.06), (-0.48, steps * 0.125 - 0.1, 0.18 * steps / 2 + 1.0), rot=(math.atan2(0.18, 0.25), 0, 0), matrix=m)
    V.box("FurnitureWood", (0.05, length, 0.2), (0.5, steps * 0.125 - 0.1, 0.18 * steps / 2), rot=(math.atan2(0.18, 0.25), 0, 0), matrix=m)


def crate(V, m, s=0.6):
    V.box("FurnitureWood", (s, s, s * 0.8), (0, 0, s * 0.4), bevel=0.01, matrix=m)
    for z in (0.1, 0.4, 0.7):
        V.box("Boards", (s + 0.02, s + 0.02, 0.06), (0, 0, s * 0.8 * z + 0.04), matrix=m)


def dress_form(V, m):
    V.lathe("Iron", [(0.18, 0), (0.02, 0.03), (0.015, 0.9), (0.0, 0.92)], (0, 0, 0), segments=8, matrix=m)
    V.lathe("Cloth", [(0.0, 0.85), (0.17, 0.88), (0.14, 1.05), (0.12, 1.15), (0.17, 1.3), (0.15, 1.42), (0.06, 1.48), (0.04, 1.55), (0.0, 1.56)], (0, 0, 0), segments=12, matrix=m @ Matrix.Diagonal((1, 0.7, 1, 1)))


def clock(V, m):
    V.box("FurnitureWood", (0.5, 0.3, 1.9), (0, 0, 0.95), bevel=0.02, matrix=m)
    V.box("FurnitureWood", (0.56, 0.34, 0.12), (0, 0, 1.96), bevel=0.02, matrix=m)
    V.lathe("Pale", [(0.0, 0.0), (0.17, 0.0), (0.17, 0.02), (0.0, 0.02)], (0, 0, 0), segments=16, matrix=m @ Matrix.Translation((0, -0.16, 1.6)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    V.box("Glass", (0.3, 0.02, 0.7), (0, -0.16, 0.95), matrix=m)
    V.lathe("Iron", [(0.06, 0.0), (0.06, 0.01)], (0, 0, 0), segments=10, matrix=m @ Matrix.Translation((0.03, -0.12, 0.75)) @ Matrix.Rotation(math.pi / 2, 4, "X"))


def rug(V, m, w, d):
    V.box("Velvet", (w, d, 0.01), (0, 0, 0.005), matrix=m)


def figure(V, grp, m):
    """Someone standing very still: tall, thin, arms hanging too long. A dark silhouette."""
    for sx in (-0.09, 0.09):
        V.lathe(grp, [(0.06, 0), (0.07, 0.4), (0.08, 0.85), (0.0, 0.9)], (sx, 0, 0), segments=8, matrix=m)
    V.lathe(grp, [(0.0, 0.82), (0.19, 0.86), (0.17, 1.1), (0.15, 1.35), (0.21, 1.5), (0.14, 1.58), (0.06, 1.62), (0.05, 1.68), (0.0, 1.7)], (0, 0, 0), segments=10, matrix=m @ Matrix.Diagonal((1, 0.6, 1, 1)))
    for sx in (-1, 1):
        a = Vector((sx * 0.22, 0, 1.52))
        b = Vector((sx * 0.27, -0.02, 1.05))
        c = Vector((sx * 0.25, -0.05, 0.62))  # hands down past the knees
        V.tube(grp, [m @ a, m @ b, m @ c], [0.045 * U, 0.035 * U, 0.03 * U], sides=0)
    V.lathe(grp, [(0.0, 0.0), (0.09, 0.06), (0.11, 0.16), (0.09, 0.27), (0.0, 0.31)], (0, 0, 0), segments=10, matrix=m @ V.frame_matrix((0, 0, 1.66), (0.18, 0.12, 0)))




# Rooms -------------------------------------------------------------------------------------------
def opening_cutters(V, slab_matrix, size):
    """Cutters for every window or door opening that passes through this slab."""
    inv = slab_matrix.inverted()
    cutters = []
    for op in V.OPENINGS:
        frame, o = op["frame"], op["o"]
        centre = inv @ (frame @ Vector((o["x"], V.T / 2, o["y"] + o["h"] / 2)))
        if abs(centre.x) < size[0] / 2 + 0.6 and abs(centre.y) < 1.2 and abs(centre.z) < size[2] / 2 + 0.6:
            cutters.append(V.box("_cutters", (o["w"], V.T * 3, o["h"]), (o["x"], V.T / 2, o["y"] + o["h"] / 2), matrix=frame))
    return cutters


def wall_slab(V, paper, a, b, floor, ceil, doorway=None):
    """A wallpapered slab from a to b (x, y on the floor plan), its openings cut through, with
    skirting and a picture rail on its room face (the left of a to b: rooms go round
    counter-clockwise). Its other face is against a house wall or the next room's slab."""
    a, b = Vector((a[0], a[1], 0)), Vector((b[0], b[1], 0))
    d = b - a
    length = d.length
    yaw = math.atan2(d.y, d.x)
    h = ceil - floor
    m = V.frame_matrix(((a + b) / 2 + Vector((0, 0, floor + h / 2))).to_tuple(), (0, 0, yaw))
    slab = V.box(paper, (length, WALL, h), (0, 0, 0), matrix=m)
    cutters = opening_cutters(V, m, (length, WALL, h))
    if doorway:
        cutters.append(V.box("_cutters", (doorway[1], 1.0, doorway[2]), (doorway[0], 0, -h / 2 + doorway[2] / 2), matrix=m))
    if cutters:
        V.cut(slab, cutters)
    skirting = V.box("FurnitureWood", (length, 0.06, 0.45), (0, 0.07, -h / 2 + 0.225), matrix=m)
    gaps = opening_cutters(V, m, (length, WALL, h))
    if doorway:
        gaps.append(V.box("_cutters", (doorway[1], 1.0, doorway[2]), (doorway[0], 0, -h / 2 + doorway[2] / 2), matrix=m))
    if gaps:
        V.cut(skirting, gaps)
    V.box("FurnitureWood", (length, 0.05, 0.12), (0, 0.07, h / 2 - 1.3), matrix=m)
    return m


def pendant(V, x, y, ceil):
    """A ceiling rose, a cord and a little shade; the game hangs the glowing bulb under it."""
    lamp = Vector((x, y, ceil - 1.2))
    V.lathe("Plaster", [(0.5, 0), (0.42, -0.08), (0.12, -0.14), (0.0, -0.15)], (x, y, ceil), segments=12)
    V.box("Iron", (0.04, 0.04, 1.0), (x, y, ceil - 0.55))
    V.lathe("Iron", [(0.06, 0.1), (0.1, 0.12), (0.38, -0.12), (0.4, -0.16), (0.36, -0.13), (0.08, 0.06)], (x, y, lamp.z + 0.1), segments=12)
    return lamp


def box_room(V, room):
    x0, x1, y0, y1, floor, ceil = room["x0"], room["x1"], room["y0"], room["y1"], room["floor"], room["ceil"]
    paper = room["paper"]
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    inset = [(x0 + WALL / 2, y0 + WALL / 2), (x1 - WALL / 2, y0 + WALL / 2), (x1 - WALL / 2, y1 - WALL / 2), (x0 + WALL / 2, y1 - WALL / 2)]
    for i in range(4):
        doorway = room.get("doorway") if i == room.get("doorway_side") else None
        wall_slab(V, paper, inset[i], inset[(i + 1) % 4], floor, ceil, doorway)
    V.box("Floorboards", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, floor - 0.1))
    V.box("Plaster", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, ceil + 0.1))
    lamp = pendant(V, room.get("lamp_x", (x0 + x1) / 2), room.get("lamp_y", (y0 + y1) / 2), ceil)
    if room.get("doorway"):
        # Darkness through the doorway.
        side = room["doorway_side"]
        a, b = Vector(inset[side] + (0,)), Vector(inset[(side + 1) % 4] + (0,))
        d = (b - a).normalized()
        out = Vector((d.y, -d.x, 0))  # away from the room's centre for a counter-clockwise loop
        mid = (a + b) / 2 + d * room["doorway"][0]
        V.box("Interior", (room["doorway"][1] + 0.6, 0.2, room["doorway"][2] + 0.4), (0, 0, 0),
              matrix=V.frame_matrix((mid + out * 1.4 + Vector((0, 0, floor + room["doorway"][2] / 2))).to_tuple(), (0, 0, math.atan2(d.y, d.x))))
        for s in (-1, 1):
            V.box("Interior", (0.2, 1.4, room["doorway"][2] + 0.4), (0, 0, 0),
                  matrix=V.frame_matrix((mid + d * s * (room["doorway"][1] / 2 + 0.3) + out * 0.7 + Vector((0, 0, floor + room["doorway"][2] / 2))).to_tuple(), (0, 0, math.atan2(d.y, d.x))))
    return lamp


def furnish(V, room):
    """Rooms are furnished per house by the game (Config/RoomLayouts, pieces from furniture.py);
    only the stair hall keeps fixed furniture: its stairs, landing and hall table."""
    if room["id"] == "R5":
        f = room["floor"]
        stairs(V, at(V, 12.1, 15.9, f), steps=7)
        V.box("FurnitureWood", (3.8, 0.6, 4.76), (12.1, 22.75, f + 2.38))  # landing
        V.box("FurnitureWood", (2.6, 1.0, 2.8), (9.4, 22.4, f + 1.4), bevel=0.05)  # hall table
        V.lathe("Glass", [(0.25, 2.8), (0.45, 3.4), (0.2, 4.1), (0.3, 4.4)], (9.4, 22.4, f), segments=10)  # a vase


def room_entry(room, lamp, role, front):
    """What the game needs to know about a room: its lamp, box, role and which wall is its front
    (the window side the furniture faces)."""
    return dict(id=room["id"], lamp=lamp, role=role, front=front,
                box=(room["x0"], room["x1"], room["y0"], room["y1"], room["floor"], room["ceil"]))


# Entrance halls ----------------------------------------------------------------------------------
# What a front door opens onto (and what an open house shows): a proper hall built into the house.
# Panelled wainscot to a chair rail, wallpaper above, a cornice, doorways into dark rooms, a
# staircase with a closed string, turned balusters and newel posts, a ceiling rose with a chain for
# the game's chandelier. Faces never share a plane: trims stop where the next wall's trims start,
# a pilaster covers an outside corner, and nothing lies flush on anything that faces the same way.

DADO = 3.6  # chair rail height above the floor
HALL = None  # the last entrance hall built (for renders)
PAPER_FACE = 0.0  # in a wall's frame (edge_frames) the room face of the wallpaper is y = 0
# The chandelier (furniture.py) hangs from its hook: arms reach out REACH, the candles' tops are
# TIP below the hook, its light sits LIGHT below (metres; the game places the flames).
CHANDELIER = dict(arms=8, reach=0.56, tip=0.2, light=0.42)


def inset_loop(points, d):
    """A counter-clockwise rectilinear outline moved `d` inward (to its left)."""
    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2 = Vector(points[i - 1]), Vector(points[i]), Vector(points[(i + 1) % n])
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((-e1.y, e1.x)), Vector((-e2.y, e2.x))
        out.append(p1 + (n1 * d if n1.dot(n2) > 0.99 else (n1 + n2) * d))
    return out


def turns(points):
    """For each vertex of a counter-clockwise outline: "in" where it turns left (an inside corner
    of the room), "out" where it turns right (a corner standing out into the room), "on" where the
    wall runs straight on."""
    n = len(points)
    res = []
    for i in range(n):
        p0, p1, p2 = Vector(points[i - 1]), Vector(points[i]), Vector(points[(i + 1) % n])
        e1, e2 = p1 - p0, p2 - p1
        cross = e1.x * e2.y - e1.y * e2.x
        res.append("in" if cross > 1e-6 else "out" if cross < -1e-6 else "on")
    return res


def edge_frame(V, a, b, floor):
    """A wall's frame: origin on the room face at a, x along to b, +y into the room, z up from
    the floor."""
    d = Vector(b) - Vector(a)
    return V.frame_matrix((a[0], a[1], floor), (0, 0, math.atan2(d.y, d.x)))


def holes_in(V, m, length, height):
    """The window and door openings (V.OPENINGS) through a wall face in frame m (edge_frame):
    (x centre, width, z bottom, height) in that frame."""
    inv = m.inverted()
    holes = []
    for op in V.OPENINGS:
        frame, o = op["frame"], op["o"]
        c = inv @ (frame @ Vector((o["x"], V.T / 2, o["y"] + o["h"] / 2)))
        if -0.6 < c.x < length + 0.6 and abs(c.y) < 1.5 and -0.6 < c.z < height + 0.6:
            holes.append((c.x, o["w"], c.z - o["h"] / 2, o["h"]))
    return holes


def run(V, grp, m, x0, x1, depth, z0, z1, gaps, bevel=0.0):
    """A trim board along a wall (frame m) from x0 to x1, `depth` into the room, z0 to z1, broken
    where it crosses a gap (x centre, width, z bottom, height)."""
    pieces = [(x0, x1)]
    for gx, gw, gz, gh in gaps:
        if gz < z1 and gz + gh > z0:
            lo, hi = gx - gw / 2, gx + gw / 2
            nxt = []
            for a, b in pieces:
                if lo > a:
                    nxt.append((a, min(b, lo)))
                if hi < b:
                    nxt.append((max(a, hi), b))
            pieces = nxt
    for a, b in pieces:
        if b - a > 0.05:
            V.box(grp, (b - a, depth, z1 - z0), ((a + b) / 2, depth / 2, (z0 + z1) / 2), bevel=bevel, matrix=m)
    return pieces


def panels(V, m, spans, z0, z1, gap=0.4, size=2.3):
    """Raised panels in the wainscot between z0 and z1 over each (a, b) span along the wall."""
    for a, b in spans:
        length = b - a - gap
        if length < 1.0:
            continue
        n = max(1, round(length / size))
        w = length / n - gap
        for k in range(n):
            x = a + gap + k * (w + gap) + w / 2
            V.box("FurnitureWood", (w, 0.05, z1 - z0), (x, 0.105, (z0 + z1) / 2), bevel=0.02, matrix=m)


def casing_round(V, m, x, w, z, h, floor_doorway=True):
    """An architrave round a doorway on the wall face: posts on plinth blocks and a corniced head."""
    cw = 0.45
    for s in (-1, 1):
        px = x + s * (w / 2 + cw / 2)
        if floor_doorway:
            V.box("FurnitureWood", (cw + 0.1, 0.24, 1.0), (px, 0.12, z + 0.5), bevel=0.03, matrix=m)  # plinth
            V.box("FurnitureWood", (cw, 0.18, h - 1.0), (px, 0.09, z + 1.0 + (h - 1.0) / 2), bevel=0.03, matrix=m)
        else:
            V.box("FurnitureWood", (cw, 0.18, h), (px, 0.09, z + h / 2), bevel=0.03, matrix=m)
    V.box("FurnitureWood", (w + 2 * cw - 0.02, 0.21, cw), (x, 0.105, z + h + cw / 2), bevel=0.03, matrix=m)  # the head, on the posts
    V.box("FurnitureWood", (w + 2 * cw + 0.4, 0.3, 0.2), (x, 0.15, z + h + cw + 0.1), bevel=0.04, matrix=m)  # cornice
    V.box("FurnitureWood", (w + 2 * cw + 0.2, 0.24, 0.16), (x, 0.12, z + h + cw + 0.28), bevel=0.03, matrix=m)


def hall_walls(V, outline, floor, ceil, paper, doorways=None, dado=DADO, plain=(), crown=True):
    """The walls of a hall round a counter-clockwise outline of its walls' inner faces (box edges,
    as rooms use): wallpapered slabs with the house's openings and the `doorways` cut through,
    wainscot (board, raised panels, chair rail, skirting) unless the edge is in `plain` (a stair
    wall), a cornice, a casing and darkness at each doorway, a pilaster at each outside corner.
    `doorways`: {edge index: [(distance along the room face from its start, width, height,
    z above the floor)]}. Returns each edge's frame and length."""
    doorways = doorways or {}
    face = inset_loop(outline, WALL)
    centre = inset_loop(outline, WALL / 2)
    inside = turns(outline)
    n = len(outline)
    h = ceil - floor
    edges = []
    for i in range(n):
        a, b = face[i], face[(i + 1) % n]
        length = (b - a).length
        m = edge_frame(V, a, b, floor)
        # The slab, centred on its line and running corner to corner like a room's.
        ca, cb = centre[i], centre[(i + 1) % n]
        sm = V.frame_matrix(((ca + cb) / 2).to_3d().to_tuple(), (0, 0, math.atan2((cb - ca).y, (cb - ca).x)))
        slab = V.box(paper, ((cb - ca).length, WALL, h), (0, 0, floor + h / 2), matrix=sm)
        holes = holes_in(V, m, length, h)
        doors = [(x, w, z, dh) for x, w, dh, z in doorways.get(i, [])]
        cutters = [V.box("_cutters", (w, 1.0, hh), (x, 0, z + hh / 2), matrix=m) for x, w, z, hh in holes + doors]
        if cutters:
            V.cut(slab, cutters)
        for x, w, z, dh in doors:
            casing_round(V, m, x, w, z, dh, floor_doorway=z < 0.5)
            # Darkness inside the hole (whatever is behind the wall: another room's slab, the
            # house's wall).
            V.box("Interior", (w - 0.02, 0.06, dh - 0.02), (x, -0.05, z + dh / 2), matrix=m)
        # Trims start past the corner when the wall before ends there in an inside corner (its
        # trims run into the corner), and stop at an outside corner (a pilaster covers the end).
        gaps = holes + [(x, w + 0.9, z, dh + 0.45) for x, w, z, dh in doors]

        def start(depth):
            return depth if inside[i] == "in" else 0.0

        if i not in plain:
            spans = run(V, "FurnitureWood", m, start(0.09), length, 0.09, 0.0, dado, gaps)  # the boards
            run(V, "FurnitureWood", m, start(0.18), length, 0.18, 0.0, 0.62, gaps, bevel=0.03)  # skirting
            run(V, "FurnitureWood", m, start(0.17), length, 0.17, dado - 0.05, dado + 0.15, gaps, bevel=0.03)  # chair rail
            panels(V, m, [(max(s0, 0.3), min(s1, length - 0.3)) for s0, s1 in spans], 1.0, dado - 0.45)
        else:
            run(V, "FurnitureWood", m, start(0.18), length, 0.18, 0.0, 0.62, gaps, bevel=0.03)
        if crown:
            run(V, "FurnitureWood", m, start(0.3), length, 0.3, h - 0.32, h, gaps, bevel=0.04)
            run(V, "FurnitureWood", m, start(0.16), length, 0.16, h - 0.62, h - 0.32, gaps, bevel=0.03)
        edges.append((m, length))
    for i in range(n):
        if inside[i] == "out":
            p = face[i]
            V.box("FurnitureWood", (0.62, 0.62, h), (p.x, p.y, floor + h / 2), bevel=0.05)
    return edges


def slabs(V, grp, rects, z, top=True, thickness=0.2):
    """Floor (top at z) or ceiling (bottom at z) boxes over each (x0, x1, y0, y1)."""
    for x0, x1, y0, y1 in rects:
        V.box(grp, (x1 - x0, y1 - y0, thickness), ((x0 + x1) / 2, (y0 + y1) / 2, z - thickness / 2 if top else z + thickness / 2))


def rose(V, x, y, ceil, r=1.5):
    """A plaster ceiling rose: rings of moulding round a boss."""
    V.lathe("Plaster", [(r, 0.0), (r, -0.06), (r * 0.9, -0.1), (r * 0.78, -0.08), (r * 0.62, -0.18), (r * 0.42, -0.14), (r * 0.3, -0.26), (r * 0.12, -0.34), (0.0, -0.36)], (x, y, ceil + 0.01), segments=20)


def chain(V, x, y, top, bottom):
    """An iron chain from the ceiling down to where a light hangs, links alternately turned."""
    z, k = top, 0
    while z - 0.42 > bottom:
        V.torus("Iron", (0, 0, 0), 0.16, 0.035, Matrix.Translation((x, y, z - 0.21)) @ Matrix.Rotation(k * math.pi / 2, 4, "Z"), segments=8, sides=4)
        z -= 0.3
        k += 1
    V.lathe("Iron", [(0.05, bottom), (0.05, z)], (x, y, 0), segments=6)


def baluster(V, grp, x, y, z, length, m):
    """A turned baluster standing at (x, y, z) in frame m."""
    L = length
    V.lathe(grp, [(0.1, 0.0), (0.12, 0.12), (0.075, 0.3), (0.07, L * 0.3), (0.12, L * 0.42), (0.06, L * 0.62), (0.07, L * 0.8), (0.1, L - 0.12), (0.08, L)], (x, y, z), segments=8, matrix=m)


def newel(V, m, x, y, z0, z1):
    """A square newel post with a moulded cap and a ball finial, in frame m."""
    V.box("FurnitureWood", (0.55, 0.55, z1 - z0), (x, y, (z0 + z1) / 2), bevel=0.04, matrix=m)
    V.box("FurnitureWood", (0.72, 0.72, 0.16), (x, y, z1 + 0.08), bevel=0.04, matrix=m)
    V.lathe("FurnitureWood", [(0.2, z1 + 0.16), (0.12, z1 + 0.26), (0.24, z1 + 0.45), (0.2, z1 + 0.62), (0.06, z1 + 0.72), (0.0, z1 + 0.74)], (x, y, 0), segments=10, matrix=m)


TOP_NEWEL = 0.42  # the top newel's centre past the last tread: its face clear of the landing's edge


def flight(V, m, steps, rise, tread, width, open_sides=(1,), base=0.0, top_newel=True, cupboard=None):
    """A straight flight climbing along +y of frame m from y = 0 on z = 0, across x 0..width:
    solid steps down to `base` (painted risers, wooden treads with a nosing), and on each open
    side (0: x = 0, 1: x = width) a closed string panelled down to `base`, turned balusters two to
    a tread, a handrail and newel posts. `cupboard`: (side, y) for a little door in the panelling.
    The landing it climbs to is the caller's, flush with the last tread at steps * rise."""
    slope = rise / tread
    for i in range(steps):
        top = (i + 1) * rise
        V.box("Plaster", (width, tread, top - 0.12 - base), (width / 2, (i + 0.5) * tread, (base + top - 0.12) / 2), matrix=m)
        V.box("FurnitureWood", (width, tread + 0.08, 0.12), (width / 2, (i + 0.5) * tread - 0.04, top - 0.06), bevel=0.025, matrix=m)
    end = steps * tread

    def nose(y):  # the line through the treads' front edges
        return rise + y * slope

    sm = m @ Matrix.Rotation(math.pi / 2, 4, "Z")  # prism (x, z) -> (y, z); extruded toward -x
    for side in open_sides:
        sx = width + 0.2 if side else 0.0  # the string spans sx - 0.2 .. sx
        outer, out = (sx, 1) if side else (sx - 0.2, -1)  # its outer face, and which way that faces
        y0 = -0.15
        pts = [(y0, base), (end, base), (end, nose(end) + 0.35), (y0, nose(y0) + 0.35)]
        if base > nose(y0) - 0.5:
            pts = [(y0, base), (end, base), (end, nose(end) + 0.35), (y0, base + 0.6)]
        V.prism("FurnitureWood", pts, 0.2, sm @ Matrix.Translation((0, -sx, 0)))
        # Raised panels on the closure below the string.
        k = 0
        y = 0.5
        while y + 2.0 < end:
            ya, yb = y, y + 1.9
            zt = nose(ya) - 0.9
            zb = base + 0.7
            if zt - zb > 1.2:
                px = outer + out * 0.03
                if cupboard and cupboard[0] == side and ya <= cupboard[1] < yb:
                    # The cupboard under the stairs: its door left an inch open on the dark.
                    V.box("Interior", (0.06, 0.14, zt - zb - 0.1), (outer + out * 0.035, yb - 0.08, (zt + zb) / 2), matrix=m)
                    V.box("FurnitureWood", (0.08, yb - ya - 0.2, zt - zb), (outer + out * 0.1, (ya + yb) / 2 - 0.1, (zt + zb) / 2), rot=(0, 0, out * 0.07), bevel=0.02, matrix=m)
                    V.lathe("Iron", [(0.06, 0.0), (0.08, 0.06), (0.0, 0.12)], (0, 0, 0), segments=6, matrix=m @ V.frame_matrix((outer + out * 0.16, ya + 0.4, (zt + zb) / 2), (0, out * math.pi / 2, 0)))
                else:
                    V.box("FurnitureWood", (0.05, yb - ya, zt - zb), (px, (ya + yb) / 2, (zt + zb) / 2), bevel=0.02, matrix=m)
            y = yb + 0.3
            k += 1
        # Balusters, the handrail and the newels.
        bx = sx - 0.1
        for i in range(steps):
            for f in (0.25, 0.75):
                yy = (i + f) * tread
                baluster(V, "FurnitureWood", bx, yy, nose(yy) + 0.35, 2.75, m)
        length = math.hypot(end + 0.5, (end + 0.5) * slope)
        V.box("FurnitureWood", (0.34, length, 0.24), (bx, end / 2, nose(end / 2) + 3.2), rot=(math.atan(slope), 0, 0), bevel=0.06, matrix=m)
        newel(V, m, bx, -0.45, base, nose(-0.45) + 3.3)
        if top_newel:
            newel(V, m, bx, end + TOP_NEWEL, base, nose(end) + 3.0)
    for side in (0, 1):
        if side not in open_sides:  # the wall string
            sx = 0.0 if side == 0 else width - 0.14
            pts = [(-0.1, max(base, -0.3) + 0.0), (end, nose(end) - 0.6), (end, nose(end) + 0.45), (-0.1, nose(-0.1) + 0.45)]
            V.prism("FurnitureWood", pts, 0.14, sm @ Matrix.Translation((0, -(sx + 0.14), 0)))
    return end


def column(V, x, y, z0, z1):
    """A turned column holding up a gallery."""
    h = z1 - z0
    V.box("FurnitureWood", (0.8, 0.8, 0.5), (x, y, z0 + 0.25), bevel=0.04)
    V.lathe("FurnitureWood", [(0.34, 0.5), (0.26, 0.7), (0.24, h * 0.45), (0.3, h * 0.5), (0.22, h * 0.55), (0.2, h - 0.7), (0.32, h - 0.45), (0.4, h - 0.2), (0.4, h)], (x, y, z0), segments=12)


def chandelier_flames():
    """Where the candles' flames burn, from the chandelier's hook (studs, Blender axes)."""
    c = CHANDELIER
    return [Vector((math.cos(a) * c["reach"] * U, math.sin(a) * c["reach"] * U, -(c["tip"] - 0.035) * U))
            for a in (k * 2 * math.pi / c["arms"] for k in range(c["arms"]))]


def entrance(lamp, figure, hang=None, drop=None, range_=None, flames=()):
    """The entrance hall the game dresses (World/BlenderLot.dressHall): where its light hangs
    (and `hang`, the furniture piece hung there, `drop` above its light), the light's `range_`,
    the hanging piece's candle flames, and where a figure stands looking out. Add the furniture
    spots to its "props": (at, yaw degrees from facing the street, pieces, chance)."""
    return dict(lamp=Vector(lamp), figure=Vector(figure), hang=hang, drop=drop, range=range_, flames=list(flames), props=[])


def hall_lines(hall):
    """Luau table rows for an entrance hall (shared with housekit.Data), one tab in."""
    def v3(p):
        return f"Vector3.new({p.x:.2f}, {p.y:.2f}, {p.z:.2f})"

    lines = ["\thall = {", f"\t\tlamp = {v3(hall['lamp'])},", f"\t\tfigure = {v3(hall['figure'])},"]
    if hall.get("hang"):
        lines.append(f'\t\thang = "{hall["hang"]}",')
    if hall.get("drop") is not None:
        lines.append(f"\t\tdrop = {hall['drop']:.2f},")
    if hall.get("range") is not None:
        lines.append(f"\t\trange = {hall['range']:.1f},")
    if hall.get("flames"):
        lines.append("\t\tflames = { " + ", ".join(v3(f) for f in hall["flames"]) + " },")
    lines.append("\t\tprops = {")
    for at, yaw, pieces, chance in hall["props"]:
        names = ", ".join(f'"{n}"' for n in pieces)
        lines.append(f"\t\t\t{{ at = {v3(Vector(at))}, yaw = {yaw:.1f}, pieces = {{ {names} }}, chance = {chance:.2f} }},")
    lines += ["\t\t},", "\t},"]
    return lines


def victorian_foyer(V):
    """The Victorian's entrance hall, two storeys high behind the front door: a vestibule (the
    tower takes the front right corner), a steep stair up the left wall to a gallery across the
    back, dark doorways under the gallery, on it and in the right wall, a cupboard under the stairs,
    a chandelier on a long chain from a ceiling rose. Returns its data for the game."""
    FOUND, STORY = V.FOUND, V.STORY
    F = FOUND + 0.5  # the ground floor (on the foundation's trim band)
    C = FOUND + 2 * STORY - 0.6
    steps, rise, tread = 13, 9.0 / 13, 0.64
    G = F + steps * rise  # the gallery
    sy = 5.6  # the first riser (the front door swings open just short of the newel)
    gy = sy + steps * tread  # the gallery's front edge
    outline = [(-3.8, 0.9), (5.0, 0.9), (5.0, 4.7), (7.4, 4.7), (7.4, 16.4), (-3.8, 16.4), (-3.8, 4.7)]
    # Doorways (along the room face from each wall's start, width, height, height above the floor).
    doors = {
        3: [(9.5 - 4.8, 3.4, 7.6, 0.0)],  # right wall, into the parlour's dark
        4: [(7.3 - 1.5, 4.0, 7.2, 0.0), (7.3 - 4.5, 3.0, 6.8, G - F)],  # under the gallery, and on it
    }
    edges = hall_walls(V, outline, F, C, "Wallpaper", doors, plain=(5,))
    slabs(V, "Floorboards", [(-3.8, 5.0, 0.9, 4.7), (-3.8, 7.4, 4.7, 16.4)], F)
    slabs(V, "Plaster", [(-3.8, 5.0, 0.9, 4.7), (-3.8, 7.4, 4.7, 16.4)], C, top=False)
    # The stair, the cupboard under it, the gallery on a beam and a column.
    stair = V.frame_matrix((-3.7, sy, F))
    flight(V, stair, steps, rise, tread, 2.6, open_sides=(1,), cupboard=(1, 4.2))
    V.box("Floorboards", (11.0, 16.3 - gy, 0.75), (1.8, (gy + 16.3) / 2, G - 0.375))
    V.box("FurnitureWood", (8.1, 0.3, 1.08), (3.25, gy - 0.15, G - 0.46), bevel=0.04)  # the beam's fascia, a lip above the floor
    V.box("FurnitureWood", (8.1, 0.2, 0.22), (3.25, gy - 0.1, G - 1.1), bevel=0.03)
    column(V, 4.4, gy - 0.15, F, G - 1.21)
    balustrade(V, (-1.0, gy + TOP_NEWEL), (7.25, gy + TOP_NEWEL), G, newels=(False, False))
    m3, m4, m5 = edges[3][0], edges[4][0], edges[5][0]
    gaps4 = [(7.3 - 4.5, 3.0 + 0.9, G - F, 7.25)]
    run(V, "FurnitureWood", m3, gy - 4.8, 11.5, 0.18, G - F, G - F + 0.62, [], bevel=0.03)
    run(V, "FurnitureWood", m4, 0.18, 11.0, 0.18, G - F, G - F + 0.62, gaps4, bevel=0.03)
    run(V, "FurnitureWood", m5, 0.18, 16.3 - gy, 0.18, G - F, G - F + 0.62, [], bevel=0.03)
    # The ceiling rose, and a chain down to where the chandelier hangs.
    lamp = Vector((1.8, 8.8, 15.6))
    rose(V, lamp.x, lamp.y, C)
    chain(V, lamp.x, lamp.y, C - 0.3, lamp.z + 0.05)
    hall = entrance(lamp, (5.4, 15.5, F), hang="Chandelier", drop=CHANDELIER["light"] * U, range_=26, flames=chandelier_flames())
    on_stair = lambda k: (sy + (k + 0.5) * tread, F + (k + 1) * rise)
    hall["props"] += [
        ((1.5, 6.5, F), 0, ["Runner"], 0.85),
        ((-2.7, 2.4, F), 90, ["CoatRack", "UmbrellaStand"], 0.9),
        ((4.9 - 0.18 - 0.61, 2.9, F), -90, ["Console"], 0.85),
        ((4.9 - 0.19, 2.9, F + 6.2), -90, ["HallMirror", "Portrait"], 0.85),
        ((7.3 - 0.18 - 0.57, 6.1, F), -90, ["Clock"], 0.9),
        ((-3.7 + 0.115, 2.7, F + 6.0), 90, ["Portrait"], 0.6),
        ((-3.7 + 0.115, 7.6, F + 8.3), 90, ["Portrait"], 0.8),
        ((-3.7 + 0.115, 10.6, F + 11.4), 90, ["Portrait", "HallMirror"], 0.7),
        ((4.4, 11.6, F), 160, ["Pram", "Doll", "SheetChair"], 0.75),
        ((-2.4, on_stair(4)[0], on_stair(4)[1]), 0, ["Doll"], 0.35),
        ((5.6, 15.4, G), 0, ["DressForm", "SheetTall"], 0.55),
    ]
    return hall


def balustrade(V, a, b, z, height=3.2, spacing=0.55, newels=(True, True)):
    """A gallery's balustrade from a to b (floor-plan points) on a floor at z: a bottom rail,
    turned balusters, a handrail, and newel posts at the ends."""
    a, b = Vector((a[0], a[1], 0)), Vector((b[0], b[1], 0))
    d = b - a
    length = d.length
    m = V.frame_matrix((a.x, a.y, z), (0, 0, math.atan2(d.y, d.x)))
    V.box("FurnitureWood", (length, 0.3, 0.22), (length / 2, 0, 0.11), bevel=0.04, matrix=m)
    n = max(1, int(length / spacing))
    for k in range(1, n):
        baluster(V, "FurnitureWood", k * length / n, 0, 0.22, height - 0.46, m)
    V.box("FurnitureWood", (length, 0.38, 0.24), (length / 2, 0, height - 0.12), bevel=0.06, matrix=m)
    for end, x in zip(newels, (0.0, length)):
        if end:
            newel(V, m, x, 0, -0.6, height + 0.1)


def main_rooms(V):
    FOUND, STORY, T = V.FOUND, V.STORY, V.T
    g0, c0 = FOUND + 0.5, FOUND + STORY - 0.6  # on top of the foundation's trim slab
    g1, c1 = FOUND + STORY, FOUND + 2 * STORY - 0.6
    xi0, xi1 = V.MAIN["x0"] + T, V.MAIN["x1"] - T
    yb = V.MAIN["y1"] - T
    bay_front = V.BAY["y"] + T
    bay_side = V.BAY["x1"] - T
    rooms = [
        dict(id="R1", x0=xi0, x1=bay_side, y0=bay_front, y1=9.0, floor=g0, ceil=c0, paper="WallpaperB", lamp_x=-9.0, lamp_y=3.0),
        dict(id="U1", x0=xi0, x1=bay_side, y0=bay_front, y1=9.0, floor=g1, ceil=c1, paper="WallpaperC"),
        dict(id="R2", x0=xi0, x1=-4.7, y0=13.0, y1=yb, floor=g0, ceil=c0, paper="WallpaperA"),
        dict(id="U2", x0=xi0, x1=-4.7, y0=11.0, y1=yb, floor=g1, ceil=c1, paper="WallpaperB"),
        dict(id="R3", x0=-4.5, x1=5.0, y0=16.6, y1=yb, floor=g0, ceil=c0, paper="WallpaperC"),
        dict(id="U3", x0=-4.5, x1=5.0, y0=16.6, y1=yb, floor=g1, ceil=c1, paper="WallpaperA"),
        dict(id="R4", x0=7.6, x1=xi1, y0=7.0, y1=15.0, floor=g0, ceil=c0, paper="WallpaperA"),
        dict(id="U4", x0=7.6, x1=xi1, y0=7.0, y1=15.0, floor=g1, ceil=c1, paper="WallpaperC"),
        # The stair hall: a doorway in its inner wall opens into darkness.
        dict(id="R5", x0=7.6, x1=xi1, y0=15.2, y1=yb, floor=g0, ceil=c0, paper="WallpaperB", doorway_side=3, doorway=(-1.5, 4.0, 8.0)),
        dict(id="U5", x0=7.6, x1=xi1, y0=15.2, y1=yb, floor=g1, ceil=c1, paper="WallpaperA"),
    ]
    roles = {'R1': ('living', 'y0'), 'U1': ('living', 'y0'), 'R2': ('kitchen', 'x0'), 'U2': ('living', 'x0'), 'R3': ('living', 'y1'), 'U3': ('living', 'y1'), 'R4': ('living', 'x1'), 'U4': ('living', 'x1'), 'R5': ('hall', 'x1'), 'U5': ('attic', 'x1')}
    lamps = []
    for room in rooms:
        lamp = box_room(V, room)
        furnish(V, room)
        role, front = roles[room["id"]]
        lamps.append(room_entry(room, lamp, role, front))
    return lamps


def tower_rooms(V):
    """An octagonal room on each tower floor, papered all round (the side facing the house too)."""
    a, T, FOUND, STORY = V.TOWER["apothem"], V.T, V.FOUND, V.STORY
    lean = V.frame_matrix((V.TOWER["x"], V.TOWER["y"], 0), (math.radians(-1.4), math.radians(2.0), 0))
    r = a - T - WALL / 2
    pw = 2 * r * math.tan(math.pi / 8)
    lamps = []
    floors = [
        ("T1", FOUND + 0.3, FOUND + STORY - 0.6, "WallpaperC"),
        ("T2", FOUND + STORY, FOUND + 2 * STORY - 0.6, "WallpaperA"),
        ("T3", FOUND + 2 * STORY, V.TOWER["eave"] - 0.6, "WallpaperB"),
    ]
    for rid, z0, z1, paper in floors:
        h = z1 - z0
        for k in range(8):
            m = lean @ V.frame_matrix((0, 0, 0), (0, 0, k * math.pi / 4)) @ Matrix.Translation((0, -r, z0 + h / 2))
            slab = V.box(paper, (pw + 0.05, WALL, h), (0, 0, 0), matrix=m)
            cutters = opening_cutters(V, m, (pw, WALL, h))
            if cutters:
                V.cut(slab, cutters)
            V.box("FurnitureWood", (pw, 0.08, 0.45), (0, 0.08, -h / 2 + 0.225), matrix=m)
        for z, grp in ((z0 - 0.1, "Floorboards"), (z1 + 0.1, "Plaster")):
            bm = bmesh.new()
            ring = [bm.verts.new((math.sin(k * math.pi / 4 + math.pi / 8) * (r / math.cos(math.pi / 8)), -math.cos(k * math.pi / 4 + math.pi / 8) * (r / math.cos(math.pi / 8)), -0.1)) for k in range(8)]
            face = bm.faces.new(ring)
            ext = bmesh.ops.extrude_face_region(bm, geom=[face])
            bmesh.ops.translate(bm, vec=Vector((0, 0, 0.2)), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            bmesh.ops.transform(bm, matrix=lean @ Matrix.Translation((0, 0, z)), verts=bm.verts)
            V.mesh_object("TowerFloor", bm, grp)
        centre = lean @ Vector((0, 0, 0))
        pendant(V, centre.x, centre.y, z1)
        half = r * 0.7  # a square inside the octagon for the furniture
        box = dict(id=rid, x0=centre.x - half, x1=centre.x + half, y0=centre.y - half, y1=centre.y + half, floor=z0, ceil=z1)
        lamps.append(room_entry(box, lean @ Vector((0, 0, z1 - 1.2)), "tower", "y0"))
    return lamps


def attic(V):
    """The attic behind the bay gable window: plank walls and floor (the game furnishes it). Kept
    narrow and shallow so it stays under the bay roof and in front of the main roof."""
    EAVE = V.EAVE
    x0, x1, y0, y1 = -11.2, -6.8, V.BAY["y"] + V.T, 0.3
    floor, ceil = EAVE + 0.2, EAVE + 6.6
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    for i in range(4):
        wall_slab(V, "Boards", corners[i], corners[(i + 1) % 4], floor, ceil)
    V.box("Floorboards", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, floor - 0.1))
    V.box("Boards", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, ceil + 0.1))
    room = dict(id="ATTIC", x0=x0, x1=x1, y0=y0, y1=y1, floor=floor, ceil=ceil)
    return [room_entry(room, Vector((-9.0, -1.0, ceil - 1.25)), "attic", "y0")]


def room_lines(rooms):
    """Luau table rows for the rooms (shared with housekit.Data)."""
    lines = []
    for r in rooms:
        p = r["lamp"]
        x0, x1, y0, y1, f, c = r["box"]
        figure = "true" if r["front"] == "y0" and r["role"] in ("living", "tower", "attic") else "false"
        lines.append(
            f'\t\t{{ id = "{r["id"]}", lamp = Vector3.new({p.x:.2f}, {p.y:.2f}, {p.z:.2f}), figure = {figure}, '
            f'attic = {"true" if r["role"] == "attic" else "false"}, role = "{r["role"]}", front = "{r["front"]}", '
            f"box = {{ x0 = {x0:.2f}, x1 = {x1:.2f}, y0 = {y0:.2f}, y1 = {y1:.2f}, floor = {f:.2f}, ceil = {c:.2f} }} }},"
        )
    return lines


def write_luau(V, lamps, hall):
    path = V.ROOT.parent / "src" / "server" / "World" / "HouseData" / "VictorianRooms.luau"
    lines = [
        "--!strict",
        "-- Generated by art/scripts/interiors.py: the rooms behind the windows of the Blender Victorian,",
        "-- in its coordinates (x right, y back from the street, z up): each room's lamp, its box, its role",
        "-- and which wall is its front (the window side the furniture faces), and its entrance hall. The",
        "-- game lights some rooms and furnishes them per house, and dresses the hall (World/BlenderLot,",
        "-- Config/RoomLayouts). Don't edit by hand.",
        "",
        "local HouseData = require(script.Parent.Types)",
        "",
        "local rooms: { HouseData.Room } = {",
    ]
    lines += [line[1:] for line in room_lines(lamps)]
    lines += ["}", ""]
    hall_rows = hall_lines(hall)
    lines += ["local hall: HouseData.Hall = {"] + [line[1:] for line in hall_rows[1:-1]] + ["}", ""]
    lines += ["return { rooms = rooms, hall = hall }", ""]
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print("WROTE", path)


def build(V):
    lamps = main_rooms(V) + tower_rooms(V) + attic(V)
    global HALL
    hall = HALL = victorian_foyer(V)
    write_luau(V, lamps, hall)
    return lamps
