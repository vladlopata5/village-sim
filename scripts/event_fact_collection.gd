extends RefCounted
## Immutable, validated data snapshot. No resident/store references or callbacks.
var _pages: Array = []
var _size := 0

func _init(records: Array) -> void:
	for index in range(0, records.size(), 256): _pages.append(records.slice(index, index + 256).duplicate(true))
	_size = records.size()

func size() -> int: return _size
func page_count() -> int: return _pages.size()
func page(index: int) -> Array: return _pages[index].duplicate(true)
