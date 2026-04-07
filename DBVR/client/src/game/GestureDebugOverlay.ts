/**
 * GestureDebugOverlay
 * Panel de debug en pantalla para diagnosticar el hand tracking.
 * Sincronizado con el GestureSkillSystem (GSS).
 */

import { Scene, MeshBuilder, Mesh, Vector3 } from "@babylonjs/core";
import { AdvancedDynamicTexture, TextBlock, Control, Rectangle } from "@babylonjs/gui";

const GESTURE_COLORS: Record<string, string> = {
  "idle": "#aaaaaa",
  "charging": "#ffcc00",
  "charging_special": "#ff8800",
  "blocking": "#44ff44",
  "recharging": "#cc44ff",
  "attack": "#ff4444",
  "ki_blast": "#00e5ff",
  "kamehameha": "#00e5ff",
  "galick_gun": "#cc44ff",
  "final_flash": "#ffff00",
  "genkidama": "#00ffff"
};

export class GestureDebugOverlay {
  private panel: HTMLDivElement;
  private visible = false;
  private frameId = 0;

  // VR 3D GUI
  private vrPlane: Mesh;
  private vrAdt: AdvancedDynamicTexture;
  private vrText: TextBlock;
  private xrCamera: any = null;

  private handTrackingActive = false;
  private currentGesture: string = "idle";
  private gestureLog: string[] = [];
  private handApiSource = "desconocido";

  constructor(private parent: HTMLElement, private scene: Scene) {
    // ─── 1. DOM OVERLAY (Desktop) ───
    this.panel = document.createElement("div");
    this.panel.style.cssText = `
      position: fixed;
      top: 60px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(0, 0, 0, 0.92);
      border: 2px solid rgba(0, 200, 255, 0.8);
      border-radius: 8px;
      padding: 12px 18px;
      font-family: monospace;
      font-size: 13px;
      color: #00ccff;
      min-width: 340px;
      max-width: 460px;
      pointer-events: none;
      z-index: 9999;
      display: none;
      line-height: 1.8;
    `;
    this.parent.appendChild(this.panel);

    // ─── 2. VR OVERLAY (Quest 3) ───
    this.vrPlane = MeshBuilder.CreatePlane("vrDebugPlane", { width: 1.5, height: 1.0 }, this.scene);
    this.vrPlane.isVisible = false;
    
    this.vrAdt = AdvancedDynamicTexture.CreateForMesh(this.vrPlane);
    
    const bg = new Rectangle("debugBg");
    bg.background = "rgba(0, 30, 50, 0.85)";
    bg.thickness = 2;
    bg.color = "#00c8ff";
    bg.cornerRadius = 10;
    this.vrAdt.addControl(bg);

    this.vrText = new TextBlock("vrDebugText");
    this.vrText.color = "cyan";
    this.vrText.fontSize = 24;
    this.vrText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    this.vrText.textVerticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    this.vrText.paddingTop = "20px";
    this.vrText.paddingLeft = "20px";
    this.vrText.fontFamily = "monospace";
    bg.addControl(this.vrText);

    window.addEventListener("keydown", (e) => {
      if (e.key.toLowerCase() === "g") this.toggle();
    });
  }

  attachToXRCamera(camera: any): void {
    this.xrCamera = camera;
    this.vrPlane.parent = camera;
    this.vrPlane.position = new Vector3(0.65, 0.0, 1.2);
    this.vrPlane.rotation = new Vector3(0, 0.25, 0);
    if (this.visible) this.vrPlane.isVisible = true;
  }

  detachFromCamera(): void {
    this.xrCamera = null;
    this.vrPlane.parent = null;
    this.vrPlane.isVisible = false;
  }

  toggle(): void {
    this.visible = !this.visible;
    this.syncVisibility();
  }

  private syncVisibility(): void {
    const isXR = this.xrCamera !== null;
    this.panel.style.display = (this.visible && !isXR) ? "block" : "none";
    this.vrPlane.isVisible = this.visible && isXR;
    
    if (this.visible) {
        this.renderLoop();
    } else {
        cancelAnimationFrame(this.frameId);
    }
  }

  update(opts: {
    handTrackingActive: boolean;
    gesture: string;
    handApiSource?: string;
    success?: boolean;
    leftJoints?: any; // Ignored for now to clean up legacy
    rightJoints?: any;
  }): void {
    if (opts.handApiSource) this.handApiSource = opts.handApiSource;
    this.handTrackingActive = opts.handTrackingActive;

    const gestureChanged = opts.gesture !== this.currentGesture;
    if (gestureChanged || opts.success) {
      const ts = new Date().toLocaleTimeString("es", { hour12: false });
      const status = opts.success ? "OK" : "State";
      const entry = `[${ts}] ${opts.gesture} (${status})`;
      
      this.gestureLog.unshift(entry);
      if (this.gestureLog.length > 15) this.gestureLog.pop();
    }
    this.currentGesture = opts.gesture;
  }

  private renderLoop(): void {
    if (!this.visible) return;
    this.render();
    this.frameId = requestAnimationFrame(() => this.renderLoop());
  }

  private render(): void {
    // ─── DOM UPDATE ───
    if (this.panel.style.display !== "none") {
      const htStatus = this.handTrackingActive ? `<span style="color:#00ff88">● ACTIVO</span>` : `<span style="color:#ff4444">● SIN DATOS</span>`;
      const color = GESTURE_COLORS[this.currentGesture] || "#00ccff";
      const gestureLabel = `<span style="color:${color};font-weight:bold">${this.currentGesture}</span>`;
      const logRows = this.gestureLog.map(l => `<div style="color:#aaa;font-size:10px">${l}</div>`).join("");

      this.panel.innerHTML = `
        <div style="display:flex;justify-content:space-between;margin-bottom:6px;border-bottom:1px solid #0a2a4a;padding-bottom:4px;">
          <span style="letter-spacing:2px;font-size:10px;color:#0088aa">GSS DEBUG</span>
          <span style="font-size:10px">[G] toggle</span>
        </div>
        <div>Hand Tracking: ${htStatus}</div>
        <div style="font-size:10px;color:#aaa">Source: <span style="color:#ffcc44">${this.handApiSource}</span></div>
        <div style="margin-top:4px">Gesto/Estado: ${gestureLabel}</div>
        <div style="border-top:1px solid #0a2a4a;margin-top:8px;padding-top:4px;font-size:10px;color:#0088aa">Log:</div>
        <div style="max-height:150px;overflow-y:hidden">${logRows}</div>
      `;
    }

    // ─── VR TEXT UPDATE ───
    if (this.vrPlane.isVisible) {
      const status = this.handTrackingActive ? "ACTIVO" : "SIN DATOS";
      const vrLogs = this.gestureLog.slice(0, 10).join("\n");
      
      this.vrText.text = `=== GSS DEBUG ===\n` +
          `Status: ${status}\n` +
          `API: ${this.handApiSource}\n` +
          `Gesture: ${this.currentGesture}\n\n` +
          `Log:\n${vrLogs}`;
    }
  }

  dispose(): void {
    cancelAnimationFrame(this.frameId);
    this.panel.remove();
    this.vrPlane.dispose();
  }
}
