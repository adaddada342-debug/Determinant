import { eventDefs } from "./data.js";
import { pick } from "./utils.js";

export function rollEvent(state, effects) {
  if (state.activeEvent) return null;
  const pool = eventDefs.filter((e) => !e.id.includes("_follow"));
  let selected = pick(pool);
  if (Math.random() < effects.eventLuck * 0.1) {
    const positives = pool.filter((e) => ["minor+", "swing", "cosmic"].includes(e.type));
    selected = pick(positives);
  }
  state.activeEvent = selected.id;
  state.stats.eventsSeen += 1;
  return selected;
}

export function getEventById(id) {
  return eventDefs.find((e) => e.id === id) || null;
}

export function applyEventChoice(state, choice) {
  for (const [k, v] of Object.entries(choice.effects || {})) state.currencies[k] = Math.max(0, (state.currencies[k] || 0) + v);
  state.activeEvent = choice.chain || null;
}
