/**
 * CombatStateManager
 * Controla el flujo del combate y las transiciones de estado
 */

import { CombatState } from '../types';

export class CombatStateManager {
  private currentState: CombatState = CombatState.NEUTRAL;
  private previousState: CombatState = CombatState.NEUTRAL;
  private stateStartTime: number = 0;
  private slowMotionTimeScale: number = 1;
  private slowMotionDuration: number = 0;
  private slowMotionElapsed: number = 0;

  constructor(private scene: any) {}

  /**
   * Actualizar el estado del combate cada frame
   */
  update(deltaTime: number): void {
    // Actualizar cámara lenta si está activa
    if (this.currentState === CombatState.SLOW_MOTION) {
      this.slowMotionElapsed += deltaTime;
      
      if (this.slowMotionElapsed >= this.slowMotionDuration) {
        this.transitionTo(CombatState.DEFENDING);
      }
      
      // Aplicar escala de tiempo
      this.scene.animationTimeScale = this.slowMotionTimeScale;
    } else {
      this.scene.animationTimeScale = 1;
    }
  }

  /**
   * Transicionar a un nuevo estado
   */
  transitionTo(newState: CombatState): void {
    if (newState === this.currentState) return;

    this.previousState = this.currentState;
    this.currentState = newState;
    this.stateStartTime = Date.now();

    console.log(`[CombatState] ${this.previousState} → ${this.currentState}`);

    this.onStateChange(newState);
  }

  /**
   * Iniciar cámara lenta cuando se recibe un ataque
   */
  startSlowMotion(duration: number = 1.5, timeScale: number = 0.3): void {
    this.slowMotionTimeScale = timeScale;
    this.slowMotionDuration = duration;
    this.slowMotionElapsed = 0;
    this.transitionTo(CombatState.SLOW_MOTION);
  }

  /**
   * Callback cuando cambia el estado
   */
  private onStateChange(newState: CombatState): void {
    switch (newState) {
      case CombatState.ATTACKING:
        console.log('🔴 Iniciando ataque');
        break;
      case CombatState.DEFENDING:
        console.log('🛡️ Modo defensa activado');
        break;
      case CombatState.SLOW_MOTION:
        console.log('⏱️ Cámara lenta activada');
        break;
      case CombatState.HIT:
        console.log('💥 ¡Impacto!');
        break;
    }
  }

  /**
   * Getters
   */
  getState(): CombatState {
    return this.currentState;
  }

  getStateElapsed(): number {
    return Date.now() - this.stateStartTime;
  }

  isInSlowMotion(): boolean {
    return this.currentState === CombatState.SLOW_MOTION;
  }

  getTimeScale(): number {
    return this.scene.animationTimeScale;
  }
}
