const CHARACTER_ROSTER = {
  vegeta: {
    name: "Vegeta",
    badge: "Príncipe de los Saiyans",
    race: "Saiyan",
    origin: "Planeta Vegeta",
    baseNp: "10.000",
    maxNp: "20.000",
    maxFormNp: "160.000",
    kiBlastCost: "2.5 Ki (Rápido Vegeta) / 9.0 Ki (Cargado)",
    furiaRule: "Furia estándar al >= 30% déficit BP (baja a 22% con Orgullo del Príncipe).",
    zenkaiRule: "Dominio: >= 40% ventaja y >= 75% máx activo · Comeback: Parry en Furia, Desvío de Súper o Determinación (+45 Ki, +25% déficit BP).",
    transformations: [
      { tier: "Fase 1", name: "SSJ", mult: "x2.0", drain: "2.1 Ki/s", unlock: ">= 75% máx, <= 78% base o Furia", color: "#ffd919" },
      { tier: "Fase 2", name: "Super Vegeta", mult: "x3.5", drain: "3.2 Ki/s", unlock: "En SSJ+: >= 85% máx, <= 68% base o Furia", color: "#ffe600" },
      { tier: "Fase 3", name: "SSB", mult: "x5.0", drain: "4.4 Ki/s", unlock: "Alcanzar Estado Zenkai", color: "#1ab3ff" },
      { tier: "Fase 4", name: "Ultra Ego", mult: "x8.0", drain: "5.5 Ki/s", unlock: "En Fase 3+ con Zenkai o piso >= 75%", color: "#ad26f2" }
    ],
    powers: [
      { name: "Ki Blast Rápido", ki: "4.0 Ki (2.5 Ki economía)", dmg: "250 BP", speed: "Estándar", gesture: "Brazo extendido + Gatillo (sin Grip)", note: "Usable en cualquier forma." },
      { name: "Galick Ho", ki: "28.0 Ki", dmg: "1.800 BP", speed: "34.0", gesture: "Ambos Grips al costado/cadera -> empujar al frente", note: "Usable en cualquier forma; inicia Beam Clash." },
      { name: "Big Bang Attack", ki: "35.0 Ki", dmg: "3.200 BP", speed: "38.0", gesture: "1 brazo extendido palma abierta + Grip (sin Gatillo)", note: "Usable en todas las transformaciones (sin restricción)." },
      { name: "Final Flash", ki: "45.0 Ki", dmg: "99.999 BP (Finisher)", speed: "44.0", gesture: "Brazos en cruz (T-Pose) con Grips -> juntar al frente", note: "Requiere SSJ+ · Ejecuta K.O. en Estado Zenkai.", isFinisher: true }
    ],
    exclusives: [
      { title: "🟣 Orgullo del Príncipe (Permanente)", condition: "Presión o Furia · 5 golpes rápidos al núcleo (3.5 s)", effect: "Furia permanente al 22% de déficit · +15% Daño en Súpers." },
      { title: "🎯 Precisión Real (16.0 s)", condition: "Dominando o en SSJ · Disparar a 3 blancos (3.2 s)", effect: "x2 Velocidad de Carga Blast · -50% Coste de Ki Blast." }
    ]
  },
  goku: {
    name: "Goku",
    badge: "Guerrero Z",
    race: "Saiyan",
    origin: "Tierra",
    baseNp: "9.000",
    maxNp: "18.000",
    maxFormNp: "144.000",
    kiBlastCost: "3.0 Ki (Rápido) / 9.0 Ki (Cargado)",
    furiaRule: "Furia al >= 30% déficit BP (+100% recarga Ki y x2 BP ganado).",
    zenkaiRule: "Dominio: >= 40% ventaja y >= 75% máx activo · Comeback: Parry en Furia, Desvío de Súper o Determinación (+45 Ki, +25% déficit BP).",
    transformations: [
      { tier: "Fase 1", name: "SSJ", mult: "x2.0", drain: "1.8 Ki/s", unlock: ">= 75% máx, <= 78% base o Furia", color: "#ffd919" },
      { tier: "Fase 2", name: "SSJ2", mult: "x3.5", drain: "2.8 Ki/s", unlock: "En SSJ+: >= 85% máx, <= 68% base o Furia", color: "#ffeb40" },
      { tier: "Fase 3", name: "SSB", mult: "x5.0", drain: "4.0 Ki/s", unlock: "Alcanzar Estado Zenkai", color: "#1ab3ff" },
      { tier: "Fase 4", name: "Ultra Instinto", mult: "x8.0", drain: "5.5 Ki/s", unlock: "En Fase 3+ con Zenkai o piso >= 75%", color: "#d9ebff" }
    ],
    powers: [
      { name: "Ki Blast Rápido", ki: "4.0 Ki (3.0 Ki economía)", dmg: "250 BP", speed: "Estándar", gesture: "Brazo extendido + Gatillo (sin Grip)", note: "Usable en cualquier forma." },
      { name: "Kamehameha", ki: "28.0 Ki", dmg: "1.800 BP", speed: "32.0", gesture: "Ambos Grips recogidos en la cadera -> empujar al frente", note: "Usable en cualquier forma; inicia Beam Clash." },
      { name: "Genkidama", ki: "45.0 Ki", dmg: "6.000 BP", speed: "10.0", gesture: "Ambos brazos al cielo con Grips -> bajar al frente", note: "Prohibida en Kaioken, SSJ, SSJ2, SSJ3, SSJ4, SSB y Ultra Instinto." },
      { name: "Super Kamehameha", ki: "45.0 Ki", dmg: "99.999 BP (Finisher)", speed: "42.0", gesture: "Mismo gesto de Kamehameha estando en SSJ+", note: "Requiere SSJ+ · Ejecuta K.O. en Estado Zenkai.", isFinisher: true }
    ],
    exclusives: [
      { title: "☀️ Corazón Sereno (Permanente)", condition: "En Base o en desventaja · Absorber 3 anillos dorados (3.5 s)", effect: "+20% Recarga de Ki · +18% Velocidad de Carga Súper." },
      { title: "🔴 Pulso Kaioken (15.0 s)", condition: "Combate intenso o Furia · 2 pulsos carmesí al ritmo (3.0 s)", effect: "+30% Daño Total · +25% Velocidad de Vuelo." }
    ]
  },
  goku_zenkai: {
    name: "Goku (Zenkai)",
    badge: "Variante Mallas por Forma",
    race: "Saiyan",
    origin: "Tierra",
    baseNp: "9.000",
    maxNp: "18.000",
    maxFormNp: "90.000",
    kiBlastCost: "3.0 Ki (Rápido) / 9.0 Ki (Cargado)",
    furiaRule: "Furia al >= 30% déficit BP (+100% recarga Ki y x2 BP ganado).",
    zenkaiRule: "Comparte las reglas de Dominio/Comeback Zenkai; intercambia mallas 3D completas de cuerpo y manos en cada transformación.",
    transformations: [
      { tier: "Fase 1", name: "SSJ", mult: "x2.0", drain: "1.8 Ki/s", unlock: ">= 75% máx, <= 78% base o Furia", color: "#ffd919" },
      { tier: "Fase 2", name: "SSJ3", mult: "x3.5", drain: "2.8 Ki/s", unlock: "En SSJ+: >= 85% máx, <= 68% base o Furia", color: "#ffeb40" },
      { tier: "Fase 3", name: "SSB", mult: "x5.0", drain: "4.0 Ki/s", unlock: "Alcanzar Estado Zenkai", color: "#1ab3ff" }
    ],
    powers: [
      { name: "Ki Blast Rápido", ki: "4.0 Ki (3.0 Ki economía)", dmg: "250 BP", speed: "Estándar", gesture: "Brazo extendido + Gatillo (sin Grip)", note: "Usable en cualquier forma." },
      { name: "Kamehameha", ki: "28.0 Ki", dmg: "1.800 BP", speed: "32.0", gesture: "Ambos Grips recogidos en la cadera -> empujar al frente", note: "Usable en cualquier forma; inicia Beam Clash." },
      { name: "Genkidama", ki: "45.0 Ki", dmg: "6.000 BP", speed: "10.0", gesture: "Ambos brazos al cielo con Grips -> bajar al frente", note: "Prohibida en Kaioken, SSJ, SSJ3, SSB y Ultra Instinto." },
      { name: "Super Kamehameha", ki: "45.0 Ki", dmg: "99.999 BP (Finisher)", speed: "42.0", gesture: "Mismo gesto de Kamehameha estando en SSJ+", note: "Requiere SSJ+ · Ejecuta K.O. en Estado Zenkai.", isFinisher: true }
    ],
    exclusives: [
      { title: "☀️ Corazón Sereno (Permanente)", condition: "En Base o en desventaja · Absorber 3 anillos dorados (3.5 s)", effect: "+20% Recarga de Ki · +18% Velocidad de Carga Súper." },
      { title: "🔴 Pulso Kaioken (15.0 s)", condition: "Combate intenso o Furia · 2 pulsos carmesí al ritmo (3.0 s)", effect: "+30% Daño Total · +25% Velocidad de Vuelo." }
    ]
  }
};

function renderCharacterSheet(charKey) {
  const container = document.getElementById("characterSheet");
  const data = CHARACTER_ROSTER[charKey];
  if (!container || !data) return;

  const transformsHtml = data.transformations.map((t) => `
    <div class="transform-card" style="border-top-color: ${t.color};">
      <strong>${t.tier} · ${t.name}</strong><br />
      <span>Multiplicador: <code>${t.mult}</code> · Drenaje: <code>${t.drain}</code></span><br />
      <small style="color: var(--muted);">${t.unlock}</small>
    </div>
  `).join("");

  const powersHtml = data.powers.map((p) => `
    <div class="power-card ${p.isFinisher ? "finisher" : ""}">
      <strong>${p.name}</strong> <code>${p.ki}</code><br />
      <span>Daño base: <strong>${p.dmg}</strong> · Vel: <code>${p.speed}</code></span><br />
      <small style="color: var(--ki);">${p.gesture}</small><br />
      <small style="color: var(--muted);">${p.note}</small>
    </div>
  `).join("");

  const exclusivesHtml = data.exclusives.map((e) => `
    <div class="power-card">
      <strong>${e.title}</strong><br />
      <small style="color: var(--muted);">${e.condition}</small><br />
      <span>${e.effect}</span>
    </div>
  `).join("");

  container.innerHTML = `
    <div class="char-header">
      <div>
        <h3 style="margin:0; color: var(--gold); font-size:1.35rem;">${data.name}</h3>
        <span style="color: var(--muted); font-size:0.9rem;">${data.badge} · ${data.race} · Origen: ${data.origin}</span>
      </div>
      <div class="stat-pills">
        <div class="stat-pill">Base BP: <strong>${data.baseNp}</strong></div>
        <div class="stat-pill">Máx Base: <strong>${data.maxNp}</strong></div>
        <div class="stat-pill">Máx Forma Final: <strong>${data.maxFormNp}</strong></div>
        <div class="stat-pill">Ki Blast: <strong>${data.kiBlastCost}</strong></div>
      </div>
    </div>

    <div>
      <h4 style="margin:0 0 0.6rem; color: var(--ki);">⚡ Transformaciones y Escalado</h4>
      <div class="transform-track">${transformsHtml}</div>
    </div>

    <div>
      <h4 style="margin:0 0 0.6rem; color: var(--ki);">💥 Poderes y Finishers</h4>
      <div class="power-grid">${powersHtml}</div>
    </div>

    <div>
      <h4 style="margin:0 0 0.6rem; color: var(--ki);">🔥 Furia, Zenkai y Eventos Exclusivos</h4>
      <div class="power-grid">
        <div class="power-card">
          <strong>🔥 Regla de Furia &amp; Zenkai</strong><br />
          <small style="color: var(--muted);">${data.furiaRule}</small><br />
          <small>${data.zenkaiRule}</small>
        </div>
        ${exclusivesHtml}
      </div>
    </div>
  `;
}

document.addEventListener("DOMContentLoaded", () => {
  const tabs = document.querySelectorAll(".phase-tab");
  const panels = document.querySelectorAll(".phase-panel");

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const target = tab.dataset.phase;
      tabs.forEach((t) => t.classList.remove("active"));
      panels.forEach((p) => p.classList.remove("active"));
      tab.classList.add("active");
      const activePanel = document.getElementById(target);
      if (activePanel) activePanel.classList.add("active");
    });
  });

  const charButtons = document.querySelectorAll(".char-btn");
  charButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      charButtons.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      renderCharacterSheet(btn.dataset.char);
    });
  });
  renderCharacterSheet("vegeta");

  const searchInput = document.getElementById("cheatSearch");
  const cheatItems = document.querySelectorAll(".cheat-item");
  if (searchInput) {
    searchInput.addEventListener("input", () => {
      const q = searchInput.value.trim().toLowerCase();
      cheatItems.forEach((item) => {
        const txt = item.textContent.toLowerCase();
        item.classList.toggle("hidden", q.length > 0 && !txt.includes(q));
      });
    });
  }
});
