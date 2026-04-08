import { Scene } from "@babylonjs/core";
import {
    StackPanel,
    TextBlock,
    Control,
    Button,
} from "@babylonjs/gui";
import { HUDPanel } from "./HUDPanel";

export class ActionPanel extends HUDPanel {
    private titleText: TextBlock;
    private actionRow: StackPanel;

    constructor(scene: Scene, isAttack: boolean) {
        super(scene, {
            name: isAttack ? "vrHud-attack" : "vrHud-defense",
            width: isAttack ? 0.90 : 0.70,
            height: 0.18,
            resolution: 1024,
        });

        const bgColor = isAttack ? "rgba(20,5,0,0.75)" : "rgba(0,20,10,0.75)";
        const borderColor = isAttack ? "#aa4400" : "#00aa44";
        
        const bg = this.makePanelBg(bgColor, borderColor);
        this.addScanlines(bg);

        this.titleText = new TextBlock("action-title", isAttack ? "⚔ ATAQUES" : "🛡 DEFENSAS");
        this.titleText.color = isAttack ? "#ff8800" : "#00ff88";
        this.titleText.fontSize = 22;
        this.titleText.fontStyle = "bold";
        this.titleText.heightInPixels = 28;
        this.titleText.verticalAlignment = Control.VERTICAL_ALIGNMENT_TOP;
        this.titleText.top = "8px";
        this.rootRect.addControl(this.titleText);

        this.actionRow = new StackPanel("action-row");
        this.actionRow.isVertical = false;
        this.actionRow.width = "100%";
        this.actionRow.height = "70%";
        this.actionRow.spacing = 10;
        this.actionRow.verticalAlignment = Control.VERTICAL_ALIGNMENT_BOTTOM;
        this.rootRect.addControl(this.actionRow);
    }

    public setTitle(text: string, color?: string): void {
        this.titleText.text = text;
        if (color) this.titleText.color = color;
    }

    public clearActions(): void {
        this.actionRow.getDescendants().forEach(c => c.dispose());
    }

    public addAction(key: string, label: string, color: string, bgColor: string, action: () => void, cost: number = 0): Button {
        const btn = Button.CreateSimpleButton(`btn-${label}`, `[${key}]\n${label}`);
        (btn as any).kiCost = cost;
        btn.width = "118px";
        btn.heightInPixels = 88;
        btn.color = color;
        btn.background = bgColor;
        btn.cornerRadius = 10;
        btn.fontSize = 20;
        btn.thickness = 2;
        (btn as any).fontStyle = "bold";
        btn.onPointerClickObservable.add(action);

        btn.onPointerEnterObservable.add(() => {
            btn.background = color + "33";
            btn.thickness = 3;
        });
        btn.onPointerOutObservable.add(() => {
            btn.background = bgColor;
            btn.thickness = 2;
        });

        this.actionRow.addControl(btn);
        return btn;
    }

    public filterByKi(ki: number): void {
        const btns = this.actionRow.getDescendants();
        for (const ctrl of btns) {
            if (ctrl instanceof Button) {
                const cost = (ctrl as any).kiCost || 0;
                ctrl.isVisible = ki >= cost;
            }
        }
    }
}
