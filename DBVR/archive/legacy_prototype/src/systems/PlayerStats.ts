import { PlayerStats as IPlayerStats } from '../types';

export class PlayerStats {
  private stats: IPlayerStats = {
    np: 10000,      // Nivel de Poder base (Canon DB)
    maxNP: 100000,  // Nivel de Poder máximo
    ki: 100,
    maxKi: 100,
    position: { x: 0, y: 0, z: 0 },
  };

  private currentThreshold: number = 0;
  private readonly thresholds: number[] = [25000, 50000, 75000, 100000];

  private kiRegenRate: number = 5; // KI por segundo
  private lastRegenTime: number = Date.now();

  constructor() {
    this.lastRegenTime = Date.now();
  }

  /**
   * Actualizar estadísticas cada frame
   */
  update(): void {
    const now = Date.now();
    const deltaTime = (now - this.lastRegenTime) / 1000;
    this.lastRegenTime = now;

    // Regenerar KI
    this.regenKi(deltaTime);
  }

  /**
   * Añadir Nivel de Poder (NP)
   * Verifica si se alcanza un nuevo umbral irreversible
   */
  addNP(amount: number): void {
    this.stats.np = Math.min(this.stats.np + amount, this.stats.maxNP);
    
    // Verificar si cruzamos un umbral irreversible
    for (const threshold of this.thresholds) {
      if (this.stats.np >= threshold && threshold > this.currentThreshold) {
        this.currentThreshold = threshold;
        console.log(`🔥 ¡Umbral alcanzado! NP bloqueado en: ${this.currentThreshold}`);
      }
    }
  }

  /**
   * "Recibir daño" ahora aumenta el NP (Resistencia/Zenkai)
   * Según DESIGN.md: el daño recibido aumenta el poder del luchador
   */
  takeDamage(amount: number): void {
    const npGain = amount * 1.2; // Factor de ganancia por resistencia
    this.addNP(npGain);
    console.log(`🛡️ Resistencia: NP aumenta en ${npGain.toFixed(0)} debido al impacto.`);
  }

  /**
   * Consumir KI para una acción
   */
  consumeKi(amount: number): boolean {
    if (this.stats.ki >= amount) {
      this.stats.ki -= amount;
      return true;
    }
    return false;
  }

  private regenKi(deltaTime: number): void {
    const regenAmount = this.kiRegenRate * deltaTime;
    this.stats.ki = Math.min(this.stats.ki + regenAmount, this.stats.maxKi);
  }

  setPosition(x: number, y: number, z: number): void {
    this.stats.position = { x, y, z };
  }

  /**
   * Getters
   */
  getStats(): IPlayerStats {
    return { ...this.stats };
  }

  getNP(): number {
    return this.stats.np;
  }

  getMaxNP(): number {
    return this.stats.maxNP;
  }

  getNPPercentage(): number {
    return (this.stats.np / this.stats.maxNP) * 100;
  }

  getKi(): number {
    return this.stats.ki;
  }

  getMaxKi(): number {
    return this.stats.maxKi;
  }

  getKiPercentage(): number {
    return (this.stats.ki / this.stats.maxKi) * 100;
  }

  getCurrentThreshold(): number {
    return this.currentThreshold;
  }
}
