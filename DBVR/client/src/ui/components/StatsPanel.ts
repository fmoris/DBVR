import { Scene } from "@babylonjs/core";
import {
    StackPanel,
    Rectangle,
    TextBlock,
    Control,
    Ellipse,
    Image,
} from "@babylonjs/gui";
import { HUDPanel } from "./HUDPanel";

export class StatsPanel extends HUDPanel {
    private npBar!: Rectangle;
    private npText!: TextBlock;
    private kiBar!: Rectangle;
    private kiText!: TextBlock;
    private estadoText!: TextBlock;

    constructor(scene: Scene, isPlayer: boolean) {
        super(scene, {
            name: isPlayer ? "vrHud-player" : "vrHud-enemy",
            width: 0.75,
            height: 0.35,
            resolution: 512,
        });

        const bgColor = isPlayer ? "rgba(0,15,40,0.75)" : "rgba(40,5,5,0.75)";
        const borderColor = isPlayer ? "rgba(0,220,255,0.9)" : "rgba(255,80,80,0.9)";
        
        const bg = this.makePanelBg(bgColor, borderColor);
        this.addScanlines(bg);
        this.buildLayout(isPlayer);
    }

    private buildLayout(isPlayer: boolean): void {
        const mainStack = new StackPanel("main-stack");
        mainStack.isVertical = false;
        mainStack.width = "100%";
        mainStack.height = "100%";
        mainStack.spacing = 12;
        mainStack.paddingLeftInPixels = 12;
        mainStack.paddingRightInPixels = 12;
        mainStack.paddingTopInPixels = 10;
        mainStack.paddingBottomInPixels = 10;
        this.rootRect.addControl(mainStack);

        // Avatar
        this.createAvatarCircle(mainStack, isPlayer);

        // Stats Stack
        const statsStack = new StackPanel("stats-stack");
        statsStack.isVertical = true;
        statsStack.width = "70%";
        statsStack.height = "100%";
        statsStack.spacing = 8;
        mainStack.addControl(statsStack);

        // NP Bar
        const npColor = isPlayer ? "#00ff88" : "#ff4444";
        const npGroup = this.makeBarGroup(statsStack, "NP", npColor);
        this.npBar = npGroup.fill;
        this.npText = npGroup.valueText;

        // KI Bar
        const kiColor = isPlayer ? "#00ccff" : "#ff6600";
        const kiGroup = this.makeBarGroup(statsStack, "KI", kiColor);
        this.kiBar = kiGroup.fill;
        this.kiText = kiGroup.valueText;

        // Status
        const estadoRow = new StackPanel("estado-row");
        estadoRow.isVertical = false;
        estadoRow.width = "100%";
        estadoRow.heightInPixels = 24;
        estadoRow.spacing = 8;
        statsStack.addControl(estadoRow);

        const estadoLabel = new TextBlock("estado-label", "ESTADO");
        estadoLabel.color = isPlayer ? "#00ff88" : "#ff4444";
        estadoLabel.fontSize = 14;
        estadoLabel.fontStyle = "bold";
        estadoLabel.width = "60px";
        estadoLabel.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
        estadoRow.addControl(estadoLabel);

        this.estadoText = new TextBlock("estado-value", "NEUTRAL");
        this.estadoText.color = isPlayer ? "#00ff88" : "#ff4444";
        this.estadoText.fontSize = 14;
        this.estadoText.fontStyle = "bold";
        this.estadoText.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
        estadoRow.addControl(this.estadoText);
    }

    private createAvatarCircle(parent: StackPanel, isPlayer: boolean): void {
        const borderColor = isPlayer ? "#00ccff" : "#ff4444";
        const glowColor = isPlayer ? "rgba(0,200,255,0.4)" : "rgba(255,60,60,0.4)";

        const glow = new Ellipse("avatar-glow");
        glow.width = "90px";
        glow.height = "90px";
        glow.color = "transparent";
        glow.thickness = 0;
        glow.shadowBlur = 15;
        glow.shadowColor = glowColor;
        parent.addControl(glow);

        const border = new Ellipse("avatar-border");
        border.width = "84px";
        border.height = "84px";
        border.color = borderColor;
        border.thickness = 2.5;
        border.background = "transparent";
        glow.addControl(border);

        const img = new Image("avatar-img", ""); // URL se pondrá después o se pasará
        img.stretch = Image.STRETCH_UNIFORM;
        border.addControl(img);
        // Guardar referencia si necesitamos cambiar la imagen dinámicamente
        (this as any).avatarImg = img;
    }

    public updateAvatar(url: string): void {
        const img = (this as any).avatarImg as Image;
        if (img) img.source = url;
    }

    private makeBarGroup(parent: StackPanel, label: string, color: string): { fill: Rectangle; valueText: TextBlock } {
        const row = new StackPanel(`${label}-row`);
        row.isVertical = false;
        row.width = "100%";
        row.heightInPixels = 20;
        row.spacing = 4;
        parent.addControl(row);

        const barBg = new Rectangle(`${label}-bg`);
        barBg.width = "85%";
        barBg.heightInPixels = 16; // Un poco más gruesa
        barBg.cornerRadius = 4;
        barBg.background = "rgba(0,0,0,0.6)";
        barBg.thickness = 1.5;
        barBg.color = "rgba(255,255,255,0.15)";
        row.addControl(barBg);

        const fill = new Rectangle(`${label}-fill`);
        fill.width = "100%";
        fill.heightInPixels = 16;
        fill.cornerRadius = 4;
        fill.background = color;
        fill.thickness = 0;
        fill.shadowBlur = 8; // Efecto de glow en la barra
        fill.shadowColor = color;
        fill.horizontalAlignment = Control.HORIZONTAL_ALIGNMENT_LEFT;
        barBg.addControl(fill);

        const val = new TextBlock(`${label}-val`, "0");
        val.color = color;
        val.fontSize = 12;
        val.fontStyle = "bold";
        val.width = "15%";
        val.textHorizontalAlignment = Control.HORIZONTAL_ALIGNMENT_RIGHT;
        row.addControl(val);

        return { fill, valueText: val };
    }

    public updateStats(np: number, npPct: number, npColor: string, ki: number, kiPct: number, estado: string, estadoColor: string): void {
        this.npBar.width = `${Math.max(0, Math.min(100, npPct * 100))}%`;
        this.npBar.background = npColor;
        this.npText.text = np.toLocaleString();

        this.kiBar.width = `${Math.max(0, Math.min(100, kiPct))}%`;
        this.kiText.text = ki.toFixed(0);

        this.estadoText.text = estado;
        this.estadoText.color = estadoColor;
    }
}
