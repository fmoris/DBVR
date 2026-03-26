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

// Costos de KI
const KI_COSTS = {
  basicAttack: 8,
  chargedAttack: { base: 20, perSecond: 5 },
  kamehameha: { base: 40, perSecond: 5, minTime: 2 },
  finalFlash: { base: 60, perSecond: 8, minTime: 3 },
  block: 15,
  dodge: 5,
  deflect: 10,
};

// Danos base
const DAMAGE = {
  basicAttack: 10,
  chargedAttack: { base: 20, perSecond: 10 },
  kamehameha: { base: 40, perSecond: 10 },
  finalFlash: { base: 60, perSecond: 15 },
};

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
    const cost = type === "kamehameha" ? KI_COSTS.kamehameha : KI_COSTS.finalFlash;
    if (this.stats.playerKi < cost.base) return;

    this.activeSpecial = type;
    this.specialChargeStart = Date.now();
    this.stats.chargeTime = 0;
    this.stats.specialType = type;
    this.setState("charging_special");
    this.vfx.showChargeEffect(true, type);

    this.stopChargeInterval();
    this.chargeInterval = setInterval(() => {
      const elapsed = (Date.now() - this.specialChargeStart) / 1000;
      this.stats.chargeTime = elapsed;

      // Consumir KI progresivamente durante la carga
      const kiDrain = cost.perSecond * 0.1; // por cada 100ms
      this.stats.playerKi = Math.max(0, this.stats.playerKi - kiDrain);

      this.emit();

      // Auto-cancelar si se queda sin KI
      if (this.stats.playerKi <= 0) {
        this.cancelCharge();
      }
    }, 100);
  }

  private launchSpecial(type: SpecialAttackType): void {
    if (this.activeSpecial !== type) return;
    this.stopChargeInterval();

    const cost = type === "kamehameha" ? KI_COSTS.kamehameha : KI_COSTS.finalFlash;
    const dmgTable = type === "kamehameha" ? DAMAGE.kamehameha : DAMAGE.finalFlash;
    const elapsed = (Date.now() - this.specialChargeStart) / 1000;

    // Carga minima requerida
    if (elapsed < cost.minTime) {
      // Aun no cumple el minimo — continuar cargando, no lanzar
      return;
    }

    const chargeTime = Math.min(elapsed, 10);
    const damage = dmgTable.base + Math.max(0, chargeTime - cost.minTime) * dmgTable.perSecond;

    // El KI ya se fue consumiendo durante la carga — solo verificar que queda algo
    if (this.stats.playerKi < 5) {
      this.cancelCharge();
      return;
    }

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
        chargeTime,
        () => {
          this.onAttackImpact(damage);
          this.activateSlowMotion(1500, 0.25);
        }
      );
    } else {
      this.vfx.spawnFinalFlash(
        { x: 0, y: 1.5, z: 0.3 },
        { x: 0, y: 1.7, z: 20 },
        chargeTime,
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
