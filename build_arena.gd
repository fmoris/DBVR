@tool
extends Node3D

@export var build_arena: bool = false:
	set(value):
		if value:
			_build()

func _build():
	# 1. Limpieza total de los 256 nodos antiguos (Causa del lag/parpadeo)
	for child in get_children():
		child.queue_free()
		
	var arena_size = 32.0 # 16 tiles * 2.0m c/u
	var height = 1.0

	# 2. Crear UN SOLO NODO para todo el suelo (Optimización Máxima)
	var floor_node = MeshInstance3D.new()
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(arena_size, height, arena_size)
	floor_node.mesh = floor_mesh
	floor_node.name = "ArenaFloor_Single"
	
	# 3. Aplicar un Shader de Recuadro Único Canon (1 solo Draw Call y sin cuadros repetitivos)
	var shader = Shader.new()
	shader.code = """
		shader_type spatial;
		
		uniform vec3 color_floor : source_color = vec3(0.85, 0.85, 0.85); // Gris claro de piedra
		uniform vec3 color_border : source_color = vec3(0.2, 0.2, 0.25);  // Gris oscuro de borde
		uniform float border_thickness = 0.03; // Borde elegante de 3%

		void fragment() {
			// Detectar si la coordenada UV actual está dentro del recuadro
			float border_mask = step(border_thickness, UV.x) * step(border_thickness, UV.y) * step(UV.x, 1.0 - border_thickness) * step(UV.y, 1.0 - border_thickness);
			
			// Mezclar color de piedra y color de borde según la máscara
			ALBEDO = mix(color_border, color_floor, border_mask);
			ROUGHNESS = 0.8;
		}
	"""
	
	var mat = ShaderMaterial.new()
	mat.shader = shader
	floor_node.material_override = mat
	
	# Posicionar y añadir el suelo
	add_child(floor_node)
	floor_node.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	# 4. Reconstruir los 4 pilares (Solo son 4 nodos, no afectan el rendimiento)
	var mat_white = StandardMaterial3D.new()
	mat_white.albedo_color = Color(0.9, 0.9, 0.85)
	var mat_green = StandardMaterial3D.new()
	mat_green.albedo_color = Color(0.3, 0.8, 0.4)

	var pillar_positions = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	var pillar_radius = 0.8
	var pillar_height = 8.0
	var p_offset = (arena_size / 2.0) + pillar_radius

	for i in range(pillar_positions.size()):
		var p_pos = pillar_positions[i]
		var pillar = MeshInstance3D.new()
		var p_mesh = CylinderMesh.new()
		p_mesh.top_radius = pillar_radius
		p_mesh.bottom_radius = pillar_radius
		p_mesh.height = pillar_height
		pillar.mesh = p_mesh
		pillar.material_override = mat_white
		
		var top_ball = MeshInstance3D.new()
		var b_mesh = SphereMesh.new()
		b_mesh.radius = pillar_radius * 1.5
		b_mesh.height = pillar_radius * 3.0
		top_ball.mesh = b_mesh
		top_ball.material_override = mat_green
		top_ball.position.y = pillar_height / 2.0 + pillar_radius * 1.5
		pillar.add_child(top_ball)
		
		pillar.position = Vector3(p_pos.x * p_offset, pillar_height/2.0 - height/2.0, p_pos.y * p_offset)
		pillar.name = "Pillar_" + str(i)
		add_child(pillar)
		pillar.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self
		top_ball.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	print("¡Arena optimizada con 1 solo nodo de suelo!")
