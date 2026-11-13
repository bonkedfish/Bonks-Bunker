# RefreshClasses — run this scene after adding a script with a new class_name: it runs the editor headless with
# --import so Godot rescans the project and updates its global class list (otherwise running scenes straight from
# the command line fails with "Identifier not declared"). Log: tests/_look/refresh_classes.txt. Depends on: nothing.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--import"], out, true)
	var f := FileAccess.open("res://tests/_look/refresh_classes.txt", FileAccess.WRITE)
	f.store_string("exit %d\n%s" % [code, "\n".join(PackedStringArray(out)).right(3000)])
	f.close()
	get_tree().quit()
