import { Scene } from "@babylonjs/core";
import { VFXManager, AttackType } from "./VFXManager";

export type CombatState =
  | "neutral"
  | "charging"
  | "charging_special"
  | "attacking"
  | "defending"
  | "slowMotion"
  | "hit"
  | "melee";

export type SpecialAttackType = "kamehameha" | "finalFlash";

export type PowerLevel = 1 | 2 | 3 | 4 | 5;

export interface GameStats {
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

// Niveles de carga para ataques especiales
// Cada nivel define: tiempo minimo para alcanzarlo, KI consumido total y daño base
const SPECIAL_LEVELS = {
  kamehameha: [
    { label: "MINIMO",  timeMin: 2,  timeMax: 4.9, ki: 40,  damage: 40  },
    { label: "MEDIO",   timeMin: 5,  timeMax: 7.9, ki: 60,  damage: 70  },
    { label: "MAXIMO",  timeMin: 8,  timeMax: 99,  ki: 80,  damage: 100 },
  ],
  finalFlash: [
    { label: "MINIMO",  timeMin: 3,  timeMax: 5.9, ki: 60,  damage: 60  },
    { label: "MEDIO",   timeMin: 6,  timeMax: 9.9, ki: 90,  damage: 110 },
    { label: "MAXIMO",  timeMin: 10, timeMax: 99,  ki: 120, damage: 150 },
  ],
} as const;

// Factor de daño segun NP del atacante (mas NP = mas daño)
function npDamageFactor(np: number): number {
  if (np >= 91) return 1.8;
  if (np >= 76) return 1.5;
  if (np >= 51) return 1.2;
  if (np >= 21) return 1.0;
  return 0.7;
}

// Obtener el nivel de carga actual segun el tiempo transcurrido
function getChargeLevel(
  type: "kamehameha" | "finalFlash",
  elapsed: number
): (typeof SPECIAL_LEVELS)["kamehameha"][number] | null {
  const levels = SPECIAL_LEVELS[type];
  // Buscar el nivel mas alto alcanzado
  let reached: (typeof SPECIAL_LEVELS)["kamehameha"][number] | null = null;
  for (const level of levels) {
    if (elapsed >= level.timeMin) reached = level;
  }
  return reached;
}

export class CombatSystem {
  private stats: GameStats = {
    playerKi: 100,
    maxKi: 100,
    playerNP: 50,
    enemyNP: 50,
    enemyKi: 100,
    enemyMaxKi: 100,
    combatState: "neutral",
    isSlowMotion: false,
    currentAttack: null,
    chargeTime: 0,
    specialType: null,
  };

  private listeners: StatsListener[] = [];
  private regenInterval: ReturnType<typeof setInterval> | null = null;
  private slowMotionTimeout: ReturnType<typeof setTimeout> | null = null;
  private chargeInterval: ReturnType<typeof setInterval> | null = null;

  // Estado de carga especial
  private activeSpecial: SpecialAttackType | null = null;
  private specialChargeStart = 0;

  // Estado de carga normal
  private isChargingNormal = false;

  constructor(private scene: Scene, private vfx: VFXManager) {
    this.startKiRegen();
    this.startNPFluctuation();
  }

  onStatsChange(listener: StatsListener): void {
    this.listeners.push(listener);
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

  private startNPFluctuation(): void {
    setInterval(() => {
      const fluctuation =
        this.stats.combatState === "attacking" || this.stats.combatState === "defending"
          ? 8
          : 3;
      const change = (Math.random() - 0.5) * fluctuation;
      this.stats.playerNP = Math.max(0, Math.min(100, this.stats.playerNP + change));
      this.stats.enemyNP = Math.max(0, Math.min(100, this.stats.enemyNP + change));
      this.emit();
    }, 1000);
  }

  // ============================================
  // ATAQUE BASICO DE KI
  // ============================================
  launchBasicAttack(): void {
    if (this.stats.playerKi < KI_COSTS.basicAttack) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.basicAttack;
    this.setState("attacking");
    this.stats.currentAttack = "basic";
    this.emit();

    this.vfx.spawnKiProjectile(
      { x: -0.2, y: 1.4, z: 0.5 },
      { x: 0, y: 1.7, z: 18 },
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
  }

  // ============================================
  // ATAQUE DE KI CARGADO
  // ============================================
  startChargedAttack(): void {
    if (this.stats.playerKi < KI_COSTS.chargedAttack.base) return;
    if (this.stats.combatState !== "neutral") return;

    this.isChargingNormal = true;
    this.stats.chargeTime = 0;
    this.setState("charging");
    this.vfx.showChargeEffect(true);

    this.stopChargeInterval();
    this.chargeInterval = setInterval(() => {
      this.stats.chargeTime += 0.1;
      // Consumir KI extra gradualmente despues del primer segundo
      if (this.stats.chargeTime > 1) {
        this.stats.playerKi = Math.max(0, this.stats.playerKi - KI_COSTS.chargedAttack.perSecond * 0.1);
      }
      this.emit();
      // Auto-cancelar si se queda sin KI
      if (this.stats.playerKi <= 0) {
        this.cancelCharge();
      }
    }, 100);
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
      { x: 0, y: 1.5, z: 0.5 },
      { x: 0, y: 1.7, z: 18 },
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

  /**
   * Llama a este metodo con el mismo tipo para iniciar Y para lanzar.
   * Primera llamada: empieza la carga.
   * Segunda llamada (con carga minima cumplida): lanza el ataque.
   */
  kamehamehaStep(step: number): void {
    // step se ignora — usamos estado interno para saber si iniciar o lanzar
    if (this.activeSpecial === "kamehameha") {
      // Ya estaba cargando — intentar lanzar
      this.launchSpecial("kamehameha");
    } else if (this.stats.combatState === "neutral") {
      // Iniciar carga
      this.beginSpecialCharge("kamehameha");
    }
  }

  finalFlashStep(step: number): void {
    if (this.activeSpecial === "finalFlash") {
      this.launchSpecial("finalFlash");
    } else if (this.stats.combatState === "neutral") {
      this.beginSpecialCharge("finalFlash");
    }
  }

  private beginSpecialCharge(type: SpecialAttackType): void {
    // Verificar KI minimo para el primer nivel
    const firstLevel = SPECIAL_LEVELS[type][0];
    if (this.stats.playerKi < firstLevel.ki) return;

    this.activeSpecial = type;
    this.specialChargeStart = Date.now();
    this.stats.chargeTime = 0;
    this.stats.specialType = type;
    this.setState("charging_special");
    this.vfx.showChargeEffect(true, type);

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
      if (this.stats.playerKi <= 0 && elapsed < minLevel.timeMin) {
        this.cancelCharge();
        return;
      }

      // Auto-lanzar al llegar al tiempo maximo
      if (elapsed >= maxLevel.timeMin) {
        this.launchSpecial(type);
        return;
      }

      this.emit();
    }, 100);
  }

  private launchSpecial(type: SpecialAttackType): void {
    if (this.activeSpecial !== type) return;
    this.stopChargeInterval();

    const elapsed = (Date.now() - this.specialChargeStart) / 1000;

    // Determinar nivel de carga alcanzado
    const level = getChargeLevel(type, elapsed);
    if (!level) {
      // No alcanzo ni el nivel minimo — cancelar sin lanzar
      this.cancelCharge();
      return;
    }

    // Calcular daño final con factor de NP
    const damage = level.damage * npDamageFactor(this.stats.playerNP);

    // El KI ya se consumio durante la carga — no se descuenta extra al lanzar

    this.activeSpecial = null;
    this.stats.chargeTime = 0;
    this.stats.specialType = null;
    this.setState("attacking");
    this.stats.currentAttack = type;
    this.vfx.showChargeEffect(false);
    this.emit();

    if (type === "kamehameha") {
      this.vfx.spawnKamehameha(
        { x: 0, y: 1.4, z: 0.3 },
        { x: 0, y: 1.7, z: 20 },
        elapsed,
        () => {
          this.onAttackImpact(damage);
          this.activateSlowMotion(1500, 0.25);
        }
      );
    } else {
      this.vfx.spawnFinalFlash(
        { x: 0, y: 1.5, z: 0.3 },
        { x: 0, y: 1.7, z: 20 },
        elapsed,
        () => {
          this.onAttackImpact(damage);
          this.activateSlowMotion(2000, 0.2);
        }
      );
    }

    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
        this.emit();
      }
    }, type === "kamehameha" ? 1200 : 1500);
  }

  // ============================================
  // DEFENSAS
  // ============================================
  activateBlock(): void {
    if (this.stats.playerKi < KI_COSTS.block) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.block;
    this.setState("defending");
    this.vfx.showBlockShield(true);

    setTimeout(() => {
      this.vfx.showBlockShield(false);
      if (this.stats.combatState === "defending") this.setState("neutral");
    }, 1500);
  }

  activateDodge(): void {
    if (this.stats.playerKi < KI_COSTS.dodge) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.dodge;
    this.setState("defending");
    this.vfx.showDodgeEffect();

    setTimeout(() => {
      if (this.stats.combatState === "defending") this.setState("neutral");
    }, 300);
  }

  activateDeflect(): void {
    if (this.stats.playerKi < KI_COSTS.deflect) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.deflect;
    this.setState("defending");
    this.vfx.showDeflectEffect();

    setTimeout(() => {
      if (this.stats.combatState === "defending") this.setState("neutral");
    }, 500);
  }

  // ============================================
  // RECARGA DE KI
  // ============================================
  rechargeKi(): void {
    if (this.stats.combatState !== "neutral") return;
    this.setState("charging");

    const chargeInterval = setInterval(() => {
      this.stats.playerKi = Math.min(this.stats.maxKi, this.stats.playerKi + 5);
      this.emit();
      if (this.stats.playerKi >= this.stats.maxKi) {
        clearInterval(chargeInterval);
        this.setState("neutral");
      }
    }, 200);

    setTimeout(() => {
      clearInterval(chargeInterval);
      if (this.stats.combatState === "charging") this.setState("neutral");
    }, 3000);
  }

  // ============================================
  // IMPACTO Y DANO
  // ============================================
  private onAttackImpact(damage: number): void {
    const isDefending = this.stats.combatState === "defending";
    const damageReduction = this.getPowerLevelDamageReduction(this.stats.enemyNP);
    const finalDamage = isDefending ? damage * 0.4 : damage * (1 - damageReduction);

    this.stats.enemyNP = Math.max(0, this.stats.enemyNP - finalDamage * 0.5);
    this.stats.playerNP = Math.min(100, this.stats.playerNP + damage * 0.2);
    this.emit();
    this.checkVictoryCondition();
  }

  private getPowerLevelDamageReduction(np: number): number {
    if (np >= 91) return 0.9;
    if (np >= 76) return 0.7;
    if (np >= 51) return 0.4;
    if (np >= 21) return 0.2;
    return 0;
  }

  private checkVictoryCondition(): void {
    const npDiff = Math.abs(this.stats.playerNP - this.stats.enemyNP);
    if (npDiff > 50) {
      if (this.stats.playerNP > this.stats.enemyNP) {
        console.log("Victoria! El enemigo no puede continuar...");
      } else {
        console.log("Derrota... Tu poder era insuficiente.");
      }
    }
  }

  // ============================================
  // CAMARA LENTA
  // ============================================
  private activateSlowMotion(durationMs: number, timeScale: number = 0.3): void {
    this.stats.isSlowMotion = true;
    this.setState("slowMotion");
    (this.scene as any).animationTimeScale = timeScale;

    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.slowMotionTimeout = setTimeout(() => {
      this.stats.isSlowMotion = false;
      (this.scene as any).animationTimeScale = 1;
      this.setState("neutral");
    }, durationMs);
  }

  // ============================================
  // GETTERS PUBLICOS
  // ============================================
  getStats(): GameStats {
    return { ...this.stats };
  }

  getKamehamehaStep(): number {
    return this.activeSpecial === "kamehameha" ? 1 : 0;
  }

  getFinalFlashStep(): number {
    return this.activeSpecial === "finalFlash" ? 1 : 0;
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
    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.stopChargeInterval();
  }
}
