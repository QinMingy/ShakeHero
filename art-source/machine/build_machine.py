"""Blender background authoring. All geometry is original; no game assets are copied.
Run: blender --background --python art-source/machine/build_machine.py
Coordinates: design pixels (420 x 840), 100 px per metre. Front is Blender +Z.
"""
import bpy, json, math, random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/model/machine'
LUA = ROOT / 'scripts/Machine'
OUT.mkdir(parents=True, exist_ok=True)
LUA.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
parts = []
palette = {'shell':(.29,.30,.22), 'edge':(.47,.46,.30), 'dark':(.035,.042,.030),
           'screen':(.075,.13,.060), 'key':(.59,.54,.31), 'action':(.33,.34,.21),
           'lamp':(.90,.90,.47), 'steel':(.57,.54,.35),
           'wear_dark':(.11,.12,.075), 'wood':(.22,.195,.16),
           'wood_light':(.255,.225,.18), 'wood_dark':(.085,.075,.06),
           'paper':(.63,.51,.33), 'paper_edge':(.34,.27,.17),
           'ink':(.13,.12,.075), 'brass':(.57,.39,.16),
           'ceramic':(.31,.40,.39), 'cool_lamp':(.28,.59,.60)}
plain_materials={'screen','dark','lamp','wood','wood_light','wood_dark',
                 'paper','paper_edge','ink','brass','ceramic','cool_lamp'}
# Hand-authored procedural pixel patina, generated locally in Blender. Oxide,
# scuffs and pores live in the material instead of floating above the mesh.
rng=random.Random(420841)
tex=bpy.data.images.new('Painted metal grain',width=256,height=256)
pixels=[]
oxide_cells=[[rng.random() for _ in range(12)] for _ in range(12)]
def oxide_at(x,y):
    gx,gy=x/25.6,y/25.6
    ix,iy=math.floor(gx),math.floor(gy)
    fx,fy=gx-ix,gy-iy
    fx,fy=fx*fx*(3-2*fx),fy*fy*(3-2*fy)
    def cell(dx,dy):return oxide_cells[(iy+dy)%12][(ix+dx)%12]
    top=cell(0,0)*(1-fx)+cell(1,0)*fx
    bottom=cell(0,1)*(1-fx)+cell(1,1)*fx
    return top*(1-fy)+bottom*fy
for y in range(256):
    for x in range(256):
        n=rng.random()
        brush=math.sin(y*.27+math.sin(x*.035)*1.3)*.047
        broad=math.sin(x*.055+y*.019)*.052
        value=.79+brush+broad+rng.uniform(-.095,.095)
        if n<.042: value*=.43
        elif n>.982: value=min(1,value+.19)
        oxide=max(0,(oxide_at(x,y)-.54)*1.7)
        scratch=max(0,math.sin(y*.31+x*.022)-.966)*2.1
        value=min(1,max(.08,value+scratch))
        pixels.extend((value*(1-.14*oxide),value*(.985-.28*oxide),
                       value*(.91-.42*oxide),1))
tex.pixels.foreach_set(pixels)
tex.filepath_raw=str(OUT/'metal-patina.png');tex.file_format='PNG';tex.save()
materials = {}
for name, rgb in palette.items():
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb,1)
    mat.use_nodes = True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(*rgb,1)
    bsdf.inputs['Roughness'].default_value=.88
    if name not in plain_materials:
        image_node=mat.node_tree.nodes.new('ShaderNodeTexImage');image_node.image=tex
        image_node.interpolation='Closest'
        mix=mat.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY'
        mix.inputs[0].default_value=1;mix.inputs[1].default_value=(*rgb,1)
        mat.node_tree.links.new(image_node.outputs['Color'],mix.inputs[2])
        mat.node_tree.links.new(mix.outputs[0],bsdf.inputs['Base Color'])
    materials[name] = mat

def box(name, x,y,w,h, depth=.14, z=0, color='shell', bevel=2, module='shell'):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x-210)/100,(420-y)/100,z))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (w/100,h/100,depth)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod=obj.modifiers.new('Single stepped bevel','BEVEL'); mod.width=bevel/100; mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(materials[color])
    obj['module']=module
    parts.append(obj)
    return obj

# The tabletop is behind the cabinet even at the slanted camera angle. Its
# quiet seams and knots give the outer frame a place to sit without using any
# platform-provided art. The same geometry is exported to the runtime scene.
box('desk_underlay',210,420,970,1370,.10,-.80,'wood_dark',0,'desk')
for index, (x,width,colour) in enumerate((( -72,130,'wood'),(86,172,'wood_light'),
                                           (261,176,'wood'),(430,162,'wood_light'))):
    box('desk_plank_%d'%index,x,420,width,1360,.045,-.719,colour,0,'desk')
    box('desk_seam_%d'%index,x-width/2,420,2,1360,.004,-.694,'wood_dark',0,'deskgrain')
for i in range(46):
    grain_x=rng.uniform(-160,585)
    grain_y=rng.uniform(-260,1080)
    grain_length=rng.uniform(18,105)
    grain_width=rng.choice((.45,.7,1.1,1.5))
    tone='wood_dark' if i%3 else 'wood_light'
    box('desk_grain_%02d'%i,grain_x,grain_y,grain_width,grain_length,
        .002,-.695,tone,0,'deskgrain')

# A slipped note, worn pencil and a few tokens are deliberately outside the
# cabinet silhouette so they cannot cover score text, the board or keys.
box('desk_receipt_shadow',102,-96,116,122,.006,-.654,'wood_dark',1,'deskprops')
box('desk_receipt',99,-100,108,118,.008,-.645,'paper',1,'deskprops')
box('receipt_heading',99,-139,72,3,.002,-.639,'ink',0,'deskprops')
for i,length in enumerate((74,54,79,61,45)):
    box('receipt_line_%d'%i,78+length/2,-121+i*15,length,1.8,
        .002,-.639,'paper_edge',0,'deskprops')
box('pencil_shadow',331,871,151,8,.008,-.648,'wood_dark',1,'deskprops')
box('pencil_body',329,868,141,6,.025,-.625,'brass',1,'deskprops')
box('pencil_ink',270,868,19,2,.027,-.607,'ink',0,'deskprops')
box('pencil_tip',403,868,8,5,.012,-.609,'paper',0,'deskprops')

def desk_disc(name,x,y,r,depth,z,color,vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r/100,depth=depth,
        location=((x-210)/100,(420-y)/100,z))
    obj=bpy.context.object; obj.name=name
    obj.data.materials.append(materials[color])
    obj['module']='deskprops'; parts.append(obj)
    return obj

for index,(x,y) in enumerate(((69,851),(101,872),(77,894))):
    desk_disc('loose_token_%d'%index,x,y,13,.028,-.625,'brass')
    desk_disc('loose_token_face_%d'%index,x,y,9,.003,-.608,'wood_dark')
    box('token_mark_%d'%index,x,y,2,11,.004,-.604,'brass',0,'deskprops')
desk_disc('desk_lamp_base',357,-103,23,.065,-.622,'ceramic')
desk_disc('desk_lamp_ring',357,-103,17,.005,-.587,'brass')
desk_disc('desk_lamp_core',357,-103,8,.008,-.582,'cool_lamp')

# Pull the entire workbench behind the cabinet by another half metre. Its
# shadow then reads as a suspended machine, while desk props keep their
# original spacing on the tabletop.
for obj in parts:
    obj.location.z -= .50

box('cabinet_bottom',210,427,408,810,.48,-.25,'dark',9)
box('cabinet_shell',210,413,400,804,.30,-.08,'shell',9)
box('left_rail',22,420,15,770,.18,.06,'edge',3)
box('right_rail',398,420,15,770,.18,.06,'edge',3)
box('nameplate',144,45,216,34,.08,.11,'dark',2,'header')
for name,x in [('score',121),('target',299)]:
    box(name+'_frame',x,115,174,82,.17,.10,'edge',4,name)
    box(name+'_glass',x,115,158,66,.06,.20,'dark',2,name)
box('round_frame',210,174,350,35,.12,.11,'edge',3,'rounds')
box('round_glass',210,174,336,24,.05,.18,'dark',1,'rounds')
box('board_frame',210,434,364,480,.22,.11,'dark',7,'board')
box('board_bevel',210,432,350,464,.17,.18,'edge',5,'board')
box('board_glass',210,434,336,448,.07,.26,'screen',2,'board')
box('timer_frame',110,690,150,43,.14,.13,'edge',3,'timer')
box('timer_glass',110,690,138,32,.06,.22,'dark',2,'timer')
box('status_plate',281,690,188,38,.10,.12,'dark',2,'status')
# The duplicate round/bottle readout tray is gone. Keep a small independent
# recess for the inventory button at the right edge of the lower panel.
box('deck_plate',340,730,86,28,.09,.14,'dark',2,'deck')
for name,x,w,col in [('reroll',94,112,'key'),('shake',271,222,'action')]:
    box(name+'_socket',x,786,w+8,62,.12,.10,'dark',3,name)
    # The cap stands 12 cm proud of its fixed trim, exposing a full-depth
    # mechanical stroke from the angled camera before it sinks nearly flush.
    box(name+'_key',x,780,w,52,.26,.38,col,4,name)
    box(name+'_highlight',x,758,w-16,2,.012,.516,'edge',0,name)
for x in (28,392):
    for y in (28,813):
        box('fastener_%s_%s'%(x,y),x,y,6,6,.025,.1,'dark',1)
        box('slot_%s_%s'%(x,y),x,y,3,1,.005,.117,'steel',0)
for i in range(5):
    box('vent_%d'%i,368+i*5,46,2,19,.02,.09,'dark',0)

# Detailed surface modules keep V1's exact board rectangle and physics dimensions.
def trim(name,x,y,w,h,z,module):
    # Four separate raised rails: warm top/left highlights, almost-black inner return.
    box(name+'_top',x,y-h/2+1,w,2,.022,z,'steel',.4,module)
    box(name+'_left',x-w/2+1,y,2,h,.022,z,'steel',.4,module)
    box(name+'_bottom',x,y+h/2-1,w,2,.025,z,'wear_dark',.4,module)
    box(name+'_right',x+w/2-1,y,2,h,.025,z,'wear_dark',.4,module)

def bolt(name,x,y,z=.26,r=2.7,module='fasteners'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r/100,depth=.027,
        location=((x-210)/100,(420-y)/100,z))
    obj=bpy.context.object;obj.name=name;obj.data.materials.append(materials['steel'])
    obj['module']=module;parts.append(obj)
    box(name+'_slot',x,y,r*1.05,.85,.007,z+.018,'dark',0,module)

trim('nameplate_lip',144,45,216,34,.159,'header')
for name,x in [('help',290),('save',355)]:
    box(name+'_socket',x,46,59,39,.10,.10,'dark',2,'header')
    box(name+'_key',x,44,54,30,.14,.19,'key',2,'header')
    trim(name+'_trim',x,44,52,28,.268,'header')
for name,x in [('score',121),('target',299)]:
    trim(name+'_rim',x,115,165,74,.228,name)
    box(name+'_divider',x,102,149,1.5,.008,.240,'edge',0,name)
    for sx in (-1,1):
        for sy in (-1,1):bolt(name+'_screw'+str(sx)+str(sy),x+sx*80,115+sy*35,.25,1.7)
trim('round_rim',210,174,350,35,.192,'rounds')
trim('crt_outer',210,434,363,480,.230,'board')
trim('crt_inner',210,434,340,452,.306,'board')
trim('timer_rim',110,690,145,38,.260,'timer')
trim('status_rim',281,690,188,38,.177,'status')
trim('deck_rim',340,730,86,28,.191,'deck')
for name,x,w in [('reroll',94,112),('shake',271,222)]:
    trim(name+'_trim',x,780,w-4,48,.378,name)
    # This return face sits below the key top and exposes its mechanical travel.
    box(name+'_return',x,809,w-1,8,.07,.10,'wear_dark',1,name)
    for sx in (-1,1):
        for sy in (-1,1):bolt(name+'_screw'+str(sx)+str(sy),x+sx*(w/2-7),780+sy*18,.518,1.5,name)
for x in (25,395):
    for y in (75,157,202,671,714,815):bolt('case_%d_%d'%(x,y),x,y,.21)
for cx in (25,395):
    for cy in (183,688,735):
        for ix in range(2):
            for iy in range(3):
                box('perforation',cx-3+ix*5,cy-5+iy*5,2.6,2.6,.015,.171,'dark',.2,'vents')
# Consolidate decorative objects by material / module: no draw call per grain or screw.
for module in ('fasteners','vents','deskgrain','deskprops'):
    for material in materials.values():
        selected=[o for o in parts if o['module']==module and o.data.materials[0]==material
                  and not o.name.startswith(('reroll_screw','shake_screw'))
                  and (o.name.startswith(('perforation','case_'))
                       or module in ('fasteners','deskgrain','deskprops'))]
        if len(selected)<2: continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in selected:o.select_set(True)
        bpy.context.view_layer.objects.active=selected[0]
        for o in selected[1:]:parts.remove(o)
        bpy.ops.object.join();selected[0].name=module+'_'+material.name+'_details'

# Export unlit base colour plus flat face normals for real runtime lighting.
# Reflect Z and reverse winding for UrhoX; normals use the same reflection.
def lua(v):
    if isinstance(v,str): return json.dumps(v,ensure_ascii=False)
    if isinstance(v,dict): return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,(list,tuple)): return '{'+','.join(lua(x) for x in v)+'}'
    return str(v)
export=[]
for obj in parts:
    mesh=obj.data; mesh.calc_loop_triangles()
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='MetalUV')
    for loop in mesh.loops:
        point=obj.matrix_world @ mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=(point.x*.7,-point.y*.7)
    rgb=tuple(obj.data.materials[0].diffuse_color)[:3]
    groups={}
    for tri in mesh.loop_triangles:
        normal=(obj.matrix_world.to_3x3().inverted().transposed() @ tri.normal).normalized()
        tris=groups.setdefault(1,[])
        for idx in reversed(tri.vertices):
            p=obj.matrix_world @ mesh.vertices[idx].co
            tris.extend([round(p.x,5),round(p.y,5),round(-p.z,5),round(p.x*.7,5),round(-p.y*.7,5),
                         round(normal.x,5),round(normal.y,5),round(-normal.z,5)])
    textured=obj.data.materials[0].name not in plain_materials
    emissive=obj.data.materials[0].name in ('screen','lamp')
    export.append({'name':obj.name,'module':obj['module'],
                   'material':obj.data.materials[0].name,'textured':1 if textured else 0,
                   'emissive':1 if emissive else 0,'groups':[
        {'color':[round(min(1,c*band)*255) for c in rgb], 'vertices':verts} for band,verts in groups.items()]})
(LUA/'MeshData.lua').write_text('-- Generated from Blender. Rebuild with art-source/machine/build_machine.py.\nreturn '+lua(export)+'\n',encoding='utf-8')

bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'machine.glb'),use_selection=True,export_format='GLB')
# Camera and lighting for an editable source and a useful modelling preview.
tilt=math.radians(30)  # Keep in sync with scripts/Machine/Projection.lua.
bpy.ops.object.camera_add(location=(0,-15.8*math.sin(tilt),15.8*math.cos(tilt)))
camera=bpy.context.object; camera.name='Portrait_Camera'; camera.rotation_euler=(0,0,0)
camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='PERSP'; camera.data.sensor_fit='VERTICAL'; camera.data.angle=math.radians(30)
bpy.context.scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=(-4,6,5))
lightobj=bpy.context.object; lightobj.name='Warm_upper_left_key'
lightobj.data.energy=1100; lightobj.data.color=(1,.88,.66)
lightobj.data.shape='DISK'; lightobj.data.size=1.5
lightobj.rotation_euler=(Vector((0,0,0))-lightobj.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'
bpy.context.preferences.filepaths.save_version=0
scene.render.resolution_x=420; scene.render.resolution_y=840; scene.render.resolution_percentage=100
scene.world.color=(.025,.03,.035)
scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(OUT/'model-preview.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art-source/machine/machine.blend'))
bpy.ops.render.render(write_still=True)
print('MACHINE_EXPORT', len(parts), 'parts', sum(len(g['vertices'])//24 for p in export for g in p['groups']), 'triangles')
