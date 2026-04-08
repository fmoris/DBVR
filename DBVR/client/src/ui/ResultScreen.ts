// ResultScreen.ts
// Pantalla de resultado al final del combate (victoria o derrota)
// Muestra estadisticas del combate y opciones para reiniciar o volver al menu

export interface CombatStats {
  playerNP: number;
  enemyNP: number;
  playerKi: number;
  winner: "player" | "enemy";
  combatDurationSeconds: number;
}

type ResultCallback = "restart" | "menu";
type ResultActionCallback = (action: ResultCallback) => void;

export class ResultScreen {
  private overlay: HTMLDivElement;
  private callbacks: ResultActionCallback[] = [];
  private visible = false;

  constructor(parent: HTMLElement) {
    this.overlay = document.createElement("div");
    this.overlay.id = "result-screen";
    this.overlay.style.cssText = `
      position:fixed;
      top:0; left:0;
      width:100%; height:100%;
      z-index:200;
      display:none;
      align-items:center;
      justify-content:center;
      font-family:var(--font-body, sans-serif);
      background:rgba(0,0,0,0.88);
      pointer-events:auto;
    `;
    parent.appendChild(this.overlay);
  }

  show(stats: CombatStats): void {
    if (this.visible) return;
    this.visible = true;
    this.render(stats);
    this.overlay.style.display = "flex";

    // Animacion de entrada
    this.overlay.style.opacity = "0";
    this.overlay.style.transition = "opacity 0.6s ease";
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.overlay.style.opacity = "1";
      });
    });
  }

  hide(): void {
    this.visible = false;
    this.overlay.style.display = "none";
    this.overlay.innerHTML = "";
  }

  onAction(callback: ResultActionCallback): void {
    this.callbacks.push(callback);
  }

  private render(stats: CombatStats): void {
    const isVictory = stats.winner === "player";
    const titleText = isVictory ? "VICTORIA" : "DERROTA";
    const titleColor = isVictory ? "#00ff88" : "#ff4444";
    const titleGlow = isVictory ? "#00ff88" : "#ff2222";
    const subtitle = isVictory
      ? "Tu poder supera al del enemigo"
      : "El enemigo fue demasiado poderoso";

    const npDiff = Math.abs(stats.playerNP - stats.enemyNP).toFixed(0);
    const duration = this.formatDuration(stats.combatDurationSeconds);

    // Calcular rango de combate
    const rank = this.getCombatRank(stats);

    this.overlay.innerHTML = `
      <div style="
        max-width:520px; width:90%; text-align:center;
        background:linear-gradient(180deg,#0a0a1a 0%,#050510 100%);
        border:2px solid ${titleColor}44;
        border-radius:12px; padding:40px 32px;
        box-shadow:0 0 60px ${titleGlow}22, inset 0 0 40px rgba(0,0,0,0.5);
      ">
        <!-- Titulo principal -->
        <div style="
          font-size:52px; font-weight:bold; letter-spacing:8px;
          font-family:var(--font-saiyan);
          color:${titleColor}; text-shadow:0 0 30px ${titleGlow};
          margin-bottom:8px; animation:pulse 1.5s ease-in-out infinite;
        ">${titleText}</div>

        <div style="
          font-size:13px; letter-spacing:3px; color:#aaa;
          margin-bottom:32px;
        ">${subtitle}</div>

        <!-- Rango de combate -->
        <div style="
          font-size:28px; font-weight:bold; letter-spacing:4px;
          color:${rank.color}; text-shadow:0 0 15px ${rank.color};
          margin-bottom:4px;
        ">${rank.label}</div>
        <div style="font-size:11px; letter-spacing:2px; color:#666; margin-bottom:28px;">
          RANGO DE COMBATE
        </div>

        <!-- Separador -->
        <div style="
          width:100%; height:1px;
          background:linear-gradient(90deg,transparent,${titleColor}44,transparent);
          margin-bottom:24px;
        "></div>

        <!-- Estadisticas -->
        <div style="
          display:grid; grid-template-columns:1fr 1fr;
          gap:16px; margin-bottom:28px; text-align:left;
        ">
          ${this.statBlock("Tu NP Final", `${stats.playerNP.toFixed(0)}%`, isVictory ? "#00ff88" : "#ff8888")}
          ${this.statBlock("NP del Enemigo", `${stats.enemyNP.toFixed(0)}%`, isVictory ? "#ff4444" : "#ff8800")}
          ${this.statBlock("Diferencia de NP", `${npDiff} pts`, "#ffcc00")}
          ${this.statBlock("Duracion", duration, "#00aaff")}
          ${this.statBlock("KI Restante", `${stats.playerKi.toFixed(0)} / 100`, "#cc44ff")}
          ${this.statBlock("Resultado", isVictory ? "VICTORIA" : "DERROTA", titleColor)}
        </div>

        <!-- Separador -->
        <div style="
          width:100%; height:1px;
          background:linear-gradient(90deg,transparent,${titleColor}44,transparent);
          margin-bottom:24px;
        "></div>

        <!-- Botones -->
        <div style="display:flex; gap:16px; justify-content:center; flex-wrap:wrap;">
          <button id="btn-restart" style="
            padding:14px 40px;
            background:linear-gradient(135deg,#003366,#0055cc);
            border:2px solid #0099ff; border-radius:6px; color:#00ccff;
            font-size:14px; font-family:var(--font-body); font-weight:700;
            letter-spacing:3px; cursor:pointer; text-transform:uppercase;
            box-shadow:0 0 20px rgba(0,150,255,0.4);
            transition:all 0.2s;
          ">Reiniciar</button>
          <button id="btn-menu" style="
            padding:14px 40px; background:transparent;
            border:1px solid #334455; border-radius:6px; color:#556677;
            font-size:14px; font-family:var(--font-body);
            letter-spacing:3px; cursor:pointer; text-transform:uppercase;
            transition:all 0.2s;
          ">Menu</button>
        </div>

        <!-- Tip de voz -->
        <div style="
          margin-top:20px; font-size:10px; letter-spacing:2px; color:#334455;
        ">
          Di "KAMEHAMEHA" o "FINAL FLASH" para activar ataques especiales por voz
        </div>
      </div>

      <style>
        @keyframes pulse {
          0%, 100% { opacity:1; text-shadow:0 0 30px ${titleGlow}; }
          50% { opacity:0.8; text-shadow:0 0 50px ${titleGlow}, 0 0 80px ${titleGlow}44; }
        }
        #btn-restart:hover {
          background:linear-gradient(135deg,#004488,#0066dd) !important;
          box-shadow:0 0 30px rgba(0,150,255,0.6) !important;
          transform:translateY(-2px);
        }
        #btn-menu:hover {
          color:#aabbcc !important;
          border-color:#556677 !important;
        }
      </style>
    `;

    // Eventos
    const restartBtn = this.overlay.querySelector("#btn-restart");
    const menuBtn = this.overlay.querySelector("#btn-menu");

    restartBtn?.addEventListener("click", () => {
      this.hide();
      this.callbacks.forEach((cb) => cb("restart"));
    });
    menuBtn?.addEventListener("click", () => {
      this.hide();
      this.callbacks.forEach((cb) => cb("menu"));
    });
  }

  private statBlock(label: string, value: string, color: string): string {
    return `
      <div style="
        background:rgba(255,255,255,0.03); border:1px solid #1a1a2a;
        border-radius:6px; padding:12px 16px;
      ">
        <div style="font-size:10px; letter-spacing:2px; color:#556677; margin-bottom:4px;">
          ${label.toUpperCase()}
        </div>
        <div style="font-size:18px; font-weight:bold; color:${color}; letter-spacing:2px;">
          ${value}
        </div>
      </div>
    `;
  }

  private getCombatRank(stats: CombatStats): { label: string; color: string } {
    if (!stats.winner || stats.winner === "enemy") {
      return { label: "DERROTADO", color: "#ff4444" };
    }
    const np = stats.playerNP;
    const ki = stats.playerKi;
    if (np >= 80 && ki >= 60) return { label: "LEGENDARIO", color: "#ffffff" };
    if (np >= 65) return { label: "ELITE", color: "#ff8800" };
    if (np >= 50) return { label: "GUERRERO", color: "#ffcc00" };
    if (np >= 35) return { label: "LUCHADOR", color: "#00ff88" };
    return { label: "NOVATO", color: "#00aaff" };
  }

  private formatDuration(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return m > 0 ? `${m}m ${s}s` : `${s}s`;
  }

  dispose(): void {
    this.overlay.remove();
    this.callbacks = [];
  }
}
