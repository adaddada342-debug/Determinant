import { getProductionPerSecond } from "./economy.js";

export function startLoop(state, getEffects, onTick) {
  let last = Date.now();
  setInterval(() => {
    const now = Date.now();
    const dt = Math.min(0.25, (now - last) / 1000);
    last = now;

    const effects = getEffects();
    const prod = getProductionPerSecond(state, effects);
    for (const [currency, rate] of Object.entries(prod)) {
      const gain = rate * dt;
      state.currencies[currency] += gain;
      const statMap = {
        momentum: "totalMomentumGenerated",
        money: "totalMoneyGenerated",
        confidence: "totalConfidenceGenerated",
        stability: "totalStabilityGenerated",
        reputation: "totalReputationGenerated",
        temporalShards: "totalTemporalShardsGenerated",
        realityAnchors: "totalRealityAnchorsGenerated"
      };
      state.stats[statMap[currency]] += gain;
    }

    if (effects.autoClicks > 0) {
      const autoGain = effects.autoClicks * dt * effects.clickPower;
      state.currencies.momentum += autoGain;
      state.stats.totalMomentumGenerated += autoGain;
    }

    state.combo = Math.max(0, state.combo - dt * 1.2);
    state.eventCooldown -= dt;
    state.stats.playTime += dt;
    state.meta.lastTickAt = now;
    onTick(prod, effects);
  }, 100);
}
