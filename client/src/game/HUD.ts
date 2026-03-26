import { CombatSystem, GameStats, CombatState } from "./CombatSystem";

const STATE_LABELS: Record<CombatState, string> = {
  neutral: "Neutral",
  charging: "Cargando...",
  charging_special: "Carga Especial",
  attacking: "Atacando",
  defending: "Defendiendo",
  slowMotion: "Cámara Lenta",
  hit: "¡Impacto!",
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
  if (np >= 91) return "#ffffff";  // Trascendente - blanco brillante
  if (np >= 76) return "#ff8800";  // Dominante - naranja
  if (np >= 51) return "#ffcc00";  // Elevado - amarillo
  if (np >= 21) return "#00ff88";  // Normal - verde
  return "#0088ff";                 // Debilitado - azul
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

  constructor(private parent: HTMLElement, private combat: CombatSystem) {
    this.container = document.createElement("div");
    this.container.style.cssText = `
      position:absolute; inset:0; pointer-events:none;
      font-family:'Courier New',monospace; user-select:none; display:none;
    `;
    this.parent.appendChild(this.container);
    this.buildDOM();
    this.combat.onStatsChange((stats) => this.update(stats));
  }

  show(): void {
    this.container.style.display = "block";
    this.update(this.combat.getStats());
  }

  private buildDOM(): void {
    // Borde de cámara lenta
    const slowBorder = document.createElement("div");
    slowBorder.id = "slow-border";
    slowBorder.style.cssText = `
      position:absolute; inset:0; border:3px solid rgba(180,60,255,0.4);
      box-shadow:inset 0 0 60px rgba(180,60,255,0.15);
      pointer-events:none; display:none;
    `;
    this.container.appendChild(slowBorder);
    this.elements["slowBorder"] = slowBorder;

    // Indicador de estado
    const stateLabel = document.createElement("div");
    stateLabel.id = "state-label";
    stateLabel.style.cssText = `
      position:absolute; top:20px; left:50%; transform:translateX(-50%);
      font-size:13px; font-weight:bold; letter-spacing:3px; text-transform:uppercase;
      background:rgba(0,0,0,0.6); padding:4px 16px; border-radius:4px;
    `;
    this.container.appendChild(stateLabel);
    this.elements["stateLabel"] = stateLabel;

    // Debug info
    const debug = document.createElement("div");
    debug.style.cssText = `
      position:absolute; top:20px; left:20px; color:#00ff88; font-size:11px;
      background:rgba(0,0,0,0.75); padding:8px 12px; border-radius:4px;
      border:1px solid #00ff8844; line-height:1.8;
    `;
    this.container.appendChild(debug);
    this.elements["debug"] = debug;

    // Indicador de carga
    const chargeIndicator = document.createElement("div");
    chargeIndicator.id = "charge-indicator";
    chargeIndicator.style.cssText = `
      position:absolute; top:60px; left:50%; transform:translateX(-50%);
      font-size:12px; font-weight:bold; letter-spacing:2px;
      background:rgba(0,0,0,0.7); padding:6px 16px; border-radius:4px;
      display:none;
    `;
    this.container.appendChild(chargeIndicator);
    this.elements["chargeIndicator"] = chargeIndicator;

    // Popup de NP
    const npPopup = document.createElement("div");
    npPopup.id = "np-popup";
    npPopup.style.cssText = `
      position:absolute; top:50%; left:50%; transform:translate(-50%, -50%);
      font-size:28px; font-weight:bold; letter-spacing:4px;
      opacity:0; pointer-events:none; transition:opacity 0.3s, transform 0.3s;
      text-shadow:0 0 20px currentColor;
    `;
    this.container.appendChild(npPopup);
    this.elements["npPopup"] = npPopup;

    // HUD inferior
    const bottom = document.createElement("div");
    bottom.style.cssText = `
      position:absolute; bottom:40px; left:50%; transform:translateX(-50%);
      display:flex; gap:60px; align-items:flex-end;
    `;
    this.container.appendChild(bottom);

    // Barras del jugador
    bottom.appendChild(this.buildPlayerBars());

    // Controles
    const controls = document.createElement("div");
    controls.style.cssText = `display:flex; flex-direction:column; gap:6px; align-items:center; pointer-events:auto;`;
    controls.innerHTML = `
      <button id="btn-attack" style="padding:8px 20px;background:linear-gradient(135deg,#003366,#0066cc);
        border:1px solid #0099ff;border-radius:4px;color:#00ccff;font-size:11px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:2px;
        cursor:pointer;text-transform:uppercase;box-shadow:0 0 10px rgba(0,150,255,0.4);">
        [A] Atacar
      </button>
      <button id="btn-charged" style="padding:8px 20px;background:linear-gradient(135deg,#663300,#cc6600);
        border:1px solid #ff9900;border-radius:4px;color:#ff9900;font-size:11px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:2px;
        cursor:pointer;text-transform:uppercase;box-shadow:0 0 10px rgba(255,150,0,0.4);">
        [W] Cargar
      </button>
      <button id="btn-kamehameha" style="padding:6px 16px;background:linear-gradient(135deg,#001133,#003366);
        border:1px solid #00aaff;border-radius:4px;color:#00aaff;font-size:10px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:1px;
        cursor:pointer;text-transform:uppercase;">
        [1] Kamehameha
      </button>
      <button id="btn-finalflash" style="padding:6px 16px;background:linear-gradient(135deg,#332200,#664400);
        border:1px solid #ffaa00;border-radius:4px;color:#ffaa00;font-size:10px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:1px;
        cursor:pointer;text-transform:uppercase;">
        [2] Final Flash
      </button>
      <button id="btn-block" style="padding:8px 20px;background:linear-gradient(135deg,#003322,#006644);
        border:1px solid #00ff88;border-radius:4px;color:#00ff88;font-size:11px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:2px;
        cursor:pointer;text-transform:uppercase;">
        [S] Bloquear
      </button>
      <button id="btn-dodge" style="padding:6px 16px;background:linear-gradient(135deg,#002233,#004466);
        border:1px solid #66ccff;border-radius:4px;color:#66ccff;font-size:10px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:1px;
        cursor:pointer;text-transform:uppercase;">
        [D] Esquivar
      </button>
      <button id="btn-recharge" style="padding:8px 20px;background:linear-gradient(135deg,#330033,#660066);
        border:1px solid #cc44ff;border-radius:4px;color:#cc44ff;font-size:11px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:2px;
        cursor:pointer;text-transform:uppercase;box-shadow:0 0 8px rgba(180,60,255,0.3);">
        [R] Recargar
      </button>
    `;
    bottom.appendChild(controls);

    // Barras del enemigo
    bottom.appendChild(this.buildEnemyBars());

    // Eventos de botones
    const combat = this.combat;
    controls.querySelector("#btn-attack")!.addEventListener("click", () => combat.launchBasicAttack());
    controls.querySelector("#btn-charged")!.addEventListener("click", () => {
      if (combat.isInChargingState()) {
        combat.releaseChargedAttack();
      } else {
        combat.startChargedAttack();
      }
    });
    controls.querySelector("#btn-kamehameha")!.addEventListener("click", () => combat.kamehamehaStep(1));
    controls.querySelector("#btn-finalflash")!.addEventListener("click", () => combat.finalFlashStep(1));
    controls.querySelector("#btn-block")!.addEventListener("click", () => combat.activateBlock());
    controls.querySelector("#btn-dodge")!.addEventListener("click", () => combat.activateDodge());
    controls.querySelector("#btn-recharge")!.addEventListener("click", () => combat.rechargeKi());
  }

  private buildPlayerBars(): HTMLDivElement {
    const wrap = document.createElement("div");
    wrap.style.cssText = `display:flex; flex-direction:column; gap:8px; align-items:center; min-width:180px;`;
    wrap.innerHTML = `
      <span style="color:#aaa;font-size:10px;letter-spacing:2px;text-transform:uppercase;">Tu Nivel de Poder</span>
      <div style="width:180px;height:18px;background:rgba(0,0,0,0.7);border:1px solid #00ff88;
        border-radius:3px;overflow:hidden;box-shadow:0 0 8px #00ff8844;">
        <div id="player-np-bar" style="height:100%;width:50%;
          background:linear-gradient(90deg,#00ff8888,#00ff88);
          transition:width 0.15s ease;box-shadow:0 0 6px #00ff88;"></div>
      </div>
      <span id="player-np-label" style="color:#00ff88;font-size:11px;font-weight:bold;">NORMAL (50%)</span>
      <span style="color:#aaa;font-size:10px;letter-spacing:2px;text-transform:uppercase;margin-top:8px;">Tu KI</span>
      <div style="width:180px;height:12px;background:rgba(0,0,0,0.7);border:1px solid #00ccff;
        border-radius:3px;overflow:hidden;box-shadow:0 0 8px #00ccff44;">
        <div id="player-ki-bar" style="height:100%;width:100%;
          background:linear-gradient(90deg,#00ccff88,#00ccff);
          transition:width 0.15s ease;box-shadow:0 0 6px #00ccff;"></div>
      </div>
    `;
    return wrap;
  }

  private buildEnemyBars(): HTMLDivElement {
    const wrap = document.createElement("div");
    wrap.style.cssText = `display:flex; flex-direction:column; gap:8px; align-items:center; min-width:180px;`;
    wrap.innerHTML = `
      <span style="color:#aaa;font-size:10px;letter-spacing:2px;text-transform:uppercase;">Enemigo</span>
      <div style="width:180px;height:18px;background:rgba(0,0,0,0.7);border:1px solid #ff4444;
        border-radius:3px;overflow:hidden;box-shadow:0 0 8px #ff444444;">
        <div id="enemy-np-bar" style="height:100%;width:50%;
          background:linear-gradient(90deg,#ff444488,#ff4444);
          transition:width 0.15s ease;box-shadow:0 0 6px #ff4444;"></div>
      </div>
      <span id="enemy-np-label" style="color:#ff4444;font-size:11px;font-weight:bold;">NORMAL (50%)</span>
      <span style="color:#aaa;font-size:10px;letter-spacing:2px;text-transform:uppercase;margin-top:8px;">KI Enemigo</span>
      <div style="width:180px;height:12px;background:rgba(0,0,0,0.7);border:1px solid #ff8800;
        border-radius:3px;overflow:hidden;box-shadow:0 0 8px #ff880044;">
        <div id="enemy-ki-bar" style="height:100%;width:100%;
          background:linear-gradient(90deg,#ff880088,#ff8800);
          transition:width 0.15s ease;box-shadow:0 0 6px #ff8800;"></div>
      </div>
    `;
    return wrap;
  }

  private showNPPopup(amount: number, isPlayer: boolean): void {
    const popup = this.elements["npPopup"] as HTMLElement;
    const sign = amount >= 0 ? "+" : "";
    const color = amount >= 0 ? (isPlayer ? "#00ff88" : "#ff4444") : (isPlayer ? "#ff4444" : "#00ff88");
    
    popup.textContent = `${sign}${Math.abs(amount)} NP`;
    popup.style.color = color;
    popup.style.opacity = "1";
    popup.style.transform = "translate(-50%, -50%) scale(1.2)";
    
    if (this.npPopupTimeout) clearTimeout(this.npPopupTimeout);
    
    this.npPopupTimeout = window.setTimeout(() => {
      popup.style.opacity = "0";
      popup.style.transform = "translate(-50%, -70%) scale(1)";
    }, 1000);
  }

  private update(stats: GameStats): void {
    const color = STATE_COLORS[stats.combatState];
    const label = this.elements["stateLabel"];
    label.textContent = STATE_LABELS[stats.combatState];
    if (stats.isSlowMotion) label.textContent += " · CAMARA LENTA";
    if (stats.chargeTime > 0) label.textContent += ` (${stats.chargeTime.toFixed(1)}s)`;
    
    label.style.color = color;
    label.style.textShadow = `0 0 12px ${color}`;
    label.style.border = `1px solid ${color}44`;

    // Indicador de carga
    const chargeIndicator = this.elements["chargeIndicator"] as HTMLElement;
    if (stats.combatState === "charging" || stats.combatState === "charging_special") {
      chargeIndicator.style.display = "block";
      chargeIndicator.style.color = "#ffcc00";
      const specialName = stats.specialType === "kamehameha" ? "KAMEHAMEHA" : stats.specialType === "finalFlash" ? "FINAL FLASH" : "";
      const minTime = stats.specialType === "kamehameha" ? 2 : stats.specialType === "finalFlash" ? 3 : 0;
      const ready = stats.chargeTime >= minTime;
      chargeIndicator.style.color = ready ? "#00ff88" : "#ffcc00";
      chargeIndicator.innerHTML = specialName
        ? `${ready ? "✅" : "⏳"} ${specialName}: ${stats.chargeTime.toFixed(1)}s ${ready ? "— LISTO! Presiona de nuevo" : `(min ${minTime}s)`}`
        : `⏳ CARGANDO: ${stats.chargeTime.toFixed(1)}s`;
    } else if (stats.combatState === "attacking" && stats.currentAttack) {
      chargeIndicator.style.display = "block";
      chargeIndicator.style.color = "#ff6600";
      const attackName = stats.currentAttack.toUpperCase();
      chargeIndicator.innerHTML = `🔥 ${attackName}`;
    } else {
      chargeIndicator.style.display = "none";
    }

    this.elements["slowBorder"].style.display = stats.isSlowMotion ? "block" : "none";

    // Debug
    const debug = this.elements["debug"];
    debug.innerHTML = `
      Tu NP: ${stats.playerNP.toFixed(0)}% | KI: ${stats.playerKi.toFixed(0)}<br>
      Enemigo NP: ${stats.enemyNP.toFixed(0)}% | KI: ${stats.enemyKi.toFixed(0)}<br>
      Estado: ${stats.combatState}<br>
      <span style="margin-top:4px;display:block;font-size:9px;color:#888;">
        A=W+A=atacar | S=bloquear | D=esquivar | R=recargar | 1=Kamehameha | 2=Final Flash
      </span>
    `;

    // Barras de NP
    const playerNPBar = this.container.querySelector("#player-np-bar") as HTMLElement;
    const playerNPLabel = this.container.querySelector("#player-np-label") as HTMLElement;
    const enemyNPBar = this.container.querySelector("#enemy-np-bar") as HTMLElement;
    const enemyNPLabel = this.container.querySelector("#enemy-np-label") as HTMLElement;
    
    // KI bars
    const playerKiBar = this.container.querySelector("#player-ki-bar") as HTMLElement;
    const enemyKiBar = this.container.querySelector("#enemy-ki-bar") as HTMLElement;

    if (playerNPBar) {
      const npColor = getNPColor(stats.playerNP);
      playerNPBar.style.width = `${stats.playerNP}%`;
      playerNPBar.style.background = `linear-gradient(90deg,${npColor}88,${npColor})`;
      playerNPBar.style.boxShadow = `0 0 6px ${npColor}`;
    }
    if (playerNPLabel) {
      const npColor = getNPColor(stats.playerNP);
      playerNPLabel.textContent = `${getNPRange(stats.playerNP)} (${stats.playerNP.toFixed(0)}%)`;
      playerNPLabel.style.color = npColor;
      if (stats.playerNP >= 91) playerNPLabel.style.textShadow = `0 0 10px ${npColor}`;
    }
    if (enemyNPBar) {
      const npColor = getNPColor(stats.enemyNP);
      enemyNPBar.style.width = `${stats.enemyNP}%`;
      enemyNPBar.style.background = `linear-gradient(90deg,${npColor}88,${npColor})`;
      enemyNPBar.style.boxShadow = `0 0 6px ${npColor}`;
    }
    if (enemyNPLabel) {
      const npColor = getNPColor(stats.enemyNP);
      enemyNPLabel.textContent = `${getNPRange(stats.enemyNP)} (${stats.enemyNP.toFixed(0)}%)`;
      enemyNPLabel.style.color = npColor;
      if (stats.enemyNP >= 91) enemyNPLabel.style.textShadow = `0 0 10px ${npColor}`;
    }

    if (playerKiBar) playerKiBar.style.width = `${stats.playerKi}%`;
    if (enemyKiBar) enemyKiBar.style.width = `${stats.enemyKi}%`;
  }
}