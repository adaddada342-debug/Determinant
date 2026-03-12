import { currencies, eras, generators, createUpgrades, createAchievements, traits } from "./data.js";
import { canAfford, getEffects, getGeneratorCost } from "./economy.js";
import { format } from "./utils.js";
import { getEventById } from "./events.js";

export const upgrades = createUpgrades();
export const achievementDefs = createAchievements();

function costText(cost) {
  return Object.entries(cost).filter(([, v]) => v > 0).map(([k, v]) => `${currencies[k].icon} ${format(v)}`).join(" • ");
}

export function initTabs(state) {
  document.querySelectorAll(".tab").forEach((btn) => btn.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((x) => x.classList.remove("active"));
    document.querySelectorAll(".tab-content").forEach((x) => x.classList.remove("active"));
    btn.classList.add("active");
    document.getElementById(`tab-${btn.dataset.tab}`).classList.add("active");
    state.meta.selectedTab = btn.dataset.tab;
  }));
}

export function renderAll(state, production, handlers) {
  const effects = getEffects(state, upgrades, achievementDefs);
  const era = eras[state.currentEra];
  document.getElementById("eraLabel").textContent = `Era: ${era.name}`;
  document.getElementById("hintText").textContent = era.hint;
  document.getElementById("app").className = `era-${era.id}`;

  const top = document.getElementById("topCurrencies");
  top.innerHTML = Object.entries(currencies).map(([k, v]) => `<div class="currency-chip" title="${v.tip}"><span>${v.icon} ${v.name}</span><b>${format(state.currencies[k] || 0)}</b></div>`).join("");

  const traitList = document.getElementById("traitList");
  traitList.innerHTML = traits.map((t) => `<button data-trait="${t.id}" class="${state.timelineTraits.includes(t.id) ? "active" : ""}" title="${t.desc}">${t.name}</button>`).join(" ");
  traitList.querySelectorAll("button").forEach((b) => b.onclick = () => handlers.onTraitToggle(b.dataset.trait));

  document.getElementById("clickValue").textContent = `+${format((1 + state.currentEra * 0.35) * effects.clickPower)} Life Momentum per click`;
  document.getElementById("automationStatus").textContent = `Automation: ${format(effects.autoClicks)}/sec auto-clicks • Combo x${format(1 + state.combo * 0.03 * effects.comboGain)}`;

  const gl = document.getElementById("generatorList");
  gl.innerHTML = generators.map((g) => {
    const owned = state.generators[g.id] || 0;
    const unlocked = state.stats.totalMomentumGenerated >= g.unlockAt;
    const cost = getGeneratorCost(g, owned, effects);
    const affordable = canAfford(state, cost);
    const rate = Object.entries(g.produces).map(([k, v]) => `${currencies[k].icon}${format(v * owned * effects.genGlobal)}/s`).join(" ");
    return `<div class="generator ${unlocked ? "" : "locked"}">
      <div class="generator-header"><b>${g.name}</b><span>Owned: ${owned}</span></div>
      <small>${g.desc}</small>
      <div class="row-between"><span class="rate">${rate || "No production yet"}</span><span>${costText(cost)}</span></div>
      <button data-gen="${g.id}" ${!unlocked || !affordable ? "disabled" : ""}>Buy</button>
    </div>`;
  }).join("");
  gl.querySelectorAll("button[data-gen]").forEach((btn) => btn.onclick = () => handlers.onBuyGenerator(btn.dataset.gen));

  const upEl = document.getElementById("tab-upgrades");
  const availUpgrades = upgrades.filter((u) => !state.boughtUpgrades.includes(u.id));
  upEl.innerHTML = `<div class="grid">${availUpgrades.map((u) => {
    const unlocked = state.stats.totalMomentumGenerated >= u.unlockAt;
    const affordable = canAfford(state, u.cost);
    return `<div class="upgrade ${unlocked ? "" : "locked"}">
      <b>${u.name}</b><small>${u.category} • ${u.desc}</small>
      <small>${costText(u.cost)}</small>
      <button data-up="${u.id}" ${!unlocked || !affordable ? "disabled" : ""}>Unlock</button>
    </div>`;
  }).join("")}</div>`;
  upEl.querySelectorAll("button[data-up]").forEach((b) => b.onclick = () => handlers.onBuyUpgrade(b.dataset.up));

  const achEl = document.getElementById("tab-achievements");
  achEl.innerHTML = achievementDefs.map((a) => `<div class="achievement ${state.boughtAchievements.includes(a.id) ? "" : "locked"}"><b>${a.name}</b><small>${a.category} • ${a.desc}</small></div>`).join("");

  const evEl = document.getElementById("tab-events");
  const activeEvent = state.activeEvent ? getEventById(state.activeEvent) : null;
  evEl.innerHTML = activeEvent ? `<div class="event-card"><b>${activeEvent.title}</b><p>${activeEvent.text}</p>${activeEvent.choices.map((c, i) => `<button class="choice-btn" data-choice="${i}">${c.label}</button>`).join("")}</div>` : `<p class="subtle">No active event. Next roll in ${format(state.eventCooldown)}s.</p>`;
  evEl.querySelectorAll("button[data-choice]").forEach((b) => b.onclick = () => handlers.onEventChoice(Number(b.dataset.choice)));

  const st = state.stats;
  document.getElementById("tab-stats").innerHTML = `
    <p>Total Clicks: ${format(st.totalClicks)}</p>
    <p>Total Momentum: ${format(st.totalMomentumGenerated)}</p>
    <p>Total Money: ${format(st.totalMoneyGenerated)}</p>
    <p>Events Seen: ${format(st.eventsSeen)}</p>
    <p>Prestiges: ${format(st.prestiges)}</p>
    <p>Biggest Click: ${format(st.biggestClick)}</p>
    <p>Generators Bought: ${format(st.totalGeneratorsBought)}</p>
    <p>Offline Momentum Collected: ${format(st.totalOfflineMomentum)}</p>
    <p>Play Time: ${format(st.playTime / 3600)}h</p>`;

  document.getElementById("tab-codex").innerHTML = Object.values(currencies).map((c) => `<div><b>${c.icon} ${c.name}</b><small>${c.tip}</small></div>`).join("") + `<hr><small>New Timeline resets most growth but grants Temporal Shards for permanent power and trait builds.</small>`;

  document.getElementById("tab-timeline").innerHTML = `<p>Starting a New Timeline converts your legacy into Temporal Shards.</p><button id="prestigeBtn">Begin New Timeline</button>`;
  document.getElementById("prestigeBtn").onclick = handlers.onPrestige;
}

export function spawnFloatingText(text, positive = true) {
  const node = document.createElement("div");
  node.className = "float";
  node.textContent = text;
  node.style.color = positive ? "#9cffad" : "#ff9b9b";
  document.getElementById("floatingContainer").appendChild(node);
  setTimeout(() => node.remove(), 1000);
}

export function setSaveStatus(msg) {
  document.getElementById("saveStatus").textContent = msg;
}

export function showModal({ title, body, actions }) {
  const modal = document.getElementById("modal");
  document.getElementById("modalTitle").textContent = title;
  document.getElementById("modalBody").innerHTML = body;
  const actionsEl = document.getElementById("modalActions");
  actionsEl.innerHTML = "";
  actions.forEach((a) => {
    const btn = document.createElement("button");
    btn.textContent = a.label;
    btn.className = a.className || "";
    btn.onclick = () => { a.onClick(); hideModal(); };
    actionsEl.appendChild(btn);
  });
  modal.classList.remove("hidden");
}

export function hideModal() {
  document.getElementById("modal").classList.add("hidden");
}
