/**
 * Tipos principales del sistema de combate VR KI
 */

export enum CombatState {
  NEUTRAL = 'NEUTRAL',
  ATTACKING = 'ATTACKING',
  DEFENDING = 'DEFENDING',
  HIT = 'HIT',
  SLOW_MOTION = 'SLOW_MOTION',
}

export enum GestureType {
  IDLE = 'IDLE',
  CHARGING = 'CHARGING',
  ATTACKING = 'ATTACKING',
  BLOCKING = 'BLOCKING',
  PARRYING = 'PARRYING',
  RECHARGING = 'RECHARGING',
}

export interface PlayerStats {
  health: number;
  maxHealth: number;
  ki: number;
  maxKi: number;
  position: { x: number; y: number; z: number };
}

export interface HandJoints {
  wrist: { x: number; y: number; z: number };
  indexTip: { x: number; y: number; z: number };
  middleTip: { x: number; y: number; z: number };
  ringTip: { x: number; y: number; z: number };
  littleTip: { x: number; y: number; z: number };
  thumbTip: { x: number; y: number; z: number };
}

export interface Projectile {
  id: string;
  position: { x: number; y: number; z: number };
  velocity: { x: number; y: number; z: number };
  damage: number;
  kiCost: number;
  radius: number;
  isActive: boolean;
}

export interface AttackAction {
  type: 'basic' | 'charged' | 'kamehameha';
  kiCost: number;
  damage: number;
  chargeTime: number;
  projectileSpeed: number;
}

export interface DefenseAction {
  type: 'block' | 'parry';
  kiCost: number;
  damageReduction: number;
  duration: number;
}
