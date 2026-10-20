extends Node3D
## Replaceable primitive artwork. No gameplay timing or state ownership here.
const Animal = preload("res://scripts/animal_data.gd")
var data: Animal
var body: Node3D
var head: MeshInstance3D
var label: Label3D
func _part(mesh: Mesh, color: Color, point: Vector3, parent: Node3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	part.mesh = mesh
	part.material_override = material
	part.position = point
	parent.add_child(part)
	return part
func setup(animal: Animal) -> void:
	data = animal
	body = Node3D.new()
	add_child(body)
	var fleece := SphereMesh.new()
	fleece.radius = 0.28
	fleece.height = 0.56
	var wool := _part(fleece,Color("eee9dc"),Vector3(0,0.4,0),body)
	wool.scale = Vector3(1,0.85,1.1)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.18,0.18,0.18)
	head = _part(head_mesh,Color("61574b"),Vector3(0,0.45,-0.23),body)
	for x in [-0.16,0.16]:
		var ear := BoxMesh.new()
		ear.size = Vector3(0.12,0.06,0.1)
		_part(ear,Color("61574b"),Vector3(x,0.51,-0.24),body)
	for x in [-0.14,0.14]:
		for z in [-0.17,0.17]:
			var leg := BoxMesh.new()
			leg.size = Vector3(0.07,0.23,0.07)
			_part(leg,Color("514a41"),Vector3(x,0.12,z),body)
	label = Label3D.new()
	label.position.y = 0.95
	label.pixel_size = 0.007
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	data.changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	var sleeping := data.behavior == Animal.Behavior.SLEEP
	body.position.y = -0.15 if sleeping else 0.0
	head.rotation.x = 0.7 if data.behavior == Animal.Behavior.GRAZE else 0.0
	head.position.y = 0.31 if data.behavior == Animal.Behavior.GRAZE else 0.45
	label.text = "%s · %s · %d/15" % [data.id,Animal.Behavior.keys()[data.behavior],data.wool_growth]
func face_movement(direction: Vector3) -> void:
	if Vector2(direction.x,direction.z).length_squared()>0.0000001: rotation.y = atan2(-direction.x,-direction.z)
