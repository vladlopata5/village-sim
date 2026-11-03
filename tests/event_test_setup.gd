extends RefCounted
## Synthetic facts only: no resident/runtime, world or signals are involved.
const Facts = preload("res://scripts/event_facts.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const DryRunner = preload("res://scripts/event_dry_run.gd")

static func person(id: String) -> Dictionary:
	return {"kind": "resident", "id": id}

static func registry() -> RefCounted:
	var facts := Facts.new()
	for id in ["a", "b", "c"]: facts.register_entity(person(id))
	facts.register_entity({"kind": "building", "id": "kitchen"})
	for key in ["equipment.clothing.appearance_rank", "equipment.clothing.acquired_minute", "housing.status_rank", "housing.assigned_minute"]: facts.register_fact(key, "resident", "number")
	for key in ["profession", "action.activity"]: facts.register_fact(key, "resident", "string")
	for key in ["profession.skill_ids", "memories.active", "tags"]: facts.register_fact(key, "resident", "array")
	facts.register_fact("skill.rank", "resident", "number", "string")
	facts.register_fact("presence.location", "resident", "entity")
	facts.register_fact("building.type", "building", "string")
	facts.register_fact("building.built", "building", "bool")
	facts.register_fact("building.state", "building", "string")
	for id in ["a", "b"]:
		var entity := person(id)
		for key in ["equipment.clothing.appearance_rank", "equipment.clothing.acquired_minute", "housing.status_rank", "housing.assigned_minute"]: facts.set_value(entity, key, 0)
		facts.set_value(entity, "profession", "builder")
		facts.set_value(entity, "profession.skill_ids", ["construction"])
		facts.set_value(entity, "skill.rank", 1 if id == "a" else 4, "construction")
		facts.set_value(entity, "action.activity", "EATING" if id == "a" else "WORKING")
		facts.set_value(entity, "presence.location", {"kind": "building", "id": "kitchen"})
		facts.set_value(entity, "memories.active", [])
	var building := {"kind": "building", "id": "kitchen"}
	facts.set_value(building, "building.type", "food")
	facts.set_value(building, "building.built", true)
	facts.set_value(building, "building.state", "BUILT")
	return facts

static func data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/event_examples.json"))

static func enabled_data() -> Dictionary:
	var result := data()
	for entry in result.definitions: entry.enabled = true
	return result

static func context(trigger: String, id: String = "op-1") -> Dictionary:
	return {"occurrence_id": id, "trigger": trigger, "minute": 1000, "actor": person("a"), "other": person("b"), "location": {"kind": "building", "id": "kitchen"}, "payload": {"reason": "completed", "shared_minutes": 20, "skill": "construction", "previous_rank": 1, "new_rank": 2}}

static func definition(id: String = "test", trigger: String = "test") -> Dictionary:
	return {"schema_version": 1, "id": id, "revision": 1, "enabled": true, "trigger": trigger, "main_role": "actor", "roles": {"actor": {"type": "resident", "from": "ctx.actor"}}, "params": {}, "bind": [], "when": true, "weight": 1, "effects": [], "text": {"chronicle": "{actor.name}: test event", "personal": "{actor.name}: test"}}

static func engine(data_value: Dictionary, facts: RefCounted) -> RefCounted:
	var catalog := Catalog.new()
	if not catalog.load_data(data_value, facts): push_error(str(catalog.errors))
	var value := DryRunner.new(catalog, facts)
	for trigger in ["test", "interaction.started", "interaction.ended", "skill.raised", "action.started", "construction.completed"]: value.set_chance(trigger, 1)
	return value
