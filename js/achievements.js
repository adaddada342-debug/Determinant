import { eras } from "./data.js";

const bucketTargets = {
  Momentum: [500, 5e3, 3e4, 1e5, 4e5, 1e6, 4e6, 2e7, 8e7, 4e8],
  Money: [200, 2e3, 2e4, 2e5, 1e6, 6e6, 3e7, 1.5e8, 8e8, 4e9],
  Mindset: [30, 90, 220, 600, 1600, 3600, 8500, 20000, 45000, 100000],
  Stability: [20, 80, 200, 520, 1300, 3100, 7500, 17000, 40000, 90000],
  Social: [10, 60, 180, 450, 1200, 2900, 7000, 17000, 41000, 100000],
  Timeline: [1, 2, 3, 4, 6, 8, 11, 14, 18, 25],
  Cosmic: [0, 1, 2, 4, 6, 9, 13, 18, 25, 35],
  Secrets: [1, 2, 3, 4, 6, 8, 10, 12, 15, 20]
};

export function checkAchievements(state, achievementDefs) {
  const newOnes = [];
  for (const ach of achievementDefs) {
    if (state.boughtAchievements.includes(ach.id)) continue;
    if (isAchieved(state, ach)) {
      state.boughtAchievements.push(ach.id);
      newOnes.push(ach);
    }
  }
  return newOnes;
}

function isAchieved(state, ach) {
  const target = bucketTargets[ach.check.cat][ach.check.tier - 1];
  switch (ach.check.cat) {
    case "Momentum": return state.stats.totalMomentumGenerated >= target;
    case "Money": return state.stats.totalMoneyGenerated >= target;
    case "Mindset": return state.currencies.confidence >= target;
    case "Stability": return state.currencies.stability >= target;
    case "Social": return state.currencies.reputation >= target;
    case "Timeline": return state.stats.prestiges >= target;
    case "Cosmic": return state.currencies.realityAnchors >= target;
    case "Secrets": return state.stats.eventsSeen >= target;
    default: return false;
  }
}

export function getEraByMomentum(totalMomentum) {
  let idx = 0;
  for (let i = 0; i < eras.length; i += 1) {
    if (totalMomentum >= eras[i].threshold) idx = i;
  }
  return idx;
}
