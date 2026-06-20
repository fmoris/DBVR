@tool
extends EditorScript

func _run():
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		write_output("Error: No hay escena activa.")
		return
		
	var skeletons = []
	find_all_skeletons(root, skeletons)
	
	var text = "=== GLOBAL REST TRANSFORMS ===\n"
	for skeleton in skeletons:
		text += "\nSkeleton: " + skeleton.name + " (" + str(skeleton.get_path()) + ")\n"
		for i in range(skeleton.get_bone_count()):
			var bone_name = skeleton.get_bone_name(i)
			var global_rest = skeleton.get_bone_global_rest(i)
			text += "  - " + bone_name + " (parent: " + (skeleton.get_bone_name(skeleton.get_bone_parent(i)) if skeleton.get_bone_parent(i) != -1 else "None") + "): pos=" + str(global_rest.origin) + "\n"
				
	write_output(text)

func find_all_skeletons(node: Node, list: Array):
	if node is Skeleton3D:
		list.append(node)
	for child in node.get_children():
		find_all_skeletons(child, list)

func write_output(text: String):
	var file = FileAccess.open("res://temp_output.txt", FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
