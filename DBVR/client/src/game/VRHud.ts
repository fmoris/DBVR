/**
 * VRHud.ts
 * HUD 3D world-space para Meta Quest 3 usando @babylonjs/gui.
 *
 * DOM Overlay NO funciona en immersive-vr — el navegador ignora todo HTML.
 * La única solución es crear planos 3D con AdvancedDynamicTexture.
 *
 * NOTA: Los paneles están posicionados en el MUNDO (no adjuntos a la cámara XR)
 * para que permanezcan fijos en el espacio mientras el jugador mira alrededor.
 *
 * Layout (fijo en el mundo):
 *   - Panel jugador    (−0.55, 1.5, 1.0):   barras NP/KI del jugador
 *   - Panel enemigo    (+0.55, 1.5, 1.0):   barras NP/KI del enemigo
 *   - Panel ataques    (0, 2.0, 0.8):       botones de ataque (arriba)
 *   - Panel defensas   (0, 1.0, 0.8):       botones de defensa (abajo)
 *   - Panel estado     (0, 1.5, 0.6):       bullet time / alertas (centro)
 *   - Panel debug      (+1.2, 1.5, 0.5):    hand tracking debug (derecha)
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
import powersConfig from "../models/powers.json";
import gokuConfig from "../models/goku.json";

// ─── Helpers de color/rango (duplicados de HUD.ts para no crear dependencia) ──

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

// ─── Clase principal ──────────────────────────────────────────────────────────

export class VRHud {
  private scene: Scene;
  private combat: CombatSystem;

  // Meshes de los paneles
  private playerPanel!: Mesh;
  private enemyPanel!: Mesh;
  private attackPanel!: Mesh;
  private defensePanel!: Mesh;
  private statusPanel!: Mesh;
  private debugPanel!: Mesh;

  // ADTs
  private playerADT!: AdvancedDynamicTexture;
  private enemyADT!: AdvancedDynamicTexture;
  private attackADT!: AdvancedDynamicTexture;
  private defenseADT!: AdvancedDynamicTexture;
  private statusADT!: AdvancedDynamicTexture;
  private debugADT!: AdvancedDynamicTexture;

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

  // Debug panel controls
  private debugLeftHandText!: TextBlock;
  private debugRightHandText!: TextBlock;
  private debugGestureText!: TextBlock;
  private debugStatusText!: TextBlock;

  // Estado del HUD dinámico
  private currentHudType: "normal" | "defense" | "melee" | null = null;
  private attackRow: StackPanel | null = null;
  private defenseRow: StackPanel | null = null;
  private attackTitle: TextBlock | null = null;
  private defenseTitle: TextBlock | null = null;
  private toastTimeout: any = null;

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
    this.buildAttackPanel();
    this.buildDefensePanel();
    this.buildStatusPanel();
    this.buildDebugPanel();
  }

  /** Panel izquierdo — stats del jugador */
  private buildPlayerPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-player", 0.52, 0.35, 512);
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

    // Barra KI
    const kiGroup = this.makeBarGroup(bg, "KI", 42, "#cc44ff");
    this.playerKIBar = kiGroup.fill;
    this.playerKIText = kiGroup.valueText;

    // Rango NP o Rango General
    const rankText = new TextBlock("p-rank", "NORMAL");
    rankText.color = "#00ff88";
    rankText.fontSize = 20;
    rankText.heightInPixels = 28;
    rankText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    rankText.paddingLeftInPixels = 14;
    rankText.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    rankText.top = "110px";
    bg.addControl(rankText);
    this.playerNPRank = rankText;
  }

  /** Panel derecho — stats del enemigo */
  private buildEnemyPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-enemy", 0.52, 0.35, 512);
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

    const kiGroup = this.makeBarGroup(bg, "KI", 42, "#ff6600");
    this.enemyKIBar = kiGroup.fill;
    this.enemyKIText = kiGroup.valueText;

    const rankText = new TextBlock("e-rank", "NORMAL");
    rankText.color = "#ff8800";
    rankText.fontSize = 20;
    rankText.heightInPixels = 28;
    rankText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    rankText.paddingLeftInPixels = 14;
    rankText.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    rankText.top = "110px";
    bg.addControl(rankText);
    this.enemyNPRank = rankText;
  }

  /** Panel superior — botones de ATAQUE */
  private buildAttackPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-attack", 0.90, 0.18, 1024);
    this.attackPanel = mesh;
    this.attackADT = adt;

    const bg = this.makePanelBg(adt, "rgba(20,5,0,0.85)", "#aa4400");

    // Título
    const title = new TextBlock("atk-title", "⚔ ATAQUES");
    title.color = "#ff8800";
    title.fontSize = 22;
    title.fontStyle = "bold";
    title.heightInPixels = 28;
    title.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    title.top = "8px";
    bg.addControl(title);

    // Fila de botones en horizontal (contenedor dinámico)
    const row = new StackPanel("attack-row");
    row.isVertical = false;
    row.width = "100%";
    row.height = "70%";
    row.spacing = 10;
    bg.addControl(row);
    this.attackRow = row;
    this.attackTitle = title;
  }

  /** Panel inferior — botones de DEFENSA */
  private buildDefensePanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-defense", 0.70, 0.18, 1024);
    this.defensePanel = mesh;
    this.defenseADT = adt;

    const bg = this.makePanelBg(adt, "rgba(0,20,10,0.85)", "#00aa44");

    // Título
    const title = new TextBlock("def-title", "🛡 DEFENSAS");
    title.color = "#00ff88";
    title.fontSize = 22;
    title.fontStyle = "bold";
    title.heightInPixels = 28;
    title.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    title.top = "8px";
    bg.addControl(title);

    // Fila de botones en horizontal (contenedor dinámico)
    const row = new StackPanel("defense-row");
    row.isVertical = false;
    row.width = "100%";
    row.height = "70%";
    row.spacing = 12;
    row.verticalAlignment = Control.VERTICAL_ALIGNMENT_BOTTOM;
    bg.addControl(row);
    this.defenseRow = row;
    this.defenseTitle = title;
  }

  /** Panel de debug para hand tracking — posición fija a la derecha */
  private buildDebugPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-debug", 0.55, 0.45, 1024);
    this.debugPanel = mesh;
    this.debugADT = adt;

    const bg = this.makePanelBg(adt, "rgba(10,10,20,0.92)", "#4444aa");

    // Título
    const title = new TextBlock("dbg-title", "🔍 HAND TRACKING DEBUG");
    title.color = "#8888ff";
    title.fontSize = 18;
    title.fontStyle = "bold";
    title.heightInPixels = 24;
    title.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    title.top = "8px";
    bg.addControl(title);

    // Contenedor para texto
    const stack = new StackPanel("dbg-stack");
    stack.isVertical = true;
    stack.width = "94%";
    stack.height = "85%";
    stack.top = "30px";
    stack.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    stack.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    bg.addControl(stack);

    // Estado general
    this.debugStatusText = new TextBlock("dbg-status", "Esperando manos...");
    this.debugStatusText.color = "#ffff00";
    this.debugStatusText.fontSize = 16;
    this.debugStatusText.fontStyle = "bold";
    this.debugStatusText.heightInPixels = 22;
    this.debugStatusText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    stack.addControl(this.debugStatusText);

    // Separador
    const sep1 = new Rectangle("sep1");
    sep1.width = "100%";
    sep1.height = "2px";
    sep1.background = "#333366";
    sep1.thickness = 0;
    sep1.paddingTop = "4px";
    sep1.paddingBottom = "4px";
    stack.addControl(sep1);

    // Mano izquierda
    const leftTitle = new TextBlock("left-title", "🤚 MANO IZQUIERDA:");
    leftTitle.color = "#00ccff";
    leftTitle.fontSize = 14;
    leftTitle.heightInPixels = 18;
    leftTitle.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    stack.addControl(leftTitle);

    this.debugLeftHandText = new TextBlock("dbg-left", "No detectada");
    this.debugLeftHandText.color = "#aabbcc";
    this.debugLeftHandText.fontSize = 12;
    this.debugLeftHandText.heightInPixels = 60;
    this.debugLeftHandText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    this.debugLeftHandText.textWrapping = true;
    stack.addControl(this.debugLeftHandText);

    // Separador
    const sep2 = new Rectangle("sep2");
    sep2.width = "100%";
    sep2.height = "2px";
    sep2.background = "#333366";
    sep2.thickness = 0;
    sep2.paddingTop = "4px";
    sep2.paddingBottom = "4px";
    stack.addControl(sep2);

    // Mano derecha
    const rightTitle = new TextBlock("right-title", "🤚 MANO DERECHA:");
    rightTitle.color = "#ff8800";
    rightTitle.fontSize = 14;
    rightTitle.heightInPixels = 18;
    rightTitle.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    stack.addControl(rightTitle);

    this.debugRightHandText = new TextBlock("dbg-right", "No detectada");
    this.debugRightHandText.color = "#aabbcc";
    this.debugRightHandText.fontSize = 12;
    this.debugRightHandText.heightInPixels = 60;
    this.debugRightHandText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    this.debugRightHandText.textWrapping = true;
    stack.addControl(this.debugRightHandText);

    // Separador
    const sep3 = new Rectangle("sep3");
    sep3.width = "100%";
    sep3.height = "2px";
    sep3.background = "#333366";
    sep3.thickness = 0;
    sep3.paddingTop = "4px";
    sep3.paddingBottom = "4px";
    stack.addControl(sep3);

    // Gesto detectado
    const gestureTitle = new TextBlock("gesture-title", "👆 GESTO DETECTADO:");
    gestureTitle.color = "#ffcc00";
    gestureTitle.fontSize = 14;
    gestureTitle.heightInPixels = 18;
    gestureTitle.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    stack.addControl(gestureTitle);

    this.debugGestureText = new TextBlock("dbg-gesture", "NINGUNO");
    this.debugGestureText.color = "#ffffff";
    this.debugGestureText.fontSize = 16;
    this.debugGestureText.fontStyle = "bold";
    this.debugGestureText.heightInPixels = 24;
    this.debugGestureText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    stack.addControl(this.debugGestureText);
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
    bg.background = "rgba(0,0,0,0.5)";
    bg.thickness = 0;
    bg.isVisible = false; // Oculto por defecto
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
    lbl.color = "#00ccff";
    lbl.fontSize = 16;
    lbl.fontStyle = "bold";
    lbl.heightInPixels = 22;
    lbl.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    lbl.paddingLeftInPixels = 14;
    lbl.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    lbl.top = `${BASE_TOP + topOffset}px`;
    parent.addControl(lbl);

    // Valor numérico (AHORA ES VISIBLE)
    const val = new TextBlock(`${label}-val`, "100"); 
    val.isVisible = true; 
    val.color = "white";
    val.fontSize = 18;
    val.fontStyle = "bold";
    val.heightInPixels = 22;
    val.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
    val.paddingRightInPixels = 14;
    val.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    val.top = `${BASE_TOP + topOffset}px`;
    parent.addControl(val);

    // Fondo de la barra
    const barBg = new Rectangle(`${label}-bar-bg`);
    barBg.width = "90%";
    barBg.heightInPixels = 14;
    barBg.cornerRadius = 4;
    barBg.background = "rgba(0,0,0,0.5)";
    barBg.thickness = 1;
    barBg.color = "rgba(0,200,255,0.3)";
    barBg.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    barBg.top = `${BASE_TOP + topOffset + 26}px`;
    parent.addControl(barBg);

    // Relleno de la barra
    const fill = new Rectangle(`${label}-fill`);
    fill.width = "100%";
    fill.heightInPixels = 14;
    fill.cornerRadius = 4;
    fill.background = fillColor;
    fill.thickness = 0;
    fill.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    barBg.addControl(fill);

    return { fill, valueText: val };
  }

  /** Botón de acción compacto para el panel central */
  private makeActionBtn(
    parent: StackPanel,
    key: string,
    label: string,
    color: string,
    bgColor: string,
    action: () => void,
    cost: number = 0
  ): void {
    const btn = Button.CreateSimpleButton(`btn-${label}`, `[${key}]\n${label}`);
    (btn as any).kiCost = cost; // Metadata
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

  // ─── Posicionamiento Gaze-Locked ──────────────────────────────────────────

  /**
   * Posiciona los paneles de forma Fija en el mundo frente al jugador.
   * Remueve el anclaje a la cabeza para prevenir Motion Sickness.
   */
  attachToXRCamera(xrCamera: any): void {
    // Desligar completamente de la cámara para mantener el HUD fijo en el mundo
    [this.playerPanel, this.enemyPanel, this.attackPanel, this.defensePanel, this.statusPanel, this.debugPanel].forEach(m => {
      m.parent = null;
    });

    const camPos = xrCamera.globalPosition;
    
    // Calcular el vector de visión "hacia adelante" del jugador omitiendo el pitch (Y=0)
    const forward = xrCamera.getDirection(new Vector3(0, 0, 1));
    forward.y = 0;
    if (forward.lengthSquared() === 0) forward.z = 1;
    forward.normalize();
    
    // Derecha es producto cruz entre Y y Forward
    const right = Vector3.Cross(Vector3.Up(), forward).normalize();
    const up = Vector3.Up();

    // Función auxiliar para plantar paneles alrededor del jugador
    const place = (mesh: any, xLocal: number, yLocal: number, zLocal: number) => {
        mesh.position = camPos
            .add(right.scale(xLocal))
            .add(up.scale(yLocal))
            .add(forward.scale(zLocal));
            
        // El HUD mira hacia el jugador (el frente por defecto de un Plano en BJS es +Z local o -Z según ADT)
        // Con lookAt, el panel girará para enfocarse en la cabeza del jugador
        mesh.lookAt(camPos, Math.PI);
    };

    // Radios de distancia local (X, Y relativo al visor, Z)
    place(this.playerPanel, -0.85,  0.40, 1.3);
    place(this.enemyPanel,   0.85,  0.40, 1.3);
    
    place(this.attackPanel,  0.00,  0.75, 1.4);
    place(this.defensePanel, 0.00, -0.60, 1.4);
    
    place(this.statusPanel,  0.00,  0.35, 1.25);
    
    // Debug panel
    place(this.debugPanel,  -0.90, -0.40, 1.3);

    this.show();
  }

  /** Desenlaza el HUD de la cámara */
  detachFromCamera(): void {
    [this.playerPanel, this.enemyPanel, this.attackPanel, this.defensePanel, this.statusPanel, this.debugPanel].forEach(m => {
      m.parent = null;
    });
    this.hide();
  }

  // ─── Visibilidad ────────────────────────────────────────────────────────────

  show(): void {
    this.visible = true;
    [this.playerPanel, this.enemyPanel, this.attackPanel, this.defensePanel, this.statusPanel, this.debugPanel].forEach(m => {
      m.setEnabled(true);
    });
    this.update(this.combat.getStats());
  }

  hide(): void {
    this.visible = false;
    [this.playerPanel, this.enemyPanel, this.attackPanel, this.defensePanel, this.statusPanel, this.debugPanel].forEach(m => {
      m.setEnabled(false);
    });
  }

  isVisible(): boolean {
    return this.visible;
  }

  // ─── Actualización en tiempo real ───────────────────────────────────────────

  update(stats: GameStats): void {
    if (!this.visible) return;

    // Determinar qué layout mostrar
    let targetType: "normal" | "defense" | "melee" = "normal";
    if (stats.enemyAttacking) {
      targetType = "defense";
    } else if (stats.combatState === "melee") {
      targetType = "melee";
    }

    // Si cambió el contexto, refrescar los botones
    if (this.currentHudType !== targetType) {
      this.refreshActions(targetType, stats);
      this.currentHudType = targetType;
    }

    // ── Jugador ──
    const pNP = stats.playerNP || 10000;
    const pNPPct = (pNP / 100000); // ADT utiliza 0-1 para widths habitualmente o píxeles. En rectángulos es píxeles o porcentaje.
    const pKI = Math.max(0, Math.min(100, (stats.playerKi / stats.maxKi) * 100));
    
    this.playerNPBar.width = `${Math.min(100, pNPPct * 100)}%`;
    this.playerNPBar.background = getNPColor(pNP);
    this.playerNPText.text = pNP.toLocaleString(); 
    this.playerNPRank.text = getNPRange(pNP);
    this.playerNPRank.color = getNPColor(pNP);
    this.playerKIBar.width = `${pKI}%`;
    this.playerKIText.text = `${stats.playerKi.toFixed(0)}`;

    // ── Enemigo ──
    const eNP = stats.enemyNP || 10000;
    const eNPPct = (eNP / 100000);
    const eKI = Math.max(0, Math.min(100, (stats.enemyKi / stats.enemyMaxKi) * 100));
    
    this.enemyNPBar.width = `${Math.min(100, eNPPct * 100)}%`;
    this.enemyNPBar.background = getNPColor(eNP);
    this.enemyNPText.text = eNP.toLocaleString();
    this.enemyNPRank.text = getNPRange(eNP);
    this.enemyNPRank.color = getNPColor(eNP);
    this.enemyKIBar.width = `${eKI}%`;
    this.enemyKIText.text = `${stats.enemyKi.toFixed(0)}`;

    this.updateStatus(stats);
    this.updateActionKiCounter(stats);
    this.filterActionsByKi(stats);
  }

  /** Oculta botones si no hay KI suficiente */
  private filterActionsByKi(stats: GameStats): void {
    if (!this.attackRow || !this.defenseRow) return;
    
    const allBtns = [...this.attackRow.getDescendants(), ...this.defenseRow.getDescendants()];
    for (const ctrl of allBtns) {
      if (ctrl instanceof Button) {
        const cost = (ctrl as any).kiCost || 0;
        ctrl.isVisible = stats.playerKi >= cost;
      }
    }
  }

  /** Muestra el KI actual en una esquina de los paneles de acción */
  private updateActionKiCounter(stats: GameStats): void {
    const kiText = `KI: ${stats.playerKi.toFixed(0)}`;
    const kiColor = stats.playerKi > 20 ? "#00ccff" : "#ff4444";
    
    // Podríamos añadir un pequeño indicador flotante o simplemente actualizar el título
    if (this.attackTitle && this.currentHudType === "normal") {
      this.attackTitle.text = `⚔ ATAQUES  [${kiText}]`;
      this.attackTitle.color = kiColor;
    }
    if (this.defenseTitle && this.currentHudType === "defense") {
      this.defenseTitle.color = kiColor;
    }
  }

  /** Refresca los botones de acción según el contexto */
  private refreshActions(type: "normal" | "defense" | "melee", stats: any): void {
    if (!this.attackRow || !this.defenseRow) return;

    // Limpiar filas
    this.attackRow.getDescendants().forEach(c => c.dispose());
    this.defenseRow.getDescendants().forEach(c => c.dispose());

    const c = this.combat;

    if (type === "normal") {
      this.attackPanel.isVisible = true;
      this.defensePanel.isVisible = true;
      this.attackTitle!.text = "⚔ ATAQUES";
      this.defenseTitle!.text = "🛡 COMPLEMENTO";

      this.makeActionBtn(this.attackRow, "A", "Atacar", "#00ff88", "#003322", () => c.launchBasicAttack(), 8);
      this.makeActionBtn(this.attackRow, "W", "Cargar", "#ffcc00", "#332200", () => c.startChargedAttack(), 20);

      const allowedPowers = gokuConfig.transformations[0].powers || [];
      const powersDict = powersConfig as Record<string, any>;
      let kIdx = 1;
      for (const k of allowedPowers) {
        const d = powersDict[k];
        if (d && (d.type === "ofensiva" || d.type === "especial")) {
          const color = k === "kamehameha" ? "#00ccff" : "#ff4400";
          // Coste mínimo para especiales es 40
          this.makeActionBtn(this.attackRow, `${kIdx}`, d.name || k, color, "#331100", () => c.triggerSpecial(k), 40);
          kIdx++;
        }
      }

      // Complementos (en el panel de defensa)
      this.makeActionBtn(this.defenseRow, "R", "Recargar KI", "#cc44ff", "#220033", () => c.rechargeKi(), 0);
    } 
    else if (type === "defense") {
      this.attackPanel.isVisible = false; // Ocultar ataques si estamos bajo fuego
      this.defensePanel.isVisible = true;
      this.defenseTitle!.text = `⚠️ ¡CUIDADO! VIENE: ${stats.enemyAttackName}`;
      
      const attType = stats.enemyAttackType || "basic";

      if (attType === "basic") {
        this.makeActionBtn(this.defenseRow, "S", "Bloqueo Seguro", "#00ff88", "#002211", () => c.activateBlock(), 15);
        this.makeActionBtn(this.defenseRow, "D", "Esquiva",        "#66ccff", "#001122", () => c.activateDodge(), 5);
      } else {
        // Ataques especiales o cargados
        this.makeActionBtn(this.defenseRow, "S", "Desvío Preciso", "#ff8800", "#331100", () => c.activateDeflect(), 10);
        this.makeActionBtn(this.defenseRow, "K", "Choque de Poder", "#ffcc00", "#332200", () => c.triggerPowerClash(), 50);
        this.makeActionBtn(this.defenseRow, "D", "Esquiva Crucial", "#ffffff", "#333333", () => c.activateDodge(), 5);
      }
    }
    else if (type === "melee") {
      this.attackPanel.isVisible = true;
      this.defensePanel.isVisible = false;
      this.attackTitle!.text = "👊 PUÑO DE HIERRO (MELEE)";
      
      this.makeActionBtn(this.attackRow, "A", "Rápido",   "#00ff88", "#002211", () => c.meleeAttack("light"), 0);
      this.makeActionBtn(this.attackRow, "S", "Múltiple", "#66ccff", "#001122", () => c.meleeAttack("heavy"), 0);
      this.makeActionBtn(this.attackRow, "D", "Cargado",  "#ffcc00", "#332200", () => c.meleeAttack("charged"), 0);
      this.makeActionBtn(this.attackRow, "W", "Vanish",   "#cc44ff", "#220033", () => c.meleeAttack("vanish"), 10);
    }
  }

  private updateStatus(stats: any): void {
    if (stats.isSlowMotion) {
      this.statusText.text = "⚡ BULLET TIME";
      this.statusText.color = "#cc44ff";
      this.statusBg.background = "rgba(80,0,120,0.75)";
      this.statusBg.thickness = 2;
      this.statusBg.color = "#cc44ff";
    } else if (stats.enemyAttackName) {
      // Mostrar el nombre del ataque o acción enemiga (ej: "Recargando KI") 
      // incluso si no es un ataque directo que requiera defensa.
      const isAttacking = stats.enemyAttacking;
      this.statusText.text = (isAttacking ? "⚠ " : "ℹ ") + stats.enemyAttackName;
      this.statusText.color = isAttacking ? "#ff2222" : "#00ff88";
      this.statusBg.background = isAttacking ? "rgba(80,0,0,0.75)" : "rgba(0,60,20,0.75)";
      this.statusBg.thickness = 2;
      this.statusBg.color = isAttacking ? "#ff2222" : "#00ff88";
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

  // ─── Debug Hand Tracking ──────────────────────────────────────────────────────

  /**
   * Actualiza la información de debug de hand tracking.
   * Llamar esto desde el game loop con los datos actuales de las manos.
   */
  updateHandTrackingDebug(
    leftHandActive: boolean,
    rightHandActive: boolean,
    leftJoints: { wrist?: { x: number; y: number; z: number }; indexTip?: { x: number; y: number; z: number } } | null,
    rightJoints: { wrist?: { x: number; y: number; z: number }; indexTip?: { x: number; y: number; z: number } } | null,
    gesture: string,
    apiSource: string
  ): void {
    if (!this.visible) return;

    // Status general
    const handsDetected = leftHandActive || rightHandActive;
    if (handsDetected) {
      this.debugStatusText.text = `✅ Manos detectadas (${apiSource})`;
      this.debugStatusText.color = "#00ff00";
    } else {
      this.debugStatusText.text = `⏳ Esperando manos... (${apiSource})`;
      this.debugStatusText.color = "#ffff00";
    }

    // Mano izquierda
    if (leftHandActive && leftJoints) {
      const wrist = leftJoints.wrist;
      const index = leftJoints.indexTip;
      this.debugLeftHandText.text =
        `Muñeca: ${wrist ? `X:${wrist.x.toFixed(2)} Y:${wrist.y.toFixed(2)} Z:${wrist.z.toFixed(2)}` : "N/A"}\n` +
        `Índice: ${index ? `X:${index.x.toFixed(2)} Y:${index.y.toFixed(2)} Z:${index.z.toFixed(2)}` : "N/A"}`;
    } else {
      this.debugLeftHandText.text = "No detectada";
    }

    // Mano derecha
    if (rightHandActive && rightJoints) {
      const wrist = rightJoints.wrist;
      const index = rightJoints.indexTip;
      this.debugRightHandText.text =
        `Muñeca: ${wrist ? `X:${wrist.x.toFixed(2)} Y:${wrist.y.toFixed(2)} Z:${wrist.z.toFixed(2)}` : "N/A"}\n` +
        `Índice: ${index ? `X:${index.x.toFixed(2)} Y:${index.y.toFixed(2)} Z:${index.z.toFixed(2)}` : "N/A"}`;
    } else {
      this.debugRightHandText.text = "No detectada";
    }

    // Gesto
    this.debugGestureText.text = gesture || "NINGUNO";
    // Color según el gesto
    const gestureColors: Record<string, string> = {
      "ATTACKING": "#ff4444",
      "CHARGING": "#ffcc00",
      "BLOCKING": "#44ff44",
      "RECHARGING": "#cc44ff",
      "RECHARGE_PREP": "#ff8800",
      "PARRYING": "#44ccff",
      "IDLE": "#aaaaaa",
    };
    this.debugGestureText.color = gestureColors[gesture] || "#ffffff";
  }

  showToast(message: string, color: string = "white", duration: number = 2000): void {
    if (!this.statusText || !this.statusBg) return;
    
    this.statusText.text = message;
    this.statusText.color = color;
    this.statusBg.isVisible = true;
    
    if (this.toastTimeout) clearTimeout(this.toastTimeout);
    
    if (duration > 0) {
      this.toastTimeout = setTimeout(() => {
        this.hideToast();
      }, duration);
    }
  }

  hideToast(): void {
    if (this.statusText) this.statusText.text = "";
    if (this.statusBg) this.statusBg.isVisible = false;
    if (this.toastTimeout) clearTimeout(this.toastTimeout);
  }

  // ─── Dispose ────────────────────────────────────────────────────────────────

  dispose(): void {
    this.playerADT.dispose();
    this.enemyADT.dispose();
    this.attackADT.dispose();
    this.defenseADT.dispose();
    this.statusADT.dispose();
    this.debugADT.dispose();
    this.playerPanel.dispose();
    this.enemyPanel.dispose();
    this.attackPanel.dispose();
    this.defensePanel.dispose();
    this.statusPanel.dispose();
    this.debugPanel.dispose();
  }
}
