extends Node3D
## Replaceable artwork only. Imported meshes/materials are shared by all residents.
const MODEL: PackedScene = preload("res://assets/models/creatures/zhabka.glb")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const FRONT_YAW: float = PI # The imported frog faces +Z; movement uses -Z.
signal dimensions_changed
@export var visual_scale: float = 1.0:
	set(value):
		visual_scale=maxf(value,0.01)
		if is_instance_valid(model_basis): _fit_model()
static var source_bounds: AABB
static var _measured := false
var model_basis: Node3D
var instance: Node3D
var fitted_scale := 1.0

static func _collect_bounds(node: Node, parent: Transform3D, boxes: Array[AABB]) -> void:
	var local: Transform3D = parent*node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh!=null: boxes.append(local*node.get_aabb())
	for child in node.get_children(): _collect_bounds(child,local,boxes)

static func _measure_model() -> void:
	if _measured: return
	var probe := MODEL.instantiate()
	var boxes: Array[AABB] = []
	_collect_bounds(probe,Transform3D.IDENTITY,boxes)
	probe.free()
	assert(not boxes.is_empty(),"Resident model must contain a mesh")
	source_bounds=boxes[0]
	for box in boxes.slice(1): source_bounds=source_bounds.merge(box)
	assert(source_bounds.size.y>0.0,"Resident model must have a positive height")
	_measured=true

func setup() -> void:
	_measure_model()
	model_basis=Node3D.new();model_basis.name="ModelBasis"
	add_child(model_basis)
	instance=MODEL.instantiate()
	model_basis.add_child(instance)
	_fit_model()

func _fit_model() -> void:
	# Match the previous resident height, uniformly; never scale the executor/collider.
	fitted_scale=Geometry.RESIDENT_HEIGHT/source_bounds.size.y*visual_scale
	var orientation := Basis(Vector3.UP,FRONT_YAW).scaled(Vector3.ONE*fitted_scale)
	var origin := Vector3(source_bounds.get_center().x,source_bounds.position.y,source_bounds.get_center().z)
	model_basis.transform=Transform3D(orientation,-(orientation*origin))
	dimensions_changed.emit()

func height() -> float: return source_bounds.size.y*fitted_scale
func face_movement(direction: Vector3) -> void:
	if Vector2(direction.x,direction.z).length_squared()>0.0000001:
		rotation.y=atan2(-direction.x,-direction.z)
