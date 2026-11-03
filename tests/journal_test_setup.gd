extends RefCounted
static func add(person: RefCounted, text: String, minute: int, permanent: bool = false, strength: float = 30) -> bool:
	return person.memories.add({"id":JSON.stringify([text,minute]),"type":"test","topic":"test","text":text,"created_minute":minute,"source_occurrence_id":"test/input","strength":strength,"permanent":permanent,"tags":[],"provenance":{"kind":"experienced"},"context":{"subject":text}})
