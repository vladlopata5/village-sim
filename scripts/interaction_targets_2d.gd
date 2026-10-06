extends RefCounted
## Replaceable input adapter: hit testing is presentation, options are simulation.
var _views: Dictionary = {}
func register(id: StringName, view: Node2D) -> void: _views[id] = weakref(view)
func remove(id: StringName) -> void: _views.erase(id)
func hit(screen_position: Vector2) -> StringName:
	# Frontmost objects are registered last, matching prototype draw order.
	var ids: Array = _views.keys()
	ids.reverse()
	for id in ids:
		var view: Node2D = _views[id].get_ref()
		if is_instance_valid(view) and view.is_visible_in_tree() and view.interaction_hit(screen_position): return id
	return &""
