import { CombatSystem } from "./CombatSystem";
import vegetaConfig from "../../models/vegeta.json";

/**
 * Clase encargada de la lógica de decisión del enemigo.
 */
export class CombatAI {
  private aiTimeout: ReturnType<typeof setTimeout> | null = null;

  constructor(private combatSystem: CombatSystem) {}

  /**
   * Inicia el bucle de decisión de la IA.
   */
  public start(): void {
    this.scheduleNextAction();
  }

  /**
   * Detiene el bucle de decisión de la IA.
   */
  public stop(): void {
    if (this.aiTimeout) {
      clearTimeout(this.aiTimeout);
      this.aiTimeout = null;
    }
  }

  private scheduleNextAction(): void {
    const stats = this.combatSystem.getStats();
    if (stats.gameOver) return;

    // Intervalo aleatorio entre 3 y 6 segundos
    const delay = 3000 + Math.random() * 3000;
    this.aiTimeout = setTimeout(() => {
      this.decideAndExecute();
      this.scheduleNextAction();
    }, delay);
  }

  private decideAndExecute(): void {
    const stats = this.combatSystem.getStats();
    if (stats.gameOver || stats.isSlowMotion) return;

    const roll = Math.random();
    const enemyNP = stats.enemyNP;
    const enemyKi = stats.enemyKi;
    
    // Obtener poderes disponibles para el enemigo (Vegeta por defecto en este caso)
    const vegetaPowers = (vegetaConfig.transformations[0] as any).powers || [];
    const randomSpecial = vegetaPowers.length > 0 
      ? vegetaPowers[Math.floor(Math.random() * vegetaPowers.length)] 
      : "charged";

    // Lógica de decisión simplificada
    // Umbral de 30k NP para ataques especiales (Phase 12)
    if (enemyNP >= 30000 && enemyKi >= 60 && roll < 0.35) {
      this.combatSystem.enemyLaunchSpecial(randomSpecial);
    } else if (enemyKi >= 20 && roll < 0.7) {
      this.combatSystem.enemyLaunchBasic();
    } else {
      // Recarga de KI visible
      this.combatSystem.enemyTriggerRecharge();
    }
  }
}
