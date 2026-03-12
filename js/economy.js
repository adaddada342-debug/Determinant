import { effectCatalog, generators, traits } from "./data.js";
import { clamp } from "./utils.js";

export function getEffects(state, upgrades, achievements) {
  const fx = {
    clickPower: 1,
    critChance: 0.05,
    critMult: 2,
    genGlobal: 1,
    comboGain: 1,
    offlineEff: 0.45,
    convertMomentumToMoney: 0,
    convertStabilityToRep: 0,
    eventLuck: 0,
    shardBoost: 1,
    anchorBoost: 1,
    autoClicks: 0,
    costReduction: 0,
    repGain: 1,
    lateTierBoost: 0
  };

  for (const uid of state.boughtUpgrades) {
    const up = upgrades.find((u) => u.id === uid);
    if (!up) continue;
    const rule = effectCatalog[up.effect.key];
    if (!rule) continue;
    fx[rule.stat] += rule.perLevel * up.effect.amount;
  }

  for (const aid of state.boughtAchievements) {
    const ach = achievements.find((a) => a.id === aid);
    if (!ach) continue;
    fx[ach.reward.stat] += ach.reward.amount;
  }

  for (const tid of state.timelineTraits) {
    const t = traits.find((x) => x.id === tid);
    if (!t) continue;
    for (const [k, v] of Object.entries(t.bonuses)) fx[k] += v;
  }

  fx.costReduction = clamp(fx.costReduction, 0, 0.65);
  fx.critChance = clamp(fx.critChance, 0.05, 0.75);
  return fx;
}

export function getGeneratorCost(generator, owned, effects) {
  const growth = 1.15 + generator.tier * 0.01;
  const mult = growth ** owned * (1 - effects.costReduction);
  const result = {};
  for (const [currency, value] of Object.entries(generator.baseCost)) result[currency] = value * mult;
  return result;
}

export function canAfford(state, cost) {
  return Object.entries(cost).every(([c, v]) => (state.currencies[c] || 0) >= v);
}

export function spend(state, cost) {
  if (!canAfford(state, cost)) return false;
  for (const [c, v] of Object.entries(cost)) state.currencies[c] -= v;
  return true;
}

export function getProductionPerSecond(state, effects) {
  const rate = { momentum: 0, money: 0, confidence: 0, stability: 0, reputation: 0, temporalShards: 0, realityAnchors: 0 };
  for (const g of generators) {
    const owned = state.generators[g.id] || 0;
    if (!owned) continue;
    for (const [currency, amount] of Object.entries(g.produces)) {
      let m = effects.genGlobal;
      if (currency === "reputation") m *= effects.repGain;
      if (g.tier >= 4) m *= 1 + effects.lateTierBoost;
      if (currency === "temporalShards") m *= effects.shardBoost;
      if (currency === "realityAnchors") m *= effects.anchorBoost;
      rate[currency] += amount * owned * m;
    }
  }
  if (effects.convertMomentumToMoney > 0) rate.money += rate.momentum * effects.convertMomentumToMoney;
  if (effects.convertStabilityToRep > 0) rate.reputation += rate.stability * effects.convertStabilityToRep;
  return rate;
}

export function clickMomentum(state, effects) {
  const base = 1 + state.currentEra * 0.35;
  const comboMult = 1 + state.combo * 0.03 * effects.comboGain;
  const crit = Math.random() < effects.critChance ? effects.critMult : 1;
  const amount = base * effects.clickPower * comboMult * crit;
  state.combo = clamp(state.combo + 1, 0, 80);
  return amount;
}

export function calcShardGain(state, effects) {
  const raw = Math.sqrt(state.stats.totalMomentumGenerated / 120000) + Math.cbrt(state.stats.totalMoneyGenerated / 5e6);
  return Math.floor(raw * effects.shardBoost);
}
