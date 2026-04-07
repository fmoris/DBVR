# Data Mapping Strategy — GestureSkillSystem

Para que el sistema sea consistente, el skill debe seguir estas reglas al transformar JSONs en código:

## 1. Mapeo de Labels de Entrenamiento
Los labels usados en el clasificador KNN deben seguir este formato:
`[character_id]_[gesture_id_from_powers_json]`

**Ejemplo (Goku + Kamehameha):**
- Character ID: `goku`
- Prep Gesture from powers.json: `hands_clasped_at_waist`
- **Training Label**: `goku_hands_clasped_at_waist`

## 2. Mapeo de Timing
El campo `charge_time` de `powers.json` es la base para los tiempos del FSM:

| Parámetro FSM | Cálculo sugerido | Razón |
|---|---|---|
| `minChargeMs` | `charge_time * 1000 * 0.5` | Permite disparos rápidos pero no instantáneos |
| `maxChargeMs` | `charge_time * 1000` | El tiempo exacto para alcanzar el poder "full" |
| `maxWaitMs` | `min(charge_time * 2000, 8000)`| Límite para sostener la pose sin disparar |

## 3. Mapeo de Extractores
Si el `firing` gesture en `powers.json` contiene palabras clave, se elige el extractor:

- Si termina en `_aim`, `_open`, `_clench`, `_together` → usar `wristAndFingertips`.
- Por defecto → usar `wristOnly`.

## 4. Reconstrucción de CharacterConfig
Al generar un personaje:
1. Leer `[character].json` -> obtener lista de `powers`.
2. Por cada power, buscar en `powers.json`.
3. Construir el objeto `extractors`, `thresholds` y `timing` automáticamente.
4. Generar el `fsmHandler` conectando las fases `preparation` -> `firing`.
