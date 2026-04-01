import { useState } from "react";

interface Gestureinfo {
  title: string;
  description: string;
  image?: string;
  icon?: string;
}

const GESTURES: Gestureinfo[] = [
  {
    title: "CARGA DE KI",
    description: "Junta ambas manos frente al pecho para acumular energía.",
    image: "vr_gesture_charging", 
  },
  {
    title: "ATAQUE RÁPIDO",
    description: "Empuja ambas manos hacia adelante con fuerza para lanzar ráfagas.",
    image: "vr_gesture_attacking",
  },
  {
    title: "BLOQUEO",
    description: "Cruza las muñecas frente a tu cara en forma de 'X' para protegerte.",
    icon: "🛡️",
  },
  {
    title: "RECARGA GLOBAL",
    description: "Abre los brazos hacia los lados para absorber energía del ambiente.",
    image: "vr_gesture_recharging",
  },
];

interface VRGestureTutorialProps {
  onClose: () => void;
}

export default function VRGestureTutorial({ onClose }: VRGestureTutorialProps) {
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 100,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "rgba(0,0,0,0.85)",
        backdropFilter: "blur(8px)",
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: "90%",
          maxWidth: 900,
          background: "rgba(10, 20, 40, 0.7)",
          border: "1px solid rgba(0, 200, 255, 0.3)",
          borderRadius: 16,
          padding: 40,
          boxShadow: "0 0 50px rgba(0, 150, 255, 0.2)",
          position: "relative",
          display: "flex",
          flexDirection: "column",
          gap: 32,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <button
          onClick={onClose}
          style={{
            position: "absolute",
            top: 20,
            right: 20,
            background: "none",
            border: "none",
            color: "#6688aa",
            fontSize: 24,
            cursor: "pointer",
          }}
        >
          ✕
        </button>

        <div style={{ textAlign: "center" }}>
          <h2
            style={{
              color: "#00ccff",
              fontSize: 32,
              fontFamily: "'Courier New', monospace",
              letterSpacing: 4,
              margin: 0,
              textShadow: "0 0 20px rgba(0,200,255,0.5)",
            }}
          >
            TUTORIAL DE GESTOS VR
          </h2>
          <p style={{ color: "#4488aa", fontSize: 14, marginTop: 8 }}>
            RECONOCIMIENTO DE MOVIMIENTOS EN TIEMPO REAL
          </p>
        </div>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))",
            gap: 24,
          }}
        >
          {GESTURES.map((g, i) => (
            <div
              key={i}
              style={{
                background: "rgba(0, 40, 80, 0.3)",
                border: "1px solid rgba(0, 200, 255, 0.1)",
                borderRadius: 12,
                padding: 20,
                textAlign: "center",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 16,
                transition: "transform 0.2s",
              }}
            >
              <div
                style={{
                  width: 140,
                  height: 140,
                  background: "rgba(0,0,0,0.5)",
                  borderRadius: 8,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  overflow: "hidden",
                  border: "1px solid rgba(0, 200, 255, 0.2)",
                }}
              >
                {g.image ? (
                  <img
                    src={`/${g.image}.png`}
                    alt={g.title}
                    style={{ width: "100%", height: "100%", objectFit: "cover" }}
                  />
                ) : (
                  <span style={{ fontSize: 64 }}>{g.icon}</span>
                )}
              </div>
              <div>
                <h3
                  style={{
                    color: "#00ff88",
                    fontSize: 14,
                    letterSpacing: 2,
                    margin: "0 0 8px 0",
                  }}
                >
                  {g.title}
                </h3>
                <p style={{ color: "#88bbcc", fontSize: 12, lineHeight: 1.5, margin: 0 }}>
                  {g.description}
                </p>
              </div>
            </div>
          ))}
        </div>

        <div style={{ textAlign: "center", marginTop: 12 }}>
          <button
            onClick={onClose}
            style={{
              padding: "12px 32px",
              background: "transparent",
              border: "1px solid #00ccff",
              borderRadius: 4,
              color: "#00ccff",
              cursor: "pointer",
              fontFamily: "'Courier New', monospace",
              fontSize: 14,
              letterSpacing: 2,
              textTransform: "uppercase",
            }}
          >
            Entendido
          </button>
        </div>
      </div>
    </div>
  );
}
