import { createInitialState } from "./state.js";
import { eras, generators } from "./data.js";
import { checkAchievements, getEraByMomentum } from "./achievements.js";
import { getEffects, clickMomentum, spend, getGeneratorCost, getProductionPerSecond, calcShardGain } from "./economy.js";
import { rollEvent, getEventById, applyEventChoice } from "./events.js";
import { performPrestige } from "./prestige.js";
import { saveGame, loadGame, exportSave, importSaveString, clearSave } from "./save.js";
import { calculateOfflineProgress } from "./offline.js";
import { audio } from "./audio.js";
import { initTabs, renderAll, spawnFloatingText, showModal, setSaveStatus, upgrades, achievementDefs } from "./ui.js";
import { startLoop } from "./gameLoop.js";
import { format } from "./utils.js";

const loaded = loadGame();
let state = loaded.state || createInitialState();
audio.setMuted(state.meta.muted);

const mainClicker = document.getElementById("mainClicker");
mainClicker.addEventListener("click", onClick);

initTabs(state);
if (loaded.recovered) {
  showModal({ title: "Save Recovered", body: "Your previous save was corrupted, so a clean timeline was started.", actions: [{ label: "Got it", onClick: () => {} }] });
}

const initialEffects = getEffects(state, upgrades, achievementDefs);
const offline = calculateOfflineProgress(state, getProductionPerSecond(state, initialEffects), initialEffects);
if (offline.elapsed > 5) {
  for (const [c, amount] of Object.entries(offline.gains)) {
    state.currencies[c] += amount;
  }
  state.stats.totalOfflineMomentum += offline.gains.momentum || 0;
  showModal({
    title: "Welcome Back",
    body: `Away for <b>${format(offline.elapsed / 60)} min</b>.<br>Recovered <span class="reward">⚡ ${format(offline.gains.momentum || 0)}</span> momentum and more.`,
    actions: [{ label: "Back to work", onClick: () => {} }]
  });
}

function currentEffects() {
  return getEffects(state, upgrades, achievementDefs);
}

function onClick() {
  const effects = currentEffects();
  const gain = clickMomentum(state, effects);
  state.currencies.momentum += gain;
  state.stats.totalMomentumGenerated += gain;
  state.stats.totalClicks += 1;
  state.stats.biggestClick = Math.max(state.stats.biggestClick, gain);
  spawnFloatingText(`+${format(gain)} ⚡`);
  audio.click();
  mainClicker.classList.add("pop");
  setTimeout(() => mainClicker.classList.remove("pop"), 80);
}

const handlers = {
  onBuyGenerator: (id) => {
    const g = generators.find((x) => x.id === id);
    const effects = currentEffects();
    const cost = getGeneratorCost(g, state.generators[id], effects);
    if (!spend(state, cost)) return;
    state.generators[id] += 1;
    state.stats.totalGeneratorsBought += 1;
    spawnFloatingText(`${g.name} online`, true);
    audio.purchase();
  },
  onBuyUpgrade: (id) => {
    const up = upgrades.find((x) => x.id === id);
    if (!spend(state, up.cost)) return;
    state.boughtUpgrades.push(id);
    spawnFloatingText(`Unlocked ${up.name}`, true);
    audio.purchase();
  },
  onEventChoice: (index) => {
    const ev = getEventById(state.activeEvent);
    if (!ev) return;
    const choice = ev.choices[index];
    applyEventChoice(state, choice);
    spawnFloatingText(`${choice.label}`, true);
    audio.event();
  },
  onPrestige: () => {
    const shardPreview = calcShardGain(state, currentEffects());
    showModal({
      title: "Begin New Timeline?",
      body: `Reset most progress for <b>${shardPreview}</b> Temporal Shards. Achievements, selected traits, and permanent currencies remain.`,
      actions: [
        { label: "Cancel", onClick: () => {} },
        {
          label: "Ascend",
          onClick: () => {
            const result = performPrestige(state, currentEffects());
            if (!result.ok) return;
            state = result.newState;
            audio.milestone();
            spawnFloatingText(`+${result.shardGain} 🕰️`, true);
          }
        }
      ]
    });
  },
  onTraitToggle: (id) => {
    if (state.timelineTraits.includes(id)) {
      if (state.timelineTraits.length > 1) state.timelineTraits = state.timelineTraits.filter((x) => x !== id);
    } else if (state.currencies.temporalShards >= 10) {
      state.timelineTraits.push(id);
      state.currencies.temporalShards -= 10;
    } else {
      spawnFloatingText("Need 10 Temporal Shards", false);
    }
  }
};

function tickRender(prod) {
  const newEra = getEraByMomentum(state.stats.totalMomentumGenerated);
  if (newEra > state.currentEra) {
    state.currentEra = newEra;
    showModal({ title: `Era Reached: ${eras[newEra].name}`, body: eras[newEra].hint, actions: [{ label: "Let's go", onClick: () => {} }] });
    audio.milestone();
  }

  const unlockedAch = checkAchievements(state, achievementDefs);
  if (unlockedAch.length) {
    spawnFloatingText(`+${unlockedAch.length} achievement`, true);
  }

  if (state.eventCooldown <= 0) {
    const ev = rollEvent(state, currentEffects());
    if (ev) {
      audio.event();
      state.eventCooldown = 45 - Math.min(20, state.currentEra * 2);
    }
  }

  renderAll(state, prod, handlers);
}

startLoop(state, currentEffects, tickRender);

setInterval(() => {
  saveGame(state);
  setSaveStatus(`Saved ${new Date().toLocaleTimeString()}`);
}, 15000);

document.getElementById("manualSaveBtn").onclick = () => {
  saveGame(state);
  setSaveStatus("Saved manually");
};

document.getElementById("exportSaveBtn").onclick = () => {
  const payload = exportSave(state);
  showModal({
    title: "Export Save",
    body: `<textarea style="width:100%;height:120px;">${payload}</textarea>`,
    actions: [{ label: "Close", onClick: () => {} }]
  });
};

document.getElementById("importSaveBtn").onclick = () => {
  showModal({
    title: "Import Save",
    body: `<textarea id="importBox" style="width:100%;height:120px;" placeholder="Paste save string"></textarea>`,
    actions: [
      { label: "Cancel", onClick: () => {} },
      {
        label: "Import",
        onClick: () => {
          const raw = document.getElementById("importBox").value;
          try {
            state = importSaveString(raw);
          } catch {
            spawnFloatingText("Invalid save string", false);
          }
        }
      }
    ]
  });
};

document.getElementById("resetSaveBtn").onclick = () => {
  showModal({
    title: "Reset Timeline?",
    body: "This wipes your save permanently.",
    actions: [
      { label: "Cancel", onClick: () => {} },
      { label: "Reset", className: "danger", onClick: () => { clearSave(); state = createInitialState(); } }
    ]
  });
};

document.getElementById("muteBtn").onclick = (e) => {
  state.meta.muted = !state.meta.muted;
  audio.setMuted(state.meta.muted);
  e.target.textContent = state.meta.muted ? "🔈" : "🔊";
};

renderAll(state, {}, handlers);
