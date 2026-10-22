extends Node3D
## Visual only: stable 3 + 3 + 3 + 1 positions, one shared imported scene.
const MODEL: PackedScene = preload("res://assets/models/resources/log.glb")
const MAX_VISIBLE := 10
const SPACING_FACTOR := 1.02 # Small clearance relative to measured mesh bounds.
static var model_bounds: AABB
static var horizontal_bounds: AABB
static var model_transform := Transform3D.IDENTITY
static var _measured := false
var instances: Array[Node3D] = []
var visible_count := 0

static func _collect_bounds(node: Node, parent: Transform3D, boxes: Array[AABB]) -> void:
	var local: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh!=null: boxes.append(local * node.get_aabb())
	for child in node.get_children(): _collect_bounds(child,local,boxes)

static func _measure_model() -> void:
	if _measured: return
	var probe := MODEL.instantiate()
	var boxes: Array[AABB] = []
	_collect_bounds(probe,Transform3D.IDENTITY,boxes)
	probe.free()
	assert(not boxes.is_empty(),"LOG model must contain a mesh")
	model_bounds=boxes[0]
	for box in boxes.slice(1): model_bounds=model_bounds.merge(box)
	# Normalize only orientation and pivot. Imported dimensions/scale stay intact.
	var axis := model_bounds.size.max_axis_index()
	var orientation := Basis.IDENTITY
	if axis==Vector3.AXIS_Y: orientation=Basis(Vector3.FORWARD,PI/2.0)
	elif axis==Vector3.AXIS_Z: orientation=Basis(Vector3.UP,PI/2.0)
	model_transform=Transform3D(orientation,-(orientation*model_bounds.get_center()))
	horizontal_bounds=model_transform*model_bounds
	_measured=true

func _slot_transform(index: int) -> Transform3D:
	var layer := floori(index/3.0)
	var across := 0 if index==9 else index%3-1
	var height := horizontal_bounds.size.y
	var spacing := horizontal_bounds.size.z*SPACING_FACTOR
	var cross := layer%2==1
	var offset := Vector3(across*spacing,0,0) if cross else Vector3(0,0,across*spacing)
	offset.y=height/2.0+layer*height*SPACING_FACTOR
	return Transform3D(Basis(Vector3.UP,PI/2.0 if cross else 0.0),offset)

func set_amount(quantity: int) -> void:
	var count := clampi(quantity,0,MAX_VISIBLE)
	if count==visible_count: return
	_measure_model()
	# Grow lazily, retain old nodes/transforms and hide only the tail on pickup.
	while instances.size()<count:
		var index := instances.size()
		var slot := Node3D.new()
		slot.name="Log%d"%(index+1)
		slot.transform=_slot_transform(index)
		var pivot := Node3D.new()
		pivot.name="ModelBasis"
		pivot.transform=model_transform
		pivot.add_child(MODEL.instantiate())
		slot.add_child(pivot)
		add_child(slot)
		instances.append(slot)
	for index in instances.size(): instances[index].visible=index<count
	visible_count=count
