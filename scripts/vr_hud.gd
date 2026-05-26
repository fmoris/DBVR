@tool
extends Node3D

# --- Parámetros de Posicionamiento Fijo (Espacio Local de Cámara) ---
@export var distance_from_camera: float = 1.2
@export var horizontal_offset: float = -0.35 # Centrado para ser visible sin cortarse en lentes (Quest 3)
@export var vertical_offset: float = -0.3   # Ajustado un poco más arriba para comodidad visual

@onready var sub_viewport: SubViewport = $SubViewport
@onready var hud_mesh: MeshInstance3D = $HUDMesh

# Referencias a nodos de la UI interna (usamos get_node_or_null para seguridad en modo @tool)
@onready var ki_bar: ProgressBar = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/KiSection/KiBar")
@onready var ki_value_label: Label = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/KiSection/Labels/Value")
@onready var np_bar: ProgressBar = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/NPSection/NPBar")
@onready var np_value_label: Label = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/NPSection/Labels/Value")
@onready var phase_status_label: Label = get_node_or_null("SubViewport/HUDLayout/MainPanel/MarginContainer/VBoxContainer/PhaseStatus")

# --- Estado del Combate Dinámico (Inicia Ki en 0) ---
var ki_max: float = 100.0
var ki_current: float = 0.0 # Partir en 0 a solicitud del usuario para probar la carga
var np_max: float = 20000.0
var np_current: float = 9000.0

var is_recharging: bool = false
var is_heavy_recharge: bool = false

func _ready() -> void:
	if not sub_viewport or not hud_mesh:
		return
	# Configurar el material dinámico para evitar fallos de vinculación en .tscn
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Glow perfecto sin sombras
	mat.albedo_texture = sub_viewport.get_texture()
	hud_mesh.material_override = mat

	if not Engine.is_editor_hint():
		# Llamamos diferido para dar tiempo a que la cámara y el árbol de nodos se inicialicen completamente
		call_deferred("_reparent_to_camera")

func _reparent_to_camera() -> void:
	var camera = get_viewport().get_camera_3d()
	if camera:
		# Si ya somos hijos de la cámara, no hace falta reparentar
		if get_parent() != camera:
			var old_parent = get_parent()
			if old_parent:
				old_parent.remove_child(self)
			camera.add_child(self)
		
		# Establecer la transformación local rígida (abajo a la izquierda y al frente)
		position = Vector3(horizontal_offset, vertical_offset, -distance_from_camera)
		rotation = Vector3.ZERO
		
		# Forzar que el procesamiento continúe en runtime para el cálculo de estadísticas
		set_process(true)
		
		# Inicializar visualmente en 0
		update_ki(ki_current, ki_max)
		update_power_level(np_current, np_max)
		
		# Conexión dinámica con el árbol de decisiones biométrico
		var gesture_tree = get_node_or_null("/root/cell_games_arena/GesturePhaseTree")
		if not gesture_tree:
			gesture_tree = get_tree().root.find_child("GesturePhaseTree", true, false)
			
		if gesture_tree:
			gesture_tree.ki_recharge_started.connect(_on_recharge_started)
			gesture_tree.ki_recharge_stopped.connect(_on_recharge_stopped)
			gesture_tree.ki_blast_fired.connect(_on_ki_blast_fired)
			print("[VRHUD] Conexión establecida con GesturePhaseTree. Ki inicializado en 0.")

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_editor_position()
		return
		
	# Bucle de juego en runtime: procesar únicamente el incremento y consumo de Ki/NP
	_update_combat_stats(delta)

func _update_editor_position() -> void:
	var camera: Camera3D = null
	var tree_root = get_tree().edited_scene_root
	if tree_root:
		camera = tree_root.find_child("XRCamera3D", true, false) as Camera3D
	if not camera:
		camera = get_viewport().get_camera_3d()

	if not camera:
		return

	var local_offset = Vector3(horizontal_offset, vertical_offset, -distance_from_camera)
	global_position = camera.global_transform * local_offset
	global_transform.basis = camera.global_transform.basis

# --- Callbacks de Señales del Gesto de Combate ---

func _on_recharge_started(is_heavy: bool) -> void:
	is_recharging = true
	is_heavy_recharge = is_heavy

func _on_recharge_stopped() -> void:
	is_recharging = false
	is_heavy_recharge = false

func _on_ki_blast_fired(hand_side: int) -> void:
	var cost = 15.0 # Cada disparo consume 15 unidades de Ki
	if ki_current >= cost:
		ki_current -= cost
		update_ki(ki_current, ki_max)
		print("[VRHUD] Ki Blast disparado por mano %s. Ki restante: %.1f" % ["Izquierda" if hand_side == 0 else "Derecha", ki_current])
	else:
		print("[VRHUD] ¡Ki insuficiente para disparar ráfagas! Requieres acumular energía.")

func _update_combat_stats(delta: float) -> void:
	if is_recharging:
		var recharge_speed = 35.0 if is_heavy_recharge else 12.0
		ki_current = min(ki_current + recharge_speed * delta, ki_max)
		
		# Incrementar NP dinámicamente según la intensidad de la carga
		if is_heavy_recharge:
			np_current = min(np_current + 1800.0 * delta, np_max)
		else:
			np_current = min(np_current + 400.0 * delta, np_max)
			
		update_ki(ki_current, ki_max)
		update_power_level(np_current, np_max)
	else:
		# Enfriamiento sutil del Nivel de Poder cuando no se está cargando energía
		if np_current > 9000.0:
			np_current = max(np_current - 200.0 * delta, 9000.0)
			update_power_level(np_current, np_max)

# --- APIs Públicas para Actualización de la Interfaz ---

func update_ki(current: float, max_val: float) -> void:
	if ki_bar:
		ki_bar.max_value = max_val
		ki_bar.value = current
	if ki_value_label:
		ki_value_label.text = "%d / %d" % [int(current), int(max_val)]

func update_power_level(current: float, max_val: float) -> void:
	if np_bar:
		np_bar.max_value = max_val
		np_bar.value = current
	if np_value_label:
		np_value_label.text = "%s" % format_number_with_commas(int(current))

func update_status_text(text: String, color: Color = Color(0.9, 0.9, 0.9)) -> void:
	if phase_status_label:
		phase_status_label.text = text
		phase_status_label.label_settings.font_color = color

# Helper para añadir comas a miles en GDScript
func format_number_with_commas(n: int) -> String:
	var s = str(n)
	var res = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count == 3 and i > 0:
			res = "," + res
			count = 0
	return res
