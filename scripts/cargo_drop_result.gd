extends RefCounted
## Result of one trusted placement attempt. FAILED never permits cargo destruction.
enum Status { FAILED, PLACED, DISCARDED }
static func completed(result: Variant) -> bool:
	return typeof(result)==TYPE_INT and result in [Status.PLACED,Status.DISCARDED]
