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
    for room in FIGURE_ROOMS:
        M["Figure_" + room] = M["Silhouette"]


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
    """A dark old portrait: frame, canvas, a pale face and the shoulders of someone in black."""
    V.box("FurnitureWood", (w + 0.12, 0.05, h + 0.12), (0, 0, 0), bevel=0.02, matrix=m)
    V.box("Canvas", (w, 0.02, h), (0, -0.03, 0), matrix=m)
    face = m @ Matrix.Translation((0, -0.05, h * 0.12)) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((1, 1.3, 0.25, 1))
    V.lathe("Pale", [(0.0, -0.13), (0.09, -0.1), (0.11, 0.0), (0.09, 0.1), (0.0, 0.13)], (0, 0, 0), segments=10, matrix=face)
    V.prism("Canvas", [(-0.22, -h / 2 + 0.02), (0.22, -h / 2 + 0.02), (0.14, -h * 0.08), (-0.14, -h * 0.08)], 0.01, m @ Matrix.Translation((0, -0.045, 0)))


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
        V.lathe("Iron", [(0.015, 0), (0.02, 0.03), (0.0, 0.05)], (sx * 0.15, -0.3, 1.1), segments=6, matrix=m @ Matrix.Rotation(math.pi / 2, 4, "X"))


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
    for i in range(4):
        V.box("Pale", (0.21, 0.29, 0.004), (-0.3 + i * 0.13, -0.05 + i * 0.02, 0.786), rot=(0, 0, 0.2 * (i - 1.5)), matrix=m)
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
            V.box("FurnitureWood", (0.02, 0.02, 0.6), (x, sy, 0.65), matrix=m)
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


FIGURE_ROOMS = ("U1", "R5", "T3")


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
    skirting and a picture rail on both faces."""
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
    for side in (-1, 1):
        skirting = V.box("FurnitureWood", (length, 0.06, 0.45), (0, side * 0.07, -h / 2 + 0.225), matrix=m)
        gaps = opening_cutters(V, m, (length, WALL, h))
        if doorway:
            gaps.append(V.box("_cutters", (doorway[1], 1.0, doorway[2]), (doorway[0], 0, -h / 2 + doorway[2] / 2), matrix=m))
        if gaps:
            V.cut(skirting, gaps)
        V.box("FurnitureWood", (length, 0.05, 0.12), (0, side * 0.07, h / 2 - 1.3), matrix=m)
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
    """Hand-placed furniture for each room (world coordinates, studs). Pieces face -Y at yaw 0, so
    yaw pi faces +Y, pi/2 faces +X and -pi/2 faces -X."""
    rid, f = room["id"], room["floor"]
    pi = math.pi
    if rid == "R1":  # parlour, seen through the bay window: fireplace on the far wall
        fireplace(V, at(V, -9.0, 8.9 - 0.3 * U, f))
        armchair(V, at(V, -11.6, 4.4, f, pi * 0.8))
        armchair(V, at(V, -6.3, 4.0, f, -pi * 0.75))
        side_table(V, at(V, -12.9, 6.9, f))
        rug(V, at(V, -9.0, 4.8, f), 2.4, 1.6)
        clock(V, at(V, -14.0 + 0.16 * U, 0.8, f, pi / 2))
        portrait(V, V.frame_matrix((-3.95 - 0.1, 4.0, f + 6.4), (0, 0, -pi / 2)) @ Matrix.Scale(U, 4))
    elif rid == "U1":  # nursery behind the upstairs bay windows; someone may stand at the glass
        crib(V, at(V, -11.4, 8.9 - 0.36 * U, f))
        rocking_chair(V, at(V, -6.6, 3.2, f, -0.25), doll=True)
        wardrobe(V, at(V, -4.0 - 0.3 * U, 6.8, f, -pi / 2))
        for i, (x, y) in enumerate(((-9.6, 2.6), (-8.8, 3.0), (-9.2, 2.4))):
            V.box("FurnitureWood", (0.6, 0.6, 0.6), (x, y, f + 0.3 + (0.6 if i == 2 else 0)), rot=(0, 0, 0.3 * i))  # toy blocks
        portrait(V, V.frame_matrix((-14.0 + 0.1, 1.5, f + 6.0), (0, 0, pi / 2)) @ Matrix.Scale(U * 0.8, 4))
        figure(V, "Figure_U1", at(V, -12.0, -1.0, f, 0.1))
    elif rid == "R2":  # kitchen behind the back door
        stove(V, at(V, -12.2, 23.0 - 0.32 * U, f))
        shelves(V, at(V, -8.0, 13.05 + 0.15 * U, f, pi), seed=3)
        table(V, at(V, -9.5, 18.0, f, 0.1))
        chair(V, at(V, -9.0, 16.0, f, 0.2))
        chair(V, at(V, -11.6, 18.4, f, pi / 2 - 0.3))
        V.box("Pale", (2.8, 2.2, 0.04), (-9.4, 18.1, f + 2.88), rot=(0, 0, 0.4))  # a cloth on the table
    elif rid == "U2":  # corner bedroom
        bed(V, at(V, -9.6, 11.1 + 1.0 * U, f, pi))
        dresser(V, at(V, -14.0 + 0.23 * U, 20.6, f, pi / 2))
        wardrobe(V, at(V, -4.8 - 0.3 * U, 20.8, f, -pi / 2))
        chair(V, at(V, -12.4, 13.2, f, -pi * 0.2))
    elif rid == "R3":  # dining room
        table(V, at(V, 0.2, 19.8, f), w=1.8, d=1.0)
        for sx in (-0.55, 0.0, 0.55):
            chair(V, at(V, 0.2 + sx * U, 19.8 - 0.7 * U, f, 0))
            chair(V, at(V, 0.2 + sx * U, 19.8 + 0.7 * U, f, pi))
        candelabra(V, at(V, 0.2, 19.8, f + 0.78 * U))
        portrait(V, V.frame_matrix((0.0, 16.6 + 0.15, f + 6.4), (0, 0, pi)) @ Matrix.Scale(U * 1.1, 4))
    elif rid == "U3":  # everything under dust sheets
        lump(V, "Cloth", (2.0, 0.85, 0.85), at(V, 0.0, 19.4, f), seed=1)
        lump(V, "Cloth", (0.5, 0.5, 1.0), at(V, -3.0, 21.8, f), seed=2)
        lump(V, "Cloth", (0.35, 0.25, 1.9), at(V, 3.6, 22.0, f, 0.3), seed=3)
        lump(V, "Cloth", (0.6, 0.4, 0.75), at(V, 2.7, 17.6, f, -0.4), seed=4)
    elif rid == "R4":  # study: shelves on the inner wall, facing the window
        for i, y in enumerate((9.0, 12.9)):
            bookshelf(V, at(V, 7.7 + 0.17 * U, y, f, pi / 2), seed=10 + i)
        desk(V, at(V, 12.0, 11.0, f, -pi / 2))
        chair(V, at(V, 10.6, 11.0, f, pi / 2))
        rug(V, at(V, 11.0, 11.0, f), 1.8, 1.4)
    elif rid == "U4":  # second bedroom, the bed running along the room
        bed(V, at(V, 10.0, 15.0 - 0.1 - 1.0 * U, f))
        rocking_chair(V, at(V, 12.8, 8.6, f, pi / 2 + 0.3))
        chair(V, at(V, 8.6, 8.0, f, pi * 0.75))
    elif rid == "R5":  # stair hall; the doorway on the inner wall opens into darkness
        stairs(V, at(V, 12.1, 15.9, f), steps=7)
        V.box("FurnitureWood", (3.8, 0.6, 4.76), (12.1, 22.75, f + 2.38))  # landing
        V.box("FurnitureWood", (2.6, 1.0, 2.8), (9.4, 22.4, f + 1.4), bevel=0.05)  # hall table
        V.lathe("Glass", [(0.25, 2.8), (0.45, 3.4), (0.2, 4.1), (0.3, 4.4)], (9.4, 22.4, f), segments=10)  # a vase
        figure(V, "Figure_R5", at(V, 9.6, 18.4, f, pi / 2))
    elif rid == "U5":  # boarded-up junk room
        for i, (x, y) in enumerate(((9.5, 21.5), (12.4, 21.0), (11.0, 17.5))):
            crate(V, at(V, x, y, f, 0.3 * i))
        lump(V, "Cloth", (0.6, 0.5, 0.7), at(V, 9.0, 17.0, f), seed=5)


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
    lamps = []
    for room in rooms:
        lamp = box_room(V, room)
        furnish(V, room)
        lamps.append((room["id"], lamp, False))
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
        lamp = pendant(V, centre.x, centre.y, z1)
        lamps.append((rid, lean @ Vector((0, 0, z1 - 1.2)), False))
        # Furniture, in tower-local positions turned into world ones.
        def spot(x, y, yaw=0.0):
            p = lean @ Vector((x, y, 0))
            return at(V, p.x, p.y, z0, yaw)

        if rid == "T1":  # a little library: shelves round the back, a chair facing the front window
            for k in (3, 4, 5):
                th = k * math.pi / 4
                bookshelf(V, spot(math.sin(th) * (r - 0.75), -math.cos(th) * (r - 0.75), th + math.pi), seed=20 + k)
            armchair(V, spot(0.3, 0.6, 0.0))
            side_table(V, spot(-1.8, 1.4))
        elif rid == "T2":
            lump(V, "Cloth", (0.7, 0.45, 0.8), spot(-1.0, 1.2, 0.3), seed=11)
            lump(V, "Cloth", (0.3, 0.2, 1.7), spot(1.8, 1.6, -0.5), seed=12)
            crate(V, spot(1.6, -1.2, 0.6))
        else:  # the top: one chair turned to face the front window, and sometimes someone by it
            chair(V, spot(0.4, -0.6, 0.15))
            figure(V, "Figure_T3", spot(-1.0, -2.4, 0.15))
    return lamps


def attic(V):
    """The attic behind the bay gable window: plank walls, crates, a trunk and a dress form. Kept
    narrow and shallow so it stays under the bay roof and in front of the main roof."""
    EAVE = V.EAVE
    x0, x1, y0, y1 = -11.2, -6.8, V.BAY["y"] + V.T, 0.3
    floor, ceil = EAVE + 0.2, EAVE + 6.6
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    for i in range(4):
        wall_slab(V, "Boards", corners[i], corners[(i + 1) % 4], floor, ceil)
    V.box("Floorboards", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, floor - 0.1))
    V.box("Boards", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, ceil + 0.1))
    crate(V, at(V, -10.2, -0.5, floor, 0.4), s=0.5)
    crate(V, at(V, -10.0, -0.6, floor + 0.4 * U, 0.1), s=0.38)
    V.box("FurnitureWood", (1.8, 1.2, 1.3), (-7.8, -0.5, floor + 0.65), rot=(0, 0, -0.2), bevel=0.06)  # a trunk
    dress_form(V, at(V, -10.4, -2.1, floor, 0.4))
    V.box("Iron", (0.04, 0.04, 1.2), (-9.0, -1.0, ceil - 0.6))
    return [("ATTIC", Vector((-9.0, -1.0, ceil - 1.25)), True)]


def write_luau(V, lamps):
    path = V.ROOT.parent / "src" / "server" / "World" / "HouseData" / "VictorianRooms.luau"
    lines = [
        "--!strict",
        "-- Generated by art/scripts/interiors.py: the rooms behind the windows of the Blender Victorian,",
        "-- in its coordinates (x right, y back from the street, z up). `lamp` is where each room's lamp",
        "-- hangs; `figure` rooms have a Figure_<id> mesh that Victorian.roomLights may keep. Don't edit",
        "-- by hand: change the rooms in interiors.py and re-export.",
        "",
        "export type Room = { id: string, lamp: Vector3, figure: boolean, attic: boolean }",
        "",
        "local rooms: { Room } = {",
    ]
    for rid, p, is_attic in lamps:
        fig = "true" if rid in FIGURE_ROOMS else "false"
        lines.append(f'\t{{ id = "{rid}", lamp = Vector3.new({p.x:.2f}, {p.y:.2f}, {p.z:.2f}), figure = {fig}, attic = {"true" if is_attic else "false"} }},')
    lines += ["}", "", "return rooms", ""]
    path.write_text("\n".join(lines), encoding="utf-8")
    print("WROTE", path)


def build(V):
    lamps = main_rooms(V) + tower_rooms(V) + attic(V)
    write_luau(V, lamps)
    return lamps
