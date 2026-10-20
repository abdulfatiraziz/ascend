"""Build Ascend's first avatar study from Blender Studio's CC0 base mesh.

Run from the project root:
  blender --background --factory-startup --disable-autoexec --python scripts/build_avatar.py
"""
import bpy
import bmesh
import json
import math
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/avatar'
SOURCE = OUT / 'source/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'renders').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != 'Collection':
        bpy.data.collections.remove(collection)

with bpy.data.libraries.load(str(SOURCE), link=False) as (src, dst):
    dst.objects = ['GEO-body_male_realistic']
    dst.texts = ['README']
body = dst.objects[0]
body.name = 'Ascend | tailored body'
bpy.context.scene.collection.objects.link(body)
body.location = (0, 0, 0)
body.rotation_euler = (0, 0, 0)
body.scale = (1, 1, 1)
body.modifiers.clear()
body.data = body.data.copy()
body.data.name = 'CC0 realistic male | Ascend adaptation'

# Remove the source face entirely; keep the sculpted body and hands.
bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
    plane_co=(0,0,1.428), plane_no=(0,0,1), dist=.000001, clear_outer=True)
neck_edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > 1.35 for v in e.verts)]
if neck_edges:
    bmesh.ops.holes_fill(bm, edges=neck_edges, sides=0)
bm.to_mesh(body.data)
bm.free()

# A relaxed A-pose: lower the forearms slightly, preserving the base topology.
for vertex in body.data.vertices:
    p = vertex.co
    s = 1 if p.x > 0 else -1
    blend = max(0.0, min(1.0, (abs(p.x) - .145) / .10))
    is_arm = p.z > .66 and (p.z > 1.05 or abs(p.x) > .255)
    if is_arm and blend:
        shoulder = Vector((s * .178, .015, 1.365))
        angle = math.radians(s * 12) * blend
        p[:] = shoulder + Matrix.Rotation(angle, 3, 'Y') @ (p - shoulder)
    # Smooth front pelvic detail into a continuous suit surface.
    if .70 < p.z < 1.03 and abs(p.x) < .145 and p.y < -.055:
        weight = max(0, 1 - abs(p.x) / .145) * max(0, 1 - abs(p.z - .88) / .18)
        p.y = p.y * (1 - weight) + max(p.y, -.078) * weight

for poly in body.data.polygons:
    poly.use_smooth = True
sub = body.modifiers.new('Smooth tailored silhouette', 'SUBSURF')
sub.levels = 1
sub.render_levels = 2

def material(name, color, metal=.65, roughness=.3, emission=None, strength=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Coat Weight'].default_value = .4
    bsdf.inputs['Coat Roughness'].default_value = .22
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1)
        bsdf.inputs['Emission Strength'].default_value = strength
    return mat

graphite = material('Graphite / flexible suit joints', (.023, .024, .031), .35, .37)
violet = material('Violet / illuminated piping', (.32, .15, .7), .2, .23, (.36, .15, 1), 4)
dim_violet = material('Violet / foundation piping', (.19, .13, .28), .5, .32, (.24, .13, .5), .22)
floor_mat = material('Obsidian stage', (.015, .016, .022), .6, .29)
white_text = material('Typography / pearl', (.75, .74, .82), .05, .7, (.75, .74, .82), .7)
muted_text = material('Typography / muted', (.25, .24, .32), 0, .8, (.25, .24, .32), .5)

def curve(name, points, radius, mat, cyclic=False):
    data = bpy.data.curves.new(name, 'CURVE')
    data.dimensions = '3D'
    data.resolution_u = 16
    data.bevel_depth = radius
    data.bevel_resolution = 3
    spline = data.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = point.handle_right_type = 'AUTO'
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj

def ring(name, radius, z, mat, tube=.002, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=96, minor_segments=8,
        location=(0, 0, z), major_radius=radius, minor_radius=tube)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj

# The neutral face is a custom continuous shell, with no eyes, nose or mouth.
bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, location=(0, -.015, 1.559))
head = bpy.context.object
head.name = 'Ascend | faceless shell'
for v in head.data.vertices:
    z = v.co.z
    taper = 1 if z > -.15 else 1 + (z + .15) * .22
    v.co.x *= .083 * taper
    v.co.y *= .098
    # A slightly flatter, uninterrupted front surface.
    if v.co.y < -.05:
        v.co.y = -.05 + (v.co.y + .05) * .74
    v.co.z *= .13
for p in head.data.polygons:
    p.use_smooth = True

collar = ring('Ascend | collar', .051, 1.432, graphite, .009, (1, .92, 1))
collar_light = ring('Ascend | collar light', .054, 1.442, dim_violet, .0016, (1, .92, 1))
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=.057, depth=.032, location=(0,0,1.43))
neck_seal = bpy.context.object
neck_seal.name = 'Ascend | neck seal'
neck_seal.scale.y = .95
neck_seal.data.materials.append(graphite)
for p in neck_seal.data.polygons:
    p.use_smooth = True

# Raised seams follow the artist mesh, rather than intersecting the silhouette.
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
evaluated = body.evaluated_get(depsgraph)
evaluated_vertices = [v.co.copy() for v in evaluated.data.vertices]
def front(x, z, offset=.0035):
    hit, loc, normal, face = evaluated.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
    return (x, loc.y - offset, z) if hit else (x, -.11, z)

seams = []
def leg_front(sign, z):
    band = [v.x for v in evaluated_vertices if abs(v.z-z) < .012 and .025 < sign*v.x < .23]
    x = sum(band)/len(band) if band else sign*.09
    return front(x, z)

for s in [-1, 1]:
    seams.append(curve('Ascend | chest inlay', [front(s*x,z) for x,z in
        [(.05,1.365),(.115,1.335),(.16,1.29),(.10,1.21),(.075,1.13)]], .0018, dim_violet))
    seams.append(curve('Ascend | shin inlay', [leg_front(s,z) for z in
        [.60,.49,.37,.24]], .0014, dim_violet))
    # Dark inset panels communicate a tailored suit, not bare metallic skin.
    seams.append(curve('Ascend | shoulder binding', [front(s*x,z,.0045) for x,z in
        [(.06,1.385),(.13,1.37),(.19,1.33),(.205,1.26)]], .004, graphite))

# Small vertical crest, away from the face.
crest = curve('Ascend | sternum light', [front(0,1.305,.006),front(0,1.26,.006)], .002, dim_violet)
seams.append(crest)
parts = [body, head, collar, collar_light, neck_seal] + seams

# Keep a continuous suit finish; a face-assigned pelvic band reads as a jagged
# material edge after subdivision. The separate collar and bindings supply trim.
body.data.materials.clear()
body.data.materials.append(graphite)
body.data.materials.append(graphite)
for poly in body.data.polygons:
    co = sum((body.data.vertices[i].co for i in poly.vertices), Vector()) / len(poly.vertices)
    poly.material_index = 0

variants = [
    ('titanium', '01 / TITANIUM', (.34,.36,.42), .77, .29, False),
    ('obsidian', '02 / OBSIDIAN', (.037,.04,.054), .66, .27, False),
    ('ascendant', '03 / ASCENDANT', (.64,.62,.72), .72, .24, True),
]
variant_collections = []
centers = [-.73, 0, .73]
for index, (slug, label, color, metal, rough, lit) in enumerate(variants):
    col = bpy.data.collections.new(f'AVATAR / {slug.upper()}')
    bpy.context.scene.collection.children.link(col)
    variant_collections.append(col)
    finish = material(f'{slug.title()} / satin alloy', color, metal, rough)
    helmet_finish = material(f'{slug.title()} / polished faceless shell', color, min(1,metal+.12), rough*.7)
    for original in parts:
        obj = original.copy()
        obj.data = original.data.copy()
        obj.name = f'{slug} / {original.name.split(" | ")[-1]}'
        col.objects.link(obj)
        if original == body:
            obj.data.materials[0] = finish
        elif original == head:
            obj.data.materials.clear()
            obj.data.materials.append(helmet_finish)
        elif original == collar_light or (original in seams and original.data.materials[0] == dim_violet):
            obj.data.materials.clear()
            obj.data.materials.append(violet if lit else dim_violet)
        obj.location.x += centers[index]
        obj['source'] = 'Blender Studio Human Base Meshes v1.4.1, CC0; customized for Ascend'
        obj['variant'] = slug

for obj in parts:
    bpy.data.objects.remove(obj, do_unlink=True)

stage_collection = bpy.data.collections.new('STUDIO / render only')
bpy.context.scene.collection.children.link(stage_collection)
def to_stage(obj):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    stage_collection.objects.link(obj)
    return obj

for i, x in enumerate(centers):
    bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=.32, depth=.045, location=(x,0,-.025))
    pedestal = to_stage(bpy.context.object)
    pedestal.name = 'Display plinth'
    pedestal.data.materials.append(floor_mat)
    bevel = pedestal.modifiers.new('Soft machined edge', 'BEVEL')
    bevel.width = .008
    bevel.segments = 3
    obj = ring('Display / violet ring', .325, -.004, violet if i==2 else dim_violet, .0015)
    obj.location.x = x
    to_stage(obj)

bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.055))
floor = to_stage(bpy.context.object)
floor.name = 'Infinite studio floor'
floor.data.materials.append(floor_mat)

def aim(obj, point):
    obj.rotation_euler = (Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()

def area(name, loc, energy, color, size, size_y=None):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.color = color
    if size_y:
        data.shape = 'RECTANGLE'
        data.size = size
        data.size_y = size_y
    else:
        data.shape = 'DISK'
        data.size = size
    obj = bpy.data.objects.new(name,data)
    stage_collection.objects.link(obj)
    obj.location = loc
    aim(obj,(0,0,.95))
    return obj

area('Key / vertical softbox',(-2,-2.4,2.8),520,(.88,.91,1),2,3.5)
area('Rim / violet',(1.9,1.2,2),600,(.38,.18,1),1.4,2.5)
area('Fill / broad',(2,-3,1.7),180,(.8,.83,1),2.2,2)
area('Top / pearl',(0,.2,4),360,(1,1,1),2.5)

scene = bpy.context.scene
scene.world.color = (.025,.025,.035)
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.055,.05,.075,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .22
camera_data = bpy.data.cameras.new('Camera / material study')
camera = bpy.data.objects.new('Camera / material study',camera_data)
stage_collection.objects.link(camera)
camera.location = (1.6,-7,2.5)
aim(camera,(0,0,.91))
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 3.35
scene.camera = camera

def text_obj(name, text, location, size, mat, align='CENTER'):
    data = bpy.data.curves.new(name,'FONT')
    data.body = text
    data.size = size
    data.align_x = align
    data.space_character = 1.2
    obj = bpy.data.objects.new(name,data)
    stage_collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = camera.rotation_euler
    data.materials.append(mat)
    return obj

# Camera-facing type placed using camera-local coordinates for crisp alignment.
cam_q = camera.rotation_euler.to_quaternion()
center = Vector((0,0,.91))
def screen_pos(x,y):
    return center + cam_q @ Vector((x,y,1.0))
text_obj('Title','A S C E N D', screen_pos(0,.93), .092, white_text)
text_obj('Subtitle','AVATAR STUDY  /  BLENDER STUDIO CC0 BASE  /  CUSTOM FACELESS SHELL',screen_pos(0,.83),.025,muted_text)
for i, (_,label,*_) in enumerate(variants):
    text_obj('Finish label', label, screen_pos((i-1)*.71,-.91), .039, white_text)
text_obj('Footer','SAME BODY.  THREE COSMETIC STATES.  PROGRESS CHANGES THE FINISH.',screen_pos(0,-1.015),.025,muted_text)

scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = 1500
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.render.filepath = str(OUT / 'renders/ascend-avatar-study.png')

# Export the avatar only: plinth, lights and typography stay out of runtime assets.
stats = []
for i, col in enumerate(variant_collections):
    bpy.ops.object.select_all(action='DESELECT')
    objs = list(col.objects)
    for obj in objs:
        obj.select_set(True)
        obj.location.x -= centers[i]
        if obj.type == 'MESH':
            for modifier in obj.modifiers:
                if modifier.type == 'SUBSURF':
                    modifier.render_levels = 1
    bpy.context.view_layer.objects.active = objs[0]
    slug = variants[i][0]
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'ascend-{slug}.glb'), export_format='GLB',
        use_selection=True, export_apply=True, export_animations=False, export_cameras=False,
        export_lights=False, export_extras=True)
    stats.append({'file': f'ascend-{slug}.glb','bytes':(OUT/f'ascend-{slug}.glb').stat().st_size})
    for obj in objs:
        obj.location.x += centers[i]
        if obj.type == 'MESH':
            for modifier in obj.modifiers:
                if modifier.type == 'SUBSURF':
                    modifier.render_levels = 2

bpy.ops.object.select_all(action='DESELECT')
for obj in variant_collections[0].objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(o for o in variant_collections[0].objects if 'tailored body' in o.name)
readme = bpy.data.texts.new('ASCEND / provenance')
readme.write('Ascend avatar study\nSource: Blender Studio Human Base Meshes v1.4.1\n'
             'Source mesh: GEO-body_male_realistic\nSource license: CC0, per bundled README and official download listing.\n'
             'Customizations: source head removed; new faceless shell; relaxed arms; pelvic suit smoothing; material panels; light inlays.\n'
             'No source rigs, animation or third-party text datablocks included.\n'
             'Runtime files contain only the avatar. This study is not rigged.\n')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'ascend-avatar-study.blend'))
(OUT / 'build-stats.json').write_text(json.dumps(stats, indent=2))
print('ASCEND_EXPORTS',json.dumps(stats),flush=True)
bpy.ops.render.render(write_still=True)
print('ASCEND_RENDER_COMPLETE',scene.render.filepath,flush=True)
