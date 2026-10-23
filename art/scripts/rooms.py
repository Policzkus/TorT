"""Renders the rooms you see through the Victorian's windows (Blender 4.4, headless).

    blender -b --factory-startup --python art/scripts/rooms.py

Small images (PSX-style; Roblox shows them with pixelated scaling) of rooms seen from a window:
lit ones glow at night (LightInfluence 0 in game), dark ones only show up in your flashlight.
Output: art/renders/rooms/<name>.png
"""

import math
import pathlib
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from victorian import TEX  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[1] / "renders" / "rooms"
RES = 256


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = scene.render.resolution_y = RES
    scene.eevee.taa_render_samples = 32
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.011, 0.01, 1)


def mat(name, color, tex=None, emission=None, scale=1.0, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    if tex:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(str(TEX / tex / f"{tex}_diff_1k.jpg"), check_existing=True)
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        nt.links.new(mapping.outputs["Vector"], img.inputs["Vector"])
        img.projection = "BOX"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        nt.links.new(img.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = color
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = color
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission[0]
        bsdf.inputs["Emission Strength"].default_value = emission[1]
    return m


def stripes(name, a, b, stain=0.6):
    """Victorian striped wallpaper with water stains."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95
    coord = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 1.6
    nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = a
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = b
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.6
    noise.inputs["Detail"].default_value = 8
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    stains = nt.nodes.new("ShaderNodeMapRange")
    stains.inputs["From Min"].default_value = 0.45
    stains.inputs["From Max"].default_value = 0.7
    stains.inputs["To Min"].default_value = 1.0
    stains.inputs["To Max"].default_value = 1.0 - stain
    nt.links.new(noise.outputs["Fac"], stains.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for ch in ("Red", "Green", "Blue"):
        nt.links.new(stains.outputs["Result"], comb.inputs[ch])
    nt.links.new(comb.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return m


def box(size, loc, material, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    me = bpy.data.meshes.new("b")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("b", me)
    obj.location = loc
    obj.rotation_euler = rot
    me.materials.append(material)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def cylinder(r, depth, loc, material, verts=12, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    me = bpy.data.meshes.new("c")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("c", me)
    obj.location = loc
    me.materials.append(material)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def sphere(r, loc, material):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=r)
    me = bpy.data.meshes.new("s")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("s", me)
    obj.location = loc
    me.materials.append(material)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def glow(obj):
    """Emissive light fittings shouldn't block the lamp inside them."""
    obj.visible_shadow = False
    return obj


def light(kind, loc, energy, color, size=0.2):
    l = bpy.data.objects.new("L", bpy.data.lights.new("L", kind))
    l.location = loc
    l.data.energy = energy
    l.data.color = color
    if kind in ("POINT", "SPOT"):
        l.data.shadow_soft_size = size
    bpy.context.scene.collection.objects.link(l)
    return l


def room(wall, floor_tex="weathered_planks", depth=9.0, width=11.0, height=9.0):
    """The room box: the window is at y = 0 looking toward +y."""
    floor = mat("Floor", (0.55, 0.5, 0.45, 1), tex=floor_tex, scale=0.25)
    ceiling = mat("Ceiling", (0.25, 0.23, 0.2, 1))
    box((width, depth, 0.2), (0, depth / 2, -0.1), floor)
    box((width, depth, 0.2), (0, depth / 2, height), ceiling)
    box((width, 0.2, height), (0, depth, height / 2), wall)
    box((0.2, depth, height), (-width / 2, depth / 2, height / 2), wall)
    box((0.2, depth, height), (width / 2, depth / 2, height / 2), wall)
    box((width, 0.25, 0.5), (0, depth - 0.15, 0.25), mat("Skirting", (0.12, 0.1, 0.08, 1)))


def camera(target=(0, 6, 3.6), loc=(0, 0.3, 4.2), lens=22):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = lens
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def figure(loc, material, sitting=False, tilt=0.0):
    x, y, z = loc
    if sitting:
        box((1.4, 1.0, 1.6), (x, y, z + 2.4), material)
        sphere(0.55, (x + tilt, y, z + 3.6), material)
    else:
        cylinder(0.55, 4.6, (x, y, z + 2.3), material, verts=10, r2=0.4)
        sphere(0.5, (x + tilt, y, z + 5.0), material)


def render(name):
    OUT.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.filepath = str(OUT / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("ROOM", name)


def lamp_room():
    reset()
    room(stripes("Paper", (0.36, 0.3, 0.2, 1), (0.28, 0.22, 0.15, 1)))
    dark = mat("Dark", (0.06, 0.05, 0.045, 1))
    fabric = mat("Fabric", (0.3, 0.12, 0.1, 1))
    # Armchair, side table, a lamp with a glowing shade, a crooked picture.
    box((2.8, 2.4, 1.0), (-2.6, 6.0, 0.9), fabric)
    box((2.8, 0.6, 3.0), (-2.6, 7.1, 1.6), fabric)
    for sx in (-1, 1):
        box((0.5, 2.4, 1.6), (-2.6 + sx * 1.3, 6.0, 1.3), fabric)
    box((1.4, 1.4, 2.4), (1.4, 7.4, 1.2), dark)
    cylinder(0.08, 2.0, (1.4, 7.4, 3.4), dark)
    glow(cylinder(0.9, 1.1, (1.4, 7.4, 4.6), mat("Shade", (0.9, 0.7, 0.45, 1), emission=((1.0, 0.65, 0.3, 1), 3.0)), r2=0.55))
    light("POINT", (1.4, 7.0, 4.4), 2200, (1.0, 0.62, 0.32), 0.4)
    box((2.0, 0.1, 1.5), (3.0, 8.85, 5.6), dark, rot=(0, 0.12, 0))
    box((1.6, 0.05, 1.1), (3.0, 8.8, 5.6), mat("Painting", (0.12, 0.08, 0.06, 1)), rot=(0, 0.12, 0))
    camera()
    render("lit_lamp")


def tv_room():
    reset()
    room(stripes("Paper", (0.22, 0.24, 0.22, 1), (0.17, 0.19, 0.17, 1)))
    dark = mat("Dark", (0.03, 0.03, 0.035, 1))
    # Someone sits facing an old TV at the back; its blue glow is the only light.
    box((3.0, 2.0, 2.2), (0.4, 8.0, 1.1), dark)
    glow(box((2.2, 0.1, 1.6), (0.4, 6.95, 1.6), mat("Screen", (0.3, 0.4, 0.5, 1), emission=((0.55, 0.7, 1.0, 1), 4.0))))
    light("POINT", (0.4, 6.2, 1.9), 700, (0.55, 0.7, 1.0), 0.6)
    box((2.4, 2.2, 1.0), (0.2, 4.2, 0.8), dark)
    box((2.4, 0.5, 2.8), (0.2, 3.2, 1.6), dark)
    figure((0.2, 4.1, 0.0), dark, sitting=True, tilt=0.25)
    camera(target=(0, 6, 2.2), loc=(0.0, 0.3, 4.5))
    render("lit_tv")


def hall_room():
    reset()
    room(stripes("Paper", (0.3, 0.26, 0.2, 1), (0.25, 0.2, 0.16, 1), stain=0.75))
    dark = mat("Dark", (0.004, 0.004, 0.004, 1))
    # A bare bulb, an open doorway at the back, and someone standing in it.
    glow(sphere(0.25, (0, 4.5, 7.6), mat("Bulb", (1, 0.9, 0.7, 1), emission=((1.0, 0.8, 0.5, 1), 12.0))))
    cylinder(0.03, 1.3, (0, 4.5, 8.4), dark)
    light("POINT", (0, 4.5, 7.4), 1600, (1.0, 0.78, 0.5), 0.1)
    # The doorway: a faintly lit corridor beyond, someone standing black against it.
    box((2.6, 0.1, 6.0), (1.6, 8.85, 3.0), mat("Corridor", (0.02, 0.02, 0.025, 1), emission=((0.25, 0.22, 0.2, 1), 0.6)))
    figure((1.6, 8.3, 0.0), mat("Fig", (0, 0, 0, 1)), tilt=0.2)
    camera()
    render("lit_hall")


def candle_room():
    reset()
    room(stripes("Paper", (0.3, 0.2, 0.22, 1), (0.24, 0.16, 0.17, 1)))
    dark = mat("Dark", (0.05, 0.04, 0.035, 1))
    sheet = mat("Sheet", (0.5, 0.48, 0.44, 1))
    # A bed with a doll sitting on it, a dresser with a candle.
    box((4.0, 5.0, 1.2), (-2.0, 6.4, 0.6), dark)
    box((4.0, 5.0, 0.3), (-2.0, 6.4, 1.35), sheet)
    box((4.0, 0.3, 3.0), (-2.0, 8.8, 1.5), dark)
    figure((-1.2, 6.0, 1.5), mat("Doll", (0.6, 0.55, 0.5, 1)), sitting=True, tilt=0.3)
    box((2.4, 1.4, 2.6), (3.0, 8.0, 1.3), dark)
    cylinder(0.12, 0.6, (3.0, 7.8, 2.9), mat("Wax", (0.8, 0.75, 0.6, 1)))
    glow(sphere(0.1, (3.0, 7.8, 3.3), mat("Flame", (1, 0.7, 0.3, 1), emission=((1.0, 0.6, 0.2, 1), 15.0))))
    light("POINT", (3.0, 7.6, 3.4), 700, (1.0, 0.55, 0.25), 0.05)
    camera(target=(0, 6, 2.8))
    render("lit_candle")


def attic_room():
    reset()
    boards = mat("Boards", (0.42, 0.36, 0.3, 1), tex="weathered_planks", scale=0.3)
    box((11, 9, 0.2), (0, 4.5, -0.1), boards)
    for side in (-1, 1):
        box((0.2, 9.5, 8.5), (side * 3.0, 4.5, 3.2), boards, rot=(0, side * math.radians(38), 0))
    box((11, 0.2, 9), (0, 9.0, 4.5), boards)
    dark = mat("Dark", (0.02, 0.02, 0.02, 1))
    glow(sphere(0.22, (0, 5.0, 5.2), mat("Bulb", (1, 0.9, 0.7, 1), emission=((1.0, 0.7, 0.4, 1), 10.0))))
    light("POINT", (0, 5.0, 5.0), 1300, (1.0, 0.6, 0.35), 0.1)
    # Boxes and a covered chair under a sheet.
    box((1.6, 1.6, 1.4), (-1.6, 7.4, 0.7), dark)
    box((1.2, 1.2, 1.0), (-1.3, 7.2, 1.9), dark)
    cylinder(1.0, 2.6, (1.8, 7.0, 1.3), mat("Sheet", (0.55, 0.52, 0.48, 1)), r2=0.6)
    camera(target=(0, 6, 2.6), loc=(0, 0.3, 3.4))
    render("lit_attic")


def dark_room(name, paper):
    reset()
    room(stripes("Paper", *paper))
    dark = mat("Dark", (0.1, 0.09, 0.08, 1))
    sheet = mat("Sheet", (0.55, 0.52, 0.48, 1))
    # Furniture under dust sheets; only your flashlight shows it.
    cylinder(1.3, 2.4, (-2.4, 6.8, 1.2), sheet, r2=0.9)
    box((3.4, 1.4, 3.2), (2.6, 8.2, 1.6), sheet)
    box((1.8, 0.1, 2.6), (-0.2, 8.85, 4.6), dark)
    light("SUN", (0, 0, 10), 1.6, (0.9, 0.9, 1.0)).rotation_euler = (math.radians(60), 0, 0)
    camera()
    render(name)


if __name__ == "__main__":
    lamp_room()
    tv_room()
    hall_room()
    candle_room()
    attic_room()
    dark_room("dark_a", ((0.4, 0.36, 0.3, 1), (0.32, 0.28, 0.23, 1)))
    dark_room("dark_b", ((0.3, 0.33, 0.3, 1), (0.24, 0.27, 0.24, 1)))
