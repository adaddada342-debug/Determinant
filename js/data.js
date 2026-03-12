const currencies = {
  momentum: { name: "Life Momentum", icon: "⚡", tip: "Effort, stubborn optimism, and forward push. Core engine of your climb." },
  money: { name: "Money", icon: "💵", tip: "Cash flow from hustle, business, and scale." },
  confidence: { name: "Confidence", icon: "🧠", tip: "Mental resilience that boosts active and passive growth." },
  stability: { name: "Stability", icon: "🏠", tip: "Reliable routines that prevent collapse and multiply efficiency." },
  reputation: { name: "Reputation", icon: "⭐", tip: "Social proof and trust. Opens influence and media pathways." },
  temporalShards: { name: "Temporal Shards", icon: "🕰️", tip: "Prestige essence from starting a New Timeline." },
  realityAnchors: { name: "Reality Anchors", icon: "🪐", tip: "Late-game constants that stabilize universe-level production." }
};

const eras = [
  { id: "rock-bottom", name: "Rock Bottom", threshold: 0, hint: "One click, one noodle, one tiny win." },
  { id: "self-repair", name: "Self-Repair", threshold: 5e3, hint: "Small habits become actual momentum." },
  { id: "rebuild", name: "Rebuild", threshold: 8e4, hint: "Systems replace chaos." },
  { id: "success", name: "Success", threshold: 9e5, hint: "You stop surviving and start leading." },
  { id: "influence", name: "Influence", threshold: 1.2e7, hint: "People are now listening." },
  { id: "absurd-wealth", name: "Absurd Wealth", threshold: 1.8e8, hint: "You accidentally bought a city block." },
  { id: "reality-manipulation", name: "Reality Manipulation", threshold: 2.2e9, hint: "Math is now a suggestion." },
  { id: "cosmic-authority", name: "Cosmic Authority", threshold: 3e10, hint: "Your board meetings include galaxies." }
];

const generators = [
  { id: "cheap_noodles", name: "Cheap Noodles", desc: "Budget carbs that keep the grind alive.", baseCost: { money: 15 }, produces: { momentum: 0.4 }, unlockAt: 0, tier: 1 },
  { id: "gig_work", name: "Gig Work", desc: "Late-night app jobs and heroic tips.", baseCost: { money: 80 }, produces: { money: 2 }, unlockAt: 60, tier: 1 },
  { id: "energy_drinks", name: "Energy Drinks", desc: "Neon can confidence at 2 AM.", baseCost: { money: 140 }, produces: { confidence: 0.35, momentum: 0.2 }, unlockAt: 120, tier: 1 },
  { id: "pawn_shop_flips", name: "Pawn Shop Flips", desc: "Buy low, fix up, flip with flair.", baseCost: { money: 350 }, produces: { money: 8 }, unlockAt: 300, tier: 1 },

  { id: "therapy_sessions", name: "Therapy Sessions", desc: "Healthier loops > old loops.", baseCost: { money: 1_000, confidence: 30 }, produces: { stability: 0.5, confidence: 0.3 }, unlockAt: 2_000, tier: 2 },
  { id: "gym_routine", name: "Gym Routine", desc: "Discipline with occasional leg-day regret.", baseCost: { money: 1_500, momentum: 600 }, produces: { confidence: 0.8, momentum: 0.6 }, unlockAt: 3_000, tier: 2 },
  { id: "budget_planning", name: "Budget Planning", desc: "Every dollar gets a mission.", baseCost: { money: 2_100, stability: 30 }, produces: { money: 18, stability: 0.2 }, unlockAt: 8_000, tier: 2 },
  { id: "parenting_wins", name: "Parenting Wins", desc: "You showed up. It mattered.", baseCost: { confidence: 120, money: 6_000 }, produces: { reputation: 0.6, stability: 0.7 }, unlockAt: 18_000, tier: 2 },

  { id: "career_growth", name: "Career Growth", desc: "Titles appear where burnout used to live.", baseCost: { money: 20_000, confidence: 250 }, produces: { money: 80, reputation: 0.5 }, unlockAt: 60_000, tier: 3 },
  { id: "small_business", name: "Small Business", desc: "Invoices, espresso, and grit.", baseCost: { money: 45_000, stability: 180 }, produces: { money: 220, momentum: 6 }, unlockAt: 130_000, tier: 3 },
  { id: "investments", name: "Investments", desc: "Your money clocks in while you sleep.", baseCost: { money: 90_000, reputation: 120 }, produces: { money: 380, stability: 3 }, unlockAt: 250_000, tier: 3 },
  { id: "media_presence", name: "Media Presence", desc: "A podcast somehow became a movement.", baseCost: { money: 220_000, reputation: 300 }, produces: { reputation: 7, confidence: 4 }, unlockAt: 600_000, tier: 3 },

  { id: "ai_delegates", name: "AI Delegates", desc: "Bots now handle your calendar and breakfast logistics.", baseCost: { money: 2.2e6, reputation: 1_200 }, produces: { momentum: 120, money: 1500 }, unlockAt: 3e6, tier: 4 },
  { id: "orbital_hq", name: "Orbital HQ", desc: "Your office has weather in it.", baseCost: { money: 1.1e7, stability: 5_000 }, produces: { reputation: 85, confidence: 50 }, unlockAt: 1.2e7, tier: 4 },
  { id: "timeline_editors", name: "Timeline Editors", desc: "Fix yesterday's mistakes at enterprise scale.", baseCost: { temporalShards: 40, money: 2.8e7 }, produces: { temporalShards: 0.35, momentum: 900 }, unlockAt: 4e7, tier: 4 },
  { id: "universe_foundries", name: "Universe Foundries", desc: "Manufacturing realities with dependable uptime.", baseCost: { temporalShards: 300, money: 1e8 }, produces: { realityAnchors: 0.2, money: 6500 }, unlockAt: 2e8, tier: 4 }
];

const categories = ["Click Power", "Hustle", "Recovery", "Finance", "Social", "Automation", "Temporal", "Reality"];

const effectCatalog = {
  clickPower: { stat: "clickPower", perLevel: 0.22 },
  critChance: { stat: "critChance", perLevel: 0.015 },
  critMult: { stat: "critMult", perLevel: 0.12 },
  genGlobal: { stat: "genGlobal", perLevel: 0.07 },
  activeCombo: { stat: "comboGain", perLevel: 0.08 },
  offlineEff: { stat: "offlineEff", perLevel: 0.03 },
  moneyFromMomentum: { stat: "convertMomentumToMoney", perLevel: 0.004 },
  repFromStability: { stat: "convertStabilityToRep", perLevel: 0.0035 },
  eventLuck: { stat: "eventLuck", perLevel: 0.04 },
  shardBoost: { stat: "shardBoost", perLevel: 0.06 },
  anchorBoost: { stat: "anchorBoost", perLevel: 0.1 },
  autoClicks: { stat: "autoClicks", perLevel: 0.6 },
  costReduction: { stat: "costReduction", perLevel: 0.015 }
};

function createUpgrades() {
  const templates = [
    ["Click Power", "Dad Reflexes", "clickPower"],
    ["Click Power", "Coffee Criticality", "critChance"],
    ["Click Power", "Stubborn Combo", "activeCombo"],
    ["Hustle", "Night Shift Discipline", "genGlobal"],
    ["Hustle", "Momentum Arbitrage", "moneyFromMomentum"],
    ["Recovery", "Boundaries First", "offlineEff"],
    ["Recovery", "Routine Compounding", "genGlobal"],
    ["Finance", "Spreadsheet Sorcery", "costReduction"],
    ["Finance", "Dividend Spiral", "genGlobal"],
    ["Social", "Dad Joke Charisma", "eventLuck"],
    ["Social", "Trust Economy", "repFromStability"],
    ["Automation", "Autopilot Morning", "autoClicks"],
    ["Automation", "Ops Dashboard", "genGlobal"],
    ["Temporal", "Shard Condenser", "shardBoost"],
    ["Temporal", "Critical Revision", "critMult"],
    ["Reality", "Anchor Harmonics", "anchorBoost"]
  ];
  const upgrades = [];
  let idCounter = 1;
  for (let level = 1; level <= 4; level += 1) {
    for (const [cat, name, effectKey] of templates) {
      upgrades.push({
        id: `up_${idCounter++}`,
        category: cat,
        name: `${name} ${["I", "II", "III", "IV"][level - 1]}`,
        desc: `Improves ${cat.toLowerCase()} pathways through ${name.toLowerCase()}.`,
        cost: {
          momentum: 100 * level ** 2,
          money: 130 * level ** 2,
          confidence: cat === "Recovery" || cat === "Social" ? 45 * level : 0,
          temporalShards: ["Temporal", "Reality"].includes(cat) ? 8 * level : 0
        },
        unlockAt: 300 * level ** 2,
        effect: { key: effectKey, amount: level }
      });
    }
  }
  return upgrades.slice(0, 64);
}

function createAchievements() {
  const categoriesLocal = ["Momentum", "Money", "Mindset", "Stability", "Social", "Timeline", "Cosmic", "Secrets"];
  const list = [];
  let id = 1;
  for (const cat of categoriesLocal) {
    for (let tier = 1; tier <= 10; tier += 1) {
      list.push({
        id: `ach_${id++}`,
        category: cat,
        name: `${cat} Milestone ${tier}`,
        desc: `Reach a defining ${cat.toLowerCase()} threshold (${tier}).`,
        reward: tier % 2 === 0 ? { stat: "genGlobal", amount: 0.01 * tier } : { stat: "clickPower", amount: 0.015 * tier },
        check: { cat, tier }
      });
    }
  }
  return list;
}

const traits = [
  { id: "hustler", name: "Hustler", desc: "+40% click power, +25% combo scaling.", bonuses: { clickPower: 0.4, comboGain: 0.25 } },
  { id: "stoic", name: "Stoic", desc: "+30% passive production, +20% offline efficiency.", bonuses: { genGlobal: 0.3, offlineEff: 0.2 } },
  { id: "charmer", name: "Charmer", desc: "+40% reputation gains, better positive events.", bonuses: { repGain: 0.4, eventLuck: 0.35 } },
  { id: "visionary", name: "Visionary", desc: "+50% Temporal Shard gain and scaling.", bonuses: { shardBoost: 0.5 } },
  { id: "reality_architect", name: "Reality Architect", desc: "+80% Reality Anchor output, +20% all late-tier generation.", bonuses: { anchorBoost: 0.8, lateTierBoost: 0.2 } }
];

const eventDefs = [
  { id: "e1", type: "minor+", title: "Discount Protein", text: "Gym café mislabeled prices. Destiny says bulk buy.", choices: [{ label: "Stock up", effects: { money: -120, confidence: 35 } }, { label: "Pass politely", effects: { stability: 10 } }] },
  { id: "e2", type: "minor-", title: "Washer Revolt", text: "Laundry machine ate two socks and your patience.", choices: [{ label: "Fix it", effects: { money: -250, stability: 18 } }, { label: "Ignore", effects: { stability: -15, momentum: -40 } }] },
  { id: "e3", type: "swing", title: "Viral Dad Tip", text: "A 30-second budgeting clip exploded online.", choices: [{ label: "Monetize", effects: { reputation: 45, money: 1300 } }, { label: "Stay grounded", effects: { stability: 45, reputation: 18 } }] },
  { id: "e4", type: "minor+", title: "Kind Text", text: "A friend messages: 'Proud of you, man.'", choices: [{ label: "Reply warmly", effects: { confidence: 40, momentum: 60 } }] },
  { id: "e5", type: "minor-", title: "Car Noise", text: "Your car makes a new sound called 'expensive.'", choices: [{ label: "Repair now", effects: { money: -900, stability: 25 } }, { label: "Delay", effects: { money: -200, stability: -35 } }] },
  { id: "e6", type: "swing", title: "Interview Call", text: "A recruiter calls during noodle hour.", choices: [{ label: "Take risk", effects: { confidence: 70, money: 2500 } }, { label: "Not yet", effects: { stability: 35 } }] },
  { id: "e7", type: "chain", title: "Community BBQ", text: "You can host. It might become a network node.", choices: [{ label: "Host it", effects: { money: -700, reputation: 90 }, chain: "bbq_follow" }, { label: "Skip", effects: { stability: 20 } }] },
  { id: "e8", type: "minor+", title: "Coupon Mastery", text: "Stacked coupons achieved impossible grocery math.", choices: [{ label: "Celebrate", effects: { money: 500, confidence: 20 } }] },
  { id: "e9", type: "minor-", title: "Group Chat Drama", text: "Everyone replied-all emotionally.", choices: [{ label: "Mediate", effects: { reputation: 20, confidence: -10 } }, { label: "Mute", effects: { stability: 22, reputation: -12 } }] },
  { id: "e10", type: "swing", title: "Unexpected Bonus", text: "Old contract finally paid out.", choices: [{ label: "Reinvest", effects: { money: 4200, stability: 40 } }, { label: "Treat family", effects: { money: 1800, reputation: 55, confidence: 30 } }] },
  { id: "e11", type: "minor+", title: "New Playlist", text: "Song hits. Productivity spikes.", choices: [{ label: "Loop it", effects: { momentum: 220, confidence: 25 } }] },
  { id: "e12", type: "minor-", title: "Phone Drop", text: "Screen shattered by gravity and irony.", choices: [{ label: "Replace", effects: { money: -1200, stability: 12 } }, { label: "Tape it", effects: { confidence: -20, money: -180 } }] },
  { id: "e13", type: "swing", title: "Mentor Offer", text: "Someone successful offers weekly advice.", choices: [{ label: "Accept", effects: { confidence: 90, reputation: 60 } }, { label: "Decline", effects: { stability: 25 } }] },
  { id: "e14", type: "chain", title: "Podcast Invitation", text: "Local show wants your story.", choices: [{ label: "Go live", effects: { reputation: 120 }, chain: "podcast_follow" }, { label: "No thanks", effects: { confidence: 20 } }] },
  { id: "e15", type: "minor+", title: "Kid's Drawing", text: "You got drawn as a superhero with coffee powers.", choices: [{ label: "Frame it", effects: { confidence: 60, stability: 40 } }] },
  { id: "e16", type: "minor-", title: "Tax Letter", text: "Envelope of mild panic arrives.", choices: [{ label: "Handle it", effects: { money: -1600, stability: 38 } }, { label: "Procrastinate", effects: { stability: -50, momentum: -120 } }] },
  { id: "e17", type: "swing", title: "Small Brand Deal", text: "Your side channel gets sponsorship interest.", choices: [{ label: "Negotiate", effects: { money: 5200, reputation: 85 } }, { label: "Stay independent", effects: { confidence: 70 } }] },
  { id: "e18", type: "minor+", title: "Neighbor Trade", text: "You swap help and save both time and cash.", choices: [{ label: "Great deal", effects: { money: 900, stability: 25 } }] },
  { id: "e19", type: "minor-", title: "Sleep Debt", text: "Three bad nights in a row.", choices: [{ label: "Rest day", effects: { momentum: -220, stability: 35 } }, { label: "Push through", effects: { confidence: -35, money: 400 } }] },
  { id: "e20", type: "swing", title: "Conference Ticket", text: "You win a pass to a high-level summit.", choices: [{ label: "Attend", effects: { reputation: 160, confidence: 60 } }, { label: "Sell ticket", effects: { money: 2600 } }] },
  { id: "e21", type: "cosmic", title: "Temporal Echo", text: "A future version of you sends one tip: 'Buy timeline editors earlier.'", choices: [{ label: "Trust the echo", effects: { temporalShards: 4, momentum: 2000 } }] },
  { id: "e22", type: "cosmic", title: "Glitch in Tuesday", text: "Tuesday repeats. You optimize breakfast execution.", choices: [{ label: "Exploit loop", effects: { stability: 120, money: 3000 } }] },
  { id: "e23", type: "chain", title: "Mayor Calls", text: "Your neighborhood plan is now city policy material.", choices: [{ label: "Lead committee", effects: { reputation: 240, stability: 80 }, chain: "mayor_follow" }, { label: "Recommend others", effects: { reputation: 120, confidence: 90 } }] },
  { id: "e24", type: "cosmic", title: "Pocket Nebula", text: "You discover a tiny nebula in a lunch thermos.", choices: [{ label: "Commercialize", effects: { realityAnchors: 1, money: 12_000 } }, { label: "Donate to science", effects: { realityAnchors: 1, reputation: 300 } }] },
  { id: "e25", type: "cosmic", title: "Universe Franchise", text: "Someone asks about licensing your reality format.", choices: [{ label: "Franchise", effects: { realityAnchors: 2, money: 25_000, reputation: 350 } }] },
  { id: "bbq_follow", type: "chain", title: "BBQ Aftermath", text: "People now ask for your life systems seminar.", choices: [{ label: "Run workshop", effects: { money: 2200, reputation: 70 } }] },
  { id: "podcast_follow", type: "chain", title: "Podcast Boost", text: "Downloads surge and doors open.", choices: [{ label: "Launch own show", effects: { reputation: 140, money: 1600 } }] },
  { id: "mayor_follow", type: "chain", title: "Policy Win", text: "Your practical plan improves thousands of lives.", choices: [{ label: "Scale nationally", effects: { reputation: 500, confidence: 200, temporalShards: 5 } }] }
];

export { currencies, eras, generators, categories, effectCatalog, createUpgrades, createAchievements, traits, eventDefs };
