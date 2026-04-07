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
  Image,
  Ellipse,
  ScrollViewer,
} from "@babylonjs/gui";
import { CombatSystem, GameStats } from "./CombatSystem";
import { InputManager } from "./InputManager";
import powersConfig from "../models/powers.json";
import gokuConfig from "../models/goku.json";
import gokuBaseImg from "../asstets/images/rosters/goku_base.png";
import vegetaBaseImg from "../asstets/images/rosters/vegeta_base.png";

// ─── Constantes de estado (copiadas de HUD.ts) ────────────────────────────────
type CombatState = "neutral" | "charging" | "charging_special" | "attacking" | "defending" | "slowMotion" | "hit" | "melee" | "recharging";

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

// ─── Helpers de color/rango (duplicados de HUD.ts para no crear dependencia) ──

function getNPColor(np: number): string {
  if (np >= 150000) return "#ffffff";
  if (np >= 70000) return "#ff8800";
  if (np >= 30000) return "#ffcc00";
  if (np >= 10000) return "#00ecff";
  if (np >= 3000) return "#00ff88";
  return "#aabbcc";
}



// ─── Clase principal ──────────────────────────────────────────────────────────

export class VRHud {
  private scene: Scene;
  private combat: CombatSystem;
  private inputManager: InputManager;

  // Meshes de los paneles
  private playerPanel!: Mesh;
  private enemyPanel!: Mesh;
  private attackPanel!: Mesh;
  private defensePanel!: Mesh;
  private statusPanel!: Mesh;
  private debugPanel!: Mesh;
  private powersGuidePanel!: Mesh;
  private hudRoot: Mesh | null = null;

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
  private playerKIBar!: Rectangle;
  private playerKIText!: TextBlock;
  private playerEstadoText!: TextBlock;

  private enemyNPBar!: Rectangle;
  private enemyNPText!: TextBlock;
  private enemyKIBar!: Rectangle;
  private enemyKIText!: TextBlock;
  private enemyEstadoText!: TextBlock;

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
  private powersStack: StackPanel | null = null;
  private toastTimeout: any = null;
  private statusBuffer: string[] = [];

  private visible = false;

  constructor(scene: Scene, combat: CombatSystem, inputManager: InputManager) {
    this.scene = scene;
    this.combat = combat;
    this.inputManager = inputManager;
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
    this.buildPowersGuidePanel();
  }

  /** Panel izquierdo — stats del jugador */
  private buildPlayerPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-player", 0.75, 0.35, 512);
    this.playerPanel = mesh;
    this.playerADT = adt;

    const bg = this.makePanelBg(adt, "rgba(0,15,40,0.95)", "rgba(0,200,255,0.7)");

    // StackPanel horizontal: avatar + barras
    const mainStack = new StackPanel("p-main-stack");
    mainStack.isVertical = false;
    mainStack.width = "100%";
    mainStack.height = "100%";
    mainStack.spacing = 12;
    mainStack.paddingLeftInPixels = 12;
    mainStack.paddingRightInPixels = 12;
    mainStack.paddingTopInPixels = 10;
    mainStack.paddingBottomInPixels = 10;
    mainStack.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    mainStack.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
    bg.addControl(mainStack);

    // Avatar circular (Goku)
    this.createAvatarCircle(mainStack, gokuBaseImg, "#00ccff");

    // StackPanel vertical para barras
    const barsStack = new StackPanel("p-bars-stack");
    barsStack.isVertical = true;
    barsStack.width = "70%";
    barsStack.height = "100%";
    barsStack.spacing = 8;
    mainStack.addControl(barsStack);

    // Fila NP
    const npGroup = this.makeBarGroupForStack(barsStack, "NP", "#00ff88");
    this.playerNPBar = npGroup.fill;
    this.playerNPText = npGroup.valueText;

    // Fila KI
    const kiGroup = this.makeBarGroupForStack(barsStack, "KI", "#00ccff");
    this.playerKIBar = kiGroup.fill;
    this.playerKIText = kiGroup.valueText;

    // Fila ESTADO
    const estadoRow = new StackPanel("p-estado-row");
    estadoRow.isVertical = false;
    estadoRow.width = "100%";
    estadoRow.heightInPixels = 24;
    estadoRow.spacing = 8;
    barsStack.addControl(estadoRow);

    const estadoLabel = new TextBlock("p-estado-label", "ESTADO");
    estadoLabel.color = "#00ff88";
    estadoLabel.fontSize = 14;
    estadoLabel.fontStyle = "bold";
    estadoLabel.width = "60px";
    estadoLabel.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    estadoRow.addControl(estadoLabel);

    this.playerEstadoText = new TextBlock("p-estado-value", "NEUTRAL");
    this.playerEstadoText.color = "#00ff88";
    this.playerEstadoText.fontSize = 14;
    this.playerEstadoText.fontStyle = "bold";
    this.playerEstadoText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    estadoRow.addControl(this.playerEstadoText);

    // Guardar referencia a rango para compatibilidad
    // playerNPRank remotion cleanup
  }

  /** Panel derecho — stats del enemigo */
  private buildEnemyPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-enemy", 0.75, 0.35, 512);
    this.enemyPanel = mesh;
    this.enemyADT = adt;

    const bg = this.makePanelBg(adt, "rgba(40,5,5,0.95)", "rgba(255,60,60,0.7)");

    // StackPanel horizontal: avatar + barras
    const mainStack = new StackPanel("e-main-stack");
    mainStack.isVertical = false;
    mainStack.width = "100%";
    mainStack.height = "100%";
    mainStack.spacing = 12;
    mainStack.paddingLeftInPixels = 12;
    mainStack.paddingRightInPixels = 12;
    mainStack.paddingTopInPixels = 10;
    mainStack.paddingBottomInPixels = 10;
    mainStack.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    mainStack.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
    bg.addControl(mainStack);

    // Avatar circular (Vegeta)
    this.createAvatarCircle(mainStack, vegetaBaseImg, "#ff4444");

    // StackPanel vertical para barras
    const barsStack = new StackPanel("e-bars-stack");
    barsStack.isVertical = true;
    barsStack.width = "70%";
    barsStack.height = "100%";
    barsStack.spacing = 8;
    mainStack.addControl(barsStack);

    // Fila NP
    const npGroup = this.makeBarGroupForStack(barsStack, "NP", "#ff4444");
    this.enemyNPBar = npGroup.fill;
    this.enemyNPText = npGroup.valueText;

    // Fila KI
    const kiGroup = this.makeBarGroupForStack(barsStack, "KI", "#ff6600");
    this.enemyKIBar = kiGroup.fill;
    this.enemyKIText = kiGroup.valueText;

    // Fila ESTADO
    const estadoRow = new StackPanel("e-estado-row");
    estadoRow.isVertical = false;
    estadoRow.width = "100%";
    estadoRow.heightInPixels = 24;
    estadoRow.spacing = 8;
    barsStack.addControl(estadoRow);

    const estadoLabel = new TextBlock("e-estado-label", "ESTADO");
    estadoLabel.color = "#ff4444";
    estadoLabel.fontSize = 14;
    estadoLabel.fontStyle = "bold";
    estadoLabel.width = "60px";
    estadoLabel.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    estadoRow.addControl(estadoLabel);

    this.enemyEstadoText = new TextBlock("e-estado-value", "NEUTRAL");
    this.enemyEstadoText.color = "#ff4444";
    this.enemyEstadoText.fontSize = 14;
    this.enemyEstadoText.fontStyle = "bold";
    this.enemyEstadoText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    estadoRow.addControl(this.enemyEstadoText);

    // Guardar referencia a rango para compatibilidad
    // enemyNPRank remotion cleanup
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
    const { mesh, adt } = this.createPanel("vrHud-debug", 0.55, 0.4, 1024);
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
    stack.height = "90%";
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
    this.debugLeftHandText.fontSize = 15;
    this.debugLeftHandText.heightInPixels = 75;
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
    this.debugRightHandText.fontSize = 15;
    this.debugRightHandText.heightInPixels = 75;
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
    this.debugGestureText.fontSize = 20;
    this.debugGestureText.fontStyle = "bold";
    this.debugGestureText.heightInPixels = 56;
    this.debugGestureText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    stack.addControl(this.debugGestureText);
  }

  /** Panel izquierdo lejano — Guía de movimientos (Phase 18) */
  private buildPowersGuidePanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-powers", 0.70, 0.75, 1200);
    this.powersGuidePanel = mesh;

    const bg = this.makePanelBg(adt, "rgba(5, 15, 10, 0.92)", "#00ff88");

    // Título
    const title = new TextBlock("guide-title", "📜 GUÍA DE MOVIMIENTOS");
    title.color = "#00ff88";
    title.fontSize = 20;
    title.fontStyle = "bold";
    title.heightInPixels = 30;
    title.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    title.top = "10px";
    bg.addControl(title);

    // Botón de Modo Espejo (Phase 21)
    const mirrorBtn = Button.CreateSimpleButton("mirror-btn", "MODO ESPEJO: OFF");
    mirrorBtn.width = "200px";
    mirrorBtn.height = "40px";
    mirrorBtn.color = "white";
    mirrorBtn.background = "#333333";
    mirrorBtn.cornerRadius = 10;
    mirrorBtn.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    mirrorBtn.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
    mirrorBtn.top = "10px";
    mirrorBtn.left = "-10px"; // En lugar de .right
    mirrorBtn.onPointerClickObservable.add(() => {
        // @ts-ignore
        const combat = this.combat;
        if (combat) {
            combat.mirrorMode = !combat.mirrorMode;
            // @ts-ignore
            if (mirrorBtn.textBlock) mirrorBtn.textBlock.text = `MODO ESPEJO: ${combat.mirrorMode ? "ON" : "OFF"}`;
            mirrorBtn.background = combat.mirrorMode ? "#00ff88" : "#333333";
            mirrorBtn.color = combat.mirrorMode ? "black" : "white";
        }
    });
    bg.addControl(mirrorBtn);

    // Botón de Exportar JSON (Para guardar permanentemente en el proyecto)
    const exportBtn = Button.CreateSimpleButton("export-btn", "📥 EXPORTAR JSON");
    exportBtn.width = "200px";
    exportBtn.height = "40px";
    exportBtn.color = "white";
    exportBtn.background = "#004488";
    exportBtn.cornerRadius = 10;
    exportBtn.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    exportBtn.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
    exportBtn.top = "60px"; // Debajo del mirrorBtn
    exportBtn.left = "-10px";
    exportBtn.onPointerClickObservable.add(() => {
        const gss = this.inputManager.getGSS();
        gss.exportModel();
        this.statusText.text = "¡MODELO EXPORTADO!\nRevisa tus descargas.";
        this.statusBg.isVisible = true;
        this.statusBg.background = "rgba(0, 100, 200, 0.8)";
        setTimeout(() => { this.statusBg.isVisible = false; }, 3000);
    });
    bg.addControl(exportBtn);

    // Contenedor ScrollViewer para lista de poderes
    const viewer = new ScrollViewer("guide-viewer");
    viewer.width = "96%";
    viewer.height = "85%";
    viewer.top = "45px";
    viewer.thickness = 0;
    viewer.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    viewer.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    viewer.barSize = 10;
    viewer.barColor = "#00ff88"; // Scrollbar en color temático
    bg.addControl(viewer);

    const stack = new StackPanel("guide-stack");
    stack.isVertical = true;
    stack.width = "100%";
    stack.adaptHeightToChildren = true; // CRECE CON EL CONTENIDO
    stack.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
    stack.spacing = 6;
    viewer.addControl(stack);
    this.powersStack = stack;
    
    this.renderPowersList();
  }

  public renderPowersList(filterPower?: string): void {
    if (!this.powersStack) return;
    this.powersStack.getDescendants().forEach(c => c.dispose());

    const gss = this.inputManager.getGSS();
    const activeChar = gss.activeCharacter;
    const characterId = activeChar?.id || "goku";
    this.statusText.text = `SISTEMA GSS: ${characterId.toUpperCase()}`; // Usar characterId para dar feedback
    
    // Fallback a gokuConfig solo si no hay personaje activo en GSS
    const allowedPowers = activeChar?.timing ? Object.keys(activeChar.timing).filter(k => k !== 'kiBlast') : (gokuConfig.transformations[0].powers || []);
    const powersDict = powersConfig as Record<string, any>;

    const gestureLabelMap: Record<string, string> = {
        "hands_clasped_at_waist": "Carga el Ki: Manos juntas cerca de tu cintura/lateral",
        "palms_forward_push": "¡Dispara!: Empuje frontal con palmas abiertas",
        "arms_extended_horizontally": "Brazos en T: Extiéndelos a los costados horizontalmente",
        "palms_forward_together": "Poder Máximo: Manos juntas al frente (Final Flash prep)",
        "arms_raised_to_sky": "Reunir Energía: Manos al cielo (Gathering)",
        "arms_throw_forward": "Lanzamiento: Baja los brazos con fuerza hacia adelante",
        "palm_forward_aim": "Apunta: Una mano extendida hacia el enemigo (Hakai prep)",
        "clench_fist": "Ejecutar: Cierra el puño con fuerza",
        "hands_left_shoulder_crossed": "Hombro Izquierdo: Manos cruzadas (Galick prep)",
        "ki_prep": "Mano lista: Mano semi-abierta al frente",
        "ki_fire": "Disparo rápido: Empuje corto y veloz",
        "ki_charge_prep": "Carga concentrada: Brazo estirado cubriendo el pecho",
        "ki_charge_fire": "Ráfaga potente: Sacudida frontal",
        "recharge_p1": "Máximo Poder: Puños cerrados cerca de la cara",
        "recharge_p2": "Grito de Guerra: Abre los brazos con fuerza lateral",
        "palms_forward_push_wide": "¡Super Disparo!: Empuje masivo con ambas manos",
        "arms_crossed_chest": "Preparación: Cruzar brazos en X frente al pecho",
        "kaioken": "¡KAIOKEN!: Grito de aumento de poder y aura roja"
    };

    // 1. ATAQUES BÁSICOS Y ESTADOS
    const basicMoves = [
        { id: "KI_BLAST", name: "Ataque de Ki Rápido", p: "ki_prep", f: "ki_fire", cost: "10 KI", time: "Instant" },
        { id: "CHARGED_KI_BLAST", name: "Ataque de Ki Cargado", p: "ki_charge_prep", f: "ki_charge_fire", cost: "1.5% Ki tick", time: "Variable" },
        { id: "RECHARGE", name: "Recargar Ki", p: "recharge_p1", f: "recharge_p2", cost: "0 KI", time: "Continuo" }
    ];

    if (!filterPower) {
        for (const b of basicMoves) {
            const powerContainer = new Rectangle(`p-guide-${b.id}`);
            powerContainer.width = "100%";
            powerContainer.heightInPixels = 105;
            powerContainer.thickness = 0;
            this.powersStack.addControl(powerContainer);

            const pTitle = new TextBlock(`pt-${b.id}`, b.name.toUpperCase());
            pTitle.color = "#00ff88";
            pTitle.fontSize = 24;
            pTitle.fontStyle = "bold";
            pTitle.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
            pTitle.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
            powerContainer.addControl(pTitle);

            const pGestures = new TextBlock(`pg-${b.id}`, `Pasos: ${gestureLabelMap[b.p]} -> ${gestureLabelMap[b.f]}`);
            pGestures.color = "#aaaaaa";
            pGestures.fontSize = 18;
            pGestures.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
            pGestures.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
            pGestures.top = "38px";
            powerContainer.addControl(pGestures);

            const pCost = new TextBlock(`pc-${b.id}`, `Costo: ${b.cost} | Tipo: ${b.time}`);
            pCost.color = "#00ccff";
            pCost.fontSize = 16;
            pCost.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
            pCost.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
            pCost.top = "68px";
            powerContainer.addControl(pCost);

            // Botones de calibración (Phase 20+)
            const calStack = new StackPanel(`cal-stack-${b.id}`);
            calStack.isVertical = false;
            calStack.width = "280px";
            calStack.height = "40px";
            calStack.spacing = 6;
            calStack.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
            calStack.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
            powerContainer.addControl(calStack);

            const gss = this.inputManager.getGSS();
            const count1 = gss.getGestureCount(this.getLabelForPower(b.id, "PREP"));
            const count2 = gss.getGestureCount(this.getLabelForPower(b.id, "FIRE"));

            const calBtn1 = Button.CreateSimpleButton(`cal1-${b.id}`, `F1: ${count1}`);
            calBtn1.width = "85px";
            calBtn1.height = "35px";
            calBtn1.color = "white";
            calBtn1.background = "#4444aa";
            calBtn1.cornerRadius = 5;
            calBtn1.onPointerClickObservable.add(() => this.startCalibration(b.id, "PREP"));
            calStack.addControl(calBtn1);

            const calBtn2 = Button.CreateSimpleButton(`cal2-${b.id}`, `F2: ${count2}`);
            calBtn2.width = "85px";
            calBtn2.height = "35px";
            calBtn2.color = "white";
            calBtn2.background = "#6666cc";
            calBtn2.cornerRadius = 5;
            calBtn2.onPointerClickObservable.add(() => this.startCalibration(b.id, "FIRE"));
            calStack.addControl(calBtn2);

            const resetBtn = Button.CreateSimpleButton(`res-${b.id}`, "RESET");
            resetBtn.width = "75px";
            resetBtn.height = "35px";
            resetBtn.color = "white";
            resetBtn.background = "#660000";
            resetBtn.cornerRadius = 5;
            resetBtn.onPointerClickObservable.add(() => this.resetCalibration(b.id));
            calStack.addControl(resetBtn);
        }
    }

    // 2. ATAQUES ESPECIALES (Dinamicos de powers.json)
    for (const k of allowedPowers) {
      if (filterPower && k.toLowerCase() !== filterPower.toLowerCase()) continue;

      const d = powersDict[k];
      if (!d) continue;

      const powerContainer = new Rectangle(`p-guide-${k}`);
      powerContainer.width = "100%";
      powerContainer.heightInPixels = 120; // Un poco mas alto
      powerContainer.thickness = 0;
      powerContainer.paddingBottomInPixels = 10;
      powerContainer.background = filterPower ? "rgba(0,255,136,0.1)" : "transparent";
      this.powersStack.addControl(powerContainer);

      const pTitle = new TextBlock(`pt-${k}`, (d.name || k).toUpperCase());
      pTitle.color = filterPower ? "#00ff88" : "#ffffff";
      pTitle.fontSize = 24;
      pTitle.fontStyle = "bold";
      pTitle.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
      pTitle.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
      powerContainer.addControl(pTitle);

      const pGestures = new TextBlock(`pg-${k}`, `Pasos: ${gestureLabelMap[d.vr_gestures?.preparation] || "???"} -> ${gestureLabelMap[d.vr_gestures?.firing] || "???"}`);
      pGestures.color = "#aaaaaa";
      pGestures.fontSize = 18;
      pGestures.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
      pGestures.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
      pGestures.top = "38px";
      powerContainer.addControl(pGestures);
      
      const pCost = new TextBlock(`pc-${k}`, `Ki: ${d.ki_cost || "40+"} | Carga: ${d.charge_time || "N/A"}s`);
      pCost.color = "#ff8800";
      pCost.fontSize = 16;
      pCost.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
      pCost.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
      pCost.top = "68px";
      powerContainer.addControl(pCost);

      // Botones de calibración (Phase 20+)
      const calStack = new StackPanel(`cal-stack-${k}`);
      calStack.isVertical = false;
      calStack.width = "280px";
      calStack.height = "40px";
      calStack.spacing = 6;
      calStack.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
      calStack.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
      powerContainer.addControl(calStack);

      const gss = this.inputManager.getGSS();
      const count1 = gss.getGestureCount(this.getLabelForPower(k, "PREP"));
      const count2 = gss.getGestureCount(this.getLabelForPower(k, "FIRE"));

      const calBtn1 = Button.CreateSimpleButton(`cal1-${k}`, `F1: ${count1}`);
      calBtn1.width = "85px";
      calBtn1.height = "35px";
      calBtn1.color = "white";
      calBtn1.background = "#aa4400";
      calBtn1.cornerRadius = 5;
      calBtn1.onPointerClickObservable.add(() => this.startCalibration(k, "PREP"));
      calStack.addControl(calBtn1);

      const calBtn2 = Button.CreateSimpleButton(`cal2-${k}`, `F2: ${count2}`);
      calBtn2.width = "85px";
      calBtn2.height = "35px";
      calBtn2.color = "white";
      calBtn2.background = "#cc6622";
      calBtn2.cornerRadius = 5;
      calBtn2.onPointerClickObservable.add(() => this.startCalibration(k, "FIRE"));
      calStack.addControl(calBtn2);

      const resetBtn = Button.CreateSimpleButton(`res-${k}`, "RESET");
      resetBtn.width = "75px";
      resetBtn.height = "35px";
      resetBtn.color = "white";
      resetBtn.background = "#660000";
      resetBtn.cornerRadius = 5;
      resetBtn.onPointerClickObservable.add(() => this.resetCalibration(k));
      calStack.addControl(resetBtn);
    }
  }

  private getLabelForPower(powerId: string, phase: "PREP" | "FIRE"): string {
      const pId = powerId.toLowerCase();
      if (pId === "kamehameha") {
          return (phase === "PREP") ? "kamehameha_preparation" : "kamehameha_firing";
      } else if (pId === "genkidama") {
          return (phase === "PREP") ? "genkidama_preparation" : "genkidama_firing";
      } else if (pId === "ki_blast") {
          return (phase === "PREP") ? "ki_prep" : "ki_fire";
      } else if (pId === "charged_ki_blast") {
          return (phase === "PREP") ? "ki_charge_prep" : "ki_charge_fire";
      } else if (pId === "recharge") {
          return (phase === "PREP") ? "recharge_p1" : "recharge_p2";
      } else if (pId === "stance") {
          return "stance";
      } else {
          // Fallback genérico si es técnica nueva o ataque dinámico
          const power = (powersConfig as any)[pId];
          return (power && power.vr_gestures) 
            ? ((phase === "PREP") ? power.vr_gestures.preparation : power.vr_gestures.firing)
            : `${pId}_${phase.toLowerCase()}`;
      }
  }

  private resetCalibration(powerId: string): void {
      const gss = this.inputManager.getGSS();
      if (!gss) return;

      // Resetear el modelo del personaje actual
      localStorage.removeItem(`gss_model_${powerId.toLowerCase()}`); 
      // Notificar al usuario — en una versión real llamaríamos a un método de reset en GSS
      this.statusText.text = `¡MODELO DE ${powerId.toUpperCase()} RESETEADO!\nReinicia la app para limpiar memoria.`;
      
      this.statusBg.isVisible = true;
      this.statusBg.background = "rgba(100, 100, 100, 0.7)";
      setTimeout(() => { this.statusBg.isVisible = false; }, 2000);
  }

  private async startCalibration(powerId: string, phase: "PREP" | "FIRE"): Promise<void> {
      const gss = this.inputManager.getGSS();
      if (!gss) return;

      const label = this.getLabelForPower(powerId, phase);

      this.statusBg.isVisible = true;
      this.statusBg.background = "rgba(40, 40, 150, 0.8)";
      
      for (let i = 5; i > 0; i--) {
          this.statusText.text = `PREPARA ${label.toUpperCase()}\nGRABANDO EN ${i}...`;
          await new Promise(r => setTimeout(r, 1000));
      }

      this.statusBg.background = "rgba(255, 0, 0, 0.7)";
      this.statusText.text = `¡GRABANDO ${label.toUpperCase()}!\nMantén la postura...`;

      // Iniciar entrenamiento en GSS
      gss.startTraining(label, "wristOnly");

      // Capturar durante 2 segundos (~20 frames con el throttle del update)
      await new Promise(r => setTimeout(r, 2000));

      gss.stopTraining();
      this.statusText.text = `SESION GUARDADA\n(${label})`;
      this.statusBg.background = "rgba(0, 255, 0, 0.6)";

      // Refrescar para ver el contador actualizado
      this.renderPowersList();

      setTimeout(() => { this.statusBg.isVisible = false; }, 2000);
  }

  /** Panel de estado — bullet time, alerta de ataque, historial de acciones */
  private buildStatusPanel(): void {
    const { mesh, adt } = this.createPanel("vrHud-status", 0.85, 0.22, 512); // Más alto para 3 líneas
    this.statusPanel = mesh;
    this.statusADT = adt;

    const bg = new Rectangle("status-bg");
    bg.width = "100%";
    bg.height = "100%";
    bg.cornerRadius = 14;
    bg.background = "rgba(0,0,0,0.65)";
    bg.color = "rgba(255,255,255,0.2)";
    bg.thickness = 1.5;
    bg.isVisible = false; // Oculto por defecto
    adt.addControl(bg);
    this.statusBg = bg;

    const txt = new TextBlock("status-txt", "");
    txt.color = "white";
    txt.fontSize = 22; // Un poco más pequeño para que quepan 3 líneas
    txt.fontStyle = "bold";
    txt.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
    txt.textVerticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
    txt.textWrapping = true;
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
    // 1. Obtener la posición y rotación actual de la cámara para "congelar" el HUD ahí
    const forward = xrCamera.getForwardRay().direction;
    const pos = xrCamera.globalPosition.clone();
    
    // Limpiar root previo si existe
    if (this.hudRoot) {
        this.hudRoot.dispose();
    }

    // Crear un contenedor invisible que mire hacia donde mira el jugador AHORA
    this.hudRoot = MeshBuilder.CreateBox("hudRoot", { size: 0.01 }, this.scene);
    this.hudRoot.isVisible = false;
    this.hudRoot.position = pos;
    // Alineamos el root con la cámara pero ignoramos el "tilt" (parche para horizonte estable)
    this.hudRoot.lookAt(pos.add(new Vector3(forward.x, 0, forward.z)));

    const panels = [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ];

    panels.forEach(m => {
      m.parent = this.hudRoot;
    });

    // 2. Posicionamiento LOCAL al root (fijo en el mundo desde este momento)
    // X+: derecha, Y+: arriba, Z+: adelante
    
    // Stats laterales (un poco más abiertos)
    this.playerPanel.position = new Vector3(-1.1, 0.4, 1.4);
    this.playerPanel.rotation = new Vector3(0, -0.4, 0);

    this.enemyPanel.position = new Vector3(1.1, 0.4, 1.4);
    this.enemyPanel.rotation = new Vector3(0, 0.4, 0);

    // Paneles de acción (arriba y abajo del todo)
    this.attackPanel.position = new Vector3(0.00, 0.95, 1.4);
    this.defensePanel.position = new Vector3(0.00, -0.72, 1.4);

    // ESTADO CENTRAL (Se mueve arriba para dar paso a la guía)
    this.statusPanel.position = new Vector3(0.00, 0.70, 1.3);

    // GUÍA DE PODERES: Ahora en el centro, encima del de gestos
    // Height de powersGuide es 0.75m. Height de debug es 0.3m.
    // Debug en -0.35, su tope es -0.20.
    // Guide en 0.22, su base es -0.15. (Gap de 0.05m)
    this.powersGuidePanel.position = new Vector3(0.0, 0.22, 1.3);
    this.powersGuidePanel.rotation = new Vector3(0, 0, 0);

    // DEBUG DE GESTOS: Centrado inferior
    this.debugPanel.position = new Vector3(0.00, -0.38, 1.3);

    this.show();
  }

  /** Desenlaza el HUD de la cámara */
  detachFromCamera(): void {
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(m => {
      m.parent = null;
    });
    if (this.hudRoot) {
        this.hudRoot.dispose();
        this.hudRoot = null;
    }
    this.hide();
  }

  // ─── Visibilidad ────────────────────────────────────────────────────────────

  show(): void {
    this.visible = true;
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(m => {
      m.setEnabled(true);
    });
    this.update(this.combat.getStats());
  }

  hide(): void {
    this.visible = false;
    [
        this.playerPanel, this.enemyPanel, this.attackPanel, 
        this.defensePanel, this.statusPanel, this.debugPanel,
        this.powersGuidePanel
    ].forEach(m => {
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
    this.playerKIBar.width = `${pKI}%`;
    this.playerKIText.text = `${stats.playerKi.toFixed(0)}`;

    // Actualizar ESTADO
    const pEstadoText = STATE_LABELS[stats.combatState as CombatState] || "NEUTRAL";
    const pEstadoColor = STATE_COLORS[stats.combatState as CombatState] || "#00ff88";
    this.playerEstadoText.text = pEstadoText;
    this.playerEstadoText.color = pEstadoColor;

    // ── Enemigo ──
    const eNP = stats.enemyNP || 10000;
    const eNPPct = (eNP / 100000);
    const eKI = Math.max(0, Math.min(100, (stats.enemyKi / stats.enemyMaxKi) * 100));

    this.enemyNPBar.width = `${Math.min(100, eNPPct * 100)}%`;
    this.enemyNPBar.background = getNPColor(eNP);
    this.enemyNPText.text = eNP.toLocaleString();
    this.enemyKIBar.width = `${eKI}%`;
    this.enemyKIText.text = `${stats.enemyKi.toFixed(0)}`;

    // Actualizar ESTADO
    const eEstadoText = STATE_LABELS[stats.combatState as CombatState] || "NEUTRAL";
    const eEstadoColor = STATE_COLORS[stats.combatState as CombatState] || "#ff4444";
    this.enemyEstadoText.text = eEstadoText;
    this.enemyEstadoText.color = eEstadoColor;

    this.updateStatus(stats);
    this.updateActionKiCounter(stats);
    this.filterActionsByKi(stats);
    this.updatePowersGuide(stats);
  }

  private updatePowersGuide(stats: GameStats): void {
    // Si estamos en medio de una carga especial, filtrar la lista para mostrar solo ese poder
    if (stats.combatState === "charging_special" && stats.specialType) {
        this.renderPowersList(stats.specialType);
    } else if (this.currentHudType === "normal") {
        // Volver a mostrar toda la lista si regresamos a neutral
        // Solo renderizar si el stats.combatState cambió de charging_special a otra cosa
        // O si simplemente refrescamos (podemos optimizar con un flag anterior)
        if (this.powersStack && this.powersStack.children.length <= 1) {
             this.renderPowersList();
        }
    }
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
        this.makeActionBtn(this.defenseRow, "D", "Esquiva", "#66ccff", "#001122", () => c.activateDodge(), 5);
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

      this.makeActionBtn(this.attackRow, "A", "Rápido", "#00ff88", "#002211", () => c.meleeAttack("light"), 0);
      this.makeActionBtn(this.attackRow, "S", "Múltiple", "#66ccff", "#001122", () => c.meleeAttack("heavy"), 0);
      this.makeActionBtn(this.attackRow, "D", "Cargado", "#ffcc00", "#332200", () => c.meleeAttack("charged"), 0);
      this.makeActionBtn(this.attackRow, "W", "Vanish", "#cc44ff", "#220033", () => c.meleeAttack("vanish"), 10);
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
      // Sólo limpiar si NO hay un toast activo (para no borrar los mensajes rápidos de acciones)
      if (!this.toastTimeout) {
        this.statusText.text = "";
        this.statusBg.background = "rgba(0,0,0,0)";
        this.statusBg.thickness = 0;
      }
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

    // Gesto e info del GSS (Phase 21+)
    const gss = this.inputManager.getGSS();
    if (gss) {
        const charId = gss.activeCharacter?.id || "unknown";
        this.debugGestureText.text = `PERSONAJE: ${charId.toUpperCase()}\nESTADO: ${gss.currentState.toUpperCase()}`;
    } else {
        this.debugGestureText.text = gesture || "NINGUNO";
    }
  }

  showToast(message: string, color: string = "white", duration: number = 4000): void {
    if (!this.statusText || !this.statusBg) return;

    // Agregar al buffer e historial
    this.statusBuffer.push(message);
    if (this.statusBuffer.length > 3) this.statusBuffer.shift();

    this.statusText.text = this.statusBuffer.join("\n");
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
    // No vaciar el texto inmediatamente si queremos que se vea el historial
    // Solo desvanecer el fondo tras el tiempo de espera
    if (this.statusBg) {
      this.statusBg.background = "rgba(0,0,0,0.2)"; // Semi-visible para el historial?
      this.statusBg.thickness = 0;
      this.statusBg.isVisible = false;
    }
    // Si queremos limpiar el historial después de un tiempo extra
    setTimeout(() => {
        if (!this.toastTimeout && this.statusText) {
            this.statusBuffer = [];
            this.statusText.text = "";
        }
    }, 2000);

    if (this.toastTimeout) {
      clearTimeout(this.toastTimeout);
      this.toastTimeout = null;
    }
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

  /** Crea un avatar circular con imagen y glow */
  private createAvatarCircle(
    parent: StackPanel,
    imageUrl: string,
    borderColor: string
  ): Ellipse {
    const glowColor = borderColor === "#00ccff" ? "rgba(0,200,255,0.5)" : "rgba(255,60,60,0.5)";

    // Glow exterior
    const glow = new Ellipse("avatar-glow");
    glow.width = "90px";
    glow.height = "90px";
    glow.color = "transparent";
    glow.thickness = 0;
    glow.shadowBlur = 15;
    glow.shadowColor = glowColor;
    parent.addControl(glow);

    // Borde del avatar
    const border = new Ellipse("avatar-border");
    border.width = "84px";
    border.height = "84px";
    border.color = borderColor;
    border.thickness = 2.5;
    border.background = "transparent";
    glow.addControl(border);

    // Imagen
    const img = new Image("avatar-img", imageUrl);
    img.stretch = Image.STRETCH_UNIFORM;
    border.addControl(img);

    return border;
  }



  /** Crea un grupo barra de progreso + valor para StackPanel */
  private makeBarGroupForStack(
    parent: StackPanel,
    label: string,
    fillColor: string
  ): { fill: Rectangle; valueText: TextBlock } {
    // Contenedor horizontal para barra + valor
    const barRow = new StackPanel(`${label}-bar-row`);
    barRow.isVertical = false;
    barRow.width = "100%";
    barRow.heightInPixels = 20;
    barRow.spacing = 4;
    parent.addControl(barRow);

    // Fondo de la barra
    const barBg = new Rectangle(`${label}-bar-bg`);
    barBg.width = "85%";
    barBg.heightInPixels = 14;
    barBg.cornerRadius = 4;
    barBg.background = "rgba(0,0,0,0.5)";
    barBg.thickness = 1;
    barBg.color = "rgba(0,200,255,0.3)";
    barRow.addControl(barBg);

    // Relleno de la barra
    const fill = new Rectangle(`${label}-fill`);
    fill.width = "100%";
    fill.heightInPixels = 14;
    fill.cornerRadius = 4;
    fill.background = fillColor;
    fill.thickness = 0;
    fill.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
    barBg.addControl(fill);

    // Valor numérico
    const val = new TextBlock(`${label}-val`, "100");
    val.isVisible = true;
    val.color = fillColor;
    val.fontSize = 12;
    val.fontStyle = "bold";
    val.width = "15%";
    val.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
    barRow.addControl(val);

    return { fill, valueText: val };
  }
}
