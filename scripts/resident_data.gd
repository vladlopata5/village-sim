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
# Invalidation generation only; the relationship still lives in these fields.
var work_assignment_revision := 0
var work_area_id: StringName = &"":
	set(value):
		if work_area_id == value: return
		work_area_id = value
		work_assignment_revision += 1
var work_location_id: StringName = &"":
	set(value):
		if work_location_id == value: return
		work_location_id = value
		work_assignment_revision += 1
signal household_changed(previous: StringName, current: StringName)
# Sole permanent housing relationship. Invalid/empty references are homeless data.
var household_id: StringName = &"":
	set(value):
		if household_id==value: return
		var previous := household_id
		household_id=value
		household_changed.emit(previous,value)
var id: String
var resident_name: String
var age: int
const Profession = preload("res://scripts/resident_profession.gd")
var profession: Profession.Type:
	set(value):
		if profession == value: return
		profession = value
		work_assignment_revision += 1
const Inventory = preload("res://scripts/resident_inventory.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
signal assignments_changed
var assignments: Array[Assignment] = []
var inventory = Inventory.new() # Work cargo only.
var equipment = preload("res://scripts/resident_equipment.gd").new()
const MemoryStore = preload("res://scripts/memory_store.gd")
const MoodletStore = preload("res://scripts/moodlet_store.gd")
var memories: MemoryStore
var moodlets: MoodletStore
signal traits_changed
var _traits: Array[Trait.Type] = []
var traits: Array[Trait.Type]:
	get: return _traits.duplicate()
	set(value): set_traits(value)
var grammatical_gender: Trait.GrammaticalGender = Trait.GrammaticalGender.MASCULINE:
	set(value):
		if value not in Trait.GrammaticalGender.values() or grammatical_gender == value: return
		grammatical_gender = value
		traits_changed.emit()
func trait_description() -> String:
	return Trait.description(_traits, grammatical_gender)
func set_traits(values: Array) -> bool:
	if not Trait.compatible(values): return false
	if _traits == values: return true
	_traits.assign(values)
	traits_changed.emit()
	return true
func has_trait(trait_type: Trait.Type) -> bool: return _traits.has(trait_type)
func add_trait(trait_type: Trait.Type) -> bool:
	if trait_type not in Trait.Type.values() or has_trait(trait_type) or _traits.has(Trait.conflict(trait_type)): return false
	_traits.append(trait_type)
	traits_changed.emit()
	return true
func remove_trait(trait_type: Trait.Type) -> bool:
	if not has_trait(trait_type): return false
	_traits.erase(trait_type)
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
	memories = MemoryStore.new(unique_id)
	moodlets = MoodletStore.new(unique_id)
	resident_name = initial_name
	age = initial_age
	profession = initial_profession
	for skill in Skill.Type.values(): _skill_xp[skill] = 0

func get_need(type: NeedType.Type) -> Need:
	return needs[type]

func notify_assignments_changed() -> void:
	assignments_changed.emit()

func start_sleep(quality: float) -> void:
	# Callers resolve the concrete context once; recovery only reads this value.
	current_sleep_quality = maxf(quality, 0.0)
	activity = ResidentActivity.Type.SLEEPING

const Skill = preload("res://scripts/skill_type.gd")
const SkillRules = preload("res://scripts/work_skill_rules.gd")
signal skill_changed(skill: Skill.Type, amount: int, previous_rank: int)
signal skill_raised(transition_id: int, skill: Skill.Type, previous_rank: int, new_rank: int)
# The only skill state. Ranks and efficiency are derived, without legacy levels.
var _skill_xp: Dictionary = {}
var _skill_raise_sequence := 0
var _skill_change_depth := 0
var _publishing_skill_raises := false
var _pending_skill_raises: Array = []
func get_skill_xp(skill: Skill.Type) -> int:
	return _skill_xp.get(skill, 0)
func get_skill_rank(skill: Skill.Type) -> Skill.Rank:
	return Skill.rank_for_xp(get_skill_xp(skill))
func add_skill_xp(skill: Skill.Type, amount: int, training_cap: int = Balance.MAX_SKILL_XP) -> bool:
	if not _skill_xp.has(skill): return false
	var gain := Skill.xp_gain(get_skill_xp(skill), amount, training_cap)
	return _commit_skill_gains({skill: gain}) if gain > 0 else false
func award_skill_xp(rules: SkillRules) -> bool:
	if rules == null or not rules.is_valid(): return false
	return _commit_skill_gains(rules.reward_deltas(self))
func _commit_skill_gains(gains: Dictionary) -> bool:
	if gains.is_empty(): return false
	var changes: Array = []
	# Commit every skill before publishing any callback. A nested award observes
	# the whole reward, and all rank facts retain their original commit order.
	for skill in gains:
		var previous_rank := get_skill_rank(skill)
		_skill_xp[skill] += gains[skill]
		var new_rank := get_skill_rank(skill)
		changes.append([skill, gains[skill], previous_rank])
		if new_rank > previous_rank:
			_skill_raise_sequence += 1
			_pending_skill_raises.append([_skill_raise_sequence, skill, previous_rank, new_rank])
	_skill_change_depth += 1
	for change in changes: skill_changed.emit(change[0] as Skill.Type, change[1], change[2])
	_skill_change_depth -= 1
	if _skill_change_depth == 0 and not _publishing_skill_raises:
		_publishing_skill_raises = true
		while not _pending_skill_raises.is_empty():
			var transition: Array = _pending_skill_raises.pop_front()
			skill_raised.emit(transition[0], transition[1] as Skill.Type, transition[2], transition[3])
		_publishing_skill_raises = false
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

const TraitPreferences = preload("res://scripts/trait_preference_resolver.gd")
signal trait_preferences_changed
var liked_traits: Array[Trait.Type] = []
var disliked_traits: Array[Trait.Type] = []
func likes_trait(trait_type: Trait.Type) -> bool: return liked_traits.has(trait_type)
func dislikes_trait(trait_type: Trait.Type) -> bool: return disliked_traits.has(trait_type)
func add_liked_trait(trait_type: Trait.Type) -> bool:
	return _add_trait_preference(liked_traits, disliked_traits, trait_type)
func add_disliked_trait(trait_type: Trait.Type) -> bool:
	return _add_trait_preference(disliked_traits, liked_traits, trait_type)
func _add_trait_preference(list: Array[Trait.Type], opposite: Array[Trait.Type], trait_type: Trait.Type) -> bool:
	if trait_type not in Trait.Type.values() or list.has(trait_type) or opposite.has(trait_type): return false
	list.append(trait_type)
	trait_preferences_changed.emit()
	return true
func remove_liked_trait(trait_type: Trait.Type) -> bool:
	return _remove_trait_preference(liked_traits, trait_type)
func remove_disliked_trait(trait_type: Trait.Type) -> bool:
	return _remove_trait_preference(disliked_traits, trait_type)
func _remove_trait_preference(list: Array[Trait.Type], trait_type: Trait.Type) -> bool:
	if not list.has(trait_type): return false
	list.erase(trait_type)
	trait_preferences_changed.emit()
	return true
func get_trait_preference_score(other: RefCounted) -> int:
	return TraitPreferences.score(self, other)


const DiaryEntry = preload("res://scripts/diary_entry.gd")
signal diary_changed
var diary_entries: Array[DiaryEntry] = []
func add_diary_entry(entry: DiaryEntry) -> bool:
	if not can_add_diary_entry(entry): return false
	_apply_event_diary(entry)
	diary_changed.emit()
	return true
func can_add_diary_entry(entry: DiaryEntry) -> bool:
	return entry != null and entry.importance != DiaryEntry.Importance.NONE and not entry.text.is_empty()
func _apply_event_diary(entry: DiaryEntry) -> void:
	# Internal synchronous commit, deliberately separate from notification.
	diary_entries.append(entry)
func expire_temporary_diary(morning_minute: int) -> void:
	var kept: Array[DiaryEntry] = []
	for entry in diary_entries:
		if entry.importance != DiaryEntry.Importance.TEMPORARY or entry.created_minute >= morning_minute: kept.append(entry)
	if kept.size() == diary_entries.size(): return
	diary_entries = kept
	diary_changed.emit()
