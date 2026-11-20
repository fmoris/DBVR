extends Resource
class_name KiEconomyConfig
## Economía centralizada de Ki y BP (data-driven). Punto 8 y 9 del playtest.
## Objetivo: barra llena ≈ 3 Supers o ~15 Ki blasts; recarga 1 vez cada 40-60 s.

const DEFAULT_PATH: String = "res://resources/ki_economy.tres"
static var _cached: KiEconomyConfig = null

@export_group("Recarga activa")
@export var charge_ki_per_sec_heavy: float = 24.0
@export var charge_ki_per_sec_light: float = 10.0
@export var charge_bp_per_sec_heavy: float = 250.0
@export var charge_bp_per_sec_light: float = 80.0
## La carga de Ki solo puede subir el BP hasta este % del máximo activo. El resto se gana peleando.
@export_range(0.1, 1.0) var charge_bp_ceiling_ratio: float = 0.60

@export_group("Regeneración pasiva")
@export var passive_ki_regen_per_sec: float = 1.0
@export var passive_regen_delay_sec: float = 2.0
@export var ki_regen_per_bp_lost: float = 0.0055

@export_group("Costos")
@export var super_charge_drain_per_sec: float = 6.0
@export var ki_blast_charge_drain_per_sec: float = 2.0
@export var ki_blast_cost: float = 3.0
@export var ki_blast_charged_cost: float = 9.0
@export var ki_blast_rapid_vegeta_cost: float = 2.5
@export var melee_dash_cost: float = 10.0
@export var melee_quick_cost: float = 5.0
@export var melee_charged_cost: float = 11.0
@export var melee_v3_cost: float = 16.0
@export var melee_hammer_guard_cost: float = 20.0
@export var melee_guard_escalation: float = 2.0
@export var ai_dodge_cost: float = 4.0

@export_group("Melee Overhaul - Administrador de Ki")
@export var melee_hammer_cost: float = 22.0
@export var melee_guard_quick_cost: float = 7.0
@export var melee_guard_charged_cost: float = 12.0
@export var melee_guard_v3_cost: float = 16.0
@export var melee_vanish_cost: float = 14.0
@export var melee_explosive_wave_cost: float = 22.0
@export var melee_meteor_chase_cost: float = 12.0
@export var melee_sonic_ki_refund: float = 1.5
@export var melee_parry_ki_reward: float = 14.0
@export var melee_deflect_ki_reward: float = 5.0
@export var melee_clash_cost: float = 4.0
@export var melee_clash_win_reward: float = 8.0
@export var melee_crater_super_charge_mult: float = 1.35

@export_group("Ki Blast Tactical Overhaul")
@export var ki_blast_deflect_ki_reward: float = 12.0
@export var ki_blast_deflect_bp_reward: float = 150.0
@export var ki_blast_pressure_decay_sec: float = 2.8
@export var ki_blast_rapid_ki_drain: float = 3.0
@export var ki_blast_charged_ki_drain: float = 9.0
@export var ki_blast_charged_guard_ki_drain: float = 16.0
@export var ki_blast_smoke_super_charge_mult: float = 1.25

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
