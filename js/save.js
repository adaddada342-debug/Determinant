import { SAVE_VERSION, createInitialState } from "./state.js";

const KEY = "dda_save_v1";

export function saveGame(state) {
  state.meta.lastSaveAt = Date.now();
  localStorage.setItem(KEY, JSON.stringify(state));
}

export function loadGame() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { state: createInitialState(), recovered: false };
    const parsed = JSON.parse(raw);
    if (!parsed.version || parsed.version > SAVE_VERSION) throw new Error("bad version");
    const base = createInitialState();
    const state = merge(base, parsed);
    return { state, recovered: false };
  } catch {
    localStorage.removeItem(KEY);
    return { state: createInitialState(), recovered: true };
  }
}

function merge(base, incoming) {
  for (const [k, v] of Object.entries(incoming)) {
    if (v && typeof v === "object" && !Array.isArray(v) && base[k]) merge(base[k], v);
    else base[k] = v;
  }
  return base;
}

export function exportSave(state) {
  return btoa(unescape(encodeURIComponent(JSON.stringify(state))));
}

export function importSaveString(str) {
  const json = decodeURIComponent(escape(atob(str.trim())));
  const parsed = JSON.parse(json);
  if (!parsed.version) throw new Error("Invalid save");
  localStorage.setItem(KEY, JSON.stringify(parsed));
  return parsed;
}

export function clearSave() {
  localStorage.removeItem(KEY);
}
