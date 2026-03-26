/**
 * StartScreen
 * Pantalla de inicio con navegacion entre: Inicio, Tutorial, Changelog
 */

const CHANGELOG = [
  {
    version: "0.3.0",
    date: "Mar 2026",
    changes: [
      "Sistema de Nivel de Poder (NP) reemplaza HP",
      "Cinco rangos de poder: Debilitado, Normal, Elevado, Dominante, Trascendente",
      "Sistema de Comeback con Transformacion y Ataque Desesperado",
      "Fluctuacion organica del NP durante el combate",
      "GestureRecognizer con 6 tipos de gestos para WebXR",
      "WebXRManager con soporte para hand tracking Meta Quest",
    ],
  },
  {
    version: "0.2.0",
    date: "Mar 2026",
    changes: [
      "Ataque de KI cargado (puno cerrado -> abrir para lanzar)",
      "Ataques especiales: Kamehameha y Final Flash con secuencias de movimiento",
      "Defensas: bloqueo, desvio, choque y esquive",
      "Camara lenta al recibir ataques especiales",
      "HUD con barras de KI y Nivel de Poder dinamicas",
      "Eliminacion de React, frontend en TypeScript puro con BabylonJS",
    ],
  },
  {
    version: "0.1.0",
    date: "Mar 2026",
    changes: [
      "Proyecto base con Vite + TypeScript + BabylonJS",
      "Escena 3D en primera persona con enemigo y aura de particulas",
      "Sistema de KI con regeneracion pasiva",
      "Ataque basico de KI (proyectil azul)",
      "Bloqueo basico y recarga de KI",
      "Controles de teclado para testing sin VR",
      "Integracion WebXR inicial para Meta Quest",
    ],
  },
];

const TUTORIAL_STEPS = [
  {
    title: "Bienvenido a VR KI Combat",
    icon: "⚡",
    content: "Un juego de combate en primera persona inspirado en Yu Yu Hakusho. Cada accion que realizas desencadena una reaccion del rival. El tiempo se relentiza para darte la oportunidad de responder.",
    controls: [],
  },
  {
    title: "El KI — Tu energia vital",
    icon: "🔵",
    content: "El KI es tu recurso principal. Cada ataque, defensa y accion consume KI. Si se agota, quedas vulnerable. Se regenera lentamente en estado neutral o puedes recargarlo activamente.",
    controls: [
      { key: "R", action: "Recargar KI activamente (te deja vulnerable)" },
      { key: "Espera", action: "Regeneracion pasiva lenta en estado neutral" },
    ],
  },
  {
    title: "Nivel de Poder (NP)",
    icon: "🔥",
    content: "No hay vida ni HP. El combate se decide por el Nivel de Poder. Entre mas alto tu NP, mas fuerte eres y mas resistente a los ataques. La victoria llega cuando la diferencia de NP entre ambos supera 50 puntos.",
    controls: [
      { key: "0-20%", action: "Debilitado: vulnerable a todo" },
      { key: "21-50%", action: "Normal: estado base" },
      { key: "51-75%", action: "Elevado: inmune a ataques basicos" },
      { key: "76-90%", action: "Dominante: inmune a ataques con poca carga" },
      { key: "91-100%", action: "Trascendente: solo ataques a maxima carga te afectan" },
    ],
  },
  {
    title: "Ataques de KI",
    icon: "💥",
    content: "Tienes dos tipos de ataque a distancia. El basico es rapido y molesta al rival. El cargado interrumpe ataques especiales y provoca camara lenta al impactar.",
    controls: [
      { key: "A", action: "Ataque basico de KI (rapido, bajo dano)" },
      { key: "W (mantener)", action: "Cargar ataque de KI (puno cerrado)" },
      { key: "W (soltar)", action: "Lanzar ataque cargado (abrir puno)" },
    ],
  },
  {
    title: "Ataques Especiales",
    icon: "🌊",
    content: "Los ataques especiales requieren una secuencia de movimientos y un tiempo minimo de carga. Mas tiempo de carga = mas dano. Al lanzarlos, el tiempo se relentiza para el rival.",
    controls: [
      { key: "1 → esperar → 1", action: "Kamehameha (ambas manos al costado, mantener 2s, empujar)" },
      { key: "2 → 2 → esperar → 2", action: "Final Flash (cruz, juntar, mantener 3s, lanzar en V)" },
    ],
  },
  {
    title: "Defensas",
    icon: "🛡️",
    content: "Cuando el rival ataca, el tiempo se relentiza para que puedas reaccionar. Elige tu defensa segun el tipo de ataque recibido.",
    controls: [
      { key: "S", action: "Bloqueo: reduce dano 60%, consume KI medio" },
      { key: "D", action: "Esquive: evita todo el dano, ventana muy corta" },
    ],
  },
  {
    title: "En VR — Meta Quest",
    icon: "🥽",
    content: "Con el Meta Quest 3, tus manos reales controlan el juego. Los gestos fisicos activan las acciones. El hand tracking detecta la posicion de tus articulaciones en tiempo real.",
    controls: [
      { key: "Palma abierta adelante", action: "Ataque basico de KI" },
      { key: "Puno cerrado adelante", action: "Iniciar carga de KI" },
      { key: "Abrir puno", action: "Lanzar ataque cargado" },
      { key: "Brazos cruzados", action: "Bloqueo" },
      { key: "Brazos a los lados", action: "Recarga de KI" },
    ],
  },
  {
    title: "Listo para combatir",
    icon: "⚔️",
    content: "Recuerda: el combate es un dialogo de acciones y reacciones. Varia tus ataques, administra tu KI y aprovecha la camara lenta para tomar decisiones. ¡El poder mas alto gana!",
    controls: [],
  },
];

type Screen = "main" | "tutorial" | "changelog";

export class StartScreen {
  private overlay: HTMLDivElement;
  private currentScreen: Screen = "main";
  private tutorialStep = 0;
  private onStart: () => void;

  constructor(parent: HTMLElement, onStart: () => void) {
    this.onStart = onStart;
    this.overlay = document.createElement("div");
    this.overlay.id = "start-screen";
    this.overlay.style.cssText = `
      position:absolute; inset:0;
      background:linear-gradient(180deg,#020210 0%,#05051a 50%,#020210 100%);
      z-index:20; overflow:hidden; font-family:'Courier New',monospace;
    `;
    parent.appendChild(this.overlay);
    this.createParticles();
    this.render();
  }

  private createParticles(): void {
    const canvas = document.createElement("canvas");
    canvas.style.cssText = "position:absolute;inset:0;pointer-events:none;opacity:0.4;";
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    this.overlay.appendChild(canvas);

    const ctx = canvas.getContext("2d")!;
    const particles: { x: number; y: number; vx: number; vy: number; size: number; alpha: number; color: string }[] = [];

    const colors = ["#00ccff", "#0066ff", "#cc44ff", "#00ff88", "#ff8800"];
    for (let i = 0; i < 60; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        vx: (Math.random() - 0.5) * 0.5,
        vy: (Math.random() - 0.5) * 0.5,
        size: Math.random() * 3 + 1,
        alpha: Math.random() * 0.8 + 0.2,
        color: colors[Math.floor(Math.random() * colors.length)],
      });
    }

    const animate = () => {
      if (!document.getElementById("start-screen")) return;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      particles.forEach((p) => {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0) p.x = canvas.width;
        if (p.x > canvas.width) p.x = 0;
        if (p.y < 0) p.y = canvas.height;
        if (p.y > canvas.height) p.y = 0;

        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fillStyle = p.color;
        ctx.globalAlpha = p.alpha * (0.5 + 0.5 * Math.sin(Date.now() * 0.002 + p.x));
        ctx.fill();
        ctx.globalAlpha = 1;
      });
      requestAnimationFrame(animate);
    };
    animate();
  }

  private render(): void {
    // Limpiar contenido previo (excepto el canvas de particulas)
    const canvas = this.overlay.querySelector("canvas");
    this.overlay.innerHTML = "";
    if (canvas) this.overlay.appendChild(canvas);

    switch (this.currentScreen) {
      case "main": this.renderMain(); break;
      case "tutorial": this.renderTutorial(); break;
      case "changelog": this.renderChangelog(); break;
    }
  }

  // ============================================
  // PANTALLA PRINCIPAL
  // ============================================
  private renderMain(): void {
    const content = document.createElement("div");
    content.style.cssText = `
      position:absolute; inset:0; display:flex; flex-direction:column;
      align-items:center; justify-content:center; gap:40px; padding:40px;
    `;

    // Logo / Titulo
    content.innerHTML = `
      <div style="text-align:center;">
        <div style="font-size:14px;letter-spacing:8px;color:#0066aa;margin-bottom:12px;text-transform:uppercase;">
          WebXR · BabylonJS · Meta Quest
        </div>
        <h1 style="
          font-size:clamp(36px,6vw,72px); font-weight:bold; margin:0;
          letter-spacing:8px; text-transform:uppercase;
          color:#00ccff;
          text-shadow:0 0 40px rgba(0,200,255,0.9),0 0 80px rgba(0,100,255,0.5),0 0 120px rgba(0,50,200,0.3);
        ">VR KI COMBAT</h1>
        <div style="
          font-size:13px; letter-spacing:4px; color:#336688; margin-top:16px;
          text-transform:uppercase;
        ">Sistema de combate accion-reaccion</div>
        <div style="
          display:inline-block; margin-top:20px; padding:4px 16px;
          border:1px solid #0044aa; border-radius:4px;
          font-size:11px; letter-spacing:3px; color:#0066cc;
        ">v0.3.0 — MVP</div>
      </div>

      <div style="display:flex;gap:16px;flex-wrap:wrap;justify-content:center;">
        <button id="btn-start" style="
          padding:16px 56px; background:linear-gradient(135deg,#003366,#0055cc);
          border:2px solid #0099ff; border-radius:6px; color:#00ccff;
          font-size:16px; font-family:'Courier New',monospace; font-weight:bold;
          letter-spacing:4px; cursor:pointer; text-transform:uppercase;
          box-shadow:0 0 30px rgba(0,150,255,0.6);
          transition:all 0.2s;
        ">Iniciar Combate</button>
      </div>

      <div style="display:flex;gap:16px;flex-wrap:wrap;justify-content:center;">
        <button id="btn-tutorial" style="
          padding:10px 32px; background:transparent;
          border:1px solid #0066aa; border-radius:6px; color:#0099cc;
          font-size:13px; font-family:'Courier New',monospace;
          letter-spacing:3px; cursor:pointer; text-transform:uppercase;
          transition:all 0.2s;
        ">Tutorial</button>
        <button id="btn-changelog" style="
          padding:10px 32px; background:transparent;
          border:1px solid #334455; border-radius:6px; color:#556677;
          font-size:13px; font-family:'Courier New',monospace;
          letter-spacing:3px; cursor:pointer; text-transform:uppercase;
          transition:all 0.2s;
        ">Changelog</button>
      </div>

      <div style="
        background:rgba(0,10,30,0.6); border:1px solid #0a1a2a;
        border-radius:8px; padding:20px 32px; text-align:center;
        max-width:480px; width:100%;
      ">
        <div style="font-size:11px;letter-spacing:2px;color:#334455;margin-bottom:12px;text-transform:uppercase;">
          Controles rapidos
        </div>
        <div style="
          display:grid; grid-template-columns:auto 1fr; gap:6px 16px;
          font-size:12px; color:#556677; letter-spacing:1px; text-align:left;
        ">
          <span style="color:#00ff88;font-weight:bold;">A</span><span>Ataque basico de KI</span>
          <span style="color:#00ff88;font-weight:bold;">W</span><span>Cargar / Lanzar ataque cargado</span>
          <span style="color:#00aaff;font-weight:bold;">S</span><span>Bloqueo</span>
          <span style="color:#00aaff;font-weight:bold;">D</span><span>Esquive</span>
          <span style="color:#cc44ff;font-weight:bold;">R</span><span>Recargar KI</span>
          <span style="color:#ff8800;font-weight:bold;">1 / 2</span><span>Ataques especiales</span>
        </div>
      </div>
    `;

    this.overlay.appendChild(content);

    content.querySelector("#btn-start")!.addEventListener("click", () => {
      this.overlay.remove();
      this.onStart();
    });
    content.querySelector("#btn-tutorial")!.addEventListener("click", () => {
      this.tutorialStep = 0;
      this.currentScreen = "tutorial";
      this.render();
    });
    content.querySelector("#btn-changelog")!.addEventListener("click", () => {
      this.currentScreen = "changelog";
      this.render();
    });
  }

  // ============================================
  // TUTORIAL
  // ============================================
  private renderTutorial(): void {
    const step = TUTORIAL_STEPS[this.tutorialStep];
    const isFirst = this.tutorialStep === 0;
    const isLast = this.tutorialStep === TUTORIAL_STEPS.length - 1;

    const content = document.createElement("div");
    content.style.cssText = `
      position:absolute; inset:0; display:flex; flex-direction:column;
      align-items:center; justify-content:center; gap:24px; padding:40px;
    `;

    // Indicador de progreso
    const progressDots = TUTORIAL_STEPS.map((_, i) =>
      `<div style="
        width:${i === this.tutorialStep ? 20 : 8}px; height:8px;
        border-radius:4px;
        background:${i === this.tutorialStep ? "#00ccff" : i < this.tutorialStep ? "#0066aa" : "#0a1a2a"};
        transition:all 0.3s;
      "></div>`
    ).join("");

    content.innerHTML = `
      <div style="display:flex;gap:6px;align-items:center;">${progressDots}</div>

      <div style="
        background:rgba(0,10,30,0.8); border:1px solid #0a2a4a;
        border-radius:12px; padding:32px 40px; max-width:560px; width:100%;
        text-align:center;
      ">
        <div style="font-size:48px;margin-bottom:16px;">${step.icon}</div>
        <h2 style="
          color:#00ccff; font-size:20px; letter-spacing:3px;
          text-transform:uppercase; margin:0 0 16px;
          text-shadow:0 0 20px rgba(0,200,255,0.5);
        ">${step.title}</h2>
        <p style="
          color:#7799aa; font-size:14px; line-height:1.8;
          letter-spacing:0.5px; margin:0 0 ${step.controls.length ? "24px" : "0"};
        ">${step.content}</p>

        ${step.controls.length ? `
          <div style="
            background:rgba(0,5,15,0.6); border:1px solid #0a1a2a;
            border-radius:8px; padding:16px; text-align:left;
          ">
            ${step.controls.map(c => `
              <div style="
                display:grid; grid-template-columns:auto 1fr;
                gap:8px 16px; align-items:center; margin-bottom:8px;
              ">
                <span style="
                  background:rgba(0,50,100,0.5); border:1px solid #0066aa;
                  border-radius:4px; padding:3px 10px;
                  font-size:11px; color:#00ccff; letter-spacing:1px;
                  white-space:nowrap; text-align:center;
                ">${c.key}</span>
                <span style="font-size:12px;color:#556677;letter-spacing:0.5px;">${c.action}</span>
              </div>
            `).join("")}
          </div>
        ` : ""}
      </div>

      <div style="display:flex;gap:12px;align-items:center;">
        <button id="btn-back" style="
          padding:10px 28px; background:transparent;
          border:1px solid ${isFirst ? "#0a1a2a" : "#0066aa"};
          border-radius:6px; color:${isFirst ? "#0a1a2a" : "#0099cc"};
          font-size:13px; font-family:'Courier New',monospace;
          letter-spacing:2px; cursor:${isFirst ? "default" : "pointer"};
          text-transform:uppercase;
        ">← Atras</button>

        <span style="font-size:11px;color:#223344;letter-spacing:2px;">
          ${this.tutorialStep + 1} / ${TUTORIAL_STEPS.length}
        </span>

        ${isLast ? `
          <button id="btn-next" style="
            padding:10px 28px;
            background:linear-gradient(135deg,#003366,#0055cc);
            border:2px solid #0099ff; border-radius:6px; color:#00ccff;
            font-size:13px; font-family:'Courier New',monospace; font-weight:bold;
            letter-spacing:2px; cursor:pointer; text-transform:uppercase;
            box-shadow:0 0 20px rgba(0,150,255,0.4);
          ">Iniciar →</button>
        ` : `
          <button id="btn-next" style="
            padding:10px 28px; background:transparent;
            border:1px solid #0066aa; border-radius:6px; color:#0099cc;
            font-size:13px; font-family:'Courier New',monospace;
            letter-spacing:2px; cursor:pointer; text-transform:uppercase;
          ">Siguiente →</button>
        `}
      </div>

      <button id="btn-menu" style="
        padding:6px 20px; background:transparent; border:none;
        color:#223344; font-size:11px; font-family:'Courier New',monospace;
        letter-spacing:2px; cursor:pointer; text-transform:uppercase;
      ">Volver al menu</button>
    `;

    this.overlay.appendChild(content);

    const btnBack = content.querySelector("#btn-back") as HTMLButtonElement;
    const btnNext = content.querySelector("#btn-next") as HTMLButtonElement;
    const btnMenu = content.querySelector("#btn-menu") as HTMLButtonElement;

    if (!isFirst) {
      btnBack.addEventListener("click", () => {
        this.tutorialStep--;
        this.render();
      });
    }

    btnNext.addEventListener("click", () => {
      if (isLast) {
        this.overlay.remove();
        this.onStart();
      } else {
        this.tutorialStep++;
        this.render();
      }
    });

    btnMenu.addEventListener("click", () => {
      this.currentScreen = "main";
      this.render();
    });
  }

  // ============================================
  // CHANGELOG
  // ============================================
  private renderChangelog(): void {
    const content = document.createElement("div");
    content.style.cssText = `
      position:absolute; inset:0; display:flex; flex-direction:column;
      align-items:center; justify-content:flex-start;
      padding:40px 24px; overflow-y:auto;
    `;

    const entriesHtml = CHANGELOG.map((entry, i) => `
      <div style="
        background:rgba(0,10,30,${i === 0 ? "0.9" : "0.5"});
        border:1px solid ${i === 0 ? "#0a2a4a" : "#0a1a2a"};
        border-radius:10px; padding:24px 28px; width:100%; max-width:560px;
        margin-bottom:16px;
      ">
        <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px;">
          <span style="
            background:${i === 0 ? "rgba(0,50,100,0.6)" : "rgba(0,20,40,0.4)"};
            border:1px solid ${i === 0 ? "#0066cc" : "#0a1a2a"};
            border-radius:4px; padding:4px 12px;
            font-size:13px; color:${i === 0 ? "#00ccff" : "#334455"};
            letter-spacing:2px; font-weight:bold;
          ">v${entry.version}</span>
          <span style="font-size:11px;color:#223344;letter-spacing:2px;">${entry.date}</span>
          ${i === 0 ? `<span style="
            background:rgba(0,200,100,0.1); border:1px solid #00aa44;
            border-radius:4px; padding:2px 8px;
            font-size:10px; color:#00cc55; letter-spacing:2px;
          ">ACTUAL</span>` : ""}
        </div>
        <ul style="margin:0;padding-left:0;list-style:none;">
          ${entry.changes.map(c => `
            <li style="
              font-size:12px; color:${i === 0 ? "#7799aa" : "#334455"};
              letter-spacing:0.5px; padding:4px 0;
              border-bottom:1px solid rgba(255,255,255,0.03);
              display:flex; gap:10px; align-items:flex-start;
            ">
              <span style="color:${i === 0 ? "#0066aa" : "#1a2a3a"};margin-top:2px;">▸</span>
              <span>${c}</span>
            </li>
          `).join("")}
        </ul>
      </div>
    `).join("");

    content.innerHTML = `
      <div style="text-align:center;margin-bottom:32px;width:100%;">
        <h2 style="
          color:#00ccff; font-size:18px; letter-spacing:6px;
          text-transform:uppercase; margin:0 0 8px;
          text-shadow:0 0 20px rgba(0,200,255,0.4);
        ">Changelog</h2>
        <div style="font-size:11px;color:#223344;letter-spacing:3px;">
          Historial de versiones
        </div>
      </div>

      ${entriesHtml}

      <button id="btn-menu" style="
        margin-top:16px; padding:10px 32px; background:transparent;
        border:1px solid #0066aa; border-radius:6px; color:#0099cc;
        font-size:13px; font-family:'Courier New',monospace;
        letter-spacing:3px; cursor:pointer; text-transform:uppercase;
      ">← Volver al menu</button>
    `;

    this.overlay.appendChild(content);

    content.querySelector("#btn-menu")!.addEventListener("click", () => {
      this.currentScreen = "main";
      this.render();
    });
  }
}
