/**
 * GestureDebugOverlay
 * Panel de debug en pantalla para diagnosticar el hand tracking en Meta Quest 3.
 * Muestra en tiempo real:
 *   - Estado del hand tracking (activo / sin datos)
 *   - Coordenadas de muñecas izquierda y derecha
 *   - Gesto detectado actualmente
 *   - Distancia entre muñecas
 *   - Velocidad de empuje (para gesto de ataque)
 * Toggle con tecla G (desktop) o botón [DBG] en el HUD.
 */

import { GestureType, HandJoints } from "./GestureRecognizer";

const GESTURE_COLORS: Record<GestureType, string> = {
  [GestureType.IDLE]:       "#888888",
  [GestureType.ATTACKING]:  "#ff6600",
  [GestureType.CHARGING]:   "#ffcc00",
  [GestureType.BLOCKING]:   "#00ff88",
  [GestureType.PARRYING]:   "#00ccff",
  [GestureType.RECHARGING]: "#cc44ff",
};

export class GestureDebugOverlay {
  private panel: HTMLDivElement;
  private visible = false;
  private frameId = 0;

  // Estado actualizado desde Game.ts
  private handTrackingActive = false;
  private leftJoints: HandJoints | null = null;
  private rightJoints: HandJoints | null = null;
  private currentGesture: GestureType = GestureType.IDLE;
  private prevLeftZ = 0;
  private prevRightZ = 0;
  private gestureLog: string[] = [];

  constructor(private parent: HTMLElement) {
    this.panel = document.createElement("div");
    this.panel.style.cssText = `
      position: absolute;
      top: 60px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(0, 0, 0, 0.82);
      border: 1.5px solid rgba(0, 200, 255, 0.5);
      border-radius: 8px;
      padding: 10px 16px;
      font-family: var(--font-body);
      font-size: 11px;
      color: #00ccff;
      min-width: 340px;
      max-width: 420px;
      pointer-events: none;
      z-index: 100;
      display: none;
      line-height: 1.6;
    `;
    this.parent.appendChild(this.panel);

    // Toggle con tecla G
    window.addEventListener("keydown", (e) => {
      if (e.key.toLowerCase() === "g") this.toggle();
    });
  }

  toggle(): void {
    this.visible = !this.visible;
    this.panel.style.display = this.visible ? "block" : "none";
    if (this.visible) this.renderLoop();
  }

  show(): void {
    this.visible = true;
    this.panel.style.display = "block";
    this.renderLoop();
  }

  hide(): void {
    this.visible = false;
    this.panel.style.display = "none";
    cancelAnimationFrame(this.frameId);
  }

  isVisible(): boolean { return this.visible; }

  // Llamado desde Game.ts cada frame con los datos actuales
  update(opts: {
    handTrackingActive: boolean;
    leftJoints: HandJoints | null;
    rightJoints: HandJoints | null;
    gesture: GestureType;
  }): void {
    // Guardar Z anterior para calcular velocidad de empuje
    this.prevLeftZ  = this.leftJoints?.wrist.z  ?? opts.leftJoints?.wrist.z  ?? 0;
    this.prevRightZ = this.rightJoints?.wrist.z ?? opts.rightJoints?.wrist.z ?? 0;

    this.handTrackingActive = opts.handTrackingActive;
    this.leftJoints         = opts.leftJoints;
    this.rightJoints        = opts.rightJoints;

    // Registrar cambios de gesto en el log
    if (opts.gesture !== this.currentGesture) {
      const ts = new Date().toLocaleTimeString("es", { hour12: false });
      this.gestureLog.unshift(`[${ts}] ${opts.gesture}`);
      if (this.gestureLog.length > 5) this.gestureLog.pop();
    }
    this.currentGesture = opts.gesture;
  }

  private renderLoop(): void {
    if (!this.visible) return;
    this.render();
    this.frameId = requestAnimationFrame(() => this.renderLoop());
  }

  private fmt(v: number): string {
    return v.toFixed(3).padStart(7);
  }

  private dist3(a: HandJoints["wrist"], b: HandJoints["wrist"]): number {
    const dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  private render(): void {
    const L = this.leftJoints;
    const R = this.rightJoints;

    const htStatus = this.handTrackingActive
      ? `<span style="color:#00ff88">● ACTIVO</span>`
      : `<span style="color:#ff4444">● SIN DATOS</span>`;

    const gestureColor = GESTURE_COLORS[this.currentGesture];
    const gestureLabel = `<span style="color:${gestureColor};font-weight:bold">${this.currentGesture}</span>`;

    const wristDist = L && R ? this.dist3(L.wrist, R.wrist).toFixed(3) : "---";
    const pushL  = L ? (this.prevLeftZ  - L.wrist.z).toFixed(3) : "---";
    const pushR  = R ? (this.prevRightZ - R.wrist.z).toFixed(3) : "---";

    const lRow = L
      ? `x:${this.fmt(L.wrist.x)} y:${this.fmt(L.wrist.y)} z:${this.fmt(L.wrist.z)}`
      : `<span style="color:#ff4444">sin datos</span>`;
    const rRow = R
      ? `x:${this.fmt(R.wrist.x)} y:${this.fmt(R.wrist.y)} z:${this.fmt(R.wrist.z)}`
      : `<span style="color:#ff4444">sin datos</span>`;

    const lIdx = L
      ? `x:${this.fmt(L.indexTip.x)} y:${this.fmt(L.indexTip.y)} z:${this.fmt(L.indexTip.z)}`
      : "---";
    const rIdx = R
      ? `x:${this.fmt(R.indexTip.x)} y:${this.fmt(R.indexTip.y)} z:${this.fmt(R.indexTip.z)}`
      : "---";

    const logRows = this.gestureLog.length
      ? this.gestureLog.map(l => `<div style="color:#aaa;font-size:10px">${l}</div>`).join("")
      : `<div style="color:#444">— sin cambios —</div>`;

    this.panel.innerHTML = `
      <div style="display:flex;justify-content:space-between;margin-bottom:6px;border-bottom:1px solid #0a2a4a;padding-bottom:4px;">
        <span style="letter-spacing:2px;font-size:10px;color:#0088aa">GESTURE DEBUG</span>
        <span style="font-size:10px">[G] toggle</span>
      </div>

      <div style="margin-bottom:4px">
        Hand Tracking: ${htStatus}
      </div>

      <div style="margin-bottom:6px">
        Gesto actual: ${gestureLabel}
      </div>

      <div style="display:grid;grid-template-columns:60px 1fr;gap:2px 8px;margin-bottom:6px;font-size:10px;">
        <span style="color:#0088aa">L.wrist</span><span>${lRow}</span>
        <span style="color:#ff8844">R.wrist</span><span>${rRow}</span>
        <span style="color:#0088aa">L.index</span><span>${lIdx}</span>
        <span style="color:#ff8844">R.index</span><span>${rIdx}</span>
        <span style="color:#aaa">dist</span><span>${wristDist} m</span>
        <span style="color:#aaa">push L/R</span><span>${pushL} / ${pushR}</span>
      </div>

      <div style="border-top:1px solid #0a2a4a;padding-top:4px;font-size:10px;color:#0088aa;margin-bottom:2px">
        Historial de gestos:
      </div>
      ${logRows}
    `;
  }

  dispose(): void {
    cancelAnimationFrame(this.frameId);
    this.panel.remove();
  }
}
