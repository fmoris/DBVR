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
    private toastTimeout: any = null;
    private statusBuffer: string[] = [];

    constructor(scene: Scene) {
        super(scene, {
            name: "vrHud-status",
            width: 0.85,
            height: 0.22,
            resolution: 512,
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
        this.statusBg.shadowColor = "rgba(255,255,255,0.2)";
        
        this.rootRect.addControl(this.statusBg);
        this.addScanlines(this.statusBg);

        this.statusText = new TextBlock("status-txt", "");
        this.statusText.color = "white";
        this.statusText.fontSize = 22;
        this.statusText.fontStyle = "bold";
        this.statusText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_CENTER;
        this.statusText.textVerticalAlignment = Control.VERTICAL_ALIGNMENT_CENTER;
        this.statusText.textWrapping = true;
        this.statusBg.addControl(this.statusText);
    }

    public updateStatus(text: string, color: string, bgColor: string, borderColor: string, thickness: number): void {
        this.statusText.text = text;
        this.statusText.color = color;
        this.statusBg.background = bgColor;
        this.statusBg.color = borderColor;
        this.statusBg.thickness = thickness;
        this.statusBg.isVisible = text !== "";
    }

    public showToast(message: string, color: string = "white", duration: number = 4000): void {
        this.statusBuffer.push(message);
        if (this.statusBuffer.length > 3) this.statusBuffer.shift();

        this.statusText.text = this.statusBuffer.join("\n");
        this.statusText.color = color;
        this.statusBg.isVisible = true;
        this.statusBg.background = "rgba(0,0,0,0.65)";

        if (this.toastTimeout) clearTimeout(this.toastTimeout);

        if (duration > 0) {
            this.toastTimeout = setTimeout(() => this.hideToast(), duration);
        }
    }

    public hideToast(): void {
        this.statusBg.background = "rgba(0,0,0,0.2)";
        this.statusBg.thickness = 0;
        this.statusBg.isVisible = false;

        setTimeout(() => {
            if (!this.toastTimeout) {
                this.statusBuffer = [];
                this.statusText.text = "";
            }
        }, 2000);

        if (this.toastTimeout) {
            clearTimeout(this.toastTimeout);
            this.toastTimeout = null;
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
        this.statusBg.isVisible = text !== "";
    }
}
