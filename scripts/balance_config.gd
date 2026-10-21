extends RefCounted
# S2: shared animal capacity, not resident housing. Wool has no economic type yet.
const SHEPHERD_ANIMAL_CAPACITY := 8
const SHEPHERD_WOOL_CAPACITY := 20
# T1 concrete textile production buffers and actual work minutes.
const WEAVER_INPUT_CAPACITY := 20
const WEAVER_OUTPUT_CAPACITY := 20
const WEAVER_WORK_MINUTES := 60
const TAILOR_INPUT_CAPACITY := 20
const TAILOR_OUTPUT_CAPACITY := 10
const TAILOR_WORK_MINUTES := 120
# H2 preliminary pair movement parameters, WORLD units and game minutes.
const ESCORT_GAP := 1.2
const ESCORT_WAIT_GAP := 3.0
const ESCORT_RESUME_GAP := 1.8
const ESCORT_MAX_TRAIL := 6.0
const ESCORT_MAX_POINTS := 256
const ESCORT_STALL_MINUTES := 10
const ESCORT_ARRIVAL_RADIUS := 0.8
const ESCORT_STEP_DISTANCE := 0.25 # Local integration quantum for large physical deltas.
## S1 prototype animal values, in WORLD units and game minutes.
const SHEEP_HABITAT_RADIUS := 10.0
const SHEEP_WALK_SPEED := 0.6 # Resident base is 4.8 WORLD/second at x1.
const SHEEP_NAV_RADIUS := 0.38 # Within the shared navigation clearance of 0.4.
const SHEEP_WANDER_CHANCE := 0.6
const SHEEP_GRAZE_MIN := 30
const SHEEP_GRAZE_MAX := 60
const SHEEP_MAX_WOOL := 15
const SHEEP_SLEEP_AFTER := 21*60
const SHEEP_WAKE_MIN := 5*60
const SHEEP_WAKE_MAX := 7*60
const SHEEP_TARGET_ATTEMPTS := 8
const SHEEP_MIN_WALK_DISTANCE := 0.5
const SHEEP_RETRY_MINUTES := 5
const SHEEP_SEED := 20261020
const ResourceType = preload("res://scripts/resource_type.gd")
const Categories = preload("res://scripts/resource_category.gd")
# Warehouse presets; production containers keep independent resource capacities.
const WAREHOUSE_SHARED_CAPACITY := 100
const STORAGE_CATEGORY_QUOTAS := {
	Categories.Type.LOG:40, Categories.Type.STONE:20,
	Categories.Type.PLANK:25, Categories.Type.SIMPLE_FOOD:15, Categories.Type.MUSHROOM:0,
}
const TOWN_CENTER_CATEGORY_QUOTAS := {
	Categories.Type.LOG:10, Categories.Type.STONE:10,
	Categories.Type.PLANK:60, Categories.Type.SIMPLE_FOOD:20, Categories.Type.MUSHROOM:0,
}
# Ground admission only: 25 simulation units = 1 world unit; build cell = 12.5.
const BUILDER_GROUND_SEARCH_MULTIPLIER := 2.0
const PORTER_GROUND_SEARCH_MULTIPLIER := 2.0
const RESIDENT_GROUND_SEARCH_RADIUS := 100.0 # 4 world units / 8 cells.
const DEFAULT_BUILDING_GROUND_SEARCH_RADIUS := 250.0 # 10 world units / 20 cells.
const RESOURCE_LOADING_MINUTES := 10
const RESOURCE_UNLOADING_MINUTES := 10
## Prototype balance values; no editor settings framework.
const ASSIGNMENT_BONUS := 3000
const UTILITY_CANDIDATE_RATIO := 0.75
const UTILITY_RANDOM_EXPONENT := 2.0
const SLEEP_SOCIAL_GROWTH_MULTIPLIER := 0.2
const SLEEP_LEISURE_GROWTH_MULTIPLIER := 0.2
const WORK_PRIORITY := 7000
const CLOTHING_PRIORITY := 7000 # Ordinary personal action, comparable to regular work.
const CLOTHING_LIFETIME_MINUTES := 4320
const NEED_ACTION_THRESHOLD := 1000
const IMPORT_MULTIPLIER := 1.1
const EXPORT_MULTIPLIER := 1.0
const DEFAULT_BUILDING_LOGISTICS_WEIGHT := 100
const GATHERER_OUTPUT_CAPACITY := 5
const KITCHEN_MUSHROOM_CAPACITY := 8
const KITCHEN_FRIED_MUSHROOM_CAPACITY := 20
const KITCHEN_WORK_MINUTES := 30
const KITCHEN_WORKER_CAPACITY := 1

# G1a prototype only; cells use the existing 0.5-world-unit BuildGrid.
const MUSHROOM_GROWTH_RADIUS := 1
const MUSHROOM_CELL_LIMIT := 4
const MUSHROOM_ZONE_LIMIT := 10
const MUSHROOM_ATTEMPTS_PER_NIGHT := 5
const MUSHROOM_GROWTH_CHANCE := 0.5
const MUSHROOM_GROWTH_SEED := 20261019

const HUNGER_BASE_WEIGHT := 100
const FATIGUE_BASE_WEIGHT := 100
const SOCIAL_BASE_WEIGHT := 80
const LEISURE_BASE_WEIGHT := 75
const KITCHEN_FOOD_CAPACITY := 20
const EAT_MIN_HUNGER := 30
const EAT_MAX_UTILITY := 10000
const EAT_UTILITY_EXPONENT := 2.0
const WANDER_PRIORITY := 500
const WANDER_RADIUS := 100.0
const WANDER_STAY_MINUTES := 10
# One uniform draw per ordinary empty-action period, in game minutes.
const IDLE_RETRY_MIN_MINUTES := 10
const IDLE_RETRY_MAX_MINUTES := 30
const CONVERSATION_POSITION_RADIUS := 64.0
const SOCIAL_GROWTH_DIVISOR := 5
const LEISURE_GROWTH_DIVISOR := 5
const RELAX_DURATION_MINUTES := 30
const WORK_CYCLE_MINUTES := 60
const MIN_CONVERSATION_MINUTES := 15
const MAX_CONVERSATION_MINUTES := 60
const CONVERSATION_RECHECK_MINUTES := 5
const CONVERSATION_EXIT_CHANCE := 0.2

# Construction site score is separate from WORK category utility.
const BUILDER_WORK_CYCLE_MINUTES = 60
const BUILDER_MATERIAL_PROGRESS_MAX = 2000.0
const BUILDER_CONSTRUCTION_PROGRESS_MAX = 2000.0
const BUILDER_ACTIVE_WORKER_BONUS = 1000.0
const BUILDER_DISTANCE_SCALE = 300.0
const BUILDER_DISTANCE_WEIGHT = 1000.0

const PORTER_DISTANCE_SCALE = 600.0
const PORTER_DISTANCE_WEIGHT = 1000.0

const HOUSE_RESIDENT_CAPACITY = 4 # Temporary prototype housing balance.

const HOME_SLEEP_QUALITY = 1.0
const OUTDOOR_SLEEP_QUALITY = 0.6

# Temporary progression; accumulated XP is retained if the curve changes later.
const SKILL_XP_PER_LEVEL = 10
const MAX_SKILL_LEVEL = 10

# First behavior modifier source: permanent traits. Base constants stay unchanged.
const SOCIABLE_SOCIAL_UTILITY_MULTIPLIER = 1.25
const INTROVERTED_SOCIAL_UTILITY_MULTIPLIER = 0.75
const INDUSTRIOUS_WORK_UTILITY_MULTIPLIER = 1.10
const LAZY_WORK_UTILITY_MULTIPLIER = 0.90
const GLUTTON_EAT_UTILITY_MULTIPLIER = 1.20
const GLUTTON_EAT_THRESHOLD_MODIFIER = -10
const RESTLESS_MOVEMENT_SPEED_MULTIPLIER = 1.10
const FOOLISH_UTILITY_CANDIDATE_RATIO = 0.55
const FOOLISH_UTILITY_RANDOM_EXPONENT = 1.50

# Directed relationship foundation; neutral reads do not allocate records.
const OPINION_MIN = -100
const OPINION_MAX = 100
const OPINION_NEUTRAL = 0

# Permanent personal tastes; derived contribution only, no social gameplay effect yet.
const LIKED_TRAITS_PER_RESIDENT = 2
const DISLIKED_TRAITS_PER_RESIDENT = 1
const LIKED_TRAIT_PREFERENCE_VALUE = 10
const DISLIKED_TRAIT_PREFERENCE_VALUE = -10


const SOCIAL_EVENT_CHANCE_CONVERSATION = 0.30
const SOCIAL_EVENT_CHANCE_MEAL = 1.00
const SOCIAL_EVENT_CHANCE_WORK = 0.50
const SOCIAL_ATTITUDE_MIN = -100
const SOCIAL_ATTITUDE_MAX = 100
const SOCIAL_REACTION_THRESHOLD = 50
const SOCIAL_EVENT_NEGATIVE_DELTA = -1
const SOCIAL_EVENT_NEUTRAL_DELTA = 0
const SOCIAL_EVENT_POSITIVE_DELTA = 1
const SOCIAL_EVENT_DIARY_CHANCE = 0.20
const SOCIAL_FEED_MAX_MESSAGES = 4
const SOCIAL_FEED_LIFETIME_SECONDS = 12.0

# Temporary first physical forestry chain. No skill efficiency modifiers.
const TREE_PHYSICAL_RADIUS := 0.35
const TREE_WORK_MINUTES := 60
const TREE_LOG_YIELD := 3

const LUMBERJACK_LOG_CAPACITY := 12
const FREE_WORK_AREA_RADIUS := 15.0 # World units.
const MAX_WORK_AREA_RADIUS := 30.0 # Player-created/edited areas; world units.
const LUMBERJACK_WORK_RADIUS := 15.0
const LUMBERJACK_TARGET_TREE_COUNT := 12
const LUMBERJACK_WORKER_CAPACITY := 1
const TREE_MINIMUM_SPACING := 2.0
const SAPLING_PHYSICAL_RADIUS := 0.15
const TREE_GROWTH_MINUTES := 4320
const TREE_PLANTING_MINUTES := 30
const WAREHOUSE_LOG_CAPACITY := 20

# First processing recipe; PLANK is a unit of processed timber, not one literal board.
const SAWMILL_WORK_MINUTES := 30
const SAWMILL_INPUT_CAPACITY := 12
const SAWMILL_OUTPUT_CAPACITY := 12
const SAWMILL_WORKER_CAPACITY := 1
# Historical 2D/reference starting stock, independent of current construction costs.
# Per-resource capacity; FOOD/LOG capacities are independent.
const WAREHOUSE_PLANK_CAPACITY := 35
const STARTER_PLANK_RESERVE := 10
static func starter_plank_amount(hut_cost: int, sawmill_cost: int) -> int:
	return hut_cost + sawmill_cost + STARTER_PLANK_RESERVE

# Small cleanup preference against world urgency 0..11000; no age term.
const PORTER_GROUND_CLEANUP_BONUS := 200.0

# Physical traversal only; planting/forestry balance remains unchanged.
const TREE_TRAVERSAL_SPEED_MULTIPLIER := 0.20

# Free instant dirt roads; a world surface state, not a construction job.
const DIRT_ROAD_SPEED_MULTIPLIER := 1.25

const TOWN_CENTER_RESOURCE_CAPACITY := 100
const TOWN_CENTER_STARTING_PLANK := 60
const TOWN_CENTER_STARTING_FOOD := 20
const TOWN_CENTER_FALLBACK_CAPACITY := 10

const GATHERER_WORKER_CAPACITY := 4

# Finite rocks: initial free mining prototype.
const ROCK_STONE_STOCK := 10
const ROCK_WORK_MINUTES := 60
const ROCK_PHYSICAL_RADIUS := 0.9
const STORAGE_STONE_CAPACITY := 100

# Quarry prototype balance; extraction time/yield remain the rock model.
const QUARRY_WORKER_CAPACITY := 1
const QUARRY_WORK_RADIUS := 15.0
const QUARRY_STONE_CAPACITY := 12

# Ground stack core. Gameplay opts in separately in E1.2.
const DEMOLITION_MATERIAL_RETURN_RATIO := 0.5
const GROUND_STACK_CAPACITY := 10
const GROUND_STONE_STACK_CAPACITY := 4
const GROUND_STACK_LIFETIME_MINUTES := 4320
const GROUND_NATURAL_PLACEMENT_RADIUS := 2
const GROUND_WORKER_PLACEMENT_RADIUS := 8

# Natural surface wear: one independent roll per physical cell entry.
const TRAMPLE_CHANCE := 0.25
const TRAMPLE_DECAY_PER_NIGHT := 1
const TRAMPLE_MAX_LEVEL := 15
const TRAMPLE_FAST_LEVEL := 11
const TRAMPLE_SEED := 20261020
