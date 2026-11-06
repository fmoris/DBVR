@tool
extends EditorScript

func _run():
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("Error: No active scene.")
		return
		
	var skeletons = []
	find_all_skeletons(root, skeletons)
	
	var found_vegeta = false
	for skeleton in skeletons:
		var path_str = str(skeleton.get_path())
		if "vegeta_optimized" in path_str or "Vegeta" in path_str or "vegeta_optimized" in skeleton.get_parent().name or "Vegeta" in skeleton.get_parent().name:
			# Eliminar animadores previos
			var prev = skeleton.get_node_or_null("TempBigBangNode")
			if prev:
				prev.queue_free()
				
			var verifier = Node.new()
			verifier.name = "TempBigBangNode"
			verifier.set_script(ResourceLoader.load("res://temp_big_bang_verifier.gd", "", ResourceLoader.CACHE_MODE_IGNORE))
			skeleton.add_child(verifier)
			verifier.owner = root
			print("¡Big Bang Attack activado en el esqueleto: " + skeleton.name + " (" + str(skeleton.get_path()) + ")!")
			found_vegeta = true
			
	if not found_vegeta:
		print("No se encontró ningún esqueleto de Vegeta en la escena activa.")

func find_all_skeletons(node: Node, list: Array):
	if node is Skeleton3D:
		list.append(node)
	for child in node.get_children():
		find_all_skeletons(child, list)
