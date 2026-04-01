/**
 * PlayerStats
 * Gestiona la salud y KI del jugador
 */

import { PlayerStats as IPlayerStats } from '../types';

export class PlayerStats {
  private stats: IPlayerStats = {
    health: 100,
    maxHealth: 100,
    ki: 100,
    maxKi: 100,
    position: { x: 0, y: 0, z: 0 },
  };

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
    const deltaTime = (now - this.lastRegenTime) / 1000; // Convertir a segundos
    this.lastRegenTime = now;

    // Regenerar KI
    this.regenKi(deltaTime);
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

  /**
   * Regenerar KI
   */
  private regenKi(deltaTime: number): void {
    const regenAmount = this.kiRegenRate * deltaTime;
    this.stats.ki = Math.min(this.stats.ki + regenAmount, this.stats.maxKi);
  }

  /**
   * Recibir daño
   */
  takeDamage(amount: number): void {
    this.stats.health = Math.max(0, this.stats.health - amount);
    console.log(`💔 Daño recibido: ${amount}. Salud: ${this.stats.health}/${this.stats.maxHealth}`);
  }

  /**
   * Establecer posición
   */
  setPosition(x: number, y: number, z: number): void {
    this.stats.position = { x, y, z };
  }

  /**
   * Getters
   */
  getStats(): IPlayerStats {
    return { ...this.stats };
  }

  getHealth(): number {
    return this.stats.health;
  }

  getMaxHealth(): number {
    return this.stats.maxHealth;
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

  getHealthPercentage(): number {
    return (this.stats.health / this.stats.maxHealth) * 100;
  }

  isAlive(): boolean {
    return this.stats.health > 0;
  }
}
