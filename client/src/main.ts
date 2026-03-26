import { Game } from "./game/Game";
import { StartScreen } from "./game/StartScreen";

const app = document.getElementById("app")!;

// Contenedor principal con posicion relativa para overlays
app.style.cssText = "position:relative;width:100%;height:100%;overflow:hidden;background:#000;";

// Crear canvas para BabylonJS (oculto hasta que inicie el juego)
const canvas = document.createElement("canvas");
canvas.style.cssText = "width:100%;height:100%;display:block;outline:none;touch-action:none;";
canvas.tabIndex = 0;
app.appendChild(canvas);

// Mostrar pantalla de inicio primero
new StartScreen(app, () => {
  // Callback: el usuario presiono Iniciar o termino el tutorial
  const game = new Game(canvas);
  game.start();
});
