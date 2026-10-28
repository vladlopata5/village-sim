extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Rules = preload("res://scripts/work_skill_rules.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	model()
	calculations()
	requirements_and_rewards()
	invalid_rules()
	atomic_notifications()
	print("Skill rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func model() -> void:
	var resident := Data.new("new", "Тест", 20)
	check(Skill.Type.size() == 15 and resident._skill_xp.size() == 15, "One complete fifteen-skill model")
	var names: Array = []
	for skill in Skill.Type.values():
		check(resident.get_skill_xp(skill) == 0 and resident.get_skill_rank(skill) == Skill.Rank.PROFANE, "All skills start at zero, regardless of profession")
		check(not Skill.display_name(skill).is_empty() and Skill.display_name(skill) not in names, "Unique readable names")
		names.append(Skill.display_name(skill))
	check(not resident.has_method("get_skill_level"), "No legacy level API or parallel progression")
	var notices: Array = []
	var raises: Array = []
	resident.skill_changed.connect(func(skill, amount, previous): notices.append([skill, amount, previous]))
	resident.skill_raised.connect(func(id, skill, previous, next): raises.append([id, skill, previous, next]))
	check(not resident.call("add_skill_xp", -1, 1) and not resident.add_skill_xp(Skill.Type.MINING, -1) and not resident.add_skill_xp(Skill.Type.MINING, 0), "Invalid and nonpositive additions are rejected")
	check(not resident.add_skill_xp(Skill.Type.MINING, 1, -1) and notices.is_empty() and raises.is_empty(), "Invalid training cap produces no signals")
	check(resident.add_skill_xp(Skill.Type.MINING, 399) and raises.is_empty(), "XP below the first title threshold is not a rank fact")
	check(resident.add_skill_xp(Skill.Type.MINING, 2, 400) and resident.get_skill_xp(Skill.Type.MINING) == 400 and notices.back()[1] == 1, "Training cap reports actual, not requested, gain")
	check(raises == [[1, Skill.Type.MINING, 0, 1]], "One first rank transition")
	check(not resident.add_skill_xp(Skill.Type.MINING, 100, 300) and resident.get_skill_xp(Skill.Type.MINING) == 400, "Lower training cap never reduces existing XP")
	check(resident.add_skill_xp(Skill.Type.MINING, 9223372036854775807) and resident.get_skill_xp(Skill.Type.MINING) == 10000, "Huge addition cannot overflow the global cap")
	check(raises.back() == [2, Skill.Type.MINING, 1, 4], "A large jump creates one fact, not fictitious intermediate awards")
	var count := notices.size()
	check(not resident.add_skill_xp(Skill.Type.MINING, 1) and not resident.add_skill_xp(Skill.Type.MINING, 1, 9223372036854775807), "Global cap remains effective above a reward cap")
	check(notices.size() == count and raises.size() == 2, "Cap no-op has no notification or fact")
	for row in [[0,0], [399,0], [400,1], [999,1], [1000,2], [1799,2], [1800,3], [2999,3], [3000,4], [10000,4]]:
		check(Skill.rank_for_xp(row[0]) == row[1], "Inclusive title boundary " + str(row[0]))
	check(Skill.rank_name(Skill.Rank.PROFANE) == "Профан" and Skill.rank_name(Skill.Rank.MASTER) == "Мастер", "Title presentation")

func calculations() -> void:
	for row in [[0,100.0], [100,105.0], [400,110.0], [2500,125.0], [10000,150.0]]:
		check(is_equal_approx(Skill.efficiency_percent(row[0]), row[1]), "Reference efficiency " + str(row[0]))
	check(Skill.efficiency_percent(-1) == 100.0 and Skill.efficiency_percent(20000) == 150.0, "Pure calculation clamps its input to the XP domain")
	check(is_equal_approx(Skill.efficiency_percent(1), 100.5), "Small gains retain fractional efficiency")
	var resident := Data.new("weights", "Тест", 20)
	resident.add_skill_xp(Skill.Type.FORESTRY, 10000)
	var rules := Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 25}, {"skill": Skill.Type.FORESTRY, "weight_percent": 75}])
	check(rules.is_valid() and is_equal_approx(rules.efficiency_percent(resident), 137.5), "Average skill efficiencies, not XP, using independent weights")
	var single := Rules.new([], [{"skill": Skill.Type.FORESTRY, "weight_percent": 100}])
	check(single.efficiency_percent(resident) == 150.0, "Single skill uses the same percent function")
	check(Rules.new().efficiency_percent(resident) == 100.0, "No contributing skills is neutral")
	var before: Dictionary = resident._skill_xp.duplicate()
	for repeat in 10:
		check(rules.efficiency_percent(resident) == 137.5 and rules.can_perform(resident), "Pure repeatable queries")
	check(resident._skill_xp == before, "Queries do not train skills or change the resident")
	resident.add_skill_xp(Skill.Type.MINING, 2500)
	check(is_equal_approx(rules.efficiency_percent(resident), 143.75), "Queries use current XP, without a stale efficiency cache")

func requirements_and_rewards() -> void:
	var resident := Data.new("rules", "Тест", 20)
	var input := [{"skill": Skill.Type.FARMING, "min_xp": 400}, {"skill": Skill.Type.GATHERING, "min_xp": 1}]
	var rules := Rules.new(input, [{"skill": Skill.Type.FORESTRY, "weight_percent": 100}], [
		{"skill": Skill.Type.CRAFTING, "amount": 700, "training_cap": 500},
		{"skill": Skill.Type.COOKING, "amount": 1, "training_cap": 10000}])
	input.clear()
	check(rules.requirements.size() == 2 and rules.is_valid(), "Rules own a copy of input data")
	check(not rules.can_perform(resident), "All minimum requirements are required")
	resident.add_skill_xp(Skill.Type.FARMING, 400)
	check(not rules.can_perform(resident), "Meeting only one requirement is insufficient")
	resident.add_skill_xp(Skill.Type.GATHERING, 1)
	check(rules.can_perform(resident) and rules.efficiency_percent(resident) == 100.0, "Requirements and efficiency skills are independent")
	check(rules.reward_deltas(resident) == {Skill.Type.CRAFTING: 500, Skill.Type.COOKING: 1} and resident.get_skill_xp(Skill.Type.CRAFTING) == 0, "Preview applies each training cap without mutation")
	check(resident.award_skill_xp(rules) and resident.get_skill_xp(Skill.Type.CRAFTING) == 500 and resident.get_skill_xp(Skill.Type.COOKING) == 1, "One operation can award several unrelated skills")
	check(resident.award_skill_xp(rules) and resident.get_skill_xp(Skill.Type.CRAFTING) == 500 and resident.get_skill_xp(Skill.Type.COOKING) == 2, "One exhausted training limit does not suppress another reward")
	var zero := Rules.new([], [], [{"skill": Skill.Type.CRAFTING, "amount": 1, "training_cap": 0}])
	check(not resident.award_skill_xp(zero) and resident.get_skill_xp(Skill.Type.CRAFTING) == 500, "Exhausted reward is a no-op, not XP loss")
	resident.add_skill_xp(Skill.Type.COOKING, 9997)
	var capped := Rules.new([], [], [{"skill": Skill.Type.COOKING, "amount": 100, "training_cap": 20000}])
	check(capped.reward_deltas(resident) == {Skill.Type.COOKING: 1} and resident.award_skill_xp(capped), "Global cap is lower than a large training cap")
	check(resident.get_skill_xp(Skill.Type.COOKING) == 10000 and not resident.award_skill_xp(capped), "Exactly full skill cannot train further")

func invalid_rules() -> void:
	var resident := Data.new("invalid", "Тест", 20)
	var invalid := [
		Rules.new([{"skill": -1, "min_xp": 0}]),
		Rules.new([{"skill": Skill.Type.MINING, "min_xp": -1}]),
		Rules.new([{"skill": Skill.Type.MINING, "min_xp": 10001}]),
		Rules.new([{"skill": Skill.Type.MINING, "min_xp": 1.5}]),
		Rules.new([{"skill": Skill.Type.MINING, "min_xp": 0}, {"skill": Skill.Type.MINING, "min_xp": 1}]),
		Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 99}]),
		Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 101}]),
		Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 0}]),
		Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 100.0}]),
		Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 50}, {"skill": Skill.Type.MINING, "weight_percent": 50}]),
		Rules.new([], [{"skill": Skill.Type.MINING, "weight_percent": 9223372036854775807}]),
		Rules.new([], [], [{"skill": Skill.Type.MINING, "amount": 0, "training_cap": 10000}]),
		Rules.new([], [], [{"skill": Skill.Type.MINING, "amount": 1, "training_cap": -1}]),
		Rules.new([], [], [{"skill": Skill.Type.MINING, "amount": 1, "training_cap": 10000}, {"skill": Skill.Type.MINING, "amount": 1, "training_cap": 10000}]),
		Rules.new([], [], [{"skill": Skill.Type.MINING, "amount": 1, "training_cap": 10000}, {"skill": 999, "amount": 1, "training_cap": 10000}]),
		Rules.new([null]), Rules.new([{"skill": Skill.Type.MINING}]), Rules.new([{"skill": 0, "min_xp": 0, "typo": 1}])]
	for rules in invalid:
		check(not rules.is_valid() and not rules.validation_errors().is_empty(), "Malformed rules have diagnostics")
		check(not rules.can_perform(resident) and rules.efficiency_percent(resident) == -1.0 and rules.reward_deltas(resident).is_empty(), "Invalid rules fail closed")
		check(not resident.award_skill_xp(rules) and resident.get_skill_xp(Skill.Type.MINING) == 0, "No partial award from a malformed list")
	check(not resident.award_skill_xp(null) and not Rules.new().can_perform(null), "Missing inputs fail without mutation")
	var changed := Rules.new([], [], [{"skill": Skill.Type.MINING, "amount": 1, "training_cap": 10000}])
	changed.xp_rewards[0].amount = -1
	check(not resident.award_skill_xp(changed), "Mutated rule data is revalidated before use")

func atomic_notifications() -> void:
	var resident := Data.new("atomic", "Тест", 20)
	resident.add_skill_xp(Skill.Type.CONSTRUCTION, 399)
	var rules := Rules.new([], [], [{"skill": Skill.Type.CONSTRUCTION, "amount": 1, "training_cap": 10000}, {"skill": Skill.Type.POTTERY, "amount": 1000, "training_cap": 10000}])
	var trace: Array = []
	var snapshots: Array = []
	resident.skill_changed.connect(func(skill, amount, previous):
		snapshots.append([resident.get_skill_xp(Skill.Type.CONSTRUCTION), resident.get_skill_xp(Skill.Type.POTTERY)])
		trace.append(["changed", skill, amount, previous])
		if skill == Skill.Type.CONSTRUCTION and previous == Skill.Rank.PROFANE:
			resident.add_skill_xp(Skill.Type.CONSTRUCTION, 600))
	resident.skill_raised.connect(func(id, skill, previous, next): trace.append(["raised", id, skill, previous, next]))
	check(resident.award_skill_xp(rules), "Valid multi-skill commit")
	check(snapshots[0] == [400, 1000] and snapshots[1] == [1000, 1000] and snapshots[2] == [1000, 1000], "Every callback sees all outer writes; nested awards see committed XP")
	check(trace.slice(3) == [["raised", 1, Skill.Type.CONSTRUCTION, 0, 1], ["raised", 2, Skill.Type.POTTERY, 0, 2], ["raised", 3, Skill.Type.CONSTRUCTION, 1, 2]], "Rank facts are immutable and FIFO by commit, including nested awards")
	for signal_name in ["skill_changed", "skill_raised"]:
		for connection in resident.get_signal_connection_list(signal_name):
			resident.disconnect(signal_name, connection.callable)
