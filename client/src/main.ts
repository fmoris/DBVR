import { Game } from "./game/Game";
import { StartScreen } from "./game/StartScreen";

const app = document.getElementById("app")!;
app.style.cssText = "position:relative;width:100%;height:100%;overflow:hidden;background:#000;";

// Canvas persistente — BabylonJS lo reutiliza en cada partida
const canvas = document.createElement("canvas");
canvas.style.cssText = "width:100%;height:100%;display:block;outline:none;touch-action:none;";
canvas.tabIndex = 0;
app.appendChild(canvas);

// Contenedor DOM Overlay — la especificación WebXR dom-overlay requiere que el elemento
// sea hijo DIRECTO del <body> para que el navegador de Quest lo proyecte sobre el visor.
// NO puede ser hijo de un div anidado.
const xrOverlay = document.createElement("div");
xrOverlay.id = "xr-overlay";
// La spec dom-overlay de WebXR requiere:
// 1. El elemento sea hijo directo de <body> ✓
// 2. pointer-events:auto en el elemento raiz (no none) para que Quest lo procese
// 3. background con algun valor (aunque sea transparente) para que sea renderizado
// Los hijos pueden tener pointer-events:none individualmente
xrOverlay.style.cssText = `
  position: fixed;
  inset: 0;
  pointer-events: auto;
  z-index: 9999;
  overflow: hidden;
  background: transparent;
`;
document.body.appendChild(xrOverlay);

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
