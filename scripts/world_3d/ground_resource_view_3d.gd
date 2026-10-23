extends Node3D
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Resources = preload("res://scripts/resource_type.gd")
var ground_resource: RefCounted
var quantity_label: Label3D
var log_visual: Node3D
func setup(drop: RefCounted) -> void:
	ground_resource = drop
	position = Coordinates.to_world(drop.world_position)
	drop.availability_changed.connect(_sync_position)
	quantity_label=Label3D.new()
	quantity_label.position.y=0.7
	quantity_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	quantity_label.font_size=48
	quantity_label.pixel_size=0.006
	quantity_label.outline_size=10
	quantity_label.no_depth_test=true
	add_child(quantity_label)
	if drop.resource_type==Resources.Type.LOG:
		log_visual=preload("res://scripts/world_3d/log_stack_visual_3d.gd").new()
		add_child(log_visual)
	_sync_position()
	if log_visual!=null: return
	if drop.resource_type==Resources.Type.WATER:
		add_child(preload("res://scripts/world_3d/water_bucket_visual_3d.gd").create())
		return
	var visual := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	if drop.resource_type == Resources.Type.SHEAF:
		var bundle:=CylinderMesh.new();bundle.top_radius=0.15;bundle.bottom_radius=0.18;bundle.height=0.42;bundle.radial_segments=6
		visual.mesh=bundle;visual.position.y=0.21;material.albedo_color=Color("d6b350")
		var tie:=MeshInstance3D.new();var band:=TorusMesh.new();band.inner_radius=0.12;band.outer_radius=0.16;band.rings=8;band.ring_segments=6;tie.mesh=band;tie.position.y=0.21
		var string_material:=StandardMaterial3D.new();string_material.albedo_color=Color("80613b");tie.material_override=string_material;add_child(tie)
	elif drop.resource_type in [Resources.Type.FLOUR,Resources.Type.BREAD]:
		var good := SphereMesh.new()
		good.radius = .18
		good.height = .4 if drop.resource_type==Resources.Type.FLOUR else .2
		good.radial_segments = 8
		good.rings = 4
		visual.mesh = good
		visual.position.y = good.height/2.0
		material.albedo_color = Color("eee0bc") if drop.resource_type==Resources.Type.FLOUR else Color("cb9144")
	elif drop.resource_type in [Resources.Type.CLAY,Resources.Type.BRICK]:
		var good:=BoxMesh.new()
		good.size=Vector3(.32,.16,.20) if drop.resource_type==Resources.Type.BRICK else Vector3(.24,.18,.23)
		visual.mesh=good;visual.position.y=good.size.y/2.0
		material.albedo_color=Color("bd6846") if drop.resource_type==Resources.Type.BRICK else Color("9f603b")
	elif drop.resource_type == Resources.Type.STONE_BRICK:
		var block:=BoxMesh.new()
		block.size=Vector3(.36,.18,.22)
		visual.mesh=block;visual.position.y=block.size.y/2.0
		material.albedo_color=Color("929ca5")
	elif drop.resource_type == Resources.Type.STONE:
		var stone := SphereMesh.new()
		stone.radius = 0.18
		stone.height = 0.25
		stone.radial_segments = 6
		stone.rings = 3
		visual.mesh = stone
		visual.position.y = 0.125
		material.albedo_color = Color(0.55,0.57,0.59)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.25,0.2,0.25)
		visual.mesh = box
		visual.position.y = 0.1
		material.albedo_color = Color(0.8,0.65,0.2)
	visual.material_override = material
	add_child(visual)
func _sync_position() -> void:
	position = Coordinates.to_world(ground_resource.world_position)
	if quantity_label!=null:
		quantity_label.text="×%d" % ground_resource.amount
		quantity_label.visible=ground_resource.resource_type!=Resources.Type.LOG and ground_resource.amount>1
	if log_visual!=null:log_visual.set_amount(ground_resource.amount)
