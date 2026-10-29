extends RefCounted
## Standard work minutes, independent of clocks, workers and task ownership.
const EPSILON := 0.00000001

static func reached(progress: float, required: float) -> bool:
	return progress >= required or absf(progress - required) <= EPSILON

static func bounded(progress: float, required: float) -> float:
	var result := clampf(progress, 0.0, required)
	if reached(result, required): return required
	return 0.0 if result <= EPSILON else result

static func advance(progress: float, work: float, required: float) -> float:
	if not is_finite(work) or work <= 0.0: return progress
	return bounded(progress + work, required)

static func whole_floor(value: float) -> int:
	var nearest := roundf(value)
	return floori(nearest if absf(value-nearest) <= EPSILON else value)

static func whole_ceil(value: float) -> int:
	var nearest := roundf(value)
	return ceili(nearest if absf(value-nearest) <= EPSILON else value)

static func display_minutes(value: float) -> String:
	return str(roundi(value)) if absf(value-roundf(value)) <= EPSILON else String.num(value,2)
