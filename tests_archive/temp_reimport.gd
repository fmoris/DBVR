@tool
extends EditorScript

func _run():
	print("Scanning filesystem...")
	var fs = get_editor_interface().get_resource_filesystem()
	fs.scan()
	fs.reimport_files(["res://assets/models/vegeta_optimized.glb"])
	print("Reimport triggered for res://assets/models/vegeta_optimized.glb")
