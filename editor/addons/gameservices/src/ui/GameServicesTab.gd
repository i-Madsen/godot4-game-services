#
# GameServicesTab.gs
# sjc - 16/1/23
# The in-editor UI for configuring GameServices
#

@tool
extends Control

var Config = preload("res://addons/gameservices/src/utils/GameServicesConfig.gd").new()


func _ready():
	_load_config()
	
	'''
	var names = ["SPORTS", "PLANETS", "BUBBLES", "SportsBalls_Uniform_Normal_Normal_None", "SportsBalls_Uniform_Normal_Normal_Bubbles", "SportsBalls_Uniform_Normal_Launcher_None", "SportsBalls_Uniform_Normal_Launcher_Bubbles", "SportsBalls_Uniform_Low_Normal_None", "SportsBalls_Uniform_Low_Normal_Bubbles", "SportsBalls_Uniform_Low_Launcher_None", "SportsBalls_Uniform_Low_Launcher_Bubbles", "SportsBalls_Individualized_Normal_Normal_None", "SportsBalls_Individualized_Normal_Normal_Bubbles", "SportsBalls_Individualized_Normal_Launcher_None", "SportsBalls_Individualized_Normal_Launcher_Bubbles", "SportsBalls_Individualized_Low_Normal_None", "SportsBalls_Individualized_Low_Normal_Bubbles", "SportsBalls_Individualized_Low_Launcher_None", "SportsBalls_Individualized_Low_Launcher_Bubbles", "PlanetBalls_Uniform_Normal_Normal_None", "PlanetBalls_Uniform_Normal_Normal_Bubbles", "PlanetBalls_Uniform_Normal_Launcher_None", "PlanetBalls_Uniform_Normal_Launcher_Bubbles", "PlanetBalls_Uniform_Low_Normal_None", "PlanetBalls_Uniform_Low_Normal_Bubbles", "PlanetBalls_Uniform_Low_Launcher_None", "PlanetBalls_Uniform_Low_Launcher_Bubbles", "PlanetBalls_Individualized_Normal_Normal_None", "PlanetBalls_Individualized_Normal_Normal_Bubbles", "PlanetBalls_Individualized_Normal_Launcher_None", "PlanetBalls_Individualized_Normal_Launcher_Bubbles", "PlanetBalls_Individualized_Low_Normal_None", "PlanetBalls_Individualized_Low_Normal_Bubbles", "PlanetBalls_Individualized_Low_Launcher_None", "PlanetBalls_Individualized_Low_Launcher_Bubbles", "BubbleBalls_Uniform_Normal_Normal_None", "BubbleBalls_Uniform_Normal_Normal_Bubbles", "BubbleBalls_Uniform_Normal_Launcher_None", "BubbleBalls_Uniform_Normal_Launcher_Bubbles", "BubbleBalls_Uniform_Low_Normal_None", "BubbleBalls_Uniform_Low_Normal_Bubbles", "BubbleBalls_Uniform_Low_Launcher_None", "BubbleBalls_Uniform_Low_Launcher_Bubbles", "BubbleBalls_Individualized_Normal_Normal_None", "BubbleBalls_Individualized_Normal_Normal_Bubbles", "BubbleBalls_Individualized_Normal_Launcher_None", "BubbleBalls_Individualized_Normal_Launcher_Bubbles", "BubbleBalls_Individualized_Low_Normal_None", "BubbleBalls_Individualized_Low_Normal_Bubbles", "BubbleBalls_Individualized_Low_Launcher_None", "BubbleBalls_Individualized_Low_Launcher_Bubbles", "DevBalls_Uniform_Normal_Normal_None", "DevBalls_Uniform_Normal_Normal_Bubbles", "DevBalls_Uniform_Normal_Launcher_None", "DevBalls_Uniform_Normal_Launcher_Bubbles", "DevBalls_Uniform_Low_Normal_None", "DevBalls_Uniform_Low_Normal_Bubbles", "DevBalls_Uniform_Low_Launcher_None", "DevBalls_Uniform_Low_Launcher_Bubbles", "DevBalls_Individualized_Normal_Normal_None", "DevBalls_Individualized_Normal_Normal_Bubbles", "DevBalls_Individualized_Normal_Launcher_None", "DevBalls_Individualized_Normal_Launcher_Bubbles", "DevBalls_Individualized_Low_Normal_None", "DevBalls_Individualized_Low_Normal_Bubbles", "DevBalls_Individualized_Low_Launcher_None", "DevBalls_Individualized_Low_Launcher_Bubbles"]
	
	var entries = names.size()
	if entries == 0:
		return # no config to setup
	
	for i in range(entries):
		add_row(names[i], names[i], names[i])
		
	_save_config()
	'''

#
# Loading and saving settings
#

func _load_config():
	# get the values from the config
	var leaderboard_ids = Config.config.get(Config.LEADERBOARD_IDS_KEY, {})
	var names = leaderboard_ids.get(Config.LEADERBOARD_NAMES_KEY, [])
	var android = leaderboard_ids.get(Config.LEADERBOARD_ANDROID_KEY, [])
	var ios = leaderboard_ids.get(Config.LEADERBOARD_IOS_KEY, [])
	
	var entries = names.size()
	if entries == 0:
		return # no config to setup
	
	for i in range(entries):
		add_row(names[i], android[i], ios[i])


func _save_config():
	
	var names = []
	var android = []
	var ios = []
	
	var child_count = $Margin/GridContainer.get_child_count()
	if child_count > 4:
		for i in range(4, child_count, 4):
			names.append($Margin/GridContainer.get_child(i).text)
			android.append($Margin/GridContainer.get_child(i+1).text)
			ios.append($Margin/GridContainer.get_child(i+2).text)
	
	Config.config[Config.LEADERBOARD_IDS_KEY] = {
		Config.LEADERBOARD_NAMES_KEY: names,
		Config.LEADERBOARD_ANDROID_KEY: android,
		Config.LEADERBOARD_IOS_KEY: ios
	}
	Config.save()


#
# GridContainer row management
#

func add_row(name: String = "", android: String = "", ios: String = ""):
	# editable text
	add_textfield(name)
	add_textfield(android)
	add_textfield(ios)
	
	# button
	var button = Button.new()
	button.text = "-"
	$Margin/GridContainer.add_child(button)
	
	var row = ($Margin/GridContainer.get_child_count() - 3) / 4
	button.pressed.connect(_on_DeleteButton_pressed.bind(row))


func add_textfield(text: String):
	var textfield = LineEdit.new()
	textfield.text = text
	textfield.text_changed.connect(_on_LineEdit_text_changed)
	textfield.text_submitted.connect(_on_LineEdit_text_entered)
	$Margin/GridContainer.add_child(textfield)


func delete_row(row: int):
	# delete the 4 controls in this row
	var index = row * 4
	for i in range(4):
		var control = $Margin/GridContainer.get_child(index)
		$Margin/GridContainer.remove_child(control)
		control.queue_free()
	
	# now fix up all the remaining 'pressed' signals
	var count = $Margin/GridContainer.get_child_count()
	if count > index:
		# the button will be the last item in each row
		for i in range(index+3, count, 4):
			var button = $Margin/GridContainer.get_child(i)
			button.pressed.disconnect(_on_DeleteButton_pressed)
			button.pressed.connect(_on_DeleteButton_pressed.bind(row))
			row += 1

#
# Callbacks
#

func _on_AddButton_pressed():
	add_row()

func _on_DeleteButton_pressed(row: int):
	delete_row(row)

func _on_LineEdit_text_changed(_text: String):
	_save_config()

func _on_LineEdit_text_entered(_text: String):
	_save_config()

