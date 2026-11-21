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
