import { Scene } from "@babylonjs/core";
import {
    StackPanel,
    Rectangle,
    TextBlock,
    Control,
    Button,
    ScrollViewer,
} from "@babylonjs/gui";
import { HUDPanel } from "./HUDPanel";
import { CombatSystem } from "../../systems/combat/CombatSystem";
import { InputManager } from "../../systems/input/InputManager";
import powersConfig from "../../models/powers.json";
import gokuConfig from "../../models/goku.json";

export class PowersGuidePanel extends HUDPanel {
    private powersStack!: StackPanel;
    public onModelRepaired?: () => void;

    // Callbacks persistentes para evitar pérdida en re-renderings
    private _onCal?: (id: string, phase: "PREP" | "FIRE") => void;
    private _onReset?: (id: string) => void;
    private _onSimulate?: (id: string) => void;
    private _onResetPositions?: () => void;

    constructor(scene: Scene, _combat: CombatSystem, private inputManager: InputManager) {
        super(scene, {
            name: "vrHud-powers",
            width: 0.65,
            height: 0.80,
            resolution: 1400,
        });

        const bg = this.makePanelBg("rgba(5, 15, 10, 0.75)", "#00ff88");
        this.addScanlines(bg);
        this.buildLayout();
    }

    private buildLayout(): void {
        const title = new TextBlock("guide-title", "📜 GUÍA DE MOVIMIENTOS");
        title.color = "#00ff88";
        title.fontSize = 20;
        title.fontStyle = "bold";
        title.heightInPixels = 30;
        title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        title.top = "10px";
        this.rootRect.addControl(title);



        const viewer = new ScrollViewer("guide-viewer");
        viewer.width = "96%";
        viewer.height = "85%";
        viewer.top = "45px";
        viewer.thickness = 0;
        viewer.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        viewer.barSize = 10;
        viewer.barColor = "#00ff88";
        this.rootRect.addControl(viewer);

        this.powersStack = new StackPanel("guide-stack");
        this.powersStack.isVertical = true;
        this.powersStack.width = "100%";
        this.powersStack.adaptHeightToChildren = true;
        this.powersStack.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        this.powersStack.spacing = 6;
        viewer.addControl(this.powersStack);
    }

    public renderPowersList(
        filterPower?: string, 
        startCalibration?: (id: string, phase: "PREP" | "FIRE") => void, 
        resetCalibration?: (id: string) => void, 
        simulateGesture?: (id: string) => void,
        resetPositions?: () => void
    ): void {
        // Guardar callbacks si se proporcionan, si no, usar los guardados
        if (startCalibration) this._onCal = startCalibration;
        if (resetCalibration) this._onReset = resetCalibration;
        if (simulateGesture) this._onSimulate = simulateGesture;
        if (resetPositions) this._onResetPositions = resetPositions;

        const onCal = this._onCal;
        const onReset = this._onReset;
        const onSim = this._onSimulate;
        const onResetPos = this._onResetPositions;

        this.powersStack.getDescendants().forEach(c => c.dispose());

        const gss = this.inputManager.getGSS();
        const activeChar = gss.activeCharacter;
        
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
            "recharge_prep": "Máximo Poder: Puños cerrados cerca de la cara",
            "recharge_active": "Grito de Guerra: Abre los brazos con fuerza lateral",
            "palms_forward_push_wide": "¡Super Disparo!: Empuje masivo con ambas manos",
            "arms_crossed_chest": "Pared: Brazos en cruz (Shield)",
            "kaioken": "¡KAIOKEN!: Aumento de poder masivo",
        };

        const basicMoves = [
            { id: "KI_BLAST", name: "Ataque de Ki", p: "ki_prep", f: "ki_fire", cost: "10 KI", time: "Instant/Charge" },
            { id: "RECHARGE", name: "Recargar Ki", p: "recharge_prep", f: "recharge_active", cost: "0 KI", time: "Continuo" }
        ];

        if (!filterPower) {
            for (const b of basicMoves) {
                this.addPowerItem(b.id, b.name, gestureLabelMap[b.p], gestureLabelMap[b.f], b.cost, b.time, onCal, onReset, onSim);
            }
        }

        for (const k of allowedPowers) {
            if (filterPower && k.toLowerCase() !== filterPower.toLowerCase()) continue;
            const d = powersDict[k];
            if (!d) continue;

            const prepLabel = gestureLabelMap[d.vr_gestures?.preparation] || "???";
            const fireLabel = gestureLabelMap[d.vr_gestures?.firing] || "???";
            const cost = `Ki: ${d.ki_cost || "40+"}`;
            const time = `Carga: ${d.charge_time || "N/A"}s`;

            this.addPowerItem(k, d.name || k, prepLabel, fireLabel, cost, time, onCal, onReset, onSim, !!filterPower);
        }

        // Si estamos viendo un detalle, añadir botón de reset de posiciones al final
        if (filterPower && onResetPos) {
            const resetBtn = Button.CreateSimpleButton("reset-pos-btn", " 🛠️ REINICIAR POSICIONES VR");
            resetBtn.width = "400px";
            resetBtn.height = "50px";
            resetBtn.color = "white";
            resetBtn.background = "#4444aa";
            resetBtn.cornerRadius = 10;
            resetBtn.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
            resetBtn.onPointerDownObservable.add(() => {
                onResetPos();
            });
            this.powersStack.addControl(resetBtn);
        }
    }

    private addPowerItem(id: string, name: string, _prep: string, _fire: string, _cost: string, _type: string, onCal?: any, onReset?: any, onSimulate?: any, highlighted: boolean = false): void {
        const container = new Rectangle(`p-guide-${id}`);
        container.width = "100%";
        container.heightInPixels = 110; // Reducido al quitar descripciones
        container.thickness = 0;
        container.paddingBottomInPixels = 15;
        container.background = highlighted ? "rgba(0,255,136,0.1)" : "transparent";
        this.powersStack.addControl(container);

        const pTitle = new TextBlock(`pt-${id}`, name.toUpperCase());
        pTitle.color = highlighted ? "#00ff88" : "#ffffff";
        pTitle.fontSize = 32; // Aumentado como se pidió
        pTitle.fontStyle = "bold";
        pTitle.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
        pTitle.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
        pTitle.left = "20px";
        container.addControl(pTitle);

        // Ya no renderizamos pGestures ni pInfo como se pidió

        // Buttons
        const calStack = new StackPanel(`cal-stack-${id}`);
        calStack.isVertical = false;
        calStack.width = "500px"; // Ajustado para el nuevo ancho del panel
        calStack.height = "65px";
        calStack.spacing = 10;
        calStack.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
        calStack.verticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
        container.addControl(calStack);

        const count1 = this.inputManager.getGSS().getGestureCount(this.getLabelForPower(id, "PREP"));
        const count2 = this.inputManager.getGSS().getGestureCount(this.getLabelForPower(id, "FIRE"));

        const btn1 = this.createCalBtn(`cal1-${id}`, `F1: ${count1}`, "#aa4400", () => { console.log(`[PGP] Cal1 click: ${id}`); onCal && onCal(id, "PREP"); }, 120);
        const btn2 = this.createCalBtn(`cal2-${id}`, `F2: ${count2}`, "#cc6622", () => { console.log(`[PGP] Cal2 click: ${id}`); onCal && onCal(id, "FIRE"); }, 120);
        const btnR = this.createCalBtn(`res-${id}`, "RESET", "#660000", () => { console.log(`[PGP] Reset click: ${id}`); onReset && onReset(id); }, 110);
        const btnS = this.createCalBtn(`sim-${id}`, "👁️ SIM", "#0055ff", () => { 
            console.log(`[PGP] Sim click: ${id}`);
            if (onSimulate) onSimulate(id);
            else console.warn(`[PGP] Sim callback is UNDEFINED for ${id}`);
        }, 120);

        calStack.addControl(btn1);
        calStack.addControl(btn2);
        calStack.addControl(btnR);
        calStack.addControl(btnS);
    }

    private createCalBtn(name: string, text: string, bg: string, action: () => void, width: number = 120): Button {
        const btn = Button.CreateSimpleButton(name, text);
        btn.widthInPixels = width;
        btn.height = "60px"; // Aumentado significativamente
        btn.color = "white";
        btn.fontSize = 20; // Aumentado para legibilidad VR
        btn.fontStyle = "bold";
        btn.background = bg;
        btn.cornerRadius = 8;
        // Usamos PointerDown en lugar de Click porque en VR el pequeño movimiento del control
        // al apretar el gatillo a menudo se interpreta como un "arrastre" (drag) por el ScrollViewer,
        // lo que anula el evento onPointerClickObservable.
        btn.onPointerDownObservable.add(action);
        return btn;
    }

    private getLabelForPower(powerId: string, phase: "PREP" | "FIRE"): string {
        const pId = powerId.toLowerCase();
        if (pId === "kamehameha") {
            return (phase === "PREP") ? "kamehameha_preparation" : "kamehameha_firing";
        } else if (pId === "genkidama") {
            return (phase === "PREP") ? "genkidama_preparation" : "genkidama_firing";
        } else if (pId === "ki_blast") {
            return (phase === "PREP") ? "ki_prep" : "ki_fire";
        } else if (pId === "recharge") {
            return (phase === "PREP") ? "recharge_prep" : "recharge_active";
        } else {
            const power = (powersConfig as any)[pId];
            return (power && power.vr_gestures) 
              ? ((phase === "PREP") ? power.vr_gestures.preparation : power.vr_gestures.firing)
              : `${pId}_${phase.toLowerCase()}`;
        }
    }

    public getChildrenCount(): number {
        return this.powersStack.children.length;
    }
}
