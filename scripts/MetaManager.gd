extends Node

## MetaManager: Centraliza la integración con Meta Quest Platform SDK.
## Requisitos: Tener instalado el addon Godot Meta Toolkit.

signal initialization_completed(success: bool)
signal user_data_received(user_info)

@export var app_id: String = "26734400099551811" # ID de DBZVR en Meta
@export var auto_initialize: bool = true

func _ready():
	if auto_initialize:
		if app_id == "YOUR_APP_ID_HERE":
			print("[MetaManager] WARNING: No se ha configurado el App ID de Meta.")
			return
		setup_meta()

func setup_meta():
	if !OS.has_feature("android"):
		print("[MetaManager] Ejecutando en PC/Simulador. Saltando inicialización de Platform SDK.")
		initialization_completed.emit(true)
		return

	print("[MetaManager] Iniciando Platform SDK (Android)...")
	
	# 1. Inicializar Plataforma
	var result = await MetaPlatformSDK.initialize_platform_async(app_id).completed
	if result.is_error():
		printerr("[MetaManager] Fallo en inicialización: ", result.error)
		initialization_completed.emit(false)
		return

	# 2. Verificar Entitlement (Propiedad del App)
	result = await MetaPlatformSDK.entitlement_get_is_viewer_entitled_async().completed
	if result.is_error():
		printerr("[MetaManager] El usuario no tiene licencia legal de la app: ", result.error)
		initialization_completed.emit(false)
		# Opcional: Cerrar el juego si es obligatorio
		# get_tree().quit()
		return

	# 3. Obtener Usuario Actual
	result = await MetaPlatformSDK.user_get_logged_in_user_async().completed
	if !result.is_error():
		user_data_received.emit(result.data)
		print("[MetaManager] Usuario autenticado: ", result.data.display_name)

	print("[MetaManager] Meta SDK listo y verificado.")
	initialization_completed.emit(true)

func get_friends():
	var result = await MetaPlatformSDK.user_get_logged_in_user_friends_async().completed
	if result.is_error():
		return []
	return result.data # MetaPlatformSDK_UserArray
