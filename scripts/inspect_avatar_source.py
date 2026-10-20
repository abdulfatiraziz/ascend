import bpy
from mathutils import Vector

path = 'assets/avatar/source/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend'
with bpy.data.libraries.load(path, link=False) as (src, dst):
    dst.objects = ['GEO-body_male_realistic', 'GEO-body_male_stylized']
    dst.texts = ['README', 'License']
for obj in dst.objects:
    bpy.context.scene.collection.objects.link(obj)
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    print('SOURCE', obj.name, 'vertices', len(pts), 'bounds',
          [tuple(round(min(v[i] for v in pts), 4) for i in range(3)),
           tuple(round(max(v[i] for v in pts), 4) for i in range(3))],
          'modifiers', [(m.name, m.type) for m in obj.modifiers],
          'groups', [g.name for g in obj.vertex_groups], 'parent', obj.parent)
for text in dst.texts:
    print('TEXT', text.name, text.as_string()[:7000])
