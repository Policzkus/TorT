"""Bakes the scripted Victorian into Roblox-ready meshes and exports one FBX.

    blender -b --factory-startup --python art/scripts/export_victorian.py

Every textured group gets its own 1024x1024 atlas (Roblox's SurfaceAppearance limit): colour with
the grime and corner shadows baked in, a tangent normal map and roughness, all from the tiling
Poly Haven materials. Flat groups (glass, glow, dark interiors, iron) keep plain colours; their
look is set in Roblox. Output: art/export/victorian/Victorian.fbx (+ PNGs next to it).
"""

import math
import pathlib
import sys

import bpy

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import victorian  # noqa: E402

SIZE = 1024
FLAT = {"Glass", "Glow", "Interior", "Silhouette", "Iron", "Brass_FrontDoor", "Brass_BackDoor", "Curtain", "Wallpaper"}
OUT = victorian.EXPORT
# --only A,B: bake just these groups and reuse the other PNGs from the last export.
ONLY = set(victorian.ARGS[victorian.ARGS.index("--only") + 1].split(",")) if "--only" in victorian.ARGS else None


def select_only(obj):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def atlas_uvs(obj):
    me = obj.data
    me.uv_layers.active = me.uv_layers["Atlas"]
    select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(obj, reuse=False):
    """Bakes the object's maps, or with `reuse` loads the PNGs a previous export left behind
    (the atlas UVs come out the same for the same mesh)."""
    scene = bpy.context.scene
    mat = obj.data.materials[0].copy()
    obj.data.materials[0] = mat
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    atlas_uvs(obj)
    images = {}
    passes = (("color", "DIFFUSE", "sRGB"), ("normal", "NORMAL", "Non-Color"), ("rough", "ROUGHNESS", "Non-Color"))
    if reuse:
        for kind, _, space in passes:
            img = bpy.data.images.load(str(OUT / f"{obj.name}_{kind}.png"))
            img.colorspace_settings.name = space
            images[kind] = img
        passes = ()
    for kind, bake_type, space in passes:
        img = bpy.data.images.new(f"{obj.name}_{kind}", SIZE, SIZE, alpha=False)
        img.colorspace_settings.name = space
        target = nodes.new("ShaderNodeTexImage")
        target.image = img
        uv = nodes.new("ShaderNodeUVMap")
        uv.uv_map = "Atlas"
        links.new(uv.outputs["UV"], target.inputs["Vector"])
        for n in nodes:
            n.select = False
        target.select = True
        nodes.active = target
        select_only(obj)
        if bake_type == "DIFFUSE":
            scene.render.bake.use_pass_direct = False
            scene.render.bake.use_pass_indirect = False
            scene.render.bake.use_pass_color = True
        bpy.ops.object.bake(type=bake_type, margin=6, uv_layer="Atlas", use_clear=True)
        path = OUT / f"{obj.name}_{kind}.png"
        img.filepath_raw = str(path)
        img.file_format = "PNG"
        img.save()
        nodes.remove(target)
        nodes.remove(uv)
        images[kind] = img
        print("BAKED", path.name)
    # Swap in a simple material that only uses the baked maps on the atlas UVs.
    baked = bpy.data.materials.new(obj.name)
    baked.use_nodes = True
    bn, bl = baked.node_tree.nodes, baked.node_tree.links
    bsdf = bn["Principled BSDF"]
    uv = bn.new("ShaderNodeUVMap")
    uv.uv_map = "Atlas"
    tex = {}
    for kind in ("color", "normal", "rough"):
        t = bn.new("ShaderNodeTexImage")
        t.image = images[kind]
        bl.new(uv.outputs["UV"], t.inputs["Vector"])
        tex[kind] = t
    bl.new(tex["color"].outputs["Color"], bsdf.inputs["Base Color"])
    nmap = bn.new("ShaderNodeNormalMap")
    bl.new(tex["normal"].outputs["Color"], nmap.inputs["Color"])
    bl.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bl.new(tex["rough"].outputs["Color"], bsdf.inputs["Roughness"])
    obj.data.materials[0] = baked
    obj.data.uv_layers.remove(obj.data.uv_layers["Tile"])
    obj.data.uv_layers["Atlas"].active_render = True


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    merged, *_ = victorian.build()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = False
    for name, obj in merged.items():
        if name in FLAT:
            # Plain colours: drop the tiling UVs, keep one UV map for the importer.
            obj.data.uv_layers.remove(obj.data.uv_layers["Tile"])
            continue
        reuse = ONLY is not None and name not in ONLY and (OUT / f"{name}_color.png").exists()
        bake(obj, reuse=reuse)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.fbx(
        filepath=str(OUT / "Victorian.fbx"),
        use_selection=False,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        path_mode="COPY",
        embed_textures=True,
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
    )
    print("EXPORTED", OUT / "Victorian.fbx", len(merged), "meshes")


if __name__ == "__main__":
    main()
