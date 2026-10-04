extends RefCounted
## Presentation-only descriptions; simulation and future AI use numeric data.
static func hunger_description(value: int) -> String:
	if value < 25:
		return "Сыт"
	if value < 50:
		return "Немного голоден"
	if value < 75:
		return "Голоден"
	return "Очень голоден"

static func fatigue_description(value: int) -> String:
	if value < 25:
		return "Отдохнувший"
	if value < 50:
		return "Немного устал"
	if value < 75:
		return "Устал"
	return "Очень устал"

static func mood_description(value: int) -> String:
	if value < 25:
		return "Очень плохое"
	if value < 50:
		return "Плохое"
	if value < 75:
		return "Хорошее"
	return "Отличное"
