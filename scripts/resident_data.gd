extends RefCounted
const ResidentActivity = preload("res://scripts/resident_activity.gd")
signal activity_changed
var activity: ResidentActivity.Type = ResidentActivity.Type.IDLE:
	set(value):
		if activity == value: return
		if activity == ResidentActivity.Type.SLEEPING:
			current_sleep_quality = Balance.OUTDOOR_SLEEP_QUALITY
		activity = value
		activity_changed.emit()
const Trait = preload("res://scripts/trait_type.gd")
## The resident exists as data, independently of any scene or renderer.
## The creator assigns an ID unique within the settlement.
var work_location_id: StringName = &""
signal home_changed(previous: StringName, current: StringName)
# Sole housing relationship. Empty/invalid references are valid homeless data.
var home_location_id: StringName = &"":
	set(value):
		if home_location_id == value: return
		var previous := home_location_id
		home_location_id = value
		home_changed.emit(previous, value)
var id: String
var resident_name: String
var age: int
const Profession = preload("res://scripts/resident_profession.gd")
var profession: Profession.Type
const Inventory = preload("res://scripts/resident_inventory.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
signal assignments_changed
var assignments: Array[Assignment] = []
var inventory = Inventory.new()
signal traits_changed
var traits: Array[Trait.Type] = []
func has_trait(trait_type: Trait.Type) -> bool: return traits.has(trait_type)
func add_trait(trait_type: Trait.Type) -> bool:
	if trait_type not in Trait.Type.values() or has_trait(trait_type) or traits.has(Trait.conflict(trait_type)): return false
	traits.append(trait_type)
	traits_changed.emit()
	return true
func remove_trait(trait_type: Trait.Type) -> bool:
	if not has_trait(trait_type): return false
	traits.erase(trait_type)
	traits_changed.emit()
	return true
## Higher hunger/fatigue means more hungry/tired; higher mood means happier.
const NeedType = preload("res://scripts/need_type.gd")
const Need = preload("res://scripts/need.gd")
const Balance = preload("res://scripts/balance_config.gd")
# Numeric snapshot of the current sleep action, not a permanent housing stat.
var current_sleep_quality: float = Balance.OUTDOOR_SLEEP_QUALITY
var needs: Dictionary = {
	NeedType.Type.HUNGER: Need.new(0, Balance.HUNGER_BASE_WEIGHT),
	NeedType.Type.FATIGUE: Need.new(0, Balance.FATIGUE_BASE_WEIGHT),
	NeedType.Type.SOCIAL: Need.new(0, Balance.SOCIAL_BASE_WEIGHT),
	NeedType.Type.LEISURE: Need.new(0, Balance.LEISURE_BASE_WEIGHT),
}
signal hunger_changed
signal fatigue_changed
# Compatibility accessors: one source of truth, not a second set of values.
var hunger: int:
	get: return needs[NeedType.Type.HUNGER].value
	set(next): needs[NeedType.Type.HUNGER].value = next
var fatigue: int:
	get: return needs[NeedType.Type.FATIGUE].value
	set(next): needs[NeedType.Type.FATIGUE].value = next
var mood: int = 50:
	set(value):
		mood = clampi(value, 0, 100)

func _init(unique_id: String, initial_name: String, initial_age: int, initial_profession: Profession.Type = Profession.Type.NONE) -> void:
	needs[NeedType.Type.HUNGER].changed.connect(hunger_changed.emit)
	needs[NeedType.Type.FATIGUE].changed.connect(fatigue_changed.emit)
	id = unique_id
	resident_name = initial_name
	age = initial_age
	profession = initial_profession

func get_need(type: NeedType.Type) -> Need:
	return needs[type]

func notify_assignments_changed() -> void:
	assignments_changed.emit()

func start_sleep(quality: float) -> void:
	# Callers resolve the concrete context once; recovery only reads this value.
	current_sleep_quality = maxf(quality, 0.0)
	activity = ResidentActivity.Type.SLEEPING

const Skill = preload("res://scripts/skill_type.gd")
signal skill_changed(skill: Skill.Type, amount: int, previous_level: int)
# XP is the only persistent skill state. Levels are never stored separately.
var _skill_xp: Dictionary = {Skill.Type.GATHERING: 0, Skill.Type.CONSTRUCTION: 0, Skill.Type.LOGISTICS: 0}
func get_skill_xp(skill: Skill.Type) -> int:
	return _skill_xp.get(skill, 0)
func get_skill_level(skill: Skill.Type) -> int:
	return clampi(floori(float(get_skill_xp(skill)) / Balance.SKILL_XP_PER_LEVEL), 0, Balance.MAX_SKILL_LEVEL)
func add_skill_xp(skill: Skill.Type, amount: int) -> bool:
	if amount <= 0 or not _skill_xp.has(skill): return false
	var previous_level := get_skill_level(skill)
	_skill_xp[skill] += amount
	skill_changed.emit(skill, amount, previous_level)
	return true

const Relationship = preload("res://scripts/resident_relationship.gd")
signal relationship_changed(other_resident_id: StringName)
# Outgoing directed records only. Never update another resident's reverse record.
var relationships: Dictionary = {}
func get_relationship(other_id: StringName) -> Relationship:
	if other_id == StringName(id) or other_id.is_empty(): return null
	return relationships.get(other_id)
func has_relationship(other_id: StringName) -> bool:
	return get_relationship(other_id) != null
func get_opinion(other_id: StringName) -> int:
	var relation := get_relationship(other_id)
	return relation.opinion if relation != null else Balance.OPINION_NEUTRAL
func set_opinion(other_id: StringName, value: int) -> bool:
	if other_id == StringName(id) or other_id.is_empty(): return false
	var bounded := clampi(value, Balance.OPINION_MIN, Balance.OPINION_MAX)
	if get_opinion(other_id) == bounded: return false
	var relation := get_relationship(other_id)
	if relation == null:
		relation = Relationship.new(other_id)
		relationships[other_id] = relation
		relation.opinion_changed.connect(_on_relationship_opinion_changed.bind(other_id))
	relation.opinion = bounded
	return true
func change_opinion(other_id: StringName, delta: int) -> bool:
	return set_opinion(other_id, get_opinion(other_id) + delta)
func _on_relationship_opinion_changed(other_id: StringName) -> void:
	relationship_changed.emit(other_id)
