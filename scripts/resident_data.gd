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
var resident_name: String:
	set(value):
		if resident_name == value: return
		resident_name = value
		_name_forms = {} # Explicit forms belong to this exact displayed name.
const NameGrammar = preload("res://scripts/event_russian_grammar.gd")
var _name_forms: Dictionary = {}
var name_indeclinable := false
func set_name_forms(forms: Dictionary, indeclinable: bool = false) -> bool:
	if not forms.is_empty() and not NameGrammar.valid_forms(forms, resident_name): return false
	_name_forms = forms.duplicate(true)
	name_indeclinable = indeclinable
	return true
func event_text_projection() -> Dictionary:
	var gender := "feminine" if grammatical_gender == Trait.GrammaticalGender.FEMININE else "masculine"
	return {"name": resident_name, "gender": gender, "name_forms": NameGrammar.forms(resident_name, gender, _name_forms, name_indeclinable)}
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
# Derived, read-only: MoodletStore is the only source of mood contributions.
var mood: float:
	get: return Modifiers.mood_from_offset(moodlets.mood_offset())
const NeedMoodlets = preload("res://scripts/need_moodlet_rules.gd")
signal need_state_changed(context: Dictionary)
var _need_state_sequence := 0
var _need_state_depth := 0
var _publishing_need_states := false
var _pending_need_states: Array = []

func _on_need_changed(type: int) -> void:
	var definition: Dictionary = NeedMoodlets.DEFINITIONS[type]
	var active := not moodlets.get_entry(definition.id).is_empty()
	var deficit: int = needs[type].value
	var desired := NeedMoodlets.desired(deficit, active)
	if desired == active: return
	_need_state_sequence += 1
	var minute := moodlets.current_minute()
	var occurrence_id := JSON.stringify(["need.state_changed", id, _need_state_sequence])
	var context := {"trigger":"need.state_changed", "occurrence_id":occurrence_id, "minute":minute, "actor":{"kind":"resident","id":id}, "payload":{"need":NeedType.Type.keys()[type].to_lower(),"active":desired,"deficit":deficit,"moodlet":definition.id}}
	# Enqueue before Store callbacks: nested threshold crossings retain fact order.
	_pending_need_states.append(context)
	_need_state_depth += 1
	var changed: bool = moodlets.add(NeedMoodlets.record(type, minute, occurrence_id)) if desired else moodlets.remove(definition.id)
	assert(changed, "A guaranteed need transition must use a valid owned moodlet store")
	_need_state_depth -= 1
	if _need_state_depth > 0 or _publishing_need_states: return
	_publishing_need_states = true
	while not _pending_need_states.is_empty(): need_state_changed.emit(_pending_need_states.pop_front().duplicate(true))
	_publishing_need_states = false

func _init(unique_id: String, initial_name: String, initial_age: int, initial_profession: Profession.Type = Profession.Type.NONE) -> void:
	id = unique_id
	opinion_rng.seed = unique_id.hash() ^ 0x4F50494E # Independent of AI/social reaction RNG.
	memories = MemoryStore.new(unique_id)
	moodlets = MoodletStore.new(unique_id)
	# Guaranteed state transitions run before existing UI/AI need observers.
	for type in NeedType.Type.values():
		needs[type].changed.connect(_on_need_changed.bind(type))
		_on_need_changed(type)
	needs[NeedType.Type.HUNGER].changed.connect(hunger_changed.emit)
	needs[NeedType.Type.FATIGUE].changed.connect(fatigue_changed.emit)
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
const Modifiers = preload("res://scripts/resident_modifiers.gd")
var opinion_rng: RefCounted = RandomNumberGenerator.new()
signal relationship_changed(other_resident_id: StringName)
# Outgoing directed records only. Never update another resident's reverse record.
var _relationships: Dictionary = {}
var relationships: Dictionary:
	get: return _relationships.duplicate()
var _social_links: RefCounted

func bind_social_links(links: RefCounted) -> void:
	_social_links = links

func is_current_opinion_partner(other: RefCounted) -> bool:
	if not _valid_opinion_target(other.id): return false
	return _social_links == null or _social_links.resident_for(other.id) == other

func _valid_opinion_target(other_id: StringName) -> bool:
	if other_id == StringName(id) or String(other_id).strip_edges().is_empty(): return false
	if _social_links == null: return true
	return _social_links.resident_for(id) == self and _social_links.resident_for(String(other_id)) != null

func _opinion_bounds(other_id: StringName, current: int) -> Vector2i:
	var level := 0
	if _social_links != null:
		level = _social_links.get_level(self, _social_links.resident_for(String(other_id)))
	var center := level * Balance.OPINION_LINK_STEP
	return Vector2i(mini(current, center - Balance.OPINION_LINK_STEP), maxi(current, center + Balance.OPINION_LINK_STEP))

func get_relationship(other_id: StringName) -> Relationship:
	if other_id == StringName(id) or other_id.is_empty(): return null
	return _relationships.get(other_id)
func has_relationship(other_id: StringName) -> bool:
	return get_relationship(other_id) != null
func get_opinion(other_id: StringName) -> int:
	var relation := get_relationship(other_id)
	return relation.opinion if relation != null else Balance.OPINION_NEUTRAL
func set_opinion(other_id: StringName, value: int) -> bool:
	if not _valid_opinion_target(other_id): return false
	var bounds := _opinion_bounds(other_id, get_opinion(other_id))
	return _write_opinion(other_id, clampi(value, bounds.x, bounds.y))

func _write_opinion(other_id: StringName, bounded: int) -> bool:
	if get_opinion(other_id) == bounded: return false
	var relation := get_relationship(other_id)
	if relation == null:
		relation = Relationship.new(other_id)
		_relationships[other_id] = relation
		relation.opinion_changed.connect(_on_relationship_opinion_changed.bind(other_id))
	relation._commit_opinion(bounded)
	return true
func change_opinion(other_id: StringName, delta: int) -> bool:
	var applied := apply_opinion_change(other_id, delta)
	return applied.before != applied.after
func apply_opinion_change(other_id: StringName, delta: int) -> Dictionary:
	# Return this operation's facts, even if an emitted callback changes opinion again.
	var before := get_opinion(other_id)
	var applied := {"before": before, "after": before}
	if not _valid_opinion_target(other_id) or delta == 0: return applied
	var bounds := _opinion_bounds(other_id, before)
	if (before == bounds.y and delta > 0) or (before == bounds.x and delta < 0): return applied
	var magnitude := absf(Modifiers.opinion_delta(self, delta))
	var whole := floori(minf(magnitude, Balance.OPINION_MAX - Balance.OPINION_MIN))
	var fraction := magnitude - floorf(magnitude)
	# Only a committed fractional change consumes one draw. Reads/set/previews do not.
	if fraction > 0.0 and opinion_rng.randf() < fraction: whole += 1
	applied.after = clampi(before + whole * signi(delta), bounds.x, bounds.y)
	_write_opinion(other_id, applied.after)
	return applied

func _erase_opinion(other_id: StringName) -> bool:
	var relation := get_relationship(other_id)
	if relation == null: return false
	relation.opinion_changed.disconnect(_on_relationship_opinion_changed.bind(other_id))
	return _relationships.erase(other_id)
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
