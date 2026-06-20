@tool
extends EditorScript

func _run():
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		print("Error: No active scene.")
		return
		
	var vegeta_node = root.get_node_or_null("Vegeta")
	var vegeta_opt_node = root.get_node_or_null("vegeta_optimized")
	
	var text = "=== SKELETON COMPARISON ===\n"
	
	if vegeta_node:
		text += "\n--- ORIGINAL VEGETA ---\n"
		var skeletons = []
		find_skeletons(vegeta_node, skeletons)
		for skel in skeletons:
			text += "Path: " + str(skel.get_path()) + "\n"
			text += "Bone count: " + str(skel.get_bone_count()) + "\n"
			for i in range(skel.get_bone_count()):
				var name = skel.get_bone_name(i)
				var parent_idx = skel.get_bone_parent(i)
				var parent_name = skel.get_bone_name(parent_idx) if parent_idx != -1 else "None"
				var local_rest = skel.get_bone_rest(i)
				var global_rest = skel.get_bone_global_rest(i)
				text += "  - Bone %d: %s (Parent: %s)\n" % [i, name, parent_name]
				text += "    Local Rest: pos=%s, rot=%s, scale=%s\n" % [str(local_rest.origin), str(local_rest.basis.get_euler()), str(local_rest.basis.get_scale())]
				text += "    Global Rest: pos=%s, rot=%s, scale=%s\n" % [str(global_rest.origin), str(global_rest.basis.get_euler()), str(global_rest.basis.get_scale())]
	else:
		text += "Vegeta not found.\n"
		
	if vegeta_opt_node:
		text += "\n--- OPTIMIZED VEGETA ---\n"
		var skeletons = []
		find_skeletons(vegeta_opt_node, skeletons)
		for skel in skeletons:
			text += "Path: " + str(skel.get_path()) + "\n"
			text += "Bone count: " + str(skel.get_bone_count()) + "\n"
			for i in range(skel.get_bone_count()):
				var name = skel.get_bone_name(i)
				var parent_idx = skel.get_bone_parent(i)
				var parent_name = skel.get_bone_name(parent_idx) if parent_idx != -1 else "None"
				var local_rest = skel.get_bone_rest(i)
				var global_rest = skel.get_bone_global_rest(i)
				text += "  - Bone %d: %s (Parent: %s)\n" % [i, name, parent_name]
				text += "    Local Rest: pos=%s, rot=%s, scale=%s\n" % [str(local_rest.origin), str(local_rest.basis.get_euler()), str(local_rest.basis.get_scale())]
				text += "    Global Rest: pos=%s, rot=%s, scale=%s\n" % [str(global_rest.origin), str(global_rest.basis.get_euler()), str(global_rest.basis.get_scale())]
	else:
		text += "vegeta_optimized not found.\n"
		
	var file = FileAccess.open("res://temp_comparison_output.txt", FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
		print("Comparison saved to res://temp_comparison_output.txt")
	else:
		print("Error saving comparison file.")

func find_skeletons(node: Node, list: Array):
	if node is Skeleton3D:
		list.append(node)
	for child in node.get_children():
		find_skeletons(child, list)
