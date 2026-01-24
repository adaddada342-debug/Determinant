-- ReplicatedStorage/DeterminantCombat/Modules/PatternSets.lua
-- Data-driven pattern sets. Add patterns by inserting tables, not writing new code.

local Sets = {}

Sets.Boss_Default = {
	-- How often the boss “throws” a pattern while phase is active
	intervalMin = 1.25,
	intervalMax = 2.15,

	-- Weighted random choice
	patterns = {
		{
			type = "RadialBurst",
			weight = 3,
			bullets = 18,
			speed = 62,
			radius = 1.05,
			life = 3.0,
			telegraph = 0.28,
		},
		{
			type = "AimedVolley",
			weight = 4,
			shots = 6,
			shotGap = 0.08,
			speed = 78,
			spreadDeg = 7,
			radius = 1.0,
			life = 2.8,
			telegraph = 0.18,
		},
		{
			type = "DelayedExplosions",
			weight = 2,
			count = 3,
			radius = 7.5,
			telegraph = 0.95,
			active = 0.18,
		},
		{
			type = "SweepingBeam",
			weight = 2,
			length = 120,
			width = 3.6,
			telegraph = 0.75,
			active = 1.25,
			sweepDeg = 120,
			duration = 1.9,
		},
	},
}

return Sets
