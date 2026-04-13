import { Scene } from "@babylonjs/core";
import {
    Rectangle,
    TextBlock,
    Control,
} from "@babylonjs/gui";
import { HUDPanel } from "./HUDPanel";

export class StatusPanel extends HUDPanel {
    private statusBg: Rectangle;
    private statusText: TextBlock;
    private logText: TextBlock;
    private toastTimeout: any = null;
    private statusBuffer: string[] = [];

    constructor(scene: Scene) {
        super(scene, {
            name: "vrHud-status",
            width: 1.0,
            height: 0.35,
            resolution: 1024,
        });

        this.statusBg = new Rectangle("status-bg");
        this.statusBg.width = "100%";
        this.statusBg.height = "100%";
        this.statusBg.cornerRadius = 14;
        this.statusBg.background = "rgba(0,0,0,0.65)";
        this.statusBg.color = "rgba(255,255,255,0.2)";
        this.statusBg.thickness = 1.5;
        this.statusBg.isVisible = false;
        
        // Glow effect
        this.statusBg.shadowBlur = 10;
        this.statusBg.shadowColor = "rgba(0,200,255,0.4)";
        
        this.rootRect.addControl(this.statusBg);
        this.addScanlines(this.statusBg);

        // --- 1. Estado Primario (Arriba, Grande) ---
        this.statusText = new TextBlock("primary-status", "");
        this.statusText.color = "cyan";
        this.statusText.fontSize = 28;
        this.statusText.fontStyle = "bold";
        this.statusText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
        this.statusText.textVerticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        this.statusText.paddingTop = "10px";
        this.statusBg.addControl(this.statusText);

        // --- 2. Log de Notificaciones (Abajo, Lista) ---
        this.logText = new TextBlock("log-txt", "");
        this.logText.color = "rgba(255,255,255,0.8)";
        this.logText.fontSize = 18;
        this.logText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
        this.logText.textVerticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        this.logText.paddingTop = "70px"; // Debajo del primario
        this.logText.lineSpacing = "5px";
        this.statusBg.addControl(this.logText);
    }

    public updateStatus(text: string, color: string, bgColor: string, borderColor: string, thickness: number): void {
        this.statusText.text = text.toUpperCase();
        this.statusText.color = color;
        this.statusBg.background = bgColor;
        this.statusBg.color = borderColor;
        this.statusBg.thickness = thickness;
        this.updatePanelVisibility();
    }

    public showToast(message: string, color: string = "white", duration: number = 5000): void {
        this.statusBuffer.push(message);
        if (this.statusBuffer.length > 3) this.statusBuffer.shift();

        this.logText.text = this.statusBuffer.join("\n");
        // this.logText.color = color; // Podemos usar colores por linea si lo hacemos mas complejo, por ahora global
        
        this.updatePanelVisibility();

        if (this.toastTimeout) clearTimeout(this.toastTimeout);
        if (duration > 0) {
            this.toastTimeout = setTimeout(() => this.hideToast(), duration);
        }
    }

    public hideToast(): void {
        this.statusBuffer = [];
        this.logText.text = "";
        this.updatePanelVisibility();
        
        if (this.toastTimeout) {
            clearTimeout(this.toastTimeout);
            this.toastTimeout = null;
        }
    }

    private updatePanelVisibility(): void {
        const hasContent = (this.statusText.text !== "" || this.logText.text !== "");
        this.statusBg.isVisible = hasContent;
        if (!hasContent) {
           this.statusBg.background = "rgba(0,0,0,0.2)";
        }
    }

    public setStatusBgVisible(visible: boolean): void {
        this.statusBg.isVisible = visible;
    }

    public setStatusBgBackground(color: string): void {
        this.statusBg.background = color;
    }

    public setStatusText(text: string): void {
        this.statusText.text = text;
        this.updatePanelVisibility();
    }
}
