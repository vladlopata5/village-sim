extends RefCounted
## Small, explicit name vocabulary; no gender inference or morphology guessing.
const CASES := ["nom", "gen", "dat", "acc", "ins", "prep"]
const MALE_HARD := ["Иван", "Степан", "Борис", "Александр", "Владимир", "Виктор", "Олег", "Роман", "Максим", "Антон", "Денис"]
const FEMALE_A := ["Анна", "Марина", "Елена", "Ольга", "Ирина", "Нина", "Светлана", "Татьяна", "Вера", "Эмма", "Алиса"]
const SPECIAL := {
	"Фёдор": ["Фёдор", "Фёдора", "Фёдору", "Фёдора", "Фёдором", "Фёдоре"],
	"Пётр": ["Пётр", "Петра", "Петру", "Петра", "Петром", "Петре"],
	"Лев": ["Лев", "Льва", "Льву", "Льва", "Львом", "Льве"],
	"Павел": ["Павел", "Павла", "Павлу", "Павла", "Павлом", "Павле"],
	"Сергей": ["Сергей", "Сергея", "Сергею", "Сергея", "Сергеем", "Сергее"],
	"Андрей": ["Андрей", "Андрея", "Андрею", "Андрея", "Андреем", "Андрее"],
	"Дарья": ["Дарья", "Дарьи", "Дарье", "Дарью", "Дарьей", "Дарье"],
	"Мария": ["Мария", "Марии", "Марии", "Марию", "Марией", "Марии"],
	"Юлия": ["Юлия", "Юлии", "Юлии", "Юлию", "Юлией", "Юлии"],
	"Софья": ["Софья", "Софьи", "Софье", "Софью", "Софьей", "Софье"],
	"Никита": ["Никита", "Никиты", "Никите", "Никиту", "Никитой", "Никите"]
}
const FEMALE_SPECIAL := ["Дарья", "Мария", "Юлия", "Софья"]
const PRONOUNS := {
	"masculine": ["он", "его", "ему", "его", "им", "нём"],
	"feminine": ["она", "её", "ей", "её", "ею", "ней"]
}

static func valid_forms(case_forms: Variant, name: String) -> bool:
	if not case_forms is Dictionary or case_forms.size() != CASES.size() or case_forms.get("nom") != name: return false
	for key in CASES:
		if not case_forms.get(key) is String or case_forms[key].strip_edges().is_empty(): return false
	return true

static func forms(name: String, gender: String, explicit: Dictionary = {}, indeclinable: bool = false) -> Dictionary:
	if indeclinable: return _pack([name, name, name, name, name, name])
	if not explicit.is_empty(): return explicit.duplicate() if valid_forms(explicit, name) else {}
	if gender not in PRONOUNS: return _pack([name, name, name, name, name, name])
	if SPECIAL.has(name) and ((name in FEMALE_SPECIAL) == (gender == "feminine")):
		return _pack(SPECIAL[name])
	if gender == "masculine" and name in MALE_HARD:
		return _pack([name, name + "а", name + "у", name + "а", name + "ом", name + "е"])
	if gender == "feminine" and name in FEMALE_A:
		var stem := name.left(-1)
		return _pack([name, stem + ("и" if stem[-1] in "гкхжчшщ" else "ы"), stem + "е", stem + "у", stem + "ой", stem + "е"])
	# Unrecognised names (including multi-part ones) are left literal and safe.
	return _pack([name, name, name, name, name, name])

static func with_name(instrumental: String) -> String:
	var word := instrumental.to_lower()
	var expanded := word.begins_with("льв") or word.begins_with("щ")
	if word.length() > 1 and word[0] in "сзшж" and word[1] not in "аеёиоуыэюя": expanded = true
	return ("со " if expanded else "с ") + instrumental

static func about_name(prepositional: String) -> String:
	# Е/Ё/Ю/Я begin with a consonant sound: о Елене, о Юлии.
	return ("об " if not prepositional.is_empty() and prepositional[0].to_lower() in "аоиуэ" else "о ") + prepositional

static func _pack(values: Array) -> Dictionary:
	var result := {}
	for index in CASES.size(): result[CASES[index]] = values[index]
	return result
