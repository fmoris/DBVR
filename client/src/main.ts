import { Game } from "./game/Game";

const app = document.getElementById("app")!;

// Crear canvas para BabylonJS
const canvas = document.createElement("canvas");
canvas.style.cssText = "width:100%;height:100%;display:block;outline:none;touch-action:none;";
canvas.tabIndex = 0;
app.appendChild(canvas);

// Iniciar el juego
const game = new Game(canvas);
game.start();
