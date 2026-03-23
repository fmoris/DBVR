import { Scene } from "@babylonjs/core";
import { VFXManager } from "./VFXManager";

export type CombatState = "neutral" | "charging" | "attacking" | "defending" | "slowMotion" | "hit";

export interface GameStats {
  playerKi: number;
  playerHealth: number;
  enemyKi: number;
  enemyHealth: number;
  combatState: CombatState;
  isSlowMotion: boolean;
}

type StatsListener = (stats: GameStats) => void;

export class CombatSystem {
  private stats: GameStats = {
    playerKi: 100,
    playerHealth: 100,
    enemyKi: 100,
    enemyHealth: 100,
    combatState: "neutral",
    isSlowMotion: false,
  };

  private listeners: StatsListener[] = [];
  private regenInterval: ReturnType<typeof setInterval> | null = null;
  private slowMotionTimeout: ReturnType<typeof setTimeout> | null = null;

  constructor(private scene: Scene, private vfx: VFXManager) {
    this.startKiRegen();
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
        this.stats.playerKi = Math.min(100, this.stats.playerKi + 1.5);
        this.emit();
      }
    }, 500);
  }

  launchAttack(): void {
    if (this.stats.playerKi < 20) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= 20;
    this.setState("attacking");

    // Lanzar proyectil
    this.vfx.spawnProjectile(
      { x: 0, y: 1.5, z: 1 },
      { x: 0, y: 1.7, z: 18 },
      () => {
        // Impacto: relentizar el tiempo
        this.activateSlowMotion(2000);
        this.stats.enemyHealth = Math.max(0, this.stats.enemyHealth - 15);
        this.emit();
      }
    );

    setTimeout(() => {
      if (this.stats.combatState === "attacking") {
        this.setState("neutral");
      }
    }, 800);
  }

  activateBlock(): void {
    if (this.stats.playerKi < 10) return;
    if (this.stats.combatState !== "neutral") return;

    this.stats.playerKi -= 10;
    this.setState("defending");

    setTimeout(() => {
      if (this.stats.combatState === "defending") {
        this.setState("neutral");
      }
    }, 1500);
  }

  rechargeKi(): void {
    if (this.stats.combatState !== "neutral") return;
    this.setState("charging");

    const chargeInterval = setInterval(() => {
      this.stats.playerKi = Math.min(100, this.stats.playerKi + 8);
      this.emit();
      if (this.stats.playerKi >= 100) {
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

  private activateSlowMotion(durationMs: number): void {
    this.stats.isSlowMotion = true;
    this.setState("slowMotion");

    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
    this.slowMotionTimeout = setTimeout(() => {
      this.stats.isSlowMotion = false;
      this.setState("neutral");
    }, durationMs);
  }

  getStats(): GameStats {
    return { ...this.stats };
  }

  dispose(): void {
    if (this.regenInterval) clearInterval(this.regenInterval);
    if (this.slowMotionTimeout) clearTimeout(this.slowMotionTimeout);
  }
}
