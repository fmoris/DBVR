import { Game } from "./game/Game";
import { StartScreen } from "./game/StartScreen";

const app = document.getElementById("app")!;
app.style.cssText = "position:relative;width:100%;height:100%;overflow:hidden;background:#000;";

// Canvas persistente — BabylonJS lo reutiliza en cada partida
const canvas = document.createElement("canvas");
canvas.style.cssText = "width:100%;height:100%;display:block;outline:none;touch-action:none;";
canvas.tabIndex = 0;
app.appendChild(canvas);

// Contenedor DOM Overlay — se proyecta sobre el visor XR cuando se activa dom-overlay
// DEBE existir antes de que se cree el Game, y DEBE ser hijo directo del body o del app
const xrOverlay = document.createElement("div");
xrOverlay.id = "xr-overlay";
xrOverlay.style.cssText = `
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 100;
`;
app.appendChild(xrOverlay);

let currentGame: Game | null = null;

function goToMenu(): void {
  if (currentGame) {
    currentGame.disposeAndExit().catch(() => {});
    currentGame = null;
  }
  new StartScreen(app, startGame);
}

function startGame(): void {
  currentGame = new Game(canvas, xrOverlay);
  currentGame.setMenuCallback(goToMenu);
  currentGame.start();
}

// Arranque inicial
goToMenu();
