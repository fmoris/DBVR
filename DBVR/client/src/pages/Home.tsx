import { useRef, useState, useCallback } from "react";
import GameCanvas from "../game/GameCanvas";
import GameHUD from "../game/GameHUD";
import { BabylonScene, GameState } from "../game/BabylonScene";

const DEFAULT_STATE: GameState = {
  playerKi: 100,
  playerHealth: 100,
  enemyKi: 100,
  enemyHealth: 100,
  combatState: "neutral",
  isSlowMotion: false,
};

export default function Home() {
  const [gameState, setGameState] = useState<GameState>(DEFAULT_STATE);
  const [started, setStarted] = useState(false);
  const gameRef = useRef<BabylonScene | null>(null);

  const handleStateChange = useCallback((state: GameState) => {
    setGameState(state);
  }, []);

  return (
    <div
      style={{
        width: "100vw",
        height: "100vh",
        overflow: "hidden",
        background: "#050510",
        position: "relative",
      }}
    >
      {/* Pantalla de inicio */}
      {!started && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            background: "linear-gradient(180deg, #050510 0%, #0a0a2a 100%)",
            zIndex: 20,
            gap: 64,
          }}
        >
          <div style={{ textAlign: "center" }}>
            <h1
              style={{
                color: "#00ccff",
                fontSize: 48,
                fontFamily: "'Courier New', monospace",
                fontWeight: "bold",
                letterSpacing: 6,
                textShadow: "0 0 30px rgba(0,200,255,0.8), 0 0 60px rgba(0,100,255,0.4)",
                margin: 0,
              }}
            >
              VR KI COMBAT
            </h1>
            <p
              style={{
                color: "#4488aa",
                fontSize: 13,
                fontFamily: "'Courier New', monospace",
                letterSpacing: 4,
                marginTop: 12,
                textTransform: "uppercase",
              }}
            >
              Sistema de combate accion-reaccion
            </p>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            <button
              onClick={() => setStarted(true)}
              style={{
                padding: "14px 48px",
                background: "linear-gradient(135deg, #003366, #0066cc)",
                border: "2px solid #0099ff",
                borderRadius: 6,
                color: "#00ccff",
                fontSize: 16,
                fontFamily: "'Courier New', monospace",
                fontWeight: "bold",
                letterSpacing: 4,
                cursor: "pointer",
                textTransform: "uppercase",
                boxShadow: "0 0 20px rgba(0,150,255,0.5)",
                transition: "all 0.2s",
              }}
              onMouseEnter={(e) => {
                (e.target as HTMLButtonElement).style.boxShadow =
                  "0 0 40px rgba(0,150,255,0.8)";
              }}
              onMouseLeave={(e) => {
                (e.target as HTMLButtonElement).style.boxShadow =
                  "0 0 20px rgba(0,150,255,0.5)";
              }}
            >
              Iniciar Combate
            </button>
          </div>
        </div>
      )}

      {/* Escena del juego */}
      {started && (
        <>
          <GameCanvas onStateChange={handleStateChange} gameRef={gameRef} />
          <GameHUD state={gameState} gameRef={gameRef} />
        </>
      )}
    </div>
  );
}
