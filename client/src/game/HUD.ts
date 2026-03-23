import { CombatSystem, GameStats, CombatState } from "./CombatSystem";

const STATE_LABELS: Record<CombatState, string> = {
  neutral: "Neutral",
  charging: "Cargando KI...",
  attacking: "Atacando",
  defending: "Bloqueando",
  slowMotion: "Camara Lenta",
  hit: "Impacto",
};

const STATE_COLORS: Record<CombatState, string> = {
  neutral: "#00ff88",
  charging: "#ffcc00",
  attacking: "#ff6600",
  defending: "#00aaff",
  slowMotion: "#cc44ff",
  hit: "#ff2222",
};

export class HUD {
  private container: HTMLDivElement;
  private elements: Record<string, HTMLElement> = {};

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
    // Borde de camara lenta
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

    // HUD inferior
    const bottom = document.createElement("div");
    bottom.style.cssText = `
      position:absolute; bottom:40px; left:50%; transform:translateX(-50%);
      display:flex; gap:60px; align-items:flex-end;
    `;
    this.container.appendChild(bottom);

    // Barras del jugador
    bottom.appendChild(this.buildBars("player", "Tu KI", "#00ff88", "Salud", "#ff4444"));

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
      <button id="btn-block" style="padding:8px 20px;background:linear-gradient(135deg,#003322,#006644);
        border:1px solid #00ff88;border-radius:4px;color:#00ff88;font-size:11px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:2px;
        cursor:pointer;text-transform:uppercase;">
        [S] Bloquear
      </button>
      <button id="btn-recharge" style="padding:8px 20px;background:linear-gradient(135deg,#330033,#660066);
        border:1px solid #cc44ff;border-radius:4px;color:#cc44ff;font-size:11px;
        font-family:'Courier New',monospace;font-weight:bold;letter-spacing:2px;
        cursor:pointer;text-transform:uppercase;box-shadow:0 0 8px rgba(180,60,255,0.3);">
        [R] Recargar KI
      </button>
    `;
    bottom.appendChild(controls);

    // Barras del enemigo
    bottom.appendChild(this.buildBars("enemy", "KI Enemigo", "#ff4444", "Salud", "#ff8800"));

    // Eventos de botones
    controls.querySelector("#btn-attack")!.addEventListener("click", () => this.combat.launchAttack());
    controls.querySelector("#btn-block")!.addEventListener("click", () => this.combat.activateBlock());
    controls.querySelector("#btn-recharge")!.addEventListener("click", () => this.combat.rechargeKi());
  }

  private buildBars(prefix: string, label1: string, color1: string, label2: string, color2: string): HTMLDivElement {
    const wrap = document.createElement("div");
    wrap.style.cssText = `display:flex; flex-direction:column; gap:8px; align-items:center;`;
    wrap.innerHTML = `
      <span style="color:#aaa;font-size:10px;letter-spacing:2px;text-transform:uppercase;">${label1}</span>
      <div style="width:180px;height:12px;background:rgba(0,0,0,0.7);border:1px solid ${color1};
        border-radius:3px;overflow:hidden;box-shadow:0 0 8px ${color1}44;">
        <div id="${prefix}-ki-bar" style="height:100%;width:100%;
          background:linear-gradient(90deg,${color1}88,${color1});
          transition:width 0.15s ease;box-shadow:0 0 6px ${color1};"></div>
      </div>
      <span style="color:#aaa;font-size:10px;letter-spacing:2px;text-transform:uppercase;">${label2}</span>
      <div style="width:180px;height:8px;background:rgba(0,0,0,0.7);border:1px solid ${color2};
        border-radius:3px;overflow:hidden;">
        <div id="${prefix}-hp-bar" style="height:100%;width:100%;
          background:linear-gradient(90deg,${color2}88,${color2});
          transition:width 0.15s ease;"></div>
      </div>
    `;
    this.container.appendChild(wrap); // temporal, se mueve al bottom
    return wrap;
  }

  private update(stats: GameStats): void {
    const color = STATE_COLORS[stats.combatState];
    const label = this.elements["stateLabel"];
    label.textContent = STATE_LABELS[stats.combatState] + (stats.isSlowMotion ? " · CAMARA LENTA" : "");
    label.style.color = color;
    label.style.textShadow = `0 0 12px ${color}`;
    label.style.border = `1px solid ${color}44`;

    this.elements["slowBorder"].style.display = stats.isSlowMotion ? "block" : "none";

    const debug = this.elements["debug"];
    debug.innerHTML = `
      KI: ${stats.playerKi.toFixed(0)}/100<br>
      Salud: ${stats.playerHealth.toFixed(0)}/100<br>
      Estado: ${stats.combatState}<br>
      <span style="margin-top:6px;display:block;font-size:10px;color:#00aa55;">A=Ataque · S=Bloqueo · R=Recarga</span>
    `;

    const playerKiBar = this.container.querySelector("#player-ki-bar") as HTMLElement;
    const playerHpBar = this.container.querySelector("#player-hp-bar") as HTMLElement;
    const enemyKiBar = this.container.querySelector("#enemy-ki-bar") as HTMLElement;
    const enemyHpBar = this.container.querySelector("#enemy-hp-bar") as HTMLElement;

    if (playerKiBar) playerKiBar.style.width = `${stats.playerKi}%`;
    if (playerHpBar) playerHpBar.style.width = `${stats.playerHealth}%`;
    if (enemyKiBar) enemyKiBar.style.width = `${stats.enemyKi}%`;
    if (enemyHpBar) enemyHpBar.style.width = `${stats.enemyHealth}%`;
  }
}
