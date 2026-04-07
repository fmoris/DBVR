import { Scene } from "@babylonjs/core";
import { VFXManager, AttackType } from "./VFXManager";
import powersConfig from "../models/powers.json";
import gokuConfig from "../models/goku.json";
import vegetaConfig from "../models/vegeta.json";

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

export interface ChargeLevel {
  label: string;
  timeMin: number;
  timeMax: number;
  ki: number;
  damage: number;
}

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

// Factor de daño segun NP del atacante (mas NP = mas daño)
function npDamageFactor(np: number): number {
  // Escala real: 10,000 NP -> x2 daño. 100,000 NP -> x11 daño.
  return 1.0 + (np / 10000);
}

function getChargeLevel(
  type: string,
  elapsed: number
): ChargeLevel | null {
  const levels = SPECIAL_LEVELS[type.toLowerCase()];
  if (!levels) return null;
  // Buscar el nivel mas alto alcanzado
  let reached: ChargeLevel | null = null;
  for (const level of levels) {
    if (elapsed >= level.timeMin) reached = level;
  }
  return reached;
}

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
  private regenInterval: ReturnType<typeof setInterval> | null = null;
  private slowMotionTimeout: ReturnType<typeof setTimeout> | null = null;
  private chargeInterval: ReturnType<typeof setInterval> | null = null;
  private enemyAIInterval: ReturnType<typeof setTimeout> | null = null;
  private enemyRegenInterval: ReturnType<typeof setInterval> | null = null;
  private gameOverCallbacks: Array<(winner: "player" | "enemy") => void> = [];
  private messageListeners: Array<(msg: string, color?: string) => void> = [];
  
  private rechargeIntervalRef: ReturnType<typeof setInterval> | null = null;
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
  private activeSpecialOrigin: { x: number; y: number; z: number } | null = null;

  private playerHeight: number = 1.75;
  private enemyHeight: number = 1.64;

  public playerName = "Player";
  public enemyName = "Enemy";

  constructor(private scene: Scene, private vfx: VFXManager, playerConfig?: any, enemyConfig?: any) {
    this.playerHeight = playerConfig?.height_m || gokuConfig.height_m || 1.75;
    this.enemyHeight = enemyConfig?.height_m || (vegetaConfig as any).height_m || 1.64;
    
    this.setAvailablePowers(playerConfig?.transformations?.[0]?.powers || gokuConfig.transformations?.[0]?.powers || []);
    this.stats.playerKi = 30; // Inicio al 30%
    this.stats.enemyKi = 30;
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

    this.startKiRegen();
    // La IA se inicia solo si está habilitada (el usuario pidió desactivarla)
    const aiEnabled = false; 
    if (aiEnabled) {
      this.startEnemyAI();
    }
    this.startEnemyKiRegen();
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

  private stopChargeInterval(): void {
    if (this.chargeInterval) {
      clearInterval(this.chargeInterval);
      this.chargeInterval = null;
    }
  }

  private startKiRegen(): void {
    this.regenInterval = setInterval(() => {
      if (this.stats.combatState === "neutral") {
        this.stats.playerKi = Math.min(this.stats.maxKi, this.stats.playerKi + 2);
        this.emit();
      }
    }, 500);
  }


  // ============================================
  // IA DEL ENEMIGO
  // ============================================
  private startEnemyKiRegen(): void {
    this.enemyRegenInterval = setInterval(() => {
      if (this.stats.gameOver) return;
      this.stats.enemyKi = Math.min(this.stats.enemyMaxKi, this.stats.enemyKi + 3);
      this.emit();
    }, 400);
  }

  private startEnemyAI(): void {
    const scheduleNextAttack = () => {
      if (this.stats.gameOver) return;
      // Intervalo aleatorio entre 3 y 6 segundos
      const delay = 3000 + Math.random() * 3000;
      this.enemyAIInterval = setTimeout(() => {
        this.enemyDoAttack();
        scheduleNextAttack();
      }, delay);
    };
    // Primera accion despues de 2 segundos
    setTimeout(() => scheduleNextAttack(), 2000);
  }

  private enemyDoAttack(): void {
    if (this.stats.gameOver) return;
    if (this.stats.isSlowMotion) return;

    // Elegir ataque segun KI disponible y nivel de NP del enemigo
    const roll = Math.random();
    const enemyNP = this.stats.enemyNP;
    
    const vegetaPowers = vegetaConfig.transformations[0].powers || [];
    const randomSpecial = vegetaPowers.length > 0 ? vegetaPowers[Math.floor(Math.random() * vegetaPowers.length)] : "charged";

    // Enemigo fuerte usa ataques especiales con mas frecuencia
    if (enemyNP >= 60 && this.stats.enemyKi >= 60 && roll < 0.35) {
      this.enemyLaunchSpecial(randomSpecial);
    } else if (this.stats.enemyKi >= 20 && roll < 0.7) {
      this.enemyLaunchBasic();
    } else {
      // Recarga de KI del enemigo (accion visible pero no es un ataque)
      this.stats.enemyAttacking = false; 
      this.stats.enemyAttackName = "Recargando KI";
      this.stats.enemyAttackType = null;
      this.emit();
      setTimeout(() => {
        this.stats.enemyAttackName = "";
        this.emit();
      }, 800);
    }
  }

  private enemyLaunchBasic(): void {
    const kiCost = 20;
    if (this.stats.enemyKi < kiCost) return;
    this.stats.enemyKi -= kiCost;
    this.stats.enemyAttacking = true;
    this.stats.enemyAttackName = "Ataque KI";
    this.stats.enemyAttackType = "basic";
    this.emit();

    // Calcular dano del enemigo
    const baseDamage = 8 + Math.random() * 12; // 8-20
    const factor = npDamageFactor(this.stats.enemyNP);
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

  private enemyLaunchSpecial(type: string): void {
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
    const factor = npDamageFactor(this.stats.enemyNP);
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

  private onEnemyAttackImpact(damage: number): void {
    if (this.stats.gameOver) return;
    const isDefending = this.stats.combatState === "defending";
    const damageReduction = this.getPowerLevelDamageReduction(this.stats.playerNP);
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

    this.stopChargeInterval();
    this.chargeInterval = setInterval(() => {
      this.stats.chargeTime += 0.1;
      
      // Actualizar VFX progresivo (Phase 16)
      if (this.stats.chargeTime > 0.3) {
        // Obtenemos posición de manos si es posible o usamos una por defecto
        this.vfx.updateChargeEffect(this.stats.chargeTime, "normal", undefined, 2.0);
      }

      // Consumir KI extra gradualmente despues del primer segundo
      if (this.stats.chargeTime > 1) {
        this.stats.playerKi = Math.max(0, this.stats.playerKi - 3); // Costo gradual
      }
      if (this.stats.playerKi <= 0) {
        this.cancelCharge();
      }
    }, 100);
    return true;
  }

  releaseChargedAttack(): void {
    if (this.stats.combatState !== "charging" || !this.isChargingNormal) return;
    this.stopChargeInterval();

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
    this.stopChargeInterval();
    this.isChargingNormal = false;
    this.activeSpecial = null;
    this.stats.chargeTime = 0;
    this.stats.specialType = null;
    this.vfx.showChargeEffect(false);
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

  triggerSpecial(attackName: string, origin?: { x: number, y: number, z: number }): boolean {
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
        this.stopChargeInterval();
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
  public updateSpecialChargeOrigin(origin: { x: number, y: number, z: number }): void {
    if (this.stats.combatState === "charging_special") {
        this.activeSpecialOrigin = origin;
    }
  }

  private beginSpecialCharge(type: string, origin?: { x: number, y: number, z: number }): boolean {
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
    this.activeSpecialOrigin = origin || { x: 0.3, y: this.playerHeight * 0.7, z: 0.5 };
    this.stats.chargeTime = 0;
    this.stats.specialType = type;
    this.setState("charging_special");
    this.vfx.showChargeEffect(true, type, this.activeSpecialOrigin as any);

    // KI se consume de forma gradual: el costo total del nivel maximo repartido en su tiempo
    // Kamehameha max: 80 KI en 8s = 1 KI/100ms
    // Final Flash max: 120 KI en 10s = 1.2 KI/100ms
    const maxLevel = SPECIAL_LEVELS[type][2];
    const maxTime = maxLevel.timeMin; // tiempo para llegar al maximo
    const kiPerTick = (maxLevel.ki / maxTime) * 0.1; // KI por cada 100ms

    this.stopChargeInterval();
    this.chargeInterval = setInterval(() => {
      const elapsed = (Date.now() - this.specialChargeStart) / 1000;
      this.stats.chargeTime = elapsed;

      // Consumir KI progresivamente
      this.stats.playerKi = Math.max(0, this.stats.playerKi - kiPerTick);

      // Auto-cancelar si se queda sin KI antes del nivel minimo
      const minLevel = SPECIAL_LEVELS[type][0];
      if (this.stats.playerKi <= 0) {
        if (elapsed < minLevel.timeMin) {
            this.log("Ki Agotado: Carga Fallida", "#ff4444");
            this.cancelCharge();
        } else {
            // Si ya pasó el mínimo, solo dejamos de cargar (se congela el tiempo)
            // No auto-lanzamos por petición del usuario (Phase 14)
        }
        return;
      }

      // Actualizar efectos de carga dinámicos (Phase 14/16)
      // Pasamos la posición actualizada y el tiempo objetivo
      this.vfx.updateChargeEffect(elapsed, type, this.activeSpecialOrigin as any, minLevel.timeMin);

      this.emit();
    }, 100);
    return true;
  }

  private launchSpecial(type: string, origin?: { x: number, y: number, z: number }): boolean {
    if (this.activeSpecial !== type) return false;
    this.stopChargeInterval();

    const elapsed = (Date.now() - this.specialChargeStart) / 1000;

    // Determinar nivel de carga alcanzado
    const level = getChargeLevel(type, elapsed);
    if (!level) {
      this.cancelCharge();
      return false;
    }

    // Calcular daño final con factor de NP
    const damage = level.damage * npDamageFactor(this.stats.playerNP);

    // Si pasaron un origen en el lanzamiento, lo usamos, sino el que guardamos al cargar
    const finalOrigin = origin || this.activeSpecialOrigin || { x: 0, y: this.playerHeight * 0.7, z: 0.3 };

    this.activeSpecial = null;
    this.activeSpecialOrigin = null;
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

    if (this.stats.combatState !== "neutral") return false;
    if (this.stats.enemyAttacking) return false;
    this.setState("recharging");

    this.log(`Iniciando recarga de KI...`, "#cc44ff");

    this.rechargeIntervalRef = setInterval(() => {
      // Bono de Voz: si hubo actividad de voz reciente, recarga el doble
      const isGritando = (Date.now() - this.lastVoiceActivity) < 1500;
      const kiGain = isGritando ? 12 : 5;
      
      if (isGritando && Math.random() > 0.8) {
        this.log("¡RECARGA POTENCIADA POR GRITO! ⚡⚡", "#ffff00");
      }

      const nextKi = this.stats.playerKi + kiGain;
      this.stats.playerKi = Math.min(this.stats.maxKi, nextKi);
      this.emit();
      
      if (this.stats.playerKi >= this.stats.maxKi) {
         this.stopRecharge();
      }
    }, 200);

    return true;
  }

  stopRecharge(): void {
    if (this.rechargeIntervalRef) {
       clearInterval(this.rechargeIntervalRef);
       this.rechargeIntervalRef = null;
    }
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
    const damageReduction = this.getPowerLevelDamageReduction(this.stats.enemyNP);
    const finalDamage = isDefending ? damage * 0.4 : damage * (1 - damageReduction);

    // El defensor PIERDE NP (Salud/Resistencia), el atacante GANA NP (Dominio)
    this.stats.enemyNP = Math.max(0, this.stats.enemyNP - finalDamage * 2.0); // Más castigo al recibir daño
    this.stats.playerNP = Math.min(100000, this.stats.playerNP + damage * 0.8);
    
    this.log(`¡IMPACTO! -${finalDamage.toFixed(0)} NP AL ENEMIGO`, "#00ff88");
    this.emit();
    this.checkVictoryCondition();
  }

  private getPowerLevelDamageReduction(np: number): number {
    if (np >= 70000) return 0.9;
    if (np >= 30000) return 0.7;
    if (np >= 10000) return 0.4;
    if (np >= 3000) return 0.2;
    return 0;
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
    if (this.enemyAIInterval) {
      clearTimeout(this.enemyAIInterval);
      this.enemyAIInterval = null;
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

  public registerVoiceActivity(): void {
    this.lastVoiceActivity = Date.now();
  }

  public registerVoiceTrigger(id: string): void {
    this.lastVoiceTrigger = id;
    this.lastVoiceTriggerTime = Date.now();
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
    if (this.regenInterval) clearInterval(this.regenInterval);
    if (this.enemyRegenInterval) clearInterval(this.enemyRegenInterval);
    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    if (this.enemyAIInterval) clearTimeout(this.enemyAIInterval);
    this.stopChargeInterval();
  }

  /**
   * Define qué poderes especiales puede ejecutar el jugador.
   */
  public setAvailablePowers(powers: string[]): void {
    this.availablePowers = powers;
    this.log(`Poderes: ${powers.join(", ")}`, "#aaaaaa");
  }
}
