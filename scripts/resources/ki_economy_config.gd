extends Resource
class_name KiEconomyConfig
## Economía centralizada de Ki y BP (data-driven). Punto 8 y 9 del playtest.
## Objetivo: barra llena ≈ 3 Supers o ~15 Ki blasts; recarga 1 vez cada 40-60 s.

const DEFAULT_PATH: String = "res://resources/ki_economy.tres"
static var _cached: KiEconomyConfig = null

@export_group("Recarga activa")
@export var charge_ki_per_sec_heavy: float = 30.0
@export var charge_ki_per_sec_light: float = 12.0
@export var charge_bp_per_sec_heavy: float = 250.0
@export var charge_bp_per_sec_light: float = 80.0
## La carga de Ki solo puede subir el BP hasta este % del máximo activo. El resto se gana peleando.
@export_range(0.1, 1.0) var charge_bp_ceiling_ratio: float = 0.60

@export_group("Regeneración pasiva")
@export var passive_ki_regen_per_sec: float = 1.5
@export var passive_regen_delay_sec: float = 1.5
@export var ki_regen_per_bp_lost: float = 0.004

@export_group("Costos")
@export var super_charge_drain_per_sec: float = 6.0
@export var ki_blast_charge_drain_per_sec: float = 3.0
@export var ki_blast_cost: float = 2.0
@export var ki_blast_charged_cost: float = 6.0
@export var melee_dash_cost: float = 8.0
@export var melee_quick_cost: float = 3.0
@export var melee_charged_cost: float = 5.0
@export var melee_v3_cost: float = 8.0
@export var melee_hammer_guard_cost: float = 10.0
@export var melee_guard_escalation: float = 1.0
@export var ai_dodge_cost: float = 4.0

@export_group("Umbrales irreversibles de BP")
## Al alcanzar el 100% el piso asegurado queda en este ratio (no 1.0) para que el BP siga oscilando.
@export_range(0.5, 1.0) var secured_floor_at_full: float = 0.90


static func get_default() -> KiEconomyConfig:
	if _cached == null:
		if ResourceLoader.exists(DEFAULT_PATH):
			_cached = load(DEFAULT_PATH) as KiEconomyConfig
		if _cached == null:
			_cached = KiEconomyConfig.new()
	return _cached
