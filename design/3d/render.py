# Renders voicemode's glass objects with Cycles.
#
#   Blender -b -P design/3d/render.py -- <out_dir> [object ...] [--fast]
#
# Every object renders alone on a transparent background, lit by the same
# studio rig, so the images composite over any colour field in the UI.

import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FAST = "--fast" in argv
argv = [a for a in argv if a != "--fast"]
OUT = argv[0] if argv else "/tmp/voicemode-3d"
ONLY = set(argv[1:])


def set_input(node, names, value):
    for name in names if isinstance(names, (list, tuple)) else [names]:
        if name in node.inputs:
            node.inputs[name].default_value = value
            return


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        scene.cycles.device = "GPU"
    except Exception:
        scene.cycles.device = "CPU"
    scene.cycles.samples = 48 if FAST else 256
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 16
    scene.cycles.transmission_bounces = 16
    scene.cycles.glossy_bounces = 8
    scene.render.film_transparent = True
    if hasattr(scene.cycles, "film_transparent_glass"):
        scene.cycles.film_transparent_glass = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -0.35
    return scene


def world():
    w = bpy.data.worlds.new("studio")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.62, 0.42, 0.34, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (1.0, 0.97, 0.93, 1)
    bg.inputs["Strength"].default_value = 1.1
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def area_light(name, loc, power, size, color=(1, 1, 1), target=(0, 0, 0)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    direction = Vector(target) - Vector(loc)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def studio(accent):
    world()
    area_light("key", (-5, -6, 7), 1400, 7, (1.0, 0.97, 0.92))
    area_light("rim", (5, 6, 5), 1600, 5, (0.9, 0.95, 1.0))
    area_light("fill", (7, -5, 1), 500, 6, accent)
    area_light("under", (0, -3, -5), 250, 6, accent)


def camera(distance, lens=70, height=0.35, target=(0, 0, 0)):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = Vector(target) + Vector((0, -distance, distance * height))
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam


def material(name, tint, rough=0.12, absorb=None, density=0.35, emission=None, strength=0.0, transmission=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    set_input(bsdf, "Base Color", (*tint, 1))
    set_input(bsdf, "Roughness", rough)
    set_input(bsdf, "IOR", 1.47)
    set_input(bsdf, ["Transmission Weight", "Transmission"], transmission)
    set_input(bsdf, ["Coat Weight", "Clearcoat"], 0.7)
    set_input(bsdf, ["Coat Roughness", "Clearcoat Roughness"], 0.04)
    set_input(bsdf, ["Specular IOR Level", "Specular"], 0.6)
    if emission:
        set_input(bsdf, ["Emission Color", "Emission"], (*emission, 1))
        set_input(bsdf, "Emission Strength", strength)
    if absorb:
        vol = nt.nodes.new("ShaderNodeVolumeAbsorption")
        vol.inputs["Color"].default_value = (*absorb, 1)
        vol.inputs["Density"].default_value = density
        nt.links.new(vol.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
    return m


def jelly(name, color, glow=0.0, rough=0.16, transmission=0.55):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    set_input(bsdf, "Base Color", (*color, 1))
    set_input(bsdf, "Roughness", rough)
    set_input(bsdf, "IOR", 1.45)
    set_input(bsdf, ["Subsurface Weight", "Subsurface"], 1.0)
    set_input(bsdf, "Subsurface Radius", (1.0, 1.0, 1.0))
    set_input(bsdf, "Subsurface Scale", 0.25)
    set_input(bsdf, ["Transmission Weight", "Transmission"], transmission)
    set_input(bsdf, ["Coat Weight", "Clearcoat"], 1.0)
    set_input(bsdf, ["Coat Roughness", "Clearcoat Roughness"], 0.03)
    set_input(bsdf, ["Specular IOR Level", "Specular"], 0.7)
    if glow:
        set_input(bsdf, ["Emission Color", "Emission"], (*color, 1))
        set_input(bsdf, "Emission Strength", glow)
    return m


def emissive(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def smooth(obj, bevel=0.2, segments=10):
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = segments
    mod.limit_method = "NONE"
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 2
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def box(name, size, loc=(0, 0, 0), bevel=0.2, segments=10, mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    smooth(obj, bevel, segments)
    if mat:
        obj.data.materials.append(mat)
    return obj


def capsule_mesh(name, radius, length, loc=(0, 0, 0), rot=(0, 0, 0), mat=None):
    mb_data = bpy.data.metaballs.new(name)
    mb_data.resolution = 0.04
    mb_data.render_resolution = 0.02
    el = mb_data.elements.new()
    el.type = "CAPSULE"
    el.radius = radius
    el.size_x = length / 2
    mb = bpy.data.objects.new(name, mb_data)
    bpy.context.collection.objects.link(mb)
    bpy.context.view_layer.objects.active = mb
    mb.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    obj.location = loc
    obj.rotation_euler = rot
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if mat:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def tube(name, radius, length, mat=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=radius, depth=length + 2 * radius, rotation=(0, math.pi / 2, 0))
    obj = bpy.context.active_object
    obj.name = name
    bev = obj.modifiers.new("ends", "BEVEL")
    bev.width = radius * 0.98
    bev.segments = 24
    bev.limit_method = "ANGLE"
    bev.profile = 0.5
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if mat:
        obj.data.materials.append(mat)
    return obj


def rod(name, radius, length, loc=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=length, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = radius * 0.95
    bev.segments = 6
    bev.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if mat:
        obj.data.materials.append(mat)
    return obj


def parent_all(objs, name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for o in objs:
        o.parent = root
    return root


def text_mesh(body, size, extrude, loc, mat, align="CENTER"):
    curve = bpy.data.curves.new("txt", "FONT")
    curve.body = body
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = extrude * 0.35
    curve.bevel_resolution = 4
    curve.align_x = align
    curve.align_y = "CENTER"
    try:
        curve.font = bpy.data.fonts.load("/System/Library/Fonts/SFNS.ttf")
    except Exception:
        pass
    obj = bpy.data.objects.new("txt", curve)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.data.materials.append(mat)
    return obj


def bar_heights(n, seed=3):
    out = []
    s = seed * 7919 + 17
    for i in range(n):
        t = i / (n - 1)
        env = math.sin(math.pi * (0.08 + 0.84 * t)) ** 0.7
        syl = 0.5 + 0.5 * abs(math.sin(i * 1.37 + seed))
        s = (s * 9301 + 49297) % 233280
        out.append(max(0.18, env * syl * (0.45 + 0.55 * s / 233280)))
    return out


# ---------------------------------------------------------------- objects

def obj_capsule_milk():
    return obj_capsule(milky=True)


def obj_capsule(milky=False):
    if milky:
        shell = jelly("shell", (1.0, 0.86, 0.72), rough=0.08, transmission=0.94)
    else:
        shell = material("shell", (1.0, 0.98, 0.96), rough=0.03, absorb=(1.0, 0.86, 0.72), density=0.5)
    glow = emissive("glow", (1.0, 0.9, 0.74), 16.0)
    shell_obj = tube("shell", 1.05, 4.6, mat=shell)
    solid = shell_obj.modifiers.new("wall", "SOLIDIFY")
    solid.thickness = 0.08
    solid.offset = -1
    parts = [shell_obj]
    heights = bar_heights(25, 3)
    for i, h in enumerate(heights):
        x = -2.1 + i * (4.2 / (len(heights) - 1))
        parts.append(rod(f"bar{i}", 0.045, 1.55 * h, loc=(x, 0, 0), mat=glow))
    light = bpy.data.lights.new("inner", "POINT")
    light.energy = 35 if milky else 140
    light.color = (1.0, 0.72, 0.45)
    light.shadow_soft_size = 2.0
    lo = bpy.data.objects.new("inner", light)
    bpy.context.collection.objects.link(lo)
    parts.append(lo)
    root = parent_all(parts, "capsule")
    root.rotation_euler = (math.radians(14), math.radians(-6), math.radians(16))
    studio((1.0, 0.6, 0.35))
    camera(16.5, lens=70, height=0.26)
    return (1600, 1000)


def obj_keycap():
    body = jelly("key", (0.08, 0.28, 1.0), glow=0.08, transmission=0.3)
    legend = emissive("legend", (1.0, 0.98, 0.95), 8.0)
    parts = [box("key", (2.4, 2.4, 1.0), bevel=0.42, segments=12, mat=body)]
    parts.append(text_mesh("fn", 0.95, 0.04, (0.35, 0.3, 0.52), legend))
    root = parent_all(parts, "keycap")
    root.rotation_euler = (math.radians(38), 0, math.radians(-24))
    studio((0.55, 0.7, 1.0))
    camera(8.6, lens=70, height=0.5)
    return (1000, 1000)


def obj_textcard():
    card = jelly("card", (0.05, 0.72, 0.6), glow=0.05, transmission=0.35)
    line = emissive("line", (1, 1, 1), 4.0)
    code = emissive("code", (0.45, 0.95, 1.0), 5.0)
    parts = [box("card", (3.0, 2.2, 0.36), bevel=0.16, segments=10, mat=card)]
    widths = [(2.1, line), (1.3, code), (1.8, line), (1.0, line)]
    for i, (w, m) in enumerate(widths):
        y = 0.62 - i * 0.42
        parts.append(capsule_mesh(f"l{i}", 0.08, w, loc=(-1.1 + w / 2, y, 0.22), mat=m))
    root = parent_all(parts, "textcard")
    root.rotation_euler = (math.radians(48), 0, math.radians(20))
    studio((0.4, 0.95, 0.85))
    camera(10.5, lens=70, height=0.45)
    return (1000, 1000)


def obj_lock():
    body = jelly("lock", (0.12, 0.8, 0.3), glow=0.05, transmission=0.35)
    parts = [box("body", (2.2, 1.0, 1.8), loc=(0, 0, -0.5), bevel=0.3, segments=10, mat=body)]
    bpy.ops.mesh.primitive_torus_add(major_radius=0.72, minor_radius=0.2, major_segments=64, minor_segments=24, location=(0, 0, 0.45), rotation=(math.pi / 2, 0, 0))
    torus = bpy.context.active_object
    for poly in torus.data.polygons:
        poly.use_smooth = True
    cut = box("cut", (3, 3, 1.2), loc=(0, 0, -0.2), bevel=0.0, segments=1)
    boolean = torus.modifiers.new("cut", "BOOLEAN")
    boolean.object = cut
    boolean.operation = "DIFFERENCE"
    bpy.context.view_layer.objects.active = torus
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cut)
    torus.data.materials.append(body)
    parts.append(torus)
    hole = emissive("hole", (0.8, 1.0, 0.85), 4.0)
    parts.append(capsule_mesh("hole", 0.14, 0.35, loc=(0, -0.52, -0.5), rot=(0, math.pi / 2, 0), mat=hole))
    root = parent_all(parts, "lock")
    root.rotation_euler = (math.radians(8), 0, math.radians(-22))
    studio((0.45, 1.0, 0.6))
    camera(11, lens=70, height=0.25, target=(0, 0, 0.1))
    return (1000, 1000)


def obj_stack():
    tints = [(0.35, 0.18, 0.95), (0.62, 0.22, 0.95), (0.95, 0.3, 0.8)]
    parts = []
    for i, tint in enumerate(tints):
        m = jelly(f"card{i}", tint, glow=0.05, transmission=0.35)
        parts.append(box(f"c{i}", (2.8, 2.0, 0.26), loc=(i * 0.18, i * 0.18, i * 0.5), bevel=0.12, segments=8, mat=m))
    line = emissive("line", (1, 0.95, 1), 3.0)
    for j, w in enumerate([1.8, 1.2]):
        parts.append(capsule_mesh(f"l{j}", 0.07, w, loc=(0.36 - 1.0 + w / 2, 0.36 + 0.35 - j * 0.4, 1.16), mat=line))
    root = parent_all(parts, "stack")
    root.rotation_euler = (math.radians(50), 0, math.radians(24))
    studio((0.85, 0.55, 1.0))
    camera(11, lens=70, height=0.45, target=(0.2, 0.2, 0.4))
    return (1000, 1000)


def obj_aa():
    glassm = jelly("aa", (1.0, 0.18, 0.5), glow=0.06, transmission=0.35)
    t = text_mesh("Аа", 2.6, 0.32, (0, 0, 0), glassm)
    t.rotation_euler = (math.radians(90), 0, 0)
    root = parent_all([t], "aa")
    root.rotation_euler = (math.radians(6), 0, math.radians(-14))
    studio((1.0, 0.5, 0.75))
    camera(11, lens=70, height=0.22)
    return (1000, 1000)


def obj_chip():
    body = jelly("chip", (0.05, 0.6, 1.0), glow=0.05, transmission=0.35)
    core = emissive("core", (0.55, 0.95, 1.0), 6.0)
    pin = jelly("pin", (0.6, 0.85, 1.0), transmission=0.2)
    parts = [box("chip", (2.2, 2.2, 0.4), bevel=0.18, segments=10, mat=body)]
    parts.append(box("core", (0.9, 0.9, 0.12), loc=(0, 0, 0.24), bevel=0.06, segments=6, mat=core))
    for k in range(5):
        off = -0.8 + k * 0.4
        for loc, size in (((off, 1.35, 0), (0.16, 0.5, 0.12)), ((off, -1.35, 0), (0.16, 0.5, 0.12)), ((1.35, off, 0), (0.5, 0.16, 0.12)), ((-1.35, off, 0), (0.5, 0.16, 0.12))):
            parts.append(box("pin", size, loc=loc, bevel=0.05, segments=4, mat=pin))
    root = parent_all(parts, "chip")
    root.rotation_euler = (math.radians(50), 0, math.radians(22))
    studio((0.45, 0.85, 1.0))
    camera(10.5, lens=70, height=0.45)
    return (1000, 1000)


def obj_appicon():
    body = jelly("icon", (1.0, 0.3, 0.06), glow=0.0, rough=0.14, transmission=0.12)
    glow = emissive("bars", (1.0, 0.97, 0.92), 3.5)
    parts = [box("icon", (2.6, 2.6, 0.9), bevel=0.62, segments=14, mat=body)]
    for i, h in enumerate([0.35, 0.7, 1.15, 0.8, 1.45, 0.95, 0.55, 0.3]):
        x = -0.98 + i * 0.28
        rodobj = rod(f"b{i}", 0.075, h, loc=(x, 0, 0.47), mat=glow)
        rodobj.rotation_euler = (math.pi / 2, 0, 0)
        parts.append(rodobj)
    root = parent_all(parts, "appicon")
    root.rotation_euler = (math.radians(44), 0, math.radians(-20))
    studio((1.0, 0.6, 0.35))
    camera(9.2, lens=70, height=0.5)
    return (1000, 1000)


OBJECTS = {
    "appicon": obj_appicon,
    "capsule": obj_capsule,
    "capsule_milk": obj_capsule_milk,
    "keycap": obj_keycap,
    "textcard": obj_textcard,
    "lock": obj_lock,
    "stack": obj_stack,
    "aa": obj_aa,
    "chip": obj_chip,
}

for name, build in OBJECTS.items():
    if ONLY and name not in ONLY:
        continue
    scene = reset_scene()
    width, height = build()
    scale = 50 if FAST else 100
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = scale
    scene.render.filepath = f"{OUT}/{name}.png"
    bpy.ops.render.render(write_still=True)
    print(f"rendered {name}")
