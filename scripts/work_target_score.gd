extends RefCounted
## All points are simulation-space XZ coordinates. No route/geometry work here.
# Fixed precision makes comparison transitive, unlike pairwise approximate equality.
# 0.001 simulation units = 0.00004 world units with the current coordinate scale.
const PRECISION := 0.001
enum Column { PRIORITY, SCORE, WORKER, KEY, TARGET }

static func measure(worker: Vector2, building: Vector2, target: Vector2) -> Dictionary:
	var distance := worker.distance_to(target)
	return {"score":distance+building.distance_to(target),"worker":distance}

static func ordered(targets: Array, worker: Vector2, building: Vector2, position: Callable, stable_key: Callable, priority: Callable = Callable()) -> Array:
	var rows: Array=[]
	for target in targets:
		var row := measure(worker,building,position.call(target))
		var key: Variant=stable_key.call(target)
		rows.append([int(priority.call(target)) if priority.is_valid() else 0,roundi(row.score/PRECISION),roundi(row.worker/PRECISION),key if key is Vector2i or key is Vector2 else String(key),target])
	rows.sort_custom(_less)
	return rows.map(func(row):return row[Column.TARGET])

static func _less(a: Array, b: Array) -> bool:
	if a[Column.PRIORITY]!=b[Column.PRIORITY]:return a[Column.PRIORITY]<b[Column.PRIORITY]
	if a[Column.SCORE]!=b[Column.SCORE]:return a[Column.SCORE]<b[Column.SCORE]
	if a[Column.WORKER]!=b[Column.WORKER]:return a[Column.WORKER]<b[Column.WORKER]
	var first: Variant=a[Column.KEY];var second: Variant=b[Column.KEY]
	if first is Vector2i or first is Vector2:
		return first.y<second.y or (first.y==second.y and first.x<second.x)
	return first<second
