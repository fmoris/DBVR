/**
 * VRHud.ts
 * HUD 3D world-space para Meta Quest 3 usando @babylonjs/gui.
 *
 * DOM Overlay NO funciona en immersive-vr — el navegador ignora todo HTML.
 * La única solución es crear planos 3D con AdvancedDynamicTexture y
 * adjuntarlos a la cámara XR para que sigan la cabeza del jugador.
 *
 * Layout:
 *   - Panel izquierdo  (−0.55, −0.25, 1.1): barras NP/KI del jugador + rango
 *   - Panel derecho    (+0.55, −0.25, 1.1): barras NP/KI del enemigo
 *   - Panel central    (0, −0.42, 1.1):     botones de acción (7 botones)
 *   - Panel estado     (0, +0.30, 1.1):     bullet time / alerta de ataque enemigo
 */

import {
  Scene,
  Mesh,
  MeshBuilder,
  Vector3,
  StandardMaterial,
} from "@babylonjs/core";
import {
  AdvancedDynamicTexture,
  TextBlock,
  Rectangle,
  StackPanel,
  Button,
  Control,
} from "@babylonjs/gui";
import { CombatSystem, GameStats } from "./CombatSystem";

// ─── Helpers de color/rango (duplicados de HUD.ts para no crear dependencia) ──

function getNPColor(np: number): string {
  if (np >= 91) return "#ffffff";
  if (np >= 76) return "#ff8800";
  if (np >= 51) return "#ffcc00";
  if (np >= 21) return "#00ff88";
  return "#4499ff";
}

function getNPRange(np: number): string {
  if (np >= 91) return "TRASCENDENTE";
  if (np >= 76) return "DOMINANTE";
  if (np >= 51) return "ELEVADO";
  if (np >= 21) return "NORMAL";
  return "DEBILITADO";
}

// ─── Clase principal ──────────────────────────────────────────────────────────

export class VRHud {
  private scene: Scene;
  private combat: CombatSystem;

  // Meshes de los paneles
  private playerPanel!: Mesh;
  private enemyPanel!: Mesh;
  private actionPanel!: Mesh;
  private statusPanel!: Mesh;

  // ADTs
  private playerADT!: AdvancedDynamicTexture;
  private enemyADT!: AdvancedDynamicTexture;
  private actionADT!: AdvancedDynamicTexture;
  private statusADT!: AdvancedDynamicTexture;

  // Referencias a controles que se actualizan en tiempo real
  private playerNPBar!: Rectangle;
  private playerNPText!: TextBlock;
  private playerNPRank!: TextBlock;
  private playerKIBar!: Rectangle;
  private playerKIText!: TextBlock;

  private enemyNPBar!: Rectangle;
  private enemyNPText!: TextBlock;
  private enemyNPRank!: TextBlock;
  private enemyKIBar!: Rectangle;
  private enemyKIText!: TextBlock;

  private statusText!: TextBlock;
  private statusBg!: Rectangle;

  private visible = false;

  constructor(scene: Scene, combat: CombatSystem) {
    this.scene = scene;
    this.combat = combat;
    this.buildPanels();
    this.hide(); // oculto hasta que se entre en VR
    // Suscribirse a cambios de stats
    this.combat.onStatsChange((stats) => this.update(stats));
  }

  // ─── Construcción de paneles ────────────────────────────────────────────────

  private buildPanels(): void {
    this.buildPlayerPanel();
    this.buildEnemyPanel();
    this.buildActionPanel();
    this.buildStatusPanel();
  }

  /** Panel izquierdo — stats del jugador */
  private buildPlayerPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-player", 0.52, 0.28, 512);
    this.playerPanel = mesh;
    this.playerADT = adt;

    const bg = this.makePanelBg(adt, "rgba(0,10,30,0.88)", "#0055aa");

    // Título
    const title = new TextBlock("p-title", "JUGADOR");
    title.color = "#00ccff";
    title.fontSize = 26;
    title.fontStyle = "bold";
    title.heightInPixels = 36;
    title.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    title.paddingLeftInPixels = 14;
    bg.addControl(title);
    title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    title.top = "10px";

    // Barra NP
    const npGroup = this.makeBarGroup(bg, "NP", 0, "#00ccff");
    this.playerNPBar = npGroup.fill;
    this.playerNPText = npGroup.valueText;

    // Rango NP
    const rankText = new TextBlock("p-rank", "NORMAL");
    rankText.color = "#00ff88";
    rankText.fontSize = 20;
    rankText.heightInPixels = 28;
    rankText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    rankText.paddingLeftInPixels = 14;
    rankText.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    rankText.top = "90px";
    bg.addControl(rankText);
    this.playerNPRank = rankText;

    // Barra KI
    const kiGroup = this.makeBarGroup(bg, "KI", 120, "#cc44ff");
    this.playerKIBar = kiGroup.fill;
    this.playerKIText = kiGroup.valueText;
  }

  /** Panel derecho — stats del enemigo */
  private buildEnemyPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-enemy", 0.52, 0.28, 512);
    this.enemyPanel = mesh;
    this.enemyADT = adt;

    const bg = this.makePanelBg(adt, "rgba(30,5,5,0.88)", "#aa1100");

    const title = new TextBlock("e-title", "ENEMIGO");
    title.color = "#ff4444";
    title.fontSize = 26;
    title.fontStyle = "bold";
    title.heightInPixels = 36;
    title.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    title.paddingLeftInPixels = 14;
    title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    title.top = "10px";
    bg.addControl(title);

    const npGroup = this.makeBarGroup(bg, "NP", 0, "#ff4444");
    this.enemyNPBar = npGroup.fill;
    this.enemyNPText = npGroup.valueText;

    const rankText = new TextBlock("e-rank", "NORMAL");
    rankText.color = "#ff8800";
    rankText.fontSize = 20;
    rankText.heightInPixels = 28;
    rankText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    rankText.paddingLeftInPixels = 14;
    rankText.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    rankText.top = "90px";
    bg.addControl(rankText);
    this.enemyNPRank = rankText;

    const kiGroup = this.makeBarGroup(bg, "KI", 120, "#ff6600");
    this.enemyKIBar = kiGroup.fill;
    this.enemyKIText = kiGroup.valueText;
  }

  /** Panel central inferior — botones de acción */
  private buildActionPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-actions", 1.10, 0.22, 1024);
    this.actionPanel = mesh;
    this.actionADT = adt;

    const bg = this.makePanelBg(adt, "rgba(0,5,20,0.82)", "#003366");

    // Fila de botones en horizontal
    const row = new StackPanel("action-row");
    row.isVertical = false;
    row.width = "100%";
    row.height = "100%";
    row.spacing = 8;
    row.paddingLeftInPixels = 12;
    row.paddingRightInPixels = 12;
    row.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
    bg.addControl(row);

    const c = this.combat;

    // Ataques
    this.makeActionBtn(row, "A", "Atacar",      "#00ff88", "#003322", () => c.launchBasicAttack());
    this.makeActionBtn(row, "W", "Cargar",       "#ffcc00", "#332200", () => c.startChargedAttack());
    this.makeActionBtn(row, "1", "Kame",         "#00ccff", "#001133", () => c.kamehamehaStep(1));
    this.makeActionBtn(row, "2", "F.Flash",      "#ff8800", "#331100", () => c.finalFlashStep(1));
    // Separador visual
    const sep = new Rectangle("sep");
    sep.width = "2px";
    sep.height = "70%";
    sep.background = "#334455";
    sep.thickness = 0;
    row.addControl(sep);
    // Defensas
    this.makeActionBtn(row, "S", "Bloquear",     "#66ffaa", "#002211", () => c.activateBlock());
    this.makeActionBtn(row, "D", "Esquivar",     "#66ccff", "#001122", () => c.activateDodge());
    this.makeActionBtn(row, "R", "Recargar",     "#cc44ff", "#220033", () => c.rechargeKi());
  }

  /** Panel de estado — bullet time, alerta de ataque */
  private buildStatusPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-status", 0.70, 0.10, 512);
    this.statusPanel = mesh;
    this.statusADT = adt;

    const bg = new Rectangle("status-bg");
    bg.width = "100%";
    bg.height = "100%";
    bg.cornerRadius = 12;
    bg.background = "rgba(0,0,0,0)";
    bg.thickness = 0;
    adt.addControl(bg);
    this.statusBg = bg;

    const txt = new TextBlock("status-txt", "");
    txt.color = "white";
    txt.fontSize = 28;
    txt.fontStyle = "bold";
    txt.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    txt.textVerticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
    bg.addControl(txt);
    this.statusText = txt;
  }

  // ─── Helpers de construcción ────────────────────────────────────────────────

  /**
   * Crea un plano 3D con su AdvancedDynamicTexture.
   * El plano NO tiene posición aquí — se asigna al adjuntar a la cámara.
   */
  private createPanel(
    name: string,
    widthM: number,
    heightM: number,
    resolution: number
  ): { mesh: Mesh; adt: AdvancedDynamicTexture } {
    const mesh = MeshBuilder.CreatePlane(name, {
      width: widthM,
      height: heightM,
      sideOrientation: Mesh.DOUBLESIDE,
    }, this.scene);
    mesh.isPickable = true;

    // Material con backFaceCulling desactivado para evitar que quede invisible
    const mat = new StandardMaterial(name + "-mat", this.scene);
    mat.backFaceCulling = false;
    mat.disableLighting = true;
    mesh.material = mat;

    const texW = Math.round(widthM * resolution);
    const texH = Math.round(heightM * resolution);
    const adt = AdvancedDynamicTexture.CreateForMesh(mesh, texW, texH);
    adt.background = "transparent";

    return { mesh, adt };
  }

  /** Fondo redondeado con borde para un panel */
  private makePanelBg(
    adt: AdvancedDynamicTexture,
    bg: string,
    borderColor: string
  ): Rectangle {
    const rect = new Rectangle("panel-bg");
    rect.width = "100%";
    rect.height = "100%";
    rect.cornerRadius = 16;
    rect.background = bg;
    rect.color = borderColor;
    rect.thickness = 2;
    adt.addControl(rect);
    return rect;
  }

  /**
   * Crea un grupo etiqueta + barra de progreso + valor numérico.
   * topOffset: posición vertical desde el borde superior del panel (px).
   */
  private makeBarGroup(
    parent: Rectangle,
    label: string,
    topOffset: number,
    fillColor: string
  ): { fill: Rectangle; valueText: TextBlock } {
    const BASE_TOP = 48; // debajo del título

    // Etiqueta
    const lbl = new TextBlock(`${label}-lbl`, label);
    lbl.color = "#aabbcc";
    lbl.fontSize = 18;
    lbl.heightInPixels = 22;
    lbl.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    lbl.paddingLeftInPixels = 14;
    lbl.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    lbl.top = `${BASE_TOP + topOffset}px`;
    parent.addControl(lbl);

    // Fondo de la barra
    const barBg = new Rectangle(`${label}-bar-bg`);
    barBg.width = "88%";
    barBg.heightInPixels = 18;
    barBg.cornerRadius = 6;
    barBg.background = "#0a1a2a";
    barBg.thickness = 1;
    barBg.color = "#223344";
    barBg.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    barBg.paddingLeftInPixels = 14;
    barBg.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    barBg.top = `${BASE_TOP + topOffset + 24}px`;
    parent.addControl(barBg);

    // Relleno de la barra
    const fill = new Rectangle(`${label}-fill`);
    fill.width = "100%";
    fill.heightInPixels = 18;
    fill.cornerRadius = 6;
    fill.background = fillColor;
    fill.thickness = 0;
    fill.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    barBg.addControl(fill);

    // Valor numérico
    const val = new TextBlock(`${label}-val`, "100%");
    val.color = "white";
    val.fontSize = 16;
    val.heightInPixels = 20;
    val.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
    val.paddingRightInPixels = 14;
    val.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    val.top = `${BASE_TOP + topOffset}px`;
    parent.addControl(val);

    return { fill, valueText: val };
  }

  /** Botón de acción compacto para el panel central */
  private makeActionBtn(
    parent: StackPanel,
    key: string,
    label: string,
    color: string,
    bgColor: string,
    action: () => void
  ): void {
    const btn = Button.CreateSimpleButton(`btn-${label}`, `[${key}]\n${label}`);
    btn.width = "118px";
    btn.heightInPixels = 88;
    btn.color = color;
    btn.background = bgColor;
    btn.cornerRadius = 10;
    btn.fontSize = 20;
    btn.thickness = 2;
    (btn as any).fontStyle = "bold";
    btn.onPointerClickObservable.add(action);
    // Hover visual
    btn.onPointerEnterObservable.add(() => {
      btn.background = color + "33"; // color con alpha bajo
      btn.thickness = 3;
    });
    btn.onPointerOutObservable.add(() => {
      btn.background = bgColor;
      btn.thickness = 2;
    });
    parent.addControl(btn);
  }

  // ─── Adjuntar a cámara XR ───────────────────────────────────────────────────

  /**
   * Llama este método cuando la sesión XR inicia y tienes la cámara XR.
   * Adjunta todos los paneles a la cámara para que sigan la cabeza del jugador.
   */
  attachToXRCamera(xrCamera: any): void {
    // Panel jugador — esquina inferior izquierda del campo de visión
    this.playerPanel.parent = xrCamera;
    this.playerPanel.position = new Vector3(-0.52, -0.22, 1.05);
    this.playerPanel.rotation = new Vector3(0, 0, 0);

    // Panel enemigo — esquina inferior derecha
    this.enemyPanel.parent = xrCamera;
    this.enemyPanel.position = new Vector3(0.52, -0.22, 1.05);
    this.enemyPanel.rotation = new Vector3(0, 0, 0);

    // Panel de acciones — centro inferior
    this.actionPanel.parent = xrCamera;
    this.actionPanel.position = new Vector3(0, -0.44, 1.05);
    this.actionPanel.rotation = new Vector3(0, 0, 0);

    // Panel de estado — centro superior
    this.statusPanel.parent = xrCamera;
    this.statusPanel.position = new Vector3(0, 0.32, 1.05);
    this.statusPanel.rotation = new Vector3(0, 0, 0);

    this.show();
  }

  /** Desancla los paneles de la cámara (para volver a desktop) */
  detachFromCamera(): void {
    [this.playerPanel, this.enemyPanel, this.actionPanel, this.statusPanel].forEach(m => {
      m.parent = null;
    });
    this.hide();
  }

  // ─── Visibilidad ────────────────────────────────────────────────────────────

  show(): void {
    this.visible = true;
    [this.playerPanel, this.enemyPanel, this.actionPanel, this.statusPanel].forEach(m => {
      m.setEnabled(true);
    });
    this.update(this.combat.getStats());
  }

  hide(): void {
    this.visible = false;
    [this.playerPanel, this.enemyPanel, this.actionPanel, this.statusPanel].forEach(m => {
      m.setEnabled(false);
    });
  }

  isVisible(): boolean {
    return this.visible;
  }

  // ─── Actualización en tiempo real ───────────────────────────────────────────

  update(stats: GameStats): void {
    if (!this.visible) return;

    // ── Jugador ──
    const pNP = Math.max(0, Math.min(100, stats.playerNP));
    const pKI = Math.max(0, Math.min(100, (stats.playerKi / stats.maxKi) * 100));
    this.playerNPBar.width = `${pNP}%`;
    this.playerNPBar.background = getNPColor(pNP);
    this.playerNPText.text = `${pNP.toFixed(0)}%`;
    this.playerNPRank.text = getNPRange(pNP);
    this.playerNPRank.color = getNPColor(pNP);
    this.playerKIBar.width = `${pKI}%`;
    this.playerKIBar.background = pKI > 30 ? "#cc44ff" : "#ff2222";
    this.playerKIText.text = `${stats.playerKi.toFixed(0)}`;

    // ── Enemigo ──
    const eNP = Math.max(0, Math.min(100, stats.enemyNP));
    const eKI = Math.max(0, Math.min(100, (stats.enemyKi / stats.enemyMaxKi) * 100));
    this.enemyNPBar.width = `${eNP}%`;
    this.enemyNPBar.background = "#ff4444";
    this.enemyNPText.text = `${eNP.toFixed(0)}%`;
    this.enemyNPRank.text = getNPRange(eNP);
    this.enemyNPRank.color = getNPColor(eNP);
    this.enemyKIBar.width = `${eKI}%`;
    this.enemyKIBar.background = "#ff6600";
    this.enemyKIText.text = `${stats.enemyKi.toFixed(0)}`;

    // ── Estado / alertas ──
    if (stats.isSlowMotion) {
      this.statusText.text = "⚡ BULLET TIME";
      this.statusText.color = "#cc44ff";
      this.statusBg.background = "rgba(80,0,120,0.75)";
      this.statusBg.thickness = 2;
      this.statusBg.color = "#cc44ff";
    } else if (stats.enemyAttacking) {
      this.statusText.text = `⚠ ${stats.enemyAttackName || "ATAQUE ENEMIGO"}`;
      this.statusText.color = "#ff2222";
      this.statusBg.background = "rgba(80,0,0,0.75)";
      this.statusBg.thickness = 2;
      this.statusBg.color = "#ff2222";
    } else if (stats.combatState === "charging" || stats.combatState === "charging_special") {
      const pct = Math.min(100, (stats.chargeTime / 8) * 100);
      this.statusText.text = `⚡ CARGANDO ${pct.toFixed(0)}%`;
      this.statusText.color = "#ffcc00";
      this.statusBg.background = "rgba(60,40,0,0.75)";
      this.statusBg.thickness = 2;
      this.statusBg.color = "#ffcc00";
    } else {
      this.statusText.text = "";
      this.statusBg.background = "rgba(0,0,0,0)";
      this.statusBg.thickness = 0;
    }
  }

  // ─── Dispose ────────────────────────────────────────────────────────────────

  dispose(): void {
    this.playerADT.dispose();
    this.enemyADT.dispose();
    this.actionADT.dispose();
    this.statusADT.dispose();
    this.playerPanel.dispose();
    this.enemyPanel.dispose();
    this.actionPanel.dispose();
    this.statusPanel.dispose();
  }
}
