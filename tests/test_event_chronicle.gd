extends "res://tests/test_event_effects.gd"
const History = preload("res://scripts/settlement_chronicle.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const EventSetup = preload("res://tests/event_test_setup.gd")
class RejectingHistory extends History:
	var validations := 0
	func prepare_add(record: Dictionary) -> Dictionary:
		validations += 1
		return {} if validations > 1 else super.prepare_add(record)

func _run() -> void:
	contract()
	atomic_history()
	calendar_and_ownership()
	variants_and_rng()
	print("Event chronicle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func contract() -> void:
	for private_diary in [false,true]:
		var f := fixture(); var data := content(f.service)
		if not private_diary: data.definitions[0].text.erase("diary_main")
		load_content(f,data)
		var observed: Array = []
		f.service.chronicle.changed.connect(func(id):
			observed.append([f.service.replay(id).status,f.service.chronicle.size(),f.a.memories.size(),f.a.moodlets.size()])
			f.service.executor.publish(id))
		check(raise_rank(f).status == "completed", "Event can succeed with/without a personal diary")
		check(f.service.chronicle.size() == 1 and f.a.diary_entries.size() == int(private_diary), "Mandatory world / optional personal record")
		check(observed == [["completed",1,1,1]], "Chronicle callback sees all writes and completed metadata; nested publish cannot duplicate")
		var context: Dictionary = f.service.last_occurrence(); var draws: int = f.service.executor.rng.draws
		f.service.replay(context.occurrence_id); f.service.executor.execute({},context,636,f.a); f.service.executor.publish(context.occurrence_id)
		check(f.service.chronicle.size() == 1 and f.service.executor.rng.draws == draws and observed.size() == 1, "All duplicate delivery paths do not append or notify")
		cleanup(f)
	for channel in ["chronicle","diary_main"]:
		var definition := EventSetup.definition(); definition.text.erase(channel)
		var catalog := Catalog.new()
		check(catalog.load_data({"definitions":[definition]},EventSetup.registry()) == (channel == "diary_main"), "Mandatory history / absence of diary is intentional")
	for bad in ["", [], ["ok","{actor.name:bad}"]]:
		var definition := EventSetup.definition(); definition.text.chronicle = bad
		check(not Catalog.new().load_data({"definitions":[definition]},EventSetup.registry()), "Invalid mandatory history rejected at catalog")
	# A malformed bundle must be rejected even if its chance is0.
	for scenario in ["chance","duplicate","nested_chance","empty"]:
		var definition := EventSetup.definition()
		var bundle := {"id":"g","chance":0.0,"effects":[{"op":"chat.say","owner":{"role":"actor"},"text":"Hi"}]}
		definition.effect_groups = [bundle]
		if scenario == "chance": bundle.chance = -0.1
		if scenario == "duplicate": definition.effect_groups.append(bundle.duplicate(true))
		if scenario == "nested_chance": bundle.effects[0].chance = 1.0
		if scenario == "empty": bundle.effects = []
		check(not Catalog.new().load_data({"definitions":[definition]},EventSetup.registry()), "Invalid shared group rejected: " + scenario)

func atomic_history() -> void:
	for scenario in ["text","store","recipient"]:
		var f := fixture(); var data := content(f.service)
		if scenario == "text": data.definitions[0].text.chronicle = "{payload.missing}"
		if scenario == "store": f.service.executor.chronicle = RejectingHistory.new()
		if scenario == "recipient":
			f.service.executor.rng.on_draw = func(n):
				if n == 2: f.control.unregister_resident("a")
		load_content(f,data)
		var notices: Array = []
		f.service.chronicle.changed.connect(func(_id): notices.append("history"))
		f.a.diary_changed.connect(func(): notices.append("diary"))
		f.a.memories.changed.connect(func(_id): notices.append("memory"))
		check(raise_rank(f).status != "completed", "History preparation or final validation can reject")
		check(f.service.chronicle.size() == 0 and f.a.diary_entries.is_empty() and f.a.memories.size() == 0 and f.a.moodlets.size() == 0 and notices.is_empty() and f.service.cooldown_history().is_empty(), "History participates in whole transaction: " + scenario)
		cleanup(f)

func calendar_and_ownership() -> void:
	var history := History.new()
	for row in [["later",5761],["earlier",1439],["midnight",1440],["tie",1440],["spring",17280]]:
		var raw := {"id":row[0],"definition_id":"test","minute":row[1],"text":"Событие.","participants":[{"kind":"resident","id":"a"}]}
		var prepared := history.prepare_add(raw); check(not prepared.is_empty(), "Prepare bounded history record")
		history._apply_event_add(prepared)
		check(history.prepare_add(raw).is_empty(), "Store itself refuses duplicate occurrence")
	var entries := history.entries()
	check(entries.map(func(entry):return entry.id) == ["earlier","midnight","tie","later","spring"], "Chronological order; stable commit order for equal minute")
	entries[0].text = "Changed"; entries[0].participants[0].id = "spoof"
	check(history.get_entry("earlier").text == "Событие." and history.get_entry("earlier").participants[0].id == "a", "Consumers cannot modify stored history")
	check(History.date_text(1439) == "День 1 · Весна" and History.time_text(1439) == "23:59" and History.date_text(1440) == "День 2 · Весна" and History.time_text(1440) == "00:00", "True absolute midnight")
	check(History.date_text(4320) == "День 4 · Лето" and History.date_text(17280) == "День 13 · Весна", "Existing3-day seasons and year wrap; absolute day is not reset")

func variants_and_rng() -> void:
	var trace: Array = []
	for with_history_variant in [false,true]:
		var f := fixture(); var data := content(f.service)
		if with_history_variant: data.definitions[0].text.chronicle = ["Первый вариант.",{"text":"Второй вариант.","weight":3}]
		else: data.definitions[0].text.chronicle = "Первый вариант."
		load_content(f,data)
		f.service.executor.rng.values = [0.1,0.1,0.9]
		check(raise_rank(f).status == "completed", "Variants use the common renderer")
		check(f.service.executor.rng.draws == (3 if with_history_variant else 2), "Single chronicle does not change any existing RNG draw")
		check(f.service.chronicle.entries()[0].text == ("Второй вариант." if with_history_variant else "Первый вариант."), "Weighted chronicle choice")
		trace.append([f.a.memories.find(),f.a.moodlets.find(),f.a.diary_entries[0].text,f.rng.draws])
		cleanup(f)
	check(trace[0] == trace[1], "New wording cannot change effects or previous diary choices of this event")
