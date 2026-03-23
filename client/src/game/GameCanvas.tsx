import { useEffect, useRef, useState, useCallback } from "react";
import { BabylonScene, GameState } from "./BabylonScene";

interface GameCanvasProps {
  onStateChange?: (state: GameState) => void;
  gameRef?: React.MutableRefObject<BabylonScene | null>;
}

export default function GameCanvas({ onStateChange, gameRef }: GameCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<BabylonScene | null>(null);

  const handleStateChange = useCallback(
    (state: GameState) => {
      onStateChange?.(state);
    },
    [onStateChange]
  );

  useEffect(() => {
    if (!canvasRef.current) return;

    const scene = new BabylonScene(canvasRef.current, handleStateChange);
    sceneRef.current = scene;
    if (gameRef) gameRef.current = scene;

    return () => {
      scene.dispose();
      sceneRef.current = null;
      if (gameRef) gameRef.current = null;
    };
  }, [handleStateChange, gameRef]);

  return (
    <canvas
      ref={canvasRef}
      style={{
        width: "100%",
        height: "100%",
        display: "block",
        outline: "none",
        touchAction: "none",
      }}
      tabIndex={0}
    />
  );
}
