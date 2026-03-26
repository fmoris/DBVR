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

export type PowerLevel = 1 | 2 | 3 | 4 | 5;

export interface GameStats {
  playerKi: number;
  maxKi: number;
  playerNP: number; // Power Level (0-100)
  enemyNP: number;
  enemyKi: number;
  enemyMaxKi: number;
  combatState: CombatState;
  isSlowMotion: boolean;
  currentAttack: AttackType | null;
  chargeTime: number;
}

type StatsListener = (stats: GameStats) => void;

// Costos de KI
const KI_COSTS = {
  basicAttack: 8,
  chargedAttack: { base: 20, perSecond: 5 },
  kamehameha: { base: 40, perSecond: 5 },
  finalFlash: { base: 60, perSecond: 8 },
  block: 15,
  dodge: 5,
  deflect: 10,
  charge: 0,
};

// Daños base
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
  };

  private listeners: StatsListener[] = [];
  private regenInterval: ReturnType<typeof setInterval> | null = null;
  private slowMotionTimeout: ReturnType<typeof setTimeout> | null = null;
  private chargeInterval: ReturnType<typeof setInterval> | null = null;
  private isChargingSpecial = false;
  private specialChargeStart = 0;

  // Para ataques especiales
  private kamehamehaCurrentStep = 0;
  private kamehamehaStepTime = 0;
  private finalFlashCurrentStep = 0;
  private finalFlashStepTime = 0;

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

  private startKiRegen(): void {
    this.regenInterval = setInterval(() => {
      if (this.stats.combatState === "neutral") {
        this.stats.playerKi = Math.min(
          this.stats.maxKi,
          this.stats.playerKi + 2
        );
        this.emit();
      }
    }, 500);
  }

  private startNPFluctuation(): void {
    // Fluctuación natural del NP
    setInterval(() => {
      const fluctuation = this.stats.combatState === "attacking" || 
                         this.stats.combatState === "defending" ? 8 : 3;
      const change = (Math.random() - 0.5) * fluctuation;
      
      this.stats.playerNP = Math.max(0, Math.min(100, this.stats.playerNP + change));
      this.stats.enemyNP = Math.max(0, Math.min(100, this.stats.enemyNP + change));
      this.emit();
    }, 1000);
  }

  // ============================================
  // ATAQUE BÁSICO DE KI (Proyectil rápido)
  // ============================================
  launchBasicAttack(): void {
    if (this.stats.playerKi < KI_COSTS.basicAttack) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.basicAttack;
    this.setState("attacking");
    this.stats.currentAttack = "basic";

    // VFX: proyectil pequeño y rápido
    this.vfx.spawnKiProjectile(
      { x: -0.2, y: 1.4, z: 0.5 },
      { x: 0, y: 1.7, z: 18 },
      "basic",
      () => {
        this.onAttackImpact(DAMAGE.basicAttack);
      }
    );

    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
      }
    }, 600);
  }

  // ============================================
  // ATAQUE DE KI CARGADO
  // ============================================
  startChargedAttack(): void {
    if (this.stats.playerKi < KI_COSTS.chargedAttack.base) return;
    if (this.stats.combatState !== "neutral" && this.stats.combatState !== "charging") return;

    if (this.stats.combatState !== "charging") {
      this.setState("charging");
      this.isChargingSpecial = false;
      this.stats.chargeTime = 0;

      // VFX de carga en el puño
      this.vfx.showChargeEffect(true);

      this.chargeInterval = setInterval(() => {
        this.stats.chargeTime += 0.1;
        
        //KI adicional por tiempo de carga
        if (this.stats.chargeTime > 1) {
          const extraCost = Math.floor(this.stats.chargeTime - 1) * KI_COSTS.chargedAttack.perSecond;
          // Consumir KI extra gradualmente
        }
        
        this.emit();
      }, 100);
    }
  }

  releaseChargedAttack(): void {
    if (this.stats.combatState !== "charging" || this.isChargingSpecial) return;
    if (this.chargeInterval) clearInterval(this.chargeInterval);

    const chargeTime = Math.max(1, Math.min(3, this.stats.chargeTime));
    const damage = DAMAGE.chargedAttack.base + (chargeTime - 1) * DAMAGE.chargedAttack.perSecond;
    const kiCost = KI_COSTS.chargedAttack.base + Math.floor(chargeTime) * KI_COSTS.chargedAttack.perSecond;

    if (this.stats.playerKi < kiCost) {
      this.setState("neutral");
      this.stats.chargeTime = 0;
      this.vfx.showChargeEffect(false);
      return;
    }

    this.stats.playerKi -= kiCost;
    this.setState("attacking");
    this.stats.currentAttack = "charged";

    // VFX: esfera cargada con electricidad
    this.vfx.spawnKiProjectile(
      { x: 0, y: 1.5, z: 0.5 },
      { x: 0, y: 1.7, z: 18 },
      "charged",
      () => {
        this.onAttackImpact(damage);
        // Bullet time corto
        this.activateSlowMotion(800, 0.4);
      }
    );

    this.vfx.showChargeEffect(false);
    this.stats.chargeTime = 0;

    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
      }
    }, 800);
  }

  // ============================================
  // KAMEHAMEHA
  // ============================================
  kamehamehaStep(step: number): void {
    const now = Date.now();
    
    if (step === 1) {
      // Paso 1: ambas manos juntas al costado
      this.kamehamehaCurrentStep = 1;
      this.kamehamehaStepTime = now;
      this.setState("charging");
      this.isChargingSpecial = true;
      this.stats.chargeTime = 0;
      
      // VFX de聚气
      this.vfx.showChargeEffect(true, "kamehameha");
    } 
    else if (step === 2 && this.kamehamehaCurrentStep === 1) {
      // Mantener posición mínimo 2 segundos
      const elapsed = (now - this.kamehamehaStepTime) / 1000;
      if (elapsed >= 2) {
        this.kamehamehaCurrentStep = 2;
        this.kamehamehaStepTime = now;
        
        this.chargeInterval = setInterval(() => {
          this.stats.chargeTime += 0.1;
          this.emit();
        }, 100);
      }
    }
    else if (step === 3 && this.kamehamehaCurrentStep === 2) {
      // Paso 3: empujar ambas manos hacia adelante
      if (this.chargeInterval) clearInterval(this.chargeInterval);
      
      const chargeTime = Math.max(2, Math.min(8, (now - this.kamehamehaStepTime) / 1000));
      const damage = DAMAGE.kamehameha.base + (chargeTime - 2) * DAMAGE.kamehameha.perSecond;
      const kiCost = KI_COSTS.kamehameha.base + Math.floor(chargeTime - 2) * KI_COSTS.kamehameha.perSecond;

      if (this.stats.playerKi < kiCost) {
        this.resetSpecialAttack();
        return;
      }

      this.stats.playerKi -= kiCost;
      this.setState("attacking");
      this.stats.currentAttack = "kamehameha";

      // VFX: rayo de energía azul
      this.vfx.spawnKamehameha(
        { x: 0, y: 1.4, z: 0.3 },
        { x: 0, y: 1.7, z: 20 },
        chargeTime,
        () => {
          this.onAttackImpact(damage);
          this.activateSlowMotion(1500, 0.25);
        }
      );

      this.vfx.showChargeEffect(false);
      this.resetSpecialAttack();
    }
  }

  // ============================================
  // FINAL FLASH
  // ============================================
  finalFlashStep(step: number): void {
    const now = Date.now();
    
    if (step === 1) {
      // Paso 1: brazos en cruz
      this.finalFlashCurrentStep = 1;
      this.finalFlashStepTime = now;
      this.setState("charging");
      this.isChargingSpecial = true;
      this.stats.chargeTime = 0;
      
      this.vfx.showChargeEffect(true, "finalFlash");
    } 
    else if (step === 2 && this.finalFlashCurrentStep === 1) {
      this.finalFlashCurrentStep = 2;
      this.finalFlashStepTime = now;
    }
    else if (step === 3 && this.finalFlashCurrentStep === 2) {
      // Mantener mínimo 3 segundos
      const elapsed = (now - this.finalFlashStepTime) / 1000;
      if (elapsed >= 3) {
        this.finalFlashCurrentStep = 3;
        this.finalFlashStepTime = now;
        
        this.chargeInterval = setInterval(() => {
          this.stats.chargeTime += 0.1;
          this.emit();
        }, 100);
      }
    }
    else if (step === 4 && this.finalFlashCurrentStep === 3) {
      // Lanzamiento en V
      if (this.chargeInterval) clearInterval(this.chargeInterval);
      
      const chargeTime = Math.max(3, Math.min(10, (now - this.finalFlashStepTime) / 1000));
      const damage = DAMAGE.finalFlash.base + (chargeTime - 3) * DAMAGE.finalFlash.perSecond;
      const kiCost = KI_COSTS.finalFlash.base + Math.floor(chargeTime - 3) * KI_COSTS.finalFlash.perSecond;

      if (this.stats.playerKi < kiCost) {
        this.resetSpecialAttack();
        return;
      }

      this.stats.playerKi -= kiCost;
      this.setState("attacking");
      this.stats.currentAttack = "finalFlash";

      // VFX: explosión dorada
      this.vfx.spawnFinalFlash(
        { x: 0, y: 1.5, z: 0.3 },
        { x: 0, y: 1.7, z: 20 },
        chargeTime,
        () => {
          this.onAttackImpact(damage);
          this.activateSlowMotion(2000, 0.2);
        }
      );

      this.vfx.showChargeEffect(false);
      this.resetSpecialAttack();
    }
  }

  private resetSpecialAttack(): void {
    this.kamehamehaCurrentStep = 0;
    this.finalFlashCurrentStep = 0;
    this.isChargingSpecial = false;
    this.stats.chargeTime = 0;
    
    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
        this.stats.currentAttack = null;
      }
    }, 1000);
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
      if (this.stats.combatState === "defending") {
        this.setState("neutral");
      }
    }, 1500);
  }

  activateDodge(): void {
    if (this.stats.playerKi < KI_COSTS.dodge) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.dodge;
    this.setState("defending");
    
    // VFX de esquive
    this.vfx.showDodgeEffect();

    setTimeout(() => {
      if (this.stats.combatState === "defending") {
        this.setState("neutral");
      }
    }, 300);
  }

  activateDeflect(): void {
    if (this.stats.playerKi < KI_COSTS.deflect) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= KI_COSTS.deflect;
    this.setState("defending");
    this.vfx.showDeflectEffect();

    setTimeout(() => {
      if (this.stats.combatState === "defending") {
        this.setState("neutral");
      }
    }, 500);
  }

  // ============================================
  // RECARGA DE KI
  // ============================================
  rechargeKi(): void {
    if (this.stats.combatState !== "neutral") return;
    this.setState("charging");

    const chargeInterval = setInterval(() => {
      this.stats.playerKi = Math.min(
        this.stats.maxKi,
        this.stats.playerKi + 5
      );
      this.emit();
      if (this.stats.playerKi >= this.stats.maxKi) {
        clearInterval(chargeInterval);
        this.setState("neutral");
      }
    }, 200);

    setTimeout(() => {
      clearInterval(chargeInterval);
      if (this.stats.combatState === "charging") {
        this.setState("neutral");
      }
    }, 3000);
  }

  // ============================================
  // SISTEMA DE IMPACTO Y DAÑO
  // ============================================
  private onAttackImpact(damage: number): void {
    const isDefending = this.stats.combatState === "defending";
    
    // Calcular reducción según nivel de poder
    const damageReduction = this.getPowerLevelDamageReduction(this.stats.enemyNP);
    const finalDamage = isDefending ? damage * 0.4 : damage * (1 - damageReduction);
    
    // Reducir NP del enemigo
    this.stats.enemyNP = Math.max(0, this.stats.enemyNP - finalDamage * 0.5);
    
    // Ganar NP por ataque exitoso
    this.stats.playerNP = Math.min(100, this.stats.playerNP + damage * 0.2);
    
    this.emit();
    
    // Verificar condición de victoria
    this.checkVictoryCondition();
  }

  private getPowerLevelDamageReduction(np: number): number {
    if (np >= 91) return 0.9;  // Trascendente: inmune a casi todo
    if (np >= 76) return 0.7;  // Dominante
    if (np >= 51) return 0.4;  // Elevado
    if (np >= 21) return 0.2;  // Normal
    return 0;                   // Debilitado
  }

  private checkVictoryCondition(): void {
    const npDiff = Math.abs(this.stats.playerNP - this.stats.enemyNP);
    
    if (npDiff > 50) {
      if (this.stats.playerNP > this.stats.enemyNP) {
        console.log("🎉 ¡Victoria! El enemigo no puede continuar...");
      } else {
        console.log("💀 Derrota... Tu poder era insuficiente.");
      }
    }
  }

  // ============================================
  // CÁMARA LENTA
  // ============================================
  private activateSlowMotion(durationMs: number, timeScale: number = 0.3): void {
    this.stats.isSlowMotion = true;
    this.setState("slowMotion");
    
    // Aplicar timeScale al scene
    (this.scene as any).animationTimeScale = timeScale;

    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.slowMotionTimeout = setTimeout(() => {
      this.stats.isSlowMotion = false;
      (this.scene as any).animationTimeScale = 1;
      this.setState("neutral");
    }, durationMs);
  }

  // ============================================
  // Getters públicos
  // ============================================
  getStats(): GameStats {
    return { ...this.stats };
  }

  getKamehamehaStep(): number {
    return this.kamehamehaCurrentStep;
  }

  getFinalFlashStep(): number {
    return this.finalFlashCurrentStep;
  }

  getChargeTime(): number {
    return this.stats.chargeTime;
  }

  isInChargingState(): boolean {
    return this.stats.combatState === "charging";
  }

  dispose(): void {
    if (this.regenInterval) clearInterval(this.regenInterval);
    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    if (this.chargeInterval) clearInterval(this.chargeInterval);
  }
}