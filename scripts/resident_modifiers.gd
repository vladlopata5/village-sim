extends RefCounted
## Narrow behavior resolver. Consumers supply base values, not trait_type identities.
## Future sources can compose their contributions here without changing callers.
const Trait = preload("res://scripts/trait_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Utility = preload("res://scripts/action_utility.gd")
const WorkRules = preload("res://scripts/work_skill_rules.gd")
const Need = preload("res://scripts/need_type.gd")
const NEED_GROWTH_CHANNEL := "need_growth_rate"
const MOOD_CHANNEL := "mood.offset"

static func valid_moodlet_modifier(modifier: Dictionary) -> bool:
	if modifier.get("channel") == MOOD_CHANNEL:
		var value: Variant = modifier.get("value")
		return modifier.size() == 2 and (value is int or value is float) and is_finite(float(value))
	if modifier.get("channel") != NEED_GROWTH_CHANNEL: return true # Legacy opaque channels stay inert.
	if modifier.size()!=3 or not modifier.get("need") is String or modifier.need.to_upper() not in Need.Type: return false
	var factor: Variant = modifier.get("multiplier")
	return (factor is int or factor is float) and is_finite(float(factor)) and factor>=0

static func moodlet_numeric_state(entries: Array, minute: int) -> Dictionary:
	var factors: Dictionary = {}
	var invalid: Dictionary = {}
	var next_change := -1
	var offsets: Array[float] = []
	for entry: Dictionary in entries:
		var numeric: Array = entry.modifiers.filter(func(row):return row.get("channel") in [NEED_GROWTH_CHANNEL,MOOD_CHANNEL] and valid_moodlet_modifier(row))
		if numeric.is_empty() or (entry.expires_at_minute!=null and minute>=entry.expires_at_minute): continue
		if minute<entry.created_minute:
			if next_change<0 or entry.created_minute<next_change: next_change=entry.created_minute
			continue
		if entry.expires_at_minute!=null and (next_change<0 or entry.expires_at_minute<next_change): next_change=entry.expires_at_minute
		for modifier: Dictionary in numeric:
			if modifier.channel == MOOD_CHANNEL:
				offsets.append(float(modifier.value))
				continue
			var type: int = Need.Type[modifier.need.to_upper()]
			if invalid.has(type): continue
			var product: float = float(factors.get(type,1.0))*modifier.multiplier
			if not is_finite(product):
				factors.erase(type);invalid[type]=true # An unrepresentable channel has no numeric effect.
			else: factors[type]=product
	# Normalise the signed sum to avoid inf-inf for very large finite inputs.
	var maximum := 0.0
	for offset in offsets: maximum = maxf(maximum,absf(offset))
	var total := 0.0
	if maximum > 1.0e308 / maxi(offsets.size(),1):
		for offset in offsets: total += offset / maximum
		total *= maximum
	else:
		for offset in offsets: total += offset
	return {"factors":factors,"mood_offset":total,"next_change":next_change}

static func mood_from_offset(offset: float) -> float:
	return clampf(50.0 + offset, 0.0, 100.0)

static func need_growth_rate(type: int, base_rate: float, factors: Dictionary) -> float:
	if base_rate<=0: return base_rate
	var effective: float = base_rate*float(factors.get(type,1.0))
	return effective if is_finite(effective) else base_rate
static func work_rate(resident: RefCounted, rules: WorkRules, active_operation: bool = true) -> float:
	if rules == null: return -1.0
	var percent := rules.efficiency_percent(resident)
	if not is_finite(percent) or percent < 100.0 or percent > 150.0: return -1.0
	var multiplier := 1.0
	if active_operation:
		if resident.has_trait(Trait.Type.HASTY): multiplier = Balance.HASTY_WORK_RATE_MULTIPLIER
		elif resident.has_trait(Trait.Type.DELIBERATE): multiplier = Balance.DELIBERATE_WORK_RATE_MULTIPLIER
	return percent / 100.0 * multiplier

static func fatigue_need_rate(resident: RefCounted, base_rate: float, active_work: bool) -> float:
	if base_rate > 0 and active_work:
		if resident.has_trait(Trait.Type.HASTY): return base_rate * Balance.HASTY_WORK_FATIGUE_MULTIPLIER
		if resident.has_trait(Trait.Type.DELIBERATE): return base_rate * Balance.DELIBERATE_WORK_FATIGUE_MULTIPLIER
	return base_rate

enum Action { WORK, EAT, SOCIAL, WANDER, LEISURE, REST }
static func opinion_delta(resident: RefCounted, base_delta: int) -> float:
	if resident.has_trait(Trait.Type.HOTHEADED): return base_delta * Balance.HOTHEADED_OPINION_DELTA_MULTIPLIER
	if resident.has_trait(Trait.Type.CALM): return base_delta * Balance.CALM_OPINION_DELTA_MULTIPLIER
	return float(base_delta)
static func social_partner_multiplier(resident: RefCounted, opinion: int) -> float:
	var bounded := clampi(opinion, Balance.OPINION_MIN, Balance.OPINION_MAX)
	if resident != null:
		if resident.has_trait(Trait.Type.SOCIABLE):
			return Balance.SOCIABLE_SOCIAL_PARTNER_BASE - Balance.SOCIAL_PARTNER_OPINION_FACTOR * abs(bounded)
		if resident.has_trait(Trait.Type.INTROVERTED):
			return 1.0 + Balance.INTROVERTED_SOCIAL_PARTNER_OPINION_FACTOR * bounded
	return 1.0 + Balance.SOCIAL_PARTNER_OPINION_FACTOR * bounded

static func social_company_multiplier(resident: RefCounted, count: int) -> float:
	if resident != null and count > 1:
		if resident.has_trait(Trait.Type.SOCIABLE): return pow(Balance.SOCIABLE_SOCIAL_COMPANY_FACTOR, count - 1)
		if resident.has_trait(Trait.Type.INTROVERTED): return pow(Balance.INTROVERTED_SOCIAL_COMPANY_FACTOR, count - 1)
	return 1.0

static func social_partner_need_multiplier(resident: RefCounted, deficit: int) -> float:
	return 1.0 + clampi(deficit, 0, 100) * Balance.CARING_SOCIAL_PARTNER_DEFICIT_FACTOR if resident != null and resident.has_trait(Trait.Type.CARING) else 1.0

static func social_partner_weight(resident: RefCounted, opinions: Array[int], social_deficits: Array[int] = []) -> float:
	if opinions.is_empty(): return 1.0
	var total := 0.0
	for index in opinions.size():
		var deficit: int = social_deficits[index] if index < social_deficits.size() else 0
		total += social_partner_multiplier(resident, opinions[index]) * social_partner_need_multiplier(resident, deficit)
	# Average individual modifiers before applying company size: opposite opinions do not cancel.
	return total / opinions.size() * social_company_multiplier(resident, opinions.size())

static func social_need_rate(resident: RefCounted, base_rate: float, caring_partner: bool = false) -> float:
	# Positive rates grow the deficit; negative rates restore it while talking.
	var multiplier := 1.0
	for trait_type in resident.traits:
		match trait_type:
			Trait.Type.SOCIABLE:
				multiplier *= Balance.SOCIABLE_SOCIAL_RECOVERY_MULTIPLIER if base_rate < 0 else Balance.SOCIABLE_SOCIAL_DEPLETION_MULTIPLIER
			Trait.Type.INTROVERTED:
				multiplier *= Balance.INTROVERTED_SOCIAL_RECOVERY_MULTIPLIER if base_rate < 0 else Balance.INTROVERTED_SOCIAL_DEPLETION_MULTIPLIER
	if base_rate < 0 and caring_partner: multiplier *= Balance.CARING_PARTNER_SOCIAL_RECOVERY_MULTIPLIER
	return base_rate * multiplier

static func action_utility(resident: RefCounted, action: Action, base: float) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		match trait_type:
			Trait.Type.SOCIABLE:
				if action == Action.SOCIAL: multiplier *= Balance.SOCIABLE_SOCIAL_UTILITY_MULTIPLIER
			Trait.Type.INTROVERTED:
				if action == Action.SOCIAL: multiplier *= Balance.INTROVERTED_SOCIAL_UTILITY_MULTIPLIER
			Trait.Type.INDUSTRIOUS:
				if action == Action.WORK: multiplier *= Balance.INDUSTRIOUS_WORK_UTILITY_MULTIPLIER
			Trait.Type.LAZY:
				if action == Action.WORK: multiplier *= Balance.LAZY_WORK_UTILITY_MULTIPLIER
				if action == Action.REST: multiplier *= Balance.LAZY_REST_UTILITY_MULTIPLIER
			Trait.Type.GLUTTON:
				if action == Action.EAT: multiplier *= Balance.GLUTTON_EAT_UTILITY_MULTIPLIER
			Trait.Type.RESTLESS:
				if action == Action.WANDER: multiplier *= Balance.RESTLESS_WANDER_UTILITY_MULTIPLIER
			Trait.Type.FOOLISH:
				if action == Action.LEISURE: multiplier *= Balance.FOOLISH_LEISURE_UTILITY_MULTIPLIER
	return maxf(base * multiplier, 0.0)
static func leisure_need_rate(resident: RefCounted, base_rate: float, ordinary_idle: bool) -> float:
	if base_rate < 0 and resident.has_trait(Trait.Type.FOOLISH):
		return base_rate * Balance.FOOLISH_LEISURE_RECOVERY_MULTIPLIER
	if ordinary_idle and base_rate > 0 and resident.has_trait(Trait.Type.RESTLESS):
		return base_rate * Balance.RESTLESS_IDLE_LEISURE_GROWTH_MULTIPLIER
	return base_rate
static func eat_threshold(resident: RefCounted, base: int = Balance.EAT_MIN_HUNGER) -> int:
	var addition := 0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.GLUTTON: addition += Balance.GLUTTON_EAT_THRESHOLD_MODIFIER
	return clampi(base + addition, 0, 99)
static func eat_utility(resident: RefCounted) -> float:
	return action_utility(resident, Action.EAT, Utility.eat(resident.hunger, eat_threshold(resident)))
static func movement_speed(resident: RefCounted, base: float) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.RESTLESS: multiplier *= Balance.RESTLESS_MOVEMENT_SPEED_MULTIPLIER
	return maxf(base * multiplier, 0.0)
static func selector_candidate_ratio(resident: RefCounted, base: float = Balance.UTILITY_CANDIDATE_RATIO) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.FOOLISH: multiplier *= Balance.FOOLISH_UTILITY_CANDIDATE_RATIO / Balance.UTILITY_CANDIDATE_RATIO
		if trait_type == Trait.Type.PRUDENT: multiplier *= Balance.PRUDENT_UTILITY_CANDIDATE_RATIO / Balance.UTILITY_CANDIDATE_RATIO
	return clampf(base * multiplier, 0.0, 1.0)
static func selector_random_exponent(resident: RefCounted, base: float = Balance.UTILITY_RANDOM_EXPONENT) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.FOOLISH: multiplier *= Balance.FOOLISH_UTILITY_RANDOM_EXPONENT / Balance.UTILITY_RANDOM_EXPONENT
		if trait_type == Trait.Type.PRUDENT: multiplier *= Balance.PRUDENT_UTILITY_RANDOM_EXPONENT / Balance.UTILITY_RANDOM_EXPONENT
	return maxf(base * multiplier, 0.0)
