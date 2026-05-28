extends Node3D

## ProceduralKiProjectile: Comportamiento físico precompilado para proyectiles 3D de Ki Blast.
## Optimizado para Meta Quest 3 (Evita spikes de CPU por compilación dinámica).

var speed_velocity: Vector3 = Vector3.ZERO
var lifetime_left: float = 4.0
var p_radius: float = 0.05
var p_color: Color = Color.WHITE
var is_dead: bool = false
var ray_query_exclude: Array[RID] = []

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Mover en línea recta en el bucle físico
	var step = speed_velocity * delta
	var prev_pos = global_position
	global_position += step
	
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		queue_free()
		return
		
	# Raycast continuo para detección estable de colisiones
	var space = get_world_3d().direct_space_state
	if space:
		var parameters = PhysicsRayQueryParameters3D.create(prev_pos, global_position)
		parameters.exclude = ray_query_exclude
		var collision = space.intersect_ray(parameters)
		if collision:
			is_dead = true
			# Llamar a la detonación de forma diferida para no interferir en el hilo físico de Jolt
			call_deferred("_trigger_explosion", collision.position, collision.collider)

func _trigger_explosion(pos: Vector3, collider: Node) -> void:
	# 1. Fallback de partículas local rápido
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = p_radius * 0.5
	sphere_mesh.height = p_radius
	flash.mesh = sphere_mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = p_color
	flash.material_override = mat
	flash.global_position = pos
	get_tree().root.add_child(flash)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(p_color.r, p_color.g, p_color.b, 0.0), 0.2).set_trans(Tween.TRANS_LINEAR)
	
	# Imprimir log del combate de Ki
	print("[COMBATE DE KI] ¡EXPLOSIÓN DE KI BLAST! Impacto contra: ", collider.name)
	
	# 2. Buscar e intentar reproducir VFX de partículas de chispas de Ki en el visualizador de manos
	var hand_visualizer = get_tree().root.find_child("vr_hand_visualizer*", true, false)
	if hand_visualizer and hand_visualizer.has_method("_spawn_ki_impact_vfx"):
		hand_visualizer.call_deferred("_spawn_ki_impact_vfx", pos, p_color)
	
	# Limpiar
	tween.chain().tween_callback(flash.queue_free)
	queue_free()
