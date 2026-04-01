import { GameState } from "./BabylonScene";
import { BabylonScene } from "./BabylonScene";

interface GameHUDProps {
  state: GameState;
  gameRef: React.MutableRefObject<BabylonScene | null>;
}

const STATE_LABELS: Record<GameState["combatState"], string> = {
  neutral: "Neutral",
  charging: "Cargando...",
  attacking: "Atacando",
  defending: "Bloqueando",
  slowMotion: "Camara Lenta",
  hit: "Impacto",
};

const STATE_COLORS: Record<GameState["combatState"], string> = {
  neutral: "#00ff88",
  charging: "#ffcc00",
  attacking: "#ff6600",
  defending: "#00aaff",
  slowMotion: "#cc44ff",
  hit: "#ff2222",
};

export default function GameHUD({ state, gameRef }: GameHUDProps) {
  const kiPercent = Math.max(0, Math.min(100, state.playerKi));
  const healthPercent = Math.max(0, Math.min(100, state.playerHealth));
  const enemyKiPercent = Math.max(0, Math.min(100, state.enemyKi));
  const enemyHealthPercent = Math.max(0, Math.min(100, state.enemyHealth));
  const stateColor = STATE_COLORS[state.combatState];

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        fontFamily: "'Courier New', monospace",
        userSelect: "none",
      }}
    >
      {/* Estado de combate */}
      {state.isSlowMotion && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            border: "3px solid rgba(180, 60, 255, 0.4)",
            pointerEvents: "none",
            boxShadow: "inset 0 0 60px rgba(180, 60, 255, 0.15)",
          }}
        />
      )}

      {/* Indicador de estado */}
      <div
        style={{
          position: "absolute",
          top: 20,
          left: "50%",
          transform: "translateX(-50%)",
          color: stateColor,
          fontSize: 13,
          fontWeight: "bold",
          letterSpacing: 3,
          textTransform: "uppercase",
          textShadow: `0 0 12px ${stateColor}`,
          background: "rgba(0,0,0,0.6)",
          padding: "4px 16px",
          borderRadius: 4,
          border: `1px solid ${stateColor}44`,
        }}
      >
        {STATE_LABELS[state.combatState]}
        {state.isSlowMotion && " · CAMARA LENTA"}
      </div>

      {/* HUD inferior */}
      <div
        style={{
          position: "absolute",
          bottom: 40,
          left: "50%",
          transform: "translateX(-50%)",
          display: "flex",
          gap: 60,
          alignItems: "flex-end",
        }}
      >
        {/* Barras del jugador */}
        <div style={{ display: "flex", flexDirection: "column", gap: 8, alignItems: "center" }}>
          <span style={{ color: "#aaa", fontSize: 10, letterSpacing: 2, textTransform: "uppercase" }}>
            Tu KI
          </span>
          <div
            style={{
              width: 180,
              height: 12,
              background: "rgba(0,0,0,0.7)",
              border: "1px solid #00ff88",
              borderRadius: 3,
              overflow: "hidden",
              boxShadow: "0 0 8px rgba(0,255,136,0.3)",
            }}
          >
            <div
              style={{
                height: "100%",
                width: `${kiPercent}%`,
                background: "linear-gradient(90deg, #00aa55, #00ff88)",
                transition: "width 0.15s ease",
                boxShadow: "0 0 6px rgba(0,255,136,0.8)",
              }}
            />
          </div>
          <span style={{ color: "#aaa", fontSize: 10, letterSpacing: 2, textTransform: "uppercase" }}>
            Salud
          </span>
          <div
            style={{
              width: 180,
              height: 8,
              background: "rgba(0,0,0,0.7)",
              border: "1px solid #ff4444",
              borderRadius: 3,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                height: "100%",
                width: `${healthPercent}%`,
                background: "linear-gradient(90deg, #aa0000, #ff4444)",
                transition: "width 0.15s ease",
              }}
            />
          </div>
        </div>

        {/* Controles */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 6,
            alignItems: "center",
            pointerEvents: "auto",
          }}
        >
          <button
            onClick={() => gameRef.current?.launchAttack()}
            disabled={state.playerKi < 20}
            style={{
              padding: "8px 20px",
              background:
                state.playerKi >= 20
                  ? "linear-gradient(135deg, #003366, #0066cc)"
                  : "rgba(30,30,30,0.8)",
              border: `1px solid ${state.playerKi >= 20 ? "#0099ff" : "#333"}`,
              borderRadius: 4,
              color: state.playerKi >= 20 ? "#00ccff" : "#555",
              fontSize: 11,
              fontFamily: "inherit",
              fontWeight: "bold",
              letterSpacing: 2,
              cursor: state.playerKi >= 20 ? "pointer" : "not-allowed",
              textTransform: "uppercase",
              boxShadow: state.playerKi >= 20 ? "0 0 10px rgba(0,150,255,0.4)" : "none",
              transition: "all 0.1s",
            }}
          >
            [A] Atacar
          </button>
          <button
            onClick={() => gameRef.current?.activateBlock()}
            disabled={state.playerKi < 10}
            style={{
              padding: "8px 20px",
              background:
                state.playerKi >= 10
                  ? "linear-gradient(135deg, #003322, #006644)"
                  : "rgba(30,30,30,0.8)",
              border: `1px solid ${state.playerKi >= 10 ? "#00ff88" : "#333"}`,
              borderRadius: 4,
              color: state.playerKi >= 10 ? "#00ff88" : "#555",
              fontSize: 11,
              fontFamily: "inherit",
              fontWeight: "bold",
              letterSpacing: 2,
              cursor: state.playerKi >= 10 ? "pointer" : "not-allowed",
              textTransform: "uppercase",
              transition: "all 0.1s",
            }}
          >
            [S] Bloquear
          </button>
          <button
            onClick={() => gameRef.current?.rechargeKi()}
            style={{
              padding: "8px 20px",
              background: "linear-gradient(135deg, #330033, #660066)",
              border: "1px solid #cc44ff",
              borderRadius: 4,
              color: "#cc44ff",
              fontSize: 11,
              fontFamily: "inherit",
              fontWeight: "bold",
              letterSpacing: 2,
              cursor: "pointer",
              textTransform: "uppercase",
              boxShadow: "0 0 8px rgba(180,60,255,0.3)",
              transition: "all 0.1s",
            }}
          >
            [R] Recargar KI
          </button>
        </div>

        {/* Barras del enemigo */}
        <div style={{ display: "flex", flexDirection: "column", gap: 8, alignItems: "center" }}>
          <span style={{ color: "#aaa", fontSize: 10, letterSpacing: 2, textTransform: "uppercase" }}>
            KI Enemigo
          </span>
          <div
            style={{
              width: 180,
              height: 12,
              background: "rgba(0,0,0,0.7)",
              border: "1px solid #ff4444",
              borderRadius: 3,
              overflow: "hidden",
              boxShadow: "0 0 8px rgba(255,68,68,0.3)",
            }}
          >
            <div
              style={{
                height: "100%",
                width: `${enemyKiPercent}%`,
                background: "linear-gradient(90deg, #aa0000, #ff4444)",
                transition: "width 0.15s ease",
                boxShadow: "0 0 6px rgba(255,68,68,0.8)",
              }}
            />
          </div>
          <span style={{ color: "#aaa", fontSize: 10, letterSpacing: 2, textTransform: "uppercase" }}>
            Salud
          </span>
          <div
            style={{
              width: 180,
              height: 8,
              background: "rgba(0,0,0,0.7)",
              border: "1px solid #ff8800",
              borderRadius: 3,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                height: "100%",
                width: `${enemyHealthPercent}%`,
                background: "linear-gradient(90deg, #884400, #ff8800)",
                transition: "width 0.15s ease",
              }}
            />
          </div>
        </div>
      </div>

      {/* Debug info */}
      <div
        style={{
          position: "absolute",
          top: 20,
          left: 20,
          color: "#00ff88",
          fontSize: 11,
          background: "rgba(0,0,0,0.75)",
          padding: "8px 12px",
          borderRadius: 4,
          border: "1px solid #00ff8844",
          lineHeight: 1.8,
        }}
      >
        <div>KI: {state.playerKi.toFixed(0)}/100</div>
        <div>Salud: {state.playerHealth.toFixed(0)}/100</div>
        <div>Estado: {state.combatState}</div>
        <div style={{ marginTop: 6, fontSize: 10, color: "#00aa55" }}>
          A=Ataque · S=Bloqueo · R=Recarga
        </div>
      </div>
    </div>
  );
}
