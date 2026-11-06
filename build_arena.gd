@tool
extends Node3D

## BuildArena: Reconstrucción canónica 1:1 del Escenario del Torneo de Cell (Dragon Ball Z).
## Genera:
## 1. El cuadrilátero de piedra pulida blanca/lila con marco perimetral y losas en cuadrícula.
## 2. El zócalo o escalón inferior perimetral de piedra.
## 3. Las 4 torres angulares con pedestal anillado y agujas cónicas afiladas en punta (Canon Anime).
## 4. El terreno exterior continuo de 180m (claro de tierra ocre + praderas verdes de colinas).
## 5. Rocas y peñascos facetados de Akira Toriyama instanciados mediante MultiMesh (1 solo Draw Call).
## 6. Colisionadores físicos en runtime para todo el conjunto.

@export var rebuild_arena: bool = false:
	set(value):
		if value:
			_build()

func _ready() -> void:
	# Asegurar construcción limpia del escenario canónico al cargar
	_build()
	if not Engine.is_editor_hint():
		call_deferred("_generate_runtime_colliders")


func _build() -> void:
	# 1. Limpieza de nodos anteriores
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var ring_size = 32.0
	var ring_height = 0.8
	var plinth_size = 36.0
	var plinth_height = 0.4
	var ground_size = 180.0

	# -------------------------------------------------------------
	# 2. TERRENO EXTERIOR CONTINUO (Claro de tierra ocre + Camino sinuoso + Praderas verdes)
	# -------------------------------------------------------------
	var ground_node = MeshInstance3D.new()
	ground_node.name = "ArenaGround_Surrounding"
	var ground_mesh = BoxMesh.new()
	ground_mesh.size = Vector3(ground_size, 1.0, ground_size)
	ground_node.mesh = ground_mesh
	ground_node.position = Vector3(0.0, -0.6, 0.0) # Superficie en Y = -0.1

	var ground_shader = Shader.new()
	ground_shader.code = """
		shader_type spatial;
		render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

		uniform vec3 color_dirt       : source_color = vec3(0.76, 0.58, 0.36); // Tierra/arena ocre del anime
		uniform vec3 color_dirt_dark  : source_color = vec3(0.64, 0.46, 0.28); // Sombra y surcos del sendero
		uniform vec3 color_grass      : source_color = vec3(0.34, 0.72, 0.22); // Verde vivo pradera Toriyama
		uniform vec3 color_grass_dark : source_color = vec3(0.22, 0.54, 0.15); // Colinas sombreadas

		void fragment() {
			vec2 p = (UV - vec2(0.5)) * 180.0;
			
			// Claro rectangular de tierra alrededor del ring (Canon Manga Akira Toriyama)
			float box_dist = max(abs(p.x), abs(p.y));
			float noise_edge = sin(p.x * 0.28) * cos(p.y * 0.28) * 2.2 + sin(p.x * 0.10 + p.y * 0.12) * 1.5;
			float dirt_box_factor = 1.0 - smoothstep(23.0 + noise_edge, 28.5 + noise_edge, box_dist);
			
			// Sendero de tierra serpenteante hacia las montañas del fondo (Canon Anime)
			float path_center = -p.y * 0.42 + 8.5 + sin(p.y * 0.07) * 4.2;
			float dist_to_path = abs(p.x - path_center);
			float path_factor = 0.0;
			if (p.y < -14.0) {
				path_factor = 1.0 - smoothstep(2.4, 4.6, dist_to_path);
			}
			
			float total_dirt_mask = clamp(dirt_box_factor + path_factor, 0.0, 1.0);

			// Variación tonal orgánica en la hierba
			float grass_noise = sin(p.x * 0.12) * cos(p.y * 0.12) * 0.5 + 0.5;
			vec3 final_grass = mix(color_grass, color_grass_dark, grass_noise * 0.40);
			
			// Variación en el sendero de tierra
			float dirt_noise = sin(p.x * 0.4) * cos(p.y * 0.4) * 0.5 + 0.5;
			vec3 final_dirt = mix(color_dirt, color_dirt_dark, dirt_noise * 0.35);

			ALBEDO = mix(final_grass, final_dirt, total_dirt_mask);
			ROUGHNESS = 0.94;
			SPECULAR = 0.06;
		}
	"""
	var ground_mat = ShaderMaterial.new()
	ground_mat.shader = ground_shader
	ground_node.material_override = ground_mat
	add_child(ground_node)
	ground_node.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 3. ZÓCALO INFERIOR DEL RING (Escalón de cemento de 36m x 36m)
	# -------------------------------------------------------------
	var plinth_node = MeshInstance3D.new()
	plinth_node.name = "ArenaPlinth_Step"
	var plinth_mesh = BoxMesh.new()
	plinth_mesh.size = Vector3(plinth_size, plinth_height, plinth_size)
	plinth_node.mesh = plinth_mesh
	plinth_node.position = Vector3(0.0, -0.3, 0.0) # Superficie en Y = -0.1

	var plinth_shader = Shader.new()
	plinth_shader.code = """
		shader_type spatial;
		render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

		uniform vec3 color_cement : source_color = vec3(0.38, 0.42, 0.46); // Cemento piedra base oscura
		uniform vec3 color_line   : source_color = vec3(0.08, 0.09, 0.11); // Tinta negra manga
		uniform float line_thickness = 0.035;

		varying vec3 v_world_pos;
		varying vec3 v_normal;

		void vertex() {
			v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
			v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		}

		void fragment() {
			float line_mask = 0.0;
			if (v_normal.y > 0.5) {
				// Cara superior del zócalo (borde exterior con bisel en 17.5m)
				vec2 p = v_world_pos.xz;
				float max_dist = max(abs(p.x), abs(p.y));
				float seam_dist = abs(max_dist - 17.5);
				vec2 fw = fwidth(p);
				float fw_val = max(max(fw.x, fw.y) * 0.75, 0.003);
				line_mask = 1.0 - smoothstep(line_thickness * 0.5, line_thickness * 0.5 + fw_val, seam_dist);
			} else {
				// Caras laterales del zócalo: bloques de cemento cada 2.4m
				float vert_coord = (abs(v_normal.x) > 0.5) ? v_world_pos.z : v_world_pos.x;
				vec2 fw_v = fwidth(vec2(vert_coord, v_world_pos.y));
				float dist_to_seam = min(fract(vert_coord * (1.0 / 2.4)), 1.0 - fract(vert_coord * (1.0 / 2.4))) * 2.4;
				float fw_val = max(fw_v.x * 0.75, 0.003);
				line_mask = 1.0 - smoothstep(line_thickness * 0.5, line_thickness * 0.5 + fw_val, dist_to_seam);
			}
			ALBEDO = mix(color_cement, color_line, line_mask);
			ROUGHNESS = 0.90;
			SPECULAR = 0.10;
		}
	"""
	var plinth_mat = ShaderMaterial.new()
	plinth_mat.shader = plinth_shader
	plinth_node.material_override = plinth_mat
	add_child(plinth_node)
	plinth_node.owner = get_tree().edited_scene_root if get_tree() and get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 4. PLATAFORMA PRINCIPAL DEL RING (Cemento con Cuadrícula Matemática)
	# -------------------------------------------------------------
	# Optimización VR: 1 solo BoxMesh, 0 geometría extra, cuadrícula dibujada
	# matemáticamente por shader antialiased con fwidth().
	var floor_node = MeshInstance3D.new()
	floor_node.name = "ArenaFloor_Single"
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(ring_size, ring_height, ring_size)
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3(0.0, 0.1, 0.0) # Superficie en Y = 0.5 (coincide con los combatientes)

	var floor_shader = Shader.new()
	floor_shader.code = """
		shader_type spatial;
		render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

		// Colores de cemento auténtico estilo cómic / manga Akira Toriyama
		uniform vec3 color_cement_base : source_color = vec3(0.50, 0.55, 0.59); // Cemento grisáceo claro
		uniform vec3 color_cement_alt  : source_color = vec3(0.46, 0.51, 0.55); // Variación tonal sutil entre baldosas
		uniform vec3 color_border      : source_color = vec3(0.42, 0.47, 0.51); // Marco perimetral sólido
		uniform vec3 color_line        : source_color = vec3(0.08, 0.09, 0.11); // Tinta negra manga (líneas de división)

		uniform float arena_half_size = 16.0;   // Semiancho del ring (32m total)
		uniform float border_width    = 1.4;    // Ancho del marco perimetral sólido (1.4m)
		uniform float tile_count      = 24.0;   // 24 cuadros exactos de lado (Canon Manga Panel)
		uniform float line_thickness  = 0.036;  // Grosor de las líneas en metros (3.6 cm)

		varying vec3 v_world_pos;
		varying vec3 v_normal;

		void vertex() {
			v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
			v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		}

		void fragment() {
			// Cara superior horizontal (piso del ring)
			if (v_normal.y > 0.5) {
				vec2 p = v_world_pos.xz;
				float max_dist = max(abs(p.x), abs(p.y));
				float inner_limit = arena_half_size - border_width;
				float tile_size = (inner_limit * 2.0) / tile_count;

				vec2 fw = fwidth(p);
				float fw_b = max(max(fw.x, fw.y) * 0.75, 0.003);

				// Línea perimetral de separación con el marco exterior
				float border_seam_dist = abs(max_dist - inner_limit);
				float border_seam = 1.0 - smoothstep(line_thickness * 0.5, line_thickness * 0.5 + fw_b, border_seam_dist);

				// Línea del filo exterior del ring
				float outer_edge_dist = abs(max_dist - arena_half_size);
				float outer_edge_seam = 1.0 - smoothstep(line_thickness * 0.5, line_thickness * 0.5 + fw_b, outer_edge_dist);

				if (max_dist > inner_limit) {
					// Marco exterior perimetral de cemento sólido
					float total_border_lines = max(border_seam, outer_edge_seam);
					ALBEDO = mix(color_border, color_line, total_border_lines);
				} else {
					// Área interior cuadriculada (24x24 cuadros alineados)
					vec2 grid_coord = (p + vec2(inner_limit)) / tile_size;
					vec2 local_tile = fract(grid_coord);
					vec2 dist_from_edge = min(local_tile, vec2(1.0) - local_tile) * tile_size;

					vec2 fw_clamped = max(fw * 0.75, vec2(0.003));
					vec2 line_factor = 1.0 - smoothstep(vec2(line_thickness * 0.5), vec2(line_thickness * 0.5) + fw_clamped, dist_from_edge);
					float grid_mask = max(line_factor.x, line_factor.y);
					grid_mask = max(grid_mask, border_seam);

					// Sombra de contacto / bisel en la ranura del mortero (aporta profundidad 3D a cada losa)
					vec2 groove_factor = 1.0 - smoothstep(vec2(line_thickness * 0.5), vec2(line_thickness * 2.6), dist_from_edge);
					float groove_mask = max(groove_factor.x, groove_factor.y);

					// Variación tonal entre baldosas usando hash discreto
					vec2 tile_id = floor(grid_coord);
					float tile_hash = fract(sin(dot(tile_id, vec2(12.9898, 78.233))) * 43758.5453);
					vec3 cement_tile = mix(color_cement_base, color_cement_alt, tile_hash * 0.75);

					// Aplicar bisel/ambient occlusion en los surcos
					cement_tile *= (1.0 - groove_mask * 0.32);

					// Micro-grano sutil de cemento
					float grain = sin(p.x * 28.0) * sin(p.y * 28.0) * 0.012;
					cement_tile += vec3(grain);

					ALBEDO = mix(cement_tile, color_line, grid_mask);
				}
			} else {
				// Caras laterales verticales del bloque de cemento (juntas verticales alineadas con las baldosas)
				float inner_limit = arena_half_size - border_width;
				float tile_size = (inner_limit * 2.0) / tile_count;
				float vert_coord = (abs(v_normal.x) > 0.5) ? v_world_pos.z : v_world_pos.x;
				float dist_to_seam = min(fract((vert_coord + inner_limit) / tile_size), 1.0 - fract((vert_coord + inner_limit) / tile_size)) * tile_size;
				float fw_v = fwidth(vert_coord);
				float fw_val = max(fw_v * 0.75, 0.003);
				float v_seam = 1.0 - smoothstep(line_thickness * 0.5, line_thickness * 0.5 + fw_val, dist_to_seam);

				vec3 side_cement = color_border * 0.85; // Cemento lateral ligeramente en sombra
				ALBEDO = mix(side_cement, color_line, v_seam);
			}

			ROUGHNESS = 0.88;
			SPECULAR = 0.12;
		}
	"""
	var floor_mat = ShaderMaterial.new()
	floor_mat.shader = floor_shader
	floor_node.material_override = floor_mat
	add_child(floor_node)
	floor_node.owner = get_tree().edited_scene_root if get_tree() and get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 5. LAS 4 TORRES ANGULARES EN AGUJA AFILADA (Canon Toriyama)
	# -------------------------------------------------------------
	# Material cel-shaded piedra plateada/cemento claro anime
	var spire_mat = StandardMaterial3D.new()
	spire_mat.albedo_color = Color(0.92, 0.94, 0.97)
	spire_mat.roughness = 0.48
	spire_mat.rim_enabled = true
	spire_mat.rim = 0.28
	spire_mat.rim_tint = 0.25

	var pillar_positions = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	# Ubicadas sobre el zócalo exterior, abrazando con precisión las esquinas del ring
	var corner_dist = 16.65

	for i in range(pillar_positions.size()):
		var p_pos = pillar_positions[i]
		var spire_root = Node3D.new()
		spire_root.name = "PillarSpire_" + str(i)
		# Anclado sobre el zócalo en Y = -0.1
		spire_root.position = Vector3(p_pos.x * corner_dist, -0.1, p_pos.y * corner_dist)
		add_child(spire_root)
		spire_root.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

		# A. Base anillada inferior (Pedestal cilíndrico)
		var ring1 = MeshInstance3D.new()
		ring1.name = "BaseRing1"
		var r1_mesh = CylinderMesh.new()
		r1_mesh.top_radius = 0.80
		r1_mesh.bottom_radius = 0.95
		r1_mesh.height = 0.35
		r1_mesh.radial_segments = 32
		ring1.mesh = r1_mesh
		ring1.position.y = 0.175
		ring1.material_override = spire_mat
		spire_root.add_child(ring1)
		ring1.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

		# B. Collarín anillado superior
		var ring2 = MeshInstance3D.new()
		ring2.name = "BaseRing2"
		var r2_mesh = CylinderMesh.new()
		r2_mesh.top_radius = 0.54
		r2_mesh.bottom_radius = 0.68
		r2_mesh.height = 0.35
		r2_mesh.radial_segments = 32
		ring2.mesh = r2_mesh
		ring2.position.y = 0.525
		ring2.material_override = spire_mat
		spire_root.add_child(ring2)
		ring2.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

		# C. Bulbo cónico inferior que ensancha hacia arriba
		var bulb = MeshInstance3D.new()
		bulb.name = "Bulb"
		var b_mesh = CylinderMesh.new()
		b_mesh.top_radius = 0.88
		b_mesh.bottom_radius = 0.52
		b_mesh.height = 1.10
		b_mesh.radial_segments = 32
		bulb.mesh = b_mesh
		bulb.position.y = 1.25
		bulb.material_override = spire_mat
		spire_root.add_child(bulb)
		bulb.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

		# D. Cuello superior de transición hacia la aguja
		var collar = MeshInstance3D.new()
		collar.name = "BulbCollar"
		var c_mesh = CylinderMesh.new()
		c_mesh.top_radius = 0.78
		c_mesh.bottom_radius = 0.88
		c_mesh.height = 0.60
		c_mesh.radial_segments = 32
		collar.mesh = c_mesh
		collar.position.y = 2.10
		collar.material_override = spire_mat
		spire_root.add_child(collar)
		collar.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

		# E. Aguja cónica afilada en punta (Aguja esbelta de 7.6m que remata en punta afilada)
		var tip = MeshInstance3D.new()
		tip.name = "SpireTip"
		var t_mesh = CylinderMesh.new()
		t_mesh.top_radius = 0.0 # Punta afilada sin esfera (Canon Toriyama)
		t_mesh.bottom_radius = 0.78
		t_mesh.height = 7.6
		t_mesh.radial_segments = 32
		tip.mesh = t_mesh
		tip.position.y = 6.20 # Altura total acumulada = 10.0m
		tip.material_override = spire_mat
		spire_root.add_child(tip)
		tip.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 6. ROCAS Y PEÑASCOS FACETADOS DE AKIRA TORIYAMA (MultiMesh)
	# -------------------------------------------------------------
	var rock_multimesh_node = MultiMeshInstance3D.new()
	rock_multimesh_node.name = "ToriyamaBoulders_MultiMesh"

	var rock_mesh = BoxMesh.new()
	rock_mesh.size = Vector3(2.4, 1.8, 2.2)

	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.65, 0.48, 0.32) # Marrón cálido arenisca
	rock_mat.roughness = 0.90
	rock_multimesh_node.material_override = rock_mat

	var rock_count = 36
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = rock_count
	multimesh.mesh = rock_mesh

	var rng = RandomNumberGenerator.new()
	rng.seed = 9000 # Semilla constante para reproducibilidad

	for idx in range(rock_count):
		var angle = rng.randf_range(0.0, TAU)
		var dist = rng.randf_range(34.0, 78.0)
		var pos_x = cos(angle) * dist
		var pos_z = sin(angle) * dist
		var scale_rnd = rng.randf_range(0.7, 2.2)
		var rot_y = rng.randf_range(0.0, TAU)
		var rot_x = rng.randf_range(-0.2, 0.2)

		var t = Transform3D()
		t = t.rotated(Vector3.UP, rot_y)
		t = t.rotated(Vector3.RIGHT, rot_x)
		t = t.scaled(Vector3(scale_rnd * rng.randf_range(0.8, 1.3), scale_rnd, scale_rnd * rng.randf_range(0.8, 1.3)))
		t.origin = Vector3(pos_x, -0.1 + (scale_rnd * 0.9) - 0.2, pos_z)

		multimesh.set_instance_transform(idx, t)

	rock_multimesh_node.multimesh = multimesh
	add_child(rock_multimesh_node)
	rock_multimesh_node.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 7. LLANURA DISTANTE CONTINUA (Elimina el corte del horizonte a 360°)
	# -------------------------------------------------------------
	var distant_ground = MeshInstance3D.new()
	distant_ground.name = "DistantGround_Disk"
	var disk_mesh = CylinderMesh.new()
	disk_mesh.top_radius = 1600.0
	disk_mesh.bottom_radius = 1600.0
	disk_mesh.height = 1.0
	disk_mesh.radial_segments = 64
	distant_ground.mesh = disk_mesh
	distant_ground.position = Vector3(0.0, -0.85, 0.0)

	var distant_mat = ShaderMaterial.new()
	var distant_shader = load("res://shaders/distant_plain.gdshader")
	if distant_shader:
		distant_mat.shader = distant_shader
	distant_ground.material_override = distant_mat
	add_child(distant_ground)
	distant_ground.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 8. CORDÓN INTERMEDIO DE MESETAS Y PEÑASCOS DE AKIRA TORIYAMA (MultiMesh)
	# -------------------------------------------------------------
	var canyon_node = MultiMeshInstance3D.new()
	canyon_node.name = "ToriyamaCanyon_MultiMesh"
	
	var mesa_mesh = CylinderMesh.new()
	mesa_mesh.top_radius = 16.0
	mesa_mesh.bottom_radius = 26.0
	mesa_mesh.height = 42.0
	mesa_mesh.radial_segments = 8
	mesa_mesh.rings = 2
	
	var mountain_mat = ShaderMaterial.new()
	var mountain_shader = load("res://shaders/toriyama_mountain.gdshader")
	if mountain_shader:
		mountain_mat.shader = mountain_shader
	canyon_node.material_override = mountain_mat
	
	var canyon_count = 48
	var canyon_mm = MultiMesh.new()
	canyon_mm.transform_format = MultiMesh.TRANSFORM_3D
	canyon_mm.instance_count = canyon_count
	canyon_mm.mesh = mesa_mesh
	
	var c_rng = RandomNumberGenerator.new()
	c_rng.seed = 7777
	
	for idx in range(canyon_count):
		var base_angle = (float(idx) / float(canyon_count)) * TAU
		var angle = base_angle + c_rng.randf_range(-0.06, 0.06)
		var dist = c_rng.randf_range(100.0, 165.0)
		var px = cos(angle) * dist
		var pz = sin(angle) * dist
		
		var scale_y = c_rng.randf_range(0.75, 1.45)
		var scale_xz = c_rng.randf_range(0.85, 1.5)
		var rot_y = c_rng.randf_range(0.0, TAU)
		
		var t = Transform3D()
		t = t.rotated(Vector3.UP, rot_y)
		t = t.scaled(Vector3(scale_xz, scale_y, scale_xz))
		var base_y = -0.5 + (42.0 * scale_y * 0.5) - 2.0
		t.origin = Vector3(px, base_y, pz)
		canyon_mm.set_instance_transform(idx, t)
		
	canyon_node.multimesh = canyon_mm
	add_child(canyon_node)
	canyon_node.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	# -------------------------------------------------------------
	# 9. GRAN CORDILLERA MONTAÑOSA DEL VALLE DE CELL (Outer Wall 360°)
	# -------------------------------------------------------------
	var wall_node = MultiMeshInstance3D.new()
	wall_node.name = "ToriyamaOuterWall_MultiMesh"
	
	var peak_mesh = CylinderMesh.new()
	peak_mesh.top_radius = 5.0
	peak_mesh.bottom_radius = 65.0
	peak_mesh.height = 115.0
	peak_mesh.radial_segments = 7
	peak_mesh.rings = 3
	wall_node.material_override = mountain_mat
	
	var wall_count = 72
	var wall_mm = MultiMesh.new()
	wall_mm.transform_format = MultiMesh.TRANSFORM_3D
	wall_mm.instance_count = wall_count
	wall_mm.mesh = peak_mesh
	
	var w_rng = RandomNumberGenerator.new()
	w_rng.seed = 8888
	
	for idx in range(wall_count):
		var base_angle = (float(idx) / float(wall_count)) * TAU
		var angle = base_angle + w_rng.randf_range(-0.04, 0.04)
		var dist = w_rng.randf_range(260.0, 480.0)
		var px = cos(angle) * dist
		var pz = sin(angle) * dist
		
		var scale_y = w_rng.randf_range(0.85, 1.65)
		var scale_xz = w_rng.randf_range(1.1, 1.85)
		var rot_y = w_rng.randf_range(0.0, TAU)
		
		var t = Transform3D()
		t = t.rotated(Vector3.UP, rot_y)
		t = t.scaled(Vector3(scale_xz, scale_y, scale_xz))
		var base_y = -0.5 + (115.0 * scale_y * 0.5) - 6.0
		t.origin = Vector3(px, base_y, pz)
		wall_mm.set_instance_transform(idx, t)
		
	wall_node.multimesh = wall_mm
	add_child(wall_node)
	wall_node.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self

	print("¡Cell Games Arena reconstruida al 100% con estética canónica de Dragon Ball Z (Cordillera 360° y Llanura Distante)!")


# -----------------------------------------------------------------
# 7. GENERACIÓN DE COLISIONADORES FÍSICOS EN RUNTIME
# -----------------------------------------------------------------
func _generate_runtime_colliders() -> void:
	# A. Suelo principal del Ring
	var floor_node = get_node_or_null("ArenaFloor_Single")
	if floor_node and floor_node is MeshInstance3D:
		var static_body = StaticBody3D.new()
		static_body.name = "FloorStaticBody"
		static_body.collision_layer = 1
		static_body.collision_mask = 1 | 2 | 4

		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(32.0, 0.8, 32.0)
		col.shape = box
		static_body.add_child(col)
		floor_node.add_child(static_body)

	# B. Zócalo inferior
	var plinth_node = get_node_or_null("ArenaPlinth_Step")
	if plinth_node and plinth_node is MeshInstance3D:
		var plinth_body = StaticBody3D.new()
		plinth_body.name = "PlinthStaticBody"
		plinth_body.collision_layer = 1
		plinth_body.collision_mask = 1 | 2

		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(36.0, 0.4, 36.0)
		col.shape = box
		plinth_body.add_child(col)
		plinth_node.add_child(plinth_body)

	# C. Terreno exterior circundante
	var ground_node = get_node_or_null("ArenaGround_Surrounding")
	if ground_node and ground_node is MeshInstance3D:
		var ground_body = StaticBody3D.new()
		ground_body.name = "GroundStaticBody"
		ground_body.collision_layer = 1
		ground_body.collision_mask = 1 | 2

		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(180.0, 1.0, 180.0)
		col.shape = box
		ground_body.add_child(col)
		ground_node.add_child(ground_body)

	# D. Colisionadores para las 4 Torres en Aguja
	for child in get_children():
		if child.name.begins_with("PillarSpire_"):
			var spire_body = StaticBody3D.new()
			spire_body.name = "SpireStaticBody_" + child.name
			spire_body.collision_layer = 1
			spire_body.collision_mask = 1 | 2 | 4

			var col = CollisionShape3D.new()
			var cylinder = CylinderShape3D.new()
			cylinder.height = 9.4
			cylinder.radius = 0.85
			col.shape = cylinder
			col.position.y = 4.7 # Centrado en la altura del pilar
			spire_body.add_child(col)
			child.add_child(spire_body)

	# E. Barrera de colisión perimetral del cañón montañoso (16 segmentos en anillo)
	var canyon_boundary = StaticBody3D.new()
	canyon_boundary.name = "CanyonBoundary_StaticBody"
	canyon_boundary.collision_layer = 1
	canyon_boundary.collision_mask = 1 | 2 | 4

	var segments = 16
	for i in range(segments):
		var ang = (float(i) / float(segments)) * TAU
		var px = cos(ang) * 98.0
		var pz = sin(ang) * 98.0
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(45.0, 40.0, 12.0)
		col.shape = box
		col.position = Vector3(px, 15.0, pz)
		col.rotation.y = -ang + (PI * 0.5)
		canyon_boundary.add_child(col)
	add_child(canyon_boundary)

	# F. Colisionadores físicos de los 48 Cañones y Mesetas de Akira Toriyama (Punto 3)
	var canyon_node = get_node_or_null("ToriyamaCanyon_MultiMesh") as MultiMeshInstance3D
	if canyon_node and canyon_node.multimesh:
		var canyon_body = StaticBody3D.new()
		canyon_body.name = "ToriyamaCanyon_StaticBody"
		canyon_body.collision_layer = 1
		canyon_body.collision_mask = 1 | 2 | 4
		var mm = canyon_node.multimesh
		for idx in range(mm.instance_count):
			var t = mm.get_instance_transform(idx)
			var col = CollisionShape3D.new()
			var cylinder = CylinderShape3D.new()
			var scale_xz = t.basis.get_scale().x
			var scale_y = t.basis.get_scale().y
			cylinder.height = 42.0 * scale_y
			cylinder.radius = 22.0 * scale_xz # Radio físico protector de la meseta
			col.shape = cylinder
			col.transform = t
			canyon_body.add_child(col)
		add_child(canyon_body)

	# G. Colisionadores físicos de las 36 Rocas y Peñascos del llano (Punto 3)
	var boulder_node = get_node_or_null("ToriyamaBoulders_MultiMesh") as MultiMeshInstance3D
	if boulder_node and boulder_node.multimesh:
		var boulder_body = StaticBody3D.new()
		boulder_body.name = "ToriyamaBoulders_StaticBody"
		boulder_body.collision_layer = 1
		boulder_body.collision_mask = 1 | 2 | 4
		var b_mm = boulder_node.multimesh
		for idx in range(b_mm.instance_count):
			var t = b_mm.get_instance_transform(idx)
			var col = CollisionShape3D.new()
			var box = BoxShape3D.new()
			var s = t.basis.get_scale()
			box.size = Vector3(2.6 * s.x, 2.0 * s.y, 2.4 * s.z)
			col.shape = box
			col.transform = t
			boulder_body.add_child(col)
		add_child(boulder_body)

	print("[ArenaBuilder] Colisionadores físicos canónicos generados con éxito.")
