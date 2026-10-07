extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Relationship = preload("res://scripts/resident_relationship.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Need = preload("res://scripts/need_type.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Choice = preload("res://scripts/weighted_choice.gd")
var failures := 0
var checks := 0
var a_events: Array[StringName] = []
var b_events: Array[StringName] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var anna = Data.new("anna", "Анна", 25)
	var stepan = Data.new("stepan", "Степан", 30)
	anna.relationship_changed.connect(func(other): a_events.append(other))
	stepan.relationship_changed.connect(func(other): b_events.append(other))
	check(Balance.OPINION_MIN == -100 and Balance.OPINION_MAX == 100 and Balance.OPINION_NEUTRAL == 0, "Opinion balance constants")
	check(anna.get_opinion(&"stepan") == 0 and anna.get_relationship(&"stepan") == null and not anna.has_relationship(&"stepan"), "Absent relationship is neutral")
	check(anna.relationships.is_empty() and stepan.relationships.is_empty(), "Neutral reads allocate nothing")
	check(not anna.set_opinion(&"stepan", 0) and not anna.change_opinion(&"stepan", 0), "Absent neutral/no-op remains sparse")
	check(a_events.is_empty() and anna.relationships.is_empty(), "No-op emits nothing")
	check(anna.set_opinion(&"stepan", 40) and anna.get_opinion(&"stepan") == 40, "Set positive creates record")
	var relation = anna.get_relationship(&"stepan")
	check(relation is Relationship and relation is RefCounted and not relation is Node, "Relationship is persistent data, not a visual Node")
	check(relation.other_resident_id == &"stepan" and anna.relationships.has(&"stepan"), "Stable ID key and target")
	check(a_events == [&"stepan"] and b_events.is_empty() and stepan.get_opinion(&"anna") == 0, "Only owning resident changes/emits")
	check(stepan.change_opinion(&"anna", -10) and stepan.get_opinion(&"anna") == -10 and anna.get_opinion(&"stepan") == 40, "Two independent directions coexist")
	check(b_events == [&"anna"], "Reverse signal belongs only to reverse owner")
	check(not anna.set_opinion(&"stepan", 40) and a_events.size() == 1, "Same opinion emits no duplicate signal")
	anna.set_opinion(&"stepan", 90)
	anna.change_opinion(&"stepan", 30)
	check(anna.get_opinion(&"stepan") == 100, "Positive delta clamps at maximum")
	var count := a_events.size()
	check(not anna.change_opinion(&"stepan", 1) and a_events.size() == count, "Clamped unchanged value emits nothing")
	anna.set_opinion(&"stepan", -90)
	anna.change_opinion(&"stepan", -30)
	check(anna.get_opinion(&"stepan") == -100, "Negative delta clamps at minimum")
	anna.set_opinion(&"stepan", 300)
	check(anna.get_opinion(&"stepan") == 100, "Set clamps positive")
	anna.set_opinion(&"stepan", -300)
	check(anna.get_opinion(&"stepan") == -100, "Set clamps negative")
	check(anna.get_relationship(&"stepan") == relation, "Changes preserve directed object identity")
	anna.set_opinion(&"stepan", 0)
	check(anna.get_opinion(&"stepan") == 0 and anna.has_relationship(&"stepan"), "Existing neutral record remains valid")
	count = a_events.size()
	relation.opinion = 500
	check(relation.opinion == 100 and a_events.size() == count + 1, "Data-object setter also clamps/forwards owner event")
	relation.opinion = 600
	check(a_events.size() == count + 1, "Direct clamped no-op emits nothing")
	check(anna.get_opinion(&"anna") == 0 and not anna.has_relationship(&"anna") and anna.get_relationship(&"anna") == null, "Self reads are neutral/null")
	check(not anna.set_opinion(&"anna", 80) and not anna.change_opinion(&"anna", -25) and not anna.relationships.has(&"anna"), "Self writes rejected")
	check(not anna.set_opinion(&"", 20) and anna.get_opinion(&"") == 0, "Empty target rejected safely")
	check(anna.change_opinion(&"temporarily_missing_id", 25) and anna.get_opinion(&"temporarily_missing_id") == 25, "Stable ID remains valid without world/View pointer")
	check(anna.relationships.size() == 2 and stepan.relationships.size() == 1, "Only modified links persist, never a full matrix")

	var scene = Setup.make_scene(self)
	for resident in scene.residents:
		check(resident.relationships.is_empty(), "Every starting resident has sparse empty storage")
		for other in scene.residents: check(resident.get_opinion(StringName(other.id)) == 0, "All effective starting opinions neutral")
	var actor = scene.resident_runtimes[1]
	var target = scene.resident_runtimes[0]
	var card = scene.get_node("HUD/ResidentCard")
	card.set_process(false)
	scene.resident_selection.select(actor.data)
	check(card.relationships_label.text.begins_with("Отношения\n"), "Relationship section exists")
	check(not card.relationships_label.text.contains(actor.data.resident_name + ":"), "Selected resident excluded")
	for other in scene.residents:
		if other != actor.data: check(card.relationships_label.text.contains(other.resident_name + ": 0"), "Other current residents displayed with neutral value")
	actor.data.set_opinion(StringName(target.data.id), 40)
	target.data.set_opinion(StringName(actor.data.id), -10)
	check(card.relationships_label.text.contains("Степан: +40"), "Card shows selected to other, not reverse")
	paused = true
	actor.data.change_opinion(StringName(target.data.id), -15)
	check(card.relationships_label.text.contains("Степан: +25"), "Signal refreshes immediately on pause")
	paused = false
	card.relationships_label.text = "event marker"
	card._refresh()
	card._process(1)
	check(card.relationships_label.text == "event marker", "Ordinary frame refresh does not poll relationships")
	scene.resident_selection.select(target.data)
	check(card.relationships_label.text.contains("Анна: -10"), "Reverse selection shows reverse opinion")
	var shown: String = card.relationships_label.text
	actor.data.change_opinion(StringName(target.data.id), 1)
	check(card.relationships_label.text == shown, "Old resident relationship signal disconnected")
	target.data.change_opinion(StringName(actor.data.id), 10)
	check(card.relationships_label.text.contains("Анна: 0"), "Zero displayed without a plus sign")
	target.data.set_opinion(&"unknown_person", -15)
	check(not card.relationships_label.text.contains("unknown_person"), "Records for absent target not shown in current roster")
	var newcomer = Data.new("newcomer", "Иван", 24)
	scene.player_control.setup([newcomer], scene.buildings)
	check(card.relationships_label.text.contains("Иван: 0"), "Roster event updates card without frames")
	scene.resident_selection.clear()
	check(not card.visible, "Clearing selection still closes card")
	scene.free()

	# Existing social options/weights and selector utility are independent of opinion.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	actor.data.get_need(Need.Type.SOCIAL).value = 100
	target.data.get_need(Need.Type.SOCIAL).value = 100
	var actions: Array = actor.decision.collect_actions(false)
	var options: Array = scene.social_world.options_for(actor.data.id)
	var original_traits: Array = actor.data.traits.duplicate()
	var original_speed: float = Modifiers.movement_speed(actor.data, 120)
	var rng = RandomNumberGenerator.new()
	rng.seed = 123
	var selected: Dictionary = Choice.pick(options, rng)
	actor.data.set_opinion(StringName(target.data.id), -100)
	target.data.set_opinion(StringName(actor.data.id), 100)
	check(actor.decision.collect_actions(false) == actions, "Opinion does not change SOCIAL or any normal utility")
	check(scene.social_world.options_for(actor.data.id) == options, "Social partners/weights unchanged")
	rng.seed = 123
	check(Choice.pick(scene.social_world.options_for(actor.data.id), rng) == selected, "Seeded partner choice independent of opinion")
	check(actor.data.traits == original_traits and Modifiers.movement_speed(actor.data, 120) == original_speed, "Traits and resolver unchanged")
	var task = Assignment.new(&"relationship_talk", actor.data.id, Assignment.TALK_TO, StringName(target.data.id))
	check(scene.player_control.add_assignment(actor.data.id, task) and actor.assignments.start(task.id), "TALK_TO still starts with negative opinion")
	actor.view._process(100)
	check(scene.social_world.group_of(actor.data.id) == scene.social_world.group_of(target.data.id), "Existing group joins concrete target")
	scene.game_time.debug_skip_minutes(15)
	check(task.state == Assignment.State.COMPLETED, "Existing 15-minute TALK_TO completion unchanged")
	check(actor.data.get_opinion(StringName(target.data.id)) == -100 and target.data.get_opinion(StringName(actor.data.id)) == 100, "Conversation and TALK_TO completion never change either opinion")
	for skill in Skill.Type.values(): check(actor.data.get_skill_xp(skill) == 0, "Talking/opinion adds no skill XP")
	scene.game_time.debug_skip_minutes(30)
	check(actor.data.get_opinion(StringName(target.data.id)) == -100, "No periodic opinion decay or conversation gain")
	scene.free()
	# Independent autonomous conversation also creates no neutral relationship records.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	actor.data.get_need(Need.Type.SOCIAL).value = 100
	target.data.get_need(Need.Type.SOCIAL).value = 100
	check(actor.social.try_social_at(StringName(target.data.id), 8000), "Independent conversation starts normally")
	actor.view._process(100)
	scene.game_time.debug_skip_minutes(15)
	check(actor.data.relationships.is_empty() and target.data.relationships.is_empty(), "Ordinary conversation adds no records or opinions")
	scene.free()
	print("Relationship checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
