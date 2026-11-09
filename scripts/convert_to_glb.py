# Converts a 3D model to .glb with Blender (without opening the window).
# Uso:  blender -b --python scripts/convert_to_glb.py -- ingresso uscita.glb
# Object names and hierarchy (doors, hood, wheels...) are kept: they are needed by the car setup.
import os
import sys

import bpy

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
lighten = "--lighten" in argv
argv = [a for a in argv if a != "--lighten"]
if len(argv) != 2:
    print("uso: blender -b --python convert_to_glb.py -- ingresso uscita.glb [--lighten]")
    sys.exit(2)
src, dst = argv
ext = os.path.splitext(src)[1].lower()

bpy.ops.wm.read_factory_settings(use_empty=True)

try:
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext == ".obj":
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=src)
        else:
            bpy.ops.import_scene.obj(filepath=src)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=src)
    elif ext in (".gltf", ".glb"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=src)
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=src)
    else:
        print("unsupported format:", ext)
        sys.exit(3)
except Exception as e:
    print("error opening the file:", e)
    sys.exit(4)

if not [o for o in bpy.data.objects if o.type == "MESH"]:
    print("the file does not contain any 3D shape")
    sys.exit(5)

if lighten:
    # Lightening: fewer triangles (Decimate) and smaller textures. Names and hierarchy stay: the car setup does not change.
    TARGET_TRIS = 400000          # total triangles to aim for
    MAX_TEX = 1536                # maximum side of the textures
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    def tris(o):
        return sum(max(1, len(p.vertices) - 2) for p in o.data.polygons)
    total = sum(tris(o) for o in meshes)
    print("triangles before:", total)
    if total > TARGET_TRIS:
        ratio = TARGET_TRIS / total
        done = set()
        for o in meshes:
            n = tris(o)
            if n < 3000:
                continue                       # small parts stay as they are
            if o.data.users > 1:
                o.data = o.data.copy()         # a shared mesh must be made unique before modifying it
            if o.data.name in done:
                continue
            done.add(o.data.name)
            m = o.modifiers.new("Decimate", "DECIMATE")
            m.decimate_type = "COLLAPSE"
            m.ratio = max(0.05, min(1.0, ratio))
            bpy.context.view_layer.objects.active = o
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e:
                print("mesh not lightened:", o.name, e)
        print("triangles after:", sum(tris(o) for o in bpy.data.objects if o.type == "MESH"))
    for img in bpy.data.images:
        try:
            w, h = img.size
            if max(w, h) > MAX_TEX:
                k = MAX_TEX / max(w, h)
                img.scale(max(1, int(w * k)), max(1, int(h * k)))
        except Exception:
            pass

try:
    # Blender is Z-up, glTF is Y-up: the exporter converts by itself (export_yup)
    opts = dict(filepath=dst, export_format="GLB", export_yup=True, export_apply=False)
    if lighten:
        opts.update(export_image_format="JPEG", export_jpeg_quality=80)      # texture in JPEG: file molto piu' piccolo
    bpy.ops.export_scene.gltf(**opts)
except Exception as e:
    print("error during export:", e)
    sys.exit(6)
print("OK", dst)
