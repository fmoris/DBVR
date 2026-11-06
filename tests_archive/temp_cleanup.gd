@tool
extends EditorScript

func _run():
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		return
		
	var v_opt = root.get_node_or_null("vegeta_optimized")
	var text = ""
	if v_opt:
		var old_scale = v_opt.scale
		v_opt.scale = Vector3(8.291948, 8.291948, 8.291948)
		EditorInterface.mark_scene_as_unsaved()
		text = "SUCCESS: scaled vegeta_optimized from %s to %s\n" % [str(old_scale), str(v_opt.scale)]
	else:
		# Búsqueda recursiva
		var found = find_node_recursively(root, "vegeta_optimized")
		if found:
			var old_scale = found.scale
			found.scale = Vector3(8.291948, 8.291948, 8.291948)
			EditorInterface.mark_scene_as_unsaved()
			text = "SUCCESS (recursivo): scaled %s from %s to %s\n" % [found.name, str(old_scale), str(found.scale)]
		else:
			text = "FAILED: vegeta_optimized not found in tree.\n"
			
	var file = FileAccess.open("res://temp_output.txt", FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()

func find_node_recursively(node: Node, substring: String) -> Node:
	if substring.to_lower() in node.name.to_lower():
		return node
	for child in node.get_children():
		var found = find_node_recursively(child, substring)
		if found:
			return found
	return null
