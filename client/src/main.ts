import { Game } from "./game/Game";
import { StartScreen } from "./game/StartScreen";

const app = document.getElementById("app")!;
app.style.cssText = "position:relative;width:100%;height:100%;overflow:hidden;background:#000;";

// Canvas persistente — BabylonJS lo reutiliza en cada partida
const canvas = document.createElement("canvas");
canvas.style.cssText = "width:100%;height:100%;display:block;outline:none;touch-action:none;";
canvas.tabIndex = 0;
app.appendChild(canvas);

let currentGame: Game | null = null;

function goToMenu(): void {
  // Limpiar el juego actual si existe
  if (currentGame) {
    currentGame.disposeAndExit().catch(() => {});
    currentGame = null;
  }

  // Mostrar de nuevo la pantalla de inicio
  new StartScreen(app, startGame);
}

function startGame(): void {
  currentGame = new Game(canvas);

  // Conectar el botón Menú del HUD al flujo de retorno
  currentGame.setMenuCallback(goToMenu);

  currentGame.start();
}

// Arranque inicial
goToMenu();
