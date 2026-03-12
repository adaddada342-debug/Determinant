import { createInitialState } from "./state.js";
import { calcShardGain } from "./economy.js";

export function performPrestige(state, effects) {
  const shardGain = calcShardGain(state, effects);
  if (shardGain < 1) return { ok: false, shardGain: 0 };

  const preserved = {
    temporalShards: state.currencies.temporalShards + shardGain,
    realityAnchors: state.currencies.realityAnchors,
    prestiges: state.stats.prestiges + 1,
    boughtAchievements: [...state.boughtAchievements],
    timelineTraits: [...state.timelineTraits],
    totalOfflineMomentum: state.stats.totalOfflineMomentum,
    totalPlayTime: state.stats.playTime
  };

  const fresh = createInitialState();
  fresh.currencies.temporalShards = preserved.temporalShards;
  fresh.currencies.realityAnchors = preserved.realityAnchors;
  fresh.stats.prestiges = preserved.prestiges;
  fresh.boughtAchievements = preserved.boughtAchievements;
  fresh.timelineTraits = preserved.timelineTraits;
  fresh.stats.totalOfflineMomentum = preserved.totalOfflineMomentum;
  fresh.stats.playTime = preserved.totalPlayTime;
  return { ok: true, shardGain, newState: fresh };
}
