/**
 * Utilidades para el sistema de combate de DBVR.
 */

/**
 * Calcula el factor de daño basado en el Nivel de Poder (NP).
 * @param np Nivel de Poder actua del atacante.
 */
export function npDamageFactor(np: number): number {
  // Escala: 10,000 NP -> x2 daño. 100,000 NP -> x11 daño.
  return 1.0 + (np / 10000);
}

/**
 * Calcula la reducción de daño basada en el Nivel de Poder (NP).
 * @param np Nivel de Poder del defensor.
 */
export function getPowerLevelDamageReduction(np: number): number {
  if (np >= 70000) return 0.9;
  if (np >= 30000) return 0.7;
  if (np >= 10000) return 0.4;
  if (np >= 3000) return 0.2;
  return 0;
}

export interface ChargeLevel {
  label: string;
  timeMin: number;
  timeMax: number;
  ki: number;
  damage: number;
}

/**
 * Determina el nivel de carga alcanzado basado en el tiempo transcurrido y la configuración del ataque.
 */
export function getChargeLevel(
  levels: ChargeLevel[] | undefined,
  elapsed: number
): ChargeLevel | null {
  if (!levels) return null;
  let reached: ChargeLevel | null = null;
  for (const level of levels) {
    if (elapsed >= level.timeMin) reached = level;
  }
  return reached;
}
