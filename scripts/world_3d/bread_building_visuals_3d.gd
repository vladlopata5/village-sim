extends RefCounted
## Low-poly presentation. The ordinary BuildingView owns the only collision/footprint.
const Types = preload("res://scripts/building_type.gd").Type
static func box(parent: Node3D, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	parent.add_child(node)
	return node
static func create(type: int) -> Node3D:
	var model := Node3D.new()
	model.name = "BreadProductionVisual"
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(6.3, 1.2, 4.3)
	roof.mesh = prism
	roof.position.y = 3.2
	var tile := StandardMaterial3D.new()
	tile.albedo_color = Color("8f563d")
	roof.material_override = tile
	model.add_child(roof)
	box(model,Vector3(1.0,1.8,.12),Vector3(0,.9,2.04),Color("58422e"))
	box(model,Vector3(1.3,.12,.6),Vector3(0,.06,2.1),Color("b9ac8e"))
	if type == Types.WINDMILL:
		box(model,Vector3(.7,1.7,.7),Vector3(0,3.9,0),Color("d4c6a3"))
		box(model,Vector3(.22,.22,2.4),Vector3(0,4.3,1.2),Color("5d4932"))
		var rotor := preload("res://scripts/world_3d/windmill_rotor_3d.gd").new()
		rotor.name = "Rotor"
		rotor.position = Vector3(0,4.3,2.4)
		model.add_child(rotor)
		for index in 4:
			var arm := Node3D.new()
			arm.rotation.z = index*PI/2.0
			rotor.add_child(arm)
			box(arm,Vector3(.12,1.7,.14),Vector3(0,.9,0),Color("634b31"))
			box(arm,Vector3(.42,1.1,.08),Vector3(.15,1.05,0),Color("e2d6b1"))
		box(rotor,Vector3(.35,.35,.3),Vector3.ZERO,Color("72583a"))
	else:
		box(model,Vector3(.7,2.0,.7),Vector3(1.7,3.6,-.7),Color("776c65"))
		box(model,Vector3(.95,.18,.95),Vector3(1.7,4.6,-.7),Color("554d48"))
		box(model,Vector3(1.25,1.3,.45),Vector3(-1.65,.65,2.05),Color("b7754f"))
		box(model,Vector3(.8,.65,.04),Vector3(-1.65,.5,2.3),Color("463c32"))
	return model
