#!/usr/bin/env python3
"""
Shared Blender helpers for the checked-in asset scripts.

Not runnable on its own — import it from a build script:

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from blenderprops import *

WHY THIS FILE EXISTS SEPARATELY

`Tools/multimeter.py` grew the same eight helpers first and is left alone
on purpose: it calls `main()` at module scope, so importing it would
rebuild the meter as a side effect of asking for a `box`. Rather than
restructure a script that works, the helpers live here and new scripts
import them.

AXES. Blender is Z-up; RealityKit is Y-up, and `export` below converts
with forward −Z and up +Y. The mapping that falls out of that is worth
writing down, because guessing it costs a render every time:

    Blender (x, y, z)  ->  RealityKit (x, z, -y)

So a part that must lie along RealityKit's X is built along Blender's X;
one that must stand up RealityKit's Y is built up Blender's Z; and a disc
or a ring that must FACE the reader — axis along RealityKit's Z — is
built with its axis along Blender's Y, which means rotating a default
+Z-axis primitive by 90 degrees about X.

SCALE. Metres throughout, and real ones. An emblem has no true size, but
a bar magnet does, and a script whose numbers are arguable is the whole
reason these assets are scripts instead of .blend files.
"""

import bpy
import math
import os


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, colour, roughness=0.5, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emission, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def shade(obj, mat, smooth=True):
    obj.data.materials.append(mat)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def bevel(obj, width, segments=3, angle=40):
    """Rounded edges. A machined part has no sharp corners, and at these
    sizes the highlight running along a bevel is most of what makes a
    shape read as a solid object rather than as a box."""
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(angle)
    bpy.ops.object.modifier_apply(modifier="bevel")
    return obj


def box(name, size, location=(0, 0, 0)):
    """`size` is the FULL width, depth and height in metres — a unit cube
    from `primitive_cube_add(size=1)` already spans 1 m, so the scale IS
    the dimension."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    # Scale only. transform_apply's location and rotation default to True,
    # and baking the location put the origin at the world's: a rotation
    # set afterwards swung the box about (0, 0, 0) instead of its own
    # centre, which is how the multimeter's detents left its case.
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def cylinder(name, radius, depth, location=(0, 0, 0), rotation=(0, 0, 0),
             vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=location,
        rotation=rotation, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def cone(name, radius1, radius2, depth, location=(0, 0, 0), rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(
        radius1=radius1, radius2=radius2, depth=depth,
        location=location, rotation=rotation, vertices=32)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def band(name, outer, inner, depth, location=(0, 0, 0), rotation=(0, 0, 0),
         vertices=64):
    """A machined ring: an annulus with a RECTANGULAR cross-section.

    Not a torus. A gimbal ring is milled from plate, so its section is a
    rectangle with a chamfer, and a round tube in its place reads as wire
    — which is exactly the difference between an instrument and a
    diagram. Cut as a boolean rather than spun, because the difference of
    two cylinders is one line and always closes.

    Built with its axis along +Z and rotated afterwards, so a ring that
    must face the reader passes `rotation=(pi/2, 0, 0)` — see the axis
    note at the top of this file.
    """
    outer_obj = cylinder(name, outer, depth, vertices=vertices)
    hole = cylinder(name + "Hole", inner, depth * 2.2, vertices=vertices)

    bpy.context.view_layer.objects.active = outer_obj
    modifier = outer_obj.modifiers.new("cut", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.object = hole
    modifier.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(hole, do_unlink=True)
    # The boolean leaves an empty material slot every face points at, so
    # shade()'s material landed in slot 1 and the USD exporter wrote the
    # ring outside every material subset: it drew in the mesh's FIRST
    # material (the inductor's copper turns came out champagne). Clear it.
    outer_obj.data.materials.clear()

    outer_obj.rotation_euler = rotation
    outer_obj.location = location
    bpy.ops.object.select_all(action="DESELECT")
    outer_obj.select_set(True)
    bpy.context.view_layer.objects.active = outer_obj
    bpy.ops.object.transform_apply(rotation=True, location=True)
    return outer_obj


def letter(name, character, size, extrude, location=(0, 0, 0),
           rotation=(0, 0, 0)):
    """A single raised character, as geometry.

    Geometry rather than a texture because these assets carry no image
    maps at all, and because a raised letter catches the key light as the
    part turns — which is the only thing that tells you it is moulded
    into the object rather than printed on it.
    """
    bpy.ops.object.text_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.body = character
    obj.data.size = size
    obj.data.extrude = extrude
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    return bpy.context.active_object


def tube(name, points, radius, mat, resolution=8):
    """A round tube along a polyline, ends capped: a frame member, a lead,
    a stroke of an inlaid schematic symbol."""
    data = bpy.data.curves.new(name, type="CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = resolution
    data.use_fill_caps = True
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return shade(bpy.context.active_object, mat)


def join(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def export(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=path,
        selected_objects_only=True,
        export_materials=True,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
    )
    print("wrote", path)
