extends RefCounted
## Permanent identities, independent of translated display names.
enum Type { SOCIABLE, INTROVERTED, INDUSTRIOUS, LAZY, GLUTTON, RESTLESS, FOOLISH, PRUDENT, CARING, HOTHEADED, CALM, HASTY, DELIBERATE }
enum GrammaticalGender { MASCULINE, FEMININE }
# Only implemented traits participate in random character/preference generation.
const GENERATION_POOL = [Type.SOCIABLE, Type.INTROVERTED, Type.INDUSTRIOUS, Type.LAZY, Type.GLUTTON, Type.RESTLESS, Type.FOOLISH, Type.PRUDENT, Type.HOTHEADED, Type.CALM]
# Masculine adjective/noun, feminine adjective/noun. Identity is separate from wording.
const FORMS = {
	Type.INDUSTRIOUS: ["Трудолюбивый", "Трудяга", "Трудолюбивая", "Трудяга"],
	Type.LAZY: ["Ленивый", "Лентяй", "Ленивая", "Лентяйка"],
	Type.SOCIABLE: ["Общительный", "Болтун", "Общительная", "Болтунья"],
	Type.INTROVERTED: ["Замкнутый", "Одиночка", "Замкнутая", "Одиночка"],
	Type.GLUTTON: ["Прожорливый", "Обжора", "Прожорливая", "Обжора"],
	Type.RESTLESS: ["Непоседливый", "Непоседа", "Непоседливая", "Непоседа"],
	Type.FOOLISH: ["Чудаковатый", "Балбес", "Чудаковатая", "Балбеска"],
	Type.PRUDENT: ["Рассудительный", "Прагматик", "Рассудительная", "Прагматичка"],
	Type.CARING: ["Заботливый", "Добряк", "Заботливая", "Добрячка"],
	Type.HOTHEADED: ["Вспыльчивый", "Задира", "Вспыльчивая", "Задира"],
	Type.CALM: ["Невозмутимый", "Флегматик", "Невозмутимая", "Флегматичка"],
	Type.HASTY: ["Торопливый", "Торопыга", "Торопливая", "Торопыга"],
	Type.DELIBERATE: ["Неторопливый", "Копуша", "Неторопливая", "Копуша"],
}
static func adjective(trait_type: Type, gender: GrammaticalGender = GrammaticalGender.MASCULINE) -> String:
	if not FORMS.has(trait_type): return ""
	return FORMS[trait_type][2 if gender == GrammaticalGender.FEMININE else 0]
static func noun(trait_type: Type, gender: GrammaticalGender = GrammaticalGender.MASCULINE) -> String:
	if not FORMS.has(trait_type): return ""
	return FORMS[trait_type][3 if gender == GrammaticalGender.FEMININE else 1]
static func description(traits: Array, gender: GrammaticalGender = GrammaticalGender.MASCULINE) -> String:
	if traits.is_empty(): return ""
	if traits.size() == 1: return adjective(traits[0], gender)
	var words := PackedStringArray()
	for index in range(traits.size() - 1): words.append(adjective(traits[index], gender).to_lower())
	words.append(noun(traits[-1], gender).to_lower())
	var text := " ".join(words)
	return text.left(1).to_upper() + text.substr(1)
static func compatible(traits: Array) -> bool:
	var seen: Array = []
	for trait_type in traits:
		if typeof(trait_type) != TYPE_INT or trait_type not in Type.values() or seen.has(trait_type) or seen.has(conflict(trait_type)): return false
		seen.append(trait_type)
	return true
static func display_name(trait_type: Type) -> String:
	match trait_type:
		Type.SOCIABLE: return "Общительный"
		Type.INTROVERTED: return "Нелюдимый"
		Type.INDUSTRIOUS: return "Трудолюбивый"
		Type.LAZY: return "Ленивый"
		Type.GLUTTON: return "Обжора"
		Type.RESTLESS: return "Неусидчивый"
		Type.FOOLISH: return "Балбес"
		Type.PRUDENT: return "Рассудительный"
		Type.CARING: return "Заботливый"
		Type.HOTHEADED: return "Вспыльчивый"
		Type.CALM: return "Невозмутимый"
		Type.HASTY: return "Торопыга"
		Type.DELIBERATE: return "Неторопливый"
		_: return ""
static func conflict(trait_type: Type) -> int:
	match trait_type:
		Type.SOCIABLE: return Type.INTROVERTED
		Type.INTROVERTED: return Type.SOCIABLE
		Type.INDUSTRIOUS: return Type.LAZY
		Type.LAZY: return Type.INDUSTRIOUS
		Type.FOOLISH: return Type.PRUDENT
		Type.PRUDENT: return Type.FOOLISH
		Type.HOTHEADED: return Type.CALM
		Type.CALM: return Type.HOTHEADED
		Type.HASTY: return Type.DELIBERATE
		Type.DELIBERATE: return Type.HASTY
		_: return -1
