import { Scene, Observer, Vector3 } from "@babylonjs/core";
import { VFXManager, AttackType } from "../vfx/VFXManager";
import powersConfig from "../../models/powers.json";
import gokuConfig from "../../models/goku.json";
import vegetaConfig from "../../models/vegeta.json";
import * as CombatUtils from "./CombatUtils";
import { CombatAI } from "./CombatAI";

export type CombatState =
  | "neutral"
  | "charging"
  | "charging_special"
  | "attacking"
  | "defending"
  | "slowMotion"
  | "hit"
  | "melee"
  | "recharging";

export type SpecialAttackType = string;

export type PowerLevel = 1 | 2 | 3 | 4 | 5;

export interface GameStats {
  playerName?: string;
  enemyName?: string;
  playerKi: number;
  maxKi: number;
  playerNP: number;
  enemyNP: number;
  enemyKi: number;
  enemyMaxKi: number;
  combatState: CombatState;
  isSlowMotion: boolean;
  currentAttack: AttackType | null;
  chargeTime: number;
  specialType: SpecialAttackType | null;
  gameOver: boolean;
  winner: "player" | "enemy" | null;
  enemyAttacking: boolean;
  enemyAttackName: string;
  enemyAttackType: "basic" | "special" | null;
}

type StatsListener = (stats: GameStats) => void;

// Costos de KI generales
const KI_COSTS = {
  basicAttack: 8,
  chargedAttack: { base: 20, perSecond: 5 },
  block: 15,
  dodge: 5,
  deflect: 10,
};

// Danos base generales
const DAMAGE = {
  basicAttack: 10,
  chargedAttack: { base: 20, perSecond: 10 },
};

export interface ChargeLevel extends CombatUtils.ChargeLevel {}

// Niveles de carga para ataques especiales generados dinámicamente
const SPECIAL_LEVELS: Record<string, ChargeLevel[]> = {};
const powersDict = powersConfig as Record<string, any>;

for (const [key, details] of Object.entries(powersDict)) {
  if (details.charge_time) {
    const ct = details.charge_time;
    SPECIAL_LEVELS[key.toLowerCase()] = [
      { label: "MINIMO",  timeMin: ct * 0.5, timeMax: ct * 0.9, ki: 40,  damage: 40  },
      { label: "MEDIO",   timeMin: ct,       timeMax: ct * 1.5, ki: 60,  damage: 70  },
      { label: "MAXIMO",  timeMin: ct * 1.6, timeMax: 99,       ki: 80,  damage: 100 },
    ];
  }
}

// Las utilidades se han movido a CombatUtils.ts

export class CombatSystem {
  private stats: GameStats = {
    playerName: gokuConfig.name, 
    enemyName: vegetaConfig.name,
    playerKi: 100,
    maxKi: 100,
    playerNP: gokuConfig.base_power,
    enemyNP: vegetaConfig.base_power,
    enemyKi: 100,
    enemyMaxKi: 100,
    combatState: "neutral",
    isSlowMotion: false,
    currentAttack: null,
    chargeTime: 0,
    specialType: null,
    gameOver: false,
    winner: null,
    enemyAttacking: false,
    enemyAttackName: "",
    enemyAttackType: null,
  };

  private listeners: StatsListener[] = [];
  private gameOverCallbacks: Array<(winner: "player" | "enemy") => void> = [];
  private messageListeners: Array<(msg: string, color?: string) => void> = [];
  
  // Referencia a la IA
  private enemyAI: CombatAI | null = null;
  
  // Observador de Babylon para el bucle de juego (Phase 16)
  private sceneObserver: Observer<Scene> | null = null;
  private lastUpdateTime: number = 0;
  private slowMotionTimeout: ReturnType<typeof setTimeout> | null = null;
  
  public mirrorMode = false;

  // Estado de carga especial
  private activeSpecial: SpecialAttackType | null = null;
  private specialChargeStart = 0;

  // Estado de carga normal
  private isChargingNormal = false;
  private availablePowers: string[] = [];
  
  // Soporte para bonos de Voz (Phase 10)
  private lastVoiceActivity = 0;
  private lastVoiceTrigger: string | null = null;
  private lastVoiceTriggerTime = 0;

  // Soporte para posiciones dinámicas de ataques especiales (Phase 12)
  private activeSpecialOrigin: Vector3 | undefined = undefined;

  private playerHeight: number = 1.75;
  private enemyHeight: number = 1.64;

  public playerName = "Player";
  public enemyName = "Enemy";

  constructor(private scene: Scene, private vfx: VFXManager, playerConfig?: any, enemyConfig?: any) {
    this.playerHeight = playerConfig?.height_m || gokuConfig.height_m || 1.75;
    this.enemyHeight = enemyConfig?.height_m || (vegetaConfig as any).height_m || 1.64;
    
    this.setAvailablePowers(playerConfig?.transformations?.[0]?.powers || gokuConfig.transformations?.[0]?.powers || []);
    this.stats.playerKi = 50; // Inicio al 50% para facilitar pruebas
    this.stats.enemyKi = 50;
    if (playerConfig) {
      this.playerName = playerConfig.name || "Goku";
      this.stats.playerNP = playerConfig.base_power || 10000;
      this.log(`Jugador: ${this.playerName} (NP: ${this.stats.playerNP})`, "#00ccff");
    }
    if (enemyConfig) {
      this.enemyName = enemyConfig.name || "Vegeta";
      this.stats.enemyNP = enemyConfig.base_power || 10000;
      this.log(`Enemigo: ${this.enemyName} (NP: ${this.stats.enemyNP})`, "#ff4444");
    }

    // Inicializar IA (desactivada si así se pide)
    const aiEnabled = true; 
    if (aiEnabled) {
      this.enemyAI = new CombatAI(this);
      this.enemyAI.start();
    }

    // Suscribirse al bucle de renderizado
    this.sceneObserver = this.scene.onBeforeRenderObservable.add(() => this.update());
    this.lastUpdateTime = Date.now();
  }

  /**
   * Bucle principal de lógica de combate (Phase 16)
   * Reemplaza a todos los setInteral para mayor precisión.
   */
  private update(): void {
    if (this.stats.gameOver) return;

    const now = Date.now();
    const dt = (now - this.lastUpdateTime) / 1000; // Delta time en segundos
    this.lastUpdateTime = now;

    // 1. Regeneración de Ki (Jugador)
    if (this.stats.combatState === "neutral") {
      // Regeneración base desactivada para pruebas de gestos
      const regenRate = 0;
      this.stats.playerKi = Math.min(this.stats.maxKi, this.stats.playerKi + regenRate * dt);
    }

    // 2. Regeneración de Ki (Enemigo) - Desactivada para pruebas
    const enemyRegenRate = 0;
    this.stats.enemyKi = Math.min(this.stats.enemyMaxKi, this.stats.enemyKi + enemyRegenRate * dt);

    // 3. Prototipo de carga (Ataque Cargado Normal)
    if (this.stats.combatState === "charging" && this.isChargingNormal) {
      this.stats.chargeTime += dt;
      if (this.stats.chargeTime > 0.3) {
        this.vfx.updateChargeEffect(this.stats.chargeTime, "normal", undefined, 2.0);
      }
      if (this.stats.chargeTime > 1.0) {
        this.stats.playerKi = Math.max(0, this.stats.playerKi - 30 * dt); // 30 Ki por segundo
      }
      if (this.stats.playerKi <= 0) this.cancelCharge();
    }

    // 4. Carga de Ataque Especial
    if (this.stats.combatState === "charging_special" && this.activeSpecial) {
      const id = this.activeSpecial.toLowerCase();
      const maxLevel = SPECIAL_LEVELS[id][2];
      const kiPerSec = maxLevel.ki / maxLevel.timeMin;
      
      this.stats.chargeTime += dt;
      this.stats.playerKi = Math.max(0, this.stats.playerKi - kiPerSec * dt);

      const minLevel = SPECIAL_LEVELS[id][0];
      if (this.stats.playerKi <= 0 && this.stats.chargeTime < minLevel.timeMin) {
        this.log("Ki Agotado: Carga Fallida", "#ff4444");
        this.cancelCharge();
      } else {
        this.vfx.updateChargeEffect(this.stats.chargeTime, this.activeSpecial, this.activeSpecialOrigin, minLevel.timeMin);
      }
    }

    // 5. Recarga Activa (Jugador)
    if (this.stats.combatState === "recharging") {
      const isGritando = false; // (now - this.lastVoiceActivity) < 1500; // Pausado
      const kiGainSec = isGritando ? 60 : 25; // Equivale a kiGain 12 y 5 cada 200ms
      
      this.stats.playerKi = Math.min(this.stats.maxKi, this.stats.playerKi + kiGainSec * dt);
      if (this.stats.playerKi >= this.stats.maxKi) this.stopRecharge();
    }

    this.emit();
  }

  onGameOver(callback: (winner: "player" | "enemy") => void): void {
    this.gameOverCallbacks.push(callback);
  }

  onStatsChange(listener: StatsListener): void {
    this.listeners.push(listener);
  }

  onMessage(listener: (msg: string, color?: string) => void): void {
    this.messageListeners.push(listener);
  }

  private log(msg: string, color: string = "white"): void {
    // console.log(`[Combat] ${msg}`);
    this.messageListeners.forEach(l => l(msg, color));
  }

  private emit(): void {
    this.listeners.forEach((l) => l({ ...this.stats }));
  }

  private setState(state: CombatState): void {
    this.stats.combatState = state;
    this.emit();
  }


  // Los métodos de regeneración legacy han sido eliminados.
  // La lógica ahora reside en el método update().

  public enemyLaunchBasic(): void {
    const kiCost = 20;
    if (this.stats.enemyKi < kiCost) return;
    this.stats.enemyKi -= kiCost;
    this.stats.enemyAttacking = true;
    this.stats.enemyAttackName = "Ataque KI";
    this.stats.enemyAttackType = "basic";
    this.emit();

    // Calcular dano del enemigo
    const baseDamage = 8 + Math.random() * 12; // 8-20
    const factor = CombatUtils.npDamageFactor(this.stats.enemyNP);
    const damage = baseDamage * factor;

    // Proyectil del enemigo (viene desde el frente)
    this.vfx.spawnKiProjectile(
      { x: 0, y: this.enemyHeight * 0.8, z: 15 },
      { x: 0, y: this.playerHeight * 0.6, z: 0 },
      "basic",
      () => { this.onEnemyAttackImpact(damage); }
    );

    setTimeout(() => {
      this.stats.enemyAttacking = false;
      this.stats.enemyAttackName = "";
      this.stats.enemyAttackType = null;
      this.emit();
    }, 700);
  }

  public enemyLaunchSpecial(type: string): void {
    const powerConfig = (powersConfig as any)[type];
    const kiCost = 60; // Consumo estandar AI
    if (this.stats.enemyKi < kiCost) return;
    this.stats.enemyKi -= kiCost;

    const attackName = powerConfig ? (powerConfig.name || type) : type;
    this.stats.enemyAttacking = true;
    this.stats.enemyAttackName = attackName + "!!!";
    this.stats.enemyAttackType = "special";
    this.emit();

    const baseDamage = 45;
    const factor = CombatUtils.npDamageFactor(this.stats.enemyNP);
    const damage = baseDamage * factor;

    if (type === "kamehameha" || type === "galick_gun") {
      this.vfx.spawnKamehameha(
        { x: 0, y: this.enemyHeight * 0.8, z: 15 },
        { x: 0, y: this.playerHeight * 0.6, z: 0 },
        4,
        () => {
          this.onEnemyAttackImpact(damage);
          this.activateSlowMotion(1200, 0.3);
        }
      );
    } else if (type === "finalFlash" || type === "final_flash") {
      this.vfx.spawnFinalFlash(
        { x: 0, y: this.enemyHeight * 0.8, z: 15 },
        { x: 0, y: this.playerHeight * 0.6, z: 0 },
        6,
        () => {
          this.onEnemyAttackImpact(damage);
          this.activateSlowMotion(1500, 0.25);
        }
      );
    } else {
      this.vfx.spawnKiProjectile(
        { x: 0, y: this.enemyHeight * 0.8, z: 15 },
        { x: 0, y: this.playerHeight * 0.6, z: 0 },
        "charged",
        () => {
          this.onEnemyAttackImpact(damage);
          this.activateSlowMotion(1200, 0.3);
        }
      );
    }

    setTimeout(() => {
      this.stats.enemyAttacking = false;
      this.stats.enemyAttackName = "";
      this.stats.enemyAttackType = null;
      this.emit();
    }, 1200);
  }

  /** Acción de recarga disparada por la IA */
  public enemyTriggerRecharge(): void {
    this.stats.enemyAttacking = false; 
    this.stats.enemyAttackName = "Recargando KI";
    this.stats.enemyAttackType = null;
    this.emit();
    setTimeout(() => {
      this.stats.enemyAttackName = "";
      this.emit();
    }, 800);
  }

  private onEnemyAttackImpact(damage: number): void {
    if (this.stats.gameOver) return;
    const isDefending = this.stats.combatState === "defending";
    const damageReduction = CombatUtils.getPowerLevelDamageReduction(this.stats.playerNP);
    const finalDamage = isDefending ? damage * 0.3 : damage * (1 - damageReduction);

    // El jugador PIERDE NP al ser golpeado
    this.stats.playerNP = Math.max(0, this.stats.playerNP - finalDamage * 2.0);
    this.stats.enemyNP = Math.min(100000, this.stats.enemyNP + damage * 0.5);
    
    this.log(`¡RECIBISTE GOLPE! -${finalDamage.toFixed(0)} DAÑO`, "#ff2222");
    this.emit();
    this.checkVictoryCondition();
  }

  // ============================================
  // ATAQUE BASICO DE KI
  // ============================================
  launchBasicAttack(): boolean {
    if (this.stats.playerKi < KI_COSTS.basicAttack) return false;
    if (this.stats.combatState !== "neutral") return false;
    if (this.stats.enemyAttacking) return false; 

    this.stats.playerKi -= KI_COSTS.basicAttack;
    this.setState("attacking");
    this.stats.currentAttack = "basic";
    this.emit();

    this.vfx.spawnKiProjectile(
      { x: -0.2, y: this.playerHeight * 0.7, z: 0.5 },
      { x: 0, y: this.enemyHeight * 0.6, z: 18 },
      "basic",
      () => { this.onAttackImpact(DAMAGE.basicAttack); }
    );

    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
        this.emit();
      }
    }, 600);
    return true;
  }

  // ============================================
  // ATAQUE DE KI CARGADO
  // ============================================
  startChargedAttack(): boolean {
    if (this.stats.playerKi < KI_COSTS.chargedAttack.base) return false;
    if (this.stats.combatState !== "neutral") return false;
    if (this.stats.enemyAttacking) return false; 

    this.isChargingNormal = true;
    this.stats.chargeTime = 0;
    this.setState("charging");
    this.vfx.showChargeEffect(true);
    return true;
  }

  releaseChargedAttack(): void {
    if (this.stats.combatState !== "charging" || !this.isChargingNormal) return;

    const chargeTime = Math.max(0.5, Math.min(3, this.stats.chargeTime));
    const damage = DAMAGE.chargedAttack.base + Math.max(0, chargeTime - 1) * DAMAGE.chargedAttack.perSecond;
    const kiCost = KI_COSTS.chargedAttack.base;

    if (this.stats.playerKi < kiCost) {
      this.cancelCharge();
      return;
    }

    this.stats.playerKi -= kiCost;
    this.isChargingNormal = false;
    this.stats.chargeTime = 0;
    this.setState("attacking");
    this.stats.currentAttack = "charged";
    this.vfx.showChargeEffect(false);
    this.emit();

    this.vfx.spawnKiProjectile(
      { x: 0, y: this.playerHeight * 0.75, z: 0.5 },
      { x: 0, y: this.enemyHeight * 0.6, z: 18 },
      "charged",
      () => {
        this.onAttackImpact(damage);
        this.activateSlowMotion(800, 0.4);
      }
    );

    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
        this.emit();
      }
    }, 800);
  }

  private cancelCharge(): void {
    this.isChargingNormal = false;
    this.activeSpecial = null;
    this.stats.chargeTime = 0;
    this.stats.specialType = null;
    this.vfx.showChargeEffect(false);
    this.activeSpecialOrigin = undefined;
    this.setState("neutral");
    this.emit();
  }

  // ============================================
  // ATAQUES ESPECIALES — modelo simplificado
  //
  // Teclado:  1 = iniciar Kamehameha, presionar 1 de nuevo = lanzar
  //           2 = iniciar Final Flash, presionar 2 de nuevo = lanzar
  //
  // Gestos VR: primer gesto inicia, segundo gesto lanza
  // ============================================

  triggerSpecial(attackName: string, origin?: Vector3): boolean {
    const id = attackName.toLowerCase();
    const power = (powersConfig as any)[id];

    if (this.activeSpecial?.toLowerCase() === id) {
      // Verificar tiempo minimo (Phase 17 - Regla de Cancelación Prematura)
      const elapsed = this.stats.chargeTime;
      if (power && power.charge_time && elapsed < power.charge_time) {
          this.log(`¡FALLO! Liberación prematura de ${attackName.toUpperCase()}`, "#ff4444");
          this.cancelSpecial();
          return false;
      }
      
      this.log(`Lanzando ${attackName.toUpperCase()}!`, "#00ff88");
      return this.launchSpecial(id, origin);
    } else if (this.stats.combatState === "neutral") {
      this.log(`Iniciando carga de ${attackName.toUpperCase()}...`, "#ff8800");
      return this.beginSpecialCharge(id, origin);
    }
    return false;
  }

  /**
   * Cancela el ataque especial actual, deteniendo VFX y reseteando estado.
   */
  public cancelSpecial(): void {
    if (this.stats.combatState === "charging_special" || this.activeSpecial) {
        this.activeSpecial = null;
        this.stats.chargeTime = 0;
        this.stats.specialType = null;
        this.vfx.showChargeEffect(false);
        this.setState("neutral");
        this.emit();
    }
  }

  /**
   * Actualiza el origen de la carga en tiempo real (Phase 14)
   * Útil para que la esfera siga las manos en VR.
   */
  public updateSpecialChargeOrigin(origin: Vector3): void {
    if (this.stats.combatState === "charging_special") {
        if (!this.activeSpecialOrigin) this.activeSpecialOrigin = new Vector3();
        this.activeSpecialOrigin.copyFrom(origin);
    }
  }

  private beginSpecialCharge(type: string, origin?: Vector3): boolean {
    const id = type.toLowerCase();
    // Validar si el poder está habilitado para este personaje/transformación
    if (!this.availablePowers.some(p => p.toLowerCase() === id)) {
      console.warn(`[CombatSystem] El poder ${type} no está disponible actualmente.`);
      return false;
    }

    // Verificar KI minimo para el primer nivel (safe check)
    const firstLevel = SPECIAL_LEVELS[id]?.[0];
    if (!firstLevel || this.stats.playerKi < firstLevel.ki) return false;

    this.activeSpecial = type;
    this.specialChargeStart = Date.now();
    this.activeSpecialOrigin = origin ? origin.clone() : new Vector3(0.3, this.playerHeight * 0.7, 0.5);
    this.stats.chargeTime = 0;
    this.stats.specialType = type;
    this.setState("charging_special");
    this.vfx.showChargeEffect(true, type, this.activeSpecialOrigin);

    return true;
  }

  private launchSpecial(type: string, origin?: Vector3): boolean {
    const elapsed = (Date.now() - this.specialChargeStart) / 1000;

    // Determinar nivel de carga alcanzado
    const level = CombatUtils.getChargeLevel(SPECIAL_LEVELS[type.toLowerCase()], elapsed);
    if (!level) {
      this.cancelCharge();
      return false;
    }

    // Calcular daño final con factor de NP
    const damage = level.damage * CombatUtils.npDamageFactor(this.stats.playerNP);

    // Si pasaron un origen en el lanzamiento, lo usamos, sino el que guardamos al cargar
    const finalOrigin = origin || this.activeSpecialOrigin || new Vector3(0, this.playerHeight * 0.7, 0.3);

    this.activeSpecial = null;
    this.activeSpecialOrigin = undefined;
    this.stats.chargeTime = 0;
    this.stats.specialType = null;
    this.setState("attacking");
    this.stats.currentAttack = type;
    this.vfx.showChargeEffect(false);
    this.emit();

    if (type === "kamehameha") {
      // Bullet time al LANZAR: 300ms de ramp-in + 3500ms en slow + 500ms ramp-out
      this.activateSlowMotion(3500, 0.18);
      this.vfx.spawnKamehameha(
        finalOrigin,
        { x: 0, y: this.enemyHeight * 0.6, z: 20 },
        elapsed,
        () => {
          this.onAttackImpact(damage);
        }
      );
    } else if (type === "finalFlash" || type === "final_flash") {
      // Final Flash: más largo y más lento
      this.activateSlowMotion(4500, 0.12);
      this.vfx.spawnFinalFlash(
        finalOrigin,
        { x: 0, y: this.enemyHeight * 0.6, z: 20 },
        elapsed,
        () => {
          this.onAttackImpact(damage);
        }
      );
    } else {
      // GENERIC FALLBACK FOR ANY DYNAMIC POWER FROM POWERS.JSON
      this.activateSlowMotion(2500, 0.25);
      // We will cast a generic big charged ball as fallback
      this.vfx.spawnKiProjectile(
        finalOrigin,
        { x: 0, y: this.enemyHeight * 0.6, z: 20 },
        "charged",
        () => {
          this.onAttackImpact(damage);
        }
      );
    }

    // El estado "attacking" dura hasta que termina el bullet time (slow motion)
    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
        this.emit();
      }
    }, type === "kamehameha" ? 4500 : (type === "finalFlash" ? 5500 : 3500));

    return true;
  }

  /** Consume KI de forma segura, retorna false si no hay suficiente */
  consumeKi(amount: number): boolean {
    if (this.stats.playerKi < amount) return false;
    this.stats.playerKi -= amount;
    this.emit();
    return true;
  }

  // ============================================
  // DEFENSAS
  // ============================================
  activateBlock(): boolean {
    if (this.stats.playerKi < KI_COSTS.block) return false;
    if (this.stats.combatState !== "neutral") return false;
    
    if (!this.stats.enemyAttacking) {
      if (this.stats.enemyAttackName === "Recargando KI") {
        this.log("Bloqueo ignorado: El enemigo solo está recargando.");
      }
      return false; 
    }

    this.stats.playerKi -= KI_COSTS.block;
    this.setState("defending");
    this.vfx.showBlockShield(true);

    setTimeout(() => {
      this.vfx.showBlockShield(false);
      if (this.stats.combatState === "defending") this.setState("neutral");
    }, 1500);
    return true;
  }

  activateDodge(): boolean {
    if (this.stats.playerKi < KI_COSTS.dodge) return false;
    if (this.stats.combatState !== "neutral") return false;
    if (!this.stats.enemyAttacking) return false; 

    this.stats.playerKi -= KI_COSTS.dodge;
    this.setState("defending");
    this.vfx.showDodgeEffect();

    setTimeout(() => {
      if (this.stats.combatState === "defending") this.setState("neutral");
    }, 300);
    return true;
  }

  activateDeflect(): boolean {
    if (this.stats.playerKi < KI_COSTS.deflect) return false;
    if (this.stats.combatState !== "neutral") return false;
    if (!this.stats.enemyAttacking) return false; 

    this.stats.playerKi -= KI_COSTS.deflect;
    this.setState("defending");
    this.vfx.showDeflectEffect();

    setTimeout(() => {
      if (this.stats.combatState === "defending") this.setState("neutral");
    }, 500);
    return true;
  }

  triggerPowerClash(): boolean {
    if (this.stats.playerKi < 50) return false;
    if (!this.stats.enemyAttacking || this.stats.enemyAttackType !== "special") return false; // Solo choque ante ataques especiales
    this.stats.playerKi -= 50;
    this.setState("attacking");
    this.stats.currentAttack = "special";
    this.emit();
    // Placeholder para el efecto visual
    this.log("¡CHOQUE DE PODER! (Power Clash)");
    setTimeout(() => this.setState("neutral"), 2000);
    return true;
  }

  meleeAttack(type: "light" | "heavy" | "charged" | "vanish"): boolean {
    const cost = type === "vanish" ? 10 : 0;
    if (this.stats.playerKi < cost) return false;
    
    this.stats.playerKi -= cost;
    // Usar spawnImpact con posición aproximada frente al jugador
    this.vfx.spawnImpact({ x: 0, y: 1.5, z: 1.0 }, "basic");
    this.onAttackImpact(type === "heavy" ? 15 : 8);
    this.emit();
    this.log(`Ataque Melee: ${type.toUpperCase()}`, "#00ff88");
    return true;
  }

  // ============================================
  // ATAQUES DE ENERGIA RÁPIDOS
  // ============================================
  launchKiBlast(handPos: {x: number, y: number, z: number}, cameraForward: {x: number, y: number, z: number}, damageMultiplier: number = 1.0): boolean {
    const cost = 10;
    if (this.stats.playerKi < cost) return false;
    
    this.stats.playerKi -= cost;
    this.setState("attacking");
    this.stats.currentAttack = "ki_blast";
    
    // Proyectar la bola de Ki hacia adelante
    const targetPos = {
       x: handPos.x + cameraForward.x * 20,
       y: handPos.y + cameraForward.y * 20,
       z: handPos.z + cameraForward.z * 20
    };
    
    const baseDamage = 15;
    const isCharged = damageMultiplier > 1.2;

    this.vfx.spawnKiProjectile(handPos, targetPos, isCharged ? "charged" : "basic", () => {
        this.onAttackImpact(baseDamage * damageMultiplier); 
    });

    if (isCharged) {
       // Cálculo de Bullet Time basado en NP
       const attackerNP = this.stats.playerNP;
       const defenderNP = this.stats.enemyNP;
       const diff = attackerNP - defenderNP;
       
       const timeScale = 0.35 + Math.min(0.35, Math.max(-0.2, diff / 50000));
       const duration = 1200 * (1 - Math.min(0.5, Math.max(-0.5, diff / 50000)));
       
       this.activateSlowMotion(duration, timeScale);
    }

    this.emit();

    setTimeout(() => {
      if (this.stats.combatState === "attacking" && this.stats.currentAttack === "ki_blast") {
        this.setState("neutral");
        this.stats.currentAttack = null;
        this.emit();
      }
    }, 200); // Reducido de 400 a 200 para permitir mayor cadencia

    return true;
  }

  // ============================================
  // RECARGA DE KI
  // ============================================
  rechargeKi(): boolean {
    // Si ya estamos recargando, no hacer nada
    if (this.stats.combatState === "recharging") return true; // Ya está en progreso

    // Si estamos cargando un ataque (normal o especial), cancelamos la carga 
    // para priorizar la recuperación de KI solicitada.
    if (this.stats.combatState === "charging" || this.stats.combatState === "charging_special") {
      this.log(`Cancelando carga (${this.stats.combatState}) para RECARGAR`, "#ffcc00");
      this.cancelCharge();
    }

    const alreadyRecharging = this.stats.combatState === "recharging";
    if (this.stats.combatState !== "neutral" && !alreadyRecharging) return false;
    if (this.stats.enemyAttacking) return false;
    
    if (!alreadyRecharging) {
        this.setState("recharging");
        this.log(`Iniciando recarga de KI...`, "#cc44ff");
    }

    return true;
  }

  stopRecharge(): void {
    if (this.stats.combatState === "recharging") {
      this.setState("neutral");
      this.emit();
    }
  }

  // ============================================
  // IMPACTO Y DANO
  // ============================================
  private onAttackImpact(damage: number): void {
    if (this.stats.gameOver) return;
    const isDefending = this.stats.combatState === "defending";
    const damageReduction = CombatUtils.getPowerLevelDamageReduction(this.stats.enemyNP);
    const finalDamage = isDefending ? damage * 0.4 : damage * (1 - damageReduction);

    // El defensor PIERDE NP (Salud/Resistencia), el atacante GANA NP (Dominio)
    this.stats.enemyNP = Math.max(0, this.stats.enemyNP - finalDamage * 2.0); // Más castigo al recibir daño
    this.stats.playerNP = Math.min(100000, this.stats.playerNP + damage * 0.8);
    
    this.log(`¡IMPACTO! -${finalDamage.toFixed(0)} NP AL ENEMIGO`, "#00ff88");
    this.emit();
    this.checkVictoryCondition();
  }

  private checkVictoryCondition(): void {
    if (this.stats.gameOver) return;
    // La victoria se alcanza por BRECHA de NP (35,000 puntos)
    const gap = this.stats.playerNP - this.stats.enemyNP;
    
    if (gap >= 35000) {
      this.triggerGameOver("player");
    } else if (gap <= -35000) {
      this.triggerGameOver("enemy");
    }
  }

  private triggerGameOver(winner: "player" | "enemy"): void {
    if (this.stats.gameOver) return;
    this.stats.gameOver = true;
    this.stats.winner = winner;
    
    if (winner === "player") {
        this.log("¡VICTORIA! HAS DERROTADO AL ENEMIGO", "#00ff00");
    } else {
        this.log("¡DERROTA! EL ENEMIGO TE HA VENCIDO", "#ff4444");
    }

    // Detener IA del enemigo
    if (this.enemyAI) {
      this.enemyAI.stop();
    }
    this.emit();
    this.gameOverCallbacks.forEach((cb) => cb(winner));
  }

  // ============================================
  // CAMARA LENTA
  // ============================================
  private activateSlowMotion(durationMs: number, timeScale: number = 0.3): void {
    this.stats.isSlowMotion = true;
    this.setState("slowMotion");

    // Transición suave de entrada: ir de 1 → timeScale en 300ms
    const startTime = Date.now();
    const rampInMs = 300;
    const rampOutMs = 500; // salida más suave
    let rampInterval: ReturnType<typeof setInterval> | null = setInterval(() => {
      const elapsed = Date.now() - startTime;
      if (elapsed >= rampInMs) {
        (this.scene as any).animationTimeScale = timeScale;
        if (rampInterval) { clearInterval(rampInterval); rampInterval = null; }
        return;
      }
      const t = elapsed / rampInMs;
      (this.scene as any).animationTimeScale = 1 - (1 - timeScale) * t;
    }, 16);

    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.slowMotionTimeout = setTimeout(() => {
      // Transición suave de salida: ir de timeScale → 1 en rampOutMs
      const exitStart = Date.now();
      const exitInterval = setInterval(() => {
        const elapsed = Date.now() - exitStart;
        if (elapsed >= rampOutMs) {
          (this.scene as any).animationTimeScale = 1;
          this.stats.isSlowMotion = false;
          this.setState("neutral");
          clearInterval(exitInterval);
          return;
        }
        const t = elapsed / rampOutMs;
        (this.scene as any).animationTimeScale = timeScale + (1 - timeScale) * t;
      }, 16);
    }, durationMs);
  }

  // ============================================
  // BONUS DE VOZ
  // ============================================
  applyVoiceBonus(attackType: string): void {
    if (this.stats.gameOver) return;
    
    let bonus = 100;
    let message = `Bonus de Voz: +${bonus} NP (${attackType})`;
    let color = "#ffff00";

    // Si es un ataque básico y hay un trigger de voz reciente (ha, ja, pum)
    if (attackType === "basic" || attackType === "ki_blast") {
        if (this.lastVoiceTrigger === "blast_bonus" && (Date.now() - this.lastVoiceTriggerTime < 800)) {
            bonus = 500;
            message = "¡ATAQUE POTENCIADO! (Ha/Ja/Pum) 🔥";
            color = "#ff8800";
        }
    }

    this.stats.playerNP = Math.min(100000, this.stats.playerNP + bonus);
    this.log(message, color);
    this.emit();
  }

  public registerVoiceActivity(command: string | null = null): void {
    // this.lastVoiceActivity = Date.now(); // Pausado
    if (command) {
      // this.lastVoiceTrigger = command;
      // this.lastVoiceTriggerTime = Date.now();
    }
  }

  public registerVoiceTrigger(command: string): void {
    // this.lastVoiceTrigger = command; // Pausado
    // this.lastVoiceTriggerTime = Date.now();
  }

  // ============================================
  // GETTERS PUBLICOS
  // ============================================
  getStats(): GameStats {
    return { ...this.stats };
  }

  isChargingSpecial(attackName: string): boolean {
    return this.activeSpecial === attackName;
  }

  getChargeTime(): number {
    return this.stats.chargeTime;
  }

  isInChargingState(): boolean {
    return (
      this.stats.combatState === "charging" ||
      this.stats.combatState === "charging_special"
    );
  }

  dispose(): void {
    if (this.sceneObserver) {
      this.scene.onBeforeRenderObservable.remove(this.sceneObserver);
      this.sceneObserver = null;
    }
    if (this.enemyAI) {
      this.enemyAI.stop();
    }
  }

  public setAvailablePowers(powers: string[]): void {
    this.availablePowers = powers;
    this.log(`Poderes: ${powers.join(", ")}`, "#aaaaaa");
  }
}
