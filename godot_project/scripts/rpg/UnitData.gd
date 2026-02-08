extends Resource

class_name UnitData

@export var unit_name: String = "Unit"
@export var health: int = 10
@export var max_health: int = 10
@export var initiative: int = 5
@export var movement_range: int = 2
@export var attack_range: int = 1
@export var is_ranged: bool = false # Ranged units attack from distance
@export var min_attack_range: int = 1 # Minimum range (ranged units can't hit adjacent)
@export var texture_path: String = "" # Path to the unit's sprite texture

# TMB Stats
@export var attack_dice: int = 1
@export var defense_dice: int = 1
@export var dex: int = 3 # Dexterity (Action Points)
# 'Bones' accumulation could live here or in a transient BattleUnit state,
# but for now we'll stick to static stats.
