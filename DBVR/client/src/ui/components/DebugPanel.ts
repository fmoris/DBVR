import { Scene } from "@babylonjs/core";
import {
    StackPanel,
    Rectangle,
    TextBlock,
    Control,
} from "@babylonjs/gui";
import { HUDPanel } from "./HUDPanel";

export class DebugPanel extends HUDPanel {
    private statusText: TextBlock;
    private leftHandText: TextBlock;
    private rightHandText: TextBlock;
    private gestureText: TextBlock;

    constructor(scene: Scene) {
        super(scene, {
            name: "vrHud-debug",
            width: 0.55,
            height: 0.4,
            resolution: 1024,
        });

        const bg = this.makePanelBg("rgba(10,10,20,0.85)", "#4444aa");
        this.addScanlines(bg);

        const title = new TextBlock("dbg-title", "🔍 HAND TRACKING DEBUG");
        title.color = "#8888ff";
        title.fontSize = 18;
        title.fontStyle = "bold";
        title.heightInPixels = 24;
        title.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        title.top = "8px";
        this.rootRect.addControl(title);

        const stack = new StackPanel("dbg-stack");
        stack.isVertical = true;
        stack.width = "94%";
        stack.height = "90%";
        stack.top = "30px";
        stack.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        this.rootRect.addControl(stack);

        this.statusText = this.createText(stack, "Esperando manos...", "#ffff00", 16, true);
        this.createSeparator(stack);
        this.createText(stack, "🤚 MANO IZQUIERDA:", "#00ccff", 14);
        this.leftHandText = this.createText(stack, "No detectada", "#aabbcc", 15, false, 75);
        this.createSeparator(stack);
        this.createText(stack, "🤚 MANO DERECHA:", "#ff8800", 14);
        this.rightHandText = this.createText(stack, "No detectada", "#aabbcc", 15, false, 75);
        this.createSeparator(stack);
        this.createText(stack, "👆 GESTO DETECTADO:", "#ffcc00", 14);
        this.gestureText = this.createText(stack, "NINGUNO", "#ffffff", 20, true, 56);
    }

    private createText(parent: StackPanel, text: string, color: string, fontSize: number, bold: boolean = false, height: number = 22): TextBlock {
        const txt = new TextBlock(undefined, text);
        txt.color = color;
        txt.fontSize = fontSize;
        if (bold) txt.fontStyle = "bold";
        txt.heightInPixels = height;
        txt.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
        txt.textWrapping = true;
        parent.addControl(txt);
        return txt;
    }

    private createSeparator(parent: StackPanel): void {
        const sep = new Rectangle();
        sep.width = "100%";
        sep.height = "2px";
        sep.background = "#333366";
        sep.thickness = 0;
        sep.paddingTop = "4px";
        sep.paddingBottom = "4px";
        parent.addControl(sep);
    }

    public updateDebug(status: string, statusColor: string, left: string, right: string, gesture: string): void {
        this.statusText.text = status;
        this.statusText.color = statusColor;
        this.leftHandText.text = left;
        this.rightHandText.text = right;
        this.gestureText.text = gesture;
    }
}
