@tool
extends EditorScript

func _run():
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		write_output("Error: No active scene.")
		return
		
	var skeletons = []
	find_all_skeletons(root, skeletons)
	
	var text = "=== SKELETON ANIMATOR CHECK ===\n"
	for skeleton in skeletons:
		text += "\nSkeleton: " + skeleton.name + " (" + str(skeleton.get_path()) + ")\n"
		var temp_node = skeleton.get_node_or_null("TempBigBangNode")
		if temp_node:
			text += "  - TempBigBangNode: FOUND\n"
			text += "    - script: " + str(temp_node.get_script().resource_path if temp_node.get_script() else "None") + "\n"
			text += "    - active: " + str(temp_node.get("active")) + "\n"
			text += "    - time: " + str(temp_node.get("time")) + "\n"
			text += "    - right_arm_idx: " + str(temp_node.get("right_arm_idx")) + "\n"
			text += "    - right_hand_idx: " + str(temp_node.get("right_hand_idx")) + "\n"
			text += "    - head_idx: " + str(temp_node.get("head_idx")) + "\n"
			text += "    - spine_idx: " + str(temp_node.get("spine_idx")) + "\n"
		else:
			text += "  - TempBigBangNode: NOT FOUND\n"
			
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
