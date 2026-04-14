import { Game } from "./core/Game";
import { StartScreen } from "./ui/StartScreen";

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
  pointer-events: none;
  z-index: 9999;
  overflow: hidden;
  background: transparent;
`;
// pointer-events se activa solo cuando el juego está corriendo (no en StartScreen)
document.body.appendChild(xrOverlay);

let currentGame: Game | null = null;

function goToMenu(): void {
  // Inicializar o resetear el juego proactivamente
  if (currentGame) {
    currentGame.disposeAndExit().catch(() => {});
    currentGame = null;
  }
  
  // Creamos la instancia del juego inmediatamente para que empiece a cargar assets y XR
  currentGame = new Game(canvas, xrOverlay);
  currentGame.setMenuCallback(goToMenu);
  currentGame.initialize().catch(err => console.warn("[Game] Error en pre-inicialización:", err));

  // Desactivar pointer-events del overlay para que el StartScreen sea clickeable
  xrOverlay.style.pointerEvents = "none";
  new StartScreen(app, startGame, startGameVR);
}

function startGame(): void {
  if (!currentGame) return;
  // Activar pointer-events en el overlay solo cuando el juego está corriendo
  xrOverlay.style.pointerEvents = "auto";
  currentGame.start();
}

window.addEventListener('xr-init-error', (e: any) => {
    alert(`❌ ERROR WEBXR:\n${e.detail.message}\n\nRECUERDA: Si estás usando una IP privada, debes aceptar el certificado SSL en el navegador de las Quest 3 antes de entrar.`);
});

async function startGameVR(): Promise<void> {
  if (!currentGame) return;
  
  // IMPORTANTE: Para que WebXR acepte la sesión, la llamada debe ser SINCRÓNICA
  // al evento de activación del usuario. 
  try {
    // 1. Activar el overlay
    xrOverlay.style.pointerEvents = "auto";
    
    // 2. Iniciar la lógica de juego
    currentGame.start();
    
    // 3. Entrar en VR inmediatamente (ya debe estar inicializado por initialize())
    await currentGame.enterVR();
  } catch (err: any) {
    console.warn('[VR] No se pudo entrar en modo VR:', err);
    alert(`⚠️ FALLO AL ENTRAR EN VR:\n${err.message || err}\n\nPosibles causas:\n1. Certificado SSL no aceptado.\n2. Límite de sala (Guardian) no configurado.\n3. Navegador no compatible.`);
  }
}

// Arranque inicial
goToMenu();
