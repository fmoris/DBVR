import { CombatSystem, GameStats, CombatState } from "./CombatSystem";

const STATE_LABELS: Record<CombatState, string> = {
  neutral: "Neutral",
  charging: "Cargando...",
  charging_special: "Carga Especial",
  attacking: "Atacando",
  defending: "Defendiendo",
  slowMotion: "Camara Lenta",
  hit: "Impacto",
  melee: "Combate Cercano",
};

const STATE_COLORS: Record<CombatState, string> = {
  neutral: "#00ff88",
  charging: "#ffcc00",
  charging_special: "#ff8800",
  attacking: "#ff6600",
  defending: "#00aaff",
  slowMotion: "#cc44ff",
  hit: "#ff2222",
  melee: "#ff0066",
};

function getNPColor(np: number): string {
  if (np >= 91) return "#ffffff";
  if (np >= 76) return "#ff8800";
  if (np >= 51) return "#ffcc00";
  if (np >= 21) return "#00ff88";
  return "#0088ff";
}

function getNPRange(np: number): string {
  if (np >= 91) return "TRASCENDENTE";
  if (np >= 76) return "DOMINANTE";
  if (np >= 51) return "ELEVADO";
  if (np >= 21) return "NORMAL";
  return "DEBILITADO";
}

export class HUD {
  private container: HTMLDivElement;
  private elements: Record<string, HTMLElement> = {};
  private npPopupTimeout: number | null = null;
  private voiceTimeout: number | null = null;

  constructor(private parent: HTMLElement, private combat: CombatSystem) {
    this.container = document.createElement("div");
    this.container.style.cssText = `
      position:absolute; inset:0; pointer-events:none;
      font-family:var(--font-saiyan); user-select:none; display:none;
    `;
    this.parent.appendChild(this.container);
    this.buildDOM();
    this.combat.onStatsChange((stats) => this.update(stats));
  }

  show(): void {
    this.container.style.display = "block";
    this.update(this.combat.getStats());
  }

  showVoiceTranscript(transcript: string): void {
    const el = this.elements["voiceIndicator"];
    if (!el) return;
    el.textContent = `\uD83C\uDFA4 ${transcript}`;
    el.style.opacity = "1";
    if (this.voiceTimeout) clearTimeout(this.voiceTimeout);
    this.voiceTimeout = window.setTimeout(() => {
      el.style.opacity = "0";
    }, 2000);
  }

  private buildDOM(): void {
    // ─── Borde de camara lenta ───────────────────────────────────────────
    const slowBorder = document.createElement("div");
    slowBorder.style.cssText = `
      position:absolute; inset:0;
      border:3px solid rgba(180,60,255,0.5);
      box-shadow:inset 0 0 80px rgba(180,60,255,0.2);
      pointer-events:none; display:none;
    `;
    this.container.appendChild(slowBorder);
    this.elements["slowBorder"] = slowBorder;

    // ─── Indicador de estado (centro-arriba) ─────────────────────────────
    const stateLabel = document.createElement("div");
    stateLabel.style.cssText = `
      position:absolute; top:18px; left:50%; transform:translateX(-50%);
      font-size:12px; font-weight:bold; letter-spacing:3px; text-transform:uppercase;
      background:rgba(0,0,0,0.55); padding:4px 18px; border-radius:4px;
      border:1px solid rgba(0,200,255,0.3);
    `;
    this.container.appendChild(stateLabel);
    this.elements["stateLabel"] = stateLabel;

    // ─── Indicador de carga / ataque especial (centro) ───────────────────
    const chargeIndicator = document.createElement("div");
    chargeIndicator.style.cssText = `
      position:absolute; top:56px; left:50%; transform:translateX(-50%);
      font-size:12px; font-weight:bold; letter-spacing:2px;
      background:rgba(0,0,0,0.7); padding:6px 18px; border-radius:4px;
      border:1px solid rgba(255,200,0,0.3); display:none; text-align:center;
    `;
    this.container.appendChild(chargeIndicator);
    this.elements["chargeIndicator"] = chargeIndicator;

    // ─── Alerta de ataque enemigo (centro, debajo del estado) ────────────
    const enemyAttack = document.createElement("div");
    enemyAttack.style.cssText = `
      position:absolute; top:100px; left:50%; transform:translate(-50%,0);
      font-size:15px; font-weight:bold; letter-spacing:3px; color:#ff4444;
      background:rgba(40,0,0,0.85); padding:6px 22px; border-radius:4px;
      border:1px solid #ff444466; opacity:0;
      transition:opacity 0.2s;
      text-shadow:0 0 12px #ff4444;
    `;
    this.container.appendChild(enemyAttack);
    this.elements["enemyAttack"] = enemyAttack;

    // ─── Popup de NP flotante ────────────────────────────────────────────
    const npPopup = document.createElement("div");
    npPopup.style.cssText = `
      position:absolute; top:45%; left:50%; transform:translate(-50%,-50%);
      font-size:26px; font-weight:bold; letter-spacing:4px;
      opacity:0; pointer-events:none; transition:opacity 0.3s, transform 0.3s;
      text-shadow:0 0 20px currentColor;
    `;
    this.container.appendChild(npPopup);
    this.elements["npPopup"] = npPopup;

    // ─── Indicador de voz (centro-bajo) ──────────────────────────────────
    const voiceIndicator = document.createElement("div");
    voiceIndicator.style.cssText = `
      position:absolute; bottom:160px; left:50%; transform:translateX(-50%);
      font-size:11px; letter-spacing:2px; color:#aa88ff;
      background:rgba(20,0,40,0.75); padding:4px 14px; border-radius:4px;
      border:1px solid #aa88ff44; opacity:0;
      transition:opacity 0.3s; max-width:380px; text-align:center;
    `;
    this.container.appendChild(voiceIndicator);
    this.elements["voiceIndicator"] = voiceIndicator;

    // ─── Panel izquierdo inferior (barras del jugador) ────────────────────
    this.container.appendChild(this.buildLeftPanel());

    // ─── Panel derecho inferior (barras del enemigo + minimapa) ──────────
    this.container.appendChild(this.buildRightPanel());

    // ─── Botones de control (fila inferior central, semi-transparente) ────
    this.container.appendChild(this.buildControlsBar());
  }

  // =========================================================================
  // PANEL IZQUIERDO — jugador
  // =========================================================================
  private buildLeftPanel(): HTMLDivElement {
    const panel = document.createElement("div");
    panel.style.cssText = `
      position:absolute; bottom:24px; left:20px;
      pointer-events:auto;
    `;

    // SVG clip-path para forma de escudo tech (esquina redondeada arriba-derecha)
    panel.innerHTML = `
      <div style="
        position:relative;
        background:linear-gradient(135deg,rgba(0,20,50,0.92) 0%,rgba(0,40,80,0.85) 100%);
        border:1.5px solid rgba(0,180,255,0.55);
        border-radius:10px 28px 10px 10px;
        padding:14px 18px 12px 14px;
        min-width:190px;
        box-shadow:0 0 24px rgba(0,150,255,0.25), inset 0 0 16px rgba(0,100,200,0.1);
      ">
        <!-- Decoracion tech superior -->
        <div style="
          position:absolute; top:-1px; left:16px; right:32px; height:2px;
          background:linear-gradient(90deg,transparent,rgba(0,200,255,0.8),transparent);
        "></div>

        <!-- Etiqueta jugador -->
        <div style="
          font-size:9px; letter-spacing:3px; color:rgba(0,200,255,0.7);
          text-transform:uppercase; margin-bottom:10px;
        ">JUGADOR</div>

        <!-- Barra NP (verde/color dinamico) -->
        <div style="margin-bottom:7px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px;">
            <span style="font-size:9px;letter-spacing:2px;color:rgba(255,255,255,0.5);">NP</span>
            <span id="player-np-label" style="font-size:10px;font-weight:bold;color:#00ff88;">NORMAL 50%</span>
          </div>
          <div style="
            width:100%; height:10px;
            background:rgba(0,0,0,0.6);
            border:1px solid rgba(0,255,136,0.3);
            border-radius:2px; overflow:hidden;
          ">
            <div id="player-np-bar" style="
              height:100%; width:50%;
              background:linear-gradient(90deg,#00aa5588,#00ff88);
              box-shadow:0 0 8px #00ff88;
              transition:width 0.15s ease;
            "></div>
          </div>
        </div>

        <!-- Barra HP (verde solida) -->
        <div style="margin-bottom:7px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px;">
            <span style="font-size:9px;letter-spacing:2px;color:rgba(255,255,255,0.5);">HP</span>
            <span style="font-size:10px;color:#44ff66;">100%</span>
          </div>
          <div style="
            width:100%; height:8px;
            background:rgba(0,0,0,0.6);
            border:1px solid rgba(0,255,80,0.3);
            border-radius:2px; overflow:hidden;
          ">
            <div id="player-hp-bar" style="
              height:100%; width:100%;
              background:linear-gradient(90deg,#22aa44,#44ff66);
              box-shadow:0 0 6px #44ff66;
              transition:width 0.15s ease;
            "></div>
          </div>
        </div>

        <!-- Barra KI (cyan) -->
        <div>
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px;">
            <span style="font-size:9px;letter-spacing:2px;color:rgba(255,255,255,0.5);">KI</span>
            <span id="player-ki-label" style="font-size:10px;color:#00ccff;">100</span>
          </div>
          <div style="
            width:100%; height:8px;
            background:rgba(0,0,0,0.6);
            border:1px solid rgba(0,200,255,0.3);
            border-radius:2px; overflow:hidden;
          ">
            <div id="player-ki-bar" style="
              height:100%; width:100%;
              background:linear-gradient(90deg,#0088bb88,#00ccff);
              box-shadow:0 0 6px #00ccff;
              transition:width 0.15s ease;
            "></div>
          </div>
        </div>

        <!-- Decoracion esquina tech -->
        <div style="
          position:absolute; bottom:6px; right:8px;
          width:8px; height:8px;
          border-right:2px solid rgba(0,200,255,0.5);
          border-bottom:2px solid rgba(0,200,255,0.5);
        "></div>
      </div>
    `;
    return panel;
  }

  // =========================================================================
  // PANEL DERECHO — enemigo + indicador de KI circular
  // =========================================================================
  private buildRightPanel(): HTMLDivElement {
    const panel = document.createElement("div");
    panel.style.cssText = `
      position:absolute; bottom:24px; right:20px;
      pointer-events:none;
    `;

    panel.innerHTML = `
      <div style="
        position:relative;
        background:linear-gradient(225deg,rgba(0,20,50,0.92) 0%,rgba(0,40,80,0.85) 100%);
        border:1.5px solid rgba(0,180,255,0.55);
        border-radius:28px 10px 10px 10px;
        padding:14px 14px 12px 18px;
        min-width:190px;
        box-shadow:0 0 24px rgba(0,150,255,0.25), inset 0 0 16px rgba(0,100,200,0.1);
      ">
        <!-- Decoracion tech superior -->
        <div style="
          position:absolute; top:-1px; left:32px; right:16px; height:2px;
          background:linear-gradient(90deg,transparent,rgba(0,200,255,0.8),transparent);
        "></div>

        <!-- Etiqueta enemigo -->
        <div style="
          font-size:9px; letter-spacing:3px; color:rgba(255,80,80,0.8);
          text-transform:uppercase; margin-bottom:10px; text-align:right;
        ">ENEMIGO</div>

        <!-- Barra NP enemigo -->
        <div style="margin-bottom:7px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px;">
            <span id="enemy-np-label" style="font-size:10px;font-weight:bold;color:#ff4444;">NORMAL 50%</span>
            <span style="font-size:9px;letter-spacing:2px;color:rgba(255,255,255,0.5);">NP</span>
          </div>
          <div style="
            width:100%; height:10px;
            background:rgba(0,0,0,0.6);
            border:1px solid rgba(255,60,60,0.3);
            border-radius:2px; overflow:hidden;
          ">
            <div id="enemy-np-bar" style="
              height:100%; width:50%;
              background:linear-gradient(90deg,#aa222288,#ff4444);
              box-shadow:0 0 8px #ff4444;
              transition:width 0.15s ease;
            "></div>
          </div>
        </div>

        <!-- Barra HP enemigo (rojo) -->
        <div style="margin-bottom:7px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px;">
            <span style="font-size:10px;color:#ff6666;">100%</span>
            <span style="font-size:9px;letter-spacing:2px;color:rgba(255,255,255,0.5);">HP</span>
          </div>
          <div style="
            width:100%; height:8px;
            background:rgba(0,0,0,0.6);
            border:1px solid rgba(255,60,60,0.3);
            border-radius:2px; overflow:hidden;
          ">
            <div id="enemy-hp-bar" style="
              height:100%; width:100%;
              background:linear-gradient(90deg,#aa2222,#ff6666);
              box-shadow:0 0 6px #ff4444;
              transition:width 0.15s ease;
            "></div>
          </div>
        </div>

        <!-- Barra KI enemigo (naranja) -->
        <div>
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:3px;">
            <span id="enemy-ki-label" style="font-size:10px;color:#00ccff;">100</span>
            <span style="font-size:9px;letter-spacing:2px;color:rgba(255,255,255,0.5);">KI</span>
          </div>
          <div style="
            width:100%; height:8px;
            background:rgba(0,0,0,0.6);
            border:1px solid rgba(0,200,255,0.3);
            border-radius:2px; overflow:hidden;
          ">
            <div id="enemy-ki-bar" style="
              height:100%; width:100%;
              background:linear-gradient(90deg,#0088bb88,#00ccff);
              box-shadow:0 0 6px #00ccff;
              transition:width 0.15s ease;
            "></div>
          </div>
        </div>

        <!-- Decoracion esquina tech -->
        <div style="
          position:absolute; bottom:6px; left:8px;
          width:8px; height:8px;
          border-left:2px solid rgba(0,200,255,0.5);
          border-bottom:2px solid rgba(0,200,255,0.5);
        "></div>
      </div>
    `;
    return panel;
  }

  // =========================================================================
  // BARRA DE CONTROLES — fila inferior central, compacta
  // =========================================================================
  private buildControlsBar(): HTMLDivElement {
    const bar = document.createElement("div");
    bar.style.cssText = `
      position:absolute; bottom:24px; left:50%; transform:translateX(-50%);
      display:flex; gap:6px; align-items:center; pointer-events:auto;
    `;

    const btns = [
      { id: "btn-attack",      key: "A", label: "Atacar",     color: "#00ccff", bg: "rgba(0,40,80,0.85)" },
      { id: "btn-charged",     key: "W", label: "Cargar",     color: "#ffcc00", bg: "rgba(40,30,0,0.85)" },
      { id: "btn-block",       key: "S", label: "Bloquear",   color: "#00ff88", bg: "rgba(0,40,20,0.85)" },
      { id: "btn-dodge",       key: "D", label: "Esquivar",   color: "#66ccff", bg: "rgba(0,20,40,0.85)" },
      { id: "btn-recharge",    key: "R", label: "Recargar",   color: "#cc44ff", bg: "rgba(30,0,50,0.85)" },
      { id: "btn-kamehameha",  key: "1", label: "Kame",       color: "#00aaff", bg: "rgba(0,20,50,0.85)" },
      { id: "btn-finalflash",  key: "2", label: "F.Flash",    color: "#ffaa00", bg: "rgba(40,20,0,0.85)" },
    ];

    btns.forEach(({ id, key, label, color, bg }) => {
      const btn = document.createElement("button");
      btn.id = id;
      btn.style.cssText = `
        padding:6px 10px;
        background:${bg};
        border:1px solid ${color}66;
        border-radius:4px;
        color:${color};
        font-size:9px;
        font-family:var(--font-saiyan);
        font-weight:bold;
        letter-spacing:1px;
        cursor:pointer;
        text-transform:uppercase;
        line-height:1.3;
        text-align:center;
        box-shadow:0 0 8px ${color}22;
        transition:box-shadow 0.15s, border-color 0.15s;
      `;
      btn.innerHTML = `<span style="font-size:8px;opacity:0.6;">[${key}]</span><br>${label}`;
      btn.addEventListener("mouseenter", () => {
        btn.style.boxShadow = `0 0 14px ${color}55`;
        btn.style.borderColor = `${color}aa`;
      });
      btn.addEventListener("mouseleave", () => {
        btn.style.boxShadow = `0 0 8px ${color}22`;
        btn.style.borderColor = `${color}66`;
      });
      bar.appendChild(btn);
    });

    // Eventos
    const c = this.combat;
    bar.querySelector("#btn-attack")!.addEventListener("click", () => c.launchBasicAttack());
    bar.querySelector("#btn-charged")!.addEventListener("click", () => {
      if (c.isInChargingState()) c.releaseChargedAttack();
      else c.startChargedAttack();
    });
    bar.querySelector("#btn-block")!.addEventListener("click", () => c.activateBlock());
    bar.querySelector("#btn-dodge")!.addEventListener("click", () => c.activateDodge());
    bar.querySelector("#btn-recharge")!.addEventListener("click", () => c.rechargeKi());
    bar.querySelector("#btn-kamehameha")!.addEventListener("click", () => c.kamehamehaStep(1));
    bar.querySelector("#btn-finalflash")!.addEventListener("click", () => c.finalFlashStep(1));

    return bar;
  }

  // =========================================================================
  // UPDATE — sincroniza el HUD con el estado del combate
  // =========================================================================
  private update(stats: GameStats): void {
    const color = STATE_COLORS[stats.combatState];
    const label = this.elements["stateLabel"];
    let labelText = STATE_LABELS[stats.combatState];
    if (stats.isSlowMotion) labelText += " · CAMARA LENTA";
    if (stats.chargeTime > 0) labelText += ` (${stats.chargeTime.toFixed(1)}s)`;
    label.textContent = labelText;
    label.style.color = color;
    label.style.textShadow = `0 0 10px ${color}`;
    label.style.borderColor = `${color}44`;

    // Indicador de carga especial
    const chargeEl = this.elements["chargeIndicator"];
    if (stats.combatState === "charging_special" && stats.specialType) {
      chargeEl.style.display = "block";
      const name = stats.specialType === "kamehameha" ? "KAMEHAMEHA" : "FINAL FLASH";
      const t = stats.chargeTime;
      const levels = stats.specialType === "kamehameha"
        ? [{ label: "MINIMO", timeMin: 2 }, { label: "MEDIO", timeMin: 5 }, { label: "MAXIMO", timeMin: 8 }]
        : [{ label: "MINIMO", timeMin: 3 }, { label: "MEDIO", timeMin: 6 }, { label: "MAXIMO", timeMin: 10 }];
      let idx = -1;
      for (let i = 0; i < levels.length; i++) if (t >= levels[i].timeMin) idx = i;
      const lvColor = idx === 2 ? "#ff4444" : idx === 1 ? "#ff8800" : idx === 0 ? "#ffcc00" : "#888";
      const lvLabel = idx >= 0 ? levels[idx].label : "CARGANDO";
      const next = levels[idx + 1];
      const nextInfo = next ? ` → ${next.label} en ${(next.timeMin - t).toFixed(1)}s` : " ★ MAX";
      chargeEl.style.color = lvColor;
      chargeEl.innerHTML = `\u26A1 ${name} ${t.toFixed(1)}s &nbsp; <span style="font-weight:bold;">${lvLabel}</span><span style="font-size:10px;color:#aaa;">${nextInfo}</span>`;
    } else if (stats.combatState === "charging") {
      chargeEl.style.display = "block";
      chargeEl.style.color = "#ffcc00";
      chargeEl.innerHTML = `\u23F3 CARGANDO: ${stats.chargeTime.toFixed(1)}s`;
    } else if (stats.combatState === "attacking" && stats.currentAttack) {
      chargeEl.style.display = "block";
      chargeEl.style.color = "#ff6600";
      chargeEl.innerHTML = `\uD83D\uDD25 ${stats.currentAttack.toUpperCase()}`;
    } else {
      chargeEl.style.display = "none";
    }

    this.elements["slowBorder"].style.display = stats.isSlowMotion ? "block" : "none";

    // Barras jugador
    const pNPBar = this.container.querySelector("#player-np-bar") as HTMLElement;
    const pNPLabel = this.container.querySelector("#player-np-label") as HTMLElement;
    const pKiBar = this.container.querySelector("#player-ki-bar") as HTMLElement;
    const pKiLabel = this.container.querySelector("#player-ki-label") as HTMLElement;
    if (pNPBar) {
      const c2 = getNPColor(stats.playerNP);
      pNPBar.style.width = `${stats.playerNP}%`;
      pNPBar.style.background = `linear-gradient(90deg,${c2}66,${c2})`;
      pNPBar.style.boxShadow = `0 0 8px ${c2}`;
    }
    if (pNPLabel) {
      const c2 = getNPColor(stats.playerNP);
      pNPLabel.textContent = `${getNPRange(stats.playerNP)} ${stats.playerNP.toFixed(0)}%`;
      pNPLabel.style.color = c2;
    }
    if (pKiBar) pKiBar.style.width = `${stats.playerKi}%`;
    if (pKiLabel) pKiLabel.textContent = `${stats.playerKi.toFixed(0)}`;

    // Barras enemigo
    const eNPBar = this.container.querySelector("#enemy-np-bar") as HTMLElement;
    const eNPLabel = this.container.querySelector("#enemy-np-label") as HTMLElement;
    const eKiBar = this.container.querySelector("#enemy-ki-bar") as HTMLElement;
    const eKiLabel = this.container.querySelector("#enemy-ki-label") as HTMLElement;
    if (eNPBar) {
      const c2 = getNPColor(stats.enemyNP);
      eNPBar.style.width = `${stats.enemyNP}%`;
      eNPBar.style.background = `linear-gradient(90deg,${c2}66,${c2})`;
      eNPBar.style.boxShadow = `0 0 8px ${c2}`;
    }
    if (eNPLabel) {
      const c2 = getNPColor(stats.enemyNP);
      eNPLabel.textContent = `${getNPRange(stats.enemyNP)} ${stats.enemyNP.toFixed(0)}%`;
      eNPLabel.style.color = c2;
    }
    if (eKiBar) eKiBar.style.width = `${stats.enemyKi}%`;
    if (eKiLabel) eKiLabel.textContent = `${stats.enemyKi.toFixed(0)}`;

    // Alerta ataque enemigo
    const enemyAttackEl = this.elements["enemyAttack"];
    if (enemyAttackEl) {
      if (stats.enemyAttacking && stats.enemyAttackName) {
        enemyAttackEl.textContent = `\u26A1 ENEMIGO: ${stats.enemyAttackName.toUpperCase()}`;
        enemyAttackEl.style.opacity = "1";
      } else {
        enemyAttackEl.style.opacity = "0";
      }
    }
  }
}
