import { CombatSystem, GameStats, CombatState } from "./CombatSystem";
import powersConfig from "../models/powers.json";
import gokuConfig from "../models/goku.json";

const STATE_LABELS: Record<CombatState, string> = {
  neutral: "Neutral",
  charging: "Cargando...",
  charging_special: "Carga Especial",
  attacking: "Atacando",
  defending: "Defendiendo",
  slowMotion: "Camara Lenta",
  hit: "Impacto",
  melee: "Combate Cercano",
  recharging: "Recargando KI...",
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
  recharging: "#cc44ff",
};

function getNPColor(np: number): string {
  if (np >= 150000) return "#ffffff";
  if (np >= 70000)  return "#ff8800";
  if (np >= 30000)  return "#ffcc00";
  if (np >= 10000)  return "#00ecff";
  if (np >= 3000)   return "#00ff88";
  return "#aabbcc";
}

function getNPRange(np: number): string {
  if (np >= 150000) return "TRASCENDENTE";
  if (np >= 70000)  return "DOMINANTE";
  if (np >= 30000)  return "ELEVADO";
  if (np >= 10000)  return "FUERTE";
  if (np >= 3000)   return "ESTABLE";
  return "DEBILITADO";
}

export class HUD {
  private container: HTMLDivElement;
  private elements: Record<string, HTMLElement> = {};
  private npPopupTimeout: number | null = null;
  private voiceTimeout: number | null = null;
  private menuCallback: (() => void) | null = null;
  private debugCallback: (() => void) | null = null;

  constructor(private parent: HTMLElement, private combat: CombatSystem) {
    this.container = document.createElement("div");
    // position:fixed con width/height explícitos para que dom-overlay de Quest
    // lo renderice correctamente. position:absolute puede quedar fuera del viewport XR.
    this.container.style.cssText = `
      position:fixed;
      top:0; left:0;
      width:100%; height:100%;
      pointer-events:none;
      font-family:var(--font-body, sans-serif);
      user-select:none;
      display:none;
      z-index:100;
    `;
    this.parent.appendChild(this.container);
    this.buildDOM();
    this.combat.onStatsChange((stats) => this.update(stats));
  }

  show(): void {
    this.container.style.display = "block";
    this.update(this.combat.getStats());
  }

  hide(): void {
    this.container.style.display = "none";
  }

  onMenu(cb: () => void): void {
    this.menuCallback = cb;
  }

  onDebugToggle(cb: () => void): void {
    this.debugCallback = cb;
  }

  showVoiceTranscript(transcript: string): void {
    const el = this.elements["voiceIndicator"];
    if (!el) return;
    el.textContent = `\uD83C\uDFA4 ${transcript}`;
    el.style.opacity = "1";
    if (this.voiceTimeout) clearTimeout(this.voiceTimeout);
    this.voiceTimeout = window.setTimeout(() => {
      el.style.opacity = "0";
    }, 5000);
  }

  private buildDOM(): void {
    // ─── Borde de camara lenta (viñeta + aberracion cromatica) ─────────────
    const slowBorder = document.createElement("div");
    slowBorder.style.cssText = `
      position:absolute; inset:0;
      border:4px solid rgba(180,60,255,0.7);
      box-shadow:
        inset 0 0 120px rgba(180,60,255,0.35),
        inset 0 0 60px rgba(0,200,255,0.15),
        0 0 40px rgba(180,60,255,0.4);
      pointer-events:none; display:none;
      animation:none;
    `;
    this.container.appendChild(slowBorder);
    this.elements["slowBorder"] = slowBorder;

    // ─── Overlay de aberracion cromatica (solo durante bullet time) ──────
    const chromaOverlay = document.createElement("div");
    chromaOverlay.style.cssText = `
      position:absolute; inset:0;
      pointer-events:none; display:none;
      mix-blend-mode:screen;
      background:
        radial-gradient(ellipse at 30% 50%, rgba(255,0,80,0.06) 0%, transparent 60%),
        radial-gradient(ellipse at 70% 50%, rgba(0,100,255,0.06) 0%, transparent 60%);
    `;
    this.container.appendChild(chromaOverlay);
    this.elements["chromaOverlay"] = chromaOverlay;

    // ─── Etiqueta BULLET TIME ────────────────────────────────────────────
    const bulletLabel = document.createElement("div");
    bulletLabel.style.cssText = `
      position:absolute; top:50%; left:50%; transform:translate(-50%,-50%);
      font-size:28px; font-weight:bold; letter-spacing:8px; color:#cc44ff;
      text-shadow:0 0 30px #cc44ff, 0 0 60px #8800ff;
      opacity:0; pointer-events:none;
      transition:opacity 0.3s;
      text-transform:uppercase;
    `;
    bulletLabel.textContent = "BULLET TIME";
    this.container.appendChild(bulletLabel);
    this.elements["bulletLabel"] = bulletLabel;

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
  // PANELES DE ACCION — derecha: ataque | izquierda: defensa
  // =========================================================================
  private buildControlsBar(): HTMLDivElement {
    // Contenedor fantasma que agrupa ambos paneles (no ocupa espacio)
    const wrapper = document.createElement("div");
    wrapper.style.cssText = `position:absolute; inset:0; pointer-events:none;`;

    // ── Estilos comunes ──────────────────────────────────────────────────────
    const makeBtn = (
      id: string, key: string, label: string,
      color: string, bg: string, wide = false
    ): HTMLButtonElement => {
      const btn = document.createElement("button");
      btn.id = id;
      btn.style.cssText = `
        padding:${wide ? "10px 14px" : "8px 12px"};
        background:${bg};
        border:1.5px solid ${color}66;
        border-radius:6px;
        color:${color};
        font-size:10px;
        font-family:var(--font-body);
        font-weight:700;
        letter-spacing:1px;
        cursor:pointer;
        text-transform:uppercase;
        line-height:1.4;
        text-align:center;
        box-shadow:0 0 10px ${color}22, inset 0 0 6px ${color}11;
        transition:box-shadow 0.15s, border-color 0.15s, transform 0.1s;
        pointer-events:auto;
        width:${wide ? "100%" : "auto"};
      `;
      btn.innerHTML = `${label}<br><span style="font-size:8px;opacity:0.45;">[${key}]</span>`;
      btn.addEventListener("mouseenter", () => {
        btn.style.boxShadow = `0 0 18px ${color}66, inset 0 0 8px ${color}22`;
        btn.style.borderColor = `${color}cc`;
        btn.style.transform = "scale(1.05)";
      });
      btn.addEventListener("mouseleave", () => {
        btn.style.boxShadow = `0 0 10px ${color}22, inset 0 0 6px ${color}11`;
        btn.style.borderColor = `${color}66`;
        btn.style.transform = "scale(1)";
      });
      return btn;
    };

    const makePanelLabel = (text: string, color: string): HTMLDivElement => {
      const lbl = document.createElement("div");
      lbl.style.cssText = `
        font-size:8px; letter-spacing:3px; color:${color};
        text-transform:uppercase; text-align:center;
        margin-bottom:6px; opacity:0.7;
      `;
      lbl.textContent = text;
      return lbl;
    };

    // ── PANEL DERECHO — ATAQUE ───────────────────────────────────────────────
    const attackPanel = document.createElement("div");
    attackPanel.style.cssText = `
      position:absolute;
      right:20px;
      top:50%;
      transform:translateY(-50%);
      display:flex;
      flex-direction:column;
      gap:8px;
      align-items:stretch;
      pointer-events:auto;
      background:linear-gradient(135deg,rgba(0,10,30,0.88) 0%,rgba(0,30,60,0.82) 100%);
      border:1.5px solid rgba(0,180,255,0.35);
      border-radius:12px;
      padding:14px 12px;
      min-width:100px;
      box-shadow:0 0 28px rgba(0,150,255,0.18), inset 0 0 12px rgba(0,100,200,0.08);
    `;
    attackPanel.appendChild(makePanelLabel("ATAQUE", "#00ccff"));
    attackPanel.appendChild(makeBtn("btn-attack",     "A", "Atacar",    "#00ccff", "rgba(0,40,80,0.85)",     true));
    attackPanel.appendChild(makeBtn("btn-charged",    "W", "Cargar",    "#ffcc00", "rgba(40,30,0,0.85)",     true));

    const powersDict = powersConfig as Record<string, any>;
    const allowedPowers = gokuConfig.transformations[0].powers || [];
    let keyIdx = 1;
    for (const key of allowedPowers) {
      const details = powersDict[key];
      if (details && (details.type === "ofensiva" || details.type === "sacrificio" || details.type === "especial")) {
        const color = key === "kamehameha" ? "#00aaff" : (key.includes("flash") ? "#ffaa00" : "#ff44ff");
        attackPanel.appendChild(makeBtn(`btn-${key}`, `${keyIdx}`, details.name || key, color, "rgba(50,25,0,0.90)", true));
        keyIdx++;
      }
    }

    // ── PANEL IZQUIERDO — DEFENSA ────────────────────────────────────────────
    const defensePanel = document.createElement("div");
    defensePanel.style.cssText = `
      position:absolute;
      left:20px;
      top:50%;
      transform:translateY(-50%);
      display:flex;
      flex-direction:column;
      gap:8px;
      align-items:stretch;
      pointer-events:auto;
      background:linear-gradient(135deg,rgba(0,20,10,0.88) 0%,rgba(0,40,20,0.82) 100%);
      border:1.5px solid rgba(0,200,120,0.35);
      border-radius:12px;
      padding:14px 12px;
      min-width:100px;
      box-shadow:0 0 28px rgba(0,200,100,0.15), inset 0 0 12px rgba(0,150,80,0.08);
    `;
    defensePanel.appendChild(makePanelLabel("DEFENSA", "#00ff88"));
    defensePanel.appendChild(makeBtn("btn-block",    "S", "Bloquear",  "#00ff88", "rgba(0,40,20,0.85)",  true));
    defensePanel.appendChild(makeBtn("btn-dodge",    "D", "Esquivar",  "#66ccff", "rgba(0,20,40,0.85)",  true));
    defensePanel.appendChild(makeBtn("btn-recharge", "R", "Recargar",  "#cc44ff", "rgba(30,0,50,0.85)",  true));

    // ── BOTONES DE SISTEMA — esquina inferior central ────────────────────────
    const sysBar = document.createElement("div");
    sysBar.style.cssText = `
      position:absolute;
      bottom:20px;
      left:50%;
      transform:translateX(-50%);
      display:flex;
      gap:6px;
      pointer-events:auto;
    `;
    sysBar.appendChild(makeBtn("btn-menu",  "M", "Menú",  "#ff4444", "rgba(50,0,0,0.85)"));
    sysBar.appendChild(makeBtn("btn-debug", "G", "DBG",   "#ffff00", "rgba(30,30,0,0.85)"));

    wrapper.appendChild(attackPanel);
    wrapper.appendChild(defensePanel);
    wrapper.appendChild(sysBar);

    // ── Eventos ──────────────────────────────────────────────────────────────
    const c = this.combat;
    wrapper.querySelector("#btn-attack")!.addEventListener("click", () => c.launchBasicAttack());
    wrapper.querySelector("#btn-charged")!.addEventListener("click", () => {
      if (c.isInChargingState()) c.releaseChargedAttack();
      else c.startChargedAttack();
    });
    wrapper.querySelector("#btn-block")!.addEventListener("click", () => c.activateBlock());
    wrapper.querySelector("#btn-dodge")!.addEventListener("click", () => c.activateDodge());
    wrapper.querySelector("#btn-recharge")!.addEventListener("click", () => c.rechargeKi());

    for (const key of allowedPowers) {
      const details = powersDict[key];
      if (details && (details.type === "ofensiva" || details.type === "sacrificio" || details.type === "especial")) {
        const btn = wrapper.querySelector(`#btn-${key}`);
        if (btn) btn.addEventListener("click", () => c.triggerSpecial(key));
      }
    }
    wrapper.querySelector("#btn-menu")!.addEventListener("click", () => {
      if (this.menuCallback) this.menuCallback();
    });
    wrapper.querySelector("#btn-debug")!.addEventListener("click", () => {
      if (this.debugCallback) this.debugCallback();
    });

    return wrapper as HTMLDivElement;
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

    const inSlow = stats.isSlowMotion;
    this.elements["slowBorder"].style.display    = inSlow ? "block" : "none";
    this.elements["chromaOverlay"].style.display = inSlow ? "block" : "none";
    // Mostrar etiqueta BULLET TIME solo al inicio (fade in/out)
    const bl = this.elements["bulletLabel"];
    if (bl) bl.style.opacity = inSlow ? "1" : "0";

    // Barras jugador
    const pNPBar = this.container.querySelector("#player-np-bar") as HTMLElement;
    const pNPLabel = this.container.querySelector("#player-np-label") as HTMLElement;
    const pKiLabel = this.container.querySelector("#player-ki-label") as HTMLElement;

    if (pNPBar) {
      const c2 = getNPColor(stats.playerNP);
      const pct = Math.min(100, (stats.playerNP / 100000) * 100);
      pNPBar.style.width = `${pct}%`;
      pNPBar.style.background = `linear-gradient(90deg,${c2}66,${c2})`;
      pNPBar.style.boxShadow = `0 0 8px ${c2}`;
    }
    if (pNPLabel) {
      const c2 = getNPColor(stats.playerNP);
      const npFormatted = stats.playerNP.toLocaleString();
      pNPLabel.textContent = `${getNPRange(stats.playerNP)} ${npFormatted}`;
      pNPLabel.style.color = c2;
    }
    if (pKiLabel) {
      pKiLabel.textContent = `KI: ${stats.playerKi.toFixed(0)}`;
      pKiLabel.style.color = stats.playerKi > 30 ? "#00ccff" : "#ff4444";
      pKiLabel.style.fontSize = "12px";
      pKiLabel.style.fontWeight = "bold";
    }

    // Filtrado de botones por KI
    this.container.querySelectorAll("button").forEach(btn => {
      const id = btn.id;
      let cost = 0;
      if (id === "btn-attack") cost = 8;
      if (id === "btn-charged") cost = 20;
      if (id === "btn-block") cost = 15;
      if (id === "btn-dodge") cost = 5;
      if (id.startsWith("btn-") && !["btn-menu", "btn-debug", "btn-recharge"].includes(id)) {
        // Asumir coste 40 para especiales
        if (id !== "btn-attack" && id !== "btn-charged" && id !== "btn-block" && id !== "btn-dodge") cost = 40;
      }
      
      btn.style.display = stats.playerKi >= cost ? "block" : "none";
    });

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
