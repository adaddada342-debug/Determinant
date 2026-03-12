import { deepCopy, now } from "./utils.js";
import { generators, traits } from "./data.js";

export const SAVE_VERSION = 1;

export function createInitialState() {
  const generatorState = Object.fromEntries(generators.map((g) => [g.id, 0]));
  return {
    version: SAVE_VERSION,
    currencies: {
      momentum: 0,
      money: 25,
      confidence: 0,
      stability: 0,
      reputation: 0,
      temporalShards: 0,
      realityAnchors: 0
    },
    generators: generatorState,
    boughtUpgrades: [],
    boughtAchievements: [],
    timelineTraits: [traits[0].id],
    currentEra: 0,
    combo: 0,
    eventCooldown: 30,
    activeEvent: null,
    buffs: [],
    stats: {
      totalClicks: 0,
      totalMomentumGenerated: 0,
      totalMoneyGenerated: 0,
      totalConfidenceGenerated: 0,
      totalStabilityGenerated: 0,
      totalReputationGenerated: 0,
      totalTemporalShardsGenerated: 0,
      totalRealityAnchorsGenerated: 0,
      eventsSeen: 0,
      prestiges: 0,
      biggestClick: 0,
      totalOfflineMomentum: 0,
      totalGeneratorsBought: 0,
      playTime: 0
    },
    meta: {
      createdAt: now(),
      updatedAt: now(),
      lastSaveAt: now(),
      lastTickAt: now(),
      muted: false,
      selectedTab: "upgrades"
    }
  };
}

export function cloneState(state) {
  return deepCopy(state);
}
