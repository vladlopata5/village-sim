extends RefCounted
## Existing execution tests fast-forward a reached operation through real GameTime.
## Boundary tests deliberately do not use this helper.
static func finish(actor: Node) -> void:
	if actor.intents.current_intent.resource_handling.is_empty(): return
	var clock: Node = actor.needs._clock
	var duration: int = preload("res://scripts/balance_config.gd").RESOURCE_LOADING_MINUTES if actor.intents.current_intent.resource_handling==&"loading" else preload("res://scripts/balance_config.gd").RESOURCE_UNLOADING_MINUTES
	clock.debug_skip_minutes(duration)
static func move_domain(actor: Node, delta: float) -> void:
	actor.view._process(delta)
	finish(actor)
static func move_3d(actor: Node, delta: float) -> void:
	actor.view._physics_process(delta)
	finish(actor)
