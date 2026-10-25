"""The homeowners (Blender 4.4, headless), in the player kids' style: chunky, soft, clay-toy
shapes, big round heads on stubby bodies, simple painted faces. Then each one wrong in its own way.
Everything in studs, standing on the origin, facing -Y, built in the rig's six parts (Head, Torso,
LeftArm, RightArm, LeftLeg, RightLeg) with the joints between them.

  Curlers     pink housecoat, curlers, the kids' dot eyes and a smile cut far too wide, all teeth
  Lanky       two kids tall, a small bald head on a long neck, wet black holes for eyes
  Nightgown   black hair over her face, one bloodshot eye staring through it, long toes
  SackMask    a burlap sack for a head, one button eye, the other torn out, a stitched grin
  TankTop     his face is upside down
  Cardigan    granny: huge eyes filling her glasses, a toothless hole of a mouth, knitting
  SweaterVest dad: no face at all, his glasses sitting on blank skin
  Porcelain   a doll: cracked bisque, one glass eye, the other broken out to the dark inside
  Grinner     his whole head opens, the top hinged back, teeth all the way round
  PumpkinSuit a carved jack-o'-lantern head, lit inside, a real eye in one hole
  Widow       a net veil, two points of light, her jaw hanging to her chest
  RavenMan    a crow's head with human teeth in the open beak, talons
  Bathrobe    an old man whose face is melting off his skull
  Butler      polite, a tray in his hand, his head on backwards
  MaskedLady  a serene white mask, below it her own lipless mouth, all teeth
  Gown        a bride: a veil over nothing, dark inside, two points of light
  BagMan      a paper grocery bag over his head, a smile drawn on in marker

    blender -b --factory-startup --python art/scripts/characters.py -- --lineup 0|1|2
    blender -b --factory-startup --python art/scripts/characters.py -- --close Name[,Name]
    blender -b --factory-startup --python art/scripts/characters.py -- --export [Name,Name]

--export bakes each part an atlas and writes art/export/characters/Homeowners.fbx (meshes
Char_Owner_<Name>_<Part>) and src/shared/Config/CharacterModels.luau (part sizes, offsets, joints);
tools/setup_characters.luau files the imported meshes under ReplicatedStorage.Assets.Characters.
"""

import math
import pathlib
import sys
from contextlib import contextmanager

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import figures as F  # noqa: E402
import victorian as V  # noqa: E402

ARGS = V.ARGS
F.setup(V, 1.0)  # the figures.py helpers, in studs
RENDERS = V.ROOT / "renders" / "characters"
UP = Vector((0, 0, 1))


# Shader helpers -----------------------------------------------------------------------------------
def _nodes(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat, mat.node_tree.nodes, mat.node_tree.links


def _math(n, L, op, a, b=None, clamp=False):
    node = n.new("ShaderNodeMath")
    node.operation = op
    node.use_clamp = clamp
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            node.inputs[i].default_value = v
        else:
            L.new(v, node.inputs[i])
    return node.outputs[0]


def _mix(n, L, fac, a, b):
    node = n.new("ShaderNodeMix")
    node.data_type = "RGBA"
    if isinstance(fac, (int, float)):
        node.inputs[0].default_value = fac
    else:
        L.new(fac, node.inputs[0])
    for i, c in ((6, a), (7, b)):
        if isinstance(c, tuple):
            node.inputs[i].default_value = c
        else:
            L.new(c, node.inputs[i])
    return node.outputs[2]


def _register(name, mat, size=2.0):
    V.MATERIALS[name] = mat
    V.UV_RULES[name] = (size, "vertical")
    return mat


def _ao(n, L, out, distance=0.6, amount=0.5):
    """Darkens `out` in the hollows."""
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = distance
    shade = n.new("ShaderNodeMapRange")
    shade.inputs["From Min"].default_value = 0.25
    shade.inputs["To Min"].default_value = 1.0 - amount
    L.new(ao.outputs["AO"], shade.inputs["Value"])
    gray = n.new("ShaderNodeCombineColor")
    for ch in ("Red", "Green", "Blue"):
        L.new(shade.outputs["Result"], gray.inputs[ch])
    mul = n.new("ShaderNodeMix")
    mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    L.new(out, mul.inputs[6])
    L.new(gray.outputs["Color"], mul.inputs[7])
    return mul.outputs[2]


# Materials ----------------------------------------------------------------------------------------
def skin(name, color, centre, paint=(), rough=0.62, veins=0.0, flip=False, sss=0.15, vein_color=(0.22, 0.2, 0.32, 1), roll=0.0):
    """Soft matte clay skin (a touch of subsurface), mottled, with a face painted on round the
    head's `centre` (studs, world). `paint` entries, in head-local studs (x side, z up):
      ("oval", x, z, rx, rz, colour, strength)      soft patches: eye bags, blush; mirrored if x
      ("arc", z0, k, w, h, grow, colour, strength)  a mouth band z = z0 + k x^2, |x| < w, h high
                                                    in the middle (the same as a head groove),
                                                    `grow` wider (lipstick round it)
      ("streak", x, top, bottom, width, colour, strength)  something running down; mirrored
      ("net", bottom, spacing, width, colour, strength)  a diamond net over the face above `bottom`
      ("seg", x0, z0, x1, z1, width, colour, strength)   a drawn line; mirrored
      ("spot", x, z, rx, rz, colour, strength)       an oval on one side only
    An "arc" may end with a slope (z rises by that much per stud of x: a lopsided mouth).
    `veins` darkens fine branching lines over all of it; `flip` puts the face on the back (+Y);
    `roll` (radians about the head's front axis) is for a head lying over to one side."""
    mat, n, L = _nodes(name)
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Subsurface Weight"].default_value = sss
    bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.4, 0.25)
    bsdf.inputs["Subsurface Scale"].default_value = 0.06
    coord = n.new("ShaderNodeTexCoord")
    sep = n.new("ShaderNodeSeparateXYZ")
    L.new(coord.outputs["Object"], sep.inputs["Vector"])
    x = _math(n, L, "SUBTRACT", sep.outputs["X"], centre[0])
    y = _math(n, L, "SUBTRACT", sep.outputs["Y"], centre[1])
    z = _math(n, L, "SUBTRACT", sep.outputs["Z"], centre[2])
    if flip:
        x = _math(n, L, "MULTIPLY", x, -1.0)
        y = _math(n, L, "MULTIPLY", y, -1.0)
    if roll:
        c, sn = math.cos(roll), math.sin(roll)
        x, z = (_math(n, L, "SUBTRACT", _math(n, L, "MULTIPLY", x, c), _math(n, L, "MULTIPLY", z, sn)),
                _math(n, L, "ADD", _math(n, L, "MULTIPLY", x, sn), _math(n, L, "MULTIPLY", z, c)))
    front = _math(n, L, "LESS_THAN", y, -0.15)
    mottle = n.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 2.5
    mottle.inputs["Detail"].default_value = 6
    L.new(coord.outputs["Object"], mottle.inputs["Vector"])
    darker = tuple(c * 0.82 for c in color[:3]) + (1,)
    out = _mix(n, L, mottle.outputs["Fac"], darker, color)

    def oval(cx, cz, rx, rz):
        dx = _math(n, L, "DIVIDE", _math(n, L, "SUBTRACT", x, cx), rx)
        dz = _math(n, L, "DIVIDE", _math(n, L, "SUBTRACT", z, cz), rz)
        d = _math(n, L, "SQRT", _math(n, L, "ADD", _math(n, L, "MULTIPLY", dx, dx), _math(n, L, "MULTIPLY", dz, dz)))
        return _math(n, L, "MULTIPLY", _math(n, L, "SUBTRACT", 1.0, d, clamp=True), front)

    for entry in paint:
        kind = entry[0]
        if kind in ("oval", "spot"):
            _, cx, cz, rx, rz, col, k = entry
            for sx in ((-1, 1) if cx and kind == "oval" else (1,)):
                out = _mix(n, L, _math(n, L, "MULTIPLY", _math(n, L, "POWER", oval(sx * cx, cz, rx, rz), 0.6), k), out, col)
        elif kind == "arc":
            _, z0, kk, w, h, grow, col, k, *rest = entry
            ax = _math(n, L, "DIVIDE", x, w)
            half = _math(n, L, "ADD", _math(n, L, "MULTIPLY", _math(n, L, "SQRT", _math(n, L, "SUBTRACT", 1.0, _math(n, L, "MULTIPLY", ax, ax), clamp=True)), h), grow)
            mid = _math(n, L, "ADD", z0, _math(n, L, "MULTIPLY", _math(n, L, "MULTIPLY", x, x), kk))
            if rest:
                mid = _math(n, L, "ADD", mid, _math(n, L, "MULTIPLY", x, rest[0]))
            off = _math(n, L, "ABSOLUTE", _math(n, L, "SUBTRACT", z, mid))
            smear = n.new("ShaderNodeTexNoise")
            smear.inputs["Scale"].default_value = 9.0
            L.new(coord.outputs["Object"], smear.inputs["Vector"])
            off = _math(n, L, "ADD", off, _math(n, L, "MULTIPLY", _math(n, L, "SUBTRACT", smear.outputs["Fac"], 0.5), grow * 0.8))
            inside = _math(n, L, "SUBTRACT", half, off)
            m = _math(n, L, "MULTIPLY", _math(n, L, "DIVIDE", inside, 0.015), front, clamp=True)
            m = _math(n, L, "MULTIPLY", m, _math(n, L, "LESS_THAN", _math(n, L, "ABSOLUTE", x), w + grow))
            out = _mix(n, L, _math(n, L, "MULTIPLY", _math(n, L, "MINIMUM", m, 1.0), k), out, col)
        elif kind == "streak":
            _, cx, top, bottom, width, col, k = entry
            for sx in ((-1, 1) if cx else (1,)):
                wob = _math(n, L, "MULTIPLY", _math(n, L, "SINE", _math(n, L, "MULTIPLY", z, 17.0 + sx)), width * 0.5)
                dx = _math(n, L, "ABSOLUTE", _math(n, L, "ADD", _math(n, L, "SUBTRACT", x, sx * cx), wob))
                t = _math(n, L, "DIVIDE", _math(n, L, "SUBTRACT", top, z), top - bottom)  # 0 at the top, 1 at the bottom
                taper = _math(n, L, "MULTIPLY", width, _math(n, L, "SUBTRACT", 1.0, _math(n, L, "MULTIPLY", t, 0.6)))
                m = _math(n, L, "MULTIPLY", _math(n, L, "LESS_THAN", dx, taper), _math(n, L, "MULTIPLY", _math(n, L, "GREATER_THAN", t, 0.0), _math(n, L, "LESS_THAN", t, 1.0)))
                m = _math(n, L, "MULTIPLY", _math(n, L, "MULTIPLY", m, front), _math(n, L, "SUBTRACT", 1.0, _math(n, L, "MULTIPLY", t, 0.7)))
                out = _mix(n, L, _math(n, L, "MULTIPLY", m, k), out, col)
        elif kind == "net":
            _, bottom, spacing, width, col, k = entry
            u = _math(n, L, "FRACT", _math(n, L, "DIVIDE", _math(n, L, "ADD", x, z), spacing * 1.4142))
            v = _math(n, L, "FRACT", _math(n, L, "DIVIDE", _math(n, L, "SUBTRACT", x, z), spacing * 1.4142))
            line = _math(n, L, "MAXIMUM", _math(n, L, "LESS_THAN", u, width / spacing), _math(n, L, "LESS_THAN", v, width / spacing))
            m = _math(n, L, "MULTIPLY", _math(n, L, "MULTIPLY", line, front), _math(n, L, "GREATER_THAN", z, bottom))
            out = _mix(n, L, _math(n, L, "MULTIPLY", m, k), out, col)
        elif kind == "seg":
            _, x0, z0, x1, z1, width, col, k = entry
            for sx in (-1, 1):
                vx, vz = sx * (x1 - x0), z1 - z0
                px = _math(n, L, "SUBTRACT", x, sx * x0)
                pz = _math(n, L, "SUBTRACT", z, z0)
                t = _math(n, L, "DIVIDE", _math(n, L, "ADD", _math(n, L, "MULTIPLY", px, vx), _math(n, L, "MULTIPLY", pz, vz)), vx * vx + vz * vz, clamp=True)
                dx = _math(n, L, "SUBTRACT", px, _math(n, L, "MULTIPLY", t, vx))
                dz = _math(n, L, "SUBTRACT", pz, _math(n, L, "MULTIPLY", t, vz))
                d = _math(n, L, "SQRT", _math(n, L, "ADD", _math(n, L, "MULTIPLY", dx, dx), _math(n, L, "MULTIPLY", dz, dz)))
                out = _mix(n, L, _math(n, L, "MULTIPLY", _math(n, L, "MULTIPLY", _math(n, L, "LESS_THAN", d, width), front), k), out, col)
    if veins > 0:
        vor = n.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 3.5
        warp = n.new("ShaderNodeTexNoise")
        warp.inputs["Scale"].default_value = 4.0
        L.new(coord.outputs["Object"], warp.inputs["Vector"])
        mixv = n.new("ShaderNodeMix")
        mixv.data_type = "VECTOR"
        mixv.inputs[0].default_value = 0.25
        L.new(coord.outputs["Object"], mixv.inputs[4])
        L.new(warp.outputs["Color"], mixv.inputs[5])
        L.new(mixv.outputs[1], vor.inputs["Vector"])
        line = _math(n, L, "LESS_THAN", vor.outputs["Distance"], 0.018)
        patch = _math(n, L, "GREATER_THAN", mottle.outputs["Fac"], 0.48)
        out = _mix(n, L, _math(n, L, "MULTIPLY", _math(n, L, "MULTIPLY", line, patch), veins), out, vein_color)
    out = _ao(n, L, out, 0.5, 0.55)
    L.new(out, bsdf.inputs["Base Color"])
    return _register(name, mat)


def eyeball(name, look=(0.0, -1.0, 0.0), iris=(0.32, 0.36, 0.3, 1), iris_size=0.955, pupil_size=0.99, white=(0.85, 0.8, 0.66, 1), veins=0.0, gloss=0.12):
    """A wet eyeball looking along `look`: `white`, red veins crawling in from the edges (`veins`),
    an iris and a pupil (each starts where the cosine off the gaze passes its size: smaller
    numbers, bigger irises)."""
    mat, n, L = _nodes(name)
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = gloss
    bsdf.inputs["Coat Weight"].default_value = 0.8
    coord = n.new("ShaderNodeTexCoord")
    dot = n.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = Vector(look).normalized()
    L.new(coord.outputs["Normal"], dot.inputs[0])
    facing = dot.outputs["Value"]
    out = white
    if veins > 0:
        vor = n.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 9.0
        L.new(coord.outputs["Object"], vor.inputs["Vector"])
        lines = _math(n, L, "MULTIPLY", _math(n, L, "LESS_THAN", vor.outputs["Distance"], 0.03), _math(n, L, "LESS_THAN", facing, iris_size - 0.15))
        out = _mix(n, L, _math(n, L, "MULTIPLY", _math(n, L, "SUBTRACT", iris_size - 0.1, facing, clamp=True), 0.9 * veins), white, (0.6, 0.22, 0.18, 1))
        out = _mix(n, L, _math(n, L, "MULTIPLY", lines, veins), out, (0.55, 0.04, 0.04, 1))
    rim = tuple(c * 0.4 for c in iris[:3]) + (1,)
    out = _mix(n, L, _math(n, L, "GREATER_THAN", facing, iris_size), out, rim)
    out = _mix(n, L, _math(n, L, "GREATER_THAN", facing, iris_size + (pupil_size - iris_size) * 0.15), out, iris)
    out = _mix(n, L, _math(n, L, "GREATER_THAN", facing, pupil_size), out, (0.004, 0.004, 0.004, 1))
    L.new(out, bsdf.inputs["Base Color"])
    return _register(name, mat)


def glow(name, color, strength=4.0):
    """Something that gives off light (a point of light in the dark)."""
    mat, n, L = _nodes(name)
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Emission Color"].default_value = color
    bsdf.inputs["Emission Strength"].default_value = strength
    return _register(name, mat)


def argyle(name, base, diamond, line, scale=0.55):
    """A knitted argyle: diamonds of two colours crossed by thin diagonal lines."""
    mat, n, L = _nodes(name)
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95
    coord = n.new("ShaderNodeTexCoord")
    sep = n.new("ShaderNodeSeparateXYZ")
    L.new(coord.outputs["Object"], sep.inputs["Vector"])
    u = _math(n, L, "DIVIDE", _math(n, L, "ADD", sep.outputs["X"], sep.outputs["Z"]), scale * 1.4142)
    v = _math(n, L, "DIVIDE", _math(n, L, "SUBTRACT", sep.outputs["X"], sep.outputs["Z"]), scale * 1.4142)
    check = _math(n, L, "FLOORED_MODULO", _math(n, L, "ADD", _math(n, L, "FLOOR", u), _math(n, L, "FLOOR", v)), 2.0)
    out = _mix(n, L, check, base, diamond)
    lines = _math(n, L, "MAXIMUM", _math(n, L, "LESS_THAN", _math(n, L, "FRACT", _math(n, L, "ADD", u, 0.5)), 0.05),
                  _math(n, L, "LESS_THAN", _math(n, L, "FRACT", _math(n, L, "ADD", v, 0.5)), 0.05))
    out = _mix(n, L, lines, out, line)
    out = _ao(n, L, out, 0.5, 0.5)
    L.new(out, bsdf.inputs["Base Color"])
    knit = n.new("ShaderNodeTexNoise")
    knit.inputs["Scale"].default_value = 40.0
    L.new(coord.outputs["Object"], knit.inputs["Vector"])
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.2
    L.new(knit.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return _register(name, mat)


def hair(name, color, gloss=0.55, strands=40.0, curly=False):
    """Hair: fine strands running down it (or, `curly`, a tight perm), lighter and darker."""
    mat, n, L = _nodes(name)
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = gloss
    bsdf.inputs["Sheen Weight"].default_value = 0.08
    bsdf.inputs["Specular IOR Level"].default_value = 0.22
    coord = n.new("ShaderNodeTexCoord")
    if curly:
        tex = n.new("ShaderNodeTexVoronoi")
        tex.feature = "SMOOTH_F1"
        tex.inputs["Scale"].default_value = strands / 4
        L.new(coord.outputs["Object"], tex.inputs["Vector"])
        fac = tex.outputs["Distance"]
    else:
        tex = n.new("ShaderNodeTexWave")
        tex.wave_type = "BANDS"
        tex.bands_direction = "X"
        tex.inputs["Scale"].default_value = strands / 10
        tex.inputs["Distortion"].default_value = 3.0
        tex.inputs["Detail"].default_value = 3
        L.new(coord.outputs["Object"], tex.inputs["Vector"])
        fac = tex.outputs["Fac"]
    dark = tuple(c * 0.6 for c in color[:3]) + (1,)
    out = _mix(n, L, fac, dark, color)
    out = _ao(n, L, out, 0.4, 0.6)
    L.new(out, bsdf.inputs["Base Color"])
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    L.new(fac, bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return _register(name, mat)


def plain(name, color, rough=0.9, coat=0.0):
    mat, n, L = _nodes(name)
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Coat Weight"].default_value = coat
    return _register(name, mat)


def fabric(name, tex, color, size=1.6, rough=0.95, dirt=0.6, tint=None):
    mat = V.textured(name, tex, paint=None if tint else color, tint=tint or (1, 1, 1, 1), rough=rough, dirt=dirt)
    return _register(name, mat, size)


def materials():
    F.materials()
    for name, tex, color, size, dirt in (
        ("Housecoat", "terry_cloth", (1.0, 0.56, 0.68, 1), 1.4, 0.45),
        ("Slipper", "terry_cloth", (0.82, 0.55, 0.6, 1), 0.8, 0.9),
        ("Suit", "caban", (0.075, 0.072, 0.08, 1), 2.2, 0.5),
        ("ShirtWhite", "stretch_poplin", (0.68, 0.66, 0.6, 1), 1.6, 0.9),
        ("Tie", "velour_velvet", (0.26, 0.03, 0.04, 1), 1.0, 0.6),
        ("Gown", "rough_linen", (0.66, 0.64, 0.58, 1), 1.8, 1.0),
        ("Flannel", "poly_wool_herringbone", (0.48, 0.11, 0.09, 1), 1.2, 0.7),
        ("TankTop", "stretch_poplin", (0.82, 0.8, 0.7, 1), 1.6, 1.0),
        ("Sweats", "terry_cloth", (0.45, 0.46, 0.5, 1), 1.4, 0.7),
        ("Sock", "rough_linen", (0.8, 0.78, 0.72, 1), 0.8, 1.0),
        ("Cardigan", "knitted_fleece", (0.62, 0.5, 0.2, 1), 0.9, 0.6),
        ("Skirt", "rough_linen", (0.34, 0.2, 0.3, 1), 1.6, 0.7),
        ("Yarn", "knitted_fleece", (0.65, 0.08, 0.08, 1), 0.5, 0.4),
        ("ShirtBlue", "stretch_poplin", (0.55, 0.66, 0.82, 1), 1.6, 0.6),
        ("Khaki", "poly_wool_herringbone", (0.62, 0.54, 0.38, 1), 1.2, 0.6),
        ("DressBlue", "velour_velvet", (0.25, 0.42, 0.75, 1), 1.2, 0.6),
        ("Ribbon", "velour_velvet", (0.2, 0.35, 0.72, 1), 0.8, 0.4),
        ("Lace", "knitted_fleece", (0.86, 0.83, 0.76, 1), 0.6, 0.8),
        ("Sweater", "knitted_fleece", (0.26, 0.44, 0.26, 1), 0.9, 0.6),
        ("Slacks", "poly_wool_herringbone", (0.32, 0.24, 0.18, 1), 1.2, 0.6),
        ("Felt", "terry_cloth", (0.95, 0.45, 0.08, 1), 1.4, 0.6),
        ("Leotard", "caban", (0.05, 0.05, 0.05, 1), 1.6, 0.4),
        ("Velvet2", "velour_velvet", (0.3, 0.045, 0.06, 1), 1.2, 0.7),
        ("Robe", "terry_cloth", (0.56, 0.64, 0.72, 1), 1.4, 0.7),
        ("Tailcoat", "caban", (0.03, 0.03, 0.035, 1), 2.0, 0.4),
        ("GownGreen", "velour_velvet", (0.08, 0.3, 0.2, 1), 1.2, 0.5),
        ("Bridal", "rough_linen", (0.84, 0.82, 0.76, 1), 1.6, 1.0),
        ("Apron", "rough_linen", (0.76, 0.72, 0.62, 1), 1.6, 1.0),
        ("ShirtGreen", "stretch_poplin", (0.2, 0.3, 0.22, 1), 1.6, 0.6),
    ):
        fabric(name, tex, color, size=size, dirt=dirt)
    fabric("Burlap", "hessian_230", None, size=1.3, dirt=0.8, tint=(0.68, 0.6, 0.47, 1))
    fabric("Rope", "hessian_230", None, size=0.5, dirt=0.6, tint=(0.45, 0.36, 0.25, 1))
    fabric("Denim", "denim_fabric_04", None, size=1.4, dirt=0.8, tint=(0.75, 0.8, 0.9, 1))
    fabric("Leather", "brown_leather", None, size=1.0, rough=0.8, dirt=0.6, tint=(0.55, 0.4, 0.3, 1))
    fabric("Shoe", "brown_leather", None, size=1.0, rough=0.7, dirt=0.4, tint=(0.12, 0.11, 0.11, 1))
    fabric("WallDark", "weathered_plank_siding", None, size=6.0, rough=1.0, dirt=0.6, tint=(0.16, 0.17, 0.2, 1))
    hair("HairMousy", (0.42, 0.37, 0.33, 1), gloss=0.7, strands=90.0, curly=True)
    hair("HairBlack", (0.006, 0.0055, 0.006, 1), gloss=0.4, strands=90.0)
    hair("HairBrown", (0.12, 0.07, 0.04, 1), gloss=0.4, strands=70.0)
    hair("HairGrey", (0.62, 0.62, 0.6, 1), gloss=0.6, strands=80.0)
    hair("HairBlonde", (0.78, 0.62, 0.32, 1), gloss=0.5, strands=50.0)
    hair("HairRed", (0.38, 0.08, 0.05, 1), gloss=0.5, strands=70.0, curly=True)
    hair("Feathers", (0.025, 0.028, 0.04, 1), gloss=0.35, strands=25.0)
    hair("Plume", (0.45, 0.05, 0.08, 1), gloss=0.5, strands=40.0)
    argyle("Argyle", (0.42, 0.1, 0.12, 1), (0.2, 0.22, 0.3, 1), (0.8, 0.75, 0.55, 1))
    for name, color, rough, coat in (
        ("Curler", (0.86, 0.48, 0.6, 1), 0.45, 0.0),
        ("EyeBlack", (0.008, 0.007, 0.008, 1), 0.22, 0.5),
        ("Teeth", (0.78, 0.72, 0.57, 1), 0.4, 0.0),
        ("Thread", (0.6, 0.55, 0.45, 1), 1.0, 0.0),
        ("Wet", (0.02, 0.012, 0.01, 1), 0.05, 1.0),
        ("Button", (0.16, 0.1, 0.07, 1), 0.35, 0.3),
        ("Brass", (0.45, 0.34, 0.16, 1), 0.45, 0.0),  # a dull painted look: not a metal
        ("Stocking", (0.55, 0.45, 0.38, 1), 0.7, 0.0),
        ("Frame", (0.08, 0.06, 0.05, 1), 0.4, 0.0),
        ("Mug", (0.85, 0.82, 0.76, 1), 0.4, 0.0),
        ("Gums", (0.32, 0.04, 0.06, 1), 0.5, 0.0),
        ("Tongue", (0.6, 0.2, 0.25, 1), 0.4, 0.3),
        ("Stem", (0.25, 0.22, 0.1, 1), 0.9, 0.0),
        ("Glove", (0.15, 0.32, 0.12, 1), 0.8, 0.0),
        ("Pearl", (0.82, 0.8, 0.74, 1), 0.3, 0.0),
        ("GloveBlack", (0.03, 0.03, 0.03, 1), 0.6, 0.0),
        ("GloveWhite", (0.85, 0.84, 0.8, 1), 0.8, 0.0),
        ("DeadFlower", (0.2, 0.04, 0.05, 1), 0.9, 0.0),
        ("DeadStem", (0.18, 0.15, 0.08, 1), 0.9, 0.0),
        ("Beak", (0.06, 0.06, 0.065, 1), 0.45, 0.0),
        ("Bone", (0.72, 0.68, 0.58, 1), 0.6, 0.0),
        ("Pewter", (0.42, 0.42, 0.42, 1), 0.5, 0.0),
        ("Rubber", (0.85, 0.7, 0.15, 1), 0.35, 0.0),
        ("TrashBag", (0.02, 0.02, 0.025, 1), 0.25, 0.3),
    ):
        plain(name, color, rough=rough, coat=coat)
    glow("EyeGlow", (1.0, 0.97, 0.9, 1), 6.0)
    glow("EyeRed", (1.0, 0.08, 0.04, 1), 8.0)
    glow("PumpkinLight", (1.0, 0.55, 0.15, 1), 5.0)  # bright in its own right, so it bakes bright too


# Shapes -------------------------------------------------------------------------------------------
def head(grp, centre, size, sockets=(), bumps=(), grooves=(), chin=0.0, jaw=0.2, sag=0.0, sag_bias=0.0, hole=None, thick=0.0, segs=(96, 64)):
    """A big round head from a sphere at `centre` (studs): half widths `size` (x, y, z), fuller low
    down like the kids', narrowing by `jaw` toward a forward `chin`. At the front: `sockets`
    [(x, z, r, depth)] pressed in, `bumps` [(x, z, rx, rz, height)] pushed out, `grooves`
    [(z0, k, w, h, depth[, slope])] cut along z = z0 + k x^2 + slope x (a mouth; skin's "arc" paints
    the same band). `sag` drags the lower face down (more on one side with `sag_bias`), `hole`
    (x, z, r) breaks a ragged piece out of the front, `thick` makes it a shell (a break shows its edge)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs[0], v_segments=segs[1], radius=1.0)
    sx, sy, sz = size
    for v in bm.verts:
        p = v.co.copy()
        x, y, z = p.x * sx, p.y * sy, p.z * sz
        front = max(0.0, -p.y) ** 0.5
        if p.z < -0.15:
            k = (-p.z - 0.15) / 0.85
            x *= 1.0 - jaw * k * k
            y *= 1.0 - jaw * 0.5 * k * k
            if y < 0:
                y -= chin * k * sy
        if sag and p.z < 0.15:
            z -= sag * (0.15 - p.z) / 1.15 * (0.5 + 0.5 * front) * (1.0 + sag_bias * p.x)
        for cx, cz, r, depth in sockets:
            y += depth * math.exp(-((x - cx) ** 2 + (z - cz) ** 2) / (r * r)) * front
        for cx, cz, rx, rz, h in bumps:
            y -= h * math.exp(-(((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2)) * front
        for gr in grooves:
            z0, k, w, h, depth = gr[:5]
            slope = gr[5] if len(gr) > 5 else 0.0
            if abs(x) < w and p.y < 0:
                half = h * math.sqrt(1 - (x / w) ** 2)
                t = abs(z - (z0 + k * x * x + slope * x)) / max(half, 1e-4)
                if t < 1:
                    y += depth * math.sqrt(1 - t * t) * front
        v.co = Vector((x, y, z)) + Vector(centre)
    if hole is not None:
        hx, hz, hr = hole
        c0 = Vector(centre)

        def broken(f):
            c = f.calc_center_median() - c0
            ang = math.atan2(c.z - hz, c.x - hx)
            ragged = hr * (1.0 + 0.3 * math.sin(ang * 5 + 1.3) + 0.18 * math.sin(ang * 11) + 0.12 * noise.noise(c * 9))
            return c.y < 0 and (c.x - hx) ** 2 + (c.z - hz) ** 2 < ragged * ragged

        bmesh.ops.delete(bm, geom=[f for f in bm.faces if broken(f)], context="FACES")
    for f in bm.faces:
        f.smooth = True
    obj = V.mesh_object("Head", bm, grp)
    if thick > 0:
        mod = obj.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = thick
        mod.offset = -1
        V.apply_modifiers(obj)
    return F.soften(obj)


_BVH = {}


def hit(obj, origin, direction):
    """Where a ray first meets `obj` (built in world space): (point, normal) or (None, None)."""
    me = obj.data
    key = (obj.name, len(me.vertices))
    if key not in _BVH:
        _BVH[key] = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(f.vertices) for f in me.polygons])
    loc, normal, _, _ = _BVH[key].ray_cast(Vector(origin), Vector(direction).normalized())
    return loc, normal


def on(p, n):
    """A frame at p whose y axis points into the surface (normal n), z as near up as it can be."""
    y = -n.normalized()
    z = (UP - y * UP.dot(y)).normalized()
    m = Matrix((y.cross(z), y, z)).transposed().to_4x4()
    m.translation = p
    return m


def face_point(obj, centre, x, z):
    """The surface of a head at head-local (x, z), seen from the front."""
    c = Vector(centre)
    return hit(obj, (c.x + x, c.y - 20, c.z + z), (0, 1, 0))


def egg(grp, m, rx, ry, rz, segs=20, rings=12, soft=True):
    obj = F.egg(grp, m, rx, ry, rz, segs=segs, rings=rings)
    return F.soften(obj) if soft else obj


def ball(grp, at, r, segs=18):
    return egg(grp, Matrix.Translation(at), r, r, r, segs=segs, rings=10)


def lathe(grp, profile, at=(0, 0, 0), squash=1.0, segs=40, ripple=None, rot=None, caps=(True, True), thick=0.0, soft=1):
    m = Matrix.Translation(at) @ (rot or Matrix.Identity(4))
    obj = F.shell(grp, profile, m, segs=segs, squash=squash, ripple=ripple, caps=caps, thick=thick)
    return F.soften(obj, soft) if soft else obj


def taper(grp, a, b, ra, rb, bulge=0.0, segs=20):
    """A soft tapered limb from a to b, radii ra and rb, fuller by `bulge` mid-way."""
    a, b = Vector(a), Vector(b)
    d = b - a
    up = d.normalized()
    side = Vector((1, 0, 0)) if abs(up.x) < 0.9 else Vector((0, 1, 0))
    x = up.cross(side).normalized()
    y = up.cross(x)
    basis = Matrix((x, y, up)).transposed().to_4x4()
    basis.translation = a
    ln = d.length
    mid = (ra + rb) / 2 + bulge
    prof = [(ra * 0.6, 0.0), (ra, ln * 0.08), (mid, ln * 0.5), (rb, ln * 0.92), (rb * 0.6, ln)]
    return F.soften(F.shell(grp, prof, basis, segs=segs))


def tube(grp, points, radii, sides=2):
    return F.limb(grp, Matrix.Identity(4), points, radii, sides=sides)


def hand(grp, wrist, down, out, palm=0.22, finger=0.4, fr=0.065, spread=0.1, curl=0.12, knuckles=0.0):
    """A chunky mitten of a hand from `wrist`, hanging along `down`, its back toward `out`: a soft
    palm and four fingers (as long as `finger`), curling toward the palm, and a thumb in front."""
    wrist, down, out = Vector(wrist), Vector(down).normalized(), Vector(out).normalized()
    side = down.cross(out).normalized()
    centre = wrist + down * palm * 0.75
    basis = Matrix((side, out, down)).transposed().to_4x4()
    basis.translation = centre
    egg(grp, basis, palm, palm * 0.55, palm * 0.95, segs=16, rings=10)
    for k, s in enumerate((-1.5, -0.5, 0.5, 1.5)):
        base = centre + down * palm * 0.7 + side * s * spread
        reach = finger * (0.8 if k in (0, 3) else 1.0)
        mid = base + down * reach * 0.55 + out * (0.02 + knuckles)
        tip = base + down * reach - out * curl + side * s * 0.02
        tube(grp, [base, mid, tip], [fr, fr * 0.9, fr * 0.65])
    forward = Vector((0, -1, 0))
    forward = (forward - down * forward.dot(down)).normalized()
    thumb = centre + forward * palm * 0.7
    tube(grp, [thumb, thumb + down * finger * 0.45 + forward * 0.06 - out * 0.05], [fr * 1.05, fr * 0.7])


def cut_faces(obj, test):
    """Deletes the faces of `obj` whose centre passes `test(point)`."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if test(f.calc_center_median())], context="FACES")
    bm.to_mesh(obj.data)
    bm.free()


def panel(grp, profile, at=(0, 0, 0), span=math.pi * 0.6, facing=-math.pi / 2, segs=24, squash=1.0, ripple=None, thick=0.05):
    """Part of a lathe: only `span` of the way round, centred on angle `facing` (front: -pi/2)."""
    bm = bmesh.new()
    rings = []
    for r, z in densify(profile):
        ring = []
        for i in range(segs + 1):
            t = facing - span / 2 + span * i / segs
            rr = max(0.0, r + (ripple(t, z) if ripple else 0.0))
            ring.append(bm.verts.new((math.cos(t) * rr, math.sin(t) * rr * squash, z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    obj = V.mesh_object("Panel", bm, grp)
    mod = obj.modifiers.new("Thick", "SOLIDIFY")
    mod.thickness = thick
    V.apply_modifiers(obj)
    return F.soften(obj)


def densify(profile, step=0.06):
    """A profile [(r, z)] with points added every `step` along it."""
    out = [profile[0]]
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        n = max(1, int(math.hypot(r1 - r0, z1 - z0) / step))
        out += [(r0 + (r1 - r0) * k / n, z0 + (z1 - z0) * k / n) for k in range(1, n + 1)]
    return out


def arc_points(z0, k, w, n, inset=0.0):
    return [(x, z0 + k * x * x) for x in (-w * (1 - inset) + 2 * w * (1 - inset) * i / (n - 1) for i in range(n))]


# Characters ---------------------------------------------------------------------------------------
# Parts and joints ---------------------------------------------------------------------------------
# Each character is built in the rig's six parts: every group is "<Character>_<Part>|<Material>",
# merged and joined per part at the end (one mesh, one baked atlas each).
PARTS = ("Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg")
CUR = {"char": None, "part": None}
PIVOTS = {}  # character -> joint -> (x, y, z), studs, Blender, feet at the origin
EYES = {}  # character -> eye height


@contextmanager
def part(name):
    prev = CUR["part"]
    CUR["part"] = name
    try:
        yield
    finally:
        CUR["part"] = prev


def g(mat):
    """The group for material `mat` in the current character's current part."""
    grp = f"{CUR['char']}_{CUR['part']}|{mat}"
    if grp not in V.MATERIALS:
        V.MATERIALS[grp] = V.MATERIALS[mat]
        V.UV_RULES[grp] = V.UV_RULES.get(mat, (2.0, "vertical"))
    return grp


def arm(side):
    return "LeftArm" if side > 0 else "RightArm"  # the character's left is +x (it faces -Y)


def leg(side):
    return "LeftLeg" if side > 0 else "RightLeg"


def joints(neck, shoulder, hip, eye, face):
    """Where the rig bends: the neck, the left shoulder and hip (the right ones mirrored); the eye
    height, and the head's centre (`face`, for the close-ups)."""
    sx, sy, sz = shoulder
    hx, hy, hz = hip
    PIVOTS[CUR["char"]] = {"Neck": tuple(neck), "LeftShoulder": (sx, sy, sz), "RightShoulder": (-sx, sy, sz), "LeftHip": (hx, hy, hz), "RightHip": (-hx, hy, hz)}
    EYES[CUR["char"]] = eye
    HEADC[CUR["char"]] = tuple(face)


@contextmanager
def track():
    """Collects the objects made inside the block."""
    before = set(bpy.data.objects)
    made = []
    yield made
    made.extend(o for o in bpy.data.objects if o not in before)


def transform(objs, m):
    for obj in objs:
        if obj.type == "MESH":
            obj.data.transform(m)


def about(centre, rot):
    """`rot` (a 4x4 rotation) about the point `centre`."""
    c = Vector(centre)
    return Matrix.Translation(c) @ rot @ Matrix.Translation(-c)


def arms(sleeve, skin_mat, shoulder, elbow, wrist, radii=(0.36, 0.31, 0.28), forearm=None, cuff=None, puff=None, hand_mat=None, sides=(-1, 1), **hand_kw):
    """Both arms (points for the left one, +x; mirrored): a sleeve from the shoulder to the elbow
    and on to the wrist (`forearm` another material: rolled sleeves, bare skin, gloves), a cuff, a
    puffed shoulder, a hand. `sides` (-1 right, 1 left) builds just one."""
    for side in sides:
        s, e, w = (Vector((side * p[0], p[1], p[2])) for p in (shoulder, elbow, wrist))
        with part(arm(side)):
            if puff:
                egg(g(puff[0]), Matrix.Translation(s), puff[1], puff[1] * 0.92, puff[1] * 0.9)
            else:
                ball(g(sleeve), s, radii[0])
            taper(g(sleeve), s, e, radii[0], radii[1])
            taper(g(forearm or sleeve), e, w, radii[1], radii[2])
            if cuff:
                r = radii[2]
                lathe(g(cuff), [(r * 0.95, 0.0), (r * 1.2, 0.02), (r * 1.22, 0.16), (r * 0.95, 0.18)], at=w - Vector((0, 0, 0.12)), segs=24, caps=(False, False))
            down = ((w - e).normalized() + Vector((0, -0.12, -1))).normalized()
            hand(g(hand_mat or skin_mat), w, down, (side, 0.25, 0), **hand_kw)


def legs(mat, hip, ankle, radii=(0.3, 0.26), shoe=None, bulge=0.02):
    """Both legs (left one's points, mirrored), and shoes: (material, (rx, ry, rz), forward)."""
    for side in (-1, 1):
        h, a = (Vector((side * p[0], p[1], p[2])) for p in (hip, ankle))
        with part(leg(side)):
            taper(g(mat), a, h, radii[1], radii[0], bulge=bulge)
            if shoe:
                m, (rx, ry, rz), fwd = shoe
                egg(g(m), Matrix.Translation((a.x, a.y - fwd, rz)), rx, ry, rz)


def ring(r, z, t=0.05, n=10):
    """A small round profile (a torus once lathed): radius r at height z, thickness t."""
    return [(r + t * math.cos(a), z + t * math.sin(a)) for a in (2 * math.pi * k / n for k in range(n + 1))]


def glasses(grp, hc, eye_x, eye_z, r, front, t=0.035):
    """Round wire spectacles over the eyes: two rims, a bridge, arms back to the ears."""
    for side in (-1, 1):
        c = Vector((hc.x + side * eye_x, front, hc.z + eye_z))
        lathe(grp, ring(r, 0.0, t, 10), at=c, rot=Matrix.Rotation(math.pi / 2, 4, "X"), segs=32, caps=(False, False), soft=0)
        tube(grp, [c + Vector((side * r, 0, 0)), c + Vector((side * (r + 0.25), 0.5, 0.05)), Vector((hc.x + side * (eye_x + r + 0.3), hc.y + 0.3, c.z))], [t] * 3, sides=1)
    tube(grp, [Vector((hc.x - eye_x + r, front, hc.z + eye_z)), Vector((hc.x, front - 0.03, hc.z + eye_z + 0.04)), Vector((hc.x + eye_x - r, front, hc.z + eye_z))], [t] * 3, sides=1)


def inside(poly, x, z):
    """Is (x, z) inside the polygon [(x, z)]?"""
    hit_ = False
    for (x0, z0), (x1, z1) in zip(poly, poly[1:] + poly[:1]):
        if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
            hit_ = not hit_
    return hit_


# The cast -----------------------------------------------------------------------------------------
def curlers(o):
    """Mrs. Hollis: pink housecoat, curlers, the kids' dot eyes and a smile cut far too wide."""
    hc = Vector((0.0, 0.0, 5.75))
    smile = (-0.42, 0.34, 0.84, 0.15)
    skin("SkinCurlers", (0.8, 0.7, 0.63, 1), hc + o, veins=0.15, paint=[
        ("oval", 0.43, -0.13, 0.27, 0.14, (0.26, 0.12, 0.16, 1), 0.8),  # bags under the eyes
        ("oval", 0.78, -0.25, 0.22, 0.2, (0.85, 0.38, 0.42, 1), 0.5),  # blush
        ("arc", *smile, 0.055, (0.58, 0.05, 0.1, 1), 1.0),  # lipstick, smeared
        ("arc", *smile, 0.0, (0.1, 0.008, 0.015, 1), 1.0),  # inside the mouth
    ])
    with part("Head"):
        h = head(g("SkinCurlers"), hc, (1.2, 1.08, 1.2), chin=0.04, jaw=0.18,
                 sockets=[(-0.43, 0.12, 0.17, 0.04), (0.43, 0.12, 0.17, 0.04)],
                 bumps=[(0.0, -0.1, 0.11, 0.1, 0.09), (-0.75, -0.3, 0.3, 0.25, 0.05), (0.75, -0.3, 0.3, 0.25, 0.05)],
                 grooves=[(*smile, 0.17)])
        for side in (-1, 1):  # the kids' eyes: black ovals
            p, nrm = face_point(h, hc, side * 0.43, 0.12)
            egg(g("EyeBlack"), on(p + nrm * -0.03, nrm), 0.12, 0.05, 0.16)
        teeth(h, hc, smile, 18, 16)
        lumps = lambda t, z: 0.06 * noise.noise(Vector((math.cos(t) * 2.2, math.sin(t) * 2.2, z * 2.2))) + 0.025 * noise.noise(Vector((math.cos(t) * 7, math.sin(t) * 7, z * 7)))
        cap = lathe(g("HairMousy"), [(0.95, -0.25), (1.24, 0.05), (1.27, 0.45), (1.14, 0.86), (0.82, 1.15), (0.4, 1.31), (0.0, 1.34)],
                    at=hc, squash=0.95, segs=64, ripple=lumps, soft=0)
        cut_faces(cap, lambda c: c.y - hc.y < -0.35 and c.z - hc.z < 0.62 - 0.18 * abs(c.x - hc.x))
        mod = cap.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.07
        V.apply_modifiers(cap)
        F.soften(cap)
        for lon, lat in ((-45, 46), (-15, 52), (15, 52), (45, 46), (-80, 68), (0, 78), (80, 68), (130, 38), (180, 44), (230, 38)):
            lon, lat = math.radians(lon), math.radians(lat)
            d = Vector((math.sin(lon) * math.cos(lat), -math.cos(lon) * math.cos(lat), math.sin(lat)))
            p, nrm = hit(cap, hc + d * 3.0, -d)
            if p is None:
                continue
            axis = UP.cross(d)
            axis = axis.normalized() if axis.length > 0.2 else Vector((1, 0, 0))
            m = Matrix((nrm, axis.cross(nrm), axis)).transposed().to_4x4()
            m.translation = p + nrm * 0.1
            F.soften(F.shell(g("Curler"), [(0.0, -0.26), (0.13, -0.25), (0.14, -0.2), (0.14, 0.2), (0.13, 0.25), (0.0, 0.26)], m, segs=36, ripple=lambda t, z: 0.014 * math.sin(t * 12)))
    with part("Torso"):
        folds = lambda t, z: 0.03 * math.sin(t * 9 + 0.6 * math.sin(t * 3)) * max(0.0, 1.0 - (z - 1.35) / 1.6)
        lathe(g("Housecoat"), [(0.95, 1.35), (1.06, 1.38), (1.12, 1.9), (1.18, 2.6), (1.2, 3.1), (1.12, 3.7), (0.98, 4.15), (0.74, 4.42), (0.4, 4.56), (0.0, 4.58)], squash=0.82, segs=48, ripple=folds)
        lathe(g("Housecoat"), ring(1.21, 3.0, 0.07), squash=0.83, segs=48, caps=(False, False))
        for side in (-1, 1):
            egg(g("Housecoat"), Matrix.Translation((side * 0.17, -1.04, 2.98)) @ Matrix.Rotation(side * 0.4, 4, "Y"), 0.17, 0.07, 0.1)
            tube(g("Housecoat"), [(side * 0.06, -1.04, 2.95), (side * 0.16, -1.07, 2.6), (side * 0.12, -1.05, 2.25)], [0.05, 0.045, 0.04])
        lathe(g("Housecoat"), [(0.36, 4.3), (0.66, 4.33), (0.76, 4.46), (0.5, 4.62), (0.34, 4.6)], squash=0.85, segs=40, caps=(False, False))
        taper(g("SkinCurlers"), (0.0, 0.0, 4.3), (0.0, 0.0, 4.95), 0.34, 0.32)
    arms("Housecoat", "SkinCurlers", (0.95, 0.0, 4.12), (1.32, -0.05, 3.0), (1.38, -0.2, 2.3), radii=(0.37, 0.31, 0.29), cuff="Housecoat",
         palm=0.2, finger=0.5, fr=0.058, spread=0.09)
    legs("SkinCurlers", (0.42, 0.0, 1.55), (0.4, 0.0, 0.3), radii=(0.29, 0.24), shoe=("Slipper", (0.32, 0.5, 0.19), 0.14))
    for side in (-1, 1):
        with part(leg(side)):
            ball(g("Slipper"), (side * 0.42, -0.58, 0.3), 0.13)
    joints((0.0, 0.0, 4.62), (0.95, 0.0, 4.12), (0.42, 0.0, 1.55), hc.z + 0.12, hc)


def teeth(h, hc, smile, top=18, bottom=16, size=0.042, slope=0.0):
    """Teeth crowding a mouth groove (head h at hc), a row along its top and one along its bottom."""
    z0, k, w, hh = smile
    for sign, count in ((1, top), (-1, bottom)):
        for x, zc in arc_points(z0, k, w, count, inset=0.12):
            zc += slope * x
            half = hh * math.sqrt(max(0.0, 1 - (x / w) ** 2))
            p, nrm = face_point(h, hc, x, zc + sign * half * 0.55)
            if p is None:
                continue
            s = size + 0.02 * math.sqrt(max(0.0, 1 - (x / w) ** 2))
            egg(g("Teeth"), on(p + nrm * 0.012, nrm), s, 0.03, half * 0.5, segs=10, rings=6)


def lanky(o):
    """The tall man: no eyes, wet holes, fingers to his knees."""
    hc = Vector((0.0, -0.55, 9.25))
    skin("SkinLanky", (0.6, 0.6, 0.57, 1), hc + o, veins=0.45, paint=[
        ("oval", 0.27, 0.06, 0.26, 0.24, (0.12, 0.1, 0.12, 1), 0.8),  # bruised round the holes
        ("streak", 0.27, -0.05, -0.75, 0.035, (0.05, 0.02, 0.02, 1), 0.95),  # what runs out of them
        ("streak", 0.33, -0.1, -0.55, 0.02, (0.05, 0.02, 0.02, 1), 0.8),
        ("arc", -0.45, 0.05, 0.2, 0.025, 0.0, (0.03, 0.01, 0.01, 1), 1.0),  # a lipless slit
        ("oval", 0.42, -0.32, 0.18, 0.25, (0.35, 0.33, 0.36, 1), 0.6),  # hollow cheeks
    ])
    stoop = about((0, 0, 4.2), Matrix.Rotation(0.1, 4, "X"))  # everything above the hips leans forward
    neck_base = stoop @ Vector((0.0, -0.05, 7.7))
    with part("Head"):
        h = head(g("SkinLanky"), hc, (0.72, 0.76, 0.9), chin=0.05, jaw=0.32,
                 sockets=[(-0.27, 0.06, 0.2, 0.3), (0.27, 0.06, 0.2, 0.3), (-0.42, -0.32, 0.17, 0.07), (0.42, -0.32, 0.17, 0.07)],
                 bumps=[(0.0, -0.12, 0.07, 0.14, 0.08), (0.0, 0.3, 0.45, 0.1, 0.04)],
                 grooves=[(-0.45, 0.05, 0.2, 0.025, 0.05)])
        for side in (-1, 1):  # in each hole, deep down, something wet
            p, nrm = face_point(h, hc, side * 0.27, 0.06)
            egg(g("Hollow"), on(p + nrm * 0.1, nrm), 0.2, 0.06, 0.21, soft=False)
            egg(g("Wet"), on(p + nrm * 0.16, nrm), 0.04, 0.025, 0.035)
        taper(g("SkinLanky"), neck_base, hc + Vector((0.0, 0.1, -0.6)), 0.17, 0.16)  # the long neck bends with the head
    with part("Torso"):
        hem = lambda t, z: 0.02 * math.sin(t * 7) * max(0.0, 1.0 - (z - 4.1) / 0.8)
        jacket = lathe(g("Suit"), [(0.6, 4.1), (0.66, 4.14), (0.6, 5.0), (0.58, 5.8), (0.72, 6.8), (0.86, 7.45), (0.78, 7.72), (0.4, 7.88), (0.0, 7.9)], squash=0.62, segs=40, ripple=hem)
        jacket.data.transform(stoop)
        for side in (-1, 1):  # lapels, the shirt and tie between them
            lap = stoop @ Matrix.Translation((side * 0.2, -0.49, 7.1)) @ Matrix.Rotation(side * 0.32, 4, "Y") @ Matrix.Rotation(-0.08, 4, "X")
            V.box(g("Suit"), (0.16, 0.05, 1.0), (0, 0, 0), matrix=lap, bevel=0.02)
        egg(g("ShirtWhite"), stoop @ Matrix.Translation((0.0, -0.45, 7.2)), 0.2, 0.06, 0.6)
        V.box(g("Tie"), (0.12, 0.04, 0.95), (0, 0, 0), matrix=stoop @ Matrix.Translation((0.0, -0.52, 7.08)), bevel=0.02)
        ball(g("Tie"), stoop @ Vector((0.0, -0.5, 7.62)), 0.08)
        lathe(g("ShirtWhite"), [(0.2, 7.62), (0.23, 7.8), (0.21, 7.95)], rot=stoop, squash=0.9, segs=20, caps=(False, False), thick=0.03)
    shoulder = stoop @ Vector((0.8, -0.05, 7.45))
    arms("Suit", "SkinLanky", shoulder, (0.98, -0.3, 5.7), (0.98, -0.5, 4.05), radii=(0.24, 0.18, 0.16), cuff="ShirtWhite",
         palm=0.26, finger=0.95, fr=0.05, spread=0.085, curl=0.18, knuckles=0.03)
    legs("Suit", (0.33, 0.0, 4.45), (0.35, 0.0, 0.32), radii=(0.27, 0.21), shoe=("Shoe", (0.22, 0.62, 0.16), 0.32))
    joints(neck_base, shoulder, (0.33, 0.0, 4.45), hc.z + 0.06, hc)


def nightgown(o):
    """The pale woman: hair over her face, one bloodshot eye through it, long toes."""
    hc = Vector((0.0, -0.05, 5.55))
    skin("SkinNight", (0.8, 0.83, 0.85, 1), hc + o, veins=0.5, paint=[
        ("oval", 0.36, 0.06, 0.32, 0.3, (0.3, 0.22, 0.28, 1), 0.7),  # dark round the eyes
        ("arc", -0.5, -0.1, 0.25, 0.03, 0.0, (0.25, 0.12, 0.15, 1), 0.9),
    ])
    eyeball("EyeBlood", look=(-0.25, -1.0, -0.1), veins=1.0)
    with part("Head"):
        h = head(g("SkinNight"), hc, (1.05, 1.0, 1.12), chin=0.03, jaw=0.2,
                 sockets=[(-0.36, 0.06, 0.25, 0.12), (0.36, 0.06, 0.25, 0.12)], bumps=[(0.0, -0.15, 0.09, 0.1, 0.06)])
        for side in (-1, 1):
            p, nrm = face_point(h, hc, side * 0.36, 0.06)
            ball(g("EyeBlood"), p + Vector((0, 0.1, 0)), 0.22, segs=24)
        # A cap over the skull, then curtains: in front down to her chest, behind to her waist,
        # parted along the strands where the eye looks through.
        strands = lambda t, z: 0.012 * math.sin(t * 97) + 0.016 * math.sin(t * 23 + z * 2.5) + 0.01 * math.sin(t * 7 - z)
        lathe(g("HairBlack"), [(1.12, 0.4), (1.1, 0.6), (0.96, 0.92), (0.6, 1.2), (0.0, 1.28)], at=hc, segs=160, ripple=strands, thick=0.05)

        def ragged(bottom):
            def test(c):
                a = math.atan2(c.y - hc.y, c.x - hc.x)
                return c.z - hc.z < bottom + 0.22 * math.sin(a * 9) + 0.16 * math.sin(a * 31 + 1.0) + 0.1 * math.sin(a * 73)
            return test

        fall = [(1.0, -2.5), (0.98, -1.8), (1.0, -1.2), (1.12, -0.6), (1.17, -0.1), (1.14, 0.3), (1.09, 0.5)]
        lo, hi, edge = 0.16, 0.5, math.pi * 0.475  # the parting, as angles off the front
        for a, b in ((-edge, lo), (hi, edge)):
            curtain = panel(g("HairBlack"), fall, at=hc, span=b - a, facing=-math.pi / 2 + (a + b) / 2, segs=max(8, int(150 * (b - a) / (2 * edge))), ripple=strands, thick=0.05)
            cut_faces(curtain, ragged(-2.2))
        below = panel(g("HairBlack"), [r for r in fall if r[1] <= -1.0], at=hc, span=hi - lo + 0.04, facing=-math.pi / 2 + (lo + hi) / 2, segs=24, ripple=strands, thick=0.05)
        cut_faces(below, lambda c: ragged(-2.2)(c) or c.z - hc.z > -1.15 + 0.12 * math.sin(c.x * 41))
        back = panel(g("HairBlack"), [(1.02, -3.2), (1.06, -2.4), (1.12, -1.4), (1.16, -0.6), (1.17, -0.1), (1.14, 0.3), (1.09, 0.5)], at=hc, span=math.pi * 1.1, facing=math.pi / 2, segs=170, ripple=strands, thick=0.05)
        cut_faces(back, ragged(-2.9))
    with part("Torso"):
        folds = lambda t, z: 0.035 * math.sin(t * 11 + 0.8 * math.sin(t * 2)) * max(0.0, 1.0 - (z - 0.9) / 1.5) + (0.03 * noise.noise(Vector((t * 2, z, 0))) if z < 1.0 else 0)
        lathe(g("Gown"), [(0.82, 0.9), (0.95, 0.94), (0.86, 1.8), (0.72, 2.8), (0.74, 3.5), (0.8, 3.9), (0.62, 4.3), (0.3, 4.45), (0.0, 4.46)], squash=0.78, segs=48, ripple=folds)
        taper(g("SkinNight"), (0.0, 0.0, 4.3), (0.0, -0.02, 4.85), 0.21, 0.2)
    arms("SkinNight", "SkinNight", (0.72, 0.0, 4.05), (0.86, -0.05, 2.95), (0.9, -0.2, 1.95), radii=(0.16, 0.13, 0.11), puff=("Gown", 0.26),
         palm=0.19, finger=0.68, fr=0.045, spread=0.075, curl=0.1)
    legs("SkinNight", (0.3, 0.0, 1.25), (0.3, 0.0, 0.16), radii=(0.19, 0.15), shoe=("SkinNight", (0.18, 0.34, 0.11), 0.18))
    for side in (-1, 1):
        with part(leg(side)):
            for k in range(5):
                x = side * (0.32 + (k - 2) * 0.065)
                tube(g("SkinNight"), [(x, -0.42, 0.1), (x + side * 0.01 * (k - 2), -0.66, 0.1), (x + side * 0.015 * (k - 2), -0.8, 0.02)], [0.04, 0.035, 0.028])
    joints((0.0, -0.02, 4.75), (0.72, 0.0, 4.05), (0.3, 0.0, 1.25), hc.z + 0.06, hc)


def sackmask(o):
    """The farmer: a sack for a head, one button eye, the other torn out, a stitched grin."""
    hc = Vector((0.0, 0.0, 6.05))
    skin("SkinFarmer", (0.74, 0.6, 0.5, 1), hc + o, veins=0.2)

    def lumps(t, z):
        return 0.05 * noise.noise(Vector((math.cos(t) * 2.2, math.sin(t) * 2.2, z * 2.2))) + 0.015 * math.sin(t * 9 + z * 6)

    with part("Head"):
        sack = lathe(g("Burlap"), [(0.36, -1.18), (0.58, -1.08), (0.42, -0.96), (0.98, -0.72), (1.22, -0.25), (1.25, 0.2), (1.17, 0.6), (0.98, 0.94),
                                   (0.66, 1.18), (0.3, 1.3), (0.0, 1.33)], at=hc, squash=0.95, segs=64, ripple=lumps, rot=Matrix.Rotation(0.06, 4, "Y"))
        egg(g("Burlap"), Matrix.Translation(hc + Vector((0.45, 0.1, 1.15))) @ Matrix.Rotation(-0.7, 4, "Y"), 0.35, 0.3, 0.22)  # the slumped corner
        loop = [(0.47 * math.sin(t), -0.47 * math.cos(t) * 0.95, hc.z - 0.96 + 0.02 * math.sin(3 * t)) for t in (2 * math.pi * k / 12 for k in range(13))]
        tube(g("Rope"), loop, [0.06] * len(loop), sides=3)
        tube(g("Rope"), [(0.12, -0.46, hc.z - 0.97), (0.2, -0.55, hc.z - 1.3), (0.24, -0.5, hc.z - 1.6)], [0.05, 0.045, 0.04], sides=3)
        p, nrm = face_point(sack, hc, -0.43, 0.16)  # the button eye, sewn on with a cross of thread
        m = on(p + nrm * 0.02, nrm)
        F.soften(F.shell(g("Button"), [(0.0, -0.035), (0.22, -0.03), (0.24, 0.0), (0.22, 0.03), (0.17, 0.04), (0.0, 0.025)], m @ Matrix.Rotation(math.pi / 2, 4, "X"), segs=32))
        for a in (0.785, 2.356):
            d = Vector((math.cos(a), 0, math.sin(a))) * 0.1
            tube(g("Thread"), [m @ (-d + Vector((0, -0.06, 0))), m @ Vector((0, -0.075, 0)), m @ (d + Vector((0, -0.06, 0)))], [0.018] * 3, sides=1)
        p, nrm = face_point(sack, hc, 0.43, 0.2)  # the other torn out: a dark hole, something wet, the thread hanging
        egg(g("Hollow"), on(p + nrm * 0.01, nrm), 0.2, 0.06, 0.17, soft=False)
        egg(g("Wet"), on(p + nrm * 0.05, nrm), 0.07, 0.03, 0.06)
        tube(g("Thread"), [p + Vector((0.06, -0.04, -0.15)), p + Vector((0.1, -0.12, -0.4)), p + Vector((0.07, -0.1, -0.62))], [0.016, 0.014, 0.012], sides=1)
        seam = [face_point(sack, hc, x, z) for x, z in arc_points(-0.42, 0.3, 0.74, 15)]
        seam = [(q, qn) for q, qn in seam if q is not None]
        tube(g("Hollow"), [q + qn * 0.005 for q, qn in seam], [0.02] * len(seam), sides=1)
        for q, qn in seam[1:-1]:
            tube(g("Thread"), [q + qn * 0.02 + Vector((0, 0, 0.11)), q + qn * 0.045, q + qn * 0.02 + Vector((0, 0, -0.11))], [0.02, 0.022, 0.02], sides=1)
    with part("Torso"):
        lathe(g("Flannel"), [(0.9, 1.75), (0.98, 2.2), (1.06, 3.0), (1.08, 3.8), (0.98, 4.42), (0.62, 4.68), (0.3, 4.76), (0.0, 4.78)], squash=0.8, segs=44)
        lathe(g("Denim"), [(0.95, 1.68), (1.02, 1.72), (1.03, 2.2), (1.1, 2.95), (1.08, 3.0)], squash=0.81, segs=44, caps=(False, False))
        panel(g("Denim"), [(1.09, 2.9), (1.11, 3.4), (1.1, 3.82)], span=math.pi * 0.36, segs=14, squash=0.81, thick=0.06)
        for side in (-1, 1):
            tube(g("Denim"), [(side * 0.32, -0.92, 3.8), (side * 0.42, -0.6, 4.5), (side * 0.45, 0.0, 4.72), (side * 0.38, 0.65, 4.3), (side * 0.3, 0.85, 3.2)], [0.07] * 5, sides=1)
            ball(g("Brass"), (side * 0.32, -0.95, 3.76), 0.07)
        taper(g("Flannel"), (0.0, 0.0, 4.5), (0.0, 0.0, 5.05), 0.4, 0.38)
    arms("Flannel", "SkinFarmer", (1.0, 0.0, 4.3), (1.3, -0.05, 3.15), (1.36, -0.2, 2.35), radii=(0.36, 0.31, 0.24), forearm="SkinFarmer", hand_mat="Leather",
         palm=0.27, finger=0.42, fr=0.085, spread=0.12, curl=0.1)
    for side in (-1, 1):
        with part(arm(side)):
            lathe(g("Flannel"), [(0.3, 0.0), (0.36, 0.03), (0.37, 0.2), (0.3, 0.23)], at=(side * 1.31, -0.06, 3.0), segs=24, caps=(False, False))
            lathe(g("Leather"), [(0.22, 0.0), (0.3, 0.04), (0.3, 0.3), (0.22, 0.34)], at=(side * 1.37, -0.21, 2.1), segs=24, caps=(False, False))
    legs("Denim", (0.42, 0.0, 1.95), (0.42, 0.0, 0.35), radii=(0.34, 0.3), shoe=("Leather", (0.3, 0.48, 0.24), 0.16))
    joints((0.0, 0.0, 4.95), (1.0, 0.0, 4.3), (0.42, 0.0, 1.95), hc.z + 0.16, hc)


def curl(grp, top, length, r=0.1, turns=3.5, thick=0.085, phase=0.0):
    """A chunky corkscrew ringlet hanging from `top`."""
    pts, radii = [], []
    steps = int(turns * 10)
    for k in range(steps + 1):
        t = k / steps
        a = phase + 2 * math.pi * turns * t
        rr = r * (1.0 - 0.25 * t)
        pts.append((top[0] + math.cos(a) * rr, top[1] + math.sin(a) * rr, top[2] - length * t))
        radii.append(thick * (1.0 - 0.45 * t))
    return tube(grp, pts, radii)


def cap(grp, hc, profile, hairline=0.6, slope=0.18, ripple=None, segs=64, squash=1.0, thick=0.07, front=-0.35):
    """Hair over the top and back of a head, open over the face below `hairline` (head-local)."""
    obj = lathe(grp, profile, at=hc, squash=squash, segs=segs, ripple=ripple, soft=0)
    cut_faces(obj, lambda c: c.y - hc.y < front and c.z - hc.z < hairline - slope * abs(c.x - hc.x))
    mod = obj.modifiers.new("Thick", "SOLIDIFY")
    mod.thickness = thick
    V.apply_modifiers(obj)
    return F.soften(obj)


def kid_eyes(h, hc, x, z, rx=0.12, rz=0.16, mat="EyeBlack"):
    """The player kids' eyes: black ovals set into the face."""
    for side in (-1, 1):
        p, nrm = face_point(h, hc, side * x, z)
        egg(g(mat), on(p + nrm * -0.03, nrm), rx, 0.05, rz)


def sunk(h, hc, x, z, r, glint=True, deep=0.1):
    """Black holes for eyes (in sockets), with a tiny white point of light in each if `glint`."""
    for side in (-1, 1):
        p, nrm = face_point(h, hc, side * x, z)
        egg(g("Hollow"), on(p + nrm * deep, nrm), r, 0.06, r * 1.05, soft=False)
        if glint:
            ball(g("EyeGlow"), p + nrm * (deep + 0.06) + Vector((side * -0.03, 0, 0.02)), 0.035, segs=10)


def front_y(profile, z, squash, y0=0.0):
    """How far forward (-Y) a lathed profile [(r, z)] reaches at height z."""
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        if min(z0, z1) <= z <= max(z0, z1) and z1 != z0:
            return y0 - (r0 + (r1 - r0) * (z - z0) / (z1 - z0)) * squash
    return y0 - profile[-1][0] * squash


def buttons(mat, profile, squash, zs, r=0.06, x=0.0):
    for z in zs:
        ball(g(mat), (x, front_y(profile, z, squash) - r * 0.4, z), r, segs=12)


def bouquet(grp_flower, grp_stem, at, dead=True):
    """A bunch of flowers held at `at`, their heads drooping when `dead`."""
    at = Vector(at)
    for k in range(7):
        a = k * 2.4
        tip = at + Vector((math.cos(a) * 0.22, -0.15 + math.sin(a) * 0.15, 0.55 + 0.1 * math.sin(k)))
        droop = tip + Vector((math.cos(a) * 0.15, -0.1, -0.2 if dead else 0.1))
        tube(grp_stem, [at + Vector((0, 0, -0.35)), at, tip, droop], [0.025, 0.025, 0.022, 0.02], sides=1)
        egg(grp_flower, Matrix.Translation(droop), 0.12, 0.12, 0.1, segs=12, rings=8)


def tank_top(o):
    """The man in the tank top: his face is upside down, bloodshot eyes rolling in it, a grimace of
    teeth across the top of his head."""
    hc = Vector((0.0, 0.0, 5.85))
    frown = (0.42, -0.36, 0.66, 0.14)  # a smile, upside down
    skin("SkinTank", (0.8, 0.66, 0.58, 1), hc + o, veins=0.4, paint=[
        ("oval", 0.0, 0.8, 0.75, 0.35, (0.36, 0.34, 0.38, 1), 0.5),  # stubble, on top, where his chin is
        ("oval", 0.42, -0.02, 0.28, 0.14, (0.35, 0.18, 0.22, 1), 0.75),  # the bags, above the eyes
        ("oval", 0.42, -0.28, 0.3, 0.28, (0.45, 0.24, 0.26, 1), 0.5),  # raw round the eyes
        ("arc", *frown, 0.05, (0.45, 0.12, 0.14, 1), 1.0),
        ("arc", *frown, 0.0, (0.1, 0.01, 0.01, 1), 1.0),
    ])
    eyeball("EyeTank", look=(0.0, -1.0, 0.15), iris=(0.2, 0.12, 0.06, 1), iris_size=0.94, pupil_size=0.985, veins=1.0)
    with part("Head"):
        h = head(g("SkinTank"), hc, (1.25, 1.12, 1.18), jaw=0.02, sockets=[(-0.42, -0.28, 0.22, 0.12), (0.42, -0.28, 0.22, 0.12)],
                 bumps=[(0.0, -0.02, 0.12, 0.14, 0.11), (-0.8, 0.25, 0.3, 0.25, 0.05), (0.8, 0.25, 0.3, 0.25, 0.05)], grooves=[(*frown, 0.18)])
        for side in (-1, 1):
            p, nrm = face_point(h, hc, side * 0.42, -0.28)
            ball(g("EyeTank"), p + Vector((0, 0.09, 0)), 0.21, segs=24)
        teeth(h, hc, frown, 16, 14, size=0.05)
        for side in (-1, 1):
            p, nrm = face_point(h, hc, side * 0.05, 0.1)  # nostrils, on top of the nose
            egg(g("Hollow"), on(p, nrm), 0.035, 0.03, 0.025, segs=10, rings=6)
            brow = [face_point(h, hc, side * x, -0.6 + 0.06 * (x - 0.42) ** 2 * 8)[0] for x in (0.25, 0.42, 0.6)]  # the brows, under the eyes
            tube(g("HairBrown"), [q + Vector((0, -0.04, 0)) for q in brow], [0.045, 0.05, 0.04], sides=1)
            egg(g("SkinTank"), Matrix.Translation(hc + Vector((side * 1.2, 0.05, -0.05))), 0.12, 0.2, 0.3)  # ears
        # His bald man's fringe of hair, round the bottom of his head.
        fringe = lathe(g("HairBrown"), [(1.02, -0.88), (1.2, -0.62), (1.25, -0.36), (1.14, -0.2)], at=hc, squash=0.93, segs=72,
                       ripple=lambda t, z: 0.02 * math.sin(t * 40), caps=(False, False), soft=0)
        cut_faces(fringe, lambda c: c.y - hc.y < -0.45)
        F.soften(fringe)
    torso = [(0.95, 1.5), (1.15, 1.6), (1.38, 2.3), (1.42, 2.9), (1.25, 3.6), (1.08, 4.2), (0.7, 4.48), (0.35, 4.58), (0.0, 4.6)]
    with part("Torso"):
        lathe(g("TankTop"), torso, squash=0.85, segs=48)
        lathe(g("Sweats"), ring(1.0, 1.58, 0.08), squash=0.86, segs=48, caps=(False, False))
        taper(g("SkinTank"), (0.0, 0.0, 4.4), (0.0, 0.0, 4.95), 0.42, 0.4)
    arms("SkinTank", "SkinTank", (1.12, 0.0, 4.15), (1.45, -0.05, 3.05), (1.5, -0.2, 2.3), radii=(0.4, 0.34, 0.3), palm=0.24, finger=0.42, fr=0.075, spread=0.11)
    legs("Sweats", (0.48, 0.0, 1.6), (0.46, 0.0, 0.35), radii=(0.38, 0.32), shoe=("Sock", (0.3, 0.46, 0.22), 0.14))
    for side in (-1, 1):
        with part(leg(side)):
            V.box(g("Leather"), (0.62, 1.05, 0.08), (side * 0.46, -0.16, 0.04), bevel=0.03)
    joints((0.0, 0.0, 4.65), (1.12, 0.0, 4.15), (0.48, 0.0, 1.6), hc.z - 0.28, hc)


def cardigan(o):
    """Granny: huge eyes filling her glasses, a toothless hole of a mouth, knitting."""
    hc = Vector((0.0, -0.2, 5.5))
    mouth = (-0.58, 0.0, 0.2, 0.17)
    skin("SkinGran", (0.83, 0.74, 0.7, 1), hc + o, veins=0.45, paint=[
        ("oval", 0.4, 0.1, 0.42, 0.4, (0.3, 0.2, 0.22, 1), 0.45),  # sunken round the eyes
        ("arc", *mouth, 0.05, (0.42, 0.25, 0.28, 1), 1.0),
        ("arc", *mouth, 0.0, (0.03, 0.0, 0.0, 1), 1.0),
        ("streak", 0.12, -0.72, -1.15, 0.03, (0.3, 0.25, 0.22, 1), 0.6),  # drool
    ])
    # Huge, white, staring: pinprick pupils, veins.
    eyeball("EyeHugeL", look=(-0.08, -1.0, 0.0), iris=(0.3, 0.22, 0.12, 1), iris_size=0.978, pupil_size=0.994, white=(0.92, 0.9, 0.84, 1), veins=1.0)
    eyeball("EyeHugeR", look=(0.22, -1.0, 0.25), iris=(0.3, 0.22, 0.12, 1), iris_size=0.978, pupil_size=0.994, white=(0.92, 0.9, 0.84, 1), veins=1.0)
    with part("Head"):
        h = head(g("SkinGran"), hc, (1.15, 1.05, 1.15), jaw=0.25, sockets=[(-0.4, 0.1, 0.3, 0.12), (0.4, 0.1, 0.3, 0.12)],
                 bumps=[(0.0, -0.18, 0.1, 0.14, 0.12)], grooves=[(*mouth, 0.22)])
        for side, mat in ((-1, "EyeHugeR"), (1, "EyeHugeL")):
            p, nrm = face_point(h, hc, side * 0.4, 0.1)
            ball(g(mat), p + Vector((0, 0.13, 0)), 0.3, segs=28)
        glasses(g("Frame"), hc, 0.4, 0.1, 0.36, hc.y - 1.2)
        cap(g("HairGrey"), hc, [(0.95, -0.3), (1.2, 0.05), (1.2, 0.45), (1.08, 0.86), (0.75, 1.13), (0.0, 1.25)], hairline=0.55,
            ripple=lambda t, z: 0.012 * math.sin(t * 50 + z * 3))
        egg(g("HairGrey"), Matrix.Translation(hc + Vector((0.0, 0.55, 1.05))), 0.45, 0.42, 0.4)
        for side in (-1, 1):
            tube(g("Frame"), [hc + Vector((side * 0.5, 0.45, 1.3)), hc + Vector((-side * 0.4, 0.7, 0.9))], [0.025, 0.025], sides=1)
    skirt = [(0.95, 0.9), (1.02, 0.95), (1.0, 1.6), (0.95, 2.4), (0.9, 2.6)]
    cardi = [(0.92, 2.4), (1.0, 2.5), (1.05, 3.1), (1.0, 3.8), (0.85, 4.2), (0.55, 4.4), (0.3, 4.48), (0.0, 4.5)]
    with part("Torso"):
        lathe(g("Skirt"), skirt, squash=0.82, segs=48, ripple=lambda t, z: 0.025 * math.sin(t * 10) * max(0.0, 1 - (z - 0.9) / 1.4), caps=(False, False))
        lathe(g("Cardigan"), cardi, squash=0.82, segs=48, ripple=lambda t, z: 0.012 * math.sin(t * 30))
        buttons("Button", cardi, 0.82, (2.7, 3.05, 3.4, 3.75), r=0.065)
        lathe(g("Lace"), [(0.32, 4.3), (0.5, 4.35), (0.56, 4.48), (0.36, 4.58)], squash=0.85, segs=40, caps=(False, False), ripple=lambda t, z: 0.015 * math.sin(t * 24))
        ball(g("Brass"), (0.0, front_y(cardi, 4.15, 0.82) - 0.05, 4.15), 0.08)
        taper(g("SkinGran"), (0.0, -0.05, 4.3), (0.0, -0.15, 4.75), 0.3, 0.28)
    arms("Cardigan", "SkinGran", (0.92, 0.0, 4.0), (1.15, -0.1, 3.05), (0.62, -0.85, 2.75), radii=(0.32, 0.28, 0.25), cuff="Cardigan",
         palm=0.18, finger=0.42, fr=0.05, spread=0.075, curl=0.16)
    with part("LeftArm"):  # a ball of red wool in one hand
        ball(g("Yarn"), (0.55, -1.15, 2.55), 0.28)
    with part("RightArm"):  # knitting in the other: needles and a red scrap hanging
        for dx in (-0.1, 0.1):
            tube(g("Frame"), [(-0.55 + dx, -1.0, 2.5), (-0.35 + dx * 2, -1.35, 3.1)], [0.025, 0.02], sides=1)
        egg(g("Yarn"), Matrix.Translation((-0.4, -1.12, 2.3)) @ Matrix.Rotation(0.2, 4, "Y"), 0.32, 0.06, 0.36)
        tube(g("Yarn"), [(-0.3, -1.15, 1.95), (0.1, -1.25, 1.85), (0.5, -1.18, 2.35)], [0.03] * 3, sides=1)
    legs("Stocking", (0.36, 0.0, 1.0), (0.36, 0.0, 0.3), radii=(0.22, 0.2), shoe=("Shoe", (0.26, 0.42, 0.18), 0.12))
    joints((0.0, -0.12, 4.55), (0.92, 0.0, 4.0), (0.36, 0.0, 1.0), hc.z + 0.1, hc)


def sweater_vest(o):
    """The dad: no face at all, just his glasses sitting on the blank skin."""
    hc = Vector((0.0, 0.0, 5.95))
    # Skin has grown over his face: his eyes and his open mouth press out under it.
    skin("SkinDad", (0.8, 0.67, 0.58, 1), hc + o, veins=0.7, vein_color=(0.32, 0.12, 0.2, 1), paint=[
        ("oval", 0.4, 0.1, 0.34, 0.3, (0.7, 0.3, 0.3, 1), 0.7),
        ("oval", 0.0, -0.5, 0.38, 0.34, (0.68, 0.3, 0.3, 1), 0.7),
        ("oval", 0.0, -0.5, 0.12, 0.1, (0.3, 0.12, 0.14, 1), 0.6),
    ])
    with part("Head"):
        head(g("SkinDad"), hc, (1.15, 1.08, 1.25), jaw=0.22, chin=0.02, sockets=[(0.0, -0.5, 0.12, 0.12)],
             bumps=[(-0.4, 0.1, 0.17, 0.14, 0.1), (0.4, 0.1, 0.17, 0.14, 0.1), (0.0, -0.5, 0.26, 0.22, 0.09), (0.0, -0.12, 0.08, 0.1, 0.05)])
        for side in (-1, 1):
            egg(g("SkinDad"), Matrix.Translation(hc + Vector((side * 1.12, 0.05, -0.05))), 0.1, 0.2, 0.28)
        glasses(g("Frame"), hc, 0.4, 0.12, 0.27, hc.y - 1.12, t=0.03)
        cap(g("HairBrown"), hc, [(1.0, -0.2), (1.18, 0.15), (1.2, 0.5), (1.06, 0.92), (0.7, 1.22), (0.0, 1.32)], hairline=0.68, slope=0.1,
            ripple=lambda t, z: 0.01 * math.sin(t * 30 + 2 * z))
        egg(g("HairBrown"), Matrix.Translation(hc + Vector((-0.3, -0.62, 1.05))) @ Matrix.Rotation(0.4, 4, "Y"), 0.55, 0.35, 0.22)  # the quiff
    shirt = [(0.9, 1.6), (0.98, 1.7), (1.05, 2.4), (1.08, 3.2), (1.02, 3.9), (0.85, 4.35), (0.5, 4.6), (0.3, 4.68), (0.0, 4.7)]
    with part("Torso"):
        lathe(g("ShirtBlue"), shirt, squash=0.8, segs=48)
        vest = lathe(g("Argyle"), [(0.97, 1.95), (1.1, 2.0), (1.12, 2.4), (1.14, 3.2), (1.08, 3.9), (0.92, 4.32), (0.6, 4.55)], squash=0.81, segs=64, caps=(False, False), soft=0)
        cut_faces(vest, lambda c: c.y < -0.4 and abs(c.x) < (c.z - 3.5) * 0.7)
        mod = vest.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.05
        V.apply_modifiers(vest)
        F.soften(vest)
        lathe(g("Leather"), ring(1.0, 1.95, 0.07), squash=0.82, segs=48, caps=(False, False))
        lathe(g("ShirtBlue"), [(0.36, 4.5), (0.42, 4.55), (0.44, 4.72), (0.36, 4.75)], squash=0.9, segs=32, caps=(False, False))
        for side in (-1, 1):  # bow tie
            egg(g("Tie"), Matrix.Translation((side * 0.14, -0.42, 4.62)) @ Matrix.Rotation(side * 0.25, 4, "Y"), 0.14, 0.06, 0.09)
        ball(g("Tie"), (0.0, -0.45, 4.62), 0.05)
        taper(g("SkinDad"), (0.0, 0.0, 4.5), (0.0, 0.0, 4.95), 0.36, 0.34)
    arms("ShirtBlue", "SkinDad", (1.0, 0.0, 4.15), (1.3, -0.05, 3.05), (1.36, -0.2, 2.3), radii=(0.35, 0.3, 0.27), cuff="ShirtBlue",
         palm=0.21, finger=0.44, fr=0.065, spread=0.1)
    with part("RightArm"):  # a mug of coffee
        lathe(g("Mug"), [(0.0, 0.0), (0.24, 0.0), (0.26, 0.05), (0.26, 0.5), (0.22, 0.52), (0.0, 0.46)], at=(-1.4, -0.62, 1.7), segs=32)
        lathe(g("Mug"), ring(0.14, 0.0, 0.035), at=(-1.4, -0.36, 1.95), rot=Matrix.Rotation(math.pi / 2, 4, "Y"), segs=20, caps=(False, False), soft=0)
    legs("Khaki", (0.42, 0.0, 1.75), (0.42, 0.0, 0.32), radii=(0.34, 0.3), shoe=("Leather", (0.28, 0.46, 0.2), 0.14))
    joints((0.0, 0.0, 4.85), (1.0, 0.0, 4.15), (0.42, 0.0, 1.75), hc.z + 0.12, hc)


def porcelain_doll(o):
    """The doll: cracked bisque, one glass eye, the other broken out to the dark inside."""
    hc = Vector((0.0, 0.0, 5.05))
    hole = (-0.42, 0.08, 0.36)
    skin("SkinDoll", (0.93, 0.89, 0.84, 1), hc + o, rough=0.5, veins=0.95, sss=0.04, vein_color=(0.1, 0.08, 0.07, 1), paint=[
        ("streak", 0.42, -0.2, -0.95, 0.03, (0.05, 0.04, 0.04, 1), 0.85),  # black tears
        ("oval", 0.68, -0.32, 0.26, 0.22, (0.92, 0.45, 0.48, 1), 0.75),
        ("arc", -0.48, 0.6, 0.16, 0.06, 0.02, (0.72, 0.08, 0.12, 1), 1.0),
        ("oval", 0.42, 0.42, 0.2, 0.05, (0.35, 0.2, 0.12, 1), 0.7),  # painted brows
    ])
    eyeball("EyeDoll", look=(0.05, -1.0, 0.0), iris=(0.2, 0.42, 0.75, 1), iris_size=0.78, pupil_size=0.93, gloss=0.05)
    with part("Head"):
        h = head(g("SkinDoll"), hc, (1.2, 1.12, 1.2), jaw=0.2, sockets=[(0.42, 0.05, 0.27, 0.1)], bumps=[(0.0, -0.18, 0.08, 0.08, 0.05)], hole=hole, thick=0.06)
        egg(g("Hollow"), Matrix.Translation(hc), 1.05, 0.98, 1.05, soft=False)
        ball(g("EyeGlow"), hc + Vector((-0.38, -1.0, 0.1)), 0.045, segs=10)  # something inside, looking out
        p, nrm = face_point(h, hc, 0.42, 0.05)
        ball(g("EyeDoll"), p + Vector((0, 0.1, 0)), 0.27, segs=28)
        cap(g("HairBlonde"), hc, [(0.98, -0.25), (1.24, 0.08), (1.26, 0.48), (1.12, 0.9), (0.75, 1.2), (0.0, 1.32)], hairline=0.62,
            ripple=lambda t, z: 0.03 * math.sin(t * 16), segs=64)
        for k in range(11):
            a = math.radians(40 + k * 28)
            top = hc + Vector((math.sin(a) * 1.15, -math.cos(a) * 1.1 + 0.05, 0.1 - 0.15 * abs(math.cos(a))))
            curl(g("HairBlonde"), top, 1.3 + 0.25 * math.sin(k * 2.1), r=0.13, turns=3.5, thick=0.1, phase=k)
        for side in (-1, 1):
            egg(g("Ribbon"), Matrix.Translation(hc + Vector((side * 0.42, 0.2, 1.22))) @ Matrix.Rotation(side * 0.5, 4, "Y"), 0.42, 0.18, 0.28)
        ball(g("Ribbon"), hc + Vector((0.0, 0.2, 1.28)), 0.14)
    dress = [(1.15, 1.0), (1.25, 1.05), (1.2, 1.5), (1.0, 2.3), (0.78, 2.9), (0.75, 3.3), (0.72, 3.7), (0.55, 3.95), (0.3, 4.02), (0.0, 4.03)]
    with part("Torso"):
        lathe(g("DressBlue"), dress, squash=0.85, segs=56, ripple=lambda t, z: 0.03 * math.sin(t * 12) * max(0.0, 1 - (z - 1.0) / 1.6))
        panel(g("Lace"), [(1.24, 1.15), (1.1, 1.6), (0.95, 2.3), (0.82, 2.85)], span=math.pi * 0.6, segs=30, squash=0.86, ripple=lambda t, z: 0.015 * math.sin(t * 14))
        lathe(g("Lace"), [(0.24, 3.88), (0.5, 3.92), (0.58, 4.02), (0.3, 4.1)], squash=0.85, segs=48, caps=(False, False), ripple=lambda t, z: 0.02 * math.sin(t * 20))
        taper(g("SkinDoll"), (0.0, 0.0, 3.9), (0.0, 0.0, 4.2), 0.26, 0.25)
    arms("SkinDoll", "SkinDoll", (0.72, 0.0, 3.75), (0.9, -0.05, 2.9), (0.95, -0.15, 2.15), radii=(0.18, 0.15, 0.13), puff=("DressBlue", 0.32),
         palm=0.17, finger=0.28, fr=0.06, spread=0.07, curl=0.06)
    for side in (-1, 1):
        with part(arm(side)):
            ball(g("SkinDoll"), (side * 0.9, -0.05, 2.9), 0.17)  # the elbow's ball joint
    legs("Sock", (0.35, 0.0, 1.2), (0.35, 0.0, 0.25), radii=(0.2, 0.17), shoe=("Shoe", (0.24, 0.38, 0.16), 0.1))
    joints((0.0, 0.0, 4.05), (0.72, 0.0, 3.75), (0.35, 0.0, 1.2), hc.z + 0.05, hc)


def grinner(o):
    """The grinner: his whole head opens, the top hinged back, a mouth all the way round."""
    hc = Vector((0.0, 0.0, 5.9))
    size = (1.25, 1.15, 1.15)
    skin("SkinGrin", (0.86, 0.7, 0.6, 1), hc + o, veins=0.1, paint=[("oval", 0.8, -0.35, 0.25, 0.2, (0.85, 0.4, 0.4, 1), 0.45)])
    hinge = Matrix.Rotation(-0.75, 4, "X")
    with part("Head"):
        lower = head(g("SkinGrin"), hc, size, jaw=0.1, bumps=[(-0.8, -0.3, 0.3, 0.25, 0.05), (0.8, -0.3, 0.3, 0.25, 0.05)])
        cut_faces(lower, lambda c: c.z > hc.z - 0.02)
        mod = lower.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.1
        V.apply_modifiers(lower)
        egg(g("Gums"), Matrix.Translation(hc + Vector((0, 0, -0.14))), 1.12, 1.02, 0.12)
        egg(g("Tongue"), Matrix.Translation(hc + Vector((0, -0.62, 0.02))) @ Matrix.Rotation(-0.25, 4, "X"), 0.36, 0.72, 0.1)  # lolling out over the rim

        def rim_teeth(dz, up):
            for k in range(19):
                a = math.radians(-175 + k * 9.7)
                p = hc + Vector((math.cos(a) * (size[0] - 0.12), math.sin(a) * (size[1] - 0.12), dz))
                long = 1.4 if k % 3 == 1 else 1.0
                egg(g("Teeth"), Matrix.Translation(p + Vector((0, 0, (0.1 if up else -0.1) * long))) @ Matrix.Rotation(a + math.pi / 2, 4, "Z"), 0.08, 0.06, 0.16 * long, segs=10, rings=6)

        rim_teeth(-0.04, True)
        with track() as top:
            upper = head(g("SkinGrin"), hc, size, jaw=0.1, bumps=[(0.0, 0.25, 0.12, 0.12, 0.1)])
            kid_eyes(upper, hc, 0.45, 0.45, rx=0.11, rz=0.15)
            for side in (-1, 1):
                brow = [face_point(upper, hc, side * x, 0.72 + 0.05 * x)[0] for x in (0.3, 0.45, 0.62)]
                tube(g("HairBrown"), [q + Vector((0, -0.04, 0)) for q in brow], [0.04, 0.05, 0.04], sides=1)
            cut_faces(upper, lambda c: c.z < hc.z + 0.02)
            mod = upper.modifiers.new("Thick", "SOLIDIFY")
            mod.thickness = 0.1
            V.apply_modifiers(upper)
            egg(g("Gums"), Matrix.Translation(hc + Vector((0, 0, 0.14))), 1.12, 1.02, 0.12)
            rim_teeth(0.04, False)
            for k in range(3):  # three hairs combed over the top
                x = -0.3 + k * 0.3
                tube(g("HairBrown"), [hc + Vector((x - 0.6, -0.2, 1.0)), hc + Vector((x, -0.1, 1.17)), hc + Vector((x + 0.6, 0.1, 1.0))], [0.03] * 3, sides=1)
        transform(top, about((0, hc.y + size[1] * 0.85, hc.z), hinge))
    belly = [(0.95, 1.6), (1.12, 1.75), (1.3, 2.4), (1.32, 3.1), (1.18, 3.8), (0.98, 4.3), (0.6, 4.6), (0.3, 4.7), (0.0, 4.72)]
    with part("Torso"):
        lathe(g("Sweater"), belly, squash=0.85, segs=48, ripple=lambda t, z: 0.01 * math.sin(t * 36))
        lathe(g("Sweater"), [(0.45, 4.5), (0.55, 4.55), (0.56, 4.72), (0.45, 4.76)], squash=0.9, segs=36, caps=(False, False))
        for side in (-1, 1):
            tube(g("Leather"), [(side * 0.45, front_y(belly, 2.0, 0.85) - 0.03, 2.0), (side * 0.5, front_y(belly, 3.0, 0.85) - 0.04, 3.0), (side * 0.5, -0.6, 4.4), (side * 0.48, 0.3, 4.6)], [0.05] * 4, sides=1)
        taper(g("SkinGrin"), (0.0, 0.0, 4.5), (0.0, 0.0, 4.9), 0.42, 0.4)
    arms("Sweater", "SkinGrin", (1.1, 0.0, 4.2), (1.42, -0.05, 3.1), (1.46, -0.2, 2.35), radii=(0.38, 0.32, 0.28), cuff="Sweater", palm=0.23, finger=0.42, fr=0.07, spread=0.1)
    legs("Slacks", (0.45, 0.0, 1.75), (0.45, 0.0, 0.34), radii=(0.36, 0.31), shoe=("Leather", (0.3, 0.48, 0.22), 0.15))
    joints((0.0, 0.0, 4.75), (1.1, 0.0, 4.2), (0.45, 0.0, 1.75), hc.z + 0.45, hc)


def prism(poly, centre, y0, y1):
    """A cutter: polygon `poly` [(x, z)] about `centre`, pushed from y0 to y1."""
    bm = bmesh.new()
    front = [bm.verts.new((centre.x + x, y0, centre.z + z)) for x, z in poly]
    back = [bm.verts.new((centre.x + x, y1, centre.z + z)) for x, z in poly]
    caps = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.triangulate(bm, faces=caps)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return V.mesh_object("Cutter", bm, "_cutters")


def pumpkin_suit(o):
    """The pumpkin: a jack-o'-lantern head carved angry, fangs in its grin, lit inside, and in one
    eye a real eye looking out."""
    hc = Vector((0.0, 0.0, 5.9))
    eyeball("EyeBlood2", look=(0.0, -1.0, -0.1), veins=1.0, iris=(0.35, 0.3, 0.12, 1), pupil_size=0.993)
    holes = [[(0.14, 0.1), (0.62, 0.06), (0.8, 0.46)], [(-0.14, 0.1), (-0.62, 0.06), (-0.8, 0.46)], [(-0.13, -0.02), (0.13, -0.02), (0.0, -0.22)]]
    top, bottom = [], []
    steps = 96
    for k in range(steps + 1):
        x = -0.95 + 1.9 * k / steps
        zt = -0.27 + 0.24 * (x / 0.95) ** 2 - 0.3 * max(0.0, 1 - min(abs(x - c) for c in (-0.56, -0.18, 0.18, 0.56)) / 0.08)
        zb = -0.78 + 0.5 * (x / 0.95) ** 2 + 0.22 * max(0.0, 1 - min(abs(x - c) for c in (-0.37, 0.0, 0.37)) / 0.07)
        top.append((x, zt))
        bottom.append((x, zb))
    holes.append(top + bottom[::-1])
    with part("Head"):
        ribs = lambda t, z: 0.09 * math.cos(t * 10)
        shell = lathe(g("Pumpkin"), densify([(0.25, -1.0), (0.8, -0.92), (1.2, -0.6), (1.38, -0.1), (1.35, 0.3), (1.15, 0.7), (0.7, 0.95), (0.25, 1.02), (0.1, 0.98)], 0.08),
                      at=hc, squash=0.92, segs=120, ripple=ribs, soft=1)
        mod = shell.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.12
        V.apply_modifiers(shell)
        V.cut(shell, [prism(poly, hc, hc.y - 2.0, hc.y - 0.3) for poly in holes])
        ball(g("PumpkinLight"), hc + Vector((0, 0.15, 0.0)), 1.0, segs=24)
        ball(g("EyeBlood2"), hc + Vector((0.52, -0.98, 0.21)), 0.17, segs=24)  # the real eye, in one hole
        tube(g("Stem"), [hc + Vector((0, 0.05, 0.9)), hc + Vector((0.05, 0.08, 1.2)), hc + Vector((0.2, 0.12, 1.4))], [0.13, 0.1, 0.08], sides=2)
        tube(g("Stem"), [hc + Vector((0.1, 0.1, 1.0)) + Vector((math.cos(a) * 0.25, math.sin(a) * 0.25, 0.02 * a)) for a in (k * 0.6 for k in range(10))], [0.025] * 10, sides=1)
    suit = [(0.9, 1.6), (1.2, 1.8), (1.45, 2.5), (1.48, 3.2), (1.3, 3.9), (0.95, 4.35), (0.5, 4.6), (0.0, 4.65)]
    with part("Torso"):
        lathe(g("Felt"), suit, squash=0.9, segs=60, ripple=lambda t, z: 0.05 * math.cos(t * 10))
        for k in range(6):
            a = k * math.pi / 3
            egg(g("Glove"), Matrix.Translation((math.cos(a) * 0.5, math.sin(a) * 0.45, 4.62)) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.5, 4, "Y"), 0.36, 0.16, 0.05)
        taper(g("Leotard"), (0.0, 0.0, 4.5), (0.0, 0.0, 4.95), 0.35, 0.33)
    arms("Leotard", "Glove", (1.05, 0.0, 4.15), (1.35, -0.05, 3.05), (1.4, -0.2, 2.3), radii=(0.3, 0.26, 0.24), hand_mat="Glove", palm=0.22, finger=0.4, fr=0.07, spread=0.1)
    legs("Leotard", (0.42, 0.0, 1.7), (0.42, 0.0, 0.32), radii=(0.28, 0.24), shoe=("Shoe", (0.28, 0.46, 0.2), 0.14))
    joints((0.0, 0.0, 4.7), (1.05, 0.0, 4.15), (0.42, 0.0, 1.7), hc.z + 0.35, hc)


def widow(o):
    """The widow: under her hat's net, two points of light, and her jaw hangs to her chest."""
    hc = Vector((0.0, -0.05, 6.0))
    mouth = (-0.85, 0.0, 0.26, 0.55)
    skin("SkinWidow", (0.76, 0.76, 0.75, 1), hc + o, veins=0.4, paint=[
        ("net", 0.0, 0.1, 0.012, (0.02, 0.02, 0.02, 1), 0.9),
        ("streak", 0.36, 0.05, -0.75, 0.03, (0.03, 0.03, 0.03, 1), 0.9),
        ("arc", *mouth, 0.05, (0.15, 0.12, 0.13, 1), 1.0),
        ("arc", *mouth, 0.0, (0.02, 0.0, 0.0, 1), 1.0),
    ])
    with part("Head"):
        h = head(g("SkinWidow"), hc, (1.0, 0.98, 1.2), jaw=0.32, chin=0.15, sag=0.75,
                 sockets=[(-0.36, 0.25, 0.2, 0.18), (0.36, 0.25, 0.2, 0.18)], grooves=[(*mouth, 0.35)])
        sunk(h, hc, 0.36, 0.25, 0.17)
        cap(g("HairBlack"), hc, [(0.9, -0.55), (1.06, -0.1), (1.06, 0.45), (0.9, 0.9), (0.0, 1.1)], hairline=0.75, slope=0.1)
        brim = hc + Vector((0, 0.05, 0.95))
        tilt = Matrix.Rotation(0.12, 4, "X") @ Matrix.Rotation(-0.08, 4, "Y")
        lathe(g("Mourning"), [(0.0, 0.0), (1.75, 0.0), (1.8, 0.04), (1.75, 0.08), (0.0, 0.08)], at=brim, rot=tilt, segs=64)
        lathe(g("Mourning"), [(0.95, 0.06), (0.92, 0.55), (0.82, 0.66), (0.0, 0.68)], at=brim, rot=tilt, segs=48)
        lathe(g("Velvet2"), ring(0.95, 0.16, 0.05), at=brim, rot=tilt, segs=48, caps=(False, False))
    dress = [(1.05, 0.05), (1.15, 0.1), (1.08, 0.8), (0.95, 1.8), (0.78, 2.8), (0.82, 3.5), (0.86, 3.9), (0.66, 4.3), (0.32, 4.45), (0.0, 4.46)]
    with part("Torso"):
        lathe(g("Mourning"), dress, squash=0.8, segs=56, ripple=lambda t, z: 0.03 * math.sin(t * 13) * max(0.0, 1 - z / 2.0))
        lathe(g("Mourning"), [(0.3, 4.3), (0.36, 4.35), (0.34, 4.8), (0.3, 4.82)], squash=0.95, segs=32, caps=(False, False))
        ball(g("Pearl"), (0.0, -0.36, 4.5), 0.09)
    arms("Mourning", "GloveBlack", (0.82, 0.0, 4.05), (1.0, -0.05, 3.0), (1.02, -0.22, 2.15), radii=(0.24, 0.2, 0.18), hand_mat="GloveBlack",
         palm=0.2, finger=0.6, fr=0.05, spread=0.08, curl=0.15)
    with part("RightArm"):
        bouquet(g("DeadFlower"), g("DeadStem"), (-1.05, -0.5, 1.55))
    legs("Mourning", (0.3, 0.0, 1.2), (0.3, 0.0, 0.2), radii=(0.22, 0.18), shoe=("Shoe", (0.2, 0.36, 0.14), 0.25))
    joints((0.0, -0.04, 4.72), (0.82, 0.0, 4.05), (0.3, 0.0, 1.2), hc.z + 0.25, hc)


def raven_man(o):
    """The raven man: under a hood of black feathers he wears a crow's bleached skull, its beak long
    and cracked; in the empty sockets, two red points of light. Talons for hands and feet."""
    hunch = about((0, 0, 2.0), Matrix.Rotation(0.25, 4, "X"))
    hc = Vector((0.0, -0.95, 6.2))
    with part("Head"):
        hood = lathe(g("Feathers"), [(0.6, -1.0), (1.02, -0.6), (1.1, -0.1), (1.08, 0.4), (0.92, 0.85), (0.5, 1.12), (0.0, 1.2)], at=hc, segs=72,
                     ripple=lambda t, z: 0.04 * abs(math.sin(t * 14 + z * 3)), soft=0)
        cut_faces(hood, lambda c: c.y < hc.y - 0.35 and ((c.x - hc.x) / 0.75) ** 2 + ((c.z - hc.z + 0.05) / 0.85) ** 2 < 1)
        mod = hood.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.06
        V.apply_modifiers(hood)
        F.soften(hood)
        egg(g("Hollow"), Matrix.Translation(hc + Vector((0.0, 0.2, 0.0))), 0.85, 0.7, 0.9, soft=False)
        skull = head(g("Bone"), hc + Vector((0.0, -0.5, 0.0)), (0.66, 0.62, 0.7), jaw=0.35,
                     sockets=[(-0.27, 0.18, 0.2, 0.3), (0.27, 0.18, 0.2, 0.3)], bumps=[(0.0, 0.45, 0.3, 0.12, 0.05)])
        for side in (-1, 1):  # empty sockets; deep in each, a red point of light
            p, nrm = face_point(skull, hc + Vector((0.0, -0.5, 0.0)), side * 0.27, 0.18)
            egg(g("Hollow"), on(p + nrm * 0.08, nrm), 0.17, 0.05, 0.19, soft=False)
            ball(g("EyeRed"), p + nrm * 0.12 + Vector((side * -0.02, 0, -0.02)), 0.04, segs=10)
        base = hc + Vector((0.0, -1.02, -0.15))
        for tilt, scale in ((0.72, 1.0), (0.88, 0.7)):  # the beak, long and narrow, hanging, a little open
            m = Matrix.Translation(base + Vector((0, 0, -0.08 * (1 - scale) * 3))) @ Matrix.Rotation(tilt, 4, "X") @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Diagonal((0.62, 0.5 * scale, scale, 1))
            F.soften(F.shell(g("Bone"), [(0.0, -0.1), (0.42, 0.0), (0.4, 0.4), (0.3, 1.0), (0.14, 1.6), (0.0, 2.0)], m, segs=28))
        for k in range(4):  # cracks down the beak
            d = 0.3 + k * 0.35
            at = base + Matrix.Rotation(0.72, 3, "X") @ Vector((0.05 * (-1) ** k, -d, 0.2 * (1 - d / 2.0)))
            tube(g("Hollow"), [at, at + Vector((0.06 * (-1) ** k, -0.12, -0.04))], [0.012, 0.008], sides=1)
        for k in range(5):  # a crest of ragged feathers
            egg(g("Feathers"), Matrix.Translation(hc + Vector((0.0, 0.2 + k * 0.18, 1.05 - k * 0.06))) @ Matrix.Rotation(-0.6 - k * 0.15, 4, "X"), 0.08, 0.06, 0.38)
    coat = [(0.85, 1.9), (0.95, 2.0), (1.0, 2.8), (1.05, 3.6), (1.15, 4.3), (1.0, 4.8), (0.6, 5.1), (0.3, 5.2), (0.0, 5.22)]
    with part("Torso"):
        with track() as made:
            lathe(g("Coat"), coat, squash=0.8, segs=48, ripple=lambda t, z: 0.02 * math.sin(t * 9) * max(0.0, 1 - (z - 1.9) / 1.0))
            cape = panel(g("Feathers"), [(1.3, 2.6), (1.25, 3.4), (1.22, 4.2), (1.12, 4.8), (0.7, 5.2)], span=math.pi * 1.35, facing=math.pi / 2, segs=60,
                         ripple=lambda t, z: 0.05 * abs(math.sin(t * 12)), thick=0.06)
            cut_faces(cape, lambda c: c.z < 2.9 + 0.35 * math.sin(math.atan2(c.y, c.x) * 14))
            for k in range(12):  # the ruff of feathers round the neck
                a = 2 * math.pi * k / 12
                egg(g("Feathers"), Matrix.Translation((math.cos(a) * 0.62, math.sin(a) * 0.55, 5.05)) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.9, 4, "Y"), 0.1, 0.07, 0.42)
            taper(g("Feathers"), (0.0, -0.05, 4.9), (0.0, -0.2, 5.6), 0.45, 0.4)
        transform(made, hunch)
    shoulder = hunch @ Vector((1.0, 0.0, 4.6))
    arms("Coat", "Beak", shoulder, (1.2, -0.6, 3.4), (1.15, -0.95, 2.4), radii=(0.32, 0.27, 0.22), hand_mat="Beak", palm=0.18, finger=0.7, fr=0.04, spread=0.07, curl=0.3)
    legs("Coat", (0.34, 0.0, 2.0), (0.32, 0.0, 0.32), radii=(0.24, 0.15))
    for side in (-1, 1):
        with part(leg(side)):
            for a in (-0.5, 0.0, 0.5):  # talons for feet
                d = Vector((math.sin(a), -math.cos(a), 0))
                tube(g("Beak"), [Vector((side * 0.32, 0, 0.15)), Vector((side * 0.32, 0, 0.1)) + d * 0.35, Vector((side * 0.32, 0, 0.02)) + d * 0.6], [0.07, 0.05, 0.03])
    joints(hunch @ Vector((0.0, -0.1, 5.0)), shoulder, (0.34, 0.0, 2.0), hc.z + 0.18, hc)


def bathrobe(o):
    """The old man in the bathrobe: his face is melting off his skull, an eye sliding down his cheek,
    skin dripping from his chin."""
    hc = Vector((0.0, -0.1, 5.8))
    mouth = (-0.85, 0.12, 0.55, 0.12, 0.5)
    skin("SkinBath", (0.78, 0.72, 0.56, 1), hc + o, veins=0.5, paint=[
        ("spot", 0.42, -0.08, 0.2, 0.09, (0.62, 0.1, 0.1, 1), 0.85),  # raw red under the eyes, the lids pulled down
        ("spot", -0.45, -0.46, 0.22, 0.1, (0.62, 0.1, 0.1, 1), 0.85),
        ("oval", 0.45, -0.3, 0.3, 0.26, (0.33, 0.24, 0.2, 1), 0.6),
        ("oval", 0.45, 0.85, 0.12, 0.1, (0.45, 0.3, 0.18, 1), 0.7),  # liver spots
        ("oval", 0.15, 1.0, 0.08, 0.07, (0.45, 0.3, 0.18, 1), 0.7),
        ("arc", *mouth[:4], 0.04, (0.4, 0.22, 0.24, 1), 1.0, mouth[4]),
        ("arc", *mouth[:4], 0.0, (0.06, 0.01, 0.01, 1), 1.0, mouth[4]),
    ])
    with part("Head"):
        h = head(g("SkinBath"), hc, (1.15, 1.08, 1.2), jaw=0.1, sag=0.8, sag_bias=-0.6,
                 sockets=[(-0.45, -0.34, 0.18, 0.06), (0.42, 0.04, 0.17, 0.05)], bumps=[(0.05, -0.4, 0.13, 0.24, 0.12)], grooves=[(*mouth[:4], 0.17, mouth[4])])
        for x, z in ((-0.45, -0.34), (0.42, 0.04)):
            p, nrm = face_point(h, hc, x, z)
            egg(g("EyeBlack"), on(p + nrm * -0.03, nrm), 0.12, 0.05, 0.15)
        teeth(h, hc, mouth[:4], 4, 0, size=0.05, slope=mouth[4])
        for k, x in enumerate((-0.5, -0.2, 0.15, 0.45)):  # skin running off his chin
            q, _ = face_point(h, hc, x, -1.25 - 0.1 * (x < 0))
            if q is None:
                continue
            drop = 0.45 + 0.25 * (k % 2)
            tube(g("SkinBath"), [q + Vector((0, 0.06, 0.05)), q + Vector((0, 0.02, -drop * 0.5)), q + Vector((0, 0.0, -drop))], [0.09, 0.05, 0.03], sides=2)
            ball(g("SkinBath"), q + Vector((0, 0.0, -drop - 0.03)), 0.05, segs=10)
        for side in (-1, 1):
            egg(g("SkinBath"), Matrix.Translation(hc + Vector((side * 1.12, 0.0, -0.35))), 0.14, 0.25, 0.48)
            for k in range(3):
                tube(g("HairGrey"), [hc + Vector((side * 1.0, 0.2 + k * 0.15, 0.4)), hc + Vector((side * 1.35, 0.25 + k * 0.2, 0.55 + 0.1 * k)), hc + Vector((side * 1.5, 0.35 + k * 0.2, 0.3))], [0.02] * 3, sides=1)
    chest = [(0.9, 1.6), (1.1, 1.8), (1.2, 2.6), (1.15, 3.4), (1.05, 4.0), (0.7, 4.4), (0.35, 4.55), (0.0, 4.56)]
    with part("Torso"):
        lathe(g("SkinBath"), chest, squash=0.82, segs=48)
        robe = lathe(g("Robe"), [(1.05, 1.1), (1.16, 1.15), (1.22, 1.8), (1.27, 2.6), (1.22, 3.4), (1.12, 4.0), (0.82, 4.4), (0.52, 4.56)], squash=0.84, segs=64,
                     caps=(False, False), ripple=lambda t, z: 0.03 * math.sin(t * 9) * max(0.0, 1 - (z - 1.1) / 1.4), soft=0)
        cut_faces(robe, lambda c: c.y < -0.3 and abs(c.x) < (c.z - 2.75) * 0.38)
        mod = robe.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.06
        V.apply_modifiers(robe)
        F.soften(robe)
        lathe(g("Robe"), ring(1.29, 2.6, 0.08), squash=0.85, segs=48, caps=(False, False))
        egg(g("Robe"), Matrix.Translation((0.25, front_y(chest, 2.6, 0.85) - 0.2, 2.55)), 0.18, 0.1, 0.12)
        tube(g("Robe"), [(0.25, -1.2, 2.5), (0.32, -1.25, 2.1), (0.28, -1.2, 1.7)], [0.06, 0.05, 0.05])
        taper(g("SkinBath"), (0.0, 0.0, 4.4), (0.0, -0.05, 4.85), 0.36, 0.34)
    arms("Robe", "SkinBath", (1.0, 0.0, 4.1), (1.32, -0.05, 3.0), (1.36, -0.2, 2.3), radii=(0.38, 0.36, 0.34), palm=0.2, finger=0.5, fr=0.055, spread=0.09, curl=0.15)
    legs("SkinBath", (0.35, 0.0, 1.4), (0.35, 0.0, 0.3), radii=(0.2, 0.17), shoe=("Leather", (0.28, 0.45, 0.17), 0.12))
    joints((0.0, -0.05, 4.62), (1.0, 0.0, 4.1), (0.35, 0.0, 1.4), hc.z + 0.04, hc)


def butler(o):
    """The butler: polite, tall, a tray held out, and his neck broken: his head lies on his
    shoulder, smiling, with black eyes that follow you."""
    hc = Vector((0.0, 0.0, 7.0))
    neck = Vector((0.0, 0.0, 6.1))
    roll = 1.3
    lie = Matrix.Translation((0.0, 0.0, 0.3)) @ about(neck, Matrix.Rotation(roll, 4, "Y"))  # over onto his left shoulder
    face = lie @ hc
    smile = (-0.42, 0.22, 0.55, 0.03)
    skin("SkinButler", (0.8, 0.76, 0.73, 1), face + o, veins=0.35, roll=roll, paint=[
        ("oval", 0.4, 0.1, 0.3, 0.28, (0.3, 0.24, 0.27, 1), 0.6),
        ("arc", *smile, 0.0, (0.06, 0.02, 0.02, 1), 1.0),
    ])
    with part("Head"):
        with track() as made:
            h = head(g("SkinButler"), hc, (1.05, 1.0, 1.18), jaw=0.25, chin=0.05, sockets=[(-0.4, 0.1, 0.2, 0.16), (0.4, 0.1, 0.2, 0.16)],
                     bumps=[(0.0, -0.1, 0.1, 0.16, 0.1)], grooves=[(*smile, 0.06)])
            sunk(h, hc, 0.4, 0.1, 0.16)
            for side in (-1, 1):
                egg(g("SkinButler"), Matrix.Translation(hc + Vector((side * 1.04, 0.05, -0.02))), 0.1, 0.18, 0.26)
            cap(g("HairBlack"), hc, [(1.0, -0.45), (1.1, -0.1), (1.12, 0.4), (1.0, 0.85), (0.6, 1.15), (0.0, 1.24)], hairline=0.62, slope=0.12,
                ripple=lambda t, z: 0.008 * math.sin(t * 40))
        transform(made, lie)
        tube(g("SkinButler"), [neck - Vector((0, 0, 0.1)), neck + Vector((0.25, 0, 0.35)), lie @ (hc + Vector((0, 0.05, -0.95)))], [0.26, 0.24, 0.24], sides=2)  # the neck, bent
    coat = [(0.75, 2.9), (0.8, 3.0), (0.78, 3.8), (0.85, 4.8), (1.0, 5.6), (0.9, 5.95), (0.5, 6.12), (0.3, 6.15), (0.0, 6.16)]
    with part("Torso"):
        lathe(g("Tailcoat"), coat, squash=0.7, segs=48)
        panel(g("Tailcoat"), [(0.82, 1.9), (0.8, 2.5), (0.79, 3.1)], span=math.pi * 0.5, facing=math.pi / 2, segs=16, squash=0.72, thick=0.06)
        panel(g("ShirtWhite"), [(0.8, 4.6), (0.88, 5.1), (0.98, 5.6), (0.9, 5.95)], span=math.pi * 0.3, segs=12, squash=0.72, thick=0.03)
        for side in (-1, 1):
            egg(g("Tailcoat"), Matrix.Translation((side * 0.13, -0.66, 5.95)) @ Matrix.Rotation(side * 0.25, 4, "Y"), 0.13, 0.06, 0.08)
        lathe(g("ShirtWhite"), [(0.3, 5.95), (0.34, 6.0), (0.35, 6.22), (0.3, 6.25)], squash=0.9, segs=32, caps=(False, False))
    arms("Tailcoat", "GloveWhite", (0.92, 0.0, 5.6), (1.05, 0.0, 4.4), (1.05, -0.15, 3.3), radii=(0.28, 0.24, 0.21), cuff="ShirtWhite", hand_mat="GloveWhite",
         palm=0.2, finger=0.45, fr=0.055, spread=0.08, sides=(1,))
    arms("Tailcoat", "GloveWhite", (0.92, 0.0, 5.6), (1.08, -0.25, 4.5), (0.78, -1.0, 4.55), radii=(0.28, 0.24, 0.21), cuff="ShirtWhite", hand_mat="GloveWhite",
         palm=0.2, finger=0.4, fr=0.055, spread=0.08, curl=0.2, sides=(-1,))
    with part("RightArm"):  # the tray, held out
        lathe(g("Pewter"), [(0.0, 0.0), (0.75, 0.0), (0.8, 0.05), (0.78, 0.09), (0.7, 0.04), (0.0, 0.04)], at=(-0.55, -1.25, 4.62), segs=48)
        egg(g("Curler"), Matrix.Translation((-0.5, -1.3, 4.75)), 0.12, 0.08, 0.08)
    legs("Tailcoat", (0.36, 0.0, 3.0), (0.36, 0.0, 0.32), radii=(0.27, 0.22), shoe=("Shoe", (0.24, 0.5, 0.17), 0.18))
    joints(neck, (0.92, 0.0, 5.6), (0.36, 0.0, 3.0), face.z, face)


def masked_lady(o):
    """The lady: a serene white mask, and below it her own mouth, lipless, all teeth."""
    hc = Vector((0.0, 0.0, 6.05))
    grimace = (-0.6, 0.12, 0.5, 0.1)
    skin("SkinMasked", (0.56, 0.53, 0.5, 1), hc + o, veins=0.6, vein_color=(0.12, 0.1, 0.12, 1), paint=[
        ("arc", *grimace, 0.03, (0.1, 0.05, 0.05, 1), 1.0),
        ("arc", *grimace, 0.0, (0.05, 0.01, 0.01, 1), 1.0),
    ])
    skin("MaskWhite", (0.93, 0.91, 0.87, 1), hc + o, rough=0.45, sss=0.0, paint=[
        ("oval", 0.36, 0.2, 0.22, 0.2, (0.05, 0.05, 0.06, 1), 0.5),
        ("arc", -0.12, 0.3, 0.32, 0.018, 0.0, (0.7, 0.08, 0.1, 1), 1.0),  # the painted smile
        ("oval", 0.58, -0.05, 0.16, 0.12, (0.92, 0.5, 0.52, 1), 0.6),
    ])
    with part("Head"):
        h = head(g("SkinMasked"), hc, (1.05, 1.0, 1.15), jaw=0.3, chin=0.05, grooves=[(*grimace, 0.12)])
        teeth(h, hc, grimace, 16, 14, size=0.035)
        mask = panel(g("MaskWhite"), [(1.02, -0.3), (1.09, 0.05), (1.09, 0.45), (1.0, 0.8), (0.85, 1.0)], at=hc, span=math.pi * 0.72, segs=48, squash=0.97, thick=0.05)
        cut_faces(mask, lambda c: any(((c.x - hc.x - s * 0.36) / 0.14) ** 2 + ((c.z - hc.z - 0.2) / 0.11) ** 2 < 1 for s in (-1, 1)))
        for side in (-1, 1):
            p = hc + Vector((side * 0.36, -0.9, 0.2))
            egg(g("Hollow"), Matrix.Translation(p), 0.16, 0.06, 0.13, soft=False)
            ball(g("EyeGlow"), p + Vector((0.0, -0.06, 0.0)), 0.03, segs=10)
        for k in range(3):  # a plume from the mask's edge
            tube(g("Plume"), [hc + Vector((0.85, -0.5, 0.6)), hc + Vector((1.1 + 0.15 * k, -0.4 + 0.1 * k, 1.3 + 0.2 * k)), hc + Vector((1.0 + 0.35 * k, -0.2 + 0.2 * k, 1.9 + 0.1 * k))], [0.06, 0.12, 0.03], sides=2)
        cap(g("HairRed"), hc, [(0.95, -0.35), (1.12, 0.05), (1.14, 0.5), (1.0, 0.92), (0.65, 1.2), (0.0, 1.3)], hairline=0.85)
        for k, (dz, r) in enumerate(((1.35, 0.55), (1.75, 0.45), (2.08, 0.32))):
            egg(g("HairRed"), Matrix.Translation(hc + Vector((0.05 * k, 0.15, dz))), r, r * 0.9, r * 0.8)
        for side in (-1, 1):
            curl(g("HairRed"), hc + Vector((side * 1.0, -0.2, 0.1)), 0.9, r=0.08, turns=3, thick=0.06, phase=side)
    gown = [(1.1, 0.05), (1.2, 0.1), (1.12, 0.9), (0.95, 2.0), (0.75, 3.0), (0.82, 3.6), (0.88, 4.1)]
    with part("Torso"):
        lathe(g("GownGreen"), gown, squash=0.8, segs=56, ripple=lambda t, z: 0.03 * math.sin(t * 12) * max(0.0, 1 - z / 2.2), caps=(True, False))
        lathe(g("SkinMasked"), [(0.84, 4.0), (0.88, 4.2), (0.7, 4.45), (0.35, 4.6), (0.0, 4.62)], squash=0.75, segs=48)
        for k in range(18):
            a = 2 * math.pi * k / 18
            ball(g("Pearl"), (math.cos(a) * 0.38, math.sin(a) * 0.35 - 0.02, 4.75 - 0.12 * max(0.0, -math.sin(a))), 0.05, segs=8)
        taper(g("SkinMasked"), (0.0, 0.0, 4.5), (0.0, 0.0, 4.95), 0.3, 0.28)
    arms("SkinMasked", "GloveBlack", (0.85, 0.0, 4.25), (1.0, -0.05, 3.2), (1.02, -0.25, 2.3), radii=(0.18, 0.15, 0.13), forearm="GloveBlack", hand_mat="GloveBlack",
         palm=0.2, finger=0.55, fr=0.05, spread=0.08, curl=0.14)
    legs("GownGreen", (0.3, 0.0, 1.2), (0.3, 0.0, 0.2), radii=(0.22, 0.18), shoe=("Shoe", (0.2, 0.36, 0.14), 0.25))
    joints((0.0, 0.0, 4.85), (0.85, 0.0, 4.25), (0.3, 0.0, 1.2), hc.z + 0.2, hc)


def bride(o):
    """The bride: a veil over nothing. Inside it, dark, and two points of light."""
    hc = Vector((0.0, 0.0, 5.9))
    skin("SkinBride", (0.64, 0.66, 0.64, 1), hc + o, veins=0.6)

    def ragged(bottom, amp=0.25):
        return lambda c: c.z < bottom + amp * math.sin(math.atan2(c.y, c.x) * 11) + amp * 0.6 * math.sin(math.atan2(c.y, c.x) * 29 + 1)

    with part("Head"):
        hood = lathe(g("Bridal"), [(0.5, -1.15), (0.95, -0.9), (1.12, -0.4), (1.15, 0.1), (1.08, 0.55), (0.85, 0.95), (0.45, 1.18), (0.0, 1.24)], at=hc, segs=96,
                     ripple=lambda t, z: 0.03 * math.sin(t * 14) * (1.0 - z / 1.3), soft=0)
        cut_faces(hood, lambda c: c.y < hc.y - 0.3 and ((c.x - hc.x) / 0.62) ** 2 + ((c.z - hc.z + 0.1) / 0.8) ** 2 < 1)
        mod = hood.modifiers.new("Thick", "SOLIDIFY")
        mod.thickness = 0.05
        V.apply_modifiers(hood)
        F.soften(hood)
        egg(g("Hollow"), Matrix.Translation(hc), 1.0, 0.95, 1.05, soft=False)
        for side in (-1, 1):
            ball(g("EyeGlow"), hc + Vector((side * 0.26, -0.99, 0.02)), 0.05, segs=10)
        tail = panel(g("Bridal"), [(1.6, -5.85), (1.4, -4.0), (1.25, -2.5), (1.15, -1.2), (1.12, -0.3), (1.1, 0.5)], at=hc, span=math.pi * 1.1, facing=math.pi / 2, segs=72,
                     ripple=lambda t, z: 0.04 * math.sin(t * 9 + z), thick=0.04)
        cut_faces(tail, ragged(0.15, 0.2))
        for k in range(9):
            a = math.radians(-60 + 15 * k)
            ball(g("Pearl"), hc + Vector((math.sin(a) * 0.9, -math.cos(a) * 0.5 + 0.1, 1.05 + 0.08 * math.cos(a * 2))), 0.07, segs=8)
    gown = [(1.25, 0.05), (1.35, 0.1), (1.25, 0.9), (1.0, 2.0), (0.75, 3.0), (0.78, 3.6), (0.84, 4.0), (0.6, 4.4), (0.3, 4.55), (0.0, 4.56)]
    with part("Torso"):
        dress = lathe(g("Bridal"), gown, squash=0.82, segs=64, ripple=lambda t, z: 0.035 * math.sin(t * 13) * max(0.0, 1 - z / 2.4))
        cut_faces(dress, ragged(0.25, 0.15))
        panel(g("Lace"), [(0.8, 3.0), (0.82, 3.6), (0.87, 4.0), (0.62, 4.42)], span=math.pi * 0.8, segs=30, squash=0.84, thick=0.03)
    arms("Bridal", "SkinBride", (0.84, 0.0, 4.1), (1.02, -0.1, 3.05), (0.85, -0.6, 2.45), radii=(0.25, 0.21, 0.18), cuff="Lace",
         palm=0.19, finger=0.6, fr=0.045, spread=0.075, curl=0.16)
    with part("LeftArm"):
        bouquet(g("DeadFlower"), g("DeadStem"), (0.75, -1.0, 2.25))
    legs("Bridal", (0.32, 0.0, 1.2), (0.32, 0.0, 0.2), radii=(0.22, 0.18))
    joints((0.0, 0.0, 4.7), (0.84, 0.0, 4.1), (0.32, 0.0, 1.2), hc.z, hc)


def paper_bag(grp, centre, size, holes):
    """A crumpled brown paper bag over a head: open at the bottom, eye holes torn in the front."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=14, use_grid_fill=True)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -0.49], context="FACES")
    for v in bm.verts:
        p = v.co.copy()
        crumple = 0.06 * noise.noise(p * 4.0) + 0.03 * noise.noise(p * 11.0)
        v.co = Vector((p.x * size[0], p.y * size[1], p.z * size[2])) + p.normalized() * crumple + Vector(centre)
    obj = V.mesh_object("Bag", bm, grp)
    c = Vector(centre)
    cut_faces(obj, lambda q: q.y < c.y - size[1] * 0.45 and any(math.hypot(q.x - c.x - hx, q.z - c.z - hz) < r * (1 + 0.25 * math.sin(math.atan2(q.z - c.z - hz, q.x - c.x - hx) * 7)) for hx, hz, r in holes))
    mod = obj.modifiers.new("Thick", "SOLIDIFY")
    mod.thickness = 0.04
    V.apply_modifiers(obj)
    return F.soften(obj)


def bag_man(o):
    """The bag man: a paper grocery bag over his head, a smile drawn on it in marker."""
    hc = Vector((0.0, 0.0, 6.1))
    skin("SkinBag", (0.78, 0.62, 0.52, 1), hc + o, veins=0.2)
    ink = (0.03, 0.03, 0.03, 1)
    grin = [("arc", -0.38, 0.25, 0.8, 0.03, 0.0, ink, 1.0), ("arc", -0.72, 0.42, 0.75, 0.03, 0.0, ink, 1.0)]  # a grin scribbled in marker
    grin += [("seg", x, -0.38 + 0.25 * x * x, x, -0.72 + 0.42 * x * x, 0.022, ink, 1.0) for x in (0.0, 0.14, 0.28, 0.42, 0.56, 0.68)]  # its teeth
    skin("PaperBag", (0.62, 0.46, 0.3, 1), hc + o, rough=0.95, sss=0.0, paint=grin + [
        ("streak", 0.42, 0.12, -0.7, 0.045, (0.14, 0.06, 0.04, 1), 0.85),  # something soaking down from the eye holes
    ])
    eyeball("EyeBlood3", look=(0.0, -1.0, -0.1), veins=1.0, iris=(0.25, 0.3, 0.2, 1), pupil_size=0.993)
    with part("Head"):
        paper_bag(g("PaperBag"), hc + Vector((0, 0, 0.1)), (2.3, 2.0, 2.7), [(-0.42, 0.25, 0.17), (0.42, 0.25, 0.17)])
        for side in (-1, 1):
            egg(g("Hollow"), Matrix.Translation(hc + Vector((side * 0.42, -0.86, 0.35))), 0.2, 0.06, 0.2, soft=False)
            ball(g("EyeBlood3"), hc + Vector((side * 0.42, -0.9, 0.35)), 0.15, segs=20)
        egg(g("Hollow"), Matrix.Translation(hc), 1.05, 0.9, 1.2, soft=False)
    shirt = [(0.95, 1.7), (1.05, 1.8), (1.12, 2.5), (1.15, 3.3), (1.08, 4.0), (0.85, 4.45), (0.5, 4.65), (0.0, 4.7)]
    with part("Torso"):
        lathe(g("ShirtGreen"), shirt, squash=0.8, segs=48)
        panel(g("Apron"), [(1.18, 1.3), (1.2, 2.2), (1.2, 3.1), (1.12, 3.9), (0.95, 4.25)], span=math.pi * 0.42, segs=20, squash=0.82, thick=0.05,
              ripple=lambda t, z: 0.02 * math.sin(t * 8 + z))
        tube(g("Apron"), [(-0.35, -0.75, 4.2), (-0.4, -0.2, 4.7), (0.0, 0.3, 4.75), (0.4, -0.2, 4.7), (0.35, -0.75, 4.2)], [0.05] * 5, sides=1)
        lathe(g("Apron"), ring(1.17, 2.7, 0.05), squash=0.82, segs=48, caps=(False, False))
        taper(g("SkinBag"), (0.0, 0.0, 4.5), (0.0, 0.0, 5.0), 0.38, 0.36)
    arms("ShirtGreen", "SkinBag", (1.02, 0.0, 4.2), (1.32, -0.05, 3.1), (1.38, -0.2, 2.35), radii=(0.36, 0.3, 0.26), forearm="SkinBag", hand_mat="Rubber",
         palm=0.25, finger=0.42, fr=0.08, spread=0.11)
    for side in (-1, 1):
        with part(arm(side)):
            lathe(g("ShirtGreen"), [(0.3, 0.0), (0.37, 0.03), (0.38, 0.22), (0.3, 0.25)], at=(side * 1.31, -0.06, 2.98), segs=24, caps=(False, False))
            lathe(g("Rubber"), [(0.24, 0.0), (0.32, 0.04), (0.32, 0.35), (0.24, 0.38)], at=(side * 1.38, -0.21, 2.15), segs=24, caps=(False, False))
    with part("RightArm"):  # a full black trash bag
        lathe(g("TrashBag"), [(0.0, -1.3), (0.6, -1.25), (0.95, -0.9), (1.0, -0.5), (0.8, -0.15), (0.3, 0.05), (0.12, 0.12), (0.0, 0.2)], at=(-1.45, -0.45, 1.85), segs=40,
              ripple=lambda t, z: 0.08 * noise.noise(Vector((math.cos(t) * 2, math.sin(t) * 2, z * 2))))
    legs("Denim", (0.42, 0.0, 1.8), (0.42, 0.0, 0.35), radii=(0.34, 0.3), shoe=("Leather", (0.3, 0.48, 0.24), 0.16))
    joints((0.0, 0.0, 4.85), (1.02, 0.0, 4.2), (0.42, 0.0, 1.8), hc.z + 0.25, hc)


CHARACTERS = {
    "Curlers": curlers,
    "Lanky": lanky,
    "Nightgown": nightgown,
    "SackMask": sackmask,
    "TankTop": tank_top,
    "Cardigan": cardigan,
    "SweaterVest": sweater_vest,
    "Porcelain": porcelain_doll,
    "Grinner": grinner,
    "PumpkinSuit": pumpkin_suit,
    "Widow": widow,
    "RavenMan": raven_man,
    "Bathrobe": bathrobe,
    "Butler": butler,
    "MaskedLady": masked_lady,
    "Gown": bride,
    "BagMan": bag_man,
}
HEADC = {}  # character -> head centre (studs, Blender), for the close-ups
EXPORT = V.ROOT / "export" / "characters"
DATA = V.ROOT.parent / "src" / "shared" / "Config" / "CharacterModels.luau"
BUDGET = {"Head": 9000, "Torso": 6000, "LeftArm": 2500, "RightArm": 2500, "LeftLeg": 1800, "RightLeg": 1800}  # triangles per mesh


# Render -------------------------------------------------------------------------------------------
def place(name, offset):
    """Builds a character and moves it by `offset` (its face paint already knows where it ends up)."""
    CUR["char"] = name
    before = set(bpy.data.objects)
    CHARACTERS[name](Vector(offset))
    for obj in set(bpy.data.objects) - before:
        obj.location += Vector(offset)
    CUR["char"] = None


def porch(width):
    """Porch boards underfoot and the dark front of a house behind (studs)."""
    V.box("Porch", (width, 18, 0.3), (0.0, -4.0, -0.15))
    V.box("WallDark", (width, 0.5, 18), (0.0, 3.0, 9.0))
    V.box("Trim", (width, 0.6, 0.4), (0.0, 2.6, 0.2))


def lights(spots, scene):
    """A warm porch lamp up to the left of each spot, a cold moon rim from behind, a faint fill."""
    def point(name, energy, color, loc, size):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        light.data.energy = energy
        light.data.color = color
        light.data.shadow_soft_size = size
        light.location = loc
        scene.collection.objects.link(light)

    for k, (x, top) in enumerate(spots):
        point(f"Lamp{k}", 1300 + top * 70, (1.0, 0.62, 0.32), (x - 3.0, -4.5, top + 2.5), 0.4)
        point(f"Rim{k}", 380, (0.5, 0.62, 1.0), (x + 2.2, 1.3, top + 1.2), 0.6)
    point("Fill", 400, (0.5, 0.6, 1.0), (0.0, -22.0, 6.0), 4.0)


def render(path, cam_loc, target, lens, res):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.016, 0.03, 1)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = lens
    cam.location = cam_loc
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    RENDERS.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def setup():
    V.reset()
    _BVH.clear()
    V.build_materials()
    import interiors

    interiors.materials(V)
    materials()


def merge_parts(names):
    """Merges every group, then joins each character's groups into its six parts:
    Char_Owner_<Character>_<Part> (the names Modules/CharacterRig asks for)."""
    merged = {}
    for name in names:
        for p in PARTS:
            prefix = f"{name}_{p}|"
            objs = [V.merge_group(grp) for grp in list(V.GROUPS) if grp.startswith(prefix)]
            objs = [obj for obj in objs if obj is not None]
            if not objs:
                raise SystemExit(f"{name} has no {p}")
            for obj in bpy.context.scene.objects:
                obj.select_set(False)
            for obj in objs:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            if len(objs) > 1:
                bpy.ops.object.join()
            obj = bpy.context.view_layer.objects.active
            obj.name = obj.data.name = f"Char_Owner_{name}_{p}"
            merged[obj.name] = obj
    for grp in list(V.GROUPS):
        if "|" not in grp and not grp.startswith("_"):
            V.merge_group(grp)
    return merged


def lineup(names, filename):
    setup()
    gap = 6.5
    xs = [(k - (len(names) - 1) / 2) * gap for k in range(len(names))]
    for name, x in zip(names, xs):
        place(name, (x, 0.0, 0.0))
    width = len(names) * gap + 10
    porch(width)
    merge_parts(names)
    lights([(x, HEADC[name][2]) for name, x in zip(names, xs)], bpy.context.scene)
    span = len(names) * gap + 3
    render(RENDERS / filename, (0.0, -span * 0.85, 4.4), (0.0, 0.0, 4.9), 30, (2000, 950))


def close(name):
    setup()
    place(name, (0.0, 0.0, 0.0))
    porch(30)
    merge_parts([name])
    hx, hy, hz = HEADC[name]
    lights([(0.0, hz)], bpy.context.scene)
    # From a trick-or-treater's eye height, a few studs away, looking up at the face.
    dist = 6.5 + max(0.0, hz - 6.0) * 0.8
    render(RENDERS / f"{name}_close.png", (0.8, hy - dist, 3.9), (hx, hy, hz - 0.15), 50 + max(0.0, hz - 6.0) * 8, (900, 1100))


# Export -------------------------------------------------------------------------------------------
def decimate(obj, budget):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > budget:
        mod = obj.modifiers.new("Budget", "DECIMATE")
        mod.ratio = budget / tris
        V.apply_modifiers(obj)
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def roblox(v):
    """Blender (x, y, z), the character facing -Y, as Roblox (facing -Z): (-x, z, y)."""
    return (-v[0], v[2], v[1])


def write_data(segments):
    def vec(v):
        return "{ " + ", ".join(f"{c:.3f}" for c in v) + " }"

    lines = [
        "--!strict",
        "-- Generated by art/scripts/characters.py --export (don't edit): the Blender homeowners, each in the",
        "-- rig's six parts. Sizes and offsets in studs, an offset being the part's centre from the point",
        "-- between the feet, facing -Z; pivots are where Modules/CharacterRig joins the parts; face is the",
        "-- middle of the face (long hair and veils make the head part's middle useless for that). The meshes",
        "-- are ReplicatedStorage.Assets.Characters.Char_<id>_<Part> (tools/setup_characters.luau).",
        "",
        "return {",
    ]
    for name, segs in segments.items():
        lines.append(f"\tOwner_{name} = {{")
        lines.append(f"\t\teye = {EYES[name]:.3f},")
        lines.append(f"\t\tface = {vec(roblox(HEADC[name]))},")
        lines.append("\t\tsegments = {")
        for p in PARTS:
            size, centre = segs[p]
            lines.append(f"\t\t\t{p} = {{ size = {vec((size.x, size.z, size.y))}, offset = {vec(roblox(centre))} }},")
        lines.append("\t\t},")
        lines.append("\t\tpivots = {")
        for joint in ("Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip"):
            lines.append(f"\t\t\t{joint} = {vec(roblox(PIVOTS[name][joint]))},")
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    DATA.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("WROTE", DATA)


def silhouette(obj, offset, step=0.15):
    """The top of a part seen from the side: for each `step` of depth, its highest point. Roblox
    space (z = Blender y, + back), feet at the origin. HomeownerController folds them by it."""
    tops = {}
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co - offset
        k = round(w.y / step)
        tops[k] = max(tops.get(k, -1e9), w.z)
    return [(tops[k], k * step) for k in sorted(tops)]


def write_outlines(names):
    """Adds each character's side silhouette (head and torso) to CharacterModels.luau as `outline`,
    leaving the rest as the last export wrote it (no re-bake)."""
    setup()
    offsets = {name: Vector(((k % 6) * 16.0, (k // 6) * 16.0, 0.0)) for k, name in enumerate(names)}
    for name in names:
        place(name, offsets[name])
    merged = merge_parts(names)
    text = DATA.read_text(encoding="utf-8")
    for name in names:
        points = []
        for p in ("Head", "Torso"):
            points += silhouette(merged[f"Char_Owner_{name}_{p}"], offsets[name])
        # Keep only what could catch overhead: the higher of any two points at the same depth.
        best = {}
        for y, z in points:
            best[round(z, 2)] = max(best.get(round(z, 2), -1e9), y)
        line = "\t\toutline = { " + ", ".join(f"{{ {y:.2f}, {z:.2f} }}" for z, y in sorted(best.items())) + " },\n"
        anchor = f"\tOwner_{name} = {{\n"
        at = text.index(anchor) + len(anchor)
        rest = text[at:]
        if rest.startswith("\t\toutline = "):
            rest = rest[rest.index("\n") + 1:]
        text = text[:at] + line + rest
        print("OUTLINE", name, len(best))
    DATA.write_text(text, encoding="utf-8", newline="\n")


def export(names):
    import export_victorian

    setup()
    offsets = {name: Vector(((k % 6) * 16.0, (k // 6) * 16.0, 0.0)) for k, name in enumerate(names)}  # apart, so no shadow falls on a neighbour
    for name in names:
        place(name, offsets[name])
    merged = merge_parts(names)
    segments = {}
    for name in names:
        segments[name] = {}
        for p in PARTS:
            obj = merged[f"Char_Owner_{name}_{p}"]
            tris = decimate(obj, BUDGET[p])
            vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
            lo = Vector([min(v[i] for v in vs) for i in range(3)])
            hi = Vector([max(v[i] for v in vs) for i in range(3)])
            segments[name][p] = (hi - lo, (lo + hi) / 2 - offsets[name])
            print("PART", obj.name, tris)
    write_data(segments)
    for obj in [o for o in bpy.data.objects if o.type == "MESH" and o.name not in merged]:
        bpy.data.objects.remove(obj, do_unlink=True)  # the porch and so on
    sizes = {n: (1024 if n.endswith("_Head") or n.endswith("_Torso") else 512) for n in merged}
    export_victorian.export(merged, EXPORT, "Homeowners.fbx", sizes=sizes)


def sheet(names, filename, cols=6):
    """Tiles the close-ups of `names` (half size) into one picture, left to right, top to bottom."""
    import numpy as np

    tiles = []
    for name in names:
        img = bpy.data.images.load(str(RENDERS / f"{name}_close.png"))
        img.scale(img.size[0] // 2, img.size[1] // 2)
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        tiles.append(px.reshape(h, w, 4))
    h, w = tiles[0].shape[:2]
    rows = (len(tiles) + cols - 1) // cols
    big = np.zeros((rows * h, cols * w, 4), dtype=np.float32)
    big[..., 3] = 1.0
    for k, tile in enumerate(tiles):
        r, c = divmod(k, cols)
        y0 = (rows - 1 - r) * h  # Blender images start at the bottom
        big[y0:y0 + h, c * w:(c + 1) * w] = tile
    out = bpy.data.images.new("Sheet", cols * w, rows * h)
    out.pixels.foreach_set(big.ravel())
    out.filepath_raw = str(RENDERS / filename)
    out.file_format = "PNG"
    out.save()
    print("SHEET", RENDERS / filename)


GROUPS_OF = [["Curlers", "TankTop", "Cardigan", "Nightgown", "SweaterVest", "Porcelain"],
             ["Grinner", "SackMask", "PumpkinSuit", "Lanky", "BagMan"],
             ["Widow", "RavenMan", "Bathrobe", "Butler", "MaskedLady", "Gown"]]

if __name__ == "__main__":
    if "--lineup" in ARGS:
        k = int(ARGS[ARGS.index("--lineup") + 1])
        lineup(GROUPS_OF[k], f"cast_{k + 1}.png")
    elif "--close" in ARGS:
        for name in ARGS[ARGS.index("--close") + 1].split(","):
            close(name)
    elif "--sheet" in ARGS:
        names = ARGS[ARGS.index("--sheet") + 1].split(",")
        sheet(names, ARGS[ARGS.index("--sheet") + 2])
    elif "--outline" in ARGS:
        write_outlines(list(CHARACTERS))
    elif "--export" in ARGS:
        names = ARGS[ARGS.index("--export") + 1].split(",") if len(ARGS) > ARGS.index("--export") + 1 else list(CHARACTERS)
        export(names)
