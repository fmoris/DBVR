@tool
extends EditorScript

func _run():
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		print("Error: No active scene.")
		return
		
	var skeletons = []
	find_all_skeletons(root, skeletons)
	
	if skeletons.is_empty():
		print("No se encontraron esqueletos (Skeleton3D) en la escena.")
		return
		
	for skeleton in skeletons:
		# Eliminar verificadores previos si los hubiera
		var prev = skeleton.get_node_or_null("TempVerifierNode")
		if prev:
			prev.queue_free()
			
		var verifier = Node.new()
		verifier.name = "TempVerifierNode"
		verifier.set_script(load("res://temp_verifier_node.gd"))
		skeleton.add_child(verifier)
		verifier.owner = root
		print("Animación temporal activada en el esqueleto: " + skeleton.name)

func find_all_skeletons(node: Node, list: Array):
	if node is Skeleton3D:
		list.append(node)
	for child in node.get_children():
		find_all_skeletons(child, list)
