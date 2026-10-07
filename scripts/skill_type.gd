extends RefCounted
## Skills describe accumulated experience, independently of assigned profession.
enum Type { GATHERING, CONSTRUCTION, LOGISTICS }
static func display_name(skill: Type) -> String:
	match skill:
		Type.GATHERING: return "Собирательство"
		Type.CONSTRUCTION: return "Строительство"
		Type.LOGISTICS: return "Логистика"
		_: return ""
