extends RefCounted
## Calendar definitions and a small visual palette; GameTime owns elapsed time.
enum Type { SPRING, SUMMER, AUTUMN, WINTER }
const DAYS_PER_SEASON := 3
const NAMES := ["Весна", "Лето", "Осень", "Зима"]
# Spring is supplied from the authored grass material, never replaced by a new RGB.
const GRASS_COLORS := {
	Type.SUMMER: Color(0.22,0.62,0.20),
	Type.AUTUMN: Color(0.51,0.59,0.44),
	Type.WINTER: Color.WHITE,
}
static func for_day(day: int) -> Type:
	# Deliberate whole-day/season arithmetic preserves exact large integer calendars.
	@warning_ignore("integer_division")
	return ((maxi(day,1)-1)/DAYS_PER_SEASON)%Type.size() as Type
static func display_name(season: Type) -> String:
	return NAMES[season]
static func palette(season: Type, spring_grass: Color) -> Dictionary:
	return {"grass":GRASS_COLORS.get(season,spring_grass)}
