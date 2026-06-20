@tool
extends EditorScript

func _run():
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		write_output("Error: No active scene root")
		return
		
	var v_opt = root.get_node_or_null("vegeta_optimized")
	var text = ""
	if v_opt:
		text += "Encontrado vegeta_optimized directamente.\n"
		text += "  - Escala antes: %s\n" % [str(v_opt.scale)]
		v_opt.scale = Vector3(8.291948, 8.291948, 8.291948)
		text += "  - Escala después: %s\n" % [str(v_opt.scale)]
		EditorInterface.mark_scene_as_dirty()
	else:
		text += "No encontrado vegeta_optimized directamente. Buscando recursivo...\n"
		var found = find_node_recursively(root, "vegeta_optimized")
		if found:
			text += "  - Encontrado recursivo: %s (%s)\n" % [found.name, str(found.get_path())]
			text += "  - Escala antes: %s\n" % [str(found.scale)]
			found.scale = Vector3(8.291948, 8.291948, 8.291948)
			text += "  - Escala después: %s\n" % [str(found.scale)]
			EditorInterface.mark_scene_as_dirty()
		else:
			text += "No se encontró vegeta_optimized en toda la escena.\n"
			
	write_output(text)

func find_node_recursively(node: Node, substring: String) -> Node:
	if substring.to_lower() in node.name.to_lower():
		return node
	for child in node.get_children():
		var found = find_node_recursively(child, substring)
		if found:
			return found
	return null

func write_output(text: String):
	var file = FileAccess.open("res://temp_output.txt", FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
