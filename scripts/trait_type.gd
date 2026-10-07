extends RefCounted
## Permanent identities, independent of translated display names.
enum Type { SOCIABLE, INTROVERTED, INDUSTRIOUS, LAZY, GLUTTON, RESTLESS, FOOLISH }
static func display_name(trait_type: Type) -> String:
	match trait_type:
		Type.SOCIABLE: return "Общительный"
		Type.INTROVERTED: return "Нелюдимый"
		Type.INDUSTRIOUS: return "Трудолюбивый"
		Type.LAZY: return "Ленивый"
		Type.GLUTTON: return "Обжора"
		Type.RESTLESS: return "Неусидчивый"
		Type.FOOLISH: return "Балбес"
		_: return ""
static func conflict(trait_type: Type) -> int:
	match trait_type:
		Type.SOCIABLE: return Type.INTROVERTED
		Type.INTROVERTED: return Type.SOCIABLE
		Type.INDUSTRIOUS: return Type.LAZY
		Type.LAZY: return Type.INDUSTRIOUS
		_: return -1
