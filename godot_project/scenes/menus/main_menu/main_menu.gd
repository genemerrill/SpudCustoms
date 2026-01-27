extends MainMenu

const TIC_TAC_TOE_SCENE = preload("res://scenes/prototypes/tic_tac_toe/TicTacToe.tscn")
const BATTLE_SCENE = preload("res://scenes/prototypes/rpg_battle/BattleMat.tscn")

func _ready():
	super._ready()
	
	var tic_tac_toe_btn = %TicTacToeButton
	if tic_tac_toe_btn:
		tic_tac_toe_btn.pressed.connect(func(): _change_scene(TIC_TAC_TOE_SCENE))
		
	var battle_btn = %TacticalBattleButton
	if battle_btn:
		battle_btn.pressed.connect(func(): _change_scene(BATTLE_SCENE))

func _change_scene(scene_packed):
	get_tree().change_scene_to_packed(scene_packed)

