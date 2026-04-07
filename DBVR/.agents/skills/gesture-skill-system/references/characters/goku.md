# Personaje: Goku — Config completa

Usar como template para otros personajes. Copiar y adaptar.

## Config completa lista para usar

```javascript
// ─────────────────────────────────────────────────────────────────
// PERSONAJE: GOKU
// Ataques: Ki Blast (rápido + cargado), Kamehameha, Genkidama, Kaioken
// ─────────────────────────────────────────────────────────────────

const gokuConfig = {
  id: 'goku',

  // ── Labels de gestos ──────────────────────────────────────────
  // Cada string es un label que se entrena en el KNN.
  // Deben coincidir EXACTAMENTE con los usados en fsmHandler.
  gestures: {
    stance:      'goku_stance',       // pose de combate neutra

    kiBlast: {
      ready:     'goku_kiblast_ready',   // una mano al frente, palma abierta
      forward:   'goku_kiblast_forward', // misma mano empujando hacia adelante
    },

    kamehameha: {
      phase1:    'goku_kame_phase1',  // manos juntas a la cadera (lateral)
      charge:    'goku_kame_charge',  // manos juntas sostenidas, cargando
      release:   'goku_kame_release', // empuje frontal con manos extendidas
    },

    genkidama: {
      gather:    'goku_genki_gather', // ambas manos alzadas, palmas al cielo
      charge:    'goku_genki_charge', // manos sobre la cabeza, sostenidas
      release:   'goku_genki_release',// manos bajando hacia el objetivo
    },

    kaioken: {
      trigger:   'goku_kaioken',      // brazos cruzados sobre el pecho
    },
  },

  // ── Extractor por estado FSM ───────────────────────────────────
  // 'wristOnly'            → solo muñecas (17 valores, más rápido)
  // 'wristAndFingertips'   → muñecas + dedos (47 valores, más preciso)
  extractors: {
    'idle':                   'wristOnly',
    'base':                   'wristOnly',
    'ki_blast_ready':         'wristOnly',        // posición de mano importa
    'ki_blast_forward':       'wristOnly',        // velocidad de muñeca importa
    'ki_blast_charging':      'wristOnly',
    'kame_phase1':            'wristOnly',        // manos juntas = posición amplia
    'kame_charging':          'wristOnly',
    'kame_releasing':         'wristOnly',
    'genki_gathering':        'wristAndFingertips', // palma abierta hacia arriba
    'genki_charging':         'wristOnly',
    'genki_releasing':        'wristOnly',
    'kaioken_charging':       'wristAndFingertips', // brazos cruzados = forma importa
  },

  // ── Umbrales de confianza por estado ──────────────────────────
  thresholds: {
    'idle':             0.65,
    'base':             0.65,
    'ki_blast_ready':   0.70,
    'ki_blast_forward': 0.68,
    'kame_phase1':      0.75,
    'kame_charging':    0.72,
    'genki_gathering':  0.70,
    'kaioken_charging': 0.75,
  },

  // ── Timing de ataques ─────────────────────────────────────────
  timing: {
    kiBlast: {
      quickThresholdMs: 150,    // si empuja en < 150ms = blast rápido
      chargeStartMs:    800,    // si sostiene > 800ms = entra en carga
      maxChargeMs:      4000,   // máximo tiempo de carga
      quickVelocity:    0.8,    // m/s mínimo para blast rápido
      chargedVelocity:  1.2,    // m/s para liberar carga
      cooldownMs:       220,
    },
    kamehameha: {
      minChargeMs:  1200,
      maxChargeMs:  8000,
      releaseHoldMs: 300,       // debe sostenerse el gesto de release
      maxWaitMs:    5000,       // timeout entre fases
    },
    genkidama: {
      gatherMs:    2000,        // tiempo mínimo recogiendo energía
      maxChargeMs: 10000,
      releaseHoldMs: 500,
    },
    kaioken: {
      minHoldMs: 800,           // sostener el gesto para activar
    },
  },

  // ── FSM Handler ───────────────────────────────────────────────
  // 'this' es la instancia de GestureSkillSystem
  fsmHandler: function(gesture, confidence, ctx, now) {
    const g  = gokuConfig.gestures;
    const t  = gokuConfig.timing;

    switch (this.currentState) {

      // ── IDLE / BASE ──────────────────────────────────────────
      case 'idle':
      case 'base':
        if (gesture === g.stance)             this._setState('base');
        if (gesture === g.kiBlast.ready)      this._setState('ki_blast_ready');
        if (gesture === g.kamehameha.phase1)  this._setState('kame_phase1');
        if (gesture === g.genkidama.gather)   this._setState('genki_gathering');
        if (gesture === g.kaioken.trigger) {
          this._setState('kaioken_charging');
          this._startCharge('kaioken', null, now);
        }
        break;

      // ── KI BLAST: LISTO ───────────────────────────────────
      case 'ki_blast_ready':
        if (gesture === g.kiBlast.forward) {
          this._setState('ki_blast_forward');
          this._startCharge('ki_blast', this._getActiveHand(ctx), now);
        } else if (gesture !== g.kiBlast.ready) {
          this._setState('idle'); // gesto perdido
        }
        break;

      // ── KI BLAST: FORWARD (decide rápido vs cargado) ─────
      case 'ki_blast_forward': {
        if (gesture !== g.kiBlast.forward) {
          this._cancelAttack();
          break;
        }
        const elapsed  = now - this.chargeStartTime;
        const velocity = this._getWristVelocity(this.lastBlastHand, ctx);

        // Blast rápido: movimiento veloz dentro del tiempo umbral
        if (elapsed < t.kiBlast.quickThresholdMs && velocity >= t.kiBlast.quickVelocity) {
          this._fireAttack('ki_blast', 1.0, this.lastBlastHand);
          this._setState('ki_blast_cooldown');
          break;
        }

        // Entrar en modo carga si el jugador sostiene
        if (elapsed >= t.kiBlast.chargeStartMs) {
          this._setState('ki_blast_charging');
        }
        break;
      }

      // ── KI BLAST: CARGANDO ────────────────────────────────
      case 'ki_blast_charging': {
        if (gesture !== g.kiBlast.forward) {
          this._cancelAttack();
          break;
        }
        const elapsed  = now - this.chargeStartTime;
        const velocity = this._getWristVelocity(this.lastBlastHand, ctx);
        const ratio    = Math.min(elapsed / t.kiBlast.maxChargeMs, 1.0);

        this.onChargeUpdate('ki_blast', ratio);

        // Liberar si empuja fuerte o si llegó al máximo de carga
        if (velocity >= t.kiBlast.chargedVelocity || elapsed >= t.kiBlast.maxChargeMs) {
          const power = 1.0 + ratio * 2.0; // 1.0 – 3.0x
          this._fireAttack('ki_blast', power, this.lastBlastHand);
          this._setState('ki_blast_cooldown');
        }
        break;
      }

      // ── KI BLAST: COOLDOWN ────────────────────────────────
      case 'ki_blast_cooldown':
        if (now - this.chargeStartTime > t.kiBlast.cooldownMs) {
          this._setState('base');
        }
        break;

      // ── KAMEHAMEHA: FASE 1 (manos a la cadera) ───────────
      case 'kame_phase1':
        if (gesture === g.kamehameha.charge) {
          this._setState('kame_charging');
          this._startCharge('kamehameha', 'both', now);
        } else if (gesture !== g.kamehameha.phase1) {
          // Tiempo de espera máximo antes de cancelar
          if (now - this.chargeStartTime > t.kamehameha.maxWaitMs) {
            this._cancelAttack();
          }
        }
        break;

      // ── KAMEHAMEHA: CARGANDO ──────────────────────────────
      case 'kame_charging': {
        if (gesture !== g.kamehameha.charge) {
          this._cancelAttack();
          break;
        }
        const elapsed = now - this.chargeStartTime;
        const ratio   = Math.min(elapsed / t.kamehameha.maxChargeMs, 1.0);
        this.onChargeUpdate('kamehameha', ratio);

        if (elapsed >= t.kamehameha.minChargeMs && gesture === g.kamehameha.release) {
          this._setState('kame_releasing');
        }
        if (elapsed >= t.kamehameha.maxChargeMs) {
          // Auto-disparo al máximo de carga
          this._fireAttack('kamehameha', 3.0, 'both');
          this._setState('idle');
        }
        break;
      }

      // ── KAMEHAMEHA: DISPARANDO ────────────────────────────
      case 'kame_releasing': {
        const elapsed = now - this.chargeStartTime;
        const ratio   = Math.min(elapsed / t.kamehameha.maxChargeMs, 1.0);
        if (now - this._releaseTime > t.kamehameha.releaseHoldMs) {
          this._fireAttack('kamehameha', 1.0 + ratio * 2.0, 'both');
          this._setState('idle');
        }
        break;
      }

      // ── GENKIDAMA: RECOGIENDO ENERGÍA ────────────────────
      case 'genki_gathering': {
        if (gesture !== g.genkidama.gather && gesture !== g.genkidama.charge) {
          this._cancelAttack();
          break;
        }
        const elapsed = now - this.chargeStartTime;
        this.onChargeUpdate('genkidama', Math.min(elapsed / t.genkidama.gatherMs, 1.0));

        if (elapsed >= t.genkidama.gatherMs) {
          this._setState('genki_charging');
        }
        break;
      }

      // ── GENKIDAMA: CARGADA (sosteniendo sobre la cabeza) ─
      case 'genki_charging': {
        if (gesture === g.genkidama.release) {
          this._setState('genki_releasing');
          this._releaseTime = now;
        } else if (gesture !== g.genkidama.charge) {
          this._cancelAttack();
        }
        break;
      }

      // ── GENKIDAMA: LANZANDO ───────────────────────────────
      case 'genki_releasing': {
        const elapsed = now - this.chargeStartTime;
        const ratio   = Math.min(elapsed / t.genkidama.maxChargeMs, 1.0);
        if (now - this._releaseTime > t.genkidama.releaseHoldMs) {
          this._fireAttack('genkidama', 1.0 + ratio * 4.0, 'both'); // hasta 5x power
          this._setState('idle');
        }
        break;
      }

      // ── KAIOKEN: ACTIVANDO ────────────────────────────────
      case 'kaioken_charging': {
        if (gesture !== g.kaioken.trigger) {
          this._cancelAttack();
          break;
        }
        const elapsed = now - this.chargeStartTime;
        if (elapsed >= t.kaioken.minHoldMs) {
          this._fireAttack('kaioken', 1.0, null); // Kaioken no tiene "poder", es una transformación
          this._setState('base');
        }
        break;
      }

      default:
        this._setState('idle');
    }
  },
};

export { gokuConfig };
```

---

## Labels de entrenamiento — referencia rápida

| Label | Gesto | Extractor | Frames sugeridos |
|---|---|---|---|
| `goku_stance` | Postura de combate neutra, manos al costado | wristOnly | 25 |
| `goku_kiblast_ready` | Una mano al frente, palma abierta | wristOnly | 20 |
| `goku_kiblast_forward` | Misma mano empujando hacia adelante | wristOnly | 20 |
| `goku_kame_phase1` | Manos juntas a la cadera (lateral, como en el anime) | wristOnly | 25 |
| `goku_kame_charge` | Manos juntas sostenidas, ligeramente hacia adelante | wristOnly | 25 |
| `goku_kame_release` | Manos extendidas hacia el frente | wristOnly | 20 |
| `goku_genki_gather` | Ambas manos alzadas, palmas hacia el cielo | wristAndFingertips | 20 |
| `goku_genki_charge` | Manos sobre/detrás de la cabeza, sostenidas | wristOnly | 20 |
| `goku_genki_release` | Manos bajando hacia el objetivo frente a ti | wristOnly | 15 |
| `goku_kaioken` | Brazos cruzados sobre el pecho | wristAndFingertips | 20 |

**Total**: ~210 frames de entrenamiento para Goku completo (~3 minutos en headset).
