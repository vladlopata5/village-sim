extends RefCounted
## Isolated domain positions; no rendering or navigation adaptation.
var _locations: Dictionary = {}
var _views: Dictionary = {}
func register(location: RefCounted, view: Node) -> void:
	_locations[location.id]=location
	_views[location.id]=view
func get_location(id: StringName) -> RefCounted: return _locations.get(id)
func get_view(id: StringName) -> Node:
	var view=_views.get(id)
	return view if is_instance_valid(view) else null
func get_position(id: StringName) -> Variant:
	var view=get_view(id)
	if view==null: return null
	return view.get_sim_position() if view.has_method("get_sim_position") else view.global_position
