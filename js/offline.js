import { clamp } from "./utils.js";

export function calculateOfflineProgress(state, productionPerSec, effects) {
  const now = Date.now();
  const elapsed = Math.max(0, (now - (state.meta.lastTickAt || now)) / 1000);
  const capped = clamp(elapsed, 0, 60 * 60 * 6);
  const mult = effects.offlineEff;
  const gains = {};
  for (const [currency, rate] of Object.entries(productionPerSec)) gains[currency] = rate * capped * mult;
  return { elapsed: capped, gains };
}
