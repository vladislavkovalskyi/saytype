# Renders saytype's 3D objects as clear glass: a thick transparent shell, a frosted core
# inside and a glowing symbol, lit by coloured rim lights.
#
#   blender -b -P design/3d/glass.py -- <out_dir> [object ...] [--fast]
#   python3 design/3d/export_app.py <out_dir> App/Resources/Assets.xcassets --glass
#
# Scene, light and mesh helpers come from render.py, which drew the earlier jelly style.

import math
import os

_render = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render.py")
with open(_render) as f:
    exec(f.read().split("# ---------------------------------------------------------------- objects")[0])


def crystal(name, tint, absorb, density=0.5, rough=0.015, film=620.0, dispersion=0.5):
    """Clear glass with a thin-film sheen on the edges and colour in its depth."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    set_input(b, "Base Color", (*tint, 1))
    set_input(b, "Roughness", rough)
    set_input(b, "IOR", 1.5)
    set_input(b, ["Transmission Weight", "Transmission"], 1.0)
    set_input(b, ["Coat Weight", "Clearcoat"], 1.0)
    set_input(b, ["Coat Roughness", "Clearcoat Roughness"], 0.0)
    set_input(b, ["Specular IOR Level", "Specular"], 0.75)
    set_input(b, "Thin Film Thickness", film)
    set_input(b, "Thin Film IOR", 1.38)
    set_input(b, "Dispersion", dispersion)
    vol = nt.nodes.new("ShaderNodeVolumeAbsorption")
    vol.inputs["Color"].default_value = (*absorb, 1)
    vol.inputs["Density"].default_value = density
    nt.links.new(vol.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
    return m


def frosted(name, tint, rough=0.38, glow=0.0):
    """Matte glass for the core behind the symbol."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    set_input(b, "Base Color", (*tint, 1))
    set_input(b, "Roughness", rough)
    set_input(b, "IOR", 1.45)
    set_input(b, ["Transmission Weight", "Transmission"], 1.0)
    set_input(b, ["Coat Weight", "Clearcoat"], 0.6)
    set_input(b, ["Coat Roughness", "Clearcoat Roughness"], 0.05)
    if glow:
        set_input(b, ["Emission Color", "Emission"], (*tint, 1))
        set_input(b, "Emission Strength", glow)
    return m


def glass_world(top, bottom):
    w = bpy.data.worlds.new("glass")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].position = 0.8
    ramp.color_ramp.elements[1].color = (*top, 1)
    bg.inputs["Strength"].default_value = 1.0
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def glass_studio(accent, complement):
    glass_world((1.0, 0.98, 0.96), tuple(c * 0.55 for c in accent))
    area_light("key", (-5, -6, 7), 1200, 6, (1.0, 0.98, 0.95))
    # A long thin softbox draws the crisp highlight streak across the glass.
    strip = area_light("strip", (-2.5, -5.5, 4.5), 900, 1, (1, 1, 1))
    strip.data.shape = "RECTANGLE"
    strip.data.size = 9
    strip.data.size_y = 0.35
    area_light("rim_a", (6, 5, 3), 3600, 3, accent)
    area_light("rim_b", (-6, 5, 2), 3000, 3, complement)
    area_light("top", (0, 3, 8), 900, 5, (1.0, 1.0, 1.0))
    area_light("under", (0, -2, -6), 500, 7, accent)


def glass_scene(scene):
    scene.cycles.samples = 96 if FAST else 512
    scene.cycles.transmission_bounces = 24
    scene.cycles.max_bounces = 24
    scene.cycles.caustics_refractive = True
    scene.cycles.blur_glossy = 0.4
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
    scene.view_settings.exposure = 0.15


def sphere(name, radius, loc, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.materials.append(mat)
    return obj


# ---------------------------------------------------------------- objects

def obj_keycap():
    shell = crystal("shell", (0.9, 0.95, 1.0), (0.25, 0.55, 1.0), density=0.45)
    core = frosted("core", (0.25, 0.5, 1.0), glow=0.6)
    legend = emissive("legend", (0.82, 0.93, 1.0), 20.0)
    parts = [box("key", (2.4, 2.4, 1.0), bevel=0.42, segments=14, mat=shell)]
    parts.append(box("core", (1.55, 1.55, 0.3), loc=(0, 0, -0.18), bevel=0.14, segments=10, mat=core))
    parts.append(text_mesh("fn", 0.9, 0.05, (0.3, 0.26, 0.2), legend))
    root = parent_all(parts, "keycap")
    root.rotation_euler = (math.radians(38), 0, math.radians(-24))
    glass_studio((0.35, 0.6, 1.0), (1.0, 0.55, 0.85))
    camera(8.6, lens=70, height=0.5)
    return (1000, 1000)


def obj_textcard():
    # Slightly rough glass: the side edges would otherwise mirror every line.
    slab = crystal("slab", (0.9, 1.0, 0.97), (0.1, 0.8, 0.65), density=1.1, rough=0.06, dispersion=0.2)
    back = frosted("back", (0.25, 0.95, 0.8), rough=0.45, glow=0.8)
    line = emissive("line", (1, 1, 1), 15.0)
    code = emissive("code", (0.5, 1.0, 0.95), 20.0)
    parts = [box("card", (3.0, 2.2, 0.56), bevel=0.24, segments=16, mat=slab)]
    parts.append(box("back", (2.6, 1.8, 0.08), loc=(0, 0, -0.3), bevel=0.04, segments=6, mat=back))
    for i, (w, m) in enumerate([(2.1, line), (1.3, code), (1.8, line), (1.0, line)]):
        y = 0.62 - i * 0.42
        parts.append(capsule_mesh(f"l{i}", 0.07, w, loc=(-1.1 + w / 2, y, 0.02), mat=m))
    root = parent_all(parts, "textcard")
    root.rotation_euler = (math.radians(48), 0, math.radians(20))
    glass_studio((0.3, 1.0, 0.8), (0.6, 0.7, 1.0))
    camera(10.5, lens=70, height=0.45)
    return (1000, 1000)


def obj_appicon():
    shell = crystal("shell", (1.0, 0.9, 0.8), (1.0, 0.42, 0.1), density=1.5)
    core = frosted("core", (1.0, 0.42, 0.1), rough=0.4, glow=0.8)
    bars = emissive("bars", (1.0, 0.96, 0.9), 16.0)
    parts = [box("icon", (2.6, 2.6, 0.9), bevel=0.62, segments=14, mat=shell)]
    parts.append(box("core", (2.0, 2.0, 0.12), loc=(0, 0, -0.3), bevel=0.3, segments=10, mat=core))
    for i, h in enumerate([0.3, 0.6, 1.0, 0.7, 1.25, 0.85, 0.5, 0.28]):
        r = rod(f"b{i}", 0.055, h, loc=(-0.84 + i * 0.24, 0, 0.05), mat=bars)
        r.rotation_euler = (math.pi / 2, 0, 0)
        parts.append(r)
    root = parent_all(parts, "appicon")
    root.rotation_euler = (math.radians(30), 0, math.radians(-16))
    glass_studio((1.0, 0.55, 0.25), (1.0, 0.35, 0.6))
    camera(9.2, lens=70, height=0.5)
    return (1000, 1000)


def obj_capsule():
    shell = crystal("shell", (1.0, 0.98, 0.95), (1.0, 0.8, 0.62), density=0.35)
    glow = emissive("glow", (1.0, 0.9, 0.74), 18.0)
    shell_obj = tube("shell", 1.05, 4.6, mat=shell)
    solid = shell_obj.modifiers.new("wall", "SOLIDIFY")
    solid.thickness = 0.12
    solid.offset = -1
    parts = [shell_obj]
    core = frosted("core", (1.0, 0.62, 0.35), rough=0.5, glow=0.35)
    inner = tube("core", 0.7, 4.0, mat=core)
    parts.append(inner)
    heights = bar_heights(25, 3)
    for i, h in enumerate(heights):
        x = -2.1 + i * (4.2 / (len(heights) - 1))
        parts.append(rod(f"bar{i}", 0.045, 1.25 * h, loc=(x, -0.78, 0), mat=glow))
    light = bpy.data.lights.new("inner", "POINT")
    light.energy = 90
    light.color = (1.0, 0.72, 0.45)
    light.shadow_soft_size = 2.0
    lo = bpy.data.objects.new("inner", light)
    bpy.context.collection.objects.link(lo)
    parts.append(lo)
    root = parent_all(parts, "capsule")
    root.rotation_euler = (math.radians(14), math.radians(-6), math.radians(16))
    glass_studio((1.0, 0.6, 0.35), (1.0, 0.45, 0.65))
    camera(16.5, lens=70, height=0.26)
    return (1600, 1000)


def smooth_text(body, size, extrude, loc, mat):
    """Text as a smooth-shaded mesh: glass shows every facet of the raw curve."""
    obj = text_mesh(body, size, extrude, loc, mat)
    obj.data.resolution_u = 24
    obj.data.bevel_resolution = 10
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return obj


def obj_aa():
    letters = crystal("letters", (1.0, 0.9, 0.95), (1.0, 0.2, 0.55), density=1.4, rough=0.03, dispersion=0.6)
    neon = frosted("neon", (1.0, 0.4, 0.75), rough=0.3, glow=4.0)
    outer = smooth_text("Аа", 2.6, 0.45, (0, 0, 0), letters)
    # A thin slice of the same outline in the middle of the glass glows like a neon core.
    inner = smooth_text("Аа", 2.6, 0.03, (0, 0, 0), neon)
    for t in (outer, inner):
        t.rotation_euler = (math.radians(90), 0, 0)
    root = parent_all([outer, inner], "aa")
    root.rotation_euler = (math.radians(6), 0, math.radians(-14))
    glass_studio((1.0, 0.35, 0.7), (0.6, 0.5, 1.0))
    camera(11, lens=70, height=0.22)
    return (1000, 1000)


def obj_stack():
    parts = []
    tints = [(0.35, 0.18, 0.95), (0.62, 0.22, 0.95), (0.95, 0.3, 0.8)]
    for i, tint in enumerate(tints):
        m = crystal(f"card{i}", (0.95, 0.92, 1.0), tint, density=1.2, rough=0.04, dispersion=0.2)
        parts.append(box(f"c{i}", (2.8, 2.0, 0.26), loc=(i * 0.18, i * 0.18, i * 0.5), bevel=0.12, segments=10, mat=m))
    core = frosted("core", (0.9, 0.45, 1.0), rough=0.45, glow=0.7)
    parts.append(box("core", (2.3, 1.5, 0.05), loc=(0.36, 0.36, 0.9), bevel=0.02, segments=4, mat=core))
    line = emissive("line", (1, 0.95, 1), 14.0)
    for j, w in enumerate([1.8, 1.2]):
        parts.append(capsule_mesh(f"l{j}", 0.07, w, loc=(0.36 - 1.0 + w / 2, 0.36 + 0.35 - j * 0.4, 1.06), mat=line))
    root = parent_all(parts, "stack")
    root.rotation_euler = (math.radians(50), 0, math.radians(24))
    glass_studio((0.7, 0.45, 1.0), (1.0, 0.5, 0.8))
    camera(11, lens=70, height=0.45, target=(0.2, 0.2, 0.4))
    return (1000, 1000)


def obj_chip():
    body = crystal("chip", (0.9, 0.97, 1.0), (0.1, 0.6, 1.0), density=1.0)
    core = frosted("core", (0.08, 0.4, 0.95), rough=0.35, glow=0.5)
    die = emissive("die", (0.45, 0.9, 1.0), 14.0)
    pin = crystal("pin", (0.9, 0.97, 1.0), (0.2, 0.7, 1.0), density=0.8, rough=0.05, dispersion=0.2)
    parts = [box("chip", (2.2, 2.2, 0.5), bevel=0.2, segments=12, mat=body)]
    parts.append(box("core", (1.2, 1.2, 0.16), loc=(0, 0, 0.0), bevel=0.08, segments=6, mat=core))
    parts.append(box("die", (0.5, 0.5, 0.06), loc=(0, 0, 0.1), bevel=0.04, segments=4, mat=die))
    for k in range(5):
        off = -0.8 + k * 0.4
        for loc, size in (((off, 1.35, 0), (0.16, 0.5, 0.12)), ((off, -1.35, 0), (0.16, 0.5, 0.12)), ((1.35, off, 0), (0.5, 0.16, 0.12)), ((-1.35, off, 0), (0.5, 0.16, 0.12))):
            parts.append(box("pin", size, loc=loc, bevel=0.05, segments=4, mat=pin))
    root = parent_all(parts, "chip")
    root.rotation_euler = (math.radians(50), 0, math.radians(22))
    glass_studio((0.3, 0.8, 1.0), (0.6, 0.5, 1.0))
    camera(10.5, lens=70, height=0.45)
    return (1000, 1000)


def obj_lock():
    body = crystal("lock", (0.92, 1.0, 0.94), (0.15, 0.85, 0.35), density=0.9)
    core = frosted("core", (0.3, 0.95, 0.5), rough=0.42, glow=0.6)
    parts = [box("body", (2.2, 1.0, 1.8), loc=(0, 0, -0.5), bevel=0.3, segments=12, mat=body)]
    parts.append(box("core", (1.5, 0.3, 1.1), loc=(0, 0.05, -0.5), bevel=0.12, segments=8, mat=core))
    # The shackle is a closed tube along a U path, so the glass has a real volume.
    path = bpy.data.curves.new("shackle", "CURVE")
    path.dimensions = "3D"
    path.bevel_depth = 0.2
    path.bevel_resolution = 10
    path.resolution_u = 32
    path.use_fill_caps = True
    spline = path.splines.new("POLY")
    points = [(-0.72, 0, -0.1), (-0.72, 0, 0.45)]
    points += [(-0.72 * math.cos(math.pi * k / 40), 0, 0.45 + 0.72 * math.sin(math.pi * k / 40)) for k in range(1, 40)]
    points += [(0.72, 0, 0.45), (0.72, 0, -0.1)]
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    shackle = bpy.data.objects.new("shackle", path)
    bpy.context.collection.objects.link(shackle)
    bpy.context.view_layer.objects.active = shackle
    shackle.select_set(True)
    bpy.ops.object.convert(target="MESH")
    shackle = bpy.context.active_object
    for poly in shackle.data.polygons:
        poly.use_smooth = True
    shackle.data.materials.append(body)
    parts.append(shackle)
    hole = emissive("hole", (0.85, 1.0, 0.9), 16.0)
    parts.append(capsule_mesh("hole", 0.12, 0.3, loc=(0, -0.34, -0.5), rot=(0, math.pi / 2, 0), mat=hole))
    root = parent_all(parts, "lock")
    root.rotation_euler = (math.radians(8), 0, math.radians(-22))
    glass_studio((0.4, 1.0, 0.6), (0.4, 0.8, 1.0))
    camera(11, lens=70, height=0.25, target=(0, 0, 0.1))
    return (1000, 1000)


def obj_mic():
    head = crystal("head", (1.0, 0.94, 0.95), (1.0, 0.3, 0.4), density=0.7)
    core = frosted("core", (1.0, 0.4, 0.5), rough=0.45, glow=0.7)
    metal = crystal("yoke", (1.0, 0.96, 0.97), (1.0, 0.6, 0.65), density=0.4, rough=0.04, dispersion=0.2)
    grille = emissive("grille", (1.0, 0.92, 0.94), 12.0)
    parts = []
    for z in (0.55, -0.35):
        parts.append(sphere("cap", 0.78, (0, 0, z), head))
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=0.78, depth=0.9, location=(0, 0, 0.1))
    mid = bpy.context.active_object
    for poly in mid.data.polygons:
        poly.use_smooth = True
    mid.data.materials.append(head)
    parts.append(mid)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=0.5, depth=1.1, location=(0, 0, 0.1))
    inner = bpy.context.active_object
    smooth(inner, 0.2, 8)
    inner.data.materials.append(core)
    parts.append(inner)
    for z in (0.5, 0.25, 0.0, -0.25):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.55, minor_radius=0.03, major_segments=96, minor_segments=12, location=(0, 0, z))
        ring = bpy.context.active_object
        ring.data.materials.append(grille)
        parts.append(ring)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.15, minor_radius=0.11, major_segments=96, minor_segments=24, location=(0, 0, -0.1), rotation=(math.pi / 2, 0, 0))
    yoke = bpy.context.active_object
    cut = box("cut", (3, 3, 1.4), loc=(0, 0, 0.6), bevel=0.0, segments=1)
    b = yoke.modifiers.new("cut", "BOOLEAN")
    b.object = cut
    b.operation = "DIFFERENCE"
    bpy.context.view_layer.objects.active = yoke
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cut)
    for poly in yoke.data.polygons:
        poly.use_smooth = True
    yoke.data.materials.append(metal)
    parts.append(yoke)
    parts.append(rod("stem", 0.11, 0.9, loc=(0, 0, -1.65), mat=metal))
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=0.85, depth=0.2, location=(0, 0, -2.12))
    base = bpy.context.active_object
    smooth(base, 0.08, 6)
    base.data.materials.append(metal)
    parts.append(base)
    root = parent_all(parts, "mic")
    root.rotation_euler = (math.radians(8), math.radians(10), math.radians(-18))
    glass_studio((1.0, 0.45, 0.5), (1.0, 0.7, 0.4))
    camera(12.5, lens=70, height=0.22, target=(0, 0, -0.6))
    return (1000, 1000)


def obj_switches():
    panel = crystal("panel", (1.0, 0.92, 0.94), (1.0, 0.25, 0.4), density=0.9)
    track_on = frosted("track_on", (1.0, 0.62, 0.22), rough=0.35, glow=1.2)
    track_off = frosted("track_off", (0.55, 0.08, 0.2), rough=0.4, glow=0.2)
    knob = emissive("knob", (1.0, 0.97, 0.95), 10.0)
    line = emissive("line", (1.0, 0.97, 0.95), 12.0)
    parts = [box("panel", (3.0, 2.4, 0.5), bevel=0.22, segments=14, mat=panel)]
    for i, (on, y) in enumerate(((True, 0.52), (False, -0.52))):
        parts.append(capsule_mesh(f"track{i}", 0.2, 1.2, loc=(0.35, y, 0.0), mat=track_on if on else track_off))
        parts.append(sphere(f"knob{i}", 0.22, (0.35 + (0.6 if on else -0.6), y, 0.05), knob))
        parts.append(capsule_mesh(f"label{i}", 0.06, 0.5, loc=(-0.95, y, 0.0), mat=line))
    root = parent_all(parts, "switches")
    root.rotation_euler = (math.radians(46), 0, math.radians(-20))
    glass_studio((1.0, 0.4, 0.45), (1.0, 0.7, 0.4))
    camera(10.5, lens=70, height=0.45)
    return (1000, 1000)


OBJECTS = {
    "keycap": obj_keycap,
    "textcard": obj_textcard,
    "appicon": obj_appicon,
    "capsule": obj_capsule,
    "aa": obj_aa,
    "stack": obj_stack,
    "chip": obj_chip,
    "lock": obj_lock,
    "mic": obj_mic,
    "switches": obj_switches,
}

for name, build in OBJECTS.items():
    if ONLY and name not in ONLY:
        continue
    scene = reset_scene()
    glass_scene(scene)
    width, height = build()
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 50 if FAST else 100
    scene.render.filepath = f"{OUT}/{name}.png"
    bpy.ops.render.render(write_still=True)
    print(f"rendered {name}")
