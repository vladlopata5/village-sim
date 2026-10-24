extends Node3D
## Replaceable artwork only. Imported meshes/materials are shared by all residents.
const MODEL: PackedScene = preload("res://assets/models/creatures/zhabka_animated.glb")
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
var animation_player: AnimationPlayer
var walking := false

static func _collect_bounds(node: Node, parent: Transform3D, boxes: Array[AABB]) -> void:
	var local: Transform3D = parent*node.transform if node is Node3D else parent
	# Imported bone attachments otherwise retain their saved transform until a tree tick.
	if node is BoneAttachment3D and node.get_parent() is Skeleton3D:
		var skeleton: Skeleton3D=node.get_parent()
		var bone: int=skeleton.find_bone(node.bone_name)
		if bone>=0: local=parent*skeleton.get_bone_global_pose(bone)
	if node is MeshInstance3D and node.mesh!=null: boxes.append(local*node.get_aabb())
	for child in node.get_children(): _collect_bounds(child,local,boxes)

static func _measure_model() -> void:
	if _measured: return
	var probe := MODEL.instantiate()
	for player in probe.find_children("*","AnimationPlayer",true,false):
		if player.has_animation(&"idle"):
			player.play(&"idle")
			player.advance(0.0)
			player.stop(true)
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
	# Cache the nested player once. Scene instances share animation data, never playback.
	for node in instance.find_children("*","AnimationPlayer",true,false):
		if node.has_animation(&"walk"):
			animation_player=node
			break
	if animation_player==null or not animation_player.has_animation(&"idle"):
		push_error("Resident model must contain an AnimationPlayer with walk and idle")
		animation_player=null
		return
	animation_player.get_animation(&"walk").loop_mode=Animation.LOOP_LINEAR
	animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_stand()

func set_walking(value: bool) -> void:
	if value==walking or animation_player==null: return
	walking=value
	if walking: animation_player.play(&"walk")
	else: _stand()

func _stand() -> void:
	# The GLB includes a single authored standing pose; do not freeze a raised foot.
	animation_player.play(&"idle")
	animation_player.advance(0.0)
	animation_player.stop(true)

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
